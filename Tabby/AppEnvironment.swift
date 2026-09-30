import SwiftUI
import TabbyKit

/// Opens the paywall from anywhere in the app. A no-op in previews.
struct ShowPaywallAction {
    var action: (PaywallTrigger) -> Void = { _ in }

    func callAsFunction(_ trigger: PaywallTrigger) {
        action(trigger)
    }
}

extension EnvironmentValues {
    /// What the user owns. Demo mode reports `.pro` so the whole app is visible.
    @Entry var entitlement: Entitlement = .pro
    @Entry var showPaywall = ShowPaywallAction()
}
