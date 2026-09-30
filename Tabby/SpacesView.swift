import SwiftData
import SwiftUI
import TabbyKit

/// Home: a 2-column grid of Spaces (built-in, then pinned, then the rest), with search.
struct SpacesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt, order: .reverse) private var people: [Person]
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @State private var searchText = ""
    @State private var editor: SpaceEditorTarget?
    @State private var isAddingPerson = false
    @State private var isReordering = false
    @State private var pendingDelete: Space?
    @State private var isShowingExtractionLog = false

    private var store: TabbyStore { TabbyStore(context: context) }

    var body: some View {
        content
            .navigationTitle("Spaces")
            .searchable(text: $searchText, prompt: "Name, handle, tag or note")
            .toolbar { toolbar }
            .sheet(item: $editor) { target in SpaceEditorView(space: target.space) }
            .sheet(isPresented: $isAddingPerson) { AddPersonView() }
            .sheet(isPresented: $isReordering) { ReorderSpacesView() }
            .sheet(isPresented: $isShowingExtractionLog) { ExtractionLogView() }
            .confirmationDialog(
                "Delete “\(pendingDelete?.name ?? "")”?",
                isPresented: Binding(isPresent: $pendingDelete),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { space in
                Button("Delete Space", role: .destructive) { store.delete(space) }
            } message: { _ in
                Text("People and tags are kept.")
            }
    }

    @ViewBuilder private var content: some View {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsView(people: SearchText.filter(people, query: searchText), query: searchText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if people.isEmpty {
                        FirstLaunchCard { isAddingPerson = true }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(tiles) { tile in
                            if let space = tile.space {
                                link(to: tile).contextMenu { menu(for: space) }
                            } else {
                                link(to: tile)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func link(to tile: SpaceTile) -> some View {
        NavigationLink(value: Route.space(tile.ref)) {
            SpaceTileView(tile: tile)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("space-tile-\(tile.title)")
    }

    private var tiles: [SpaceTile] {
        let facts = people.map(PersonFacts.init)
        let builtIns = BuiltInSpace.allCases.map { builtIn in
            SpaceTile(ref: .builtIn(builtIn), space: nil, title: builtIn.title, icon: builtIn.icon,
                      color: .accentColor, members: facts.members(of: builtIn))
        }
        let ordered = spaces.filter(\.isPinned) + spaces.filter { !$0.isPinned }
        let custom = ordered.map { space in
            SpaceTile(ref: .custom(space.id), space: space, title: space.name, icon: space.icon,
                      color: TabbyPalette.color(space.colorIndex), members: facts.members(of: space.rule))
        }
        return builtIns + custom
    }

    @ViewBuilder private func menu(for space: Space) -> some View {
        Button {
            store.setPinned(!space.isPinned, for: space)
        } label: {
            Label(space.isPinned ? "Unpin" : "Pin", systemImage: space.isPinned ? "pin.slash" : "pin")
        }
        Button { editor = .edit(space) } label: { Label("Edit", systemImage: "pencil") }
        Button { isReordering = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
        Button(role: .destructive) { pendingDelete = space } label: { Label("Delete", systemImage: "trash") }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink(value: Route.tags) {
                Label("Tags", systemImage: "tag")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { isAddingPerson = true } label: { Label("Add person", systemImage: "person.badge.plus") }
                Button { editor = .new } label: { Label("New Space", systemImage: "square.grid.2x2") }
                if !spaces.isEmpty {
                    Button { isReordering = true } label: { Label("Reorder Spaces", systemImage: "arrow.up.arrow.down") }
                }
                #if DEBUG
                Divider()
                Button { SampleData.seed(into: context) } label: { Label("Add sample data", systemImage: "wand.and.stars") }
                Button { isShowingExtractionLog = true } label: { Label("Extraction log", systemImage: "list.bullet.clipboard") }
                #endif
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }
}

enum SpaceEditorTarget: Identifiable {
    case new
    case edit(Space)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let space): space.id.uuidString
        }
    }

    var space: Space? {
        if case .edit(let space) = self { return space }
        return nil
    }
}

struct SpaceTile: Identifiable {
    let ref: SpaceRef
    let space: Space?
    let title: String
    let icon: String
    let color: Color
    let members: [Person]

    var id: SpaceRef { ref }
    var isPinned: Bool { space?.isPinned ?? false }
}

struct SpaceTileView: View {
    let tile: SpaceTile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: tile.icon)
                    .font(.title3)
                    .foregroundStyle(tile.color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tile.color.opacity(0.15)))
                Spacer()
                if tile.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(tile.title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text("\(tile.members.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                AvatarStack(people: Array(tile.members.prefix(3)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.title), \(tile.members.count) people")
    }
}

struct AvatarStack: View {
    let people: [Person]
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(people) { person in
                AvatarView(person: person, size: size)
                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
            }
        }
    }
}

struct SearchResultsView: View {
    let people: [Person]
    let query: String

    var body: some View {
        if people.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(people) { person in
                NavigationLink(value: Route.person(person.id)) {
                    PersonRow(person: person)
                }
                .accessibilityIdentifier("person-row-\(person.title)")
            }
            .listStyle(.plain)
        }
    }
}

/// First launch: how to get the first person in.
struct FirstLaunchCard: View {
    let onAddManually: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save your first person")
                .font(.title3.bold())
            step(1, symbol: "square.and.arrow.up", title: "Pin Tabby in the share sheet",
                 detail: "Tap Share on any profile, scroll the app row to More, and add Tabby to Favorites.")
            step(2, symbol: "person.crop.circle.badge.plus", title: "Share a profile",
                 detail: "On Instagram, TikTok or LinkedIn, open a profile, tap Share and pick Tabby.")
            step(3, symbol: "tag", title: "Add a tag", detail: "Tags decide which Spaces people show up in.")
            Button(action: onAddManually) {
                Label("Or paste a profile link", systemImage: "link")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func step(_ number: Int, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)").font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Spaces") {
    NavigationStack { SpacesView() }
        .modelContainer(SampleData.previewContainer())
}

#Preview("Empty") {
    NavigationStack { SpacesView() }
        .modelContainer(try! TabbyContainer.make(inMemory: true))
}
