import SwiftUI

// MARK: - 行情页

struct MarketView: View {
    @StateObject private var vm = MarketViewModel()
    @State private var searchText = ""

    private var filtered: [Ticker] {
        searchText.isEmpty ? vm.tickers : vm.tickers.filter { $0.instId.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                ForEach(filtered) { t in
                    NavigationLink {
                        MarketDetailView(instId: t.instId)
                    } label: {
                        TickerRowView(ticker: t)
                    }
                    .listRowBackground(Color(.secondarySystemBackground))
                }
            } header: {
                Text("现货实时行情 · 欧易 OKX V5 API")
                    .textCase(nil)
            } footer: {
                Text("共 \(filtered.count) 个交易对 · WebSocket 实时推送")
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("行情")
        .searchable(text: $searchText, prompt: "搜索交易对，如 BTC-USDT")
        .refreshable { await vm.reload() }
        .task { await vm.start() }
        .onDisappear { vm.stop() }
    }
}

@MainActor
final class MarketViewModel: ObservableObject {
    @Published var tickers: [Ticker] = []
    private var ws: OKXWebSocket?

    func start() async {
        await reload()
        guard ws == nil else { return }
        let socket = OKXWebSocket(isPrivate: false)
        socket.onEvent = { [weak self] event in
            guard let arg = event["arg"] as? [String: Any],
                  arg["channel"] as? String == "tickers",
              let data = event["data"] as? [[String: Any]] else { return }
            Task { @MainActor in
                guard let self else { return }
                for d in data {
                    if let idx = self.tickers.firstIndex(where: { $0.instId == (d["instId"] as? String ?? "") }) {
                        self.tickers[idx] = self.tickers[idx].updating(with: d)
                    }
                }
            }
        }
        socket.connect()
        ws = socket
        resubscribe()
    }

    func reload() async {
        do {
            let list = try await OKXClient.shared.tickers(instType: "SPOT")
            tickers = list.sorted { $0.volCcy24h > $1.volCcy24h }
            resubscribe()
        } catch {
            tickers = []
        }
    }

    func stop() {
        ws?.disconnect()
        ws = nil
    }

    private func resubscribe() {
        guard let ws else { return }
        let args = tickers.prefix(30).map { ["channel": "tickers", "instId": $0.instId] as [String: Any] }
        guard !args.isEmpty else { return }
        ws.subscribe(args)
    }
}

// MARK: - 行情行

struct TickerRowView: View {
    let ticker: Ticker

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(ticker.instId)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("24h量 \(ticker.volCcy24h.cnMagnitudeText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ticker.last.priceText)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(AppTheme.color(forChange: ticker.changePct))
                Text("高 \(ticker.high24h.priceText)  低 \(ticker.low24h.priceText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(ticker.changeText)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.color(forChange: ticker.changePct).opacity(0.18)))
                .foregroundColor(AppTheme.color(forChange: ticker.changePct))
                .frame(width: 84)
        }
    }
}

// MARK: - K线详情页（K线下方内置止盈止损设置，对齐欧易）

struct MarketDetailView: View {
    let instId: String
    @State private var bar = "15m"
    @State private var candles: [Candle] = []
    @State private var book = OrderBook()
    @State private var ticker: Ticker?
    @State private var bookWS: OKXWebSocket?
    @State private var loading = true
    @ObservedObject private var config = OKXConfig.shared

    private let bars = ["1m", "5m", "15m", "1H", "4H", "1D"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard
                chartCard
                TPSLCard(instId: instId, lastPrice: ticker?.last ?? 0)
                orderBookCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .navigationTitle(instId)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { bookWS?.disconnect() }
    }

    private func load() async {
        loading = true
        async let t: () = loadTicker()
        async let c: () = loadCandles()
        async let b: () = loadBook()
        _ = await (t, c, b)
        loading = false
        startBookWS()
    }

    private func loadTicker() async {
        ticker = try? await OKXClient.shared.ticker(instId: instId)
    }

    private func loadCandles() async {
        candles = (try? await OKXClient.shared.candles(instId: instId, bar: bar, limit: 80)) ?? []
    }

    private func loadBook() async {
        book = (try? await OKXClient.shared.orderBook(instId: instId, sz: 20)) ?? OrderBook()
    }

    private func startBookWS() {
        let socket = OKXWebSocket(isPrivate: false)
        socket.onEvent = { event in
            guard let arg = event["arg"] as? [String: Any],
                  let channel = arg["channel"] as? String, channel == "books",
                  let data = event["data"] as? [[String: Any]] else { return }
            let newBook = OrderBook(data: data)
            Task { @MainActor in
                self.book = newBook
            }
        }
        socket.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            socket.subscribe([["channel": "books", "instId": instId]])
        }
        bookWS = socket
    }

    // MARK: 子视图

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = ticker {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.last.priceText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.color(forChange: t.changePct))
                    Text(t.changeText)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(AppTheme.color(forChange: t.changePct))
                }
                HStack(spacing: 14) {
                    stat("24h最高", t.high24h.priceText)
                    stat("24h最低", t.low24h.priceText)
                    stat("24h量", t.volCcy24h.cnMagnitudeText)
                }
                .font(.caption)
            } else {
                Text("加载行情中…").font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).foregroundColor(.secondary)
            Text(v).foregroundColor(.primary)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("周期", selection: $bar) {
                ForEach(bars, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: bar) { _ in Task { await loadCandles() } }

            if candles.isEmpty {
                Text("K线加载中…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                CandleChartView(candles: candles)
                    .frame(height: 220)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private var orderBookCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("盘口深度").font(.subheadline.weight(.semibold))
            OrderBookView(book: book)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - K线图（Canvas 自绘）

struct CandleChartView: View {
    let candles: [Candle]

    var body: some View {
        Canvas { ctx, size in
            let data = candles.suffix(60)
            guard !data.isEmpty else { return }
            let hi = data.map(\.high).max() ?? 1
            let lo = data.map(\.low).min() ?? 0
            let range = max(hi - lo, 0.0000001)
            let w = size.width / CGFloat(data.count)
            let chartH = size.height - 18

            // 网格与价格刻度
            for i in 0...4 {
                let y = chartH * CGFloat(i) / 4
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                let price = hi - range * Double(i) / 4
                ctx.draw(Text(price.priceText).font(.system(size: 8)).foregroundColor(.secondary),
                         at: CGPoint(x: 30, y: y + 4), anchor: .leading)
            }

            for (i, c) in data.enumerated() {
                let x = CGFloat(i) * w + w / 2
                func y(_ p: Double) -> CGFloat { chartH * CGFloat(1 - (p - lo) / range) }
                let up = c.close >= c.open
                let color = up ? AppTheme.up : AppTheme.down

                // 影线
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(c.high)))
                wick.addLine(to: CGPoint(x: x, y: y(c.low)))
                ctx.stroke(wick, with: .color(color), lineWidth: 1)

                // 实体
                let bodyTop = y(max(c.open, c.close))
                let bodyH = max(abs(y(c.open) - y(c.close)), 1)
                let bodyW = max(w * 0.6, 1)
                let rect = CGRect(x: x - bodyW / 2, y: bodyTop, width: bodyW, height: bodyH)
                ctx.fill(Path(rect), with: .color(color))
            }
        }
    }
}

// MARK: - 盘口

struct OrderBookView: View {
    let book: OrderBook

    private var maxSz: Double {
        max((book.bids.prefix(10).map(\.size).max() ?? 1),
            (book.asks.prefix(10).map(\.size).max() ?? 1))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            bookSide(levels: Array(book.bids.prefix(10)).reversed(), isBid: true, title: "买盘 Bids")
            bookSide(levels: Array(book.asks.prefix(10)), isBid: false, title: "卖盘 Asks")
        }
    }

    private func bookSide(levels: [BookLevel], isBid: Bool, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            ForEach(Array(levels.enumerated()), id: \.offset) { _, lv in
                Text(lv.price.priceText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isBid ? AppTheme.up : AppTheme.down)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: isBid ? .leading : .trailing)
                    .background(
                        GeometryReader { geo in
                            HStack {
                                if isBid { Spacer() }
                                Rectangle()
                                    .fill((isBid ? AppTheme.up : AppTheme.down).opacity(0.12))
                                    .frame(width: geo.size.width * lv.size / maxSz)
                                if !isBid { Spacer() }
                            }
                        }
                    )
            }
        }
    }
}

// MARK: - 止盈止损设置（K线下方，样式对齐欧易策略委托）

struct TPSLCard: View {
    let instId: String
    let lastPrice: Double

    @ObservedObject private var config = OKXConfig.shared
    @State private var side = "sell"
    @State private var szText = "1"
    @State private var tpText = ""
    @State private var slText = ""
    @State private var submitting = false
    @State private var resultText: String?
    @State private var errorText: String?
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("止盈止损").font(.subheadline.weight(.semibold))
                Spacer()
                Text(config.isDemo ? "模拟盘" : "实盘")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill((config.isDemo ? Color.orange : AppTheme.up).opacity(0.2)))
                    .foregroundColor(config.isDemo ? .orange : AppTheme.up)
            }

            if !config.isConfigured {
                Text("配置欧易API密钥后可在此设置策略委托（触发后市价成交）")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Picker("方向", selection: $side) {
                    Text("买入").tag("buy")
                    Text("卖出").tag("sell")
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    tpslField("数量", $szText, "个/张")
                    tpslField("止盈触发价", $tpText, "选填")
                    tpslField("止损触发价", $slText, "选填")
                }

                HStack {
                    if lastPrice != 0 {
                        Text("参考现价 \(lastPrice.priceText)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        showConfirm = true
                    } label: {
                        if submitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("设置止盈止损")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .disabled(submitting || (tpText.isEmpty && slText.isEmpty) || szText.isEmpty)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.accent))
                    .foregroundColor(.white)
                }

                if let resultText {
                    Text(resultText).font(.caption).foregroundColor(AppTheme.up)
                }
                if let errorText {
                    Text(errorText).font(.caption).foregroundColor(AppTheme.down)
                }
                Text("止盈止损为真实策略委托（OCO/条件单），触发后按市价平仓，请谨慎设置。")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .alert("确认设置止盈止损？", isPresented: $showConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认", role: .destructive) { Task { await submit() } }
        } message: {
            Text("\(instId) \(side == "buy" ? "买入" : "卖出") 数量\(szText) · 止盈\(tpText.isEmpty ? "无" : tpText) · 止损\(slText.isEmpty ? "无" : slText)\n当前为\(config.isDemo ? "模拟盘" : "实盘")环境")
        }
    }

    private func tpslField(_ label: String, _ binding: Binding<String>, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            TextField(hint, text: binding)
                .keyboardType(.decimalPad)
                .font(.system(.footnote, design: .monospaced))
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemBackground)))
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            let algoId = try await TradeService.shared.placeTPSL(
                instId: instId,
                tdMode: "cross",
                side: side,
                sz: szText,
                tp: tpText.isEmpty ? nil : tpText,
                sl: slText.isEmpty ? nil : slText
            )
            resultText = "策略委托已提交 · 策略号 \(algoId)"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            resultText = nil
        }
    }
}
