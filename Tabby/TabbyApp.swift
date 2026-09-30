import SwiftData
import SwiftUI
import TabbyKit

@main
struct TabbyApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try TabbyContainer.make()
        } catch {
            fatalError("Could not open the Tabby store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

enum Route: Hashable {
    case space(SpaceRef)
    case person(UUID)
    case tags
}

/// My Tabs: a NavigationStack rooted at Spaces. `tabby://person/{id}` opens a Person.
struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
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
                path = [.person(id)]
            }
        }
    }
}
