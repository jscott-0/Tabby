import SafariServices
import SwiftUI
import TabbyKit

/// Two ways to pay: Unlimited Tabs (one-time) or Tabby Pro (monthly / annual, recommended).
/// Opens on the option that fits why it was shown.
struct PaywallView: View {
    let model: AppModel
    let trigger: PaywallTrigger
    @State private var option: Option
    @State private var proPeriod: ProPeriod = .annual
    @State private var checkoutURL: URL?
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    enum Option { case unlimitedTabs, pro }

    enum ProPeriod: String, CaseIterable, Identifiable {
        case annual, monthly
        var id: String { rawValue }
        var title: String { self == .annual ? "Yearly" : "Monthly" }
        var productID: String { self == .annual ? PurchaseManager.proAnnualID : PurchaseManager.proMonthlyID }
    }

    init(model: AppModel, trigger: PaywallTrigger) {
        self.model = model
        self.trigger = trigger
        _option = State(initialValue: trigger.defaultsToPro ? .pro : .unlimitedTabs)
    }

    private var purchases: PurchaseManager { model.purchases }

    private var selectedProductID: String {
        option == .pro ? proPeriod.productID : PurchaseManager.unlimitedTabsID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    optionCard(.unlimitedTabs)
                    optionCard(.pro)
                    if option == .pro {
                        Picker("Billing", selection: $proPeriod) {
                            ForEach(ProPeriod.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if !model.isInDemo {
                        Button {
                            model.enterDemo()
                        } label: {
                            Label("Preview the full app", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("paywall-demo")
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("paywall-close")
                }
            }
        }
        .sheet(isPresented: Binding(isPresent: $checkoutURL)) {
            if let checkoutURL { SafariView(url: checkoutURL) }
        }
        .alert("Purchase", isPresented: Binding(isPresent: Binding(get: { purchases.errorMessage }, set: { purchases.errorMessage = $0 }))) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchases.errorMessage ?? "")
        }
        .task { await purchases.loadProducts() }
    }

    // MARK: Header

    private var copy: (title: String, subtitle: String) {
        switch trigger {
        case .firstSave:
            ("Your first Tab is saved!", "Free accounts keep 1 Tab. Unlock Tabby to save everyone worth remembering.")
        case .slotLimit:
            ("Saved as a draft", "You've used your free Tab. Unlock to open your drafts and keep saving.")
        case .banner, .lockedDraft:
            ("Unlock your Tabs", "Save as many people as you like. Your drafts unlock right away.")
        case .proFeature:
            ("Tabby Pro", "Everything in Tabby, plus Talent Search as it arrives.")
        case .demo:
            ("Make it yours", "Unlock Tabby to build your own rolodex like the demo.")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: trigger == .firstSave ? "checkmark.seal.fill" : "lock.open.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text(copy.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("paywall-title")
            Text(copy.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: Options

    @ViewBuilder private func optionCard(_ card: Option) -> some View {
        let selected = option == card
        Button {
            option = card
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(card == .pro ? "Tabby Pro" : "Unlimited Tabs")
                        .font(.headline)
                    if card == .pro {
                        Text("Recommended")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Text(priceLabel(card))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                ForEach(features(card), id: \.self) { feature in
                    Label(feature, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(card == .pro ? "paywall-option-pro" : "paywall-option-unlimited")
    }

    private func features(_ card: Option) -> [String] {
        switch card {
        case .unlimitedTabs:
            ["Save unlimited people", "Every Space, tag and search", "Pay once, keep it forever"]
        case .pro:
            ["Everything in Unlimited Tabs", "Talent Search (coming soon)", "Alerts when saved people post (coming soon)"]
        }
    }

    private func priceLabel(_ card: Option) -> String {
        switch card {
        case .unlimitedTabs:
            return price(PurchaseManager.unlimitedTabsID).map { "\($0) once" } ?? ""
        case .pro:
            let suffix = proPeriod == .annual ? "/year" : "/month"
            return price(proPeriod.productID).map { $0 + suffix } ?? ""
        }
    }

    /// Store prices; placeholders from Tabby.storekit when StoreKit isn't available (UI tests).
    private func price(_ productID: String) -> String? {
        if let price = purchases.displayPrice(productID) { return price }
        #if DEBUG
        if UITesting.isEnabled {
            return [PurchaseManager.unlimitedTabsID: "$14.99", PurchaseManager.proMonthlyID: "$4.99",
                    PurchaseManager.proAnnualID: "$29.99"][productID]
        }
        #endif
        return nil
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                buy()
            } label: {
                Group {
                    if isWorking || purchases.isPurchasing {
                        ProgressView()
                    } else {
                        Text(option == .pro ? "Start Tabby Pro" : "Unlock Unlimited Tabs")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || purchases.isPurchasing)
            .accessibilityIdentifier("paywall-buy")
            HStack(spacing: 16) {
                Button("Restore") {
                    Task { await purchases.restore() }
                }
                // PLACEHOLDER: real Terms and Privacy URLs before submission.
                Link("Terms", destination: URL(string: "https://tabbyapp.com/terms")!)
                Link("Privacy", destination: URL(string: "https://tabbyapp.com/privacy")!)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func buy() {
        let productID = selectedProductID
        let accountID = model.sharedDefaults.account?.id
        isWorking = true
        Task {
            defer { isWorking = false }
            switch await purchases.route(for: productID, accountID: accountID) {
            case .webCheckout(let url):
                checkoutURL = url
            case .appStore:
                if await purchases.purchase(productID, accountID: accountID) {
                    dismiss()
                }
            }
        }
    }
}

/// US web checkout, kept in the app so the user comes straight back.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
