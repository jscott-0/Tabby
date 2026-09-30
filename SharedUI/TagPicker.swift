import SwiftData
import SwiftUI
import TabbyKit

struct TagChip: View {
    let name: String
    let colorIndex: Int
    var isSelected = true
    var compact = false

    init(name: String, colorIndex: Int, isSelected: Bool = true, compact: Bool = false) {
        self.name = name
        self.colorIndex = colorIndex
        self.isSelected = isSelected
        self.compact = compact
    }

    init(tag: Tag, isSelected: Bool = true, compact: Bool = false) {
        self.init(name: tag.name, colorIndex: tag.colorIndex, isSelected: isSelected, compact: compact)
    }

    private var color: Color { TabbyPalette.color(colorIndex) }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
            Text(name).lineLimit(1)
        }
        .font(compact ? .caption : .subheadline)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 2 : 6)
        .background(Capsule().fill(isSelected ? color.opacity(0.18) : Color.secondary.opacity(0.08)))
        .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.6) : Color.clear, lineWidth: 1))
    }
}

/// Tap to toggle tags, plus a "New tag" chip that creates one inline and selects it.
struct TagPicker: View {
    /// Already in display order (see `Tag.shareSheetOrder`).
    let tags: [Tag]
    @Binding var selection: Set<UUID>
    /// Finds or creates a tag with that name.
    let onCreate: (String) -> Tag?

    @State private var isAdding = false
    @State private var newName = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                let selected = selection.contains(tag.id)
                Button {
                    toggle(tag.id)
                } label: {
                    TagChip(tag: tag, isSelected: selected)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if isAdding {
                TextField("Tag name", text: $newName)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFieldFocused)
                    .onSubmit(commit)
                    .frame(width: 140)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                    .onAppear { DispatchQueue.main.async { isFieldFocused = true } }
            } else {
                Button {
                    newName = ""
                    isAdding = true
                } label: {
                    Label("New tag", systemImage: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy, value: selection)
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func commit() {
        if let tag = onCreate(newName) {
            selection.insert(tag.id)
        }
        newName = ""
        isAdding = false
    }
}
