# Launchpad

A native macOS recreation of the classic Launchpad: an edge-to-edge, blurred app
launcher with paged grids, folders, live search, drag-and-drop arrangement, an
edit/jiggle mode, a global hot key, an optional hot corner, and a menu-bar
agent lifecycle.

The app is built with SwiftUI for the interface, AppKit for the window, event,
and hot-key plumbing, Core Image for the wallpaper blur, and an MVVM structure
with `async/await` services. There are no third-party dependencies.

- **Platform:** macOS 26.0 or newer
- **Language:** Swift 5.9+ toolchain (project `SWIFT_VERSION = 5.0`, using
  modern concurrency, actors, and the macOS 26 SwiftUI APIs)
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
│   │   ├── SettingsStore.swift        # UserDefaults JSON settings
│   │   └── SystemWallpaper.swift      # Real wallpaper from store/providers
│   ├── ViewModels/
│   │   └── LaunchpadViewModel.swift   # All overlay state and interactions
│   ├── Views/
│   │   ├── AppIconImage.swift         # Async icon view with fallback tile
│   │   ├── BackgroundView.swift       # Blurred-wallpaper surface + material fallback
│   │   ├── FolderPanelView.swift      # Folder panel, paging, drag-out
│   │   ├── InfoSheet.swift            # Native Get Info sheet
│   │   ├── ItemIconView.swift         # App/folder tile, jiggle, badge, menu
│   │   ├── LaunchpadRootView.swift    # Root layout, search, pages, drag layer
│   │   ├── LiquidGlass.swift          # System Liquid Glass helpers
│   │   ├── PageDots.swift             # Bare clickable page indicators
│   │   ├── PageView.swift             # One paged grid with reorder preview
│   │   ├── PreferencesView.swift      # SwiftUI Settings content
│   │   ├── SearchBar.swift            # Search pill with options menu
│   │   ├── ShortcutRecorder.swift     # AppKit key-chord recorder
│   │   └── WallpaperBackdrop.swift    # Cached Gaussian blur of the desktop image
│   ├── Window/
│   │   ├── LaunchpadWindow.swift      # Borderless, key-capable overlay
│   │   ├── LaunchpadWindowController.swift # Overlay + Dock backdrop + monitors
│   │   ├── DockReservation.swift      # Dock edge/thickness + viewport mapping
│   │   ├── DockBackgroundWindowController.swift # Blurred strip behind the Dock
│   │   ├── MenuBarPatchWindowController.swift   # Corner patch for a side Dock
│   │   ├── PreferencesWindowController.swift
│   │   ├── WindowLevels.swift         # Above the menu bar, below the Dock
│   │   └── WindowManager.swift        # Show/hide, mirrors, screen changes
├── LaunchpadTests/
│   ├── BackdropTests.swift            # 3 wallpaper pixel/cache checks
│   ├── CoreTests.swift                # 39 unit tests
│   ├── GridReorderTests.swift         # 14 reorder/folder-drop tests
│   ├── SystemWallpaperTests.swift     # 5 wallpaper-source tests
│   └── SmokeTests.swift               # 5 window-layout tests
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
| `LSMinimumSystemVersion` | `$(MACOSX_DEPLOYMENT_TARGET)` → `26.0` | Deployment target |
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

# Test suite (66 unit tests)
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad \
  -configuration Debug -derivedDataPath .build test \
  CODE_SIGNING_ALLOWED=NO

# Debug-only smoke test: shows the overlay, prints window diagnostics,
# asserts the overlay reserves the Dock with a below-Dock backdrop and
# that a real wallpaper source resolves, then exits.
.build/Build/Products/Debug/Launchpad.app/Contents/MacOS/Launchpad --smoke-test
```

The smoke test prints a line such as:

```text
SMOKE overlayWindows=1 displays=1 expectedWindows=1 pages=3 items=74 frame=(0.0, 82.0, 1920.0, 1118.0) expectedFrame=(0.0, 82.0, 1920.0, 1118.0) screen=(0.0, 0.0, 1920.0, 1200.0) level=26 frameStopsAtDock=true windowCountMatches=true dockWindows=1 patchWindows=0 dockStripIsPresent=true patchIsPresent=true belowDockLevel=19 dockIsBelowTheOverlay=true wallpaper=neptune:TahoeDark wallpaperIsResolved=true
```

The overlay frame stops at the Dock's edge (`screen.frame` minus the reserved
strip) while a background-only window one level below the Dock continues the
blurred wallpaper behind it. The wallpaper line shows the real source the
backdrop resolved (`neptune:TahoeDark` for the macOS 26 Tahoe default in dark
mode, `neptune:TahoeLight` in light mode); it must not be `none` on a normal
desktop.

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
  Double-click a folder tile to open it and edit its name. A folder page shows
  7 × 3 = 21 apps with the same icon and label size as the main grid. Drag apps
  out of an open folder to return them to the main grid. A folder with fewer
  than two apps dissolves.
- **Edit mode:** long-press an icon (0.5 s), hold Option, or choose a delete
  action from an item's context menu. In edit mode, deletable user apps show an
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
- [ ] **Reset Layout** from both the status menu and Preferences restores
      alphabetical order, dissolves all folders, resets the icon size to 81 pt,
      and leaves app files untouched.

### Window and background

- [ ] Overlay covers the screen from the menu bar down to the Dock's edge; the
      Finder/macOS menu bar and status items are not visible, while the Dock
      stays visible and clickable.
- [ ] The blurred wallpaper backdrop continues behind the Dock, so the strip
      around the Dock matches the rest of the overlay with no seam.
- [ ] The backdrop is the user's own wallpaper, blurred by about 50 pt and still
      vivid; a flat 22–25% black layer dims it. There is no grey frost, navy or
      blue wash, sheen, or highlight gradient.
- [ ] Change the desktop wallpaper, hide Launchpad, and show it again; the new
      wallpaper appears (the cached blur is rebuilt when its signature changes).
- [ ] Set the macOS 26 Tahoe default wallpaper (light and dark); the backdrop
      matches the wallpaper shown in System Settings, not the generic old aerial.
- [ ] Select a specific aerial whose video has downloaded; its frame is blurred.
      If the video is not downloaded, the backdrop falls back to the system
      material, still dimmed the same way.
- [ ] Move the Dock to the bottom, left, and right edge: the overlay reserves
      the correct edge, the strip behind the Dock stays blurred, and a side Dock
      gets the menu-bar corner patch.
- [ ] Move the pointer to the top edge: no menu titles appear and clicking there
      opens no macOS menu.
- [ ] Enable **Reduce Transparency** in System Settings → Accessibility →
      Display; the background becomes a solid dark gray fallback.
- [ ] With **Show on all displays** enabled, every display mirrors the UI, but
      only the cursor display accepts clicks/keys.
- [ ] Disconnect/reconnect a display while the overlay is open; the primary
      window relocates and mirrors refresh.
- [ ] With another app's window open, hiding Launchpad returns focus to that app;
      with no other window, the app hides itself.

### Grid and paging

- [ ] Default grid is 7 × 5 with 81 pt icons; Preferences allows 5–9 columns and
      4–6 rows.
- [ ] At 1440 × 900 with default settings all icons and single-line labels fit;
      icons shrink automatically at dense settings.
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
- [ ] The pill shows a magnifier, the placeholder “Search Applications”, and a
      circled “…” button that opens Preferences… and Reset Layout without
      breaking typing, focus, or Escape.
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
- [ ] A folder page shows 7 × 3 = 21 apps. Folder icons and labels match the
      main grid size; additional apps paginate and are reachable by swipe,
      scroll, or the panel page dots.
- [ ] Opening and closing the folder keeps every icon and label inside the
      rounded glass panel; the close spring settles without overshoot.
- [ ] Drag within an open folder to reorder with the reflow preview; swipe or
      scroll pages inside folders with more than 21 apps.
- [ ] Drag an app out of the folder panel; the panel closes as the cursor
      leaves and the icon continues onto the main grid. The drop snaps to the
      nearest grid cell, including drops over a margin or the search field.
- [ ] Removing the second-to-last app dissolves the folder: the survivor stays
      in the folder's former slot and the dragged app lands at the cursor.
      Removing the last app deletes the folder. Other pages are not repaginated
      by a drop.
- [ ] Right-click a folder → **Remove from Launchpad** dissolves it and releases
      its apps without deleting anything.
- [ ] Drag to the left/right 60 pt edge and hold 0.8 s; the grid flips pages,
      creating a temporary empty last page if necessary, and empty pages are
      removed on drop.

### Animations

- [ ] Show: the whole overlay cross-fades in over 0.18 s (0.14 s out) by
      animating each window's alpha, so the wallpaper and Liquid Glass surfaces
      are composited once instead of re-rendered every frame.
- [ ] Page changes use the 0.40 s / 0.86 spring.
- [ ] Search cross-fades (0.2 s) and page dots hide.
- [ ] Folder open scales from the folder icon center with a 0.35 s / 0.82
      spring and dims the grid behind it with a flat scrim. Close reverses in
      0.25 s with a critically damped spring, so the panel shrinks without
      overshooting its tile.
- [ ] Edit mode jiggles ±2° with a ±0.5 pt translation on the current page only;
      exiting eases back. Icons use a repeating layer animation rather than a
      60 fps timeline.
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
- [ ] Columns/rows, icon size (64 pt up to the largest size the current grid
      fits), label size (6–15), hot corner, global shortcut, **Launch at login**,
      and **Show on all displays** all persist across relaunch.
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

- **Wallpaper source:** `SystemWallpaper` resolves the wallpaper the system is
  actually showing. It uses `NSWorkspace.desktopImageURL(for:)` for ordinary
  static/user images, but that API returns the generic `DefaultDesktop.heic` for
  macOS 26 provider-backed wallpapers. In that case it reads the system
  wallpaper store (per-display choice first, then all displays), maps
  `com.apple.NeptuneOneExtension` to its bundled `TahoeLight.heic`/`TahoeDark.heic`
  by appearance, and extracts a frame from the downloaded aerial video when a
  specific aerial is selected. Linked files are used directly.
- **Wallpaper blur:** `WallpaperBackdrop` downscales the resolved image to at
  most 1280 px, aspect-fills it to a 640 pt working width, applies a Gaussian
  blur (`sigma` scaled from a ~50 pt target), and caches the result per display,
  screen size, and radius. The 1.1 saturation pass is baked into the cached
  bitmap; a flat 22–25% black overlay keeps it vivid without a grey frost. Baking
  avoids a full-screen SwiftUI colour filter on every window fade. `prepare(for:)`
  runs from the window controller and rebuilds the cache only when a cheap
  wallpaper signature changes, so wallpaper and appearance changes still appear
  on the next show. SwiftUI body evaluation only reads the cache; the ~1 s store
  read and HEIC decode never run during a page drag or other grid re-render.
- **Wallpaper fallback:** if the store or provider cannot resolve an image (for
  example a chosen aerial whose video has not downloaded), the backdrop uses
  `NSVisualEffectView` (`.fullScreenUI`, emphasized) with the same black dim
  instead of a blur. Reduce Transparency always wins and renders a solid dark
  gray fill.
- **Liquid Glass:** the folder panel, search pill, and folder-drop plate use the
  system material through SwiftUI's `glassEffect(_:in:)` (regular variant, with
  a scheme-aware tint for legibility), hosted in a single
  `GlassEffectContainer`. The app background deliberately does not use glass:
  the wallpaper blur needs a large radius and full saturation. Page dots are
  bare, with no pill behind them. The folder panel is clipped to its rounded
  shape before the glass effect and carries a subtle specular rim, so its
  contents stay inside the panel while it scales. It does not use a glass-morph
  transition; it scales and dims the grid instead, which avoids re-sampling a
  large glass surface on every animation frame.
- **Icon-size range:** `LayoutMetrics.iconSize` caps a request to the cell and
  label block, so the Preferences slider ends at `maximumIconSize` for the
  current grid instead of offering inert values above the cap. Changing columns,
  rows, or display clamps the stored value into the new range.
- **Window and Dock:** the Dock (level 20) and menu bar (level 24, status items
  25) live on different levels, so one window cannot be both above the menu bar
  and below the Dock. The main borderless overlay sits at `.statusBar + 1`
  (level 26) and its frame stops at the Dock's edge. A non-interactive strip one
  level below the Dock (`belowDock`, level 19) continues the blurred wallpaper
  behind it, so the Dock stays visible and clickable. A side Dock also gets a
  menu-bar-height corner patch. The wallpaper is rendered full-screen in each
  window and offset by its viewport, so the pieces line up without a seam.
  `NSApp.presentationOptions` is not modified.
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
- **Show/hide compositing:** the overlay uses a window-level alpha cross-fade
  instead of a SwiftUI opacity animation over the full screen. A SwiftUI opacity
  pass would force the wallpaper and every Liquid Glass surface to be re-sampled
  each frame, which is expensive on integrated GPUs. The window alpha lets the
  compositor cross-fade the finished frame for free.
- **Search results:** results reuse the same paged grid; there is no separate
  search-specific stagger timer or transition.
- **Launch at login:** uses `SMAppService.mainApp`; registration may fail for
  ad-hoc builds outside `/Applications`. The toggle reflects the actual system
  status after the attempt.
- **Tests:** 66 unit tests cover search ranking, pagination math, reorder
  preview/commit parity, drag-state isolation, folder creation/merge/dissolve
  rules, app-removal return semantics, normalization, JSON persistence,
  page-snap geometry, layout ratios, window coverage, Dock-strip levels and
  viewport mapping, wallpaper-store/provider resolution, backdrop
  saturation/brightness, and the cache-only backdrop lookup. The
  `--smoke-test` debug hook also asserts that the overlay stops at the Dock and
  that the below-Dock backdrop windows are present and correctly layered.

---

## Verification performed

```text
xcodebuild ... build      → BUILD SUCCEEDED
xcodebuild ... test       → TEST SUCCEEDED, 66 tests, 0 failures
Launchpad --smoke-test    → SMOKE overlayWindows=1 displays=1 expectedWindows=1
                            pages=3 items=74
                            frame=(0.0, 82.0, 1920.0, 1118.0)
                            expectedFrame=(0.0, 82.0, 1920.0, 1118.0)
                            screen=(0.0, 0.0, 1920.0, 1200.0)
                            level=26 frameStopsAtDock=true
                            dockWindows=1 patchWindows=0 belowDockLevel=19
                            dockStripIsPresent=true
                            dockIsBelowTheOverlay=true
                            wallpaper=neptune:TahoeDark
                            wallpaperIsResolved=true
layout ratios             → 1440×900 and 1920×1200: cell width 0.1323 W,
                            cell height 0.1636 H, icon 0.0563 W
backdrop pixels           → output saturation 1.031× input,
                            brightness 0.801× input, hue delta 0.000
backdrop hot path         → unprepared lookup returns nil (no resolve),
                            prepared lookup is cache-only, repeated prepare
                            reuses the same rendered image,
                            1000 cache lookups in 0.008 s
wallpaper source          → neptune:TahoeDark, 1280×1280
                            (public API returned DefaultDesktop.heic)
window checks             → frame stops at the Dock edge, level 26,
                            Dock strip at level 19, viewport mapping exact
graceful quit             → process exited after layout.json was flushed
```

The local machine used Xcode 26.5 on macOS 26.7.1 with deployment target 26.0.
Screen Recording permission is unavailable in this environment, so the visual
match was not checked by eye. Window frames, levels, layout ratios, rendered
backdrop pixels, build, and tests were verified programmatically.
