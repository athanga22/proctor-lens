import SwiftUI
import WebKit

/// A thin SwiftUI wrapper around WKWebView.
/// Loads a local HTML file bundled with the app.
struct WebView: UIViewRepresentable {

    let onQuizSubmitted: () -> Void

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(onQuizSubmitted: onQuizSubmitted)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Allow the JS in quiz.html to message back when the form submits.
        config.userContentController.add(context.coordinator, name: "quizBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true

        loadQuiz(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No dynamic updates needed — the quiz is static.
    }

    // MARK: - Private

    private func loadQuiz(into webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "quiz", withExtension: "html") else {
            // Fallback: show an error page so the problem is obvious during dev.
            let html = "<html><body><h1>quiz.html not found in bundle</h1></body></html>"
            webView.loadHTMLString(html, baseURL: nil)
            return
        }
        // allowingReadAccessTo lets the page load local CSS/JS siblings if added later.
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        let onQuizSubmitted: () -> Void

        init(onQuizSubmitted: @escaping () -> Void) {
            self.onQuizSubmitted = onQuizSubmitted
        }

        // Called when quiz.html posts `window.webkit.messageHandlers.quizBridge.postMessage("submitted")`
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "quizBridge",
               let body = message.body as? String,
               body == "submitted" {
                DispatchQueue.main.async { self.onQuizSubmitted() }
            }
        }

        // Navigation error surfacing (helpful during dev).
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[WebView] Navigation failed: \(error.localizedDescription)")
        }
    }
}
