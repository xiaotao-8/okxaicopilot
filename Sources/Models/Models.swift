import Foundation

// MARK: - Dictionary parsing helpers

extension Dictionary where Key == String, Value == Any {
    func s(_ key: String) -> String {
        (self[key] as? String) ?? ""
    }
    func d(_ key: String) -> Double {
        if let v = self[key] as? String { return Double(v) ?? 0 }
        if let v = self[key] as? NSNumber { return v.doubleValue }
        return 0
    }
    func sub(_ key: String) -> [String: Any] {
        (self[key] as? [String: Any]) ?? [:]
    }
    func arr(_ key: String) -> [[String: Any]] {
        (self[key] as? [[String: Any]]) ?? []
    }
}

// MARK: - 行情 Ticker

struct Ticker: Identifiable, Equatable {
    let instId: String
    var last: Double
    var open24h: Double
    var high24h: Double
    var low24h: Double
    var volCcy24h: Double
    var changePct: Double

    var id: String { instId }

    init(_ dict: [String: Any]) {
        instId = dict.s("instId")
        last = dict.d("last")
        open24h = dict.d("open24h")
        high24h = dict.d("high24h")
        low24h = dict.d("low24h")
        volCcy24h = dict.d("volCcy24h")
        let open = open24h != 0 ? open24h : 1
        changePct = (last - open) / open * 100
    }

    func updating(with dict: [String: Any]) -> Ticker {
        var t = self
        let new = Ticker(dict)
        if new.last != 0 { t.last = new.last }
        if new.high24h != 0 { t.high24h = new.high24h }
        if new.low24h != 0 { t.low24h = new.low24h }
        if new.volCcy24h != 0 { t.volCcy24h = new.volCcy24h }
        let open = t.open24h != 0 ? t.open24h : 1
        t.changePct = (t.last - open) / open * 100
        return t
    }
}

// MARK: - K线

struct Candle: Identifiable {
    let ts: Double
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    var id: Double { ts }

    /// OKX K线数组: [ts, o, h, l, c, vol, volCcy, volCcyQuote, confirm]
    init(_ row: [Any]) {
        func f(_ i: Int) -> Double { (row[i] as? String).flatMap(Double.init) ?? 0 }
        ts = f(0) / 1000
        open = f(1); high = f(2); low = f(3); close = f(4)
        volume = f(6)
    }
}

// MARK: - 盘口深度

struct BookLevel {
    let price: Double
    let size: Double
    init(_ row: [Any]) {
        func f(_ i: Int) -> Double { (row[i] as? String).flatMap(Double.init) ?? 0 }
        price = f(0); size = f(1)
    }
}

struct OrderBook {
    var bids: [BookLevel] = []
    var asks: [BookLevel] = []
    var ts: Double = 0

    init(data: [[String: Any]]) {
        guard let first = data.first else { return }
        bids = (first["bids"] as? [[Any]] ?? []).map(BookLevel.init)
        asks = (first["asks"] as? [[Any]] ?? []).map(BookLevel.init)
        ts = first.d("ts") / 1000
    }

    init() {}
}

// MARK: - 订单

enum OrderState {
    case live, partiallyFilled, filled, canceled, other

    var label: String {
        switch self {
        case .live: return "等待成交"
        case .partiallyFilled: return "部分成交"
        case .filled: return "已成交"
        case .canceled: return "已撤销"
        case .other: return "其他"
        }
    }

    init(_ state: String) {
        switch state {
        case "live": self = .live
        case "partially_filled": self = .partiallyFilled
        case "filled": self = .filled
        case "canceled": self = .canceled
        default: self = .other
        }
    }
}

struct OrderInfo: Identifiable {
    let ordId: String
    let instId: String
    let instType: String
    let side: String          // buy / sell
    let ordType: String       // limit / market / post_only ...
    let tdMode: String        // cash / cross / isolated
    let px: Double
    let sz: Double
    let accFillSz: Double
    let avgPx: Double
    let state: String
    let cTime: Double

    var id: String { ordId }
    var stateLabel: String { OrderState(state).label }
    var sideLabel: String { side == "buy" ? "买入" : "卖出" }
    var typeLabel: String { ordType == "market" ? "市价" : "限价" }
    var timeLabel: String {
        Date(timeIntervalSince1970: cTime / 1000).formatted(date: .abbreviated, time: .shortened)
    }

    init(_ dict: [String: Any]) {
        ordId = dict.s("ordId")
        instId = dict.s("instId")
        instType = dict.s("instType")
        side = dict.s("side")
        ordType = dict.s("ordType")
        tdMode = dict.s("tdMode")
        px = dict.d("px")
        sz = dict.d("sz")
        accFillSz = dict.d("accFillSz")
        avgPx = dict.d("avgPx")
        state = dict.s("state")
        cTime = dict.d("cTime")
    }
}

// MARK: - 持仓

struct PositionInfo: Identifiable {
    let instId: String
    let posSide: String       // long / short / net
    let pos: Double
    let avgPx: Double
    let upl: Double
    let uplRatio: Double
    let lever: Double
    let mgnMode: String
    let instType: String
    let sourceTag: String     // 跟单来源标签（跟投仓位标识，可为空）
    let cTime: Double

    var id: String { instId + "_" + posSide }
    var directionLabel: String {
        posSide == "net" ? (pos >= 0 ? "多" : "空") : (posSide == "long" ? "多" : "空")
    }
    var isCopyTrade: Bool { !sourceTag.isEmpty }
    var timeLabel: String {
        Date(timeIntervalSince1970: cTime / 1000).formatted(date: .abbreviated, time: .shortened)
    }

    init(_ dict: [String: Any]) {
        instId = dict.s("instId")
        posSide = dict.s("posSide")
        pos = dict.d("pos")
        avgPx = dict.d("avgPx")
        upl = dict.d("upl")
        uplRatio = dict.d("uplRatio") * 100
        lever = dict.d("lever")
        mgnMode = dict.s("mgnMode")
        instType = dict.s("instType")
        sourceTag = dict.s("sourceTag")
        cTime = dict.d("cTime")
    }
}

// MARK: - 策略委托（止盈止损单）

struct AlgoOrderInfo: Identifiable {
    let algoId: String
    let instId: String
    let ordType: String        // conditional / oco
    let side: String
    let sz: Double
    let tpTriggerPx: Double
    let slTriggerPx: Double
    let state: String
    let cTime: Double

    var id: String { algoId }
    var typeLabel: String {
        if ordType == "oco" { return "止盈止损" }
        return tpTriggerPx != 0 ? "止盈" : "止损"
    }
    var sideLabel: String { side == "buy" ? "买入" : "卖出" }

    init(_ dict: [String: Any]) {
        algoId = dict.s("algoId")
        instId = dict.s("instId")
        ordType = dict.s("ordType")
        side = dict.s("side")
        sz = dict.d("sz")
        tpTriggerPx = dict.d("tpTriggerPx")
        slTriggerPx = dict.d("slTriggerPx")
        state = dict.s("state")
        cTime = dict.d("cTime")
    }
}

// MARK: - 资产

struct AssetBalance: Identifiable {
    let ccy: String
    let eq: Double        // 总权益
    let availBal: Double  // 可用余额

    var id: String { ccy }

    init(_ dict: [String: Any]) {
        ccy = dict.s("ccy")
        eq = dict.d("eq")
        availBal = dict.d("availBal") != 0 ? dict.d("availBal") : dict.d("availEq")
    }
}

// MARK: - 跟单/带单交易员

struct LeadTrader: Identifiable {
    let uniqueCode: String
    let nickName: String
    let instType: String
    let aum: Double          // 资产管理规模
    let pnlRatio: Double     // 收益率
    let followers: Double
    let curPnl: Double

    var id: String { uniqueCode }

    init(_ dict: [String: Any]) {
        uniqueCode = dict.s("uniqueCode")
        nickName = dict.s("nickName")
        instType = dict.s("instType")
        aum = dict.d("aum")
        pnlRatio = dict.d("pnlRatio") * 100
        followers = dict.d("curSharingCnt")
        curPnl = dict.d("curPnl")
    }
}

struct LeadTraderPosition: Identifiable {
    let instId: String
    let posSide: String
    let pos: Double
    let posAvgPx: Double
    let openAvgPx: Double
    let lever: Double
    let cTime: Double
    let uniqueCode: String

    var id: String { uniqueCode + "_" + instId + "_" + posSide }

    init(_ dict: [String: Any]) {
        instId = dict.s("instId")
        posSide = dict.s("posSide")
        pos = dict.d("pos")
        posAvgPx = dict.d("posAvgPx")
        openAvgPx = dict.d("openAvgPx")
        lever = dict.d("lever")
        cTime = dict.d("cTime")
        uniqueCode = dict.s("uniqueCode")
    }
}

// MARK: - 账户概况

struct AccountSummary {
    var totalEq: Double = 0       // 总权益(USD)
    var details: [AssetBalance] = []
}
