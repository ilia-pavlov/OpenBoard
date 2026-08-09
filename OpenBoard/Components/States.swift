import SwiftUI

// MARK: - Generic load state

enum Loadable<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    /// Failed, possibly with a stale cached copy + its timestamp.
    case failed(message: String, cached: T?, cachedAt: Date?)

    var value: T? {
        switch self {
        case .loaded(let v): v
        case .failed(_, let cached, _): cached
        default: nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Skeleton shimmer

struct SkeletonCard: View {
    var height: CGFloat = 120
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.obCard)
            .overlay(shimmer.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.obHairline, lineWidth: 1)
            )
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
            .accessibilityLabel("Loading")
    }

    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Color.white.opacity(0.06), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.7)
                .offset(x: geo.size.width * phase)
        }
    }
}

struct SkeletonList: View {
    var rows: Int = 3

    var body: some View {
        VStack(spacing: 14) {
            SkeletonCard(height: 200)
            HStack(spacing: 14) {
                SkeletonCard(height: 110)
                SkeletonCard(height: 110)
            }
            ForEach(0..<rows, id: \.self) { _ in
                SkeletonCard(height: 64)
            }
        }
    }
}

// MARK: - Error card

struct ErrorCard: View {
    var message: String
    var cachedAt: Date?
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.obDown)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Retry", action: retry)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .obCard()
    }

    private var title: String {
        if let cachedAt {
            "Couldn't reach US Chess — showing cached from \(Format.timeOfDay(cachedAt))"
        } else {
            "Couldn't reach US Chess"
        }
    }
}

// MARK: - Empty state

struct EmptyStateCard: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(Color.obGold)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .obCard()
    }
}
