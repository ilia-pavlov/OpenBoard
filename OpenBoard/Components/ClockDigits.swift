import SwiftUI

/// THE signature element: ratings as glowing chess-clock digits.
struct ClockDigits: View {
    var value: Int?
    var tint: Color = .obGold
    var size: Font.TextStyle = .largeTitle

    @ScaledMetric(relativeTo: .largeTitle) private var glowRadius = 10

    var body: some View {
        Group {
            if let value {
                Text(value.clockDigits)
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.55), radius: glowRadius)
                    .shadow(color: tint.opacity(0.25), radius: glowRadius * 2.4)
            } else {
                Text(verbatim: "– – – –")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size, design: .monospaced).weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .accessibilityLabel(value.map { "rating \($0)" } ?? "unrated")
    }
}

/// Extra-large hero variant used on My Card / profile.
struct HeroClockDigits: View {
    var value: Int?
    var tint: Color = .obGold

    @ScaledMetric(relativeTo: .largeTitle) private var fontSize = 64

    var body: some View {
        Group {
            if let value {
                Text(value.clockDigits)
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.55), radius: 12)
                    .shadow(color: tint.opacity(0.22), radius: 30)
            } else {
                Text(verbatim: "– – – –")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.35)
        .accessibilityLabel(value.map { "rating \($0)" } ?? "unrated")
    }
}

#Preview("Clock digits", traits: .sizeThatFitsLayout) {
    VStack(spacing: 20) {
        HeroClockDigits(value: 383)
        ClockDigits(value: 379, tint: .obTeal)
        ClockDigits(value: nil)
    }
    .padding(40)
    .background(Color.obBackground)
    .preferredColorScheme(.dark)
}
