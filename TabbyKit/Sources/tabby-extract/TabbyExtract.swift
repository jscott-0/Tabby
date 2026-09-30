import Foundation
import TabbyKit

/// Phase 0 spike: fetch real profile URLs, print what tiers 1–3 return, and a hit-rate table per platform.
///
///     swift run --package-path TabbyKit tabby-extract --file urls.txt --fixtures TabbyKit/Tests/TabbyKitTests/Fixtures
@main
struct TabbyExtract {
    static let usage = """
    usage: tabby-extract [--file urls.txt] [--fixtures DIR] [URL ...]
      --file      one URL (or shared text containing a URL) per line; # comments allowed
      --fixtures  save each fetched page as DIR/<platform>/<handle>.html
    """

    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var inputs: [String] = []
        var fixturesDirectory: URL?

        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--file":
                guard let path = arguments.first, let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                    fail("cannot read --file")
                }
                arguments.removeFirst()
                inputs += text.split(whereSeparator: \.isNewline).map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
            case "--fixtures":
                guard let path = arguments.first else { fail("--fixtures needs a directory") }
                arguments.removeFirst()
                fixturesDirectory = URL(fileURLWithPath: path, isDirectory: true)
            case "-h", "--help":
                print(usage)
                return
            default:
                inputs.append(argument)
            }
        }
        guard !inputs.isEmpty else { fail(usage) }

        let fetcher = MetadataFetcher()
        var results: [ExtractionResult] = []
        for (index, input) in inputs.enumerated() {
            guard let url = ProfileURLParser.firstURL(in: input) else {
                print("✗ no URL in: \(input)")
                continue
            }
            let result = await fetcher.fetch(ProfileURLParser.parse(url))
            report(result)
            if let fixturesDirectory, let html = result.html { save(html, for: result.parsed, in: fixturesDirectory) }
            results.append(result)
            // Be polite: at most one request per second.
            if index < inputs.count - 1 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        print(summary(results))
    }

    static func report(_ result: ExtractionResult) {
        let m = result.metadata
        func show(_ field: ProfileMetadata.Field, _ value: String?) -> String {
            guard let value else { return "  \(field.rawValue): —" }
            let tier = m.sources[field].map { " [t\($0.rawValue)]" } ?? ""
            return "  \(field.rawValue)\(tier): \(value.replacingOccurrences(of: "\n", with: " ⏎ "))"
        }
        print("""
        \(result.status == .failed ? "✗" : "✓") \(result.parsed.platform.rawValue) @\(result.parsed.handle ?? "?") \
        — \(result.status.rawValue)\(result.httpStatus.map { " (HTTP \($0))" } ?? "")\(result.error.map { " \($0)" } ?? "")
        \(show(.name, m.name))
        \(show(.headline, m.headline))
        \(show(.bio, m.bio))
        \(show(.avatarURL, m.avatarURL?.absoluteString))
        \(show(.links, m.links.isEmpty ? nil : m.links.map(\.absoluteString).joined(separator: ", ")))
        \(show(.followerCount, m.followerCount.map { String($0) }))
        """)
    }

    /// Markdown table: % of shares per platform where each field was filled.
    static func summary(_ results: [ExtractionResult]) -> String {
        let fields = ProfileMetadata.Field.allCases
        var lines = [
            "",
            "| Platform | Shares | " + fields.map(\.rawValue).joined(separator: " | ") + " | complete | partial | failed |",
            "|" + String(repeating: "---|", count: fields.count + 5),
        ]
        for platform in Platform.allCases {
            let group = results.filter { $0.parsed.platform == platform }
            guard !group.isEmpty else { continue }
            func percent(_ count: Int) -> String { "\(count * 100 / group.count)%" }
            let fieldCells = fields.map { field in percent(group.filter { $0.metadata.has(field) }.count) }
            let statusCells = [ExtractionStatus.complete, .partial, .failed].map { status in
                percent(group.filter { $0.status == status }.count)
            }
            lines.append("| \(platform.rawValue) | \(group.count) | " + (fieldCells + statusCells).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    static func save(_ html: String, for parsed: ParsedProfileURL, in directory: URL) {
        let folder = directory.appendingPathComponent(parsed.platform.rawValue, isDirectory: true)
        let name = (parsed.handle ?? "unknown").replacingOccurrences(of: "/", with: "_")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try html.write(to: folder.appendingPathComponent("\(name).html"), atomically: true, encoding: .utf8)
        } catch {
            print("  ! could not save fixture: \(error.localizedDescription)")
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
