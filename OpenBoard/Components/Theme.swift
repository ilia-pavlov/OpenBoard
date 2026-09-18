import SwiftUI
import UIKit

// MARK: - Palette (dark-first, adaptive)

extension Color {
    /// Near-black app background (#0B0E13 dark / soft paper in light).
    static let obBackground = Color(dynamicDark: 0x0B0E13, light: 0xF2F4F8)
    /// Card surface (#141922 dark).
    static let obCard = Color(dynamicDark: 0x141922, light: 0xFFFFFF)
    /// Hairline separators (#26303F dark).
    static let obHairline = Color(dynamicDark: 0x26303F, light: 0xD9DEE7)
    /// Signature tournament gold.
    static let obGold = Color(dynamicDark: 0xE9B44C, light: 0xB8860B)
    /// Secondary teal.
    static let obTeal = Color(dynamicDark: 0x3DBCCB, light: 0x18808F)
    /// Rating went up.
    static let obUp = Color(dynamicDark: 0x41D18B, light: 0x14834E)
    /// Rating went down.
    static let obDown = Color(dynamicDark: 0xF0716E, light: 0xC2413E)

    init(dynamicDark dark: UInt32, light: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        })
    }
}

// MARK: - Formatting

extension Int {
    /// Chess-clock display: zero-padded to 4 digits ("0383").
    var clockDigits: String { String(format: "%04d", self) }

    var signedString: String { self >= 0 ? "+\(self)" : "\(self)" }
}

enum Format {
    static func eventDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func daysAgo(_ date: Date?) -> String {
        guard let date else { return "not yet rated" }
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        switch days {
        case ..<1: return "rated today"
        case 1: return "rated yesterday"
        default: return "rated \(days) days ago"
        }
    }

    static func timeOfDay(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Fri, Sep 18 – Sun, Sep 20" (the year is added when it isn't this year).
    static func dateRange(_ start: Date, _ end: Date) -> String {
        let thisYear = Calendar.current.isDate(start, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        let endStyle = thisYear ? style : style.year()
        return "\(start.formatted(style)) – \(end.formatted(endStyle))"
    }

    /// "6462385213" → "(646) 238-5213"; anything else unchanged.
    static func phone(_ digits: String) -> String {
        let d = digits.count == 11 && digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
        guard d.count == 10 else { return digits }
        return "(\(d.prefix(3))) \(d.dropFirst(3).prefix(3))-\(d.suffix(4))"
    }
}

// MARK: - Reusable card chrome

extension View {
    /// Content-layer card: opaque surface + hairline. Used for lists/stat rows
    /// so glass stays reserved for the hero chrome.
    func obCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Color.obCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.obHairline, lineWidth: 1)
            )
    }
}
