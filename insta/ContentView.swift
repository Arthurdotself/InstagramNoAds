import SwiftUI
import WebKit

// MARK: - Content

struct ContentView: View {
    var body: some View {
        InstagramWebView()
            .background(Color(red: 10 / 255, green: 14 / 255, blue: 22 / 255))
            .preferredColorScheme(.dark)
    }
}

// MARK: - Web view (Instagram only)

#if canImport(UIKit)
import UIKit

struct InstagramWebView: UIViewRepresentable {
    func makeCoordinator() -> InstagramNavigationGuard { InstagramNavigationGuard() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: InstagramNavigationGuard.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never // SwiftUI already handles the safe area
        webView.load(URLRequest(url: InstagramNavigationGuard.homeURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit

struct InstagramWebView: NSViewRepresentable {
    func makeCoordinator() -> InstagramNavigationGuard { InstagramNavigationGuard() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: InstagramNavigationGuard.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: InstagramNavigationGuard.homeURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

// MARK: - Navigation guard

/// Allows top-level navigation only to instagram.com (and its subdomains).
final class InstagramNavigationGuard: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let homeURL = URL(string: "https://www.instagram.com")!

    /// Set to false to turn the ad hider off completely (useful for testing).
    static let hideAds = true

    /// Experimental: pulls the next post up over a hidden ad to close the blank gap.
    /// If the feed stops loading again, set this to false.
    static let collapseAdGaps = true

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // keeps you logged in between launches

        // Identify as regular Safari so Instagram serves its current web app, not a legacy layout.
        #if os(iOS)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        configuration.applicationNameForUserAgent = isPhone
            ? "Version/26.0 Mobile/15E148 Safari/604.1"
            : "Version/26.0 Safari/605.1.15"
        #else
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        #endif

        // Play videos inside the page instead of jumping to fullscreen.
        #if canImport(UIKit)
        configuration.allowsInlineMediaPlayback = true
        #endif
        configuration.preferences.isElementFullscreenEnabled = false

        if hideAds {
            let adBlocker = WKUserScript(source: adHidingScript,
                                         injectionTime: .atDocumentEnd,
                                         forMainFrameOnly: true)
            configuration.userContentController.addUserScript(adBlocker)
        }
        return configuration
    }

    /// Hides any feed post whose label reads "Sponsored" (English and Arabic).
    /// Instagram loads posts as you scroll, so a MutationObserver re-checks the page on every change.
    private static let adHidingScript = #"""
    (function () {
      var COLLAPSE_GAPS = \#(collapseAdGaps);
      var labels = new Set([
        'sponsored',
        'ad',
        'promoted',
        '\u0645\u064F\u0645\u0648\u0651\u064E\u0644',
        '\u0645\u0645\u0648\u0644',
        '\u0645\u0645\u0648\u0651\u0644',
        '\u0625\u0639\u0644\u0627\u0646'
      ]);

      function isAdLabel(el) {
        return el.children.length === 0 && labels.has((el.textContent || '').trim().toLowerCase());
      }

      function scan() {
        document.querySelectorAll('video:not([playsinline])').forEach(function (video) {
          video.setAttribute('playsinline', '');
          video.setAttribute('webkit-playsinline', '');
        });
        document.querySelectorAll('article').forEach(function (post) {
          if (post.dataset.adHidden) return;
          var spans = post.querySelectorAll('span');
          for (var i = 0; i < spans.length; i++) {
            if (isAdLabel(spans[i])) {
              // Keep the post in the layout (so infinite scroll keeps working), just make it invisible.
              post.style.visibility = 'hidden';
              post.style.pointerEvents = 'none';
              post.dataset.adHidden = '1';
              if (COLLAPSE_GAPS) {
                var h = post.getBoundingClientRect().height;
                if (h > 0) post.style.marginBottom = (-h) + 'px';
              }
              post.querySelectorAll('video').forEach(function (v) { v.muted = true; v.pause(); });
              break;
            }
          }
        });
      }

      var timer;
      new MutationObserver(function () {
        clearTimeout(timer);
        timer = setTimeout(scan, 200);
      }).observe(document.documentElement, { childList: true, subtree: true });

      scan();
    })();
    """#

    private func isAllowed(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme == "about" { return true }
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only restrict page-level navigation; images, scripts and iframes still load normally.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        decisionHandler(!isMainFrame || isAllowed(navigationAction.request.url) ? .allow : .cancel)
    }

    // Links that try to open a new window (target="_blank") stay in the same view, if allowed.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if isAllowed(navigationAction.request.url) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

#Preview {
    ContentView()
}
