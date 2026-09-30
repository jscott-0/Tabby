import Foundation
import TabbyKit
import WebKit

/// Tier 4: loads a profile in an offscreen WKWebView (no cookies, mobile Safari UA), lets its
/// scripts run, and returns the resulting HTML. Only used for retries of incomplete profiles.
struct WebPageRenderer: PageRenderer {
    var timeout: Duration = .seconds(15)

    func renderedHTML(for url: URL) async throws -> String {
        try await WebPageLoad.html(for: url, timeout: timeout)
    }
}

@MainActor
private final class WebPageLoad {
    private let webView: WKWebView

    private init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        webView.customUserAgent = URLSessionHTTPClient.mobileSafariUserAgent
    }

    static func html(for url: URL, timeout: Duration) async throws -> String {
        let load = WebPageLoad()
        return try await load.run(url, timeout: timeout)
    }

    private func run(_ url: URL, timeout: Duration) async throws -> String {
        let deadline = ContinuousClock.now + timeout
        webView.load(URLRequest(url: url))
        try await Task.sleep(for: .milliseconds(500))
        while webView.isLoading {
            guard ContinuousClock.now < deadline else {
                webView.stopLoading()
                throw URLError(.timedOut)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        // Give client-side rendering a moment after the load event.
        try await Task.sleep(for: .seconds(1.5))
        let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
        return html as? String ?? ""
    }
}
