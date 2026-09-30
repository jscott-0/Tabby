import SwiftData
import SwiftUI
import TabbyKit

/// Name, icon, color, ANY/ALL, tags, platform filter and a live count of who matches.
struct SpaceEditorView: View {
    let space: Space?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tags: [Tag]
    @Query private var people: [Person]
    @State private var draft: SpaceDraft
    @State private var isConfirmingDelete = false

    init(space: Space?) {
        self.space = space
        _draft = State(initialValue: space.map { SpaceDraft(space: $0) } ?? SpaceDraft())
    }

    private var store: TabbyStore { TabbyStore(context: context) }

    private var matchCount: Int {
        let rule = draft.rule
        return people.filter { rule.matches(PersonFacts($0)) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                }
                Section("Icon") {
                    IconGrid(selection: $draft.icon, color: TabbyPalette.color(draft.colorIndex))
                }
                Section("Color") {
                    ColorGrid(selection: $draft.colorIndex)
                }
                Section {
                    Picker("Match", selection: $draft.matchAll) {
                        Text("Any of these tags").tag(false)
                        Text("All of these tags").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TagPicker(tags: Tag.shareSheetOrder(tags), selection: $draft.tagIDs) {
                        store.findOrCreateTag(named: $0)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Rule")
                } footer: {
                    if draft.tagIDs.isEmpty {
                        Text("Pick at least one tag.")
                    } else {
                        Text("\(matchCount) \(matchCount == 1 ? "person matches" : "people match") right now.")
                    }
                }
                Section {
                    ForEach(Platform.social, id: \.self) { platform in
                        Toggle(isOn: binding(for: platform)) {
                            Label(platform.displayName, systemImage: platform.symbol)
                        }
                    }
                } header: {
                    Text("Platforms")
                } footer: {
                    Text("Leave all off to include every platform.")
                }
                if space != nil {
                    Section {
                        Button("Delete Space", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .navigationTitle(space == nil ? "New Space" : "Edit Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.canSave)
                }
            }
            .confirmationDialog("Delete this Space?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Space", role: .destructive) {
                    guard let space else { return }
                    dismiss()
                    store.delete(space)
                }
            } message: {
                Text("People and tags are kept.")
            }
        }
    }

    private func binding(for platform: Platform) -> Binding<Bool> {
        Binding {
            draft.platforms.contains(platform)
        } set: { isOn in
            if isOn {
                draft.platforms.insert(platform)
            } else {
                draft.platforms.remove(platform)
            }
        }
    }

    private func save() {
        do {
            if let space {
                try store.update(space, with: draft)
            } else {
                try store.createSpace(draft)
            }
            dismiss()
        } catch {
            // canSave guarantees a name; nothing else throws.
        }
    }
}

struct IconGrid: View {
    @Binding var selection: String
    let color: Color

    static let symbols = [
        "folder.fill", "star.fill", "heart.fill", "briefcase.fill", "paintbrush.fill", "hammer.fill",
        "cpu", "camera.fill", "music.note", "fork.knife", "figure.run", "building.2.fill",
        "graduationcap.fill", "lightbulb.fill", "sparkles", "leaf.fill", "airplane", "cart.fill",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(Self.symbols, id: \.self) { symbol in
                let selected = selection == symbol
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(selected ? Color.white : color)
                        .background(Circle().fill(selected ? color : color.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct ColorGrid: View {
    @Binding var selection: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
            ForEach(TabbyPalette.colors.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Circle()
                        .fill(TabbyPalette.color(index))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selection == index {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TabbyPalette.names[index])
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Drag to reorder custom Spaces. Pinned Spaces still show first on the grid.
struct ReorderSpacesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Space.sortOrder) private var spaces: [Space]

    var body: some View {
        NavigationStack {
            List {
                ForEach(spaces) { space in
                    Label(space.name, systemImage: space.icon)
                }
                .onMove { source, destination in
                    var ordered = spaces
                    ordered.move(fromOffsets: source, toOffset: destination)
                    TabbyStore(context: context).reorder(ordered)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Spaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SpaceEditorView(space: nil)
        .modelContainer(SampleData.previewContainer())
}
