import Foundation
import OSLog
import SwiftData

/// The one SwiftData store, shared by the app and the share extension through the App Group.
public enum TabbyContainer {
    public static let appGroupID = "group.com.tabbyapp.tabby"

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
