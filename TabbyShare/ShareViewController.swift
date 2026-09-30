import SwiftData
import SwiftUI
import TabbyKit
import UIKit

/// Hosts the SwiftUI share sheet. Everything it decides lives in `ShareFlow` (TabbyKit).
final class ShareViewController: UIViewController {
    /// Kept alive for the extension's lifetime; the flow's context depends on it.
    private var container: ModelContainer?

    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            let container = try TabbyContainer.make()
            self.container = container
            let flow = ShareFlow(context: container.mainContext)
            let sheet = ShareSheetView(
                flow: flow,
                onClose: { [weak self] in self?.finish() },
                onOpenInTabby: { [weak self] in self?.openInTabby(flow) }
            )
            .modelContainer(container)
            embed(sheet)

            let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            Task {
                let url = await SharedInput.firstURL(in: providers)
                await flow.start(with: url)
            }
        } catch {
            embed(StoreErrorView { [weak self] in self?.finish() })
        }
    }

    private func embed(_ root: some View) {
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// If opening the app fails, the pending open saved by `requestOpen()` shows this person
    /// the next time Tabby comes to the foreground.
    private func openInTabby(_ flow: ShareFlow) {
        guard let url = flow.requestOpen(), HostAppOpener.open(url, from: self) else {
            finish()
            return
        }
        // Completing the request right away can cancel the open before it happens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finish()
        }
    }
}

/// Share extensions have no documented way to open their containing app
/// (`NSExtensionContext.open` is for widgets). Shipping apps walk the responder chain to the
/// UIApplication and call `openURL:options:completionHandler:` dynamically, since the method is
/// unavailable to extensions at compile time. Verify on each new iOS version.
enum HostAppOpener {
    @MainActor @discardableResult
    static func open(_ url: URL, from responder: UIResponder) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var current: UIResponder? = responder
        while let candidate = current {
            if let application = candidate as? UIApplication, application.responds(to: selector) {
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(application.method(for: selector), to: OpenURL.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            current = candidate.next
        }
        return false
    }
}

private struct StoreErrorView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Tabby couldn't open its data", systemImage: "exclamationmark.triangle",
                                   description: Text("Open the Tabby app once, then try sharing again."))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                    }
                }
        }
    }
}
