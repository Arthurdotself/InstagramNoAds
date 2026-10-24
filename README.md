# InstagramNoAds

A tiny, native SwiftUI app that wraps **instagram.com** and quietly removes the ads: sponsored posts in your feed and sponsored stories are hidden or skipped automatically.

No jailbreak, no sideloaded tweaks, no third-party servers. Just a web view, one locked-down navigation rule, and a small script that cleans up the page.

> **Disclaimer:** this is an unofficial, personal project. It is not affiliated with, endorsed by, or connected to Instagram or Meta. Using modified clients may go against Instagram's Terms of Use, so use it at your own risk.

---

## Why I built it

Instagram's feed and stories are increasingly packed with sponsored content. The official app gives you no way to turn it off, and most "no ads" solutions are either patched clients (risky and hard to keep up to date), browser extensions (not available in an app-like form on iPhone), or paid subscriptions.

I wanted something simple:

- an app I can open and just **use Instagram without the ads**
- **small enough to read in a few minutes**, so I know exactly what it does
- **no accounts, no tracking, no backend**: it only talks to Instagram

## What problem it solves

| Problem | How InstagramNoAds handles it |
| --- | --- |
| Sponsored posts break up the feed | Posts labelled "Sponsored" are detected and hidden |
| Ugly blank gaps where ads were | Optional gap collapsing pulls the next post up |
| Sponsored stories interrupt viewing | The ad is covered, muted and skipped automatically |
| Links pull you out into random sites | Navigation is restricted to `instagram.com` only |
| Having to log in every time | Login is kept between launches |
| Videos jumping to fullscreen | Videos play inline in the page |

## How it works

The whole app is two Swift files.

1. **`WKWebView` shell.** `InstagramWebView` loads `https://www.instagram.com` in a `WKWebView` (via `UIViewRepresentable` on iOS/iPadOS/visionOS and `NSViewRepresentable` on macOS). It identifies itself as regular Safari so Instagram serves its current web app.
2. **Navigation guard.** `InstagramNavigationGuard` only allows top-level navigation to `instagram.com` and its subdomains. Anything else is cancelled. Links that try to open a new window stay inside the same view, if allowed.
3. **Injected ad-hiding script.** A user script runs at document end and uses a `MutationObserver`, because Instagram loads posts dynamically as you scroll:
   - **Feed:** finds each `<article>` whose label reads *Sponsored* (English and Arabic labels are supported) and makes it invisible. The post stays in the layout so infinite scroll keeps working.
   - **Gap collapsing (experimental):** applies a negative margin so the next post moves up over the hidden ad.
   - **Stories:** detects a sponsored label in the story header, covers the screen with a black overlay (taps still pass through), mutes the video and presses **Next**. It retries a few times, then stops so you are never locked out.
4. **Persistent session.** The default website data store is used, so you stay logged in between launches.

### Settings

Two flags at the top of `InstagramNavigationGuard` in `ContentView.swift`:

```swift
static let hideAds = true          // turn the ad hider off completely (useful for testing)
static let collapseAdGaps = true   // experimental: close the blank gap left by a hidden ad
```

If the feed ever stops loading new posts, set `collapseAdGaps` to `false`.

## Getting started

### Requirements

- A Mac with a recent version of **Xcode** (the project was created with Xcode 26.3)
- Deployment target is set to **27.0** for iOS, iPadOS, macOS and visionOS in the project settings
- An Apple ID for code signing (a free account works for running on your own device)

### Run it

```bash
git clone https://github.com/Arthurdotself/InstagramNoAds.git
cd InstagramNoAds
open insta.xcodeproj
```

1. In Xcode, select the **insta** target, go to **Signing & Capabilities**, and choose your own Team.
2. Change the bundle identifier to something unique to you.
3. Pick a simulator, a connected device or **My Mac**, then press **Run** (⌘R).
4. Log in to Instagram inside the app. You will stay logged in next time.

## Project structure

```
InstagramNoAds/
├── insta.xcodeproj
└── insta/
    ├── MyApp.swift          # App entry point
    ├── ContentView.swift    # Web view, navigation guard and ad-hiding script
    └── Assets.xcassets      # App icon and colors
```

## Limitations

- Ads are detected by their visible **"Sponsored" label**. If Instagram changes its page structure or wording, detection can break and the script will need an update.
- Only the labels listed in the script are recognised (currently English and Arabic). Adding a language means adding its label to the `labels` set.
- It is a web view of the Instagram website, so you get the web experience, not every feature of the official app.
- Reels, and other surfaces beyond the feed and stories, are not specifically handled.

## Contributing

Ideas and pull requests are welcome, especially:

- sponsored labels in more languages
- more reliable ad detection
- handling other surfaces such as Reels

Open an issue to discuss a change before sending a large pull request.

## License

Released under the [MIT License](LICENSE).
