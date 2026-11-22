import SwiftUI

// MARK: - 交易页（真实可操作下单，对齐欧易交易界面）

struct TradeView: View {
    @ObservedObject private var config = OKXConfig.shared
    @State private var instType = "SPOT"
    @State private var instId = "BTC-USDT"
    @State private var side = "buy"
    @State private var ordType = "limit"
    @State private var pxText = ""
    @State private var szText = ""
    @State private var leverage = 1.0
    @State private var book = OrderBook()
    @State private var availText = "--"
    @State private var bookWS: OKXWebSocket?
    @State private var submitting = false
    @State private var showConfirm = false
    @State private var resultText: String?
    @State private var errorText: String?

    private let commonPairs = ["BTC-USDT", "ETH-USDT", "SOL-USDT", "XRP-USDT", "DOGE-USDT", "OKB-USDT"]

    private var tdMode: String { instType == "SPOT" ? "cash" : "cross" }

    var body: some View {
        Group {
            if !config.isConfigured {
                placeholder
            } else {
                tradeForm
            }
        }
        .navigationTitle("交易")
        .task { await loadBalance() }
        .onDisappear { bookWS?.disconnect() }
        .alert("确认下单？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认下单", role: .destructive) { Task { await submit() } }
        } message: {
            Text("\(side == "buy" ? "买入" : "卖出") \(instId)\n\(ordType == "market" ? "市价" : "限价 \(pxText)") · 数量 \(szText)\n当前为\(config.isDemo ? "模拟盘" : "实盘")环境，将提交真实委托")
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill").font(.largeTitle).foregroundColor(.orange)
            Text("请先在设置页配置欧易API密钥")
                .foregroundColor(.secondary)
            NavigationLink("前往设置") { SettingsView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tradeForm: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 交易对与环境
                VStack(spacing: 10) {
                    Picker("类型", selection: $instType) {
                        Text("现货").tag("SPOT")
                        Text("永续合约").tag("SWAP")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: instType) { _ in
                        pxText = ""; szText = ""
                        Task { await loadBalance() }
                    }

                    Picker("交易对", selection: $instId) {
                        ForEach(commonPairs, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: instId) { _ in
                        bookWS?.disconnect(); bookWS = nil
                        Task { await startBookWS() }
                    }

                    HStack {
                        TextField("自定义交易对，如 BTC-USDT", text: $instId)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .font(.system(.footnote, design: .monospaced))
                        if config.isDemo {
                            Text("模拟盘").font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                                .foregroundColor(.orange)
                        } else {
                            Text("实盘").font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(AppTheme.up.opacity(0.2)))
                                .foregroundColor(AppTheme.up)
                        }
                    }

                    if instType == "SWAP" {
                        Stepper(value: $leverage, in: 1...20, step: 1) {
                            Text("杠杆 \(Int(leverage))x")
                                .font(.subheadline.weight(.semibold))
                        }
                        .onChange(of: leverage) { newValue in
                            Task {
                                try? await OKXClient.shared.setLeverage(instId: instId,
                                                                       lever: String(Int(newValue)),
                                                                       mgnMode: "cross")
                            }
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                // 盘口
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("盘口").font(.subheadline.weight(.semibold))
                        Spacer()
                        if !book.bids.isEmpty && !book.asks.isEmpty {
                            let mid = (book.bids[0].price + book.asks[0].price) / 2
                            Text("中间价 \(mid.priceText)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    OrderBookView(book: book)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                // 下单表单
                VStack(spacing: 12) {
                    Picker("方向", selection: $side) {
                        Text("买入").tag("buy")
                        Text("卖出").tag("sell")
                    }
                    .pickerStyle(.segmented)

                    Picker("类型", selection: $ordType) {
                        Text("限价").tag("limit")
                        Text("市价").tag("market")
                    }
                    .pickerStyle(.segmented)

                    if ordType == "limit" {
                        fieldRow("委托价格", $pxText, "USDT")
                    }
                    fieldRow("委托数量", $szText, instType == "SPOT" ? "个" : "张")

                    HStack {
                        Text("可用 \(availText)")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { pct in
                            Button("\(Int(pct * 100))%") { applyPercent(pct) }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemBackground)))
                        }
                    }

                    Button {
                        showConfirm = true
                    } label: {
                        HStack {
                            if submitting { ProgressView().tint(.white) }
                            Text(side == "buy" ? "买入 \(instId.replacingOccurrences(of: "-USDT", with: ""))" : "卖出 \(instId.replacingOccurrences(of: "-USDT", with: ""))")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(side == "buy" ? AppTheme.up : AppTheme.down))
                        .foregroundColor(.white)
                    }
                    .disabled(submitting || szText.isEmpty || (ordType == "limit" && pxText.isEmpty))

                    if let resultText {
                        Text(resultText).font(.caption).foregroundColor(AppTheme.up)
                    }
                    if let errorText {
                        Text(errorText).font(.caption).foregroundColor(AppTheme.down)
                    }
                    Text("点击下单即向欧易提交真实委托（\(config.isDemo ? "模拟盘" : "实盘")），请在确认弹窗中核对信息。")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .task { await startBookWS() }
    }

    private func fieldRow(_ label: String, _ binding: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            TextField("0.00", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.subheadline, design: .monospaced))
            Text(unit).font(.caption).foregroundColor(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
    }

    private func applyPercent(_ pct: Double) {
        let px = ordType == "limit" ? (Double(pxText) ?? 0) : (book.asks.first?.price ?? 0)
        guard px > 0, let avail = Double(availText), avail > 0 else { return }
        if side == "buy" && instType == "SPOT" {
            szText = String(format: "%.6f", avail * pct / px)
        } else {
            szText = String(format: "%.4f", avail * pct)
        }
    }

    private func loadBalance() async {
        guard config.isConfigured else { return }
        do {
            let summary = try await OKXClient.shared.accountBalance()
            if instType == "SPOT" {
                availText = summary.details.first { $0.ccy == "USDT" }?.availBal.priceText ?? "0"
            } else {
                availText = summary.details.first { $0.ccy == "USDT" }?.eq.priceText ?? "0"
            }
        } catch {
            availText = "--"
        }
    }

    private func startBookWS() async {
        guard bookWS == nil else { return }
        let socket = OKXWebSocket(isPrivate: false)
        socket.onEvent = { event in
            guard let arg = event["arg"] as? [String: Any],
                  arg["channel"] as? String == "books",
                  let data = event["data"] as? [[String: Any]] else { return }
            let newBook = OrderBook(data: data)
            Task { @MainActor in self.book = newBook }
        }
        socket.connect()
        let id = instId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            socket.subscribe([["channel": "books", "instId": id]])
        }
        bookWS = socket
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            _ = try await TradeService.shared.place(
                instId: instId, tdMode: tdMode, side: side, ordType: ordType,
                sz: szText, px: pxText.isEmpty ? nil : pxText
            )
            resultText = TradeService.shared.lastOrderText
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            resultText = nil
        }
    }
}
