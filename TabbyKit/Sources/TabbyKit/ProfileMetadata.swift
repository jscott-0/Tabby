import Foundation

/// Profile fields gathered by extraction tiers 2+, with the tier each field came from.
public struct ProfileMetadata: Equatable, Sendable {
    public enum Field: String, CaseIterable, Sendable {
        case name, headline, bio, avatarURL, links, followerCount
    }

    public var name: String?
    public var headline: String?
    public var bio: String?
    public var avatarURL: URL?
    public var links: [URL] = []
    public var emails: [String] = []
    public var followerCount: Int?
    public var sources: [Field: ExtractionTier] = [:]

    public init() {}

    public func has(_ field: Field) -> Bool {
        switch field {
        case .name: name != nil
        case .headline: headline != nil
        case .bio: bio != nil
        case .avatarURL: avatarURL != nil
        case .links: !links.isEmpty
        case .followerCount: followerCount != nil
        }
    }

    /// Complete = name, avatar and some description; partial = anything; failed = nothing.
    public var status: ExtractionStatus {
        if name != nil, avatarURL != nil, bio != nil || headline != nil { return .complete }
        return Field.allCases.contains { has($0) } ? .partial : .failed
    }

    /// Takes each field from `other` when this one lacks it, or always for fields in `preferring`.
    public mutating func merge(_ other: ProfileMetadata, tier: ExtractionTier, preferring: Set<Field> = []) {
        for field in Field.allCases where other.has(field) && (!has(field) || preferring.contains(field)) {
            switch field {
            case .name: name = other.name
            case .headline: headline = other.headline
            case .bio: bio = other.bio
            case .avatarURL: avatarURL = other.avatarURL
            case .links: links = other.links
            case .followerCount: followerCount = other.followerCount
            }
            sources[field] = tier
        }
        for email in other.emails where !emails.contains(email) {
            emails.append(email)
        }
    }

    /// Adds links not already present, comparing without scheme, "www." or trailing slash.
    public mutating func addLinks(_ newLinks: [URL], tier: ExtractionTier) {
        var seen = Set(links.map(Self.linkKey))
        for link in newLinks where seen.insert(Self.linkKey(link)).inserted {
            links.append(link)
            if sources[.links] == nil { sources[.links] = tier }
        }
    }

    static func linkKey(_ url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return host + path + (url.query.map { "?" + $0 } ?? "")
    }
}
