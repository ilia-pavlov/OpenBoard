import SwiftUI

// MARK: - Hero card (My Card home screen)

struct HeroRatingCard: View {
    var label: String = "Regular"
    var rating: Rating?
    var delta: Int?
    var sparkline: [Int]
    var peak: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: label)
                Spacer()
                if let delta, delta != 0 {
                    DeltaBadge(delta: delta, prominent: true)
                }
            }
            HeroClockDigits(value: rating?.value)
            if sparkline.count > 1 {
                Sparkline(values: sparkline)
                    .frame(height: 64)
                    .clipped() // Charts' AreaMark can overshoot its frame; contain it
            }
            footer
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var footer: some View {
        Text(footerText)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .kerning(0.5)
    }

    private var footerText: String {
        guard let rating, rating.isRated else { return "UNRATED — PLAY A RATED EVENT TO GET ON THE BOARD" }
        var parts: [String] = []
        if let floor = rating.floor { parts.append("FLOOR \(floor)") }
        if let games = rating.games { parts.append("\(games) GAMES") }
        if rating.isProvisional { parts.append("PROVISIONAL (<26 GAMES)") }
        if let peak { parts.append("PEAK \(peak)") }
        return parts.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        guard let value = rating?.value else { return "\(label) rating: unrated" }
        var text = "\(label) rating \(value)"
        if let delta, delta != 0 {
            text += delta > 0 ? ", up \(delta)" : ", down \(abs(delta))"
        }
        return text
    }
}

// MARK: - Dual live/published card (player profile)

struct DualRatingCard: View {
    var label: String = "Regular"
    var published: Int?
    var live: Int?
    var footnote: String?

    private var hasPendingChange: Bool { live != nil && live != published }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: label)
            HStack(alignment: .lastTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.obGold)
                        .kerning(1)
                    HeroClockDigits(value: live ?? published)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PUBLISHED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .kerning(1)
                    Text(published.map(\.clockDigits) ?? "– – – –")
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
            }
            if hasPendingChange {
                Label("Live includes results not yet in the published supplement",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let footnote {
                Text(footnote)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Half-width mini card (Quick / Blitz)

struct MiniRatingCard: View {
    var label: String
    var rating: Rating?
    var tint: Color = .obTeal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: label)
            ClockDigits(value: rating?.value, tint: tint, size: .title)
            Text(footnote)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var footnote: String {
        guard let rating, rating.isRated else { return "UNRATED" }
        var parts: [String] = []
        if let games = rating.games { parts.append("\(games) GAMES") }
        if let floor = rating.floor { parts.append("FLOOR \(floor)") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}
