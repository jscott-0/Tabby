# Device testing checklist

The phase gates in `docs/PLAN.md` that CI can't check. Work top to bottom. Anything that fails,
note what you did, what you expected, and what happened (a screenshot helps).

## 0. First run (≈10 min)

1. `brew install xcodegen` (once).
2. Create `Config/Local.xcconfig` (gitignored) with your team ID, from
   developer.apple.com → Membership:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```
   If Xcode says `com.tabbyapp.tabby` is unavailable, add a bundle ID you own. The extension,
   App Group and tests follow it:
   ```
   TABBY_BUNDLE_ID = com.yourname.tabby
   ```
3. `xcodegen generate && open Tabby.xcodeproj`.
4. Select the **Tabby** scheme and your iPhone, then Run. Automatic signing registers the App Group
   (`group.<bundle id>`) the first time. If it complains about the App Group, open
   Signing & Capabilities on both targets and let Xcode fix it.
5. `swift test --package-path TabbyKit` should pass on your Mac too.

## 1. Main app (Phase 1 gate)

Tap **+ → Add sample data** (DEBUG builds only) to load 20 invented people and 5 Spaces.

- [ ] Spaces grid: built-in Spaces first (All, Recently added, Untagged, Needs info), then pinned
      (Hardware designers), then the rest. Counts and 3 avatars per tile.
- [ ] **Hardware designers** (ALL of designer + hardware) shows only Priya Castellan and Arjun Mehta.
      Add the `hardware` tag to Mara Quill (open her, Edit), come back, and she appears.
- [ ] **Tags → designer → Delete**: people keep existing. The tag is gone from every Space rule, and
      a Space left with no tags shows "This Space has no tags" with **Edit rule**.
- [ ] Space detail: filter chips (tags, platform), sort menu, swipe to retag or delete,
      **Select** → Tag / Delete several.
- [ ] Person detail: **Open in app** opens the profile in Instagram / TikTok / LinkedIn, or Safari.
      Sample handles don't exist, so expect a "not found" page there.
- [ ] Tags screen: rename (renaming to an existing name suggests Merge), color, merge, delete.
- [ ] Space editor: ANY / ALL, platform toggles, and the live "N people match" count.
- [ ] Search feels instant: name, @handle, headline, bio, note or a tag.
- [ ] **+ → Add person**: paste a real profile link. Platform and handle appear immediately, then
      name, bio and avatar fill in.

## 2. Share extension (Phase 2 gate)

Pin Tabby first: in any app tap Share, scroll the app row to **More**, then Edit and add Tabby to Favorites.

- [ ] Instagram: open a profile → ••• → **Share to…** → Tabby. Platform and handle show at once,
      then "Importing…" fills the rest.
- [ ] TikTok: profile → Share → **More** (or Copy link, then paste into Add person) → Tabby.
- [ ] LinkedIn: profile → ••• → **Share via…** → Tabby. Expect a login wall, so handle only; it still saves.
- [ ] Save with no tags and no note works.
- [ ] A tag created in the sheet appears in the app's Tags screen.
- [ ] Share the same profile again: "Already in Tabby as …" with its tags pre-selected. Saving
      doesn't create a second person, and the new note is appended with a date.
- [ ] Share a post or reel: "This looks like a post, not a profile" and it saves the author (TikTok)
      or a link (Instagram reels don't name the author).
- [ ] Airplane mode: share a profile, Save works, and the person is in **Needs info**.
- [ ] **Open in Tabby ↗** after saving: the app opens on that person. If it doesn't, open Tabby
      yourself. It should jump to the person (that's the fallback).
- [ ] Memory: attach Xcode's debugger to the TabbyShare process (Debug → Attach to Process) while
      the sheet is open. The memory gauge should stay well under ~120 MB.

## 3. Enrichment (Phase 3 gate)

- [ ] The airplane-mode person from above: turn networking back on, then leave and reopen Tabby.
      They leave Needs info with a name and avatar (retries run when the app becomes active).
- [ ] Person detail → ••• → **Re-fetch details** refreshes bio, avatar and follower count.
- [ ] **Hit rates**: share ~10 real profiles per platform, then **+ → Extraction log**. It shows
      the hit rate per platform and field. Tap **Share** and send me the report; it's the Phase 0
      table without needing the Mac CLI.

## What to send back

- The Extraction log report.
- Any checklist item that failed, with a screenshot.
- Crashes: Xcode → Window → Devices and Simulators → your phone → View Device Logs, or just the
  console output around the crash.
