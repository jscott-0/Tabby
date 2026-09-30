import Foundation

/// Minimal HTML scanning for meta tags and script bodies. Not a general HTML parser.
public struct HTMLMeta: Equatable, Sendable {
    /// Lowercased `property` / `name` → first `content` seen, entity-decoded.
    public var properties: [String: String]
    public var title: String?

    public subscript(key: String) -> String? {
        properties[key.lowercased()].flatMap { $0.isEmpty ? nil : $0 }
    }
}

public enum HTMLScanner {
    public static func meta(in html: String) -> HTMLMeta {
        var properties: [String: String] = [:]
        for attributes in tags(named: "meta", in: html) {
            guard let content = attributes["content"],
                  let key = attributes["property"] ?? attributes["name"] else { continue }
            let normalized = key.lowercased()
            if properties[normalized] == nil {
                properties[normalized] = HTMLEntities.decode(content)
            }
        }
        let title = firstMatch(#"<title\b[^>]*>(.*?)</title>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators])
            .map { HTMLEntities.decode($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return HTMLMeta(properties: properties, title: title)
    }

    /// Bodies of `<script>` tags whose attributes match all of `attributes` (values compared case-insensitively).
    public static func scripts(in html: String, matching attributes: [String: String] = [:]) -> [String] {
        let pattern = #"<script\b([^>]*)>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let attrs = parseAttributes(ns.substring(with: match.range(at: 1)))
            for (key, value) in attributes where attrs[key]?.lowercased() != value.lowercased() {
                return nil
            }
            return ns.substring(with: match.range(at: 2))
        }
    }

    static func tags(named name: String, in html: String) -> [[String: String]] {
        guard let regex = try? NSRegularExpression(pattern: "<\(name)\\b([^>]*)>", options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            parseAttributes(ns.substring(with: $0.range(at: 1)))
        }
    }

    static func parseAttributes(_ text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([a-zA-Z_:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) else {
            return [:]
        }
        let ns = text as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            result[name] = ns.substring(with: valueRange)
        }
        return result
    }

    /// First capture group of `pattern`.
    static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&"),
              let regex = try? NSRegularExpression(pattern: "&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let entity = ns.substring(with: match.range(at: 1))
            result += replacement(for: entity) ?? ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func replacement(for entity: String) -> String? {
        if entity.hasPrefix("#") {
            let digits = entity.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            return value.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        return named[entity.lowercased()]
    }
}
