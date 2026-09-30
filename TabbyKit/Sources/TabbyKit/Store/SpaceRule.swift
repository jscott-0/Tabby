import Foundation

/// What decides membership, snapshotted from a Person so rules evaluate without touching SwiftData.
public struct PersonFacts {
    public let person: Person
    public let tagIDs: Set<UUID>
    public let platforms: Set<Platform>
    public let createdAt: Date
    public let needsInfo: Bool

    public init(_ person: Person) {
        self.person = person
        self.tagIDs = Set((person.tags ?? []).map(\.id))
        self.platforms = Set((person.accounts ?? []).map(\.platform))
        self.createdAt = person.createdAt
        self.needsInfo = person.needsInfo
    }
}

/// A Space rule: ANY or ALL of a set of tags, optionally filtered by platform.
/// A rule with no tags matches nobody (the UI prompts to edit it).
public struct SpaceRule: Equatable, Sendable {
    public var matchAll: Bool
    public var tagIDs: Set<UUID>
    /// Empty means every platform.
    public var platforms: Set<Platform>

    public init(matchAll: Bool, tagIDs: Set<UUID>, platforms: Set<Platform> = []) {
        self.matchAll = matchAll
        self.tagIDs = tagIDs
        self.platforms = platforms
    }

    public var isEmpty: Bool { tagIDs.isEmpty }

    public func matches(tagIDs personTags: Set<UUID>, platforms personPlatforms: Set<Platform>) -> Bool {
        guard !tagIDs.isEmpty else { return false }
        if !platforms.isEmpty, platforms.isDisjoint(with: personPlatforms) { return false }
        return matchAll ? tagIDs.isSubset(of: personTags) : !tagIDs.isDisjoint(with: personTags)
    }

    public func matches(_ facts: PersonFacts) -> Bool {
        matches(tagIDs: facts.tagIDs, platforms: facts.platforms)
    }
}

/// Spaces every user has, listed before their own.
public enum BuiltInSpace: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all, recentlyAdded, untagged, needsInfo

    public var id: String { rawValue }

    /// How far back "Recently added" looks.
    public static let recentWindow: TimeInterval = 30 * 24 * 60 * 60

    public var title: String {
        switch self {
        case .all: "All"
        case .recentlyAdded: "Recently added"
        case .untagged: "Untagged"
        case .needsInfo: "Needs info"
        }
    }

    /// SF Symbol name.
    public var icon: String {
        switch self {
        case .all: "person.2.fill"
        case .recentlyAdded: "clock.fill"
        case .untagged: "tag.slash.fill"
        case .needsInfo: "exclamationmark.circle.fill"
        }
    }

    public var emptyMessage: String {
        switch self {
        case .all: "Share a profile to Tabby to save your first person."
        case .recentlyAdded: "Nobody added in the last 30 days."
        case .untagged: "Everyone has at least one tag."
        case .needsInfo: "Every saved profile has its details."
        }
    }

    public func contains(_ facts: PersonFacts, now: Date = .now) -> Bool {
        switch self {
        case .all: true
        case .recentlyAdded: now.timeIntervalSince(facts.createdAt) <= Self.recentWindow
        case .untagged: facts.tagIDs.isEmpty
        case .needsInfo: facts.needsInfo
        }
    }
}

/// A route-safe reference to either kind of Space.
public enum SpaceRef: Hashable, Sendable {
    case builtIn(BuiltInSpace)
    case custom(UUID)
}

public enum PersonSort: String, CaseIterable, Identifiable, Sendable {
    case recent, name, lastViewed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recent: "Recently added"
        case .name: "Name"
        case .lastViewed: "Last viewed"
        }
    }

    public func sorted(_ people: [Person]) -> [Person] {
        switch self {
        case .recent:
            people.sorted { $0.createdAt > $1.createdAt }
        case .name:
            people.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .lastViewed:
            people.sorted { ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast) }
        }
    }
}

extension Array where Element == PersonFacts {
    public func members(of builtIn: BuiltInSpace, now: Date = .now) -> [Person] {
        filter { builtIn.contains($0, now: now) }.map(\.person)
    }

    public func members(of rule: SpaceRule) -> [Person] {
        filter { rule.matches($0) }.map(\.person)
    }
}
