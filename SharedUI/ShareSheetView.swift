import SwiftData
import SwiftUI
import TabbyKit

/// Full-height sheet: preview (every field editable), tags, note, Save pinned above the keyboard,
/// then a "Saved to Tabby!" state with Open in Tabby / Done.
struct ShareSheetView: View {
    @Bindable var flow: ShareFlow
    let onClose: () -> Void
    let onOpenInTabby: () -> Void
    @Query private var tags: [Tag]

    private var isSaved: Bool {
        if case .saved = flow.phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Tabby").font(.headline.weight(.heavy))
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        if !isSaved {
                            Button("Cancel", action: onClose)
                        }
                    }
                }
        }
        .sensoryFeedback(.success, trigger: isSaved)
    }

    @ViewBuilder private var content: some View {
        switch flow.phase {
        case .loading:
            ProgressView("Reading the link…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noLink:
            ContentUnavailableView("No profile link", systemImage: "link",
                                   description: Text("Share a LinkedIn, Instagram or TikTok profile to save it to Tabby."))
        case .editing:
            editor
        case .saved(_, let name):
            SavedView(name: name, isDraft: flow.savedAsDraft, onOpenInTabby: onOpenInTabby, onDone: onClose)
        }
    }

    private var editor: some View {
        Form {
            if flow.isTeaching {
                Section {
                    TeachingChecklist(flow: flow)
                } header: {
                    Text("Your first save")
                } footer: {
                    Text("Tags and a reason are what make someone easy to find later.")
                }
            }
            if flow.willLock {
                Section {
                    Label("You've used your free Tab. This one saves as a draft until you unlock Tabby.", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            if let notice = flow.notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                        .font(.subheadline)
                }
            }
            if let existing = flow.existingName {
                Section {
                    Label("Already in Tabby as \(existing). Saving updates them.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
            Section {
                PreviewCard(draft: $flow.draft, isImporting: flow.isImporting)
            }
            Section("Tags") {
                TagPicker(tags: Tag.shareSheetOrder(tags), selection: $flow.draft.tagIDs) {
                    flow.createTag(named: $0)
                }
                .padding(.vertical, 4)
            }
            Section("Why I saved them") {
                TextField("e.g. Great packaging work, possible collaborator", text: $flow.draft.note, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("share-note")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                Button {
                    flow.save()
                } label: {
                    Text(flow.saveButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!flow.canSave)
                .accessibilityIdentifier("share-save")
                if flow.isTeaching {
                    Button("Skip and save") { flow.skipTeaching() }
                        .font(.subheadline)
                        .accessibilityIdentifier("share-skip")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .alert("Couldn't save", isPresented: Binding(isPresent: $flow.saveError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(flow.saveError ?? "")
        }
    }
}

/// Avatar, name, handle, platform, headline, bio (3 lines until expanded) and link chips.
struct PreviewCard: View {
    @Binding var draft: PersonDraft
    let isImporting: Bool
    @State private var isBioExpanded = false

    private var handleText: String {
        if !draft.handle.isEmpty { return "@" + draft.handle }
        return draft.profileURL?.host ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(name: draft.displayName.isEmpty ? draft.handle : draft.displayName,
                           imageData: draft.avatarData, imageURL: draft.avatarURL, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $draft.displayName)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("preview-name")
                    HStack(spacing: 6) {
                        PlatformBadge(platform: draft.platform, showsName: true)
                        Text(handleText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Importing…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Headline", text: $draft.headline, axis: .vertical)
                .font(.subheadline)
            TextField("Bio", text: $draft.bio, axis: .vertical)
                .font(.subheadline)
                .lineLimit(isBioExpanded ? 20 : 3)
            if draft.bio.count > 120 {
                Button(isBioExpanded ? "Show less" : "Show more") { isBioExpanded.toggle() }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            if !draft.links.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(draft.links, id: \.self) { url in
                        Label(url.host ?? url.absoluteString, systemImage: "link")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// First-save lesson: check the details, add a tag, say why. Import unlocks when all three are done.
struct TeachingChecklist: View {
    @Bindable var flow: ShareFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ShareFlow.TeachingItem.allCases, id: \.self) { item in
                let done = flow.isDone(item)
                HStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(done ? Color.green : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(item.title)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary)
                    Spacer()
                    if item == .details, !done {
                        Button("Looks right") { flow.hasConfirmedDetails = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("share-confirm-details")
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .animation(.default, value: ShareFlow.TeachingItem.allCases.map(flow.isDone))
    }
}

/// Modeled on ReciMe's "Recipe saved!" screen. A locked draft gets "Unlock in Tabby" instead.
struct SavedView: View {
    let name: String
    var isDraft = false
    let onOpenInTabby: () -> Void
    let onDone: () -> Void
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isDraft ? "lock.fill" : "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(isDraft ? Color.orange : Color.accentColor)
                .symbolEffect(.bounce, value: hasAppeared)
            Text(isDraft ? "Saved as a draft" : "Saved to Tabby!")
                .font(.title2.bold())
            Text(name)
                .font(.headline)
                .foregroundStyle(.secondary)
            if isDraft {
                Text("Unlock Tabby to open them and keep saving.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: onOpenInTabby) {
                HStack {
                    Text(isDraft ? "Unlock in Tabby" : "Open in Tabby")
                    Image(systemName: "arrow.up.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Done", action: onDone)
                .font(.headline)
                .padding(.vertical, 8)
        }
        .padding(24)
        .onAppear { hasAppeared = true }
    }
}
