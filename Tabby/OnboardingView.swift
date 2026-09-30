import AuthenticationServices
import SwiftData
import SwiftUI
import TabbyKit

/// Welcome → account → interests → first suggestion → waiting for the first save.
/// The step is kept in the App Group so a relaunch (e.g. after the share sheet) resumes it.
/// The first saved person, from the share sheet or a pasted link, ends onboarding.
struct OnboardingView: View {
    let model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt) private var people: [Person]
    @State private var step: OnboardingStep
    @State private var categoryIDs: Set<String>
    @State private var creatorIDs: [String]
    @State private var isAddingPerson = false

    init(model: AppModel) {
        self.model = model
        _step = State(initialValue: model.sharedDefaults.onboardingStep)
        _categoryIDs = State(initialValue: Set(model.sharedDefaults.interests))
        _creatorIDs = State(initialValue: model.sharedDefaults.pickedCreators)
    }

    private var suggestion: SuggestedCreator {
        OnboardingCatalog.firstSuggestion(pickedCreatorIDs: creatorIDs, categoryIDs: categoryIDs)
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeStep { go(to: .account) }
            case .account:
                AccountStep { profile in
                    model.sharedDefaults.account = profile
                    go(to: .interests)
                }
            case .interests:
                InterestsStep(categoryIDs: $categoryIDs, creatorIDs: $creatorIDs) { finishInterests() }
            case .firstSuggestion:
                FirstSuggestionStep(creator: suggestion, onOpened: { go(to: .awaitingFirstSave) },
                                    onPasteLink: { isAddingPerson = true })
            case .awaitingFirstSave:
                AwaitingFirstSaveStep(creator: suggestion, onPasteLink: { isAddingPerson = true },
                                      onSkip: { model.completeOnboarding(firstPersonID: nil) })
            }
        }
        .animation(.default, value: step)
        .sheet(isPresented: $isAddingPerson) { AddPersonView() }
        .onChange(of: people.count, initial: true) { _, count in
            // The share extension's save arrives as a reopened store; a pasted link saves here.
            guard count > 0, let first = people.first else { return }
            isAddingPerson = false
            model.completeOnboarding(firstPersonID: first.id)
        }
    }

    private func go(to next: OnboardingStep) {
        step = next
        model.sharedDefaults.onboardingStep = next
    }

    /// Picked categories become tags, so the first save has something to pick.
    private func finishInterests() {
        model.sharedDefaults.interests = categoryIDs.sorted()
        model.sharedDefaults.pickedCreators = creatorIDs
        let store = TabbyStore(context: context)
        for id in categoryIDs.sorted() {
            store.findOrCreateTag(named: id)
        }
        go(to: .firstSuggestion)
    }
}

// MARK: - Steps

private struct StepScaffold<Content: View>: View {
    let buttonTitle: String
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: action) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isEnabled)
            .accessibilityIdentifier("onboarding-continue")
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.background)
        }
    }
}

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        StepScaffold(buttonTitle: "Get started", action: onContinue) {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 48)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep tabs on people worth remembering")
                        .font(.largeTitle.bold())
                    Text("Save anyone from Instagram, TikTok or LinkedIn in two taps, and find them again when you need them.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    point("square.and.arrow.up", "Save from the share sheet")
                    point("tag.fill", "Tag them so they land in the right Space")
                    point("magnifyingglass", "Search by name, tag or why you saved them")
                }
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.body.weight(.medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}

/// Sign in with Apple, or an email address. Kept on the device until accounts reach the backend.
private struct AccountStep: View {
    let onSignedIn: (AccountProfile) -> Void
    @State private var email = ""
    @State private var error: String?
    @FocusState private var isEmailFocused: Bool

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        return trimmed[trimmed.index(after: at)...].contains(".") && !trimmed.contains(" ")
    }

    var body: some View {
        StepScaffold(buttonTitle: "Continue with email", isEnabled: isValidEmail, action: continueWithEmail) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Create your account")
                    .font(.largeTitle.bold())
                    .padding(.top, 32)
                Text("So your Tabs are safe if you change phones.")
                    .foregroundStyle(.secondary)
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                HStack {
                    VStack { Divider() }
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    VStack { Divider() }
                }
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isEmailFocused)
                    .submitLabel(.continue)
                    .onSubmit { if isValidEmail { continueWithEmail() } }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .accessibilityIdentifier("onboarding-email")
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private func continueWithEmail() {
        onSignedIn(AccountProfile(id: UUID().uuidString, method: .email,
                                  email: email.trimmingCharacters(in: .whitespaces).lowercased()))
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            onSignedIn(AccountProfile(id: credential.user, method: .apple, email: credential.email,
                                      name: name?.isEmpty == false ? name : nil))
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = "Sign in with Apple didn't work. Try again, or use your email."
        }
    }
}

private struct InterestsStep: View {
    @Binding var categoryIDs: Set<String>
    @Binding var creatorIDs: [String]
    let onContinue: () -> Void

    var body: some View {
        StepScaffold(buttonTitle: categoryIDs.isEmpty ? "Skip" : "Continue", action: onContinue) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Who do you want to keep tabs on?")
                    .font(.largeTitle.bold())
                    .padding(.top, 32)
                Text("Pick a few. They become your first tags.")
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(OnboardingCatalog.categories) { category in
                        chip(category)
                    }
                }
                if !categoryIDs.isEmpty {
                    Text("Try saving one of these")
                        .font(.headline)
                        .padding(.top, 8)
                    VStack(spacing: 8) {
                        ForEach(OnboardingCatalog.creators(in: categoryIDs)) { creator in
                            creatorRow(creator)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ category: InterestCategory) -> some View {
        let selected = categoryIDs.contains(category.id)
        return Button {
            if selected {
                categoryIDs.remove(category.id)
                let removed = Set(OnboardingCatalog.creators.filter { $0.categoryID == category.id }.map(\.id))
                creatorIDs.removeAll { removed.contains($0) }
            } else {
                categoryIDs.insert(category.id)
            }
        } label: {
            Label(category.title, systemImage: category.icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("interest-\(category.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func creatorRow(_ creator: SuggestedCreator) -> some View {
        let selected = creatorIDs.contains(creator.id)
        return Button {
            if selected {
                creatorIDs.removeAll { $0 == creator.id }
            } else {
                creatorIDs.append(creator.id)
            }
        } label: {
            HStack(spacing: 12) {
                AvatarView(name: creator.name, imageData: nil, imageURL: nil, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(creator.name).font(.body.weight(.semibold))
                    HStack(spacing: 6) {
                        PlatformBadge(platform: creator.platform)
                        Text("@" + creator.handle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("creator-\(creator.id)")
    }
}

/// How to share a profile to Tabby, then a button straight to one.
private struct FirstSuggestionStep: View {
    let creator: SuggestedCreator
    let onOpened: () -> Void
    let onPasteLink: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepScaffold(buttonTitle: "Open @\(creator.handle) in \(creator.platform.displayName)", action: open) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Save your first person")
                    .font(.largeTitle.bold())
                    .padding(.top, 32)
                Text("Tabby lives in the share sheet. Here's the whole trick:")
                    .foregroundStyle(.secondary)
                ShareHowTo(platform: creator.platform)
                Button("Paste a link instead", action: onPasteLink)
                    .font(.subheadline)
                    .accessibilityIdentifier("onboarding-paste-link")
            }
        }
    }

    private func open() {
        onOpened()
        if let url = creator.profileURL { openURL(url) }
    }
}

/// While the user is off in Instagram / TikTok. Coming back without a save lands here.
private struct AwaitingFirstSaveStep: View {
    let creator: SuggestedCreator
    let onPasteLink: () -> Void
    let onSkip: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepScaffold(buttonTitle: "Open @\(creator.handle) again", action: reopen) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Waiting for your first save")
                    .font(.largeTitle.bold())
                    .padding(.top, 32)
                ShareHowTo(platform: creator.platform)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Didn't see Tabby in the share sheet?", systemImage: "questionmark.circle.fill")
                        .font(.headline)
                    Text("Scroll the row of apps to the end, tap More, then Edit and add Tabby to Favorites. It stays at the front after that.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Paste a profile link instead", action: onPasteLink)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding-paste-link")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
                Button("Skip for now", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func reopen() {
        if let url = creator.profileURL { openURL(url) }
    }
}

/// Three frames: open a profile, tap Share, pick Tabby.
private struct ShareHowTo: View {
    let platform: Platform

    private var shareHint: String {
        switch platform {
        case .instagram: "Tap ••• on the profile, then Share this profile."
        case .tiktok: "Tap the share arrow on the profile, then More."
        case .linkedin: "Tap ••• on the profile, then Share via…"
        case .other: "Tap Share."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            frame(1, symbol: "person.crop.circle", title: "Open a profile", detail: "In \(platform.displayName).")
            frame(2, symbol: "square.and.arrow.up", title: "Tap Share", detail: shareHint)
            frame(3, symbol: "checkmark.circle.fill", title: "Pick Tabby", detail: "Tag them, say why, Import.")
        }
    }

    private func frame(_ number: Int, symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 76)
                    .overlay {
                        Image(systemName: symbol).font(.title).foregroundStyle(.tint)
                    }
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))
                    .padding(6)
            }
            Text(title).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
