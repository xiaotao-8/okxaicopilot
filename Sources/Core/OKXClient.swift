import Foundation

enum OKXError: LocalizedError {
    case api(code: String, message: String)
    case network(Error)
    case badResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .api(let code, let message): return "欧易API错误[\(code)]：\(message)"
        case .network(let err): return "网络错误：\(err.localizedDescription)"
        case .badResponse: return "响应数据解析失败"
        case .notConfigured: return "请先在“设置”中配置欧易 API 密钥"
        }
    }
}

/// OKX V5 REST 客户端（async/await），自动完成鉴权签名
final class OKXClient {
    static let shared = OKXClient()
    private let config: OKXConfig
    private let session: URLSession

    init(config: OKXConfig = .shared) {
        self.config = config
        let conf = URLSessionConfiguration.default
        conf.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: conf)
    }

    // MARK: - 基础请求

    @discardableResult
    func request(
        _ method: String,
        path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        requiresAuth: Bool = true
    ) async throws -> [[String: Any]] {
        var components = URLComponents(string: config.baseURL + path)!
        var items: [URLQueryItem] = []
        for (k, v) in query.sorted(by: { $0.key < $1.key }) where !v.isEmpty {
            items.append(URLQueryItem(name: k, value: v))
        }
        if !items.isEmpty { components.queryItems = items }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyString = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if method == "POST" { urlRequest.httpBody = bodyString.data(using: .utf8) }

        // 请求路径需带原始 query 用于签名
        let signedPath = items.isEmpty ? path : path + "?" + components.percentEncodedQuery

        if requiresAuth {
            guard config.isConfigured else { throw OKXError.notConfigured }
            let ts = String(format: "%.3f", Date().timeIntervalSince1970)
            urlRequest.setValue(config.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
            urlRequest.setValue(config.sign(timestamp: ts, method: method, requestPath: signedPath, body: bodyString),
                                forHTTPHeaderField: "OK-ACCESS-SIGN")
            urlRequest.setValue(ts, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
            urlRequest.setValue(config.passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
            if config.isDemo {
                urlRequest.setValue("1", forHTTPHeaderField: "x-simulated-trading")
            }
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw OKXError.network(error)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OKXError.badResponse
        }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = obj["code"] as? String else {
            throw OKXError.badResponse
        }
        if code != "0" {
            throw OKXError.api(code: code, message: (obj["msg"] as? String) ?? "未知错误")
        }
        return (obj["data"] as? [[String: Any]]) ?? []
    }

    /// 原始 JSON（供 AI 工具等直接使用）
    @discardableResult
    func requestRaw(_ method: String, path: String, query: [String: String] = [:],
                    body: [String: Any]? = nil, requiresAuth: Bool = true) async throws -> [String: Any] {
        var components = URLComponents(string: config.baseURL + path)!
        var items: [URLQueryItem] = []
        for (k, v) in query.sorted(by: { $0.key < $1.key }) where !v.isEmpty {
            items.append(URLQueryItem(name: k, value: v))
        }
        if !items.isEmpty { components.queryItems = items }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyString = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if method == "POST" { urlRequest.httpBody = bodyString.data(using: .utf8) }
        let signedPath = items.isEmpty ? path : path + "?" + components.percentEncodedQuery

        if requiresAuth {
            guard config.isConfigured else { throw OKXError.notConfigured }
            let ts = String(format: "%.3f", Date().timeIntervalSince1970)
            urlRequest.setValue(config.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
            urlRequest.setValue(config.sign(timestamp: ts, method: method, requestPath: signedPath, body: bodyString),
                                forHTTPHeaderField: "OK-ACCESS-SIGN")
            urlRequest.setValue(ts, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
            urlRequest.setValue(config.passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
            if config.isDemo { urlRequest.setValue("1", forHTTPHeaderField: "x-simulated-trading") }
        }

        let (data, _) = try await session.data(for: urlRequest)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OKXError.badResponse
        }
        if let code = obj["code"] as? String, code != "0" {
            throw OKXError.api(code: code, message: (obj["msg"] as? String) ?? "未知错误")
        }
        return obj
    }

    // MARK: - 行情（公开接口，无需鉴权）

    /// 全量行情列表
    func tickers(instType: String = "SPOT") async throws -> [Ticker] {
        try await request("GET", path: "/api/v5/market/tickers", query: ["instType": instType], requiresAuth: false)
            .map(Ticker.init)
    }

    /// 单个交易对行情
    func ticker(instId: String) async throws -> Ticker {
        let list = try await request("GET", path: "/api/v5/market/ticker",
                                     query: ["instId": instId], requiresAuth: false)
        guard let first = list.first else { throw OKXError.badResponse }
        return Ticker(first)
    }

    /// 盘口深度
    func orderBook(instId: String, sz: Int = 50) async throws -> OrderBook {
        let list = try await request("GET", path: "/api/v5/market/books",
                                     query: ["instId": instId, "sz": String(sz)], requiresAuth: false)
        return OrderBook(data: list)
    }

    /// K线（bar 例："1m","5m","15m","1H","4H","1D"）
    func candles(instId: String, bar: String = "15m", limit: Int = 100) async throws -> [Candle] {
        let list = try await request("GET", path: "/api/v5/market/candles",
                                     query: ["instId": instId, "bar": bar, "limit": String(limit)],
                                     requiresAuth: false)
        return list.compactMap { row in (row as [Any]).count >= 5 ? Candle(row) : nil }
    }

    // MARK: - 账户（私有）

    /// 账户总权益 + 币种明细
    func accountBalance() async throws -> AccountSummary {
        let list = try await request("GET", path: "/api/v5/account/balance")
        var summary = AccountSummary()
        if let first = list.first {
            summary.totalEq = first.d("totalEq")
            if let details = first["details"] as? [[String: Any]] {
                summary.details = details.map(AssetBalance.init)
            }
        }
        return summary
    }

    /// 持仓（SWAP/FUTURES/OPTION；传 instType 过滤）
    func positions(instType: String = "SWAP") async throws -> [PositionInfo] {
        try await request("GET", path: "/api/v5/account/positions", query: ["instType": instType])
            .map(PositionInfo.init)
    }

    /// 设置杠杆
    func setLeverage(instId: String, lever: String, mgnMode: String = "cross", posSide: String? = nil) async throws {
        var body: [String: Any] = ["instId": instId, "lever": lever, "mgnMode": mgnMode]
        if let p = posSide { body["posSide"] = p }
        _ = try await request("POST", path: "/api/v5/account/set-leverage", body: body)
    }

    // MARK: - 止盈止损 / 策略委托（私有）

    /// 设置止盈止损：同时传 tp/sl 为 OCO 单，单边为条件单；触发后按市价成交（ordPx=-1）
    @discardableResult
    func placeTPSL(
        instId: String,
        tdMode: String,
        side: String,
        sz: String,
        tpTriggerPx: String? = nil,
        slTriggerPx: String? = nil,
        posSide: String? = nil,
        reduceOnly: Bool = true
    ) async throws -> String {
        var body: [String: Any] = [
            "instId": instId,
            "tdMode": tdMode,
            "side": side,
            "sz": sz,
            "ordType": (tpTriggerPx != nil && slTriggerPx != nil) ? "oco" : "conditional",
            "reduceOnly": reduceOnly ? "true" : "false",
        ]
        if let t = tpTriggerPx { body["tpTriggerPx"] = t; body["tpOrdPx"] = "-1" }
        if let s = slTriggerPx { body["slTriggerPx"] = s; body["slOrdPx"] = "-1" }
        if let p = posSide { body["posSide"] = p }
        let list = try await request("POST", path: "/api/v5/trade/order-algo", body: body)
        return list.first?.s("algoId") ?? ""
    }

    /// 撤销策略委托
    func cancelAlgoOrder(instId: String, algoId: String) async throws {
        _ = try await request("POST", path: "/api/v5/trade/cancel-algos",
                              body: [["instId": instId, "algoId": algoId]])
    }

    /// 当前策略委托（止盈/止损/OCO 单合并返回）
    func pendingAlgoOrders(instType: String = "SWAP") async throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        for ordType in ["conditional", "oco"] {
            let list = try await request("GET", path: "/api/v5/trade/orders-algo-pending",
                                         query: ["instType": instType, "ordType": ordType])
            result.append(contentsOf: list)
        }
        return result
    }

    /// 账户配置（账户等级、持仓模式、UID等）
    func accountConfig() async throws -> [String: Any] {
        let list = try await request("GET", path: "/api/v5/account/config")
        guard let first = list.first else { throw OKXError.badResponse }
        return first
    }

    // MARK: - 交易（私有）

    /// 下单。市价单 px 传 nil；卖出限价单 side="sell"
    @discardableResult
    func placeOrder(
        instId: String,
        tdMode: String = "cash",
        side: String,
        ordType: String = "limit",
        sz: String,
        px: String? = nil,
        posSide: String? = nil,
        reduceOnly: Bool = false
    ) async throws -> String {
        var body: [String: Any] = [
            "instId": instId,
            "tdMode": tdMode,
            "side": side,
            "ordType": ordType,
            "sz": sz,
        ]
        if let p = px, ordType == "limit" { body["px"] = p }
        if let p = posSide { body["posSide"] = p }
        if reduceOnly { body["reduceOnly"] = "true" }
        let list = try await request("POST", path: "/api/v5/trade/order", body: body)
        return list.first?.s("ordId") ?? ""
    }

    /// 撤单
    func cancelOrder(instId: String, ordId: String) async throws {
        _ = try await request("POST", path: "/api/v5/trade/cancel-order",
                              body: ["instId": instId, "ordId": ordId])
    }

    /// 当前挂单
    func pendingOrders(instType: String = "SPOT", instId: String? = nil) async throws -> [OrderInfo] {
        var query = ["instType": instType]
        if let i = instId { query["instId"] = i }
        return try await request("GET", path: "/api/v5/trade/orders-pending", query: query).map(OrderInfo.init)
    }

    /// 历史订单
    func orderHistory(instType: String = "SPOT") async throws -> [OrderInfo] {
        try await request("GET", path: "/api/v5/trade/orders-history-archive", query: ["instType": instType])
            .map(OrderInfo.init)
    }

    /// 成交明细
    func fillsHistory(instType: String = "SPOT") async throws -> [[String: Any]] {
        try await request("GET", path: "/api/v5/trade/fills-history", query: ["instType": instType])
    }

    // MARK: - 跟单（公开带单数据，无需鉴权）

    /// 带单交易员列表
    func leadTraders(instType: String = "SWAP") async throws -> [LeadTrader] {
        try await request("GET", path: "/api/v5/copytrading/public-lead-traders",
                          query: ["instType": instType], requiresAuth: false)
            .map(LeadTrader.init)
    }

    /// 交易员当前带单持仓
    func leadTraderPositions(uniqueCode: String, instType: String = "SWAP") async throws -> [LeadTraderPosition] {
        try await request("GET", path: "/api/v5/copytrading/public-lead-trader-positions",
                          query: ["uniqueCode": uniqueCode, "instType": instType], requiresAuth: false)
            .map(LeadTraderPosition.init)
    }

    /// 交易员收益走势
    func leadTraderTrends(uniqueCode: String, instType: String = "SWAP") async throws -> [[String: Any]] {
        try await request("GET", path: "/api/v5/copytrading/public-lead-trader-trends",
                          query: ["uniqueCode": uniqueCode, "instType": instType], requiresAuth: false)
    }
}
