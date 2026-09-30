import Foundation

public enum Platform: String, Codable, CaseIterable, Sendable {
    case linkedin, instagram, tiktok, other
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
}
