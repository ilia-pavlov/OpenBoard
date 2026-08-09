import SwiftUI

// MARK: - Delta badge (▲ green / ▼ red)

struct DeltaBadge: View {
    var delta: Int
    var prominent: Bool = false

    private var tint: Color { delta >= 0 ? .obUp : .obDown }
    private var arrow: String { delta >= 0 ? "▲" : "▼" }

    var body: some View {
        Text("\(arrow) \(abs(delta))")
            .font(prominent ? .title3.weight(.bold) : .caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, prominent ? 10 : 6)
            .padding(.vertical, prominent ? 4 : 2)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel(delta >= 0 ? "up \(abs(delta))" : "down \(abs(delta))")
    }
}

// MARK: - Class chip ("● Class H · New Jersey")

struct ClassChip: View {
    var rating: Int?
    var stateName: String?

    var body: some View {
        if rating != nil || stateName != nil {
            HStack(spacing: 6) {
                Circle().fill(Color.obGold).frame(width: 7, height: 7)
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.obGold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(Color.obGold.opacity(0.12)), in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    private var label: String {
        var parts: [String] = []
        if let rating { parts.append(ClassTitle(rating: rating).rawValue) }
        if let stateName { parts.append(stateName) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Stat card (National / State ranking)

struct StatCard: View {
    var title: String
    var value: String
    var caption: String?
    var systemImage: String
    var tint: Color = .obGold

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .obCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Initials avatar

struct InitialsAvatar: View {
    var name: String
    var tint: Color = .obTeal
    var size: CGFloat = 44

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            Circle().strokeBorder(tint.opacity(0.45), lineWidth: 1)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(1.1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
