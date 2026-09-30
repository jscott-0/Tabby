import SwiftData
import XCTest
@testable import TabbyKit

@MainActor
final class TabbyStoreTests: XCTestCase {
    /// Containers must outlive their contexts; XCTest makes a new instance per test.
    private var containers: [ModelContainer] = []

    private func makeContainer() throws -> ModelContainer {
        let container = try TabbyContainer.make(inMemory: true)
        containers.append(container)
        return container
    }

    private func makeStore() throws -> TabbyStore {
        TabbyStore(context: try makeContainer().mainContext)
    }

    private func makeDraft(_ platform: Platform, _ handle: String, name: String = "", tags: Set<UUID> = [], note: String = "") -> PersonDraft {
        var draft = PersonDraft(platform: platform, handle: handle, profileURL: ProfileURLParser.profile(platform: platform, handle: handle)?.url)
        draft.displayName = name
        draft.tagIDs = tags
        draft.note = note
        return draft
    }

    private func count<T: PersistentModel>(_ type: T.Type, in store: TabbyStore) throws -> Int {
        try store.context.fetchCount(FetchDescriptor<T>())
    }

    // MARK: Saving and dedup

    func testSaveCreatesPersonAndAccount() throws {
        let store = try makeStore()
        let outcome = try store.save(makeDraft(.instagram, "tabby_sample_mara", name: "Mara Quill", note: "Packaging"))
        XCTAssertFalse(outcome.wasExisting)
        XCTAssertEqual(outcome.person.displayName, "Mara Quill")
        XCTAssertEqual(outcome.person.primaryAccount?.dedupKey, "instagram:tabby_sample_mara")
        XCTAssertEqual(outcome.person.primaryAccount?.extractionStatus, .pending)
        XCTAssertTrue(outcome.person.needsInfo)
        XCTAssertEqual(try count(Person.self, in: store), 1)
        XCTAssertEqual(try count(Account.self, in: store), 1)
    }

    func testSameProfileTwiceNeverCreatesTwoPeople() throws {
        let store = try makeStore()
        let designer = try XCTUnwrap(store.findOrCreateTag(named: "designer"))
        let boston = try XCTUnwrap(store.findOrCreateTag(named: "boston"))
        let first = try store.save(makeDraft(.linkedin, "tabby-sample-priya", name: "Priya", tags: [designer.id], note: "Met at meetup"))

        // Second share: handle case differs, existing tags pre-selected plus a new one, new note.
        var second = makeDraft(.linkedin, "Tabby-Sample-Priya", tags: [designer.id, boston.id], note: "Hiring soon")
        second.headline = "Industrial Designer"
        XCTAssertEqual(store.existingPerson(for: second)?.id, first.person.id)
        let outcome = try store.save(second)

        XCTAssertTrue(outcome.wasExisting)
        XCTAssertEqual(outcome.person.id, first.person.id)
        XCTAssertEqual(try count(Person.self, in: store), 1)
        XCTAssertEqual(try count(Account.self, in: store), 1)
        XCTAssertEqual(outcome.person.displayName, "Priya", "empty name in a re-share keeps the old one")
        XCTAssertEqual(outcome.person.headline, "Industrial Designer")
        XCTAssertEqual(Set(outcome.person.sortedTags.map(\.name)), ["boston", "designer"])
        XCTAssertTrue(outcome.person.note.hasPrefix("Met at meetup\n\n"))
        XCTAssertTrue(outcome.person.note.hasSuffix(" — Hiring soon"))
        XCTAssertEqual(boston.useCount, 1)
        XCTAssertEqual(designer.useCount, 1, "re-applying an existing tag is not a new use")
    }

    func testMergeNeverDowngradesExtractionStatus() throws {
        let store = try makeStore()
        var complete = makeDraft(.tiktok, "tabby_sample_dev", name: "Dev")
        complete.extractionStatus = .complete
        try store.save(complete)
        var offline = makeDraft(.tiktok, "tabby_sample_dev")
        offline.extractionStatus = .failed
        let outcome = try store.save(offline)
        XCTAssertEqual(outcome.person.primaryAccount?.extractionStatus, .complete)
    }

    func testSaveWithNoTagsAndNoNote() throws {
        let store = try makeStore()
        let outcome = try store.save(makeDraft(.tiktok, "tabby_sample_freya"))
        XCTAssertEqual(outcome.person.title, "@tabby_sample_freya")
        XCTAssertTrue(outcome.person.sortedTags.isEmpty)
        XCTAssertEqual(outcome.person.note, "")
    }

    func testNonProfileURLSavesAsOther() throws {
        let store = try makeStore()
        let parsed = ProfileURLParser.parse(URL(string: "https://www.instagram.com/p/C1a2b3c4/")!)
        let postDraft = PersonDraft(parsed: parsed)
        XCTAssertEqual(postDraft.platform, .other)
        let outcome = try store.save(postDraft)
        XCTAssertEqual(outcome.person.primaryAccount?.platform, .other)
        XCTAssertEqual(outcome.person.primaryAccount?.dedupKey, "other:instagram.com/p/c1a2b3c4")
        XCTAssertTrue(try store.save(PersonDraft(parsed: parsed)).wasExisting)
    }

    func testPostWithAuthorSavesAuthor() {
        let parsed = ProfileURLParser.parse(URL(string: "https://www.tiktok.com/@tabby_sample_dev/video/7300000000000000000")!)
        let authorDraft = PersonDraft(parsed: parsed)
        XCTAssertEqual(authorDraft.platform, .tiktok)
        XCTAssertEqual(authorDraft.handle, "tabby_sample_dev")
    }

    func testDraftApplyFillsOnlyEmptyFields() {
        var draft = makeDraft(.tiktok, "tabby_sample_dev", name: "Typed by user")
        var metadata = ProfileMetadata()
        metadata.name = "Fetched Name"
        metadata.bio = "fetched bio"
        metadata.avatarURL = URL(string: "https://cdn.example.com/a.jpg")
        let parsed = ProfileURLParser.parse(URL(string: "https://www.tiktok.com/@tabby_sample_dev")!)
        draft.apply(ExtractionResult(parsed: parsed, metadata: metadata, status: .partial, httpStatus: 200, error: nil, html: nil))
        XCTAssertEqual(draft.displayName, "Typed by user")
        XCTAssertEqual(draft.bio, "fetched bio")
        XCTAssertEqual(draft.extractionStatus, .partial)
        XCTAssertNotNil(draft.rawMetadata)
    }

    func testShortLinkDraftTakesResolvedProfile() {
        var draft = PersonDraft(parsed: ProfileURLParser.parse(URL(string: "https://vm.tiktok.com/ZMabc123/")!))
        XCTAssertEqual(draft.platform, .other)
        let resolved = ProfileURLParser.parse(URL(string: "https://www.tiktok.com/@tabby_sample_dev")!)
        draft.apply(ExtractionResult(parsed: resolved, metadata: ProfileMetadata(), status: .failed, httpStatus: nil, error: "offline", html: nil))
        XCTAssertEqual(draft.platform, .tiktok)
        XCTAssertEqual(draft.dedupKey, "tiktok:tabby_sample_dev")
    }

    // MARK: Tags

    func testTagNamesAreUniqueCaseInsensitively() throws {
        let store = try makeStore()
        let first = try XCTUnwrap(store.findOrCreateTag(named: "Designer"))
        let second = try XCTUnwrap(store.findOrCreateTag(named: "  #designer "))
        XCTAssertEqual(first.id, second.id)
        XCTAssertNil(store.findOrCreateTag(named: "   "))
        XCTAssertEqual(store.allTags().count, 1)
    }

    func testNewTagsSpreadAcrossPalette() throws {
        let store = try makeStore()
        let colors = ["a", "b", "c"].compactMap { store.findOrCreateTag(named: $0)?.colorIndex }
        XCTAssertEqual(Set(colors).count, 3)
    }

    func testDeletingTagRemovesItFromPeopleAndRulesButKeepsPeople() throws {
        let store = try makeStore()
        let hardware = try XCTUnwrap(store.findOrCreateTag(named: "hardware"))
        let person = try store.save(makeDraft(.tiktok, "tabby_sample_dev", tags: [hardware.id])).person
        var spaceDraft = SpaceDraft()
        spaceDraft.name = "Hardware"
        spaceDraft.tagIDs = [hardware.id]
        let space = try store.createSpace(spaceDraft)

        store.delete(hardware)

        XCTAssertEqual(try count(Person.self, in: store), 1)
        XCTAssertTrue(person.sortedTags.isEmpty)
        XCTAssertFalse(person.searchText.contains("hardware"))
        XCTAssertTrue(space.rule.isEmpty, "the Space is left with no tags and shows an Edit rule prompt")
        XCTAssertFalse(space.rule.matches(PersonFacts(person)))
    }

    func testRenameUpdatesSearchAndRejectsTakenNames() throws {
        let store = try makeStore()
        let tag = try XCTUnwrap(store.findOrCreateTag(named: "designr"))
        _ = try XCTUnwrap(store.findOrCreateTag(named: "maker"))
        let person = try store.save(makeDraft(.instagram, "tabby_sample_mara", tags: [tag.id])).person

        try store.rename(tag, to: "designer")
        XCTAssertTrue(person.searchText.contains("designer"))
        XCTAssertThrowsError(try store.rename(tag, to: "Maker")) { error in
            XCTAssertEqual(error as? TabbyStoreError, .tagNameTaken)
        }
    }

    func testMergeMovesPeopleAndRules() throws {
        let store = try makeStore()
        let source = try XCTUnwrap(store.findOrCreateTag(named: "designers"))
        let target = try XCTUnwrap(store.findOrCreateTag(named: "designer"))
        let onlySource = try store.save(makeDraft(.instagram, "tabby_sample_felix", tags: [source.id])).person
        let both = try store.save(makeDraft(.instagram, "tabby_sample_mara", tags: [source.id, target.id])).person
        var spaceDraft = SpaceDraft()
        spaceDraft.name = "Design"
        spaceDraft.tagIDs = [source.id]
        let space = try store.createSpace(spaceDraft)

        store.merge(source, into: target)

        XCTAssertEqual(store.allTags().map(\.name), ["designer"])
        XCTAssertEqual(onlySource.sortedTags.map(\.name), ["designer"])
        XCTAssertEqual(both.sortedTags.map(\.name), ["designer"])
        XCTAssertEqual(space.sortedRuleTags.map(\.name), ["designer"])
    }

    func testShareSheetTagOrder() throws {
        let store = try makeStore()
        let now = Date.now
        let old = try XCTUnwrap(store.findOrCreateTag(named: "zebra"))
        let recent = try XCTUnwrap(store.findOrCreateTag(named: "yak"))
        _ = store.findOrCreateTag(named: "alpha")
        old.lastUsedAt = now.addingTimeInterval(-100)
        recent.lastUsedAt = now
        let ordered = Tag.shareSheetOrder(store.allTags(), recentCount: 2).map(\.name)
        XCTAssertEqual(ordered, ["yak", "zebra", "alpha"])
    }

    // MARK: Spaces

    func testAllOfRuleUpdatesWhenATagIsAddedElsewhere() throws {
        let store = try makeStore()
        let designer = try XCTUnwrap(store.findOrCreateTag(named: "designer"))
        let hardware = try XCTUnwrap(store.findOrCreateTag(named: "hardware"))
        let both = try store.save(makeDraft(.linkedin, "tabby-sample-priya", tags: [designer.id, hardware.id])).person
        let designerOnly = try store.save(makeDraft(.instagram, "tabby_sample_mara", tags: [designer.id])).person
        _ = try store.save(makeDraft(.tiktok, "tabby_sample_dev", tags: [hardware.id]))

        var spaceDraft = SpaceDraft()
        spaceDraft.name = "Hardware designers"
        spaceDraft.matchAll = true
        spaceDraft.tagIDs = [designer.id, hardware.id]
        let space = try store.createSpace(spaceDraft)

        func members() -> Set<UUID> {
            Set(store.allPeople().map(PersonFacts.init).members(of: space.rule).map(\.id))
        }
        XCTAssertEqual(members(), [both.id])

        store.addTags([hardware.id], to: [designerOnly])
        XCTAssertEqual(members(), [both.id, designerOnly.id])
    }

    func testAnyRuleWithPlatformFilter() throws {
        let store = try makeStore()
        let fitness = try XCTUnwrap(store.findOrCreateTag(named: "fitness"))
        let tiktok = try store.save(makeDraft(.tiktok, "tabby_sample_noor", tags: [fitness.id])).person
        _ = try store.save(makeDraft(.linkedin, "tabby-sample-coach", tags: [fitness.id]))
        let rule = SpaceRule(matchAll: false, tagIDs: [fitness.id], platforms: [.tiktok, .instagram])
        XCTAssertEqual(store.allPeople().map(PersonFacts.init).members(of: rule).map(\.id), [tiktok.id])
    }

    func testBuiltInSpaces() throws {
        let store = try makeStore()
        let now = Date.now
        let tag = try XCTUnwrap(store.findOrCreateTag(named: "food"))
        var complete = makeDraft(.instagram, "tabby_sample_chloe", tags: [tag.id])
        complete.extractionStatus = .complete
        let tagged = try store.save(complete, at: now.addingTimeInterval(-40 * 86_400)).person
        let fresh = try store.save(makeDraft(.tiktok, "tabby_sample_new"), at: now).person

        let facts = store.allPeople().map(PersonFacts.init)
        XCTAssertEqual(Set(facts.members(of: .all, now: now).map(\.id)), [tagged.id, fresh.id])
        XCTAssertEqual(facts.members(of: .recentlyAdded, now: now).map(\.id), [fresh.id])
        XCTAssertEqual(facts.members(of: .untagged, now: now).map(\.id), [fresh.id])
        XCTAssertEqual(facts.members(of: .needsInfo, now: now).map(\.id), [fresh.id])
    }

    func testReorderAndPin() throws {
        let store = try makeStore()
        let tag = try XCTUnwrap(store.findOrCreateTag(named: "x"))
        var spaceDraft = SpaceDraft()
        spaceDraft.tagIDs = [tag.id]
        let spaces = try ["A", "B", "C"].map { name -> Space in
            spaceDraft.name = name
            return try store.createSpace(spaceDraft)
        }
        store.reorder([spaces[2], spaces[0], spaces[1]])
        XCTAssertEqual(store.allSpaces().map(\.name), ["C", "A", "B"])
        store.setPinned(true, for: spaces[1])
        XCTAssertTrue(spaces[1].isPinned)
        XCTAssertThrowsError(try store.createSpace(SpaceDraft()))
    }

    // MARK: Search

    func testSearchMatchesNameHandleHeadlineBioNoteAndTags() throws {
        let store = try makeStore()
        let tag = try XCTUnwrap(store.findOrCreateTag(named: "ceramics"))
        var aiko = makeDraft(.instagram, "tabby_sample_aiko", name: "Aiko Lindqvist", tags: [tag.id], note: "Custom mugs")
        aiko.bio = "Stoneware and glazes"
        aiko.headline = "Studio potter"
        try store.save(aiko)
        try store.save(makeDraft(.tiktok, "tabby_sample_dev", name: "Dev Okafor"))

        let people = store.allPeople()
        for query in ["aiko", "LINDQVIST", "@tabby_sample_aiko", "potter", "glazes", "mugs", "#ceramics", "aiko mugs"] {
            XCTAssertEqual(SearchText.filter(people, query: query).map(\.displayName), ["Aiko Lindqvist"], query)
        }
        XCTAssertEqual(SearchText.filter(people, query: "okafor mugs").count, 0)
        XCTAssertEqual(SearchText.filter(people, query: "  ").count, 2)
    }

    func testSearchIsDiacriticInsensitive() throws {
        let store = try makeStore()
        try store.save(makeDraft(.instagram, "tabby_sample_chloe", name: "Chloé Dubois"))
        XCTAssertEqual(SearchText.filter(store.allPeople(), query: "chloe").count, 1)
    }

    func testSearchOverOneThousandPeopleIsFast() throws {
        let store = try makeStore()
        let tags = (0..<20).compactMap { store.findOrCreateTag(named: "tag\($0)")?.id }
        for index in 0..<1_000 {
            var person = makeDraft(Platform.social[index % 3], "tabby_sample_\(index)", name: "Person \(index)",
                               tags: [tags[index % tags.count]], note: "Note number \(index)")
            person.bio = "Bio for person \(index) with some longer text about their work"
            _ = try store.save(person)
        }
        let people = store.allPeople()
        XCTAssertEqual(people.count, 1_000)

        let clock = ContinuousClock()
        for query in ["person 99", "tag7", "@tabby_sample_5", "longer text", "nothing matches this"] {
            var results: [Person] = []
            let elapsed = clock.measure { results = SearchText.filter(people, query: query) }
            XCTAssertLessThan(elapsed, .milliseconds(100), "\"\(query)\" over 1,000 people took \(elapsed)")
            XCTAssertEqual(results.isEmpty, query == "nothing matches this", query)
        }
    }

    // MARK: Sample data

    func testSampleDataSeeds() throws {
        let container = try makeContainer()
        SampleData.seed(into: container.mainContext)
        let store = TabbyStore(context: container.mainContext)
        XCTAssertEqual(store.allPeople().count, 20)
        XCTAssertEqual(store.allSpaces().count, 5)
        let facts = store.allPeople().map(PersonFacts.init)
        let hardwareDesigners = try XCTUnwrap(store.allSpaces().first { $0.name == "Hardware designers" })
        XCTAssertEqual(Set(facts.members(of: hardwareDesigners.rule).map(\.displayName)), ["Priya Castellan", "Arjun Mehta"])
        XCTAssertEqual(facts.members(of: .needsInfo).count, 2)

        SampleData.seed(into: container.mainContext)
        XCTAssertEqual(store.allPeople().count, 20, "seeding again merges instead of duplicating")
        XCTAssertEqual(store.allSpaces().count, 5)
        XCTAssertTrue(SampleData.isSampleHandle("tabby_sample_dev"))
        XCTAssertFalse(SampleData.isSampleHandle("devbuilds"))
    }

    func testDeepLinkRoundTrip() {
        let id = UUID()
        XCTAssertEqual(DeepLink.personID(from: DeepLink.url(forPerson: id)), id)
        XCTAssertNil(DeepLink.personID(from: URL(string: "https://example.com/person/\(id)")!))
    }
}
