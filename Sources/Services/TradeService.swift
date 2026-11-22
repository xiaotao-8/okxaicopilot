import Foundation

/// 交易服务：封装下单/撤单/策略委托，统一中文错误提示
@MainActor
final class TradeService: ObservableObject {
    static let shared = TradeService()

    @Published var lastOrderText: String?   // 最近一次下单结果提示
    @Published var lastErrorText: String?

    private let client = OKXClient.shared

    func loadBalance() async throws -> AccountSummary {
        try await client.accountBalance()
    }

    func loadPositions(instType: String = "SWAP") async throws -> [PositionInfo] {
        try await client.positions(instType: instType)
    }

    /// 下单（真实委托）
    func place(instId: String, tdMode: String, side: String, ordType: String,
               sz: String, px: String?, posSide: String? = nil, reduceOnly: Bool = false) async throws -> String {
        do {
            let ordId = try await client.placeOrder(instId: instId, tdMode: tdMode, side: side,
                                                    ordType: ordType, sz: sz, px: px,
                                                    posSide: posSide, reduceOnly: reduceOnly)
            let verb = side == "buy" ? "买入" : "卖出"
            let type = ordType == "market" ? "市价" : "限价\(px ?? "")"
            lastOrderText = "已下单：\(instId) \(verb) \(type) 数量 \(sz) · 订单号 \(ordId)"
            return ordId
        } catch {
            lastErrorText = error.localizedDescription
            throw error
        }
    }

    /// 止盈止损（策略委托）
    func placeTPSL(instId: String, tdMode: String, side: String, sz: String,
                   tp: String?, sl: String?, posSide: String? = nil) async throws -> String {
        do {
            let algoId = try await client.placeTPSL(instId: instId, tdMode: tdMode, side: side, sz: sz,
                                                    tpTriggerPx: tp, slTriggerPx: sl, posSide: posSide)
            lastOrderText = "止盈止损已设置：\(instId) \(side == "buy" ? "买入" : "卖出") 数量 \(sz) · 策略号 \(algoId)"
            return algoId
        } catch {
            lastErrorText = error.localizedDescription
            throw error
        }
    }

    func cancel(instId: String, ordId: String) async throws {
        try await client.cancelOrder(instId: instId, ordId: ordId)
    }

    func cancelAlgo(instId: String, algoId: String) async throws {
        try await client.cancelAlgoOrder(instId: instId, algoId: algoId)
    }
}
