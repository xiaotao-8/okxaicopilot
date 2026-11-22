import SwiftUI

// MARK: - 设置页（欧易API + 自行接入AI模型Key + 交易环境）

struct SettingsView: View {
    @ObservedObject private var config = OKXConfig.shared

    var body: some View {
        Form {
            Section {
                TextField("API Key", text: $config.apiKey)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Secret Key", text: $config.secretKey)
                    .font(.system(.footnote, design: .monospaced))
                SecureField("Passphrase", text: $config.passphrase)
                    .font(.system(.footnote, design: .monospaced))
                Link(destination: URL(string: "https://www.okx.com/docs-v5/zh/")!) {
                    Label("如何创建欧易API密钥（官方文档）", systemImage: "safari")
                        .font(.footnote)
                }
            } header: {
                Text("欧易 API")
            } footer: {
                Text("密钥仅保存在本机 Keychain，不会上传任何服务器。建议只授予「交易」权限，不开启提币权限。")
            }

            Section {
                Picker("交易环境", selection: $config.isDemo) {
                    Text("模拟盘").tag(true)
                    Text("实盘").tag(false)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("交易环境")
            } footer: {
                Text(config.isDemo
                     ? "模拟盘需先在欧易网页端「模拟交易」中生成模拟盘API密钥，下单不涉及真实资金。"
                     : "⚠️ 实盘模式下所有下单/撤单均为真实委托，请谨慎操作。")
            }

            Section {
                TextField("接口地址（OpenAI兼容）", text: $config.aiBaseURL)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField("模型 API Key", text: $config.aiAPIKey)
                    .font(.system(.footnote, design: .monospaced))
                TextField("模型名称（如 gpt-4o-mini / deepseek-chat）", text: $config.aiModel)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("AI 模型（自行接入）")
            } footer: {
                Text("兼容 OpenAI 接口格式，可填入任意兼容服务的 API Key 与模型名（GPT / DeepSeek / Kimi 等）。AI 可查询行情与持仓，经你确认后执行真实下单。")
            }

            Section("当前状态") {
                HStack {
                    Text("欧易API").foregroundColor(.secondary)
                    Spacer()
                    statusBadge(config.isConfigured ? "已配置" : "未配置", ok: config.isConfigured)
                }
                HStack {
                    Text("交易环境").foregroundColor(.secondary)
                    Spacer()
                    Text(config.isDemo ? "模拟盘" : "实盘")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill((config.isDemo ? Color.orange : AppTheme.up).opacity(0.2)))
                        .foregroundColor(config.isDemo ? .orange : AppTheme.up)
                }
                HStack {
                    Text("AI服务").foregroundColor(.secondary)
                    Spacer()
                    statusBadge(config.aiAPIKey.isEmpty ? "未接入" : "已接入", ok: !config.aiAPIKey.isEmpty)
                }
            }

            Section("风险提示") {
                Text("加密货币交易风险极高，可能损失全部本金。本应用仅为工具，不构成投资建议。所有委托均通过欧易官方 V5 API 提交，请先在模拟盘验证。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置")
    }

    private func statusBadge(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill((ok ? AppTheme.up : Color.orange).opacity(0.2)))
            .foregroundColor(ok ? AppTheme.up : .orange)
    }
}
