import Foundation

/// What a user has bought. One-time Unlimited Tabs or the Pro subscription.
public enum Entitlement: String, Codable, CaseIterable, Comparable, Sendable {
    case free, unlimitedTabs, pro

    public var hasUnlimitedTabs: Bool { self != .free }
    public var isPro: Bool { self == .pro }

    private var rank: Int {
        switch self {
        case .free: 0
        case .unlimitedTabs: 1
        case .pro: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public enum PaywallPolicy {
    /// Free users keep this many People; more saves become locked drafts.
    public static let freeTabLimit = 1

    public static func canAddPerson(unlockedCount: Int, entitlement: Entitlement) -> Bool {
        entitlement.hasUnlimitedTabs || unlockedCount < freeTabLimit
    }
}

/// Why the paywall opened; picks which option it opens on.
public enum PaywallTrigger: String, Codable, Identifiable, Sendable {
    /// Right after onboarding's first save.
    case firstSave
    /// A save past the free limit became a locked draft.
    case slotLimit
    /// The "1 of 1 free Tab used" banner.
    case banner
    /// Tapped a draft in Waiting to unlock.
    case lockedDraft
    /// A Pro-only feature.
    case proFeature
    /// "Unlock" in the demo banner, or leaving the demo.
    case demo

    public var id: String { rawValue }

    /// Slot limits default to Unlimited Tabs; Pro features to Pro.
    public var defaultsToPro: Bool {
        switch self {
        case .proFeature, .demo, .firstSave: true
        case .slotLimit, .banner, .lockedDraft: false
        }
    }
}

/// US storefronts may link out to web checkout (no Apple commission as of mid-2026, under a court
/// order that may change); everywhere else uses in-app purchase. Web checkout needs the backend
/// that grants the entitlement from the payment webhook, so it stays off until a URL is configured.
public enum PurchaseRoute: Equatable, Sendable {
    case appStore
    case webCheckout(URL)
}

public enum PurchaseRouter {
    public static func route(storefrontCountryCode: String?, webCheckoutBase: URL?, accountID: String?, productID: String) -> PurchaseRoute {
        guard storefrontCountryCode == "USA", let webCheckoutBase, let accountID, !accountID.isEmpty,
              var components = URLComponents(url: webCheckoutBase, resolvingAgainstBaseURL: false) else {
            return .appStore
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "account", value: accountID),
            URLQueryItem(name: "product", value: productID),
        ]
        return components.url.map(PurchaseRoute.webCheckout) ?? .appStore
    }
}
