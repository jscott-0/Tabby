import SwiftData
import SwiftUI
import TabbyKit

/// Large avatar, accounts with "Open in app", bio, links, tags, note and added date.
struct PersonDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [Person]
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    init(personID: UUID) {
        _matches = Query(filter: #Predicate<Person> { $0.id == personID })
    }

    private var store: TabbyStore { TabbyStore(context: context) }

    var body: some View {
        if let person = matches.first {
            PersonDetailContent(person: person)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { isConfirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $isEditing) { PersonEditorView(person: person) }
                .confirmationDialog("Delete \(person.title)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        dismiss()
                        store.delete([person])
                    }
                } message: {
                    Text("They'll be removed from every Space. Tags are kept.")
                }
                .onAppear { store.markViewed(person) }
        } else {
            ContentUnavailableView("Not found", systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text("This person may have been deleted."))
        }
    }
}

private struct PersonDetailContent: View {
    let person: Person

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    AvatarView(person: person, size: 96)
                    Text(person.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !person.headline.isEmpty {
                        Text(person.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section(person.sortedAccounts.count > 1 ? "Accounts" : "Account") {
                ForEach(person.sortedAccounts) { account in
                    AccountRow(account: account)
                }
            }

            if let bio = person.primaryAccount?.bio, !bio.isEmpty {
                Section("Bio") {
                    Text(bio).textSelection(.enabled)
                }
            }

            if let links = person.primaryAccount?.links, !links.isEmpty {
                Section("Links") {
                    FlowLayout(spacing: 8) {
                        ForEach(links, id: \.self) { url in
                            Link(destination: url) {
                                Label(url.host ?? url.absoluteString, systemImage: "link")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Tags") {
                if person.sortedTags.isEmpty {
                    Text("No tags").foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(person.sortedTags) { TagChip(tag: $0) }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Why I saved them") {
                if person.note.isEmpty {
                    Text("No note").foregroundStyle(.secondary)
                } else {
                    Text(person.note).textSelection(.enabled)
                }
            }

            Section {
                LabeledContent("Added", value: person.createdAt.formatted(date: .abbreviated, time: .omitted))
                if person.needsInfo {
                    Label("Details couldn't be fetched. Edit to fill them in.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(person.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountRow: View {
    let account: Account
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            PlatformBadge(platform: account.platform, showsName: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayHandle).lineLimit(1)
                if let followers = account.followerCount {
                    Text("\(followers.formatted(.number.notation(.compactName))) followers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let url = account.profileURL {
                Button("Open in app") { openURL(url) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

/// Edit name, headline, bio, tags and note.
struct PersonEditorView: View {
    let person: Person
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tags: [Tag]
    @State private var draft: PersonDraft

    init(person: Person) {
        self.person = person
        _draft = State(initialValue: PersonDraft(person: person))
    }

    private var store: TabbyStore { TabbyStore(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $draft.displayName)
                        .textContentType(.name)
                }
                Section("Headline") {
                    TextField("e.g. Industrial Designer · Northwind Labs", text: $draft.headline, axis: .vertical)
                }
                Section("Bio") {
                    TextField("Bio", text: $draft.bio, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Tags") {
                    TagPicker(tags: Tag.shareSheetOrder(tags), selection: $draft.tagIDs) {
                        store.findOrCreateTag(named: $0)
                    }
                    .padding(.vertical, 4)
                }
                Section("Why I saved them") {
                    TextField("e.g. Great packaging work, possible collaborator", text: $draft.note, axis: .vertical)
                        .lineLimit(2...8)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(person, with: draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let container = SampleData.previewContainer()
    let person = try! container.mainContext.fetch(FetchDescriptor<Person>()).first!
    return NavigationStack { PersonDetailView(personID: person.id) }
        .modelContainer(container)
}
