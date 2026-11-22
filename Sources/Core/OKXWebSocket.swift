import Foundation

/// OKX V5 WebSocket（公共/私有频道），自动心跳与重连
final class OKXWebSocket: NSObject, URLSessionWebSocketDelegate {
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession!
    private let url: URL
    private let config: OKXConfig
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private var pendingSubs: [[String: Any]] = []
    private var isAuthenticated = false
    private var manualClose = false

    /// 收到服务端事件（含 event/ack/data）
    var onEvent: (([String: Any]) -> Void)?
    var onConnected: (() -> Void)?

    init(isPrivate: Bool, config: OKXConfig = .shared) {
        self.config = config
        self.url = URL(string: isPrivate ? OKXConfig.wsPrivateURL : OKXConfig.wsPublicURL)!
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect() {
        manualClose = false
        let task = session.webSocketTask(with: url)
        task.resume()
        socket = task
        receiveLoop()

        if url.absoluteString.contains("private") {
            login { [weak self] in
                self?.resubscribe()
                self?.onConnected?()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.resubscribe()
                self?.onConnected?()
            }
        }
        startPing()
    }

    func disconnect() {
        manualClose = true
        pingTimer?.invalidate()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    /// 订阅频道，例：[["channel": "tickers", "instId": "BTC-USDT"]]
    func subscribe(_ args: [[String: Any]]) {
        pendingSubs.append(contentsOf: args)
        send(["op": "subscribe", "args": args])
    }

    func unsubscribe(_ args: [[String: Any]]) {
        pendingSubs.removeAll { sub in
            args.contains { $0["channel"] as? String == sub["channel"] as? String
                && $0["instId"] as? String == sub["instId"] as? String }
        }
        send(["op": "unsubscribe", "args": args])
    }

    // MARK: - Private

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { error in
            if error != nil { /* 重连后 resubscribe 会补发 */ }
        }
    }

    private func login(completion: @escaping () -> Void) {
        guard config.isConfigured else { return }
        let ts = String(Int(Date().timeIntervalSince1970))
        let sign = config.sign(timestamp: ts, method: "GET", requestPath: "/users/self/verify", body: "")
        let auth: [String: Any] = [
            "op": "login",
            "args": [[
                "apiKey": config.apiKey,
                "passphrase": config.passphrase,
                "timestamp": ts,
                "sign": sign,
            ]],
        ]
        // 登录成功事件在 receiveLoop 中判定
        loginCompletion = completion
        send(auth)
    }

    private var loginCompletion: (() -> Void)?

    private func resubscribe() {
        guard !pendingSubs.isEmpty else { return }
        send(["op": "subscribe", "args": pendingSubs])
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.socket?.sendPing { _ in }
        }
    }

    private func receiveLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.handleDisconnect()
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let event = obj["event"] as? String
                    if event == "login" {
                        self.isAuthenticated = true
                        self.loginCompletion?()
                        self.loginCompletion = nil
                    } else if event == "error" {
                        // 登录/订阅失败等
                    }
                    self.onEvent?(obj)
                }
                self.receiveLoop()
            }
        }
    }

    private func handleDisconnect() {
        guard !manualClose else { return }
        pingTimer?.invalidate()
        reconnectAttempts = min(reconnectAttempts + 1, 6)
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(reconnectAttempts) * 2) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        reconnectAttempts = 0
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleDisconnect()
    }
}
