import SwiftUI
import TabbyKit

/// Debug screen: per-platform hit rates and recent extractions from the share sheet, the Add
/// sheet, retries and re-fetches. "Share" exports the same markdown table as `tabby-extract`,
/// so the Phase 0 numbers can be checked on a device.
struct ExtractionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var attempts = ExtractionLog.shared.attempts

    var body: some View {
        NavigationStack {
            List {
                if attempts.isEmpty {
                    ContentUnavailableView("No extractions yet", systemImage: "list.bullet.clipboard",
                                           description: Text("Share or add a profile, then come back."))
                } else {
                    Section("Hit rate by platform") {
                        ForEach(ExtractionStats.rows(attempts)) { row in
                            StatsRow(row: row)
                        }
                    }
                    Section("Recent") {
                        ForEach(attempts) { attempt in
                            AttemptRow(attempt: attempt)
                        }
                    }
                }
            }
            .navigationTitle("Extraction log")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { attempts = ExtractionLog.shared.attempts }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: report) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(attempts.isEmpty)
                    Button(role: .destructive) {
                        ExtractionLog.shared.clear()
                        attempts = []
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(attempts.isEmpty)
                }
            }
        }
    }

    private var report: String {
        let lines = attempts.map { attempt in
            let fields = ProfileMetadata.Field.allCases
                .compactMap { field in attempt.fields[field].map { "\(field.rawValue)=t\($0.rawValue)" } }
                .joined(separator: " ")
            return "- \(attempt.platform.rawValue) \(attempt.handle): \(attempt.status.rawValue)"
                + (attempt.httpStatus.map { " HTTP \($0)" } ?? "")
                + " [\(attempt.source.rawValue)] \(fields)"
        }
        return ExtractionStats.markdownTable(attempts) + "\n\n" + lines.joined(separator: "\n")
    }
}

private struct StatsRow: View {
    let row: ExtractionStats.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PlatformBadge(platform: row.platform, showsName: true)
                Spacer()
                Text("\(row.attempts) \(row.attempts == 1 ? "share" : "shares")")
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(ProfileMetadata.Field.allCases, id: \.self) { field in
                    let rate = row.fieldRates[field] ?? 0
                    GridRow {
                        Text(field.rawValue).font(.caption)
                        ProgressView(value: rate)
                        Text(ExtractionStats.percent(rate))
                            .font(.caption.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            Text(["complete", "partial", "failed"].map { name in
                let status = ExtractionStatus(rawValue: name) ?? .failed
                return "\(name) \(ExtractionStats.percent(row.statusRates[status] ?? 0))"
            }.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AttemptRow: View {
    let attempt: ExtractionAttempt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PlatformBadge(platform: attempt.platform)
                Text(attempt.handle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(attempt.status.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(attempt.status == .failed ? Color.red : attempt.status == .complete ? Color.green : Color.orange)
            }
            Text(fieldsSummary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack {
                Text(attempt.source.rawValue)
                if let http = attempt.httpStatus { Text("HTTP \(http)") }
                if let error = attempt.error { Text(error).lineLimit(1) }
                Spacer()
                Text(attempt.date, format: .relative(presentation: .named))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var fieldsSummary: String {
        let filled = ProfileMetadata.Field.allCases.compactMap { field in
            attempt.fields[field].map { "\(field.rawValue):t\($0.rawValue)" }
        }
        return filled.isEmpty ? "no fields" : filled.joined(separator: " ")
    }
}

#Preview {
    ExtractionLogView()
}
