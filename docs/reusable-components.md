# Reusable components

Most of this repository is a client for one specific forum. These parts are not, and they are
the reason the code is published rather than kept private. Each entry names real files, so you
can read one layer without wading through the app.

Everything here is MIT licensed.

---

## 1. Building a TrollStore-installable IPA in CI

**→ Extracted to its own repository: [Zeu1s/trollstore-ipa](https://github.com/Zeu1s/trollstore-ipa)**

A composite GitHub Action that archives any Xcode iOS project with signing fully disabled,
signs nested Mach-O binaries before the outer bundle with `ldid`, and verifies the resulting
archive. No Apple Developer account, no `.p12`, no local Mac.

This repository consumes its own action:
[`trollstore.yml`](../.github/workflows/trollstore.yml). That is the reference call, and
it is exercised on a real ~6 MB app bundle on every run.

The two non-obvious things it encodes:

- `CODE_SIGNING_ALLOWED=NO` alone is not enough — `CODE_SIGNING_REQUIRED`, `CODE_SIGN_IDENTITY`
  and `DEVELOPMENT_TEAM` all have to be neutralised or `xcodebuild` still goes looking for an
  identity.
- Nested binaries must be signed **before** the main executable, or the outer signature is
  computed over bytes that are about to change and the install fails on-device with no useful
  error.

---

## 2. HTML/XPath → native model

`nodeseek/SharedCore/Parsing/`

- `NodeSeekParser.swift` — protocol: HTML in, typed view models out.
- `KannaNodeSeekParser.swift` — implementation over Kanna/XPath.
- `XPathRules.swift` — every selector in one table, so a markup change is a one-file diff
  instead of a hunt through the codebase.
- `LossyJSONDecoding.swift` — decoding that survives a server sending `""` where it means
  `null`, which is the normal failure mode of JSON embedded in HTML.

Worth stealing if you have to render a site that will never ship an API. The selector table and
the lossy decoder are the reusable halves; the model types are forum-specific.

---

## 3. Cloudflare challenge detection and recovery

`nodeseek/SharedCore/HTTP/ChallengeDetector.swift`, `nodeseek/SharedCore/Domain/ChallengeSession.swift`

Distinguishing "you are being challenged" from "the page is empty" from "the server is having a
moment", and holding a session state so the next request retries instead of permanently
poisoning the cache. `TemporaryServerErrorClassifier.swift` and `HTMLPayloadInspector.swift`
handle the classification side.

Any app that scrapes or talks to a Cloudflare-fronted site hits exactly this. It is the single
most common cause of "works on my machine, blank on the phone".

---

## 4. WebView ↔ native cookie bridging

`nodeseek/AppRuntime/Web/CookieBridge.swift`, `NodeSeekCookieSession.swift`

The user authenticates once in a `WKWebView`, and native `URLSession` requests then reuse that
session — without the two stores drifting apart or leaking cookies to third-party hosts.
`WebRequestFingerprint.swift` keeps the native request headers consistent with what the web view
sent, which is what stops a server treating the same session as two different clients.

---

## 5. Rendering arbitrary HTML in UIKit

`nodeseek/AppRuntime/Rendering/`

`HTMLContentRenderer.swift` defines the contract; `DTCoreTextHTMLContentRenderer` implements it,
split across extensions for attributes, document handling, content blocks, media sources,
"magic tabs" (tab-indent markup that must survive into a native layout) and diagnostics.
`RenderedContentBlock.swift` is the intermediate representation.

Useful as a worked example of DTCoreText beyond the "hello world" that every tutorial stops at —
particularly the diagnostics extension, which exists because silent renderer fallbacks are
almost impossible to debug otherwise.

---

## 6. Image handling

- `SharedCore/Media/SVGContentInspector.swift` — decide whether an SVG is safe to render
  natively or must be rasterised.
- `SharedCore/Media/StickerAspectRatioCache.swift` — cache intrinsic aspect ratios so a list can
  lay out before images arrive.
- `SharedCore/Layout/DetailImageLayout.swift` — pure layout maths, no UIKit.
- `AppRuntime/Images/ImageURLResolver.swift` — resolve a display URL to a full-size URL.

All four are independently testable and have no notion of this forum in them.

---

## 7. Local persistence

`nodeseek/AppRuntime/Storage/SQLiteVisitedPostPersistence.swift`

A "recently visited" store on raw SQLite with no ORM. Small, and a reasonable reference for the
minimum amount of machinery a cache-with-eviction actually needs.

---

## Tests

`nodeseekTests/SharedCore/` covers the parsing, challenge-detection, routing and layout layers
directly — they are pure logic and run without a simulator. `make spm-test` runs them through
SwiftPM; see the `Makefile` for the Xcode-hosted targets.
