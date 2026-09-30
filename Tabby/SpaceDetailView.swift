import SwiftData
import SwiftUI
import TabbyKit

/// People in a Space, with tag / platform filter chips, sorting, swipe to retag or delete,
/// and multi-select to bulk tag.
struct SpaceDetailView: View {
    let ref: SpaceRef
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt, order: .reverse) private var people: [Person]
    @Query private var matchingSpaces: [Space]
    @State private var sort: PersonSort = .recent
    @State private var tagFilter: Set<UUID> = []
    @State private var platformFilter: Platform?
    @State private var selection: Set<UUID> = []
    @State private var editMode: EditMode = .inactive
    @State private var retagging: Person?
    @State private var isBulkTagging = false
    @State private var isEditingRule = false

    init(ref: SpaceRef) {
        self.ref = ref
        let spaceID: UUID
        if case .custom(let id) = ref {
            spaceID = id
        } else {
            spaceID = UUID()
        }
        _matchingSpaces = Query(filter: #Predicate<Space> { $0.id == spaceID })
    }

    private var store: TabbyStore { TabbyStore(context: context) }
    private var space: Space? { matchingSpaces.first }

    private var title: String {
        switch ref {
        case .builtIn(let builtIn): builtIn.title
        case .custom: space?.name ?? "Space"
        }
    }

    var body: some View {
        let members = computeMembers()
        let visible = sort.sorted(members.filter(passesFilters))
        Group {
            if members.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(visible) { person in
                        NavigationLink(value: Route.person(person.id)) {
                            PersonRow(person: person)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete([person])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                retagging = person
                            } label: {
                                Label("Tags", systemImage: "tag")
                            }
                            .tint(.indigo)
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
                .overlay {
                    if visible.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("No one here has all the selected filters."))
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    FilterBar(people: members, tagFilter: $tagFilter, platformFilter: $platformFilter)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if editMode.isEditing {
                        selectionBar(visible: visible)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button("Done") {
                        editMode = .inactive
                        selection = []
                    }
                } else {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(PersonSort.allCases) { Text($0.title).tag($0) }
                        }
                        if !members.isEmpty {
                            Button { editMode = .active } label: { Label("Select", systemImage: "checkmark.circle") }
                        }
                        if space != nil {
                            Button { isEditingRule = true } label: { Label("Edit rule", systemImage: "slider.horizontal.3") }
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $retagging) { person in
            TagSelectionSheet(title: "Tags for \(person.title)", initial: Set((person.tags ?? []).map(\.id)), confirmTitle: "Save") { ids in
                store.setTags(ids, for: person)
            }
        }
        .sheet(isPresented: $isBulkTagging) {
            TagSelectionSheet(title: "Add tags to \(selection.count)", initial: [], confirmTitle: "Add") { ids in
                store.addTags(ids, to: people.filter { selection.contains($0.id) })
                selection = []
                editMode = .inactive
            }
        }
        .sheet(isPresented: $isEditingRule) {
            if let space { SpaceEditorView(space: space) }
        }
    }

    private func computeMembers() -> [Person] {
        let facts = people.map(PersonFacts.init)
        switch ref {
        case .builtIn(let builtIn):
            return facts.members(of: builtIn)
        case .custom:
            guard let space else { return [] }
            return facts.members(of: space.rule)
        }
    }

    private func passesFilters(_ person: Person) -> Bool {
        let tagIDs = Set((person.tags ?? []).map(\.id))
        guard tagFilter.isSubset(of: tagIDs) else { return false }
        guard let platformFilter else { return true }
        return (person.accounts ?? []).contains { $0.platform == platformFilter }
    }

    private func selectionBar(visible: [Person]) -> some View {
        HStack {
            Button("Select all") { selection = Set(visible.map(\.id)) }
            Spacer()
            Button {
                isBulkTagging = true
            } label: {
                Label("Tag \(selection.count)", systemImage: "tag")
            }
            .disabled(selection.isEmpty)
            Button(role: .destructive) {
                store.delete(people.filter { selection.contains($0.id) })
                selection = []
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder private var emptyState: some View {
        switch ref {
        case .builtIn(let builtIn):
            ContentUnavailableView(builtIn.title, systemImage: builtIn.icon, description: Text(builtIn.emptyMessage))
        case .custom:
            if let space {
                ContentUnavailableView {
                    Label(space.rule.isEmpty ? "This Space has no tags" : "No one here yet", systemImage: space.icon)
                } description: {
                    Text(space.rule.isEmpty
                         ? "Pick tags to decide who shows up here."
                         : "Rule: \(space.ruleSummary)")
                } actions: {
                    Button("Edit rule") { isEditingRule = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView("Space deleted", systemImage: "square.dashed")
            }
        }
    }
}

/// Tag and platform chips that narrow a Space's list. Only shows what its people actually have.
struct FilterBar: View {
    let people: [Person]
    @Binding var tagFilter: Set<UUID>
    @Binding var platformFilter: Platform?

    private var availableTags: [Tag] {
        var seen = Set<UUID>()
        var result: [Tag] = []
        for person in people {
            for tag in person.tags ?? [] where seen.insert(tag.id).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var availablePlatforms: [Platform] {
        let present = Set(people.flatMap { ($0.accounts ?? []).map(\.platform) })
        return Platform.allCases.filter { present.contains($0) }
    }

    var body: some View {
        let tags = availableTags
        let platforms = availablePlatforms
        if !tags.isEmpty || platforms.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if platforms.count > 1 {
                        ForEach(platforms, id: \.self) { platform in
                            platformChip(platform)
                        }
                    }
                    ForEach(tags) { tag in
                        Button {
                            if tagFilter.contains(tag.id) {
                                tagFilter.remove(tag.id)
                            } else {
                                tagFilter.insert(tag.id)
                            }
                        } label: {
                            TagChip(tag: tag, isSelected: tagFilter.contains(tag.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private func platformChip(_ platform: Platform) -> some View {
        let selected = platformFilter == platform
        return Button {
            platformFilter = selected ? nil : platform
        } label: {
            Label(platform.displayName, systemImage: platform.symbol)
                .font(.subheadline)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? platform.tint : Color.secondary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

/// A row in any people list: avatar, name, platform badge, headline, first 3 tags.
struct PersonRow: View {
    let person: Person

    private var subtitle: String? {
        let headline = person.headline
        if !headline.isEmpty { return headline }
        guard let handle = person.primaryAccount?.displayHandle, handle != person.title else { return nil }
        return handle
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(person: person, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let platform = person.primaryAccount?.platform {
                        PlatformBadge(platform: platform)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                let tags = Array(person.sortedTags.prefix(3))
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags) { TagChip(tag: $0, compact: true) }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Pick tags in a sheet: retag one person, or add tags to a selection.
struct TagSelectionSheet: View {
    let title: String
    let confirmTitle: String
    let onConfirm: (Set<UUID>) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tags: [Tag]
    @State private var selection: Set<UUID>

    init(title: String, initial: Set<UUID>, confirmTitle: String, onConfirm: @escaping (Set<UUID>) -> Void) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        _selection = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TagPicker(tags: Tag.shareSheetOrder(tags), selection: $selection) {
                    TabbyStore(context: context).findOrCreateTag(named: $0)
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        onConfirm(selection)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack { SpaceDetailView(ref: .builtIn(.all)) }
        .modelContainer(SampleData.previewContainer())
}
