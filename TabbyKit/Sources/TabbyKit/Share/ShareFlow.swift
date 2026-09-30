import Foundation
import Observation
import SwiftData

/// The share sheet's state: tier 1 parse (instant) → editable preview → tiers 2–3 → save.
/// UI-free so it can be tested; the extension renders it.
@MainActor
@Observable
public final class ShareFlow {
    public enum Phase: Equatable {
        case loading
        case noLink
        case editing
        case saved(personID: UUID, name: String)
    }

    /// The three things teaching mode asks for before the first import.
    public enum TeachingItem: CaseIterable, Sendable {
        case details, tag, note

        public var title: String {
            switch self {
            case .details: "Check their details"
            case .tag: "Add a tag"
            case .note: "Why you saved them"
            }
        }
    }

    public private(set) var phase: Phase = .loading
    public var draft = PersonDraft(platform: .other, handle: "", profileURL: nil)
    public private(set) var parsed: ParsedProfileURL?
    /// Set when this profile is already saved; saving merges into that Person.
    public private(set) var existingName: String?
    public private(set) var isImporting = false
    public var saveError: String?
    /// The first share-sheet save runs as a short lesson: a checklist and an Import button.
    public private(set) var isTeaching: Bool
    /// Set by the UI once the preview has been looked at (scrolled past or edited).
    public var hasConfirmedDetails = false
    /// A free account at its limit: this save becomes a locked draft in Waiting to unlock.
    public private(set) var willLock = false
    public private(set) var savedAsDraft = false

    private let store: TabbyStore
    private let service: EnrichmentService
    private let sharedDefaults: SharedDefaults
    private let log: ExtractionLog?

    /// No page renderer here: tier 4 is too slow and memory-hungry for an extension.
    public init(
        context: ModelContext,
        service: EnrichmentService = EnrichmentService(),
        sharedDefaults: SharedDefaults = .shared,
        log: ExtractionLog? = .shared
    ) {
        self.store = TabbyStore(context: context)
        self.service = service
        self.sharedDefaults = sharedDefaults
        self.log = log
        self.isTeaching = !sharedDefaults.hasCompletedFirstSave
    }

    public func isDone(_ item: TeachingItem) -> Bool {
        switch item {
        case .details: hasConfirmedDetails
        case .tag: !draft.tagIDs.isEmpty
        case .note: !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Teaching mode enables Import once the checklist is done; Skip saves without it.
    public var canSave: Bool {
        !isTeaching || TeachingItem.allCases.allSatisfy(isDone)
    }

    public var saveButtonTitle: String {
        if willLock { return "Save as draft" }
        return isTeaching ? "Import" : "Save"
    }

    /// Leaves teaching mode and saves as-is.
    public func skipTeaching() {
        isTeaching = false
        save()
    }

    /// Shown above the preview when the link isn't a profile.
    public var notice: String? {
        guard let parsed else { return nil }
        switch parsed.kind {
        case .profile, .shortLink:
            return nil
        case .post(let author):
            guard let author else { return "This looks like a post, not a profile. It will be saved as a link." }
            return "This looks like a post, not a profile. Saving its author, @\(author)."
        case .unknown:
            return "This isn't a LinkedIn, Instagram or TikTok profile. It will be saved as a link."
        }
    }

    public func start(with url: URL?) async {
        guard let url else {
            phase = .noLink
            return
        }
        let parsed = ProfileURLParser.parse(url)
        self.parsed = parsed
        draft = PersonDraft(parsed: parsed)
        adoptExisting()
        willLock = store.wouldLock(draft, entitlement: sharedDefaults.entitlement)
        phase = .editing
        await importMetadata()
    }

    /// Tiers 2–3, then the avatar (downscaled). Only fills fields the user hasn't typed into;
    /// failure leaves tier 1 in place. Saving doesn't wait for the avatar.
    public func importMetadata() async {
        guard let parsed else { return }
        let target = parsed.authorProfile ?? parsed
        guard target.kind == .profile || target.kind == .shortLink else { return }
        isImporting = true
        let result = await service.enrich(target, downloadAvatar: false)
        isImporting = false
        log?.append(ExtractionAttempt(result.extraction, source: .shareSheet))
        guard phase == .editing else { return }
        draft.apply(result.extraction)
        adoptExisting()
        willLock = store.wouldLock(draft, entitlement: sharedDefaults.entitlement)

        guard draft.avatarData == nil, let avatarURL = draft.avatarURL else { return }
        let avatar = await AvatarProcessor.download(avatarURL, client: service.client)
        if phase == .editing, draft.avatarData == nil { draft.avatarData = avatar }
    }

    /// A duplicate starts from what's saved: its tags pre-selected, its name kept.
    private func adoptExisting() {
        guard existingName == nil, let person = store.existingPerson(for: draft) else { return }
        existingName = person.title
        draft.tagIDs.formUnion((person.tags ?? []).map(\.id))
        if draft.displayName.isEmpty { draft.displayName = person.displayName }
    }

    @discardableResult
    public func createTag(named name: String) -> Tag? {
        let tag = store.findOrCreateTag(named: name)
        sharedDefaults.markExternalWrite()
        return tag
    }

    public func save() {
        do {
            let outcome = try store.save(draft, entitlement: sharedDefaults.entitlement)
            sharedDefaults.markExternalWrite()
            sharedDefaults.hasCompletedFirstSave = true
            savedAsDraft = outcome.isLockedDraft
            phase = .saved(personID: outcome.person.id, name: outcome.person.title)
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// "Open in Tabby": remembers the person so the app shows them on its next launch
    /// even if opening the app from the extension fails. Returns the deep link to open.
    public func requestOpen() -> URL? {
        guard case .saved(let id, _) = phase else { return nil }
        sharedDefaults.setPendingOpen(id)
        if savedAsDraft { sharedDefaults.setPendingPaywall(.slotLimit) }
        return DeepLink.url(forPerson: id)
    }
}
