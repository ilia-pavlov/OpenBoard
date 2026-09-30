import SwiftUI

/// News tab: the latest US Chess articles, filterable by topic. The newest is
/// featured with its photo; each opens the full article.
struct NewsView: View {
    @Environment(AppModel.self) private var model
    @State private var topic: NewsTopic = .all
    @State private var state: Loadable<[NewsArticle]> = .idle
    /// The topic the shown articles came from; `.task` re-runs on every return
    /// to the tab, and reloading the same topic would reset the scroll.
    @State private var loadedTopic: NewsTopic?
    /// The article opened last, outlined when the user comes back.
    @State private var lastOpenedID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenTitle("News")
                topicPicker
                content
            }
            .padding(16)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.news)
        .background(Color.obBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: topic) { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    // MARK: - Topics

    private var topicPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsTopic.allCases) { option in
                    Button {
                        withAnimation(.snappy) { topic = option }
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(option == topic ? Color.black : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(option == topic ? Color.obGold : Color.obCard, in: Capsule())
                            .overlay(Capsule().strokeBorder(option == topic ? Color.clear : Color.obHairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == topic ? .isSelected : [])
                    .accessibilityIdentifier(AccessibilityID.newsTopic(option.rawValue))
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - Articles

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            SkeletonCard(height: 280)
            SkeletonCard(height: 110)
            SkeletonCard(height: 110)
        case .loaded(let articles):
            list(articles)
        case .failed(let message, let cached, let cachedAt):
            ErrorCard(message: message, cachedAt: cachedAt) {
                Task { await load(force: true) }
            }
            if let cached { list(cached) }
        }
    }

    @ViewBuilder
    private func list(_ articles: [NewsArticle]) -> some View {
        if articles.isEmpty {
            EmptyStateCard(systemImage: "newspaper",
                           title: "No articles yet",
                           message: "Nothing in \(topic.title) right now. Try another topic.")
        } else {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                NavigationLink(value: Destination.newsArticle(article)) {
                    Group {
                        if index == 0 {
                            FeaturedNewsCard(article: article)
                        } else {
                            NewsRow(article: article)
                        }
                    }
                    .lastOpened(lastOpenedID == article.id)
                }
                .buttonStyle(.plain)
                .onOpen { lastOpenedID = article.id }
                .accessibilityIdentifier(AccessibilityID.newsArticle(article.id))
            }
            Text("News from US Chess (new.uschess.org).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    // MARK: - Loading

    private func load(force: Bool) async {
        guard force || loadedTopic != topic || state.value == nil else { return }
        if loadedTopic != topic || state.value == nil { state = .loading }
        do {
            state = .loaded(try await model.news.articles(topic, force: force))
            loadedTopic = topic
        } catch is CancellationError {
            // A newer topic replaced this one.
        } catch {
            let cached = await model.news.cachedArticles(topic)
            state = .failed(message: error.localizedDescription, cached: cached?.0, cachedAt: cached?.1)
        }
    }
}

// MARK: - Rows

/// The newest article: large photo, headline, opening lines.
private struct FeaturedNewsCard: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewsImage(url: article.imageURL)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                NewsByline(article: article)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .obCard()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct NewsRow: View {
    let article: NewsArticle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                NewsByline(article: article)
            }
            Spacer(minLength: 0)
            NewsImage(url: article.imageURL)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .obCard()
        .contentShape(Rectangle())
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

/// A remote photo that fills its frame, with a quiet placeholder while loading
/// or when the article has none.
struct NewsImage: View {
    let url: URL?

    var body: some View {
        Color.obCard
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "newspaper")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Article

struct NewsArticleView: View {
    let article: NewsArticle

    @Environment(AppModel.self) private var model
    @State private var text: Loadable<String> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if article.imageURL != nil {
                    NewsImage(url: article.imageURL)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Text(article.title)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                NewsByline(article: article)
                articleText
                photos
                Link(destination: article.link) {
                    Label("Read on US Chess", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.newsArticle)
        .background(Color.obBackground)
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: article.link, subject: Text(article.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task(id: article.id) { await load() }
    }

    @ViewBuilder
    private var articleText: some View {
        switch text {
        case .idle, .loading:
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            ProgressView()
                .frame(maxWidth: .infinity)
        case .loaded(let markdown):
            Text(RichText.attributed(markdown))
                .font(.body)
                .tint(Color.obGold)
                .textSelection(.enabled)
        case .failed:
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.body)
            }
            Text("Couldn't load the full article. Open it on US Chess below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The article's other photos (the first is the lead image above).
    @ViewBuilder
    private var photos: some View {
        let more = Array(article.imageURLs.dropFirst())
        if !more.isEmpty {
            SectionLabel(text: "Photos")
                .padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(more, id: \.self) { url in
                        NewsImage(url: url)
                            .frame(width: 240, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func load() async {
        guard text.value == nil else { return }
        text = .loading
        do {
            let markdown = try await model.news.body(of: article)
            text = markdown.isEmpty ? .failed(message: "", cached: nil, cachedAt: nil) : .loaded(markdown)
        } catch is CancellationError {
            // Left the article.
        } catch {
            text = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
        }
    }
}
