//
//  OAuthWebView.swift
//  Toolbelt
//
//  A web view for signing in to Yandex that reports every address it goes to,
//  so the token can be taken from the redirect.
//

import SwiftUI
import WebKit

struct OAuthWebView: NSViewRepresentable {
    let url: URL
    /// Returns `true` when the address ends the sign-in; loading stops there.
    let onAddress: (URL) -> Bool
    let onFailure: (Error) -> Void
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Toolbelt keeps the token, not a Yandex session: the cookies go with the window.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.observe(webView)
        // After the view update: the first callbacks change SwiftUI state.
        let request = URLRequest(url: url)
        Task { [weak webView] in
            webView?.load(request)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OAuthWebView
        private var addressObservation: NSKeyValueObservation?
        private var isFinished = false

        init(parent: OAuthWebView) {
            self.parent = parent
        }

        /// Observing the address rather than deciding on navigations: it also sees
        /// server redirects and changes of the fragment alone.
        func observe(_ webView: WKWebView) {
            addressObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    self?.inspect(webView)
                }
            }
        }

        func stopObserving() {
            addressObservation?.invalidate()
            addressObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            inspect(webView)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            inspect(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            fail(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            fail(error)
        }

        private func inspect(_ webView: WKWebView) {
            guard !isFinished, let url = webView.url, parent.onAddress(url) else { return }
            isFinished = true
            webView.stopLoading()
            parent.isLoading = false
        }

        private func fail(_ error: any Error) {
            parent.isLoading = false
            let error = error as NSError
            // Stopped on purpose: by the token or by a newer navigation.
            guard !isFinished, !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
            parent.onFailure(error)
        }
    }
}
