import Foundation

public enum OnboardingStep: String, Codable, CaseIterable, Sendable {
    case welcome, account, interests, firstSuggestion, awaitingFirstSave
}

/// Who's signed in. Local for now; the backend (Phase 4) will own accounts and entitlements.
public struct AccountProfile: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Sendable { case apple, email }

    /// Apple's stable user identifier, or a generated one for email sign-up.
    public var id: String
    public var method: Method
    public var email: String?
    public var name: String?

    public init(id: String, method: Method, email: String? = nil, name: String? = nil) {
        self.id = id
        self.method = method
        self.email = email
        self.name = name
    }
}

public struct InterestCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// SF Symbol name.
    public let icon: String
}

public struct SuggestedCreator: Identifiable, Hashable, Sendable {
    public let name: String
    public let platform: Platform
    public let handle: String
    public let categoryID: String

    public var id: String { "\(platform.rawValue):\(handle)" }

    public var profileURL: URL? { ProfileURLParser.profile(platform: platform, handle: handle)?.url }
}

/// Onboarding's categories and suggested creators.
///
/// PLACEHOLDER: large public brand accounts so the flow works on a device before the curated
/// launch list exists (an open question in the spec). Replace with the real list.
public enum OnboardingCatalog {
    public static let categories: [InterestCategory] = [
        InterestCategory(id: "design", title: "Design", icon: "paintbrush.pointed.fill"),
        InterestCategory(id: "fitness", title: "Fitness", icon: "figure.run"),
        InterestCategory(id: "food", title: "Food", icon: "fork.knife"),
        InterestCategory(id: "tech", title: "Tech & science", icon: "cpu"),
        InterestCategory(id: "fashion", title: "Fashion", icon: "tshirt.fill"),
        InterestCategory(id: "travel", title: "Travel & nature", icon: "leaf.fill"),
        InterestCategory(id: "learning", title: "Learning", icon: "graduationcap.fill"),
        InterestCategory(id: "news", title: "News", icon: "newspaper.fill"),
    ]

    public static let creators: [SuggestedCreator] = [
        SuggestedCreator(name: "Adobe", platform: .instagram, handle: "adobe", categoryID: "design"),
        SuggestedCreator(name: "Nike", platform: .instagram, handle: "nike", categoryID: "fitness"),
        SuggestedCreator(name: "NBA", platform: .tiktok, handle: "nba", categoryID: "fitness"),
        SuggestedCreator(name: "Tastemade", platform: .instagram, handle: "tastemade", categoryID: "food"),
        SuggestedCreator(name: "Bon Appétit", platform: .instagram, handle: "bonappetitmag", categoryID: "food"),
        SuggestedCreator(name: "NASA", platform: .instagram, handle: "nasa", categoryID: "tech"),
        SuggestedCreator(name: "NASA", platform: .tiktok, handle: "nasa", categoryID: "tech"),
        SuggestedCreator(name: "Vogue", platform: .instagram, handle: "voguemagazine", categoryID: "fashion"),
        SuggestedCreator(name: "National Geographic", platform: .instagram, handle: "natgeo", categoryID: "travel"),
        SuggestedCreator(name: "National Geographic", platform: .tiktok, handle: "natgeo", categoryID: "travel"),
        SuggestedCreator(name: "Duolingo", platform: .tiktok, handle: "duolingo", categoryID: "learning"),
        SuggestedCreator(name: "The Washington Post", platform: .tiktok, handle: "washingtonpost", categoryID: "news"),
    ]

    /// Creators in the picked categories (all of them when none are picked).
    public static func creators(in categoryIDs: Set<String>) -> [SuggestedCreator] {
        categoryIDs.isEmpty ? creators : creators.filter { categoryIDs.contains($0.categoryID) }
    }

    /// The one to try first: a picked creator, else one from a picked category, else the default.
    public static func firstSuggestion(pickedCreatorIDs: [String], categoryIDs: Set<String>) -> SuggestedCreator {
        if let picked = pickedCreatorIDs.lazy.compactMap({ id in creators.first { $0.id == id } }).first {
            return picked
        }
        return creators(in: categoryIDs).first ?? creators[0]
    }

    public static func category(id: String) -> InterestCategory? {
        categories.first { $0.id == id }
    }
}

/// Measures whether the demo sells: entries, time spent, and purchases within 24 h of a demo.
public struct DemoLog {
    public struct Session: Codable, Equatable, Sendable {
        public var start: Date
        public var end: Date?
    }

    private static let sessionsKey = "demoSessions"
    private static let purchaseKey = "purchasesAfterDemo"
    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Kept next to the other App Group flags.
    public init(_ shared: SharedDefaults) {
        self.init(defaults: shared.defaults)
    }

    public var sessions: [Session] {
        defaults.data(forKey: Self.sessionsKey).flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []
    }

    /// Purchases made within 24 h after a demo session ended.
    public var purchasesAfterDemo: Int { defaults.integer(forKey: Self.purchaseKey) }

    public var totalTimeInDemo: TimeInterval {
        sessions.reduce(0) { $0 + (($1.end ?? $1.start).timeIntervalSince($1.start)) }
    }

    public func enter(at date: Date = .now) {
        write(sessions + [Session(start: date)])
    }

    public func exit(at date: Date = .now) {
        var all = sessions
        guard let last = all.indices.last, all[last].end == nil else { return }
        all[last].end = date
        write(all)
    }

    public func recordPurchase(at date: Date = .now) {
        let recent = sessions.contains { date.timeIntervalSince($0.end ?? $0.start) <= 24 * 60 * 60 }
        if recent { defaults.set(purchasesAfterDemo + 1, forKey: Self.purchaseKey) }
    }

    private func write(_ sessions: [Session]) {
        defaults.set(try? JSONEncoder().encode(sessions), forKey: Self.sessionsKey)
    }
}
