import SwiftUI
import Combine
import WebKit

// MARK: - Content

struct ContentView: View {
    #if canImport(UIKit)
    /// How much of the web view the keyboard covers; we shrink the web view by this amount
    /// so Instagram's story reply box stays visible above the keyboard.
    @State private var keyboardHeight: CGFloat = 0
    @StateObject private var controller = WebController()
    #endif

    var body: some View {
        #if canImport(UIKit)
        VStack(spacing: 0) {
            StoryToolbar(controller: controller)
            InstagramWebView(controller: controller)
        }
            .padding(.bottom, keyboardHeight)
            .background(Color(red: 10 / 255, green: 14 / 255, blue: 22 / 255))
            .ignoresSafeArea(.keyboard) // we handle the keyboard ourselves (below)
            .preferredColorScheme(.dark)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                let screenHeight = scene?.screen.bounds.height ?? UIScreen.main.bounds.height
                let bottomInset = scene?.windows.first?.safeAreaInsets.bottom ?? 0
                // The web view already stops at the bottom safe area, so subtract it.
                let covered = max(0, screenHeight - endFrame.minY - bottomInset)
                withAnimation(.easeOut(duration: duration)) { keyboardHeight = covered }
            }
        #else
        InstagramWebView()
            .background(Color(red: 10 / 255, green: 14 / 255, blue: 22 / 255))
            .preferredColorScheme(.dark)
        #endif
    }
}

// MARK: - View-all-stories controller + button

/// Bridges the SwiftUI button to the JavaScript story loop running inside the web view.
final class WebController: ObservableObject {
    weak var webView: WKWebView?
    @Published var running = false
    @Published var count = 0
    @Published var status = ""

    /// Max number of people's stories per tap (kept low for testing).
    static let maxUsers = 200

    func toggle() {
        if running {
            webView?.evaluateJavaScript("window.__stopViewAll && window.__stopViewAll()", completionHandler: nil)
            running = false
        } else {
            count = 0
            status = ""
            running = true
            let js = "window.__viewAllStories ? (window.__viewAllStories(\(Self.maxUsers)), 'started') : 'script-missing'"
            webView?.evaluateJavaScript(js) { [weak self] result, error in
                print("[ViewAll] start ->", result ?? "nil", error?.localizedDescription ?? "")
                if (result as? String) != "started" {
                    DispatchQueue.main.async {
                        self?.running = false
                        self?.status = "Script not loaded. Reload the page and try again."
                    }
                }
            }
        }
    }

    /// Called every second while running: syncs the counter and resets the button when the loop ends.
    func poll() {
        guard running else { return }
        webView?.evaluateJavaScript("JSON.stringify(window.__viewAllState || null)") { [weak self] result, _ in
            guard let self else { return }
            var isRunning = false
            var newCount = self.count
            var errorText: String? = nil
            if let text = result as? String,
               let data = text.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] {
                isRunning = (obj["running"] as? Bool) ?? false
                newCount = (obj["count"] as? Int) ?? newCount
                errorText = obj["error"] as? String
                if !isRunning, errorText != nil { print("[ViewAll] stopped:", text) }
            }
            DispatchQueue.main.async {
                self.count = newCount
                if !isRunning {
                    self.running = false
                    if let errorText {
                        self.status = errorText == "tray not found"
                            ? "Couldn't find the story tray. Stay on the Home feed."
                            : errorText
                    }
                }
            }
        }
    }
}

struct StoryToolbar: View {
    @ObservedObject var controller: WebController

    var body: some View {
        HStack(spacing: 10) {
            Button {
                controller.toggle()
            } label: {
                Label(controller.running ? "Stop" : "View all stories",
                      systemImage: controller.running ? "stop.fill" : "eye.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(controller.running ? Color.red : Color.blue))
                    .foregroundColor(.white)
            }
            if controller.running {
                Text("\(controller.count)/\(WebController.maxUsers) viewed")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
            } else if !controller.status.isEmpty {
                Text(controller.status)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 10 / 255, green: 14 / 255, blue: 22 / 255))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            controller.poll()
        }
    }
}

// MARK: - Web view (Instagram only)

#if canImport(UIKit)
import UIKit

struct InstagramWebView: UIViewRepresentable {
    var controller: WebController? = nil

    func makeCoordinator() -> InstagramNavigationGuard { InstagramNavigationGuard() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: InstagramNavigationGuard.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never // SwiftUI already handles the safe area
        controller?.webView = webView
        webView.load(URLRequest(url: InstagramNavigationGuard.homeURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit

struct InstagramWebView: NSViewRepresentable {
    var controller: WebController? = nil

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

        // Story replies: make the keyboard's Return/Send key press Instagram's on-screen Send button.
        let storyReply = WKUserScript(source: storyReplyScript,
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: true)
        configuration.userContentController.addUserScript(storyReply)

        // "View all stories" button: the loop that opens the tray and steps through each story.
        let viewAll = WKUserScript(source: viewAllScript,
                                   injectionTime: .atDocumentEnd,
                                   forMainFrameOnly: true)
        configuration.userContentController.addUserScript(viewAll)
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

      // ---- Stories ----------------------------------------------------------
      // The story viewer is not made of <article> posts, so it needs its own check:
      // find the "Sponsored" label in the header area, cover the ad, mute it and press "Next".
      var storyCover = null;
      var lastSkip = 0;
      var skipTries = 0;

      function inStories() {
        return location.pathname.indexOf('/stories/') === 0;
      }

      function storyHasAdLabel() {
        var els = document.querySelectorAll('span, div');
        for (var i = 0; i < els.length; i++) {
          var el = els[i];
          if (!isAdLabel(el)) continue;
          var r = el.getBoundingClientRect();
          // The label sits in the story header (top part of the screen).
          if (r.height > 0 && r.top >= 0 && r.top < window.innerHeight * 0.25) return true;
        }
        return false;
      }

      function showCover(on) {
        if (on && !storyCover) {
          storyCover = document.createElement('div');
          // pointer-events:none so you can still tap/swipe through it manually.
          storyCover.style.cssText = 'position:fixed;inset:0;background:#000;z-index:2147483647;pointer-events:none;';
          document.documentElement.appendChild(storyCover);
        } else if (!on && storyCover) {
          storyCover.remove();
          storyCover = null;
        }
      }

      function pressNext() {
        var btn = document.querySelector(
          '[aria-label="Next"], [aria-label="next"], [aria-label="\u0627\u0644\u062a\u0627\u0644\u064a"]'
        );
        if (btn) {
          (btn.closest('button, [role="button"]') || btn).click();
          return;
        }
        // Fallback: the story viewer also reacts to the right arrow key.
        ['keydown', 'keyup'].forEach(function (type) {
          var e = new KeyboardEvent(type, { key: 'ArrowRight', code: 'ArrowRight', keyCode: 39, which: 39, bubbles: true });
          document.dispatchEvent(e);
          window.dispatchEvent(e);
        });
      }

      function scanStories() {
        if (!inStories()) { showCover(false); skipTries = 0; return; }
        if (!storyHasAdLabel()) { showCover(false); skipTries = 0; return; }

        document.querySelectorAll('video').forEach(function (v) { v.muted = true; v.pause(); });
        showCover(true);

        // Skip it. Retry a few times, then stop so you are never locked out (the cover lets taps through).
        var now = Date.now();
        if (skipTries < 6 && now - lastSkip > 500) {
          lastSkip = now;
          skipTries++;
          pressNext();
        }
      }

      var timer;
      var storyTimer;
      new MutationObserver(function () {
        clearTimeout(timer);
        timer = setTimeout(scan, 200);
        // Stories need a faster reaction so the ad is covered before it is seen.
        if (inStories()) {
          clearTimeout(storyTimer);
          storyTimer = setTimeout(scanStories, 30);
        }
      }).observe(document.documentElement, { childList: true, subtree: true });

      // Safety net: the story label can change without a DOM mutation we notice.
      setInterval(scanStories, 400);

      scan();
      scanStories();
    })();
    """#

    /// Story reply box: the keyboard's Return key shows "Send" and clicks Instagram's Send button.
    private static let storyReplyScript = #"""
    (function () {
      var SEND_LABELS = ['send', 'post', '\u0625\u0631\u0633\u0627\u0644', '\u0646\u0634\u0631'];
      var INPUT_SELECTOR = 'textarea, input[type="text"], input:not([type]), [contenteditable="true"], [role="textbox"]';

      function inStories() {
        return location.pathname.indexOf('/stories/') === 0;
      }

      function isSendButton(el) {
        var text = (el.textContent || '').trim().toLowerCase();
        var aria = (el.getAttribute('aria-label') || '').trim().toLowerCase();
        return SEND_LABELS.indexOf(text) !== -1 || SEND_LABELS.indexOf(aria) !== -1;
      }

      function findSendButton(input) {
        // Look near the input first (walk up the tree), then fall back to the whole page.
        var node = input;
        for (var depth = 0; node && depth < 10; depth++, node = node.parentElement) {
          var local = node.querySelectorAll('button, [role="button"]');
          for (var i = 0; i < local.length; i++) {
            if (isSendButton(local[i])) return local[i];
          }
        }
        var all = document.querySelectorAll('button, [role="button"]');
        for (var j = 0; j < all.length; j++) {
          if (isSendButton(all[j])) return all[j];
        }
        return null;
      }

      // Make the iOS keyboard's Return key read "Send".
      document.addEventListener('focusin', function (e) {
        if (!inStories()) return;
        var input = e.target && e.target.closest && e.target.closest(INPUT_SELECTOR);
        if (input) input.setAttribute('enterkeyhint', 'send');
      }, true);

      // Return/Send on the keyboard -> click the on-screen Send button.
      document.addEventListener('keydown', function (e) {
        if (!inStories()) return;
        if (e.key !== 'Enter' || e.shiftKey || e.isComposing) return;
        var input = e.target && e.target.closest && e.target.closest(INPUT_SELECTOR);
        if (!input) return;
        var btn = findSendButton(input);
        if (!btn) return; // nothing typed yet (Instagram only shows Send once there is text)
        e.preventDefault();
        e.stopPropagation();
        btn.click();
      }, true);
    })();
    """#

    /// Opens the first story in the tray and steps through each person's stories with a human-like delay.
    /// Controlled from Swift via window.__viewAllStories(max) / window.__stopViewAll().
    private static let viewAllScript = #"""
    (function () {
      var state = { running: false, count: 0, max: 20, opened: false, openTries: 0, lastUser: null, error: null };
      window.__viewAllState = state;
      var timer = null;

      function inStories() {
        return location.pathname.indexOf('/stories/') === 0 && location.pathname.indexOf('/stories/highlights/') !== 0;
      }
      function currentUser() {
        var m = location.pathname.match(/^\/stories\/([^\/]+)/);
        return m ? m[1] : null;
      }
      function clickEl(el) {
        (el.closest('a, button, [role="button"], [role="menuitem"]') || el).click();
      }
      function isOwn(el) {
        var t = ((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
        return /your story|add story|new story|\u0642\u0635\u062a\u0643|\u0625\u0636\u0627\u0641\u0629/.test(t);
      }
      function inTopArea(el) {
        var r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && r.top >= 0 && r.top < window.innerHeight * 0.5;
      }
      function describe(el) {
        var r = el.getBoundingClientRect();
        return { tag: el.tagName, role: el.getAttribute('role'), aria: el.getAttribute('aria-label'),
                 href: el.getAttribute('href'), text: (el.textContent || '').trim().slice(0, 25),
                 top: Math.round(r.top), left: Math.round(r.left), w: Math.round(r.width), h: Math.round(r.height) };
      }
      function isRtl() {
        return getComputedStyle(document.documentElement).direction === 'rtl';
      }
      // Reading order: top to bottom by row, then left to right (right to left in Arabic).
      function sortReading(list) {
        var rtl = isRtl();
        return list.sort(function (a, b) {
          var ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
          if (Math.abs(ra.top - rb.top) > 20) return ra.top - rb.top;
          return rtl ? rb.left - ra.left : ra.left - rb.left;
        });
      }
      // Strategy A: elements that are labelled / linked as stories.
      function findLabelled() {
        var sel = 'a[href^="/stories/"]:not([href^="/stories/highlights/"]), ' +
                  '[aria-label*="story" i], [aria-label*="\u0642\u0635\u0629"], ' +
                  '[role="menu"] [role="menuitem"]';
        var nodes = document.querySelectorAll(sel);
        var list = [];
        for (var i = 0; i < nodes.length; i++) {
          if (inTopArea(nodes[i]) && !isOwn(nodes[i])) list.push(nodes[i]);
        }
        return list.length ? sortReading(list)[0] : null;
      }
      // Strategy B: find a row of avatar-sized clickable items (what a story tray looks like).
      function findAvatarRow() {
        var els = document.querySelectorAll('button, [role="button"], [role="menuitem"], [role="link"], a, li');
        var cands = [];
        for (var i = 0; i < els.length; i++) {
          var el = els[i];
          if (!inTopArea(el) || isOwn(el)) continue;
          var r = el.getBoundingClientRect();
          if (r.width < 40 || r.width > 140 || r.height < 50 || r.height > 200) continue;
          if (!el.querySelector('canvas, img')) continue;
          cands.push(el);
        }
        cands = cands.filter(function (c) {
          return !cands.some(function (o) { return o !== c && c.contains(o); });
        });
        var rows = {};
        cands.forEach(function (c) {
          var k = Math.round(c.getBoundingClientRect().top / 20);
          (rows[k] = rows[k] || []).push(c);
        });
        var best = null;
        Object.keys(rows).forEach(function (k) { if (!best || rows[k].length > best.length) best = rows[k]; });
        return best && best.length ? sortReading(best)[0] : null;
      }
      function findTrayItem() {
        var item = findLabelled() || findAvatarRow();
        if (!item) {
          // Dump what is at the top of the page so we can see how Instagram builds it.
          var all = document.querySelectorAll('a, button, [role="button"], [role="menuitem"], [role="link"], li, canvas, img');
          var dump = [];
          for (var i = 0; i < all.length && dump.length < 40; i++) {
            if (inTopArea(all[i])) dump.push(describe(all[i]));
          }
          state.debug = dump;
        }
        return item;
      }
      function pressNext() {
        var btn = document.querySelector(
          '[aria-label="Next"], [aria-label="next"], [aria-label="\u0627\u0644\u062a\u0627\u0644\u064a"]'
        );
        if (btn) { clickEl(btn); return; }
        ['keydown', 'keyup'].forEach(function (type) {
          var e = new KeyboardEvent(type, { key: 'ArrowRight', code: 'ArrowRight', keyCode: 39, which: 39, bubbles: true });
          document.dispatchEvent(e);
          window.dispatchEvent(e);
        });
      }
      function closeViewer() {
        var c = document.querySelector('[aria-label="Close"], [aria-label="close"], [aria-label="\u0625\u063a\u0644\u0627\u0642"]');
        if (c) clickEl(c); else history.back();
      }
      function stop() {
        state.running = false;
        if (timer) { clearTimeout(timer); timer = null; }
      }

      function step() {
        if (!inStories()) {
          if (state.opened) { stop(); return; }              // viewer closed itself: tray finished
          if (state.openTries >= 4) { state.error = 'tray not found'; stop(); return; }
          state.openTries++;
          window.scrollTo(0, 0);
          var item = findTrayItem();
          if (item) clickEl(item);
          return;
        }
        state.opened = true;
        var user = currentUser();
        if (user && user !== state.lastUser) {
          if (state.count >= state.max) { stop(); closeViewer(); return; }
          state.lastUser = user;
          state.count++;
        }
        document.querySelectorAll('video').forEach(function (v) { v.muted = true; });
        pressNext();
      }

      function loop() {
        if (!state.running) return;
        try { step(); } catch (e) { state.error = String(e); }
        if (state.running) timer = setTimeout(loop, 1500 + Math.random() * 1500);
      }

      window.__viewAllStories = function (max) {
        stop();
        state.running = true;
        state.count = 0;
        state.max = max || 20;
        state.opened = false;
        state.openTries = 0;
        state.lastUser = null;
        state.error = null;
        loop();
      };
      window.__stopViewAll = function () {
        stop();
        if (inStories()) closeViewer();
      };
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
