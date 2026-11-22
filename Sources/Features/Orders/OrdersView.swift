import SwiftUI

// MARK: - 委托与持仓页（持仓/当前委托/策略委托/历史订单/账户信息）

struct OrdersView: View {
    @ObservedObject private var config = OKXConfig.shared
    @State private var tab = 0
    @State private var instType = "SPOT"

    var body: some View {
        Group {
            if !config.isConfigured {
                VStack(spacing: 12) {
                    Image(systemName: "key.fill").font(.largeTitle).foregroundColor(.orange)
                    Text("配置密钥后查看委托与持仓").foregroundColor(.secondary)
                    NavigationLink("前往设置") { SettingsView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    Picker("页签", selection: $tab) {
                        Text("持仓").tag(0)
                        Text("当前委托").tag(1)
                        Text("策略委托").tag(2)
                        Text("历史").tag(3)
                        Text("账户").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                    if tab == 0 {
                        PositionsTab()
                    } else if tab == 1 {
                        PendingOrdersTab()
                    } else if tab == 2 {
                        AlgoOrdersTab()
                    } else if tab == 3 {
                        HistoryTab()
                    } else {
                        AccountInfoTab()
                    }
                }
            }
        }
        .navigationTitle("委托与持仓")
    }
}

// MARK: - 持仓（含跟单来源标签 + 止盈止损 + 平仓）

private struct PositionsTab: View {
    @State private var positions: [PositionInfo] = []
    @State private var errorText: String?
    @State private var tpSlTarget: PositionInfo?
    @State private var closeTarget: PositionInfo?
    @State private var resultText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).font(.caption).foregroundColor(AppTheme.down).listRowBackground(Color.clear)
            }
            ForEach(positions) { p in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(p.directionLabel)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill((p.directionLabel == "多" ? AppTheme.up : AppTheme.down).opacity(0.2)))
                            .foregroundColor(p.directionLabel == "多" ? AppTheme.up : AppTheme.down)
                        Text(p.instId).font(.subheadline.weight(.semibold))
                        if p.lever > 0 {
                            Text("\(Int(p.lever))x").font(.caption2).foregroundColor(.orange)
                        }
                        if p.isCopyTrade {
                            Text("跟单").font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.accent.opacity(0.2)))
                                .foregroundColor(AppTheme.accent)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(p.upl.priceText)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundColor(AppTheme.color(forChange: p.upl))
                            Text(String(format: "%.2f%%", p.uplRatio))
                                .font(.caption2)
                                .foregroundColor(AppTheme.color(forChange: p.upl))
                        }
                    }
                    HStack(spacing: 12) {
                        Text("数量 \(abs(p.pos).priceText)").font(.caption2).foregroundColor(.secondary)
                        Text("均价 \(p.avgPx.priceText)").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Button("止盈止损") { tpSlTarget = p }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.accent.opacity(0.15)))
                            .foregroundColor(AppTheme.accent)
                        Button("市价平仓") { closeTarget = p }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.down.opacity(0.15)))
                            .foregroundColor(AppTheme.down)
                    }
                    if let resultText {
                        Text(resultText).font(.caption2).foregroundColor(AppTheme.up)
                    }
                }
                .padding(.vertical, 3)
            }
            if positions.isEmpty {
                Text("暂无持仓").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $tpSlTarget) { p in
            NavigationStack {
                ScrollView {
                    TPSLCard(instId: p.instId, lastPrice: p.avgPx)
                        .padding(12)
                }
                .navigationTitle("止盈止损 · \(p.instId)")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .confirmationDialog("确认市价平仓 \(closeTarget?.instId ?? "")？（真实委托）",
                            isPresented: Binding(get: { closeTarget != nil },
                                                 set: { if !$0 { closeTarget = nil } }),
                            titleVisibility: .visible) {
            Button("确认平仓", role: .destructive) { Task { await close() } }
            Button("取消", role: .cancel) { closeTarget = nil }
        }
    }

    private func load() async {
        do {
            positions = try await OKXClient.shared.positions(instType: "ANY").filter { abs($0.pos) > 0 }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func close() async {
        guard let p = closeTarget else { return }
        closeTarget = nil
        do {
            let opposite = p.posSide == "net" ? (p.pos >= 0 ? "sell" : "buy") : (p.posSide == "long" ? "sell" : "buy")
            _ = try await TradeService.shared.place(
                instId: p.instId, tdMode: p.mgnMode.isEmpty ? "cross" : p.mgnMode,
                side: opposite, ordType: "market",
                sz: String(format: "%.8f", abs(p.pos)),
                px: nil, posSide: p.posSide == "net" ? nil : p.posSide, reduceOnly: true
            )
            resultText = "平仓委托已提交"
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 当前委托

private struct PendingOrdersTab: View {
    @State private var orders: [OrderInfo] = []
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).font(.caption).foregroundColor(AppTheme.down).listRowBackground(Color.clear)
            }
            ForEach(orders) { o in
                OrderRow(order: o)
                    .swipeActions(edge: .trailing) {
                        Button("撤单", role: .destructive) { Task { await cancel(o) } }
                    }
            }
            if orders.isEmpty {
                Text("暂无当前委托").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            var list = try await OKXClient.shared.pendingOrders(instType: "SPOT")
            list.append(contentsOf: (try? await OKXClient.shared.pendingOrders(instType: "SWAP")) ?? [])
            orders = list
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func cancel(_ o: OrderInfo) async {
        do {
            try await OKXClient.shared.cancelOrder(instId: o.instId, ordId: o.ordId)
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct OrderRow: View {
    let order: OrderInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(order.sideLabel)
                    .font(.caption.weight(.bold))
                    .foregroundColor(order.side == "buy" ? AppTheme.up : AppTheme.down)
                Text("\(order.instId) · \(order.typeLabel)").font(.subheadline.weight(.semibold))
                Spacer()
                Text(order.stateLabel).font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                if order.px > 0 { Text("价 \(order.px.priceText)").font(.caption2).foregroundColor(.secondary) }
                Text("量 \(order.sz.priceText)").font(.caption2).foregroundColor(.secondary)
                Text("成交 \(order.accFillSz.priceText)").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text(order.timeLabel).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 策略委托（止盈止损单）

private struct AlgoOrdersTab: View {
    @State private var algos: [AlgoOrderInfo] = []
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).font(.caption).foregroundColor(AppTheme.down).listRowBackground(Color.clear)
            }
            ForEach(algos) { a in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(a.typeLabel).font(.caption.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.accent.opacity(0.15)))
                            .foregroundColor(AppTheme.accent)
                        Text("\(a.instId) · \(a.sideLabel)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("量 \(a.sz.priceText)").font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 12) {
                        if a.tpTriggerPx > 0 { Text("止盈 \(a.tpTriggerPx.priceText)").font(.caption2).foregroundColor(AppTheme.up) }
                        if a.slTriggerPx > 0 { Text("止损 \(a.slTriggerPx.priceText)").font(.caption2).foregroundColor(AppTheme.down) }
                        Spacer()
                        Text("策略号 \(a.algoId)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("撤销", role: .destructive) { Task { await cancel(a) } }
                }
            }
            if algos.isEmpty {
                Text("暂无策略委托（可在行情K线图下方设置止盈止损）")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let rows = try await OKXClient.shared.pendingAlgoOrders(instType: "ANY")
            algos = rows.map(AlgoOrderInfo.init).sorted { $0.cTime > $1.cTime }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func cancel(_ a: AlgoOrderInfo) async {
        do {
            try await OKXClient.shared.cancelAlgoOrder(instId: a.instId, algoId: a.algoId)
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 历史订单

private struct HistoryTab: View {
    @State private var orders: [OrderInfo] = []
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).font(.caption).foregroundColor(AppTheme.down).listRowBackground(Color.clear)
            }
            ForEach(orders) { OrderRow(order: $0) }
            if orders.isEmpty {
                Text("暂无历史订单").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            var list = try await OKXClient.shared.orderHistory(instType: "SPOT")
            list.append(contentsOf: (try? await OKXClient.shared.orderHistory(instType: "SWAP")) ?? [])
            orders = list.sorted { $0.cTime > $1.cTime }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 账户信息

private struct AccountInfoTab: View {
    @ObservedObject private var config = OKXConfig.shared
    @State private var summary = AccountSummary()
    @State private var configDict: [String: Any] = [:]
    @State private var errorText: String?

    private var acctLvLabel: String {
        switch configDict.s("acctLv") {
        case "1": return "简单交易模式"
        case "2": return "现货和合约模式"
        case "3": return "跨币种保证金模式"
        case "4": return "组合保证金模式"
        default: return "--"
        }
    }

    var body: some View {
        List {
            if let errorText {
                Text(errorText).font(.caption).foregroundColor(AppTheme.down).listRowBackground(Color.clear)
            }
            Section("账户概况") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("总权益（USD）").font(.caption).foregroundColor(.secondary)
                        Text(summary.totalEq.priceText)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                    }
                    Spacer()
                    Text(config.isDemo ? "模拟盘" : "实盘")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill((config.isDemo ? Color.orange : AppTheme.up).opacity(0.2)))
                        .foregroundColor(config.isDemo ? .orange : AppTheme.up)
                }
                LabeledRow("账户模式", acctLvLabel)
                if !configDict.s("uid").isEmpty {
                    LabeledRow("UID", configDict.s("uid"))
                }
            }
            Section("币种明细") {
                ForEach(summary.details.filter { $0.eq != 0 }) { a in
                    HStack {
                        Text(a.ccy).font(.subheadline.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("权益 \(a.eq.priceText)").font(.caption)
                            Text("可用 \(a.availBal.priceText)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                if summary.details.isEmpty {
                    Text("暂无资产数据").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            summary = try await OKXClient.shared.accountBalance()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        configDict = (try? await OKXClient.shared.accountConfig()) ?? [:]
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline)
        }
    }
}
