import SafariServices
import SwiftUI

/// News tab: recent US Chess articles, newest first. The newest is a full-bleed
/// hero, the rest of this week are large cards, and older ones sit in a grid.
/// Articles open on the website, inside the app, where they read best.
struct NewsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[NewsArticle]> = .idle
    /// The article open in Safari.
    @State private var reading: NewsArticle?
    /// The article opened last, outlined when the user comes back.
    @State private var lastOpenedID: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenTitle("News")
                content
            }
            .padding(16)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.news)
        .background(Color.obBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { if state.value == nil { await load(force: false) } }
        .refreshable { await load(force: true) }
        .fullScreenCover(item: $reading) { article in
            SafariView(url: article.link) { reading = nil }
                .ignoresSafeArea()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            SkeletonCard(height: 300)
            SkeletonCard(height: 240)
        case .loaded(let articles):
            feed(articles)
        case .failed(let message, let cached, let cachedAt):
            ErrorCard(message: message, cachedAt: cachedAt) {
                Task { await load(force: true) }
            }
            if let cached { feed(cached) }
        }
    }

    @ViewBuilder
    private func feed(_ articles: [NewsArticle]) -> some View {
        if let hero = articles.first {
            let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
            let rest = articles.dropFirst()
            let thisWeek = rest.filter { ($0.published ?? .distantPast) >= weekAgo }
            let earlier = rest.filter { ($0.published ?? .distantPast) < weekAgo }

            open(hero) { HeroNewsCard(article: hero) }

            if !thisWeek.isEmpty {
                SectionLabel(text: "This week")
                    .padding(.top, 8)
                ForEach(thisWeek) { article in
                    open(article) { NewsCard(article: article) }
                }
            }
            if !earlier.isEmpty {
                SectionLabel(text: "Earlier")
                    .padding(.top, 8)
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(earlier) { article in
                        open(article, cornerRadius: 16) { NewsTile(article: article) }
                    }
                }
            }
            Text("Articles open on new.uschess.org.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        } else {
            EmptyStateCard(systemImage: "newspaper",
                           title: "No news right now",
                           message: "Pull down to check again.")
        }
    }

    /// A tappable article that opens on the website and is outlined on return.
    private func open(
        _ article: NewsArticle,
        cornerRadius: CGFloat = 20,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            lastOpenedID = article.id
            reading = article
        } label: {
            label()
                .lastOpened(lastOpenedID == article.id, cornerRadius: cornerRadius)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the article on US Chess")
        .accessibilityIdentifier(AccessibilityID.newsArticle(article.id))
    }

    // MARK: - Loading

    private func load(force: Bool) async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await model.news.latest(force: force))
        } catch is CancellationError {
            // Left the tab mid-load; the next visit loads again.
        } catch {
            let cached = await model.news.cachedLatest()
            state = .failed(message: error.localizedDescription, cached: cached?.0, cachedAt: cached?.1)
        }
    }
}

// MARK: - Cards

/// The newest article: its photo edge to edge, the headline over a dark fade.
private struct HeroNewsCard: View {
    let article: NewsArticle

    var body: some View {
        NewsImage(url: article.imageURL)
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    if let when = Format.newsDate(article.published) {
                        Text(when.uppercased())
                            .font(.caption2.weight(.bold))
                            .kerning(1)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.obGold, in: Capsule())
                    }
                    Text(article.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !article.summary.isEmpty {
                        Text(article.summary)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}

/// This week's articles: photo on top, headline and opening lines below.
private struct NewsCard: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewsImage(url: article.imageURL)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                NewsByline(article: article)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .obCard()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Older articles, two to a row: photo and headline.
private struct NewsTile: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewsImage(url: article.imageURL)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                Text(Format.newsDate(article.published) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .obCard(cornerRadius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "JJ Lang · 2 days ago"
private struct NewsByline: View {
    let article: NewsArticle

    var body: some View {
        Text([article.author, Format.newsDate(article.published)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// A photo that fills its frame. Articles without one (or while it loads) get a
/// gold-tinted panel with a knight, so the feed never shows a gray hole.
private struct NewsImage: View {
    let url: URL?

    var body: some View {
        LinearGradient(colors: [Color.obGold.opacity(0.28), Color.obCard],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
            .overlay {
                Text("♞")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.obGold.opacity(0.35))
            }
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Safari

/// The article on the website, in Safari inside the app (Reader, sharing and
/// the site's own layout), tinted to match. Done closes it.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor(Color.obGold)
        safari.dismissButtonStyle = .close
        safari.delegate = context.coordinator
        return safari
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDone()
        }
    }
}
