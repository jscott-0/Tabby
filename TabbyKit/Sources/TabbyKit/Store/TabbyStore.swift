import Foundation
import SwiftData

public enum TabbyStoreError: Error, Equatable {
    case emptyName
    case tagNameTaken
}

public struct SaveOutcome {
    public let person: Person
    /// The profile was already in Tabby and the save merged into it.
    public let wasExisting: Bool
}

/// Every write to the store goes through here, so dedup, tag bookkeeping and
/// `Person.searchText` stay consistent between the app and the share extension.
@MainActor
public final class TabbyStore {
    public let context: ModelContext
    /// A context doesn't keep its container alive, and using it after the container is freed traps.
    private let container: ModelContainer

    public init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    /// Saves pending changes, logging instead of throwing.
    public func persist() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            TabbyContainer.logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - People

    public func person(id: UUID) -> Person? {
        var descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public func allPeople() -> [Person] {
        (try? context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    /// The Person already holding this profile, if any.
    public func existingPerson(for draft: PersonDraft) -> Person? {
        draft.dedupKey.flatMap { account(dedupKey: $0) }?.person
    }

    func account(dedupKey key: String) -> Account? {
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.dedupKey == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Creates a Person, or merges into the one that already has this profile:
    /// non-empty fields win, tags become `draft.tagIDs`, and a new note is appended with the date.
    @discardableResult
    public func save(_ draft: PersonDraft, at date: Date = .now) throws -> SaveOutcome {
        let existingAccount = draft.dedupKey.flatMap { self.account(dedupKey: $0) }
        let person: Person
        let account: Account
        let wasExisting: Bool
        if let existingAccount, let existingPerson = existingAccount.person {
            person = existingPerson
            account = existingAccount
            wasExisting = true
        } else {
            if let orphan = existingAccount { context.delete(orphan) }
            person = Person(createdAt: date)
            account = Account(platform: draft.platform, handle: draft.handle, profileURL: draft.profileURL, createdAt: date)
            context.insert(person)
            context.insert(account)
            account.person = person
            wasExisting = false
        }

        let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { person.displayName = name }
        if let avatarData = draft.avatarData { person.avatarData = avatarData }
        fill(account, from: draft, isNew: !wasExisting)
        applyTags(draft.tagIDs, to: person, at: date)

        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty, !person.note.contains(note) {
            if person.note.isEmpty {
                person.note = note
            } else {
                person.note += "\n\n\(date.formatted(date: .abbreviated, time: .omitted)) — \(note)"
            }
        }

        person.updatedAt = date
        refreshSearchText(person)
        try context.save()
        return SaveOutcome(person: person, wasExisting: wasExisting)
    }

    /// Applies the Person editor: replaces name, note, tags and the primary Account's text fields.
    public func update(_ person: Person, with draft: PersonDraft, at date: Date = .now) {
        person.displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        person.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account = person.primaryAccount {
            account.headline = draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            account.bio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
            account.links = draft.links
        }
        applyTags(draft.tagIDs, to: person, at: date)
        person.updatedAt = date
        refreshSearchText(person)
        persist()
    }

    /// Merges a fetch into an Account. Fills empty fields only, unless `overwrite` (an explicit
    /// re-fetch), which replaces the Account's fetched fields but never the user's name, note or tags.
    public func applyEnrichment(_ result: EnrichmentResult, to account: Account, overwrite: Bool = false, at date: Date = .now) {
        guard let person = account.person else { return }
        let extraction = result.extraction
        if extraction.status != .failed {
            let metadata = extraction.metadata
            if person.displayName.isEmpty, let name = metadata.name { person.displayName = name }
            if let headline = metadata.headline, overwrite || account.headline.isEmpty { account.headline = headline }
            if let bio = metadata.bio, overwrite || account.bio.isEmpty { account.bio = bio }
            if !metadata.links.isEmpty, overwrite || account.links.isEmpty { account.links = metadata.links }
            if let count = metadata.followerCount { account.followerCount = count }
            if let avatarURL = metadata.avatarURL { account.avatarURL = avatarURL }
            account.rawMetadata = try? JSONEncoder().encode(metadata)
            account.fetchedAt = date
        }
        if let avatarData = result.avatarData { person.avatarData = avatarData }
        if overwrite || extraction.status.rank >= account.extractionStatus.rank {
            account.extractionStatus = extraction.status
        }
        if overwrite {
            account.fetchAttempts = 0
            account.lastAttemptAt = nil
        }
        person.updatedAt = date
        refreshSearchText(person)
        persist()
    }

    public func setTags(_ tagIDs: Set<UUID>, for person: Person) {
        applyTags(tagIDs, to: person, at: .now)
        person.updatedAt = .now
        refreshSearchText(person)
        persist()
    }

    /// Bulk tag: adds the tags to everyone, keeping their existing ones.
    public func addTags(_ tagIDs: Set<UUID>, to people: [Person]) {
        let now = Date.now
        for person in people {
            let current = Set((person.tags ?? []).map(\.id))
            applyTags(current.union(tagIDs), to: person, at: now)
            person.updatedAt = now
            refreshSearchText(person)
        }
        persist()
    }

    public func delete(_ people: [Person]) {
        for person in people { context.delete(person) }
        persist()
    }

    public func markViewed(_ person: Person) {
        person.lastViewedAt = .now
        persist()
    }

    public func refreshSearchText(_ person: Person) {
        let text = SearchText.make(for: person)
        if person.searchText != text { person.searchText = text }
    }

    private func fill(_ account: Account, from draft: PersonDraft, isNew: Bool) {
        if !draft.handle.isEmpty { account.handle = draft.handle }
        if let url = draft.profileURL { account.profileURL = url }
        if !draft.headline.isEmpty { account.headline = draft.headline }
        if !draft.bio.isEmpty { account.bio = draft.bio }
        if !draft.links.isEmpty { account.links = draft.links }
        if let count = draft.followerCount { account.followerCount = count }
        if let url = draft.avatarURL { account.avatarURL = url }
        if isNew || draft.extractionStatus.rank >= account.extractionStatus.rank {
            account.extractionStatus = draft.extractionStatus
        }
        if let raw = draft.rawMetadata { account.rawMetadata = raw }
        if let fetchedAt = draft.fetchedAt { account.fetchedAt = fetchedAt }
    }

    /// Sets the person's tags, counting a use for each newly applied one.
    private func applyTags(_ tagIDs: Set<UUID>, to person: Person, at date: Date) {
        let current = Set((person.tags ?? []).map(\.id))
        let wanted = tags(withIDs: tagIDs)
        for tag in wanted where !current.contains(tag.id) {
            tag.useCount += 1
            tag.lastUsedAt = date
        }
        if Set(wanted.map(\.id)) != current {
            person.tags = wanted
        }
    }

    // MARK: - Tags

    public func allTags() -> [Tag] {
        ((try? context.fetch(FetchDescriptor<Tag>())) ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func tags(withIDs ids: Set<UUID>) -> [Tag] {
        guard !ids.isEmpty else { return [] }
        return allTags().filter { ids.contains($0.id) }
    }

    /// Case- and diacritic-insensitive lookup.
    public func tag(named raw: String) -> Tag? {
        let name = Tag.normalizedName(raw)
        guard !name.isEmpty else { return nil }
        return allTags().first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// The tag with this name, or a new one in the least-used palette color.
    @discardableResult
    public func findOrCreateTag(named raw: String, at date: Date = .now) -> Tag? {
        let name = Tag.normalizedName(raw)
        guard !name.isEmpty else { return nil }
        if let existing = self.tag(named: name) { return existing }
        let tag = Tag(name: name, colorIndex: nextColorIndex(), createdAt: date)
        context.insert(tag)
        persist()
        return tag
    }

    func nextColorIndex() -> Int {
        var counts = Array(repeating: 0, count: TagPalette.count)
        for tag in allTags() {
            counts[((tag.colorIndex % TagPalette.count) + TagPalette.count) % TagPalette.count] += 1
        }
        return counts.indices.min { counts[$0] < counts[$1] } ?? 0
    }

    public func rename(_ tag: Tag, to raw: String) throws {
        let name = Tag.normalizedName(raw)
        guard !name.isEmpty else { throw TabbyStoreError.emptyName }
        if let other = self.tag(named: name), other.id != tag.id { throw TabbyStoreError.tagNameTaken }
        tag.name = name
        for person in tag.people ?? [] { refreshSearchText(person) }
        persist()
    }

    public func recolor(_ tag: Tag, colorIndex: Int) {
        tag.colorIndex = colorIndex
        persist()
    }

    /// Moves every person and Space rule from `source` to `target`, then deletes `source`.
    public func merge(_ source: Tag, into target: Tag) {
        guard source.id != target.id else { return }
        let people = source.people ?? []
        for person in people {
            var tags = (person.tags ?? []).filter { $0.id != source.id }
            if !tags.contains(where: { $0.id == target.id }) { tags.append(target) }
            person.tags = tags
        }
        for space in source.spaces ?? [] {
            var tags = (space.ruleTags ?? []).filter { $0.id != source.id }
            if !tags.contains(where: { $0.id == target.id }) { tags.append(target) }
            space.ruleTags = tags
        }
        target.useCount += source.useCount
        if let lastUsed = source.lastUsedAt, lastUsed > (target.lastUsedAt ?? .distantPast) {
            target.lastUsedAt = lastUsed
        }
        context.delete(source)
        for person in people { refreshSearchText(person) }
        persist()
    }

    /// Removes the tag from every person and Space rule. Never deletes people.
    public func delete(_ tag: Tag) {
        let people = tag.people ?? []
        for person in people {
            person.tags = (person.tags ?? []).filter { $0.id != tag.id }
        }
        for space in tag.spaces ?? [] {
            space.ruleTags = (space.ruleTags ?? []).filter { $0.id != tag.id }
        }
        context.delete(tag)
        for person in people { refreshSearchText(person) }
        persist()
    }

    // MARK: - Spaces

    public func allSpaces() -> [Space] {
        (try? context.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    public func space(id: UUID) -> Space? {
        var descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    public func createSpace(_ draft: SpaceDraft, at date: Date = .now) throws -> Space {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TabbyStoreError.emptyName }
        let order = (allSpaces().map(\.sortOrder).max() ?? -1) + 1
        let space = Space(name: name, icon: draft.icon, colorIndex: draft.colorIndex, sortOrder: order, createdAt: date)
        context.insert(space)
        apply(draft, to: space)
        persist()
        return space
    }

    public func update(_ space: Space, with draft: SpaceDraft) throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TabbyStoreError.emptyName }
        space.name = name
        space.icon = draft.icon
        space.colorIndex = draft.colorIndex
        apply(draft, to: space)
        persist()
    }

    private func apply(_ draft: SpaceDraft, to space: Space) {
        space.matchAll = draft.matchAll
        space.platformFilter = draft.platforms
        space.ruleTags = tags(withIDs: draft.tagIDs)
    }

    public func delete(_ space: Space) {
        context.delete(space)
        persist()
    }

    public func setPinned(_ pinned: Bool, for space: Space) {
        space.isPinned = pinned
        persist()
    }

    /// Stores the given order.
    public func reorder(_ spaces: [Space]) {
        for (index, space) in spaces.enumerated() where space.sortOrder != index {
            space.sortOrder = index
        }
        persist()
    }
}

/// The Space editor's working copy.
public struct SpaceDraft: Equatable, Sendable {
    public var name = ""
    public var icon = "folder.fill"
    public var colorIndex = 0
    public var matchAll = false
    public var tagIDs: Set<UUID> = []
    public var platforms: Set<Platform> = []

    public init() {}

    public init(space: Space) {
        name = space.name
        icon = space.icon
        colorIndex = space.colorIndex
        matchAll = space.matchAll
        tagIDs = Set((space.ruleTags ?? []).map(\.id))
        platforms = space.platformFilter
    }

    public var rule: SpaceRule {
        SpaceRule(matchAll: matchAll, tagIDs: tagIDs, platforms: platforms)
    }

    /// A Space needs a name and at least one tag.
    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tagIDs.isEmpty
    }
}
