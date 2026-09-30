import Foundation
import SwiftData

/// The card the user sees. Owns one or more Accounts (v1 creates one) so the same human
/// on several platforms can be merged later without a migration.
///
/// CloudKit-ready: no unique constraints, every property optional or defaulted, relationships optional.
@Model
public final class Person {
    public var id: UUID = UUID()
    public var displayName: String = ""
    /// Downscaled avatar (400 px JPEG). Falls back to the primary Account's `avatarURL` when nil.
    @Attribute(.externalStorage) public var avatarData: Data?
    /// "Why I saved them".
    public var note: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var lastViewedAt: Date?
    /// Folded name, handles, headlines, bios, note and tag names. Maintained by `TabbyStore`.
    public var searchText: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Account.person)
    public var accounts: [Account]? = []

    @Relationship(inverse: \Tag.people)
    public var tags: [Tag]? = []

    public init(displayName: String = "", note: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.displayName = displayName
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Person {
    /// The first Account added; drives the platform badge and default avatar.
    public var primaryAccount: Account? {
        (accounts ?? []).min { $0.createdAt < $1.createdAt }
    }

    public var sortedAccounts: [Account] {
        (accounts ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    public var sortedTags: [Tag] {
        (tags ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Display name, else "@handle", else "Unnamed".
    public var title: String {
        if !displayName.isEmpty { return displayName }
        if let handle = primaryAccount?.handle, !handle.isEmpty { return "@" + handle }
        return "Unnamed"
    }

    public var headline: String { primaryAccount?.headline ?? "" }

    public var avatarURL: URL? { primaryAccount?.avatarURL }

    /// Extraction never succeeded for any Account.
    public var needsInfo: Bool {
        let accounts = accounts ?? []
        return !accounts.isEmpty && accounts.allSatisfy { $0.extractionStatus == .pending || $0.extractionStatus == .failed }
    }
}
