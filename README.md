# Tabby

Save people from LinkedIn, Instagram and TikTok to a personal rolodex straight from the iOS share sheet, then organize them into tag-driven Spaces.

Status: Phases 0–3 (extraction, data layer and app, share extension, enrichment) awaiting device testing. See [`docs/PLAN.md`](docs/PLAN.md) for the full build plan.

## Getting started (macOS, Xcode 16+)

```sh
brew install xcodegen
echo 'DEVELOPMENT_TEAM = YOUR_TEAM_ID' > Config/Local.xcconfig   # gitignored; see Config/Tabby.xcconfig
xcodegen generate
open Tabby.xcodeproj
swift test --package-path TabbyKit
```

Running on a phone: follow [`docs/DEVICE_TESTING.md`](docs/DEVICE_TESTING.md), the checklist for the phase gates CI can't cover.

## Phase 0 spike

Put 10 real profile URLs per platform in `urls.txt` (one per line), then:

```sh
swift run --package-path TabbyKit tabby-extract --file urls.txt --fixtures TabbyKit/Tests/TabbyKitTests/Fixtures
```

It prints what tiers 1–3 extracted for each URL and a markdown hit-rate table per platform.
