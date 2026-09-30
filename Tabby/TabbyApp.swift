import Observation
import SwiftData
import SwiftUI
import TabbyKit

@main
struct TabbyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .id(model.storeGeneration)
                .modelContainer(model.activeContainer)
        }
        // `initial` so a cold launch (already active, no change) still runs it.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.becameActive() }
        }
    }
}

enum Route: Hashable {
    case space(SpaceRef)
    case person(UUID)
    case tags
}

/// App-wide state that must survive the store being reopened: the store, navigation,
/// onboarding, purchases, the paywall and demo mode.
@MainActor
@Observable
final class AppModel {
    private(set) var container: ModelContainer
    /// Demo mode's in-memory store. While set, the app shows it instead of the real one.
    private(set) var demoContainer: ModelContainer?
    /// Bumped when the store is reopened so views drop objects from the old one.
    private(set) var storeGeneration = 0
    var path: [Route] = []
    var paywall: PaywallTrigger?
    private(set) var isOnboarding: Bool
    let purchases: PurchaseManager
    let sharedDefaults: SharedDefaults

    @ObservationIgnored private let demoLog: DemoLog
    @ObservationIgnored private var lastSeenExternalWrite: Date?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryRun = UUID()

    var activeContainer: ModelContainer { demoContainer ?? container }
    var isInDemo: Bool { demoContainer != nil }
    /// The demo shows everything, as if on Pro.
    var entitlement: Entitlement { isInDemo ? .pro : purchases.entitlement }

    init() {
        let defaults: SharedDefaults
        let container: ModelContainer
        var isSimulated = false
        #if DEBUG
        if UITesting.isEnabled {
            defaults = UITesting.sharedDefaults
            container = UITesting.makeContainer()
            isSimulated = true
        } else {
            defaults = .shared
            container = Self.openStore()
        }
        #else
        defaults = .shared
        container = Self.openStore()
        #endif
        self.sharedDefaults = defaults
        self.container = container
        self.demoLog = DemoLog(defaults)
        self.purchases = PurchaseManager(sharedDefaults: defaults, isSimulated: isSimulated)

        // People saved before onboarding existed: nothing to teach.
        if !defaults.onboardingFinished, defaults.onboardingStep == .welcome,
           TabbyStore(context: container.mainContext).unlockedPeopleCount() > 0 {
            defaults.onboardingFinished = true
            defaults.hasCompletedFirstSave = true
        }
        isOnboarding = !defaults.onboardingFinished
        lastSeenExternalWrite = defaults.lastExternalWrite

        purchases.onUpgrade = { [weak self] _ in self?.didUpgrade() }
        purchases.start()
    }

    private static func openStore() -> ModelContainer {
        do {
            return try TabbyContainer.make()
        } catch {
            fatalError("Could not open the Tabby store: \(error)")
        }
    }

    /// The share extension saves from another process, which this app's context doesn't see.
    /// Reopen the store when it has written since we last looked, show any pending "Open in Tabby"
    /// and paywall, then retry profiles whose extraction didn't complete.
    func becameActive() {
        #if DEBUG
        if UITesting.isEnabled { return }
        #endif
        guard !isInDemo else { return }
        if let write = sharedDefaults.lastExternalWrite, write != lastSeenExternalWrite {
            lastSeenExternalWrite = write
            if let fresh = try? TabbyContainer.make() {
                retryTask?.cancel()
                retryTask = nil
                container = fresh
                storeGeneration += 1
            }
        }
        if let id = sharedDefaults.takePendingOpen() {
            open(personID: id)
        }
        if let trigger = sharedDefaults.takePendingPaywall(), !isOnboarding {
            paywall = trigger
        }
        retryIncompleteProfiles()
    }

    private func retryIncompleteProfiles() {
        guard retryTask == nil, !isInDemo else { return }
        let queue = RetryQueue(context: container.mainContext, service: AppServices.enrichment(renderer: WebPageRenderer()))
        let run = UUID()
        retryRun = run
        retryTask = Task { [weak self] in
            await queue.run()
            if self?.retryRun == run { self?.retryTask = nil }
        }
    }

    /// Locked drafts can't be opened; they go to Waiting to unlock and the paywall.
    func open(personID: UUID) {
        if sharedDefaults.pendingOpenPersonID == personID {
            sharedDefaults.setPendingOpen(nil)
        }
        if let person = TabbyStore(context: activeContainer.mainContext).person(id: personID), person.isLockedDraft {
            path = [.space(.builtIn(.waitingToUnlock))]
            if paywall == nil { paywall = .lockedDraft }
            return
        }
        path = [.person(personID)]
    }

    // MARK: Onboarding

    /// The first save (share sheet or pasted link) ends onboarding on that person, then the paywall.
    func completeOnboarding(firstPersonID: UUID?) {
        sharedDefaults.onboardingFinished = true
        sharedDefaults.hasCompletedFirstSave = true
        isOnboarding = false
        if let firstPersonID {
            path = [.person(firstPersonID)]
            guard !entitlement.hasUnlimitedTabs else { return }
            // Let the person show first (and any sheet from onboarding finish closing).
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                if paywall == nil { paywall = .firstSave }
            }
        }
    }

    // MARK: Purchases and demo

    private func didUpgrade() {
        TabbyStore(context: container.mainContext).unlockAllDrafts()
        demoLog.recordPurchase()
        if isInDemo { exitDemo(showingPaywall: false) }
        paywall = nil
    }

    func enterDemo() {
        paywall = nil
        path = []
        demoContainer = SampleData.demoContainer()
        storeGeneration += 1
        demoLog.enter()
    }

    /// Back to the real (untouched) store; by default on the paywall, since that's where the demo started.
    func exitDemo(showingPaywall: Bool = true) {
        guard isInDemo else { return }
        demoLog.exit()
        path = []
        demoContainer = nil
        storeGeneration += 1
        if showingPaywall { paywall = .demo }
    }
}

/// My Tabs: a NavigationStack rooted at Spaces. `tabby://person/{id}` opens a Person.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        #if DEBUG
        if let url = UITesting.shareURL {
            UITestShareHost(url: url)
        } else {
            main
        }
        #else
        main
        #endif
    }

    @ViewBuilder private var main: some View {
        Group {
            if model.isOnboarding {
                OnboardingView(model: model)
            } else {
                stack
            }
        }
        .environment(\.entitlement, model.entitlement)
        .environment(\.showPaywall, ShowPaywallAction { model.paywall = $0 })
        .sheet(item: $model.paywall) { trigger in
            PaywallView(model: model, trigger: trigger)
        }
    }

    private var stack: some View {
        NavigationStack(path: $model.path) {
            SpacesView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .space(let ref): SpaceDetailView(ref: ref)
                    case .person(let id): PersonDetailView(personID: id)
                    case .tags: TagsView()
                    }
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.isInDemo {
                DemoBanner(onUnlock: { model.paywall = .demo }, onExit: { model.exitDemo() })
            }
        }
        .onOpenURL { url in
            if let id = DeepLink.personID(from: url) {
                model.open(personID: id)
            }
        }
    }
}

/// Always visible in demo mode, so sample data is never mistaken for your own.
struct DemoBanner: View {
    let onUnlock: () -> Void
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
            VStack(alignment: .leading, spacing: 1) {
                Text("Demo").font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("demo-banner")
                Text("Sample data. Nothing is saved.").font(.caption)
            }
            Spacer()
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.accentColor)
                .controlSize(.small)
            Button("Exit", action: onExit)
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.small)
                .accessibilityIdentifier("demo-exit")
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor)
    }
}
