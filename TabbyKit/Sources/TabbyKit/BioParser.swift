import Foundation

/// Text-level parsing of titles, descriptions and bios. Formats are unverified until the Phase 0 spike.
public enum BioParser {
    /// Web links in a bio (emails excluded).
    public static func links(in text: String) -> [URL] {
        detectedURLs(in: text).filter { $0.scheme?.lowercased() != "mailto" }
    }

    public static func emails(in text: String) -> [String] {
        detectedURLs(in: text).compactMap { url in
            guard url.scheme?.lowercased() == "mailto" else { return nil }
            return String(url.absoluteString.dropFirst("mailto:".count)).removingPercentEncoding
        }
    }

    private static func detectedURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    /// LinkedIn og:title, expected as "Name - Headline - Company | LinkedIn".
    public static func parseLinkedInTitle(_ title: String) -> (name: String, headline: String?)? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: " | LinkedIn", options: [.backwards, .caseInsensitive]) {
            text = String(text[..<range.lowerBound])
        }
        let parts = text.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let name = parts.first, !isLinkedInBoilerplate(name) else { return nil }
        let headline = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil
        return (name, headline)
    }

    /// Login-wall and generic page titles that are not a person's name.
    static func isLinkedInBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["linkedin", "sign up", "sign in", "log in", "join linkedin", "security verification"]
            .contains { lower == $0 || lower.hasPrefix($0 + " ") }
    }

    /// Generic LinkedIn descriptions that carry no information about the person.
    static func isLinkedInBoilerplateDescription(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("profile on linkedin") && lower.contains("professional community")
    }

    /// "Name (@handle) • Instagram photos and videos" / "Name (@handle) | TikTok" → "Name".
    public static func nameBeforeHandle(_ title: String) -> String? {
        let name = HTMLScanner.firstMatch(#"^\s*(.*?)\s*\(@[^)]+\)"#, in: title)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    /// Instagram og:description, expected as
    /// "12.4K Followers, 312 Following, 208 Posts - See Instagram photos and videos from Name (@handle)"
    /// optionally followed by `on Instagram: "bio"`.
    public static func parseInstagramDescription(_ text: String) -> (followers: Int?, bio: String?) {
        let followers = HTMLScanner.firstMatch(#"([\d.,]+\s*[KkMmBb]?)\s+Followers"#, in: text).flatMap(parseCount)
        let bio = HTMLScanner.firstMatch(#"on Instagram:\s*"(.*)"\s*$"#, in: text, options: [.dotMatchesLineSeparators])
        if followers == nil && bio == nil { return (nil, text) }
        return (followers, bio)
    }

    /// TikTok og:description, expected as
    /// "Name (@handle) on TikTok | 1.2M Likes. 48.5K Followers. Bio. Watch the latest video from Name (@handle)."
    public static func parseTikTokDescription(_ text: String) -> (followers: Int?, bio: String?) {
        let followers = HTMLScanner.firstMatch(#"([\d.,]+\s*[KkMmBb]?)\s+Followers"#, in: text).flatMap(parseCount)
        guard followers != nil else { return (nil, text) }
        let bio = HTMLScanner.firstMatch(#"Followers\.\s*(.*?)\s*Watch the latest video"#, in: text, options: [.dotMatchesLineSeparators])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (followers, bio?.isEmpty == false ? bio : nil)
    }

    /// "1,234" → 1234, "12.3K" → 12300, "1.2M" → 1200000.
    public static func parseCount(_ text: String) -> Int? {
        var digits = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        var multiplier = 1.0
        switch digits.last?.lowercased() {
        case "k": multiplier = 1_000
        case "m": multiplier = 1_000_000
        case "b": multiplier = 1_000_000_000
        default: break
        }
        if multiplier != 1 { digits.removeLast() }
        guard let value = Double(digits.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Int((value * multiplier).rounded())
    }
}
