# Launchtap

A native macOS 26 “Launchpad” replica built with Swift 6 and SwiftUI. It recreates the
full-screen app grid — Liquid Glass surfaces, folders, search, paging, jiggle mode and drag
reordering — as a menu-bar app, while using the real desktop picture as its backdrop.

The project deliberately targets **macOS 26.0+** and builds **universal (`x86_64 arm64`)** so it
runs on Intel Macs as well as Apple silicon. It is **ad-hoc signed**: there is no Developer ID,
no notarization, and no App Store submission. See [Distribution](#distribution-without-a-developer-id)
for what that means for users.

## Quick start

```sh
# Debug build + full test suite (145 tests in 19 suites)
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad -configuration Debug \
  -derivedDataPath /tmp/launchpad-debug test

# Build, ad-hoc sign, install to /Applications and relaunch
./tools/install-release.sh

# Build and package a DMG for download (writes dist/Launchpad-<version>.dmg + .sha256)
./tools/make-dmg.sh
```

Both release scripts build with `ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO` into
`~/Library/Caches/Launchpad/Release`, then apply the ad-hoc signature explicitly. An incremental
Xcode build can leave a previous signature on the cached product, so the explicit re-sign avoids
a stale identity being shipped. The Xcode target itself uses `CODE_SIGN_IDENTITY = "-"`.

The source group is filesystem-synchronized: new files added under `Launchpad/` are picked up
automatically, with no project-file edits.

Always build and compile after making changes. UI and trackpad behaviour need to be verified by a
human on a real Mac — the test suite covers logic, not gestures.

## What it does

- 7×5 default grid, configurable to 7/8/9 columns and 4/5/6 rows (the reference grid is derived
  from the screenshots in `screenshots/`). No grid zoom.
- Folders with a lifted glass plate, drag-to-create from two apps (with a name prompt), drag
  between folders, and magnify on hover.
- Live search, keyboard navigation, jiggle mode and drag reordering with a transient new page
  created after an edge dwell.
- Finger-following paging: two-finger swipes translate the strip live and commit by distance or
  projected velocity. Three-, four- and five-finger sideways swipes page the grid too, instead of
  switching desktops or full-screen apps.
- With the trackpad take-over enabled, Accessibility granted and **Pinch with four fingers** on, a
  four-finger **pinch** opens the launcher and a **spread** closes it. Each contact sequence fires
  at most one gesture, so relaxing the fingers after a pinch cannot immediately close it. The
  gesture pair is shared with macOS's Show Desktop, so the pinch that restores the windows does not
  also open Launchpad.
- The edit-mode “×” opens the uninstall panel from frames 065–066: it scans the app bundle
  and the matching folders under `~/Library` (Application Support, Caches, Preferences, Saved
  State, Containers, WebKit, HTTP storage, LaunchAgents, Logs), shows each item with its size,
  and moves only the checked items to the Trash.
- Drag an app out of the grid and drop it on the Dock to pin it there. Crossing into the Dock
  hands the gesture to a real file drag, so the Dock slides its own icons aside instead of
  restarting. Drop it on the Trash instead and the same uninstall list opens before anything is
  moved, so leftover files can be reviewed.
- `⌥Space` toggles the panel (configurable), plus an optional screen-corner trigger.
- The Dock stays visible; the menu bar is painted over rather than hidden, because hiding it
  hides the Dock as well.
- App icons follow the system style (Normal / Clear / Dark / Tinted) live, via `NSWorkspace`.

## Where things live

| Path | Purpose |
| --- | --- |
| `Launchpad/App/AppDelegate.swift` | Lifecycle, settings observation, hotkey, hot corner, pinch wiring |
| `Launchpad/App/AppModel.swift` | Observable grid/page/folder/search state and drag transactions |
| `Launchpad/App/LaunchpadSettings.swift` | Persisted preferences (`UserDefaults`, keys `Launchpad.*`) |
| `Launchpad/App/SystemLaunchpadGesture.swift` | Dock preference override for the system Apps pinch |
| `Launchpad/App/GlobalHotKey.swift`, `HotCornerMonitor.swift` | Global activation |
| `Launchpad/Window/LaunchpadPanelController.swift` | Panel presentation, paging scroll events, gesture suppression, banner state |
| `Launchpad/Window/BackdropView.swift`, `MenuBarCoverWindow.swift` | Wallpaper backdrop and menu-bar cover |
| `Launchpad/Views/` | SwiftUI grid, folders, search, settings and the permission banner |
| `Launchpad/Services/PinchGestureMonitor.swift` | Raw `MultitouchSupport` contacts; pinch/spread recognizer and four-finger swipe tracker |
| `Launchpad/Services/TrackpadGestureBlocker.swift` | Session event taps and the swallow policy |
| `Launchpad/Services/AccessibilityAccess.swift` | Permission prompt, stale-grant repair, installer helpers |
| `Launchpad/Services/UninstallInventory.swift`, `AppUninstaller.swift` | App-footprint scan, sizes and the trash flow |
| `Launchpad/Services/DockDrop.swift` | Dock geometry, handoff hit testing and Trash detection |
| `Launchpad/Services/DockDragSession.swift` | Native file-drag handoff and the Trash guard window |
| `Launchpad/Views/UninstallDialog.swift` | White uninstall panel from frames 065–066 |
| `LaunchpadTests/` | Swift Testing suites (layout, settings, gestures, policy, geometry) |

User data:

- Custom layout: `~/Library/Application Support/Launchpad/layout.json` (explicit pages plus a
  capacity; an old flat `items` array is migrated by chunking into pages).
- Preferences: `UserDefaults` under `com.example.Launchpad`.
- Debug logging: subsystem `com.example.Launchpad`, categories `gesture` and `trackpad`. Inspect
  with `/usr/bin/log show --last 5m --info --debug --predicate 'subsystem == "com.example.Launchpad"'`.

## Permissions and gesture blocking

Native four-finger gestures (desktop swipe, Mission Control, Show Desktop and the system Apps
pinch) belong to the Dock, not to the frontmost app. Launchpad cannot pause them with a public
API, so `TrackpadGestureBlocker` installs head-insert event taps on **both** the session and
annotated-session streams for private CGEvent types **29 (`gesture`)** and **30 (`dockControl`)**.
While the panel is visible, every event of those types is dropped; blocking outlives the panel by
**450 ms** so the Dock's late decision for the closing spread cannot slip through.

Two-finger paging arrives as scroll-wheel events (type 22) and is never blocked. Pinch, spread
and the three-, four- and five-finger page swipe are read directly from the trackpad's
`MultitouchSupport` contacts, so they keep working while the Dock's versions stand down. The
private symbols are resolved at runtime; if unavailable, monitoring is simply inactive rather than
crashing.

Spread-to-close and multi-finger paging are gated on **Block system gestures while open** plus
Accessibility; pinch-to-open additionally needs the **Pinch with four fingers** switch. Without
Accessibility the Dock's own gestures still run, so Launchpad would race them rather than replace
them; the banner asks for the grant instead. While pinch-to-open is on, macOS's own Apps view is
switched off (via the Dock's `showSpotlightGestureEnabled` and the legacy
`showLaunchpadGestureEnabled`) so its pinch cannot open it instead of Launchpad. Turning that
switch off restores the Dock's Apps pinch; the block setting still keeps system gestures from
interrupting an open Launchpad. Spotlight itself is untouched and stays on `⌘Space`. The override
is restored as soon as the switch or the block setting is turned off, or the grant goes missing.

macOS uses the same four-finger gestures for **Show Desktop**: a spread reveals the desktop and the
following pinch restores the windows. `DesktopRevealState` remembers a spread seen while no panel
was on screen, so the next pinch is treated as that restore and does **not** open Launchpad. There
is deliberately no timeout — the user may stay on the desktop as long as they like. Pinch again to
open the launcher, or use `⌥Space` / the menu bar item, which always take precedence. A spread that
closes Launchpad does not arm this state because the Dock is blocked at that moment.

**All of this requires Accessibility access.** Without it the app still works, but the native
gestures are not suppressed.

### The ad-hoc signing trap (important)

macOS ties an **ad-hoc** signature's Accessibility grant to that build's **code hash**. After a
rebuild or an update:

- System Settings still shows “Launchpad” as **on**, but the new binary is not trusted.
- `AXIsProcessTrusted()` returns false and the event taps are never installed.
- The failure is silent: the desktop swipe and Show Desktop leak again.

This is not a bug in the blocker; it is how TCC identifies ad-hoc code. Two mechanisms handle it:

1. **The banner.** While the panel is visible and blocking is enabled but the grant is missing,
   a glass capsule appears next to the search field: **Allow gesture blocking → Grant Access**.
2. **Grant Access** in *Settings → General → Trackpad*, and in the banner, calls
   `AccessibilityAccess.grant()`. It runs `tccutil reset Accessibility com.example.Launchpad` to
   remove the stale entry, asks the system for access again, and opens the Accessibility pane.
   The status row turns green live when the user enables it.

Consequence for released builds: **users must re-approve Accessibility once after every update.**
Batch releases accordingly. A Developer ID signature would make the grant survive updates — that
is its main advantage here beyond Gatekeeper — but no Apple developer account is available for
this project, so the app ships ad-hoc. Do **not** substitute a self-signed certificate: other
Macs do not trust it, and asking users to trust a local root certificate is worse than ad-hoc.

The macOS Apps pinch is disabled while pinch-to-open is active — **Pinch with four fingers** on,
the block setting on and Accessibility granted — by setting the Dock keys
`showSpotlightGestureEnabled` and legacy `showLaunchpadGestureEnabled` to `0`. They are restored
when the pinch switch or the block setting is turned off, or Accessibility is missing.
`TrackpadFourFingerPinchGesture` is left alone so the native spread still works when Launchpad is
hidden. Show Desktop is never permanently disabled; an old build that stranded
`showDesktopGestureEnabled = 0` is repaired once at launch.

## Distribution without a Developer ID

`./tools/make-dmg.sh` produces a compressed, verified DMG in `dist/` with an `Applications`
symlink, plus a `.sha256` file. Publish both on the landing page.

Without notarization, every download is quarantined by the browser and macOS blocks the first
launch. Users see “Apple cannot check it for malicious software” and must go to
**System Settings → Privacy & Security → Open Anyway**, authenticate, then launch again. The
warning returns for each new version. `LANDING.md` contains ready-to-use user-facing copy for
these steps and for the Accessibility permission.

Also consider:

- Publishing the source and the DMG checksum. Without Apple's stamp, transparency is the trust
  signal.
- A Homebrew tap or a published `curl` + `hdiutil` installer script: files fetched that way are
  not quarantined, so users avoid Gatekeeper entirely. The tradeoff is a terminal step.
- Delaying Sparkle auto-updates. Replacing the binary re-triggers both Gatekeeper assessment and
  the Accessibility re-approval, which is worse when it happens silently.

There is intentionally no certificate, trust-setting or keychain setup in the repository. If a
Developer ID becomes available later, replace the ad-hoc re-sign in the scripts with that
identity, notarize and staple the DMG; the banner and Grant Access flow can stay as a fallback.

## Known limitations

- macOS hides the Dock for the whole full-screen space; there is no public API to pin it there.
  The panel never joins a foreign full-screen space.
- Private `MultitouchSupport` and CGEvent gesture types can change across macOS versions; the
  code degrades gracefully instead of failing.
- Full gesture suppression depends on the Accessibility grant described above.
- The panel is a borderless floating window; opening Settings hides it, as switching apps does.
