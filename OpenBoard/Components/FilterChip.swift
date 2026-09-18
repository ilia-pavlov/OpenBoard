import SwiftUI

/// Capsule dropdown used for filter rows (Rating History, Upcoming tournaments).
/// Shows the filter's name while unfiltered and turns gold once a choice is made;
/// chips share a row equally so three always fit on a phone.
struct FilterChip<Content: View>: View {
    var title: String
    var systemImage: String
    var active: Bool
    var id: String?
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage).imageScale(.small)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(active ? Color.obGold : .primary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(active ? Color.obGold.opacity(0.14) : Color.obCard, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.obGold.opacity(0.5) : Color.obHairline))
        }
        .accessibilityIdentifier(id ?? "")
    }
}
