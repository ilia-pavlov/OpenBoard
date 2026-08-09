import SwiftUI

/// Rendered via ImageRenderer for ShareLink — a bragging-rights result card.
struct ResultShareCard: View {
    var playerName: String
    var eventName: String
    var placement: Int?
    var score: String?
    var delta: Int?
    var newRating: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Color(dynamicDark: 0xE9B44C, light: 0xE9B44C))
                Text("OPENBOARD")
                    .font(.caption.weight(.heavy))
                    .kerning(2.5)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }

            Text(playerName)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text(eventName)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 14) {
                if let placement {
                    chip("№ \(placement)", tint: Color(red: 0.91, green: 0.71, blue: 0.30))
                }
                if let score {
                    chip("SCORE \(score)", tint: Color(red: 0.24, green: 0.74, blue: 0.80))
                }
                if let delta {
                    chip(delta >= 0 ? "▲ \(delta)" : "▼ \(abs(delta))",
                         tint: delta >= 0
                            ? Color(red: 0.25, green: 0.82, blue: 0.55)
                            : Color(red: 0.94, green: 0.44, blue: 0.43))
                }
            }

            if let newRating {
                Text(String(format: "%04d", newRating))
                    .font(.system(size: 88, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.91, green: 0.71, blue: 0.30))
                    .shadow(color: Color(red: 0.91, green: 0.71, blue: 0.30).opacity(0.5), radius: 16)
                Text("NEW USCF REGULAR RATING")
                    .font(.caption.weight(.semibold))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(36)
        .frame(width: 480, alignment: .leading)
        .background(Color(red: 0.043, green: 0.055, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

@MainActor
enum ShareCardRenderer {
    static func render(_ card: ResultShareCard) -> Image? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
