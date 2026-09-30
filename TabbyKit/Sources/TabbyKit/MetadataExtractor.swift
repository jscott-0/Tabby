import Foundation

/// Tiers 2 and 3 over already-fetched HTML. Pure, so it runs against saved fixtures in tests.
public enum MetadataExtractor {
    public static func extract(html: String, platform: Platform) -> ProfileMetadata {
        var result = ProfileMetadata()
        result.merge(metaTags(html, platform), tier: .metaTags)
        // Embedded JSON carries full bios and exact counts, so it wins over og: snippets for those.
        result.merge(embeddedJSON(html, platform), tier: .embeddedJSON, preferring: [.bio, .headline, .followerCount])
        if let bio = result.bio {
            let tier = result.sources[.bio] ?? .metaTags
            result.addLinks(BioParser.links(in: bio), tier: tier)
            for email in BioParser.emails(in: bio) where !result.emails.contains(email) {
                result.emails.append(email)
            }
        }
        return result
    }

    // MARK: - Tier 2: og: / meta tags

    static func metaTags(_ html: String, _ platform: Platform) -> ProfileMetadata {
        let meta = HTMLScanner.meta(in: html)
        var result = ProfileMetadata()
        let title = meta["og:title"] ?? meta["twitter:title"] ?? meta.title
        let description = meta["og:description"] ?? meta["description"] ?? meta["twitter:description"]
        result.avatarURL = (meta["og:image"] ?? meta["twitter:image"]).flatMap { URL(string: $0) }

        switch platform {
        case .linkedin:
            // No person title means a login wall: its image and description are LinkedIn's, not the person's.
            guard let title, let parsed = BioParser.parseLinkedInTitle(title) else { return ProfileMetadata() }
            result.name = parsed.name
            result.headline = parsed.headline
            if let description, !BioParser.isLinkedInBoilerplateDescription(description) {
                result.bio = description
            }
        case .instagram:
            result.name = title.flatMap(BioParser.nameBeforeHandle)
            if let description {
                let parsed = BioParser.parseInstagramDescription(description)
                result.followerCount = parsed.followers
                result.bio = parsed.bio
            }
        case .tiktok:
            result.name = title.flatMap(BioParser.nameBeforeHandle)
            if let description {
                let parsed = BioParser.parseTikTokDescription(description)
                result.followerCount = parsed.followers
                result.bio = parsed.bio
            }
        case .other:
            result.name = title
            result.bio = description
        }
        return result
    }

    // MARK: - Tier 3: embedded JSON

    static func embeddedJSON(_ html: String, _ platform: Platform) -> ProfileMetadata {
        var result = ProfileMetadata()
        switch platform {
        case .tiktok: result.merge(tiktokUser(html), tier: .embeddedJSON)
        case .instagram: result.merge(instagramUser(html), tier: .embeddedJSON)
        case .linkedin, .other: break
        }
        result.merge(jsonLDPerson(html), tier: .embeddedJSON)
        return result
    }

    /// TikTok's `__UNIVERSAL_DATA_FOR_REHYDRATION__` script, falling back to the older `SIGI_STATE`.
    static func tiktokUser(_ html: String) -> ProfileMetadata {
        var user: [String: Any]?
        var stats: [String: Any]?
        if let json = HTMLScanner.scripts(in: html, matching: ["id": "__UNIVERSAL_DATA_FOR_REHYDRATION__"]).first.flatMap(parseJSON) {
            let userInfo = dig(json, ["__DEFAULT_SCOPE__", "webapp.user-detail", "userInfo"])
            user = dig(userInfo, ["user"]) as? [String: Any]
            stats = dig(userInfo, ["stats"]) as? [String: Any]
        } else if let json = HTMLScanner.scripts(in: html, matching: ["id": "SIGI_STATE"]).first.flatMap(parseJSON) {
            user = (dig(json, ["UserModule", "users"]) as? [String: Any])?.values.first as? [String: Any]
            stats = (dig(json, ["UserModule", "stats"]) as? [String: Any])?.values.first as? [String: Any]
        }

        var result = ProfileMetadata()
        guard let user else { return result }
        result.name = nonEmpty(user["nickname"])
        result.bio = nonEmpty(user["signature"])
        result.avatarURL = nonEmpty(user["avatarLarger"] ?? user["avatarMedium"]).flatMap { URL(string: $0) }
        if let link = nonEmpty(dig(user, ["bioLink", "link"])).flatMap(webURL) {
            result.links = [link]
        }
        result.followerCount = stats?["followerCount"] as? Int
        return result
    }

    /// Instagram user JSON when the page embeds it (often it does not).
    static func instagramUser(_ html: String) -> ProfileMetadata {
        var result = ProfileMetadata()
        result.bio = jsonString(forKey: "biography", in: html).flatMap { nonEmpty($0) }
        result.name = jsonString(forKey: "full_name", in: html).flatMap { nonEmpty($0) }
        result.avatarURL = (jsonString(forKey: "profile_pic_url_hd", in: html) ?? jsonString(forKey: "profile_pic_url", in: html))
            .flatMap { URL(string: $0) }
        if let link = jsonString(forKey: "external_url", in: html).flatMap(webURL) {
            result.links = [link]
        }
        result.followerCount = HTMLScanner.firstMatch(#""edge_followed_by"\s*:\s*\{\s*"count"\s*:\s*(\d+)"#, in: html)
            .flatMap { Int($0) }
        return result
    }

    /// schema.org Person in `application/ld+json` (LinkedIn public profiles, portfolio sites).
    static func jsonLDPerson(_ html: String) -> ProfileMetadata {
        var result = ProfileMetadata()
        let candidates = HTMLScanner.scripts(in: html, matching: ["type": "application/ld+json"])
            .compactMap(parseJSON)
            .flatMap(jsonLDObjects)
        guard let person = candidates.first(where: { isType($0, "Person") })
            ?? candidates.compactMap({ $0["mainEntity"] as? [String: Any] }).first(where: { isType($0, "Person") })
        else { return result }

        result.name = nonEmpty(person["name"])
        result.bio = nonEmpty(person["description"])
        let jobTitle = nonEmpty(person["jobTitle"]) ?? (person["jobTitle"] as? [Any])?.compactMap { nonEmpty($0) }.first
        let company = (person["worksFor"] as? [[String: Any]])?.compactMap { nonEmpty($0["name"]) }.first
            ?? nonEmpty(dig(person, ["worksFor", "name"]))
        result.headline = [jobTitle, company].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        let image = person["image"]
        result.avatarURL = (nonEmpty(image) ?? nonEmpty(dig(image, ["contentUrl"])) ?? nonEmpty(dig(image, ["url"])))
            .flatMap { URL(string: $0) }
        return result
    }

    // MARK: - JSON helpers

    private static func parseJSON(_ text: String) -> Any? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func dig(_ value: Any?, _ path: [String]) -> Any? {
        path.reduce(value) { ($0 as? [String: Any])?[$1] }
    }

    private static func jsonLDObjects(_ value: Any) -> [[String: Any]] {
        if let array = value as? [Any] { return array.flatMap(jsonLDObjects) }
        guard let object = value as? [String: Any] else { return [] }
        return [object] + ((object["@graph"] as? [Any])?.flatMap(jsonLDObjects) ?? [])
    }

    private static func isType(_ object: [String: Any], _ type: String) -> Bool {
        if let value = object["@type"] as? String { return value == type }
        return (object["@type"] as? [String])?.contains(type) ?? false
    }

    /// Value of the first `"key":"…"` JSON string anywhere in the page, unescaped.
    private static func jsonString(forKey key: String, in html: String) -> String? {
        guard let raw = HTMLScanner.firstMatch("\"\(key)\"\\s*:\\s*(\"(?:\\\\.|[^\"\\\\])*\")", in: html) else { return nil }
        return parseJSON(raw) as? String
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func webURL(_ string: String) -> URL? {
        let candidate = string.contains("://") ? string : "https://" + string
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return url
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
