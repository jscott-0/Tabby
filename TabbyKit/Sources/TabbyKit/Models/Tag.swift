import Foundation
import SwiftData

/// Many-to-many with Person. Names are unique case-insensitively, enforced by `TabbyStore`.
@Model
public final class Tag {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Index into the app's tag palette (`TagPalette.count` colors).
    public var colorIndex: Int = 0
    public var emoji: String?
    public var createdAt: Date = Date.now
    public var useCount: Int = 0
    /// Drives tag ordering in the share sheet.
    public var lastUsedAt: Date?
    public var people: [Person]? = []
    /// Spaces whose rule uses this tag.
    public var spaces: [Space]? = []

    public init(name: String, colorIndex: Int, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }
}

public enum TagPalette {
    /// Number of tag / Space colors. The UI maps `colorIndex % count` to a color.
    public static let count = 10
}

extension Tag {
    public var peopleCount: Int { people?.count ?? 0 }

    /// "Recently used tags first, then alphabetical": the `recentCount` most recently used, then the rest by name.
    public static func shareSheetOrder(_ tags: [Tag], recentCount: Int = 6) -> [Tag] {
        let recent = tags
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(recentCount)
        let recentIDs = Set(recent.map(\.id))
        let rest = tags
            .filter { !recentIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Array(recent) + rest
    }

    /// Trims, drops a leading "#" and collapses inner whitespace.
    public static func normalizedName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix("#") { name.removeFirst() }
        return name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
