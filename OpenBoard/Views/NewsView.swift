import SafariServices
import SwiftUI

/// News tab: US Chess articles, newest first, a page (~15) at a time — more load
/// as you reach the bottom. A range filter limits how far back it goes. The
/// newest article is a large photo card; the rest are rows with the article's
/// photo, grouped by month. Articles open on the website, inside the app.
struct NewsView: View {
    @Environment(AppModel.self) private var model
    @State private var range: NewsRange = .all
    @State private var articles: [NewsArticle] = []
    @State private var nextPage = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// The article open in Safari.
    @State private var reading: NewsArticle?
    /// The article opened last, outlined when the user comes back.
    @State private var lastOpenedID: String?

    private var cutoff: Date? { range.cutoff() }

    private var shown: [NewsArticle] {
        guard let cutoff else { return articles }
        return articles.filter { ($0.published ?? .distantPast) >= cutoff }
    }

    /// Past the range's cutoff, older pages have nothing to add.
    private var canLoadMore: Bool {
        guard hasMore else { return false }
        guard let cutoff, let oldest = articles.last?.published else { return true }
        return oldest >= cutoff
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenTitle("News")
                rangePicker
                content
            }
            .padding(16)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.news)
        .background(Color.obBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { if articles.isEmpty { await loadNextPage() } }
        .refreshable { await reload() }
        .fullScreenCover(item: $reading) { article in
            SafariView(url: article.link) { reading = nil }
                .ignoresSafeArea()
        }
    }

    // MARK: - Range

    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsRange.allCases) { option in
                    let selected = option == range
                    Button {
                        withAnimation(.snappy) { range = option }
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Color.black : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? Color.obGold : Color.obCard, in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.obHairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier(AccessibilityID.newsRange(option.rawValue))
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let shown = shown
        if let errorMessage, articles.isEmpty {
            ErrorCard(message: errorMessage, cachedAt: nil) {
                Task { await reload() }
            }
        } else if let hero = shown.first {
            open(hero) { HeroNewsCard(article: hero) }
            ForEach(monthGroups(Array(shown.dropFirst())), id: \.title) { group in
                SectionLabel(text: group.title)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(Array(group.articles.enumerated()), id: \.element.id) { index, article in
                        if index > 0 {
                            Divider().padding(.leading, 104)
                        }
                        open(article, cornerRadius: 0) { NewsRow(article: article) }
                    }
                }
                .obCard()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        } else if !isLoading && !canLoadMore {
            EmptyStateCard(systemImage: "newspaper",
                           title: "No news \(range == .all ? "yet" : "in this range")",
                           message: range == .all ? "Pull down to check again." : "Try a longer range.")
        }

        if canLoadMore {
            // Reaching the bottom loads the next page; a short range keeps loading
            // until it passes its cutoff.
            HStack(spacing: 10) {
                ProgressView()
                Text(articles.isEmpty ? "Loading news…" : "Loading more…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .onAppear { Task { await loadNextPage() } }
            .id(articles.count) // a new page re-arms onAppear
        } else if !shown.isEmpty {
            Text("Articles open on new.uschess.org.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    /// Rows grouped under "September 2026"-style headers, in order.
    private func monthGroups(_ articles: [NewsArticle]) -> [(title: String, articles: [NewsArticle])] {
        var groups: [(title: String, articles: [NewsArticle])] = []
        for article in articles {
            let title = article.published?.formatted(.dateTime.month(.wide).year()) ?? String(localized: "Earlier")
            if groups.last?.title == title {
                groups[groups.count - 1].articles.append(article)
            } else {
                groups.append((title, [article]))
            }
        }
        return groups
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
                .background(cornerRadius == 0 && lastOpenedID == article.id ? Color.obGold.opacity(0.12) : .clear)
                .lastOpened(cornerRadius > 0 && lastOpenedID == article.id, cornerRadius: cornerRadius)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(lastOpenedID == article.id ? .isSelected : [])
        .accessibilityHint("Opens the article on US Chess")
        .accessibilityIdentifier(AccessibilityID.newsArticle(article.id))
    }

    // MARK: - Loading

    private func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.news.page(nextPage)
            let known = Set(articles.map(\.id))
            articles = NewsParser.settleDates(articles + page.articles.filter { !known.contains($0.id) })
            hasMore = page.hasMore
            nextPage += 1
            errorMessage = nil
        } catch is CancellationError {
            // Left the tab; the next visit picks up here.
        } catch {
            // Stop here; pull to refresh (or Retry) starts over.
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }

    private func reload() async {
        do {
            let page = try await model.news.page(0, force: true)
            articles = NewsParser.settleDates(page.articles)
            hasMore = page.hasMore
            nextPage = 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Cards

/// The newest article: its photo edge to edge, the headline over a dark fade.
private struct HeroNewsCard: View {
    let article: NewsArticle

    var body: some View {
        NewsImage(url: article.largeImageURL ?? article.imageURL)
            .frame(height: 300)
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
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 6)
                .padding(18)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    // Strong enough to carry white text over busy graphics too.
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black.opacity(0.75), location: 0.35),
                                           .init(color: .black.opacity(0.92), location: 1)],
                                   startPoint: .top,
                                   endPoint: .bottom)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}

/// An article row: its photo as a rounded avatar, the headline, opening lines
/// and date.
private struct NewsRow: View {
    let article: NewsArticle

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NewsImage(url: article.imageURL, compact: true)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let when = Format.newsDate(article.published) {
                    Text(when)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A photo that fills its frame. While it loads, or when an article has none,
/// a gold-tinted panel with a knight stands in.
private struct NewsImage: View {
    let url: URL?
    var compact = false

    var body: some View {
        LinearGradient(colors: [Color.obGold.opacity(0.28), Color.obCard],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
            .overlay {
                Text("♞")
                    .font(.system(size: compact ? 30 : 56))
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
