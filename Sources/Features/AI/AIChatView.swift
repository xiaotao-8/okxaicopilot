import SwiftUI

// MARK: - AI 助手对话页（接入用户自配的模型 Key，可查行情/持仓并执行真实下单）

struct AIChatView: View {
    @State private var messages: [(role: String, content: String)] = []
    @State private var bubbles: [ChatBubble] = []
    @State private var inputText = ""
    @State private var pending = false
    @FocusState private var inputFocused: Bool
    @ObservedObject private var config = OKXConfig.shared

    private let quickPrompts = ["现在BTC什么行情？", "帮我看看我的持仓", "分析一下ETH走势", "帮我市价买入0.001个BTC"]

    var body: some View {
        Group {
            if config.aiAPIKey.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundColor(AppTheme.accent)
                    Text("请先在设置页配置AI模型API Key")
                        .foregroundColor(.secondary)
                    Text("支持任意 OpenAI 兼容接口（GPT / DeepSeek / Kimi 等）")
                        .font(.caption).foregroundColor(.secondary)
                    NavigationLink("前往设置") { SettingsView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chatArea
            }
        }
        .navigationTitle("AI助手")
    }

    private var chatArea: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if bubbles.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("你好，我是欧易交易AI助手 👋")
                                    .font(.subheadline.weight(.semibold))
                                Text("可以问我行情、分析走势、查持仓余额，也可以让我帮你下单或撤单（真实委托，会先和你确认）。")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            .padding(.horizontal, 12)
                        }
                        ForEach(bubbles) { b in
                            BubbleView(bubble: b)
                                .id(b.id)
                        }
                        if pending {
                            HStack(spacing: 6) {
                                ProgressView()
                                Text("思考中…").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            .padding(.horizontal, 12)
                            .id("pending")
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: bubbles.count) { _ in
                    withAnimation {
                        if let lastId = bubbles.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        } else {
                            proxy.scrollTo("pending", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: pending) { _ in
                    proxy.scrollTo("pending", anchor: .bottom)
                }
            }

            // 快捷指令
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { p in
                        Button(p) {
                            inputText = p
                            send()
                        }
                        .font(.caption)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                        .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)

            Divider()
            HStack(spacing: 8) {
                TextField("输入问题，如：帮我限价50000买0.001个BTC", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .focused($inputFocused)
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.body)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppTheme.accent))
                        .foregroundColor(.white)
                }
                .disabled(pending || inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !pending else { return }
        inputText = ""
        bubbles.append(ChatBubble(role: "user", text: text, actions: []))
        messages.append((role: "user", content: text))
        pending = true

        Task { @MainActor in
            defer { pending = false }
            do {
                let history = Array(messages.suffix(12))
                let reply = try await AIService.shared.send(history: history)
                messages.append((role: "assistant", content: reply.text))
                bubbles.append(ChatBubble(role: "assistant", text: reply.text, actions: reply.actions))
            } catch {
                bubbles.append(ChatBubble(role: "assistant", text: "出错了：\(error.localizedDescription)", actions: []))
            }
        }
    }
}

// MARK: - 气泡

struct ChatBubble: Identifiable {
    let id = UUID()
    let role: String       // user / assistant
    let text: String
    let actions: [AIService.ExecutedAction]
}

struct BubbleView: View {
    let bubble: ChatBubble

    var body: some View {
        HStack {
            if bubble.role == "user" { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 6) {
                Text(bubble.text)
                    .font(.subheadline)
                    .textSelection(.enabled)
                ForEach(bubble.actions) { a in
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.caption2)
                        Text(a.summary).font(.caption.weight(.semibold))
                    }
                    .foregroundColor(AppTheme.up)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.up.opacity(0.1)))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(bubble.role == "user" ? AppTheme.accent.opacity(0.85) : Color(.secondarySystemBackground)))
            .foregroundColor(bubble.role == "user" ? .white : .primary)
            if bubble.role == "assistant" { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
    }
}
