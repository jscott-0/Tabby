import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import TabbyKit

@MainActor
final class ShareFlowTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private let profileURL = URL(string: "https://www.tiktok.com/@tabby_sample_dev?_t=8abc")!
    private let profileHTML = """
    <meta property="og:title" content="Dev Okafor (@tabby_sample_dev) | TikTok">
    <meta property="og:image" content="https://cdn.example.com/tt/dev.jpg">
    <meta property="og:description" content="Dev Okafor (@tabby_sample_dev) on TikTok | 10 Likes. 5 Followers. hardware tinkerer. Watch the latest video from Dev Okafor (@tabby_sample_dev).">
    """

    private func makeDefaults() -> SharedDefaults {
        SharedDefaults(defaults: UserDefaults(suiteName: "tabby-tests-\(UUID().uuidString)")!)
    }

    private func makeFlow(_ responses: [String: HTTPResponse] = [:], defaults: SharedDefaults? = nil) throws -> (ShareFlow, TabbyStore) {
        let container = try TabbyContainer.make(inMemory: true)
        containers.append(container)
        let service = EnrichmentService(client: StubHTTPClient(responses))
        let flow = ShareFlow(context: container.mainContext, service: service, sharedDefaults: defaults ?? makeDefaults(), log: nil)
        return (flow, TabbyStore(context: container.mainContext))
    }

    private var profileResponse: [String: HTTPResponse] {
        let canonical = "https://www.tiktok.com/@tabby_sample_dev"
        return [canonical: HTTPResponse(url: URL(string: canonical)!, statusCode: 200, body: Data(profileHTML.utf8))]
    }

    func testProfileShareFillsPreviewAndSaves() async throws {
        let defaults = makeDefaults()
        let (flow, store) = try makeFlow(profileResponse, defaults: defaults)
        await flow.start(with: profileURL)

        XCTAssertEqual(flow.phase, .editing)
        XCTAssertEqual(flow.draft.platform, .tiktok)
        XCTAssertEqual(flow.draft.handle, "tabby_sample_dev")
        XCTAssertEqual(flow.draft.displayName, "Dev Okafor")
        XCTAssertEqual(flow.draft.bio, "hardware tinkerer.")
        XCTAssertNil(flow.notice)
        XCTAssertNil(flow.existingName)

        flow.draft.note = "Explains PCB design clearly"
        flow.save()
        guard case .saved(let id, let name) = flow.phase else { return XCTFail("not saved: \(flow.phase)") }
        XCTAssertEqual(name, "Dev Okafor")
        XCTAssertEqual(store.person(id: id)?.note, "Explains PCB design clearly")
        XCTAssertNotNil(defaults.lastExternalWrite, "the app is told to reload")
    }

    func testOfflineSaveStillWorksAndNeedsInfo() async throws {
        let (flow, store) = try makeFlow()
        await flow.start(with: profileURL)
        XCTAssertEqual(flow.draft.handle, "tabby_sample_dev", "tier 1 survives a failed fetch")
        XCTAssertEqual(flow.draft.extractionStatus, .failed)
        flow.save()
        guard case .saved(let id, _) = flow.phase else { return XCTFail("not saved") }
        XCTAssertEqual(store.person(id: id)?.needsInfo, true)
    }

    func testDuplicateShowsExistingAndMerges() async throws {
        let (flow, store) = try makeFlow()
        let tag = try XCTUnwrap(store.findOrCreateTag(named: "hardware"))
        var existing = PersonDraft(platform: .tiktok, handle: "tabby_sample_dev", profileURL: nil)
        existing.displayName = "Dev"
        existing.tagIDs = [tag.id]
        let saved = try store.save(existing)

        await flow.start(with: profileURL)
        XCTAssertEqual(flow.existingName, "Dev")
        XCTAssertEqual(flow.draft.tagIDs, [tag.id], "existing tags are pre-selected")
        flow.save()
        guard case .saved(let id, _) = flow.phase else { return XCTFail("not saved") }
        XCTAssertEqual(id, saved.person.id)
        XCTAssertEqual(store.allPeople().count, 1)
    }

    func testPostWithoutAuthorSavesAsLink() async throws {
        let (flow, _) = try makeFlow()
        await flow.start(with: URL(string: "https://www.instagram.com/reel/C1a2b3c4/?igsh=abc")!)
        XCTAssertEqual(flow.draft.platform, .other)
        XCTAssertEqual(flow.notice, "This looks like a post, not a profile. It will be saved as a link.")
    }

    func testPostWithAuthorSavesAuthor() async throws {
        let (flow, _) = try makeFlow()
        await flow.start(with: URL(string: "https://www.tiktok.com/@tabby_sample_dev/video/7300000000000000000")!)
        XCTAssertEqual(flow.draft.platform, .tiktok)
        XCTAssertEqual(flow.draft.handle, "tabby_sample_dev")
        XCTAssertEqual(flow.notice, "This looks like a post, not a profile. Saving its author, @tabby_sample_dev.")
    }

    func testNoURLShowsNoLink() async throws {
        let (flow, _) = try makeFlow()
        await flow.start(with: nil)
        XCTAssertEqual(flow.phase, .noLink)
    }

    func testTagsCreatedInTheExtensionAreSavedAndSignalled() async throws {
        let defaults = makeDefaults()
        let (flow, store) = try makeFlow(defaults: defaults)
        await flow.start(with: profileURL)
        let tag = try XCTUnwrap(flow.createTag(named: "maker"))
        flow.draft.tagIDs.insert(tag.id)
        XCTAssertNotNil(defaults.lastExternalWrite)
        flow.save()
        XCTAssertEqual(store.allPeople().first?.sortedTags.map(\.name), ["maker"])
    }

    func testRequestOpenRemembersPendingPerson() async throws {
        let defaults = makeDefaults()
        let (flow, _) = try makeFlow(defaults: defaults)
        XCTAssertNil(flow.requestOpen(), "nothing to open before saving")
        await flow.start(with: profileURL)
        flow.save()
        let url = try XCTUnwrap(flow.requestOpen())
        let id = try XCTUnwrap(DeepLink.personID(from: url))
        XCTAssertEqual(defaults.takePendingOpen(), id)
        XCTAssertNil(defaults.takePendingOpen(), "taking clears it")
    }

    // MARK: Shared input

    func testSharedURLAttachment() async {
        let provider = NSItemProvider(item: profileURL as NSURL, typeIdentifier: UTType.url.identifier)
        let url = await SharedInput.firstURL(in: [provider])
        XCTAssertEqual(url, profileURL)
    }

    func testURLInsideSharedText() async {
        let text = "Check out Dev Okafor's profile on TikTok! \(profileURL.absoluteString)"
        let provider = NSItemProvider(item: text as NSString, typeIdentifier: UTType.plainText.identifier)
        let url = await SharedInput.firstURL(in: [provider])
        XCTAssertEqual(url?.host, "www.tiktok.com")
    }

    func testTextWithoutURL() async {
        let provider = NSItemProvider(item: "just words" as NSString, typeIdentifier: UTType.plainText.identifier)
        let url = await SharedInput.firstURL(in: [provider])
        XCTAssertNil(url)
    }
}
