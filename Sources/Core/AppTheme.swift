import SwiftUI

// MARK: - 主题色

enum AppTheme {
    /// 涨（绿）
    static let up = Color(red: 0.10, green: 0.75, blue: 0.45)
    /// 跌（红）
    static let down = Color(red: 0.90, green: 0.28, blue: 0.28)
    /// 品牌强调色
    static let accent = Color(red: 0.0, green: 0.62, blue: 0.45)

    static func color(forChange pct: Double) -> Color {
        pct >= 0 ? up : down
    }
}

extension Double {
    /// 价格格式化（自动小数位）
    var priceText: String {
        let abs_ = abs(self)
        let digits = abs_ >= 1000 ? 2 : (abs_ >= 1 ? 4 : 6)
        return String(format: "%.\(digits)f", self)
    }

    /// 涨跌幅文本，如 +2.35%
    var changeText: String {
        String(format: "%+.2f%%", self)
    }

    /// 大数格式化：1.2万 / 3.4亿
    var cnMagnitudeText: String {
        let v = abs(self)
        if v >= 100_000_000 { return String(format: "%.2f亿", self / 100_000_000) }
        if v >= 10_000 { return String(format: "%.2f万", self / 10_000) }
        return String(format: "%.2f", self)
    }
}
