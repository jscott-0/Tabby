import Observation
import SwiftData
import SwiftUI
import TabbyKit

@main
struct TabbyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .id(model.storeGeneration)
                .modelContainer(model.container)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.becameActive() }
        }
    }
}

enum Route: Hashable {
    case space(SpaceRef)
    case person(UUID)
    case tags
}

/// App-wide state that must survive the store being reopened: the store itself and navigation.
@MainActor
@Observable
final class AppModel {
    private(set) var container: ModelContainer
    /// Bumped when the store is reopened so views drop objects from the old one.
    private(set) var storeGeneration = 0
    var path: [Route] = []

    @ObservationIgnored private var lastSeenExternalWrite: Date?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryRun = UUID()
    private let sharedDefaults = SharedDefaults.shared

    init() {
        do {
            container = try TabbyContainer.make()
        } catch {
            fatalError("Could not open the Tabby store: \(error)")
        }
        lastSeenExternalWrite = sharedDefaults.lastExternalWrite
    }

    /// The share extension saves from another process, which this app's context doesn't see.
    /// Reopen the store when it has written since we last looked, show any pending "Open in Tabby",
    /// then retry profiles whose extraction didn't complete.
    func becameActive() {
        if let write = sharedDefaults.lastExternalWrite, write != lastSeenExternalWrite {
            lastSeenExternalWrite = write
            if let fresh = try? TabbyContainer.make() {
                retryTask?.cancel()
                retryTask = nil
                container = fresh
                storeGeneration += 1
            }
        }
        if let id = sharedDefaults.takePendingOpen() {
            open(personID: id)
        }
        retryIncompleteProfiles()
    }

    private func retryIncompleteProfiles() {
        guard retryTask == nil else { return }
        let queue = RetryQueue(context: container.mainContext, service: EnrichmentService(renderer: WebPageRenderer()))
        let run = UUID()
        retryRun = run
        retryTask = Task { [weak self] in
            await queue.run()
            if self?.retryRun == run { self?.retryTask = nil }
        }
    }

    func open(personID: UUID) {
        if sharedDefaults.pendingOpenPersonID == personID {
            sharedDefaults.setPendingOpen(nil)
        }
        path = [.person(personID)]
    }
}

/// My Tabs: a NavigationStack rooted at Spaces. `tabby://person/{id}` opens a Person.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            SpacesView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .space(let ref): SpaceDetailView(ref: ref)
                    case .person(let id): PersonDetailView(personID: id)
                    case .tags: TagsView()
                    }
                }
        }
        .onOpenURL { url in
            if let id = DeepLink.personID(from: url) {
                model.open(personID: id)
            }
        }
    }
}
