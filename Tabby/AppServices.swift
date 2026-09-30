import Foundation
import SwiftData
import SwiftUI
import TabbyKit

/// Network-facing services, swapped for offline stubs under UI tests.
enum AppServices {
    static func enrichment(renderer: (any PageRenderer)? = nil) -> EnrichmentService {
        #if DEBUG
        if UITesting.isEnabled { return EnrichmentService(client: UITestHTTPClient()) }
        #endif
        return EnrichmentService(renderer: renderer)
    }
}

#if DEBUG
/// Launch arguments used by TabbyUITests.
enum UITesting {
    /// In-memory store seeded with the sample data; no network, no App Group.
    static let flag = "-uiTesting"
    /// Followed by a URL: shows the share sheet for it instead of My Tabs.
    static let shareFlag = "-uiTestingShare"
    /// Starts onboarding with an empty store on the free plan.
    static let onboardingFlag = "-uiTestingOnboarding"
    /// The free plan (sample data is over its limit, so new saves become locked drafts).
    static let freeFlag = "-uiTestingFree"
    /// The share sheet in first-save teaching mode.
    static let teachingFlag = "-uiTestingTeaching"

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(flag) }
    static var isOnboarding: Bool { ProcessInfo.processInfo.arguments.contains(onboardingFlag) }

    /// A fresh App Group stand-in per launch, set up for the flags above. Purchases are simulated.
    static let sharedDefaults: SharedDefaults = {
        let name = "tabby-ui-tests"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let shared = SharedDefaults(defaults: defaults)
        let arguments = ProcessInfo.processInfo.arguments
        shared.onboardingFinished = !isOnboarding
        shared.hasCompletedFirstSave = !isOnboarding && !arguments.contains(teachingFlag)
        shared.entitlement = isOnboarding || arguments.contains(freeFlag) ? .free : .pro
        return shared
    }()

    @MainActor
    static func makeContainer() -> ModelContainer {
        if isOnboarding, let empty = try? TabbyContainer.make(inMemory: true) { return empty }
        return SampleData.previewContainer()
    }

    static var shareURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: shareFlag), arguments.indices.contains(index + 1) else { return nil }
        return URL(string: arguments[index + 1])
    }
}

/// Serves a synthetic profile page for any social profile URL, so UI tests never touch the network.
struct UITestHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> HTTPResponse {
        let parsed = ProfileURLParser.parse(url)
        guard parsed.kind == .profile, let handle = parsed.handle else { throw URLError(.notConnectedToInternet) }
        let html = """
        <meta property="og:title" content="Sample Person (@\(handle)) | TikTok">
        <meta property="og:description" content="Sample Person (@\(handle)) on TikTok | 12 Likes. 3.4K Followers. Builds tiny robots. Watch the latest video from Sample Person (@\(handle)).">
        """
        return HTTPResponse(url: url, statusCode: 200, body: Data(html.utf8))
    }
}

/// Hosts the share extension's sheet inside the app so UI tests can drive it.
struct UITestShareHost: View {
    let url: URL
    @Environment(\.modelContext) private var context
    @State private var flow: ShareFlow?
    @State private var isClosed = false

    var body: some View {
        Group {
            if isClosed {
                Text("Share sheet closed").accessibilityIdentifier("share-closed")
            } else if let flow {
                ShareSheetView(flow: flow, onClose: { isClosed = true }, onOpenInTabby: { isClosed = true })
            } else {
                ProgressView()
            }
        }
        .task {
            let flow = ShareFlow(
                context: context,
                service: AppServices.enrichment(),
                sharedDefaults: UITesting.sharedDefaults,
                log: nil
            )
            self.flow = flow
            await flow.start(with: url)
        }
    }
}
#endif
