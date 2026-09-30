import Foundation
import Observation
import StoreKit
import TabbyKit

/// StoreKit 2: loads products, listens for transactions and turns what's owned into an
/// `Entitlement`, cached in the App Group so the share extension sees it.
///
/// Until the backend exists (Phase 4), the App Store is the only source of truth. US web checkout
/// opens the configured URL, but granting that purchase needs the backend's payment webhook.
@MainActor
@Observable
final class PurchaseManager {
    static let unlimitedTabsID = "tabby.unlimited"
    static let proMonthlyID = "tabby.pro.monthly"
    static let proAnnualID = "tabby.pro.annual"
    static let productIDs = [unlimitedTabsID, proMonthlyID, proAnnualID]

    private(set) var products: [String: Product] = [:]
    private(set) var entitlement: Entitlement
    private(set) var isPurchasing = false
    var errorMessage: String?

    /// Called when the entitlement goes up, so locked drafts can be unlocked.
    @ObservationIgnored var onUpgrade: ((Entitlement) -> Void)?

    private let sharedDefaults: SharedDefaults
    /// UI tests: purchases succeed at once and nothing talks to StoreKit.
    private let isSimulated: Bool
    @ObservationIgnored private var updates: Task<Void, Never>?

    init(sharedDefaults: SharedDefaults, isSimulated: Bool = false) {
        self.sharedDefaults = sharedDefaults
        self.isSimulated = isSimulated
        entitlement = sharedDefaults.entitlement
    }

    static func entitlement(for productID: String) -> Entitlement {
        switch productID {
        case unlimitedTabsID: .unlimitedTabs
        case proMonthlyID, proAnnualID: .pro
        default: .free
        }
    }

    func start() {
        guard !isSimulated, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        guard !isSimulated, products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            errorMessage = "Couldn't load prices. Check your connection and try again."
        }
    }

    func refreshEntitlement() async {
        guard !isSimulated else { return }
        var best = Entitlement.free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            best = max(best, Self.entitlement(for: transaction.productID))
        }
        apply(best)
    }

    /// Returns whether the purchase went through.
    func purchase(_ productID: String, accountID: String?) async -> Bool {
        if isSimulated {
            apply(max(entitlement, Self.entitlement(for: productID)))
            return true
        }
        guard let product = products[productID] else {
            errorMessage = "This option isn't available right now."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            var options: Set<Product.PurchaseOption> = []
            if let accountID, let token = UUID(uuidString: accountID) {
                options.insert(.appAccountToken(token))
            }
            switch try await product.purchase(options: options) {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlement()
                return true
            case .success(.unverified):
                errorMessage = "The App Store couldn't verify this purchase."
                return false
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        guard !isSimulated else { return }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlement()
    }

    /// US storefronts link out to web checkout when one is configured; otherwise in-app purchase.
    func route(for productID: String, accountID: String?) async -> PurchaseRoute {
        guard !isSimulated else { return .appStore }
        let country = await Storefront.current?.countryCode
        return PurchaseRouter.route(storefrontCountryCode: country, webCheckoutBase: Self.webCheckoutBase,
                                    accountID: accountID, productID: productID)
    }

    /// From the `TabbyWebCheckoutURL` Info.plist key (`TABBY_WEB_CHECKOUT_URL` in Config/Tabby.xcconfig).
    /// Empty by default.
    static var webCheckoutBase: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TabbyWebCheckoutURL") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return URL(string: value)
    }

    private func apply(_ new: Entitlement) {
        let old = entitlement
        entitlement = new
        sharedDefaults.entitlement = new
        if new > old { onUpgrade?(new) }
    }

    func displayPrice(_ productID: String) -> String? {
        products[productID]?.displayPrice
    }
}
