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
        // `initial` so a cold launch (already active, no change) still runs it.
        .onChange(of: scenePhase, initial: true) { _, phase in
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
    /// Reopen the store when it has written since we last looked, then show any pending "Open in Tabby".
    func becameActive() {
        if let write = sharedDefaults.lastExternalWrite, write != lastSeenExternalWrite {
            lastSeenExternalWrite = write
            if let fresh = try? TabbyContainer.make() {
                container = fresh
                storeGeneration += 1
            }
        }
        if let id = sharedDefaults.takePendingOpen() {
            open(personID: id)
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
