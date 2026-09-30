import SwiftData
import SwiftUI
import TabbyKit

/// All tags with counts and colors: rename, recolor, merge, delete.
struct TagsView: View {
    @Environment(\.modelContext) private var context
    @Query private var tags: [Tag]
    @State private var renaming: Tag?
    @State private var renameText = ""
    @State private var merging: Tag?
    @State private var deleting: Tag?
    @State private var isAdding = false
    @State private var newName = ""
    @State private var errorMessage: String?

    private var store: TabbyStore { TabbyStore(context: context) }

    private var sortedTags: [Tag] {
        tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(sortedTags) { tag in
                HStack(spacing: 12) {
                    Circle()
                        .fill(TabbyPalette.color(tag.colorIndex))
                        .frame(width: 12, height: 12)
                    Text(tag.name)
                    Spacer()
                    Text("\(tag.peopleCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .contextMenu { menu(for: tag) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleting = tag } label: { Label("Delete", systemImage: "trash") }
                    Button { beginRename(tag) } label: { Label("Rename", systemImage: "pencil") }
                        .tint(.orange)
                }
            }
        }
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView("No tags yet", systemImage: "tag",
                                       description: Text("Create tags when you save someone, or add one here."))
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    isAdding = true
                } label: {
                    Label("New tag", systemImage: "plus")
                }
            }
        }
        .alert("New tag", isPresented: $isAdding) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.never)
            Button("Add") { _ = store.findOrCreateTag(named: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename tag", isPresented: Binding(isPresent: $renaming)) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.never)
            Button("Save") {
                if let tag = renaming { rename(tag) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $merging) { tag in
            MergeTagSheet(sourceName: tag.name, candidates: sortedTags.filter { $0.id != tag.id }) { target in
                store.merge(tag, into: target)
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(isPresent: $deleting),
            titleVisibility: .visible,
            presenting: deleting
        ) { tag in
            Button("Delete tag", role: .destructive) { store.delete(tag) }
        } message: { tag in
            Text("It will be removed from \(tag.peopleCount) \(tag.peopleCount == 1 ? "person" : "people") and from any Space rules. No one is deleted.")
        }
        .alert("Couldn't rename", isPresented: Binding(isPresent: $errorMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder private func menu(for tag: Tag) -> some View {
        Button { beginRename(tag) } label: { Label("Rename", systemImage: "pencil") }
        Menu {
            ForEach(TabbyPalette.colors.indices, id: \.self) { index in
                Button {
                    store.recolor(tag, colorIndex: index)
                } label: {
                    if index == tag.colorIndex {
                        Label(TabbyPalette.names[index], systemImage: "checkmark")
                    } else {
                        Text(TabbyPalette.names[index])
                    }
                }
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
        Button { merging = tag } label: { Label("Merge into…", systemImage: "arrow.triangle.merge") }
            .disabled(tags.count < 2)
        Button(role: .destructive) { deleting = tag } label: { Label("Delete", systemImage: "trash") }
    }

    private func beginRename(_ tag: Tag) {
        renameText = tag.name
        renaming = tag
    }

    private func rename(_ tag: Tag) {
        let attempted = renameText
        do {
            try store.rename(tag, to: attempted)
        } catch {
            let message = (error as? TabbyStoreError) == .tagNameTaken
                ? "Another tag is already called “\(Tag.normalizedName(attempted))”. Use Merge to combine them."
                : "Tag names can't be empty."
            // Let the rename alert finish dismissing before showing this one.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                errorMessage = message
            }
        }
    }
}

/// Pick the tag to merge into. Takes the source's name, not the tag, since the tag is deleted by the merge.
struct MergeTagSheet: View {
    let sourceName: String
    let candidates: [Tag]
    let onMerge: (Tag) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { tag in
                Button {
                    dismiss()
                    onMerge(tag)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(TabbyPalette.color(tag.colorIndex))
                            .frame(width: 12, height: 12)
                        Text(tag.name).foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(tag.peopleCount)").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Merge “\(sourceName)” into")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { TagsView() }
        .modelContainer(SampleData.previewContainer())
}
