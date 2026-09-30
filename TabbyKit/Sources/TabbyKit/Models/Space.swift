import Foundation
import SwiftData

/// A smart folder. Contents are computed from `rule`, never stored.
@Model
public final class Space {
    public var id: UUID = UUID()
    public var name: String = ""
    /// SF Symbol name.
    public var icon: String = "folder"
    public var colorIndex: Int = 0
    /// ALL of the rule tags when true, ANY when false.
    public var matchAll: Bool = false
    /// Comma-separated `Platform` raw values; empty means every platform.
    public var platformFilterRaw: String = ""
    @Relationship(inverse: \Tag.spaces)
    public var ruleTags: [Tag]? = []
    public var sortOrder: Int = 0
    public var isPinned: Bool = false
    public var createdAt: Date = Date.now

    public init(name: String, icon: String, colorIndex: Int, sortOrder: Int, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension Space {
    public var platformFilter: Set<Platform> {
        get { Set(platformFilterRaw.split(separator: ",").compactMap { Platform(rawValue: String($0)) }) }
        set { platformFilterRaw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    public var sortedRuleTags: [Tag] {
        (ruleTags ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var rule: SpaceRule {
        SpaceRule(matchAll: matchAll, tagIDs: Set((ruleTags ?? []).map(\.id)), platforms: platformFilter)
    }

    /// "All of designer, hardware · Instagram" style summary.
    public var ruleSummary: String {
        let names = sortedRuleTags.map(\.name)
        guard !names.isEmpty else { return "No tags yet" }
        var summary = (matchAll ? "All of " : "Any of ") + names.joined(separator: ", ")
        let filter = platformFilter
        let platforms = Platform.allCases.filter { filter.contains($0) }.map(\.displayName)
        if !platforms.isEmpty { summary += " · " + platforms.joined(separator: ", ") }
        return summary
    }
}
