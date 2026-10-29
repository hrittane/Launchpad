# Launchpad

A native macOS recreation of the classic Launchpad: a full-screen, blurred app
launcher with paged grids, folders, live search, drag-and-drop arrangement, an
edit/jiggle mode, a global hot key, an optional hot corner, and a menu-bar
agent lifecycle.

The app is built with SwiftUI for the interface, AppKit for the window, blur,
event, and hot-key plumbing, and an MVVM structure with `async/await` services.
There are no third-party dependencies.

- **Platform:** macOS 13.0 or newer
- **Language:** Swift 5.9+ toolchain (project `SWIFT_VERSION = 5.0`, using
  modern concurrency, actors, and SwiftUI APIs available on macOS 13)
- **Bundle identifier:** `com.soufiane.launchpad`
- **Product:** `Launchpad.app`
- **Data:** `~/Library/Application Support/Launchpad/`

---

## Project structure

```text
Launchpad/
├── Config/
│   ├── Info.plist                     # Bundle metadata, LSUIElement, high-res
│   └── Launchpad.entitlements         # Empty: sandbox off, no special powers
├── Launchpad.xcodeproj/
│   ├── project.pbxproj                # Synchronized source groups
│   └── xcshareddata/xcschemes/
│       └── Launchpad.xcscheme         # Shared scheme (app + tests)
├── Launchpad/
│   ├── App/
│   │   ├── AppDelegate.swift          # Menu-bar agent lifecycle
│   │   ├── AppEnvironment.swift       # Composition root / service wiring
│   │   └── LaunchpadApp.swift         # Settings scene + MenuBarExtra
│   ├── Design/
│   │   ├── Metrics.swift              # Every size, timing, spring, and grid formula
│   │   ├── PageDragGeometry.swift     # Page-snap bounds and commit rules
│   │   └── PageDragState.swift        # Isolated high-frequency gesture offset
│   ├── Input/
│   │   ├── HotCornerMonitor.swift     # Global mouse-moved dwell detection
│   │   └── HotKeyManager.swift        # Carbon RegisterEventHotKey
│   ├── Models/
│   │   ├── AppItem.swift              # App identity + metadata
│   │   ├── AppSettings.swift          # Settings, KeyShortcut, HotCorner
│   │   └── FolderItem.swift           # Folder model and display name
│   ├── Resources/
│   │   └── Localizable.xcstrings      # English source + French translations
│   ├── Services/
│   │   ├── AppDirectoryMonitor.swift  # NSMetadataQuery debounced rescans
│   │   ├── AppScanner.swift           # Actor: authoritative FileManager scan
│   │   ├── GridReorder.swift         # Pure live-reorder preview + drop model
│   │   ├── IconProvider.swift         # Actor-backed icon cache + bitmaps
│   │   ├── LayoutEngine.swift         # Pagination, normalization, folder rules
│   │   ├── LayoutStore.swift          # Actor: debounced JSON persistence
│   │   ├── LaunchAtLoginService.swift # SMAppService wrapper
│   │   ├── SearchEngine.swift         # Ranked prefix/word/substring/fuzzy search
│   │   └── SettingsStore.swift        # UserDefaults JSON settings
│   ├── ViewModels/
│   │   └── LaunchpadViewModel.swift   # All overlay state and interactions
│   ├── Views/
│   │   ├── AppIconImage.swift         # Async icon view with fallback tile
│   │   ├── BackgroundView.swift       # Shared blur + tint (overlay, Dock strip, patch)
│   │   ├── FolderPanelView.swift      # Folder panel, paging, drag-out
│   │   ├── InfoSheet.swift            # Native Get Info sheet
│   │   ├── ItemIconView.swift         # App/folder tile, jiggle, badge, menu
│   │   ├── LaunchpadRootView.swift    # Root layout, search, pages, drag layer
│   │   ├── PageDots.swift             # Clickable page indicators
│   │   ├── PageView.swift             # One paged grid with reorder preview
│   │   ├── PreferencesView.swift      # SwiftUI Settings content
│   │   ├── SearchBar.swift            # Growing search field
│   │   └── ShortcutRecorder.swift     # AppKit key-chord recorder
│   ├── Window/
│   │   ├── DockBackgroundWindowController.swift # Backdrop strip behind the Dock
│   │   ├── DockReservation.swift      # Dock edge/thickness and window frames
│   │   ├── LaunchpadWindow.swift      # Borderless, key-capable overlay
│   │   ├── LaunchpadWindowController.swift
│   │   ├── MenuBarPatchWindowController.swift # Corner patch for a side Dock
│   │   ├── PreferencesWindowController.swift
│   │   ├── WindowLevels.swift         # Above status bar / below Dock levels
│   │   └── WindowManager.swift        # Show/hide, mirrors, screen changes
├── LaunchpadTests/
│   ├── CoreTests.swift                # 30 unit tests
│   ├── GridReorderTests.swift         # 14 reorder/folder-drop tests
│   └── SmokeTests.swift               # Hosted-app smoke test
├── README.md
└── spec.md                            # Requirements + agreed clarifications
```

Xcode 16+ synchronized folders (`PBXFileSystemSynchronizedRootGroup`) are used,
so files added under `Launchpad/` and `LaunchpadTests/` are compiled
automatically. The app target is `Launchpad`; the test target is
`LaunchpadTests`.

---

## Info.plist and entitlements

### `Config/Info.plist`

| Key | Value | Why |
| --- | --- | --- |
| `CFBundleIdentifier` | `$(PRODUCT_BUNDLE_IDENTIFIER)` → `com.soufiane.launchpad` | Stable identity, also used by `SMAppService` |
| `CFBundleName` / `CFBundleDisplayName` | `Launchpad` | App/menu-bar name |
| `CFBundlePackageType` | `APPL` | Application bundle |
| `CFBundleShortVersionString` / `CFBundleVersion` | `1.0` / `1` | Version metadata |
| `LSMinimumSystemVersion` | `$(MACOSX_DEPLOYMENT_TARGET)` → `13.0` | Deployment target |
| `LSApplicationCategoryType` | `public.app-category.utilities` | Utilities category |
| `LSUIElement` | `true` | Menu-bar agent: no Dock icon, no app menu |
| `LSMultipleInstancesProhibited` | `true` | One launcher instance |
| `NSHighResolutionCapable` | `true` | Retina rendering |
| `NSHumanReadableCopyright` | Project copyright | Metadata |

No usage-description keys are needed. The app does not use the camera,
microphone, contacts, calendars, location, Apple Events, or Accessibility APIs.
App names/icons come from public `Bundle`/`NSWorkspace` metadata, and launching
uses `NSWorkspace.open`.

### `Config/Launchpad.entitlements`

The entitlements file is intentionally an empty `<dict/>`:

- **App Sandbox: OFF** (`ENABLE_APP_SANDBOX = NO`). Launchpad must enumerate
  `/Applications`, `/System/Applications`, and `~/Applications`, launch any
  installed app, and move user apps to the Trash. A sandboxed build would need
  user-selected-folder access for each location and still could not mirror
  Launchpad's system-wide behavior.
- **Hardened Runtime: ON** (`ENABLE_HARDENED_RUNTIME = YES`). No hardened-runtime
  exceptions are required.
- **Signing:** `CODE_SIGN_IDENTITY = "-"` (ad-hoc), `CODE_SIGN_STYLE = Manual`.
  For distribution, select your Developer ID team in Xcode, keep Hardened
  Runtime enabled, and notarize the archive.

App discovery, layout JSON, and icon caching all work without privacy prompts.

---

## Build and run

### Xcode

1. Open `Launchpad.xcodeproj`.
2. Select the `Launchpad` scheme and **My Mac**.
3. Press **Run** (⌘R). The app has no Dock icon; use the grid icon in the menu
   bar or press **F4**.
4. To run the tests, press **Test** (⌘U) or choose **Product → Test**.

### Command line

```sh
# Build
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad \
  -configuration Debug -derivedDataPath .build build \
  CODE_SIGNING_ALLOWED=NO

# Run the built app
open .build/Build/Products/Debug/Launchpad.app

# Test suite (44 unit tests + 1 hosted smoke test = 45 total)
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad \
  -configuration Debug -derivedDataPath .build test \
  CODE_SIGNING_ALLOWED=NO

# Debug-only smoke test: shows the overlay, prints layout diagnostics,
# reports whether a visible overlay window exists, then exits.
.build/Build/Products/Debug/Launchpad.app/Contents/MacOS/Launchpad --smoke-test
```

The smoke test prints a line such as:

```text
SMOKE overlayWindows=1 pages=3 items=75 frame=(0.0, 82.0, 1920.0, 1118.0)
```

The frame excludes the Dock strip on the current display (1920×1200 with an
82 pt bottom Dock). If `overlayWindows=0`, the app did not create/show its
window correctly.

### First launch and permissions

- macOS may ask for confirmation the first time the app opens another app; this
  is standard Launch Services behavior.
- **Launch at login** registers the app through `SMAppService.mainApp`. The
  setting is only effective for a signed app in `/Applications` (or another
  stable location); ad-hoc debug builds may fail to register and the toggle
  falls back to the system's real status.
- The global shortcut uses Carbon hot keys, so no Accessibility permission is
  needed.
- The hot corner uses a global mouse-moved monitor. macOS may require Input
  Monitoring permission for global mouse monitoring on some releases; the
  status menu and hot key always remain available.

### Data files

| Path | Contents |
| --- | --- |
| `~/Library/Application Support/Launchpad/layout.json` | Ordered pages, folders, and folder names |
| `UserDefaults` (`com.soufiane.launchpad`) | Grid, appearance, activation, and shortcut settings |
| Memory cache | Decoded app icons (2× bitmap, `NSCache`) |

`layout.json` is written atomically after a 0.5 s debounce and flushed once more
during normal termination, so arrangement changes made just before Quit are
durable. Corrupt or missing files fall back to a fresh alphabetical layout;
unknown apps are dropped and new apps are appended in localized, case-insensitive
alphabetical order. Tests never write to the real layout file (the app detects
an XCTest environment and skips runtime startup).

---

## Behavior and controls

- **Show/hide:** F4 (configurable), status-bar menu, hot corner (bottom-right by
  default), or ⌘⇧L from the status menu.
- **Open:** click an app, press Return on a focused app, or use the context menu.
- **Search:** type anywhere. Search matches names and app names inside folders.
- **Pages:** trackpad swipe, mouse wheel, page dots, ⌘1…⌘9, Tab / Shift-Tab.
- **Folders:** drop an app on another app to create a folder immediately. The
  target highlights under the pointer; holding briefly shrinks it into the
  folder-glass preview first. The new folder zooms open from its tile named
  “Untitled Folder”, with the name selected so typing replaces it; Return or a
  click outside commits, Escape restores the name. Click a folder to open it.
  Double-click a folder tile to open it and edit its name. Drag apps out of an
  open folder to return them to the main grid. A folder with fewer than two apps
  dissolves.
- **Edit mode:** long-press an icon (0.5 s), hold Option, or use the context
  menu's delete action prerequisites. In edit mode, deletable user apps show an
  “×” badge. A blank click exits edit mode; a second blank click closes the
  overlay. Escape and Return also exit edit mode.
- **Get Info:** right-click → **Get Info** opens a native SwiftUI sheet.
- **Preferences:** ⌘, or the status menu → **Preferences…**.

---

## Manual QA checklist

### Discovery and layout

- [ ] Launch the app and confirm the menu-bar icon appears (no Dock icon).
- [ ] Show the overlay; all apps from `/Applications`, `/System/Applications`,
      `/System/Applications/Utilities`, and `~/Applications` appear once each.
- [ ] Launchpad itself never appears in the grid.
- [ ] Single-click an app: it launches and the overlay closes. The very first
      click works even when another app was active when Launchpad appeared.
- [ ] Install or remove an app while the app is running; after the debounced
      rescan the grid updates without losing the custom order.
- [ ] Reorder apps, quit, relaunch; the order is restored from
      `layout.json`.
- [ ] Change the Mac language to French and relaunch; UI strings are French.
      (Console testing: `Launchpad.app/Contents/MacOS/Launchpad -AppleLanguages '(fr)'`.)
- [ ] Delete/corrupt `layout.json` and relaunch; a fresh alphabetical layout is
      created instead of crashing.
- [ ] Use **Reset Layout** from both the status menu and Preferences; all folders
      dissolve, apps become alphabetical, and app files are untouched.

### Window and background

- [ ] Overlay covers the full width at the top edge and the whole screen above
      the Dock; the Finder/macOS menu bar and status items are not visible.
- [ ] The Dock remains visible above the overlay and can still launch apps; the
      area behind it shows the same blurred backdrop, not an untreated desktop
      strip.
- [ ] Move the Dock to the left or right edge and show Launchpad again: the
      strip behind the Dock is blurred, the small menu-bar corner above it is
      covered, and the Dock remains usable.
- [ ] Move the pointer to the top edge: no menu titles appear and clicking there
      opens no macOS menu.
- [ ] Background is a blurred desktop with a dark/light tint; increasing **Blur
      intensity** deepens the tint.
- [ ] Enable **Reduce Transparency** in System Settings → Accessibility →
      Display; the background becomes a solid dark gray fallback.
- [ ] With **Show on all displays** enabled, every display mirrors the UI, but
      only the cursor display accepts clicks/keys.
- [ ] Disconnect/reconnect a display while the overlay is open; the primary
      window relocates and mirrors refresh.
- [ ] With another app's window open, hiding Launchpad returns focus to that app;
      with no other window, the app hides itself.

### Grid and paging

- [ ] Default grid is 7 × 5; Preferences allows 5–9 columns and 4–6 rows.
- [ ] At 1440 × 900 with 96 pt icons all icons and two-line labels fit; icons
      shrink automatically at dense settings.
- [ ] Page dots appear only with more than one page and are clickable.
- [ ] ⌘1…⌘9 jumps to the page; Tab / Shift-Tab cycle pages.
- [ ] Trackpad two-finger horizontal scroll follows 1:1 for at most one page,
      rubber-bands at the ends, then snaps to the adjacent page (or back) on
      release; momentum never drags through additional pages.
- [ ] A non-precise mouse wheel flips one page per notch with a 0.4 s cooldown.
- [ ] Click-drag on empty background swipes one page and snaps into place.
- [ ] Folder paging uses the panel width for its commit distance and snaps the
      same way.

### Search

- [ ] Typing a letter anywhere focuses search and filters immediately.
- [ ] Search is case- and diacritic-insensitive; prefix results rank above word
      prefixes, substrings, then one-edit fuzzy matches (queries ≥ 4 chars).
- [ ] Search includes apps inside folders.
- [ ] Results paginate internally when they exceed one page; page dots stay
      hidden while searching.
- [ ] “No Results” appears centered when nothing matches.
- [ ] Return launches the first result; arrows navigate the results.
- [ ] The clear button appears with text and clears the query; Escape clears
      search before closing the overlay.

### Folders

- [ ] Drag an app onto another: the target gets a light ring, and after a short
      dwell it shrinks into the folder glass. Releasing immediately creates and
      opens the new folder named “Untitled Folder” with its name selected.
- [ ] Drop an app onto an existing folder to append it (maximum 100 apps; a full
      folder is not treated as a drop target, so the app is not lost).
- [ ] In the open-folder name field, typing replaces the selection; Return or a
      click outside commits, Escape restores the previous name.
- [ ] Single-click a folder in the grid opens it. Double-click the folder tile
      opens it and focuses the title field. Return confirms a rename.
- [ ] Drag within an open folder to reorder with the reflow preview; swipe or
      scroll pages inside folders with more than 12 apps.
- [ ] Drag an app out of the folder panel; the panel closes as the cursor
      leaves and the icon continues onto the main grid.
- [ ] Removing the second-to-last app dissolves the folder and releases the
      survivor; removing the last app deletes the folder.
- [ ] Right-click a folder → **Remove from Launchpad** dissolves it and releases
      its apps without deleting anything.
- [ ] Drag to the left/right 60 pt edge and hold 0.8 s; the grid flips pages,
      creating a temporary empty last page if necessary, and empty pages are
      removed on drop.

### Animations

- [ ] Show: background fades in (0.25 s); icons scale/fade in (0.30 s) with a
      row stagger capped at 0.1 s.
- [ ] Hide: icons scale/fade out (0.22 s), the background fades (0.15 s), then
      windows order out.
- [ ] Page changes use the 0.40 s / 0.86 spring.
- [ ] Search cross-fades (0.2 s) and page dots hide.
- [ ] Folder open scales from the folder icon center with a 0.35 s / 0.82
      spring; the grid blurs and dims. Close reverses in 0.25 s.
- [ ] Edit mode jiggles ±2° with a ±0.5 pt translation; exiting eases back.
- [ ] Dragging scales the icon to 1.12 with a larger shadow and reflows neighbors
      with a 0.30 s / 0.8 spring.
- [ ] Enable Reduce Motion; all animations become ~0.15 s fades and jiggle
      stops.
- [ ] Deleting an app shrinks/fades it in 0.2 s and neighbors reflow.

### Edit mode and deletion

- [ ] Enter edit mode via long-press, Option, or an icon context menu action.
- [ ] Only user-installed apps outside `/System` show the 22 pt white “×”
      badge; system apps and folders never show it.
- [ ] Clicking the badge asks for confirmation, then moves the app to the Trash
      via `NSWorkspace.recycle`; Cancel does nothing.
- [ ] Blank click exits edit mode; next blank click closes the overlay.
- [ ] Escape exits edit mode → closes folder → clears search → closes overlay.
      Return exits edit mode before launching anything.

### Preferences, hot key, hot corner

- [ ] ⌘, and the status menu both open Preferences.
- [ ] Columns/rows, icon size (64–128), label size (11–15), blur intensity, hot
      corner, global shortcut, **Launch at login**, and **Show on all displays**
      all persist across relaunch.
- [ ] The shortcut recorder captures a chord and the new global shortcut toggles
      the overlay; **Reset** restores F4.
- [ ] Selecting a hot corner shows the overlay after a 0.3 s dwell at that
      corner; **Off** disables it.
- [ ] **Clear Icon Cache** frees icon memory; icons reload.
- [ ] **Show Data Folder** opens `~/Library/Application Support/Launchpad/`.

### Accessibility and performance

- [ ] VoiceOver reads app/folder names, announces button traits, and provides
      “Open” hints and actions.
- [ ] The rotor includes page entries (“Page N of M”).
- [ ] Full keyboard navigation works without a mouse: arrows, Return, Escape,
      Tab, ⌘1…⌘9, ⌘,, Delete-to-search.
- [ ] Focus ring is a 2 pt white (80%) rounded outline.
- [ ] With ~300 apps, cold show is under 150 ms, only current ±1 pages are
      instantiated, and memory stays below 200 MB.
- [ ] Scrolling/paging and drag reflow stay smooth on a ProMotion display.
      Paging offsets are published from a dedicated `PageDragState`, so a
      scroll event only re-evaluates the offset modifier instead of every icon
      on the three visible pages. A committed page slides for 0.30 s with its
      base positions fixed; the page index is swapped in once the slide ends,
      so icon bodies never re-render on the animation's first frame. Item
      drags follow the same rule: the cursor lives in `ItemDragState` and the
      reorder preview is only published when the cursor crosses into another
      cell, so mouse movement never re-renders the grid.

---

## Implementation notes and known limitations

- **Blur radius:** AppKit does not expose a public continuous 40–60 pt Gaussian
  radius. The background uses `NSVisualEffectView` (`.fullScreenUI`) plus a
  tint/dimming overlay; the **Blur intensity** slider adjusts that tint. This is
  documented in Preferences and is an intentional platform limitation.
- **Window layering:** the Dock (level 20) and the menu bar (level 24, status
  items 25) sit at different system levels, so no single window can be both
  above the menu bar and below the Dock. The main overlay is at
  `.statusBar + 1` (level 26) and its frame stops at the Dock edge; a
  non-interactive backdrop window one level below the Dock (level 19) fills the
  Dock strip. The Dock therefore stays visible and clickable while the menu bar
  cannot show through. The app does not modify `NSApp.presentationOptions`:
  AppKit rejects `.hideMenuBar` unless `.hideDock` is also set, which would hide
  the Dock.
- **Side Dock:** with a left or right Dock, the main window starts at the Dock
  edge and leaves the menu-bar-height corner above the Dock exposed. A small
  companion window at level 26 renders the same backdrop there and consumes
  clicks. A bottom Dock needs no patch.
- **Auto-hidden Dock:** macOS stops reserving Dock space in `visibleFrame` when
  the Dock is set to auto-hide. In that case the app reads the Dock's saved
  orientation and tile size on the primary display and reserves a conservative
  strip, so a revealed Dock is not covered. An auto-hidden Dock still follows
  the system setting and remains hidden until the pointer reaches its edge.
- **4-finger pinch:** third-party apps cannot intercept the system pinch/spread
  gesture that Apple's Launchpad used. Use the hot key, hot corner, status menu,
  trackpad horizontal scroll, arrow keys, Tab, or page dots instead.
- **Global mouse monitoring:** the hot corner relies on a global `NSEvent`
  monitor; some macOS versions gate this behind Input Monitoring permission. The
  hot key and status menu are permission-free fallbacks.
- **Multi-display dragging:** mirrors are read-only. Cross-display drag-and-drop
  is not supported; the cursor display is the only interactive one.
- **App Sandbox:** disabled intentionally. Enabling it requires user-selected
  folder access for every app root and changes trash/launch behavior.
- **App discovery:** `FileManager` is authoritative; `NSMetadataQuery` is only a
  change signal and triggers a debounced rescan. This avoids Spotlight indexing
  gaps, especially under `/System`.
- **Folder removal:** “Remove from Launchpad” dissolves the folder and releases
  its apps. It never deletes app files.
- **Get Info:** implemented as a native SwiftUI sheet rather than Finder
  AppleScript, so no Automation permission is required.
- **Page-indicator scale nuance:** icons show from 1.12 → 1.0. The hide
  animation ends near 1.08; subsequent shows start from 1.08 rather than
  snapping back to 1.12 while hidden. Reduce Motion replaces the scale motion
  with fades.
- **Search result stagger:** results cross-fade into the same paged grid and
  inherit the per-row show stagger. There is no separate search-specific
  stagger timer.
- **Launch at login:** uses `SMAppService.mainApp`; registration may fail for
  ad-hoc builds outside `/Applications`. The toggle reflects the actual system
  status after the attempt.
- **Tests:** 44 unit tests cover search ranking, pagination math, reorder
  preview/commit parity, drag-state isolation, folder creation/merge/dissolve
  rules, app-removal return semantics, normalization, JSON persistence, and
  page-snap geometry.
  A hosted smoke test plus the `--smoke-test` debug hook verify that the overlay
  window is created and shown.

---

## Verification performed

```text
xcodebuild ... build      → BUILD SUCCEEDED
xcodebuild ... test       → TEST SUCCEEDED, 45 tests, 0 failures
Launchpad --smoke-test    → SMOKE overlayWindows=1 pages=3 items=75 frame=(0.0, 82.0, 1920.0, 1118.0)
window levels (debug)     → overlay 26 at (0, 82, 1920, 1118); Dock backdrop 19 at (0, 0, 1920, 83); Dock 20
graceful quit             → process exited after layout.json was flushed
```

The local machine used Xcode 26.5 on macOS 26.7.1 with deployment target 13.0.
Pixel-level visual inspection requires Screen Recording permission, which was
unavailable in this environment; window levels, frames, visibility, build, and
tests were verified programmatically.
# Launchpad
