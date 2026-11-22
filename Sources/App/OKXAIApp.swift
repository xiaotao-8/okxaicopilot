import SwiftUI

@main
struct OKXAIApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { MarketView() }
                .tabItem { Label("行情", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack { TradeView() }
                .tabItem { Label("交易", systemImage: "arrow.left.arrow.right.circle") }

            NavigationStack { CopyTradeView() }
                .tabItem { Label("跟单", systemImage: "person.2.crop.square.stack") }

            NavigationStack { AIChatView() }
                .tabItem { Label("AI助手", systemImage: "sparkles") }

            NavigationStack { ProfileView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(AppTheme.accent)
    }
}

/// “我的”页：委托持仓入口 + 设置入口
struct ProfileView: View {
    @ObservedObject private var config = OKXConfig.shared

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("欧易AI跟单")
                            .font(.headline)
                        Text(config.isDemo ? "当前模式：模拟盘" : "当前模式：实盘")
                            .font(.caption)
                            .foregroundColor(config.isDemo ? .orange : AppTheme.up)
                    }
                    Spacer()
                    Image(systemName: config.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(config.isConfigured ? AppTheme.up : .orange)
                }
            }

            Section("交易") {
                NavigationLink("委托与持仓") { OrdersView() }
            }

            Section("设置") {
                NavigationLink("API 与 AI 配置") { SettingsView() }
            }

            Section("关于") {
                Text("本应用通过欧易(OKX)官方 V5 API 获取真实行情并执行真实交易。加密货币交易风险极高，请务必先在模拟盘验证策略。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("我的")
    }
}
