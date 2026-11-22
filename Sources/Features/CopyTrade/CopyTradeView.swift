import SwiftUI

// MARK: - 跟单页（欧易公开带单大厅 + 一键跟卖）

struct CopyTradeView: View {
    @State private var traders: [LeadTrader] = []
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        List {
            Section {
                if let errorText {
                    Text(errorText).font(.caption).foregroundColor(AppTheme.down)
                }
                ForEach(traders) { t in
                    NavigationLink {
                        TraderDetailView(trader: t)
                    } label: {
                        TraderRow(trader: t)
                    }
                    .listRowBackground(Color(.secondarySystemBackground))
                }
                if traders.isEmpty && !loading {
                    Text("暂无带单数据").font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Text("带单大厅 · 实时收益排行").textCase(nil)
            } footer: {
                Text("公开带单数据仅供参考；本应用通过自有账户查看交易员持仓后手动跟单执行（下单为真实委托）。")
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("跟单")
        .refreshable { await load() }
        .task { await load() }
        .overlay {
            if loading { ProgressView() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            traders = try await OKXClient.shared.leadTraders(instType: "SWAP")
                .sorted { $0.pnlRatio > $1.pnlRatio }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct TraderRow: View {
    let trader: LeadTrader

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(trader.nickName.isEmpty ? "交易员 \(trader.uniqueCode.prefix(6))" : trader.nickName)
                    .font(.subheadline.weight(.semibold))
                Text("跟单 \(Int(trader.followers)) 人 · 规模 \(trader.aum.cnMagnitudeText)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%+.2f%%", trader.pnlRatio))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(AppTheme.color(forChange: trader.pnlRatio))
                Text("收益率").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 交易员详情（收益走势 + 当前带单持仓 + 一键跟卖）

struct TraderDetailView: View {
    let trader: LeadTrader
    @State private var trends: [[String: Any]] = []
    @State private var positions: [LeadTraderPosition] = []
    @State private var errorText: String?
    @ObservedObject private var config = OKXConfig.shared

    var body: some View {
        List {
            Section("收益走势") {
                TrendChartView(trends: trends)
                    .frame(height: 140)
                    .listRowBackground(Color.clear)
            }
            Section {
                if let errorText {
                    Text(errorText).font(.caption).foregroundColor(AppTheme.down)
                }
                ForEach(positions) { p in
                    TraderPositionRow(position: p, configured: config.isConfigured)
                }
                if positions.isEmpty {
                    Text("该交易员当前无带单持仓").font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Text("当前带单持仓（永续）").textCase(nil)
            } footer: {
                Text("「跟卖」将以你自己的账户，按交易员持仓的反方向提交真实市价委托。").textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trader.nickName.isEmpty ? "交易员详情" : trader.nickName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        async let t: () = loadTrends()
        async let p: () = loadPositions()
        _ = await (t, p)
    }

    private func loadTrends() async {
        trends = (try? await OKXClient.shared.leadTraderTrends(uniqueCode: trader.uniqueCode)) ?? []
    }

    private func loadPositions() async {
        do {
            positions = try await OKXClient.shared.leadTraderPositions(uniqueCode: trader.uniqueCode)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct TraderPositionRow: View {
    let position: LeadTraderPosition
    let configured: Bool

    @State private var showFollow = false
    @State private var szText = ""
    @State private var submitting = false
    @State private var resultText: String?
    @State private var errorText: String?

    private var followSide: String { position.posSide == "long" ? "sell" : "buy" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(position.posSide == "long" ? "多" : "空")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill((position.posSide == "long" ? AppTheme.up : AppTheme.down).opacity(0.2)))
                    .foregroundColor(position.posSide == "long" ? AppTheme.up : AppTheme.down)
                Text(position.instId).font(.subheadline.weight(.semibold))
                if position.lever > 0 {
                    Text("\(Int(position.lever))x").font(.caption2).foregroundColor(.orange)
                }
                Spacer()
                Text("持仓 \(abs(position.pos).priceText)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Text("开仓均价 \(position.openAvgPx != 0 ? position.openAvgPx.priceText : position.posAvgPx.priceText)")
                .font(.caption2).foregroundColor(.secondary)

            HStack {
                if let resultText { Text(resultText).font(.caption2).foregroundColor(AppTheme.up) }
                if let errorText { Text(errorText).font(.caption2).foregroundColor(AppTheme.down) }
                Spacer()
                Button {
                    szText = String(format: "%.0f", abs(position.pos))
                    showFollow = true
                } label: {
                    Text("一键跟卖")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.accent))
                        .foregroundColor(.white)
                }
                .disabled(!configured || submitting)
            }
        }
        .padding(.vertical, 2)
        .alert("跟卖确认（真实委托）", isPresented: $showFollow) {
            TextField("数量（张）", text: $szText)
                .keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("确认跟卖", role: .destructive) { Task { await followClose() } }
        } message: {
            Text("将以你的账户对 \(position.instId) 提交\(followSide == "sell" ? "卖出" : "买入")市价单（反方向跟单）。请核对数量。")
        }
    }

    private func followClose() async {
        submitting = true
        defer { submitting = false }
        do {
            let ordId = try await TradeService.shared.place(
                instId: position.instId, tdMode: "cross", side: followSide,
                ordType: "market", sz: szText, px: nil
            )
            resultText = "跟卖委托已提交 · \(ordId)"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            resultText = nil
        }
    }
}

// MARK: - 收益走势折线（Canvas 自绘）

private struct TrendChartView: View {
    let trends: [[String: Any]]

    private var points: [Double] {
        // 兼容 [ts, equity, pnlRatio, ...] 或 [ts, pnlRatio]
        let rows = (trends.first?["trends"] as? [[Any]]) ?? []
        return rows.compactMap { row -> Double? in
            guard row.count >= 3 else { return nil }
            let v = (row[2] as? String).flatMap(Double.init) ?? ((row[2] as? NSNumber)?.doubleValue ?? 0)
            return v * 100
        }
    }

    var body: some View {
        if points.count < 2 {
            Text("走势数据加载中或暂无数据").font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Canvas { ctx, size in
                let hi = max(points.max() ?? 1, 0.001)
                let lo = min(points.min() ?? 0, 0)
                let range = max(hi - lo, 0.0001)
                let stepX = size.width / CGFloat(points.count - 1)
                var path = Path()
                for (i, v) in points.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height * CGFloat(1 - (v - lo) / range)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(AppTheme.accent), lineWidth: 2)
                // 填充渐变
                var fill = path
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(AppTheme.accent.opacity(0.12)))

                let pct = points.last ?? 0
                let label = Text(String(format: "%+.2f%%", pct))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(pct >= 0 ? AppTheme.up : AppTheme.down)
                ctx.draw(label, at: CGPoint(x: size.width - 24, y: 8))
            }
        }
    }
}
