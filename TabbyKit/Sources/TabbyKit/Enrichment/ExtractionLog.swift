import Foundation

/// One extraction, for the on-device debug log and hit-rate table.
public struct ExtractionAttempt: Codable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case shareSheet, addSheet, retry, refetch, cli
    }

    public var id = UUID()
    public var date: Date
    public var source: Source
    public var platform: Platform
    public var handle: String
    public var status: ExtractionStatus
    public var httpStatus: Int?
    public var error: String?
    /// Which tier filled each field.
    public var fields: [ProfileMetadata.Field: ExtractionTier]

    public init(_ result: ExtractionResult, source: Source, date: Date = .now) {
        self.date = date
        self.source = source
        self.platform = result.parsed.platform
        self.handle = result.parsed.handle ?? result.parsed.url.absoluteString
        self.status = result.status
        self.httpStatus = result.httpStatus
        self.error = result.error
        self.fields = result.metadata.sources.filter { result.metadata.has($0.key) }
    }
}

/// The last `capacity` attempts, kept in the App Group's defaults so the share extension's
/// attempts show up in the app's debug screen too.
public struct ExtractionLog {
    public static let shared = ExtractionLog(defaults: SharedDefaults.shared.defaults)
    public static let capacity = 200
    private static let key = "extractionLog"

    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Newest first.
    public var attempts: [ExtractionAttempt] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ExtractionAttempt].self, from: data)) ?? []
    }

    public func append(_ attempt: ExtractionAttempt) {
        let updated = Array(([attempt] + attempts).prefix(Self.capacity))
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// Per-platform hit rates, as printed by `tabby-extract` and shown in the app's debug screen.
public enum ExtractionStats {
    public struct Row: Identifiable, Sendable {
        public let platform: Platform
        public let attempts: Int
        /// 0...1 per field.
        public let fieldRates: [ProfileMetadata.Field: Double]
        public let statusRates: [ExtractionStatus: Double]
        public var id: Platform { platform }
    }

    public static func rows(_ attempts: [ExtractionAttempt]) -> [Row] {
        Platform.allCases.compactMap { platform in
            let group = attempts.filter { $0.platform == platform }
            guard !group.isEmpty else { return nil }
            let total = Double(group.count)
            var fieldRates: [ProfileMetadata.Field: Double] = [:]
            for field in ProfileMetadata.Field.allCases {
                fieldRates[field] = Double(group.filter { $0.fields[field] != nil }.count) / total
            }
            var statusRates: [ExtractionStatus: Double] = [:]
            for status in [ExtractionStatus.complete, .partial, .failed] {
                statusRates[status] = Double(group.filter { $0.status == status }.count) / total
            }
            return Row(platform: platform, attempts: group.count, fieldRates: fieldRates, statusRates: statusRates)
        }
    }

    /// A markdown table, one row per platform.
    public static func markdownTable(_ attempts: [ExtractionAttempt]) -> String {
        let fields = ProfileMetadata.Field.allCases
        let statuses = [ExtractionStatus.complete, .partial, .failed]
        var lines = [
            "| Platform | Shares | " + (fields.map(\.rawValue) + statuses.map(\.rawValue)).joined(separator: " | ") + " |",
            "|" + String(repeating: "---|", count: fields.count + statuses.count + 2),
        ]
        for row in rows(attempts) {
            let cells = fields.map { percent(row.fieldRates[$0] ?? 0) } + statuses.map { percent(row.statusRates[$0] ?? 0) }
            lines.append("| \(row.platform.rawValue) | \(row.attempts) | " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    public static func percent(_ rate: Double) -> String {
        "\(Int((rate * 100).rounded()))%"
    }
}
