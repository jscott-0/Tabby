# Tabby

iOS rolodex for LinkedIn / Instagram / TikTok profiles, saved via the share sheet.
Spec: "Tabby — iOS Spec for Claude Code" doc. Build plan and phase gates: `docs/PLAN.md`.

## Layout
- `TabbyKit/` — Swift package with all shared logic: parsers, fetcher, SwiftData models and `TabbyStore` (every write goes through it). `tabby-extract` is the Phase 0 spike CLI.
- `Tabby/` — main app target. `TabbyShare/` — share extension target.
- `SharedUI/` — SwiftUI components compiled into both targets (tag picker, avatars, chips). iOS-only, so it lives outside the package.
- `project.yml` — XcodeGen spec; `Tabby.xcodeproj`, Info.plists and entitlements are generated, not committed.
- `Config/Tabby.xcconfig` — bundle ID, App Group and team; personal overrides go in gitignored `Config/Local.xcconfig`.
- `TabbyUITests/` — simulator smoke tests. The app's `-uiTesting` launch argument swaps in an in-memory sample store and an offline HTTP stub (`Tabby/AppServices.swift`).

## Commands (macOS)
- `swift test --package-path TabbyKit`
- `xcodegen generate && open Tabby.xcodeproj`
- `swift run --package-path TabbyKit tabby-extract --file urls.txt --fixtures TabbyKit/Tests/TabbyKitTests/Fixtures`

CI (`.github/workflows/ci.yml`, macOS 26 runner, Xcode 26 / iOS 26 SDK) runs the package tests, a simulator build, and the UI tests on a simulator; cloud sessions have no Swift toolchain, so CI is the compile check. The UI test job prints each screenshot as a base64 JPEG between `SCREENSHOT_BEGIN <name>` / `SCREENSHOT_END` lines in its log (also uploaded as the `screenshots` artifact).

## Rules
- No third-party packages without asking (XcodeGen is an approved build tool, not a dependency).
- Every parser has fixture-based unit tests; network calls go through `HTTPClient` so tests stub them.
- Fixtures and demo data use invented people only.
- The share extension writes and exits; slow work (tier 4 retries) runs in the main app.
- SwiftData: no `@Attribute(.unique)`, all properties optional or defaulted (CloudKit-ready); dedup in code by platform + lowercased handle.
- Bundle IDs: `com.tabbyapp.tabby`, `com.tabbyapp.tabby.share`; App Group `group.com.tabbyapp.tabby`. Minimum iOS 18.
- Out of scope until usage data says otherwise: Talent Spotter AI chat, suggested profiles.

## UI style
- Liquid Glass on iOS 26 with iOS 18 fallbacks, all through `SharedUI/GlassStyle.swift`: `primaryActionStyle()` / `secondaryActionStyle()` for buttons, `glassSurface(in:tint:)` for chips and banners, `floatingBottomBar` / `floatingTopBar` instead of `safeAreaInset` + `.bar`, `SheetCloseButton` / `SheetConfirmButton` in sheet toolbars. Don't call `.glassEffect` or `.buttonStyle(.glass…)` directly.
- Glass is for controls and navigation that float over content; content cards (Space tiles, paywall options) stay solid.
