import Foundation
import SwiftData

/// "Never lose a save": profiles whose extraction didn't complete (or whose avatar never
/// downloaded) are retried by the main app, a few at a time, at most `maxAttempts` times and
/// no more than once per `minimumInterval`. Complete profiles are never refreshed automatically.
@MainActor
public final class RetryQueue {
    public static let maxAttempts = 3
    public static let minimumInterval: TimeInterval = 60 * 60
    public static let batchSize = 10

    private let store: TabbyStore
    private let service: EnrichmentService
    private let log: ExtractionLog?

    public init(context: ModelContext, service: EnrichmentService, log: ExtractionLog? = .shared) {
        self.store = TabbyStore(context: context)
        self.service = service
        self.log = log
    }

    /// Social profiles still missing details, newest first.
    public func candidates(now: Date = .now) -> [Account] {
        let accounts = (try? store.context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return Array(accounts.filter { isDue($0, now: now) }.prefix(Self.batchSize))
    }

    func isDue(_ account: Account, now: Date) -> Bool {
        guard account.platform != .other, !account.handle.isEmpty, account.person != nil else { return false }
        guard !SampleData.isSampleHandle(account.handle) else { return false }
        guard account.fetchAttempts < Self.maxAttempts else { return false }
        if let last = account.lastAttemptAt, now.timeIntervalSince(last) < Self.minimumInterval { return false }
        let missingAvatar = account.person?.avatarData == nil && account.avatarURL != nil
        return account.extractionStatus.needsRetry || missingAvatar
    }

    /// Returns how many profiles were retried. Stops early when the task is cancelled.
    @discardableResult
    public func run(now: Date = .now) async -> Int {
        var retried = 0
        for account in candidates(now: now) {
            guard !Task.isCancelled else { break }
            guard let parsed = ProfileURLParser.profile(platform: account.platform, handle: account.handle) else { continue }
            account.fetchAttempts += 1
            account.lastAttemptAt = now
            store.persist()
            let result = await service.enrich(parsed)
            guard !account.isDeleted, account.modelContext != nil else { continue }
            store.applyEnrichment(result, to: account)
            log?.append(ExtractionAttempt(result.extraction, source: .retry))
            retried += 1
        }
        return retried
    }
}
