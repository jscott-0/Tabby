import Foundation
import OSLog
import SwiftData

/// The one SwiftData store, shared by the app and the share extension through the App Group.
public enum TabbyContainer {
    /// From the `TabbyAppGroup` Info.plist key (set from `TABBY_APP_GROUP` in Config/Tabby.xcconfig),
    /// so a bundle ID change is one line. Falls back to the default outside the app (tests, CLI).
    public static let appGroupID: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "TabbyAppGroup") as? String,
           !value.isEmpty, !value.contains("$(") {
            return value
        }
        return "group.com.tabbyapp.tabby"
    }()

    public static let schema = Schema([Person.self, Account.self, Tag.self, Space.self])

    static let logger = Logger(subsystem: "com.tabbyapp.tabby", category: "store")

    /// `Tabby.store` in the App Group container. Falls back to Application Support when the
    /// App Group entitlement is missing (unsigned builds), which unshares it from the extension.
    public static var storeURL: URL {
        let directory: URL
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            directory = group
        } else {
            logger.error("App Group \(appGroupID, privacy: .public) unavailable; using Application Support")
            directory = URL.applicationSupportDirectory
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Tabby.store")
    }

    /// CloudKit stays off until iCloud sync ships (P1).
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration("Tabby", schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
