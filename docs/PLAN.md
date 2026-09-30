# Tabby — Build Plan

## Context
Build Tabby from the spec doc "Tabby — iOS Spec for Claude Code": an iOS rolodex where users save LinkedIn / Instagram / TikTok profiles via the system share sheet, organize them with tags into rule-based Spaces, and (paid) browse/search a shared Talent Search index. Scope is kept tight: the spec's Talent Spotter AI chat and suggested profiles are deferred until real usage shows demand. The repo `/home/user/Tabby` is empty (no commits).

Decisions made: **iOS 18 minimum**, **Supabase** backend, bundle prefix **com.tabbyapp** (app `com.tabbyapp.tabby`, extension `com.tabbyapp.tabby.share`, App Group `group.com.tabbyapp.tabby`), builds verified on **GitHub Actions macOS CI** (this container has no Swift/Xcode).

The spec's own 5-phase build plan only covers the local rolodex; the later sections (accounts, paywall, onboarding, Talent Search, demo, settings) have no phases. This plan keeps the spec's phases 0–3 and adds phases 4–8 for those.

## Repo layout
```
project.yml               XcodeGen spec → Tabby.xcodeproj (generated, not committed)
Tabby/                    main app target (SwiftUI)
TabbyShare/               share extension (SwiftUI in UIHostingController)
TabbyKit/                 local Swift package
  Sources/TabbyKit/       Models, ProfileURLParser, MetadataFetcher, BioParser, TagStore, SpaceRule, Search
  Sources/tabby-extract/  Phase 0 CLI
  Tests/TabbyKitTests/ + Tests/Fixtures/{linkedin,instagram,tiktok}/*.html
backend/supabase/         migrations, edge functions (Phase 4+)
.github/workflows/ci.yml  macos runner: swift test (TabbyKit) + xcodebuild build (app + extension, simulator)
```
**Flag for approval:** XcodeGen is a build-time tool, not an app dependency, but the spec says "no third-party packages without asking" — using it avoids hand-writing `project.pbxproj` from Linux. Fallback: a minimal hand-written pbxproj.

## Phases (each ends with a gate)

**Phase 0 — Scaffold + extraction spike**
- Repo skeleton, `project.yml`, CI workflow, `.gitignore`, CLAUDE.md with the spec's "Rules for Claude Code".
- `ProfileURLParser` (tier 1): LinkedIn `/in/{slug}`, Instagram `/{handle}` (strip `igsh`/`utm_*`, reject `p|reel|stories|explore`), TikTok `/@{handle}` + short-link redirect resolution; URL extraction from share text.
- `MetadataFetcher` behind an `HTTPClient` protocol (tier 2 og: tags, tier 3 embedded JSON), mobile Safari UA, 8 s timeout. `BioParser` (NSDataDetector links/emails, LinkedIn "Name - Headline - Company").
- `tabby-extract` CLI: reads URLs, prints per-field results, saves HTML to Fixtures.
- Gate: fixture-based unit tests green in CI; **you** run the CLI on your Mac against 10 real URLs/platform → hit-rate table.

**Phase 1 — Data layer + main app (local)**
- SwiftData `Person`, `Account`, `Tag`, `Space` (+ `SpaceRule` ANY/ALL + platform filter, computed contents), no `.unique`, all properties optional/defaulted (CloudKit-ready), dedup key `platform + lowercased handle` in code. Store in App Group container.
- Screens: Spaces grid (built-ins All / Recently added / Untagged / Needs info), Space detail (filters, sort, swipe, bulk tag), Person detail, Tags (rename/recolor/merge/delete), Space editor sheet, local search. Previews with 20 seeded People.
- Gate: main-app acceptance criteria; search perf test over 1,000 People.

**Phase 2 — Share extension**
- Activation rules (URL, text, image ×1), full-height sheet, tier-1 result < 300 ms, Importing… state, editable preview, tag row (recent first, inline create), note, Save above keyboard, duplicate merge ("Already in Tabby"), post-vs-profile detection, offline save → Needs info. Success state with Open in Tabby (`tabby://person/{id}`) / Done, local-notification fallback.
- Gate: share acceptance criteria on a physical device from all 3 apps (you).

**Phase 3 — Enrichment**
- Tiers 2–3 in extension, avatar download + 400 px downscale (`.externalStorage`), retry queue on launch with tier-4 background WKWebView, debug screen with per-tier success log.
- Gate: Phase 0 hit rates reproduced on device; failed shares recover next launch.

**Phase 4 — Accounts + backend (Supabase)**
- Sign in with Apple (+ email magic link), `profiles`, `entitlements`, `interests` tables with RLS; account deletion edge function. Local-first sync of My Tabs to Supabase (offline stays working).
- Gate: sign in/out, delete account end-to-end.

**Phase 5 — Onboarding + first-save teaching mode**
- Welcome → account → interests (categories + creator grid) → first suggestion → deep link out → teaching-mode share sheet (3-item checklist, Import, Skip) driven by `onboardingStep` in App Group → back on the saved Person. "Didn't see Tabby?" card + paste-link fallback.
- Status: built with Phase 6 (same PR). The first person saved, from the share sheet or a pasted link, ends onboarding.

**Phase 6 — Paywall + purchases**
- Paywall (Unlimited Tabs one-time, Tabby Pro monthly/annual), storefront routing via `Storefront.current.countryCode`: US → Stripe web checkout in SFSafariViewController + webhook edge function; else StoreKit 2 + App Store Server Notifications. Single server-side entitlement. Free gating: 1 Person, locked drafts in "Waiting to unlock", Pro badges.
- Demo mode: separate in-memory store from bundled JSON seed (~30 People, ~200 index profiles, all fictional; no AI chat), persistent banner.
- Gate: demo leaves the real store byte-identical; both purchase paths unlock drafts.
- Status: app side built ahead of Phase 4. Account and entitlement live on the device (StoreKit 2 is
  the source of truth; cached in the App Group for the extension). Demo uses the in-app sample data,
  not the Talent Search index, which doesn't exist yet. Web checkout needs Phase 4's webhook, so it's
  off until `TABBY_WEB_CHECKOUT_URL` is set. Placeholders: prices (`Config/Tabby.storekit`),
  onboarding creators (`OnboardingCatalog`), Terms/Privacy links.

**Phase 7 — Talent Search (browse + keyword search only)**
- Shared index table (public fields only, save counts, opt-in aggregated tags), Postgres full-text search, add-to-My-Tabs from a result. Opt-out/removal request flow (pending legal).
- **Out of scope until there's usage data:** Talent Spotter AI chat, embeddings/pgvector, LLM edge function, suggested-profiles feed. The Talent Search tab has no chat UI; Pro's value is unlimited Tabs + full Talent Search results + notifications.

**Phase 8 — Settings + P1**
- Settings groups per spec (manage-subscription routing, export CSV/vCard, delete account, legal). Then P1: screenshot OCR, merge People, on-device suggested tags, iCloud sync.

## Still open (don't block Phases 0–3)
Prices; RevenueCat vs. hand-rolled entitlements; Spaces rules-only in v1 (assume yes); whether Pro is compelling enough without AI chat (revisit with usage data); Talent Search GDPR/CCPA review; onboarding creator list source.

## How I'll work
- Branch per phase, draft PR each; CI must be green before a phase is called done. I'll need **you** for on-device gates and real-URL runs.
- First step on approval: Phase 0 (scaffold, CI, TabbyKit parsers + tests, CLI).

## Verification
- CI: `swift test --package-path TabbyKit` and `xcodebuild -scheme Tabby -destination 'platform=iOS Simulator,name=iPhone 16' build` on `macos-latest`.
- Parser tests run against saved HTML fixtures, network stubbed via `HTTPClient` protocol.
- Device checks by you per phase gate, using the spec's acceptance criteria as the checklist.
