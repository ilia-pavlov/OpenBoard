import Foundation

/// Inline Markdown (from `TournamentParser.markdown(fromHTML:)`) ready to display:
/// bold, italic and links kept, and bare web addresses, emails and phone numbers
/// made tappable. Used by tournament announcements and news articles.
enum RichText {
    static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var text = (try? AttributedString(markdown: markdown, options: options))
            ?? AttributedString(markdown)
        let plain = String(text.characters)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return text }
        for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            let url = match.url ?? match.phoneNumber.flatMap { URL(string: "tel:" + $0.filter(\.isNumber)) }
            guard let url, let range = Range(match.range, in: text),
                  text[range].runs.allSatisfy({ $0.link == nil }) else { continue }
            text[range].link = url
        }
        return text
    }
}
