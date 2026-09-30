import SwiftData
import SwiftUI
import TabbyKit

/// "Paste a profile link": tier 1 parse as you type, then fetch tiers 2–3 to pre-fill.
/// Saving a profile that's already in Tabby merges into it.
struct AddPersonView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tags: [Tag]
    @State private var link = ""
    @State private var parsed: ParsedProfileURL?
    @State private var draft: PersonDraft?
    @State private var existing: Person?
    @State private var isImporting = false
    @State private var saveError: String?

    private var store: TabbyStore { TabbyStore(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.instagram.com/…", text: $link, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        guard let first = strings.first else { return }
                        Task { @MainActor in link = first }
                    }
                } header: {
                    Text("Profile link")
                } footer: {
                    if let hint { Text(hint) }
                }

                if let draft = Binding($draft) {
                    Section {
                        HStack {
                            PlatformBadge(platform: draft.wrappedValue.platform, showsName: true)
                            Text(handleLabel(draft.wrappedValue)).lineLimit(1)
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                        if existing != nil {
                            Label("Already in Tabby. Saving updates them.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    Section("Details") {
                        TextField("Name", text: draft.displayName)
                        TextField("Headline", text: draft.headline, axis: .vertical)
                        TextField("Bio", text: draft.bio, axis: .vertical)
                            .lineLimit(1...6)
                    }
                    Section("Tags") {
                        TagPicker(tags: Tag.shareSheetOrder(tags), selection: draft.tagIDs) {
                            store.findOrCreateTag(named: $0)
                        }
                        .padding(.vertical, 4)
                    }
                    Section("Why I saved them") {
                        TextField("e.g. Great packaging work, possible collaborator", text: draft.note, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
            }
            .navigationTitle("Add person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft == nil)
                }
            }
            .onChange(of: link) { _, newValue in reparse(newValue) }
            .task(id: parsed?.url) { await importMetadata() }
            .alert("Couldn't save", isPresented: Binding(isPresent: $saveError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var hint: String? {
        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let parsed else { return "That doesn't look like a link." }
        switch parsed.kind {
        case .profile:
            return nil
        case .post(let author):
            return author == nil
                ? "This looks like a post, not a profile. It will be saved as a link."
                : "This looks like a post, not a profile. Saving its author."
        case .shortLink:
            return isImporting ? "Opening the short link…" : nil
        case .unknown:
            return "Not a LinkedIn, Instagram or TikTok profile. It will be saved as a link."
        }
    }

    private func handleLabel(_ draft: PersonDraft) -> String {
        if !draft.handle.isEmpty { return "@" + draft.handle }
        return draft.profileURL?.host ?? ""
    }

    private func reparse(_ text: String) {
        guard let url = ProfileURLParser.firstURL(in: text) else {
            parsed = nil
            draft = nil
            existing = nil
            return
        }
        let newParsed = ProfileURLParser.parse(url)
        guard newParsed != parsed else { return }
        parsed = newParsed
        var newDraft = PersonDraft(parsed: newParsed)
        existing = store.existingPerson(for: newDraft)
        if let existing { preselect(existing, into: &newDraft) }
        draft = newDraft
    }

    /// A duplicate starts from what's saved: its tags pre-selected, its name kept.
    private func preselect(_ person: Person, into draft: inout PersonDraft) {
        draft.tagIDs.formUnion((person.tags ?? []).map(\.id))
        if draft.displayName.isEmpty { draft.displayName = person.displayName }
    }

    private func importMetadata() async {
        guard let parsed else { return }
        let target = parsed.authorProfile ?? parsed
        guard target.kind == .profile || target.kind == .shortLink else { return }
        isImporting = true
        defer { isImporting = false }
        let result = await MetadataFetcher().fetch(target)
        guard !Task.isCancelled, var current = draft else { return }
        current.apply(result)
        if existing == nil, let match = store.existingPerson(for: current) {
            existing = match
            preselect(match, into: &current)
        }
        draft = current
    }

    private func save() {
        guard let draft else { return }
        do {
            try store.save(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    AddPersonView()
        .modelContainer(SampleData.previewContainer())
}
