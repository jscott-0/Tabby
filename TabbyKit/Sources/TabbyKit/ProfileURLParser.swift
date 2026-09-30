import Foundation

/// Tier 1: everything we can learn from the shared URL alone, offline.
public struct ParsedProfileURL: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case profile
        /// A post, reel or video. `authorHandle` is set when the URL names its author.
        case post(authorHandle: String?)
        /// vm.tiktok.com / tiktok.com/t/ links; resolve by following redirects.
        case shortLink
        case unknown
    }

    public var platform: Platform
    /// Normalized handle (Instagram and TikTok lowercased; LinkedIn slug as given).
    public var handle: String?
    /// Canonical profile URL for `.profile`, otherwise the original URL.
    public var url: URL
    public var kind: Kind

    public init(platform: Platform, handle: String?, url: URL, kind: Kind) {
        self.platform = platform
        self.handle = handle
        self.url = url
        self.kind = kind
    }

    /// Dedup key: platform + lowercased handle.
    public var dedupKey: String? {
        handle.map { "\(platform.rawValue):\($0.lowercased())" }
    }

    /// For a post whose author is known, the author's profile.
    public var authorProfile: ParsedProfileURL? {
        guard case .post(let author?) = kind else { return nil }
        return ProfileURLParser.profile(platform: platform, handle: author)
    }
}

public enum ProfileURLParser {
    private static let instagramPostPaths: Set<String> = ["p", "reel", "reels", "tv"]
    private static let instagramReserved: Set<String> = [
        "p", "reel", "reels", "tv", "stories", "explore", "accounts", "direct", "about", "legal", "developer",
    ]

    /// The first http(s) URL in shared text such as "Check out X's profile https://…".
    public static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), isWeb(url), url.host != nil {
            return url
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector.matches(in: trimmed, range: range).lazy.compactMap(\.url).first(where: isWeb)
    }

    public static func parse(_ url: URL) -> ParsedProfileURL {
        guard let host = url.host?.lowercased() else { return unknown(.other, url) }
        let path = url.path.split(separator: "/").map(String.init)

        if host.matchesDomain("linkedin.com") { return parseLinkedIn(path, url) }
        if host.matchesDomain("instagram.com") || host.matchesDomain("instagr.am") { return parseInstagram(path, url) }
        if host == "vm.tiktok.com" || host == "vt.tiktok.com" {
            return ParsedProfileURL(platform: .tiktok, handle: nil, url: url, kind: .shortLink)
        }
        if host.matchesDomain("tiktok.com") { return parseTikTok(path, url) }
        return unknown(.other, url)
    }

    /// Builds the canonical profile for a known handle.
    public static func profile(platform: Platform, handle: String) -> ParsedProfileURL? {
        let escaped = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        let string: String
        switch platform {
        case .linkedin: string = "https://www.linkedin.com/in/\(escaped)/"
        case .instagram: string = "https://www.instagram.com/\(escaped)/"
        case .tiktok: string = "https://www.tiktok.com/@\(escaped)"
        case .other: return nil
        }
        guard let url = URL(string: string) else { return nil }
        return ParsedProfileURL(platform: platform, handle: handle, url: url, kind: .profile)
    }

    // MARK: - Platforms

    private static func parseLinkedIn(_ path: [String], _ url: URL) -> ParsedProfileURL {
        guard let first = path.first?.lowercased() else { return unknown(.linkedin, url) }
        if first == "in", path.count >= 2, !path[1].isEmpty,
           let profile = profile(platform: .linkedin, handle: path[1]) {
            return profile
        }
        if first == "posts", path.count >= 2 {
            // linkedin.com/posts/{author-slug}_{title}-activity-{id}
            let author = path[1].split(separator: "_").first.map(String.init)
            return ParsedProfileURL(platform: .linkedin, handle: nil, url: url, kind: .post(authorHandle: author))
        }
        return unknown(.linkedin, url)
    }

    private static func parseInstagram(_ path: [String], _ url: URL) -> ParsedProfileURL {
        guard let first = path.first else { return unknown(.instagram, url) }
        let lower = first.lowercased()

        if lower == "stories" {
            let author = path.count >= 2 && path[1].lowercased() != "highlights" ? path[1].lowercased() : nil
            return ParsedProfileURL(platform: .instagram, handle: nil, url: url, kind: .post(authorHandle: author))
        }
        if instagramPostPaths.contains(lower) {
            return ParsedProfileURL(platform: .instagram, handle: nil, url: url, kind: .post(authorHandle: nil))
        }
        guard !instagramReserved.contains(lower), isValidHandle(lower, maxLength: 30) else {
            return unknown(.instagram, url)
        }
        // instagram.com/{handle}/p/{code} and /reel/{code}
        if path.count >= 2, instagramPostPaths.contains(path[1].lowercased()) {
            return ParsedProfileURL(platform: .instagram, handle: nil, url: url, kind: .post(authorHandle: lower))
        }
        return profile(platform: .instagram, handle: lower) ?? unknown(.instagram, url)
    }

    private static func parseTikTok(_ path: [String], _ url: URL) -> ParsedProfileURL {
        guard let first = path.first else { return unknown(.tiktok, url) }
        if first.lowercased() == "t" {
            return ParsedProfileURL(platform: .tiktok, handle: nil, url: url, kind: .shortLink)
        }
        guard first.hasPrefix("@") else { return unknown(.tiktok, url) }
        let handle = String(first.dropFirst()).lowercased()
        guard isValidHandle(handle, maxLength: 24) else { return unknown(.tiktok, url) }
        if path.count >= 2, ["video", "photo"].contains(path[1].lowercased()) {
            return ParsedProfileURL(platform: .tiktok, handle: nil, url: url, kind: .post(authorHandle: handle))
        }
        return profile(platform: .tiktok, handle: handle) ?? unknown(.tiktok, url)
    }

    // MARK: - Helpers

    private static func unknown(_ platform: Platform, _ url: URL) -> ParsedProfileURL {
        ParsedProfileURL(platform: platform, handle: nil, url: url, kind: .unknown)
    }

    private static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func isValidHandle(_ handle: String, maxLength: Int) -> Bool {
        guard !handle.isEmpty, handle.count <= maxLength else { return false }
        return handle.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_")
        }
    }
}

extension String {
    func matchesDomain(_ domain: String) -> Bool {
        self == domain || hasSuffix("." + domain)
    }
}
