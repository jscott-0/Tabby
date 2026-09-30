import Foundation

/// Local search over the denormalized `Person.searchText`.
public enum SearchText {
    /// Case-, diacritic- and width-insensitive form used on both sides of a match.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whitespace-separated query terms; a leading "#" is dropped so "#designer" finds the tag.
    public static func terms(_ query: String) -> [String] {
        fold(query)
            .split(whereSeparator: \.isWhitespace)
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : String($0) }
            .filter { !$0.isEmpty }
    }

    /// Every term must appear somewhere.
    public static func matches(_ searchText: String, terms: [String]) -> Bool {
        terms.allSatisfy { searchText.contains($0) }
    }

    public static func filter(_ people: [Person], query: String) -> [Person] {
        let queryTerms = Self.terms(query)
        guard !queryTerms.isEmpty else { return people }
        return people.filter { matches($0.searchText, terms: queryTerms) }
    }

    /// The text a Person is found by: name, handles, headlines, bios, note and tag names.
    public static func make(for person: Person) -> String {
        var parts = [person.displayName, person.note]
        for account in person.accounts ?? [] {
            parts += [account.handle, "@" + account.handle, account.headline, account.bio]
        }
        parts += (person.tags ?? []).map(\.name)
        return fold(parts.filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

/// `tabby://person/{id}` links used by the share extension's "Open in Tabby".
public enum DeepLink {
    public static let scheme = "tabby"

    public static func url(forPerson id: UUID) -> URL {
        URL(string: "\(scheme)://person/\(id.uuidString)")!
    }

    public static func personID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "person" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
