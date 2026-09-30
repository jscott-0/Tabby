import Foundation

/// The editable value behind the share sheet, the Add sheet and the Person editor.
/// `TabbyStore.save(_:)` turns it into a Person, merging into an existing one on a duplicate.
public struct PersonDraft: Equatable, Sendable {
    public var platform: Platform
    public var handle: String
    public var profileURL: URL?
    public var displayName: String = ""
    public var headline: String = ""
    public var bio: String = ""
    public var links: [URL] = []
    public var followerCount: Int?
    public var avatarURL: URL?
    public var avatarData: Data?
    public var note: String = ""
    /// The Person's full tag set after saving. When editing a duplicate, callers pre-select its existing tags.
    public var tagIDs: Set<UUID> = []
    public var extractionStatus: ExtractionStatus = .pending
    public var rawMetadata: Data?
    public var fetchedAt: Date?

    public init(platform: Platform, handle: String, profileURL: URL?) {
        self.platform = platform
        self.handle = handle
        self.profileURL = profileURL
    }

    /// Tier 1 only. A post with a known author becomes that author's profile;
    /// anything else that is not a profile is saved as a web page (platform "other").
    public init(parsed: ParsedProfileURL) {
        let target = parsed.authorProfile ?? parsed
        if target.kind == .profile, let handle = target.handle {
            self.init(platform: target.platform, handle: handle, profileURL: target.url)
        } else {
            self.init(platform: .other, handle: "", profileURL: parsed.url)
        }
    }

    /// Editing an existing Person (its primary Account).
    public init(person: Person) {
        let account = person.primaryAccount
        self.init(platform: account?.platform ?? .other, handle: account?.handle ?? "", profileURL: account?.profileURL)
        displayName = person.displayName
        headline = account?.headline ?? ""
        bio = account?.bio ?? ""
        links = account?.links ?? []
        followerCount = account?.followerCount
        avatarURL = account?.avatarURL
        note = person.note
        tagIDs = Set((person.tags ?? []).map(\.id))
        extractionStatus = account?.extractionStatus ?? .pending
    }

    public var dedupKey: String? {
        Account.dedupKey(platform: platform, handle: handle, url: profileURL)
    }

    /// Fills fields that are still empty, so nothing the user typed is overwritten.
    public mutating func apply(_ result: ExtractionResult, at date: Date = .now) {
        if result.parsed.kind == .profile, let resolvedHandle = result.parsed.handle, platform == .other || handle.isEmpty {
            platform = result.parsed.platform
            handle = resolvedHandle
            profileURL = result.parsed.url
        }
        let metadata = result.metadata
        if displayName.isEmpty, let name = metadata.name { displayName = name }
        if headline.isEmpty, let value = metadata.headline { headline = value }
        if bio.isEmpty, let value = metadata.bio { bio = value }
        if links.isEmpty { links = metadata.links }
        if followerCount == nil { followerCount = metadata.followerCount }
        if avatarURL == nil { avatarURL = metadata.avatarURL }
        extractionStatus = result.status
        rawMetadata = try? JSONEncoder().encode(metadata)
        fetchedAt = date
    }
}
