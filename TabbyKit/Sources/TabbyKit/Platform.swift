import Foundation

public enum Platform: String, Codable, CaseIterable, Sendable {
    case linkedin, instagram, tiktok, other

    /// The three social platforms, in display order.
    public static let social: [Platform] = [.linkedin, .instagram, .tiktok]

    public var displayName: String {
        switch self {
        case .linkedin: "LinkedIn"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .other: "Web"
        }
    }
}

/// Where a piece of profile data came from. See "Profile extraction" in docs/PLAN.md.
public enum ExtractionTier: Int, Codable, Comparable, Sendable {
    case urlParse = 1
    case metaTags = 2
    case embeddedJSON = 3
    case renderedPage = 4
    case screenshot = 5

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum ExtractionStatus: String, Codable, Sendable {
    case pending, complete, partial, failed

    /// Not complete: retried by the main app, and failed / pending ones show in "Needs info".
    public var needsRetry: Bool { self != .complete }

    /// Ordering used when merging a re-share into an existing Account: never downgrade.
    var rank: Int {
        switch self {
        case .failed: 0
        case .pending: 1
        case .partial: 2
        case .complete: 3
        }
    }
}
