import Foundation

/// Small flags the app and the share extension pass through the App Group's UserDefaults.
public struct SharedDefaults {
    public static let shared = SharedDefaults(defaults: UserDefaults(suiteName: TabbyContainer.appGroupID) ?? .standard)

    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private enum Key {
        static let lastExternalWrite = "lastExternalWrite"
        static let pendingOpenPersonID = "pendingOpenPersonID"
        static let pendingPaywall = "pendingPaywall"
        static let entitlement = "entitlement"
        static let hasCompletedFirstSave = "hasCompletedFirstSave"
        static let onboardingFinished = "onboardingFinished"
        static let onboardingStep = "onboardingStep"
        static let interests = "interests"
        static let pickedCreators = "pickedCreators"
        static let account = "account"
    }

    /// When the share extension last wrote to the store. The app reopens its store when this moves.
    public var lastExternalWrite: Date? {
        defaults.object(forKey: Key.lastExternalWrite) as? Date
    }

    public func markExternalWrite(at date: Date = .now) {
        defaults.set(date, forKey: Key.lastExternalWrite)
    }

    /// A save the user tapped "Open in Tabby" on. Kept until the app shows it, in case opening
    /// the app from the extension fails.
    public var pendingOpenPersonID: UUID? {
        defaults.string(forKey: Key.pendingOpenPersonID).flatMap { UUID(uuidString: $0) }
    }

    public func setPendingOpen(_ id: UUID?) {
        defaults.set(id?.uuidString, forKey: Key.pendingOpenPersonID)
    }

    /// Returns the pending open and clears it.
    public func takePendingOpen() -> UUID? {
        let id = pendingOpenPersonID
        if id != nil { setPendingOpen(nil) }
        return id
    }

    // MARK: - Paywall

    /// Set by the extension when a save became a locked draft; the app opens the paywall next.
    public var pendingPaywall: PaywallTrigger? {
        defaults.string(forKey: Key.pendingPaywall).flatMap(PaywallTrigger.init(rawValue:))
    }

    public func setPendingPaywall(_ trigger: PaywallTrigger?) {
        defaults.set(trigger?.rawValue, forKey: Key.pendingPaywall)
    }

    public func takePendingPaywall() -> PaywallTrigger? {
        let trigger = pendingPaywall
        if trigger != nil { setPendingPaywall(nil) }
        return trigger
    }

    /// Cached by the app from StoreKit so the extension knows the free limit without asking.
    public var entitlement: Entitlement {
        get { defaults.string(forKey: Key.entitlement).flatMap(Entitlement.init(rawValue:)) ?? .free }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.entitlement) }
    }

    // MARK: - Onboarding

    /// False until the first share-sheet import; the share sheet runs in teaching mode until then.
    public var hasCompletedFirstSave: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstSave) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasCompletedFirstSave) }
    }

    public var onboardingFinished: Bool {
        get { defaults.bool(forKey: Key.onboardingFinished) }
        nonmutating set { defaults.set(newValue, forKey: Key.onboardingFinished) }
    }

    /// Where onboarding resumes if the app is relaunched part-way through.
    public var onboardingStep: OnboardingStep {
        get { defaults.string(forKey: Key.onboardingStep).flatMap(OnboardingStep.init(rawValue:)) ?? .welcome }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.onboardingStep) }
    }

    /// Picked interest categories (their names become suggested tags).
    public var interests: [String] {
        get { defaults.stringArray(forKey: Key.interests) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.interests) }
    }

    /// Picked onboarding creators, as dedup keys.
    public var pickedCreators: [String] {
        get { defaults.stringArray(forKey: Key.pickedCreators) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.pickedCreators) }
    }

    public var account: AccountProfile? {
        get { defaults.data(forKey: Key.account).flatMap { try? JSONDecoder().decode(AccountProfile.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.account) }
    }
}
