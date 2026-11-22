import Foundation

// MARK: - AI 服务（用户自行接入任意 OpenAI 兼容模型的 Key）

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    struct AIReply {
        let text: String
        let actions: [ExecutedAction]
    }

    struct ExecutedAction: Identifiable {
        let id = UUID()
        let summary: String
    }

    private let client = OKXClient.shared
    private let config = OKXConfig.shared

    private var systemPrompt: String {
        """
        你是欧易(OKX)交易AI助手，运行在iOS客户端中。你可以调用工具：查询行情(tickers/orderbook/candles)、查询持仓、查询账户余额、执行下单(place_order)与撤单(cancel_order)。
        规则：
        1. 始终使用中文回答。
        2. 执行下单/撤单前，若用户没有明确给出完整参数和明确指令，必须先向用户确认。
        3. 数量单位说明：现货为币的数量(个)，永续合约为张。
        4. 回答末尾简要提示市场风险。
        当前环境：\(config.isDemo ? "模拟盘" : "实盘")
        """
    }

    private var tools: [[String: Any]] {
        [
            tool("get_ticker", "获取某交易对最新行情", ["instId": "交易对，如 BTC-USDT"]),
            tool("get_orderbook", "获取盘口深度前10档", ["instId": "交易对"]),
            tool("get_candles", "获取K线", ["instId": "交易对", "bar": "周期：1m/5m/15m/1H/4H/1D", "limit": "数量，默认50"]),
            tool("get_positions", "查询当前合约持仓", [:]),
            tool("get_balance", "查询账户权益与币种余额", [:]),
            tool("place_order", "提交真实订单。instId交易对; side买buy/卖sell; ordType限价limit/市价market; sz数量; px限价价格(市价省略); tdMode现货cash/合约cross",
                 ["instId": "", "side": "", "ordType": "", "sz": "", "px": "限价时必填，可省略", "tdMode": "cash或cross，可省略"]),
            tool("cancel_order", "撤销订单", ["instId": "交易对", "ordId": "订单号"]),
        ]
    }

    private func tool(_ name: String, _ desc: String, _ params: [String: String]) -> [String: Any] {
        let properties: [String: Any] = params.mapValues { ["type": "string", "description": $0] }
        let required = ["instId", "side", "ordType", "sz"].filter { params.keys.contains($0) }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": desc,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ],
            ],
        ]
    }

    /// 发送对话，自动执行模型工具调用，返回最终回复与已执行动作
    func send(history: [(role: String, content: String)]) async throws -> AIReply {
        guard !config.aiAPIKey.isEmpty else {
            throw OKXError.api(code: "AI", message: "请先在设置页配置AI模型API Key（支持任意OpenAI兼容接口）")
        }

        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for m in history {
            messages.append(["role": m.role, "content": m.content])
        }

        var actions: [ExecutedAction] = []
        var finalText = ""

        for _ in 0..<4 {
            let result = try await chatCompletion(messages: messages)
            let choice = ((result["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]) ?? [:]
            finalText = (choice["content"] as? String) ?? ""
            let toolCalls = (choice["tool_calls"] as? [[String: Any]]) ?? []

            guard !toolCalls.isEmpty else { break }

            messages.append(choice)
            for call in toolCalls {
                let fn = (call["function"] as? [String: Any]) ?? [:]
                let name = (fn["name"] as? String) ?? ""
                let argsJSON = (fn["arguments"] as? String) ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8)) as? [String: Any]) ?? [:]
                let (reply, action) = await executeTool(name, args)
                if let action { actions.append(action) }
                messages.append([
                    "role": "tool",
                    "tool_call_id": (call["id"] as? String) ?? "",
                    "content": reply,
                ])
            }
        }
        return AIReply(text: finalText, actions: actions)
    }

    // MARK: - 工具执行（对接欧易真实接口）

    private func executeTool(_ name: String, _ args: [String: Any]) async -> (String, ExecutedAction?) {
        do {
            switch name {
            case "get_ticker":
                let t = try await client.ticker(instId: args.s2("instId"))
                return ("\(t.instId) 最新价 \(t.last)，24h涨跌 \(t.changeText)，最高 \(t.high24h)，最低 \(t.low24h)", nil)

            case "get_orderbook":
                let b = try await client.orderBook(instId: args.s2("instId"), sz: 10)
                let bids = b.bids.map { "买 \($0.price)x\($0.size)" }.joined(separator: "; ")
                let asks = b.asks.map { "卖 \($0.price)x\($0.size)" }.joined(separator: "; ")
                return ("买盘: \(bids)\n卖盘: \(asks)", nil)

            case "get_candles":
                let bar = args.s2("bar").isEmpty ? "15m" : args.s2("bar")
                let limitN = Int(args.d2("limit")) == 0 ? 50 : Int(args.d2("limit"))
                let cs = try await client.candles(instId: args.s2("instId"), bar: bar, limit: limitN)
                let summary = cs.prefix(5).map { "开\($0.open) 收\($0.close) 高\($0.high) 低\($0.low)" }
                    .joined(separator: "\n")
                return ("最近K线（新到旧）：\n\(summary)", nil)

            case "get_positions":
                let ps = try await client.positions(instType: "ANY").filter { abs($0.pos) > 0 }
                guard !ps.isEmpty else { return ("当前无持仓", nil) }
                let text = ps.map { "\($0.instId) \($0.directionLabel) 数量\(abs($0.pos)) 均价\($0.avgPx) 未实现盈亏\($0.upl)" }
                    .joined(separator: "\n")
                return (text, nil)

            case "get_balance":
                let s = try await client.accountBalance()
                let details = s.details.filter { $0.eq != 0 }.prefix(8)
                    .map { "\($0.ccy): 权益\($0.eq) 可用\($0.availBal)" }.joined(separator: "; ")
                return ("总权益 $\(s.totalEq)。明细：\(details)", nil)

            case "place_order":
                let ordId = try await client.placeOrder(
                    instId: args.s2("instId"),
                    tdMode: args.s2("tdMode").isEmpty ? "cash" : args.s2("tdMode"),
                    side: args.s2("side"),
                    ordType: args.s2("ordType"),
                    sz: args.s2("sz"),
                    px: args.s2("px").isEmpty ? nil : args.s2("px")
                )
                let verb = args.s2("side") == "buy" ? "买入" : "卖出"
                let type = args.s2("ordType") == "market" ? "市价" : "限价\(args.s2("px"))"
                let summary = "⚡ 已下单：\(args.s2("instId")) \(verb) \(type) 数量\(args.s2("sz")) · 订单号 \(ordId)"
                return ("下单成功，订单号 \(ordId)", ExecutedAction(summary: summary))

            case "cancel_order":
                try await client.cancelOrder(instId: args.s2("instId"), ordId: args.s2("ordId"))
                let summary = "⚡ 已撤单：\(args.s2("instId")) 订单号 \(args.s2("ordId"))"
                return ("撤单成功", ExecutedAction(summary: summary))

            default:
                return ("未知工具", nil)
            }
        } catch {
            return ("工具执行失败：\(error.localizedDescription)", nil)
        }
    }

    // MARK: - OpenAI 兼容请求

    private func chatCompletion(messages: [[String: Any]]) async throws -> [String: Any] {
        var url = URL(string: config.aiBaseURL)!
        if !url.path.contains("/chat/completions") {
            url.appendPathComponent("chat/completions")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.aiAPIKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.aiModel,
            "messages": messages,
            "tools": tools,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw OKXError.badResponse }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OKXError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (obj["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? "未知错误"
            throw OKXError.api(code: String(http.statusCode), message: msg)
        }
        return obj
    }
}

private extension Dictionary where Key == String, Value == Any {
    func s2(_ k: String) -> String { (self[k] as? String) ?? "" }
    func d2(_ k: String) -> Double { (self[k] as? String).flatMap(Double.init) ?? 0 }
}
