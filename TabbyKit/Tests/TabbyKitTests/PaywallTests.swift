import SwiftData
import XCTest
@testable import TabbyKit

@MainActor
final class PaywallTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try TabbyContainer.make(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private func makeDefaults() -> SharedDefaults {
        SharedDefaults(defaults: UserDefaults(suiteName: "tabby-tests-\(UUID().uuidString)")!)
    }

    private func draft(_ handle: String) -> PersonDraft {
        var draft = PersonDraft(parsed: ProfileURLParser.profile(platform: .instagram, handle: handle)!)
        draft.displayName = handle
        return draft
    }

    // MARK: Policy

    func testFreeLimitAndEntitlements() {
        XCTAssertTrue(PaywallPolicy.canAddPerson(unlockedCount: 0, entitlement: .free))
        XCTAssertFalse(PaywallPolicy.canAddPerson(unlockedCount: 1, entitlement: .free))
        XCTAssertTrue(PaywallPolicy.canAddPerson(unlockedCount: 500, entitlement: .unlimitedTabs))
        XCTAssertTrue(PaywallPolicy.canAddPerson(unlockedCount: 500, entitlement: .pro))
        XCTAssertLessThan(Entitlement.unlimitedTabs, .pro)
        XCTAssertFalse(Entitlement.unlimitedTabs.isPro)
        XCTAssertTrue(PaywallTrigger.demo.defaultsToPro)
        XCTAssertFalse(PaywallTrigger.slotLimit.defaultsToPro)
    }

    // MARK: Locked drafts

    func testSecondFreeSaveIsALockedDraftHiddenFromSpacesAndSearch() throws {
        let store = TabbyStore(context: try makeContext())
        let first = try store.save(draft("tabby_sample_one"), entitlement: .free)
        XCTAssertFalse(first.isLockedDraft)
        XCTAssertTrue(store.wouldLock(draft("tabby_sample_two"), entitlement: .free))
        XCTAssertFalse(store.wouldLock(draft("tabby_sample_one"), entitlement: .free), "re-sharing a saved person merges")
        XCTAssertFalse(store.wouldLock(draft("tabby_sample_two"), entitlement: .unlimitedTabs))

        let second = try store.save(draft("tabby_sample_two"), entitlement: .free)
        XCTAssertTrue(second.isLockedDraft)
        XCTAssertEqual(store.unlockedPeopleCount(), 1)
        XCTAssertEqual(store.lockedDraftCount(), 1)

        let merged = try store.save(draft("tabby_sample_one"), entitlement: .free)
        XCTAssertTrue(merged.wasExisting)
        XCTAssertFalse(merged.isLockedDraft, "merges never lock")

        let facts = store.allPeople().map(PersonFacts.init)
        XCTAssertEqual(facts.members(of: .all).map(\.id), [first.person.id])
        XCTAssertEqual(facts.members(of: .waitingToUnlock).map(\.id), [second.person.id])
        XCTAssertTrue(facts.members(of: SpaceRule(matchAll: false, tagIDs: [], platforms: [])).allSatisfy { !$0.isLockedDraft })
        XCTAssertTrue(SearchText.filter(store.allPeople(), query: "tabby_sample_two").isEmpty)
    }

    func testPurchaseUnlocksAllDrafts() throws {
        let store = TabbyStore(context: try makeContext())
        for handle in ["tabby_sample_a", "tabby_sample_b", "tabby_sample_c"] {
            try store.save(draft(handle), entitlement: .free)
        }
        XCTAssertEqual(store.lockedDraftCount(), 2)
        store.unlockAllDrafts()
        XCTAssertEqual(store.lockedDraftCount(), 0)
        XCTAssertEqual(store.unlockedPeopleCount(), 3)
    }

    // MARK: Purchase routing

    func testUSStorefrontRoutesToWebCheckoutOnlyWhenConfigured() {
        let base = URL(string: "https://example.com/checkout")!
        XCTAssertEqual(PurchaseRouter.route(storefrontCountryCode: "USA", webCheckoutBase: nil, accountID: "u1", productID: "p"), .appStore)
        XCTAssertEqual(PurchaseRouter.route(storefrontCountryCode: "GBR", webCheckoutBase: base, accountID: "u1", productID: "p"), .appStore)
        XCTAssertEqual(PurchaseRouter.route(storefrontCountryCode: "USA", webCheckoutBase: base, accountID: nil, productID: "p"), .appStore)
        XCTAssertEqual(
            PurchaseRouter.route(storefrontCountryCode: "USA", webCheckoutBase: base, accountID: "u1", productID: "tabby.pro.annual"),
            .webCheckout(URL(string: "https://example.com/checkout?account=u1&product=tabby.pro.annual")!)
        )
    }

    // MARK: Share sheet

    func testFirstShareTeachesThenStopsTeaching() async throws {
        let defaults = makeDefaults()
        let context = try makeContext()
        let flow = ShareFlow(context: context, service: EnrichmentService(client: StubHTTPClient([:])), sharedDefaults: defaults, log: nil)
        XCTAssertTrue(flow.isTeaching)
        await flow.start(with: URL(string: "https://www.instagram.com/tabby_sample_first/")!)
        XCTAssertEqual(flow.saveButtonTitle, "Import")
        XCTAssertFalse(flow.canSave)

        flow.hasConfirmedDetails = true
        let tag = try XCTUnwrap(flow.createTag(named: "design"))
        flow.draft.tagIDs = [tag.id]
        XCTAssertFalse(flow.canSave, "the note is still missing")
        flow.draft.note = "  "
        XCTAssertFalse(flow.isDone(.note))
        flow.draft.note = "Lovely type work"
        XCTAssertTrue(flow.canSave)
        flow.save()
        XCTAssertTrue(defaults.hasCompletedFirstSave)

        let next = ShareFlow(context: context, service: EnrichmentService(client: StubHTTPClient([:])), sharedDefaults: defaults, log: nil)
        XCTAssertFalse(next.isTeaching)
    }

    func testSkipTeachingSavesWithoutTheChecklist() async throws {
        let defaults = makeDefaults()
        let flow = ShareFlow(context: try makeContext(), service: EnrichmentService(client: StubHTTPClient([:])), sharedDefaults: defaults, log: nil)
        await flow.start(with: URL(string: "https://www.instagram.com/tabby_sample_first/")!)
        flow.skipTeaching()
        guard case .saved = flow.phase else { return XCTFail("not saved") }
        XCTAssertTrue(defaults.hasCompletedFirstSave)
    }

    func testFreeShareOverTheLimitSavesADraftAndQueuesThePaywall() async throws {
        let defaults = makeDefaults()
        defaults.hasCompletedFirstSave = true
        let context = try makeContext()
        try TabbyStore(context: context).save(draft("tabby_sample_one"), entitlement: .free)

        let flow = ShareFlow(context: context, service: EnrichmentService(client: StubHTTPClient([:])), sharedDefaults: defaults, log: nil)
        await flow.start(with: URL(string: "https://www.instagram.com/tabby_sample_two/")!)
        XCTAssertTrue(flow.willLock)
        XCTAssertEqual(flow.saveButtonTitle, "Save as draft")
        flow.save()
        XCTAssertTrue(flow.savedAsDraft)
        XCTAssertNotNil(flow.requestOpen())
        XCTAssertEqual(defaults.takePendingPaywall(), .slotLimit)
        XCTAssertNil(defaults.pendingPaywall)

        defaults.entitlement = .unlimitedTabs
        let paid = ShareFlow(context: context, service: EnrichmentService(client: StubHTTPClient([:])), sharedDefaults: defaults, log: nil)
        await paid.start(with: URL(string: "https://www.instagram.com/tabby_sample_three/")!)
        XCTAssertFalse(paid.willLock)
        XCTAssertEqual(paid.saveButtonTitle, "Save")
    }

    // MARK: Onboarding state

    func testSharedDefaultsRoundTrip() {
        let defaults = makeDefaults()
        XCTAssertEqual(defaults.entitlement, .free)
        XCTAssertEqual(defaults.onboardingStep, .welcome)
        XCTAssertNil(defaults.account)
        defaults.onboardingStep = .interests
        defaults.interests = ["design", "food"]
        defaults.account = AccountProfile(id: "abc", method: .email, email: "sample@example.com")
        XCTAssertEqual(defaults.onboardingStep, .interests)
        XCTAssertEqual(defaults.interests, ["design", "food"])
        XCTAssertEqual(defaults.account?.email, "sample@example.com")
        defaults.account = nil
        XCTAssertNil(defaults.account)
    }

    func testCatalogSuggestions() {
        XCTAssertEqual(Set(OnboardingCatalog.creators.map(\.id)).count, OnboardingCatalog.creators.count, "unique IDs")
        for creator in OnboardingCatalog.creators {
            XCTAssertNotNil(OnboardingCatalog.category(id: creator.categoryID), creator.id)
            XCTAssertNotNil(creator.profileURL, creator.id)
        }
        XCTAssertTrue(OnboardingCatalog.creators(in: ["food"]).allSatisfy { $0.categoryID == "food" })
        XCTAssertEqual(OnboardingCatalog.creators(in: []).count, OnboardingCatalog.creators.count)
        XCTAssertEqual(OnboardingCatalog.firstSuggestion(pickedCreatorIDs: ["tiktok:nba"], categoryIDs: ["food"]).handle, "nba")
        XCTAssertEqual(OnboardingCatalog.firstSuggestion(pickedCreatorIDs: [], categoryIDs: ["food"]).categoryID, "food")
    }

    func testDemoStoreIsSeparateAndFuller() {
        let demo = SampleData.demoContainer()
        XCTAssertEqual(TabbyStore(context: demo.mainContext).allPeople().count, 30)
        XCTAssertTrue(TabbyStore(context: demo.mainContext).allPeople().allSatisfy {
            SampleData.isSampleHandle($0.primaryAccount?.handle ?? "")
        }, "invented handles only, never fetched")
    }

    func testDemoLogCountsPurchasesWithinADay() {
        let log = DemoLog(defaults: UserDefaults(suiteName: "tabby-demo-\(UUID().uuidString)")!)
        let start = Date(timeIntervalSince1970: 1_000_000)
        log.recordPurchase(at: start)
        XCTAssertEqual(log.purchasesAfterDemo, 0, "no demo yet")
        log.enter(at: start)
        log.exit(at: start.addingTimeInterval(90))
        XCTAssertEqual(log.totalTimeInDemo, 90)
        log.recordPurchase(at: start.addingTimeInterval(3600))
        XCTAssertEqual(log.purchasesAfterDemo, 1)
        log.recordPurchase(at: start.addingTimeInterval(3 * 24 * 3600))
        XCTAssertEqual(log.purchasesAfterDemo, 1, "too long after the demo")
    }
}
