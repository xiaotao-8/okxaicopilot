import WidgetKit
import SwiftUI

// MARK: - 欧易行情桌面小组件（真实数据：直接调用欧易公开行情API）

@main
struct OKXWidgetBundle: WidgetBundle {
    var body: some Widget {
        OKXMarketWidget()
    }
}

// MARK: - 数据模型

struct MarketEntry: TimelineEntry {
    let date: Date
    let tickers: [Ticker]
    let isStale: Bool
}

struct MarketProvider: TimelineProvider {
    /// 小组件默认展示的主流交易对
    static let watchlist = [
        "BTC-USDT", "ETH-USDT", "SOL-USDT", "XRP-USDT",
        "DOGE-USDT", "OKB-USDT", "BNB-USDT", "LTC-USDT",
    ]

    func placeholder(in context: Context) -> MarketEntry {
        MarketEntry(date: Date(), tickers: [], isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MarketEntry) -> Void) {
        fetch { entry in completion(entry ?? MarketEntry(date: Date(), tickers: [], isStale: false)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MarketEntry>) -> Void) {
        fetch { entry in
            // 系统允许的最小刷新间隔约15分钟
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry ?? MarketEntry(date: Date(), tickers: [], isStale: true)],
                                policy: .after(next)))
        }
    }

    private func fetch(completion: @escaping (MarketEntry?) -> Void) {
        let client = OKXClient.shared
        Task {
            do {
                let all = try await client.tickers(instType: "SPOT")
                let picked = Self.watchlist.compactMap { id in all.first { $0.instId == id } }
                completion(MarketEntry(date: Date(), tickers: picked, isStale: false))
            } catch {
                completion(nil)
            }
        }
    }
}

// MARK: - 小组件

struct OKXMarketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OKXMarketWidget", provider: MarketProvider()) { entry in
            MarketWidgetView(entry: entry)
        }
        .configurationDisplayName("欧易行情")
        .description("实时显示欧易主流币种价格与24h涨跌（每15分钟自动刷新）")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MarketWidgetView: View {
    let entry: MarketEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            default: LargeView(entry: entry)
            }
        }
        .containerBackgroundCompat()
    }
}

// MARK: - 小尺寸：BTC 单币焦点

private struct SmallView: View {
    let entry: MarketEntry
    private var btc: Ticker? { entry.tickers.first { $0.instId == "BTC-USDT" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundColor(.white)
                Text("BTC / USDT")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("欧易")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .foregroundColor(.white)
            }
            Spacer()
            if let t = btc {
                Text(t.last.priceText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(t.changeText)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundColor(AppTheme.color(forChange: t.changePct))
            } else {
                Text(entry.isStale ? "数据已过期" : "加载中…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(entry.date, style: .time)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(4)
    }
}

// MARK: - 中尺寸：4币行情列表

private struct MediumView: View {
    let entry: MarketEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("欧易行情")
                    .font(.caption.weight(.bold))
                Text("实时 · OKX V5 API")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 6)

            if entry.tickers.isEmpty {
                Spacer()
                Text(entry.isStale ? "行情数据已过期，等待刷新" : "正在获取欧易行情…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(spacing: 6) {
                    ForEach(entry.tickers.prefix(4)) { t in
                        TickerRow(ticker: t)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(4)
    }
}

// MARK: - 大尺寸：8币完整列表

private struct LargeView: View {
    let entry: MarketEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("欧易行情")
                    .font(.headline)
                Spacer()
                Text("24h涨跌")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            if entry.tickers.isEmpty {
                Spacer()
                Text(entry.isStale ? "行情数据已过期，等待刷新" : "正在获取欧易行情…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(spacing: 7) {
                    ForEach(entry.tickers.prefix(8)) { t in
                        TickerRow(ticker: t)
                    }
                }
                Spacer(minLength: 0)
                Text("数据来源：欧易 OKX · 每15分钟自动刷新")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .padding(4)
    }
}

// MARK: - 单行

private struct TickerRow: View {
    let ticker: Ticker

    var body: some View {
        HStack(spacing: 8) {
            Text(ticker.instId.replacingOccurrences(of: "-USDT", with: ""))
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .frame(width: 52, alignment: .leading)
            Text(ticker.last.priceText)
                .font(.system(.footnote, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(ticker.changeText)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppTheme.color(forChange: ticker.changePct).opacity(0.18))
                )
                .foregroundColor(AppTheme.color(forChange: ticker.changePct))
        }
    }
}

// MARK: - iOS16/17 背景兼容

extension View {
    @ViewBuilder
    func containerBackgroundCompat() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.08),
                                        Color(red: 0.02, green: 0.05, blue: 0.04)],
                               startPoint: .top, endPoint: .bottom)
            }
        } else {
            padding(.all, 12)
                .background(
                    LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.08),
                                            Color(red: 0.02, green: 0.05, blue: 0.04)],
                                   startPoint: .top, endPoint: .bottom)
                )
        }
    }
}
