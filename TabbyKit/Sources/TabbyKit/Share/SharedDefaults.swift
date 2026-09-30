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
}
