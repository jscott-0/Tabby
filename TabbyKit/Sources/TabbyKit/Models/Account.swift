import Foundation
import SwiftData

/// One social profile. Dedup key = platform + lowercased handle, enforced in code by `TabbyStore`.
@Model
public final class Account {
    public var id: UUID = UUID()
    public var platformRaw: String = Platform.other.rawValue
    public var handle: String = ""
    public var dedupKey: String = ""
    public var profileURLString: String = ""
    public var headline: String = ""
    public var bio: String = ""
    /// Newline-separated URLs.
    public var linksText: String = ""
    public var followerCount: Int?
    public var avatarURLString: String?
    public var extractionStatusRaw: String = ExtractionStatus.pending.rawValue
    /// JSON-encoded `ProfileMetadata` from the last fetch.
    @Attribute(.externalStorage) public var rawMetadata: Data?
    public var fetchedAt: Date?
    /// Automatic retries so far (see `RetryQueue`); reset when the user re-fetches.
    public var fetchAttempts: Int = 0
    public var lastAttemptAt: Date?
    public var createdAt: Date = Date.now
    public var person: Person?

    public init(platform: Platform, handle: String, profileURL: URL?, createdAt: Date = .now) {
        self.id = UUID()
        self.platformRaw = platform.rawValue
        self.handle = handle
        self.profileURLString = profileURL?.absoluteString ?? ""
        self.dedupKey = Account.dedupKey(platform: platform, handle: handle, url: profileURL) ?? ""
        self.createdAt = createdAt
    }
}

extension Account {
    public var platform: Platform {
        get { Platform(rawValue: platformRaw) ?? .other }
        set { platformRaw = newValue.rawValue }
    }

    public var extractionStatus: ExtractionStatus {
        get { ExtractionStatus(rawValue: extractionStatusRaw) ?? .pending }
        set { extractionStatusRaw = newValue.rawValue }
    }

    public var profileURL: URL? {
        get { URL(string: profileURLString) }
        set { profileURLString = newValue?.absoluteString ?? "" }
    }

    public var avatarURL: URL? {
        get { avatarURLString.flatMap { URL(string: $0) } }
        set { avatarURLString = newValue?.absoluteString }
    }

    public var links: [URL] {
        get { linksText.split(separator: "\n").compactMap { URL(string: String($0)) } }
        set { linksText = newValue.map(\.absoluteString).joined(separator: "\n") }
    }

    /// "@handle" for the social platforms, the host for web pages.
    public var displayHandle: String {
        switch platform {
        case .linkedin, .instagram, .tiktok: "@" + handle
        case .other: profileURL?.host ?? handle
        }
    }

    /// `platform:lowercased-handle` for social profiles, `other:<host/path>` for web pages.
    public static func dedupKey(platform: Platform, handle: String, url: URL?) -> String? {
        switch platform {
        case .linkedin, .instagram, .tiktok:
            let normalized = handle.trimmingCharacters(in: .whitespaces).lowercased()
            return normalized.isEmpty ? nil : "\(platform.rawValue):\(normalized)"
        case .other:
            guard let url, let host = url.host?.lowercased() else { return nil }
            var path = url.path
            while path.hasSuffix("/") { path.removeLast() }
            let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return "other:\(bareHost)\(path.lowercased())"
        }
    }
}
