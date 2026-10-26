# ROLE

You are a senior macOS engineer (Swift, SwiftUI, AppKit, Core Animation). Build a complete, compilable macOS app that replicates the behavior and look of Apple's classic Launchpad. Deliver production-quality code, not pseudocode.

# TECH STACK

- Language: Swift 5.9+

- Min deployment target: macOS 13 Ventura (use `@available` for anything newer)

- UI: SwiftUI for views, AppKit for the window, blur, and event handling (NSWindow, NSVisualEffectView, NSHostingView, NSEvent)

- Architecture: MVVM with `ObservableObject` view models, async/await, no third-party dependencies

- The app runs as a menu-bar agent (`LSUIElement = YES`) with a status-bar icon (menu: "Show Launchpad", "Preferences…", "Quit")

- Xcode project, App Sandbox OFF (needed to scan /Applications), Hardened Runtime ON

# 1. APP DISCOVERY &amp; DATA MODEL

- Scan these folders recursively (depth ≤ 2) for `.app` bundles: `/Applications`, `/System/Applications`, `/System/Applications/Utilities`, `/Applications/Utilities`, `~/Applications`

- Use `NSMetadataQuery` (kMDItemContentType == "com.apple.application-bundle") for live updates: new/removed apps must appear/disappear without restart

- Read the display name from `CFBundleDisplayName`, falling back to `CFBundleName`, then the file name. Skip bundles with `LSUIElement`/`LSBackgroundOnly` = true

- Icons: `NSWorkspace.shared.icon(forFile:)`, rendered at 2x, cached in an `NSCache` (key = bundle path), loaded lazily and off the main thread

- Models:

  - `AppItem` (id = bundle identifier, name, url, isSystemApp)

  - `FolderItem` (id UUID, name, `[AppItem]`)

  - `LaunchpadEntry` enum { app(AppItem), folder(FolderItem) }

  - `PageLayout` = [[LaunchpadEntry]]

- Default order: alphabetical (localized, case-insensitive). After the user rearranges, persist the custom layout as JSON in `~/Library/Application Support/<AppName>/layout.json` (debounced save, 0.5 s). New apps are appended at the end of the last page; removed apps are dropped from the layout

- Menu: "Reset Layout" restores alphabetical order and removes all folders

# 2. WINDOW &amp; BACKGROUND

- A borderless `NSWindow` (styleMask `.borderless`, `isOpaque = false`, `backgroundColor = .clear`) covering the screen under the mouse except the strip occupied by the Dock. `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`. The Dock edge and thickness are derived from `NSScreen.visibleFrame`; for an auto-hidden Dock (where `visibleFrame` no longer reserves it) the app reads the `com.apple.dock` orientation and tile size on the primary display and reserves a conservative strip.

- Because the Dock (level 20) and the menu bar (level 24, status items 25) sit at different system levels, no single window can be both above the menu bar and below the Dock. The main overlay is therefore layered above the status bar (`.statusBar + 1`, level 26) so the Finder/macOS menu bar cannot show through or be operated, while its frame stops at the Dock edge.

- A second non-interactive borderless window fills the Dock strip one level below the Dock (`CGWindowLevelForKey(kCGDockWindowLevelKey) - 1`, level 19). It renders the same blur and tint backdrop and ignores mouse events, so the area behind the Dock looks continuous while the Dock itself stays visible and clickable. It overlaps the main window by 1 pt to avoid a hairline seam.

- With a left or right Dock, the main window starts at the Dock edge and leaves the menu-bar-height corner above the Dock exposed. A small companion window at the main window's level covers only that corner, reuses the same backdrop, and consumes clicks. A bottom Dock needs no patch.

- The app does not modify `NSApp.presentationOptions`. AppKit rejects `.hideMenuBar` unless `.hideDock` is also set, which would hide the Dock.

- Background layers (back to front):

  1. `NSVisualEffectView` (material `.fullScreenUI` or `.hudWindow`, blendingMode `.behindWindow`, state `.active`) for the blurred desktop effect

  2. A black overlay at 25% opacity (dark mode) / 10% (light mode) for contrast

  3. The content layer (search bar, grid, page dots)

- Overall transparency: the wallpaper must remain clearly recognizable but heavily blurred (equivalent of a 40–60 pt Gaussian blur)

- Keep the Dock visible and usable while the overlay is open. The Dock strip must show the same blurred backdrop as the rest of the screen, without adding a separate visible bar or strip at the top of the grid

- Multi-display: show on the screen with the mouse cursor; recompute the layout on screen/resolution change

- Dark/Light mode: follow the system appearance. Text is always white with a soft shadow

- Window closes and the app deactivates when the user clicks an app, presses Esc, or clicks any empty area

# 3. LAYOUT (UI SPECIFICATION)

Reference size: 1440×900 pt screen. All values must be computed proportionally (scale factor = screenWidth / 1440, clamped to 0.8–1.6) so they work on all displays.

**Grid**

- Default: 7 columns × 5 rows = 35 items per page (configurable in Preferences: 5–9 columns, 4–6 rows)

- Grid horizontal margin: 8% of screen width on each side

- Grid top margin: 110 pt (below search field), bottom margin: 90 pt (above page dots)

- Cell size = available width / columns × available height / rows; items are centered within their cell

- Minimum gap between icons: 40 pt horizontal, 32 pt vertical (these emerge from the cell size, but never go below the minimum)

**Icon**

- Icon size: 96 × 96 pt at reference size (scaled by the factor above)

- Icons keep their native macOS rounded-square shape; add a shadow: black 35% opacity, radius 6, y-offset 3

- Hover (mouse): scale to 1.05 over 0.15 s, no highlight box

- Pressed state: scale 0.92, brightness −15%, 0.1 s

**Label**

- Font: SF Pro Text (`.system`), 13 pt, weight `.medium`, white, centered, max 2 lines, `lineBreakMode = .byTruncatingTail`

- Distance from icon bottom: 10 pt

- Shadow: black 60% opacity, radius 2, y-offset 1 (for legibility on bright wallpapers)

- Max label width = cell width − 8 pt

**Search field** (top center)

- Width 280 pt, height 30 pt, corner radius 8 pt, 36 pt from the top of the screen

- Background: white 15% opacity with a 0.5 pt white 25% border, text 14 pt white, placeholder "Search" in white 55% with a magnifying-glass SF Symbol (`magnifyingglass`, 13 pt) on the left

- Becomes slightly wider (320 pt) with a 0.2 s animation when focused; has a clear "x" button when text is present

**Page indicator dots** (bottom center)

- Dot diameter 8 pt, spacing 14 pt, 40 pt above the screen bottom

- Active dot: white 100%; inactive: white 35%

- Dots are clickable (go to that page with the page-change animation). Hidden when there is only one page

**Folder icon (in grid)**

- Same size as an app icon (96 pt) with a rounded-rect background (corner radius 22 pt), white 22% opacity, plus a blur material

- Shows a 3×3 mini-preview of the first 9 apps inside (each \~24 pt), 8 pt inner padding

- Folder name displayed as a label, same style as app labels

**Opened folder panel**

- Centered on the screen, 560 × 460 pt (scaled), corner radius 32 pt, material `.hudWindow`, white 18% overlay, shadow radius 30 / opacity 40%

- Folder grid inside: 4 columns × 3 rows per page, icon size 80 pt, labels 12 pt; own page dots (7 pt) when more than 12 apps

- Folder title: centered above the grid, 24 pt, weight `.regular`, white; double-click or click to edit inline (TextField, blue-less, white caret), Return confirms. Default name "New Folder"

# 4. ANIMATIONS

Honor `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (replace all animations with 0.15 s fades). Target 60 fps minimum, 120 fps on ProMotion.

- **Show:** the background fades in (0.25 s, easeOut); icons scale from 1.12 → 1.0 and fade from 0 → 1 (0.30 s, easeOut) with a subtle stagger (each row delayed by 0.02 s, max 0.1 s)

- **Hide:** icons scale 1.0 → 1.08 and fade to 0 (0.22 s, easeIn), then the background fades out (0.15 s); only then `orderOut`

- **Page change:** horizontal slide with a spring (response 0.40, dampingFraction 0.86). During a drag/scroll the pages follow the finger 1:1 with a rubber-band effect at the first/last page (resistance factor 0.35). Commit to the next page if drag distance &gt; 25% of the page width OR velocity &gt; 500 pt/s

- **Search enter:** the grid cross-fades (0.2 s) into a single-page list of results with a stagger; page dots hide. **Search exit:** the reverse

- **Folder open:** the folder panel scales from the tapped folder icon's frame (anchor = icon center) to its final size and position using a spring (response 0.35, damping 0.82), while the rest of the grid blurs (radius 12) and dims to 55% opacity. **Close:** the reverse, 0.25 s

- **Jiggle (edit mode):** every icon rotates ±2° (random starting phase, 0.13 s, autoreverses, repeats forever) with a ±0.5 pt vertical translation. Stops with a 0.15 s ease back to 0°

- **Drag &amp; drop:** the picked-up icon scales to 1.12 with a larger shadow (radius 14), follows the cursor with no lag; other icons reflow to make room with a spring (response 0.30, damping 0.8)

- **Folder creation:** when an icon hovers over another icon (center-distance &lt; 40% of icon size) for 0.6 s, the target icon pulses (scale 1.15) and a folder background fades in behind it; dropping merges both into a new folder with a 0.3 s spring and auto-opens it with the name field focused

- **Remove (delete badge):** the icon shrinks to 0 and fades out in 0.2 s, and neighbors reflow with a spring

# 5. GESTURES &amp; INPUT

**Trackpad / mouse**

- Two-finger horizontal scroll → page navigation (use `scrollWheel` events, `hasPreciseScrollingDeltas`, momentum phase handling, accumulate deltas and apply the commit thresholds from Section 4)

- Mouse wheel (non-precise) → one page per notch with a 0.4 s cooldown

- Click-drag on empty space → swipe pages

- Pinch (magnify gesture): pinch-in at the Launchpad window = nothing; in the search results nothing. (Note: the system 4-finger pinch/spread cannot be intercepted by third-party apps — provide the alternatives below)

- Click on a blank area → close (or close the open folder first)

- Long-press (0.5 s) on any icon, or holding the Option (⌥) key → enter edit mode (jiggle). Click blank area / press Esc / press Return → exit edit mode

- Right-click on an icon → context menu: "Open", "Show in Finder", "Remove from Launchpad" (folder only), "Get Info"

**Activation**

- Global hotkey (default F4, configurable in Preferences) via Carbon `RegisterEventHotKey` toggling the window

- Optional hot corner (bottom-right default) detected through a global `NSEvent` mouse-moved monitor with a 0.3 s dwell time

- Status-bar menu item

- Optional "Launch at login" using `SMAppService.mainApp`

**Keyboard**

- Typing any character anywhere → focus the search field and start filtering immediately

- Arrow keys → move the focus ring between icons (2 pt white 80% rounded outline, radius 24); crossing the page edge moves to the adjacent page

- Return → launch focused item (open folder if it is a folder)

- Esc → in order: exit edit mode → close folder → clear search → close Launchpad

- ⌘1…⌘9 → jump to page N; ⌘, → Preferences; ⌘Q → quit

- Tab / Shift-Tab → next/previous page

# 6. SEARCH BEHAVIOR

- Live filtering on each keystroke (debounce 80 ms), case- and diacritic-insensitive, matches name prefix first, then word prefix, then substring, then fuzzy (Levenshtein ≤ 1 for queries ≥ 4 chars)

- Searches inside folders as well (results are flat, folder membership ignored)

- Results are shown on a single page in the same grid layout; "No Results" centered label (22 pt, white 60%) when empty

- Return launches the first result; arrow keys navigate

# 7. FOLDER LOGIC

- Create by dropping an app on another app (see animation spec). A folder with 1 app left is dissolved automatically; an empty folder is deleted

- Drag an app out of an opened folder: when the cursor leaves the folder panel bounds, the folder closes and the icon continues to be dragged on the main grid

- Drag within a folder to reorder; paging inside folders supports the same swipe gestures

- Folder names are persisted. Max 100 apps per folder

- Dragging an icon to the left/right 60 pt screen edge for 0.8 s auto-flips to the previous/next page (and creates a new empty last page if needed; empty pages are removed on drop)

# 8. EDIT MODE DETAILS

- A small circular "x" delete badge (22 pt, white 85% fill with dark "x", top-left of icon, offset −6/−6) appears ONLY for deletable items: user-installed apps outside /System (clicking moves the app to the Trash via `NSWorkspace.recycle` after a confirmation dialog). System apps never show a badge

- Folders show no badge; dragging all apps out deletes them

# 9. PREFERENCES WINDOW (SwiftUI Settings scene)

Grid columns/rows, icon size slider (64–128 pt), label font size (11–15 pt), global shortcut recorder, hot corner picker, blur intensity slider, "Reset Layout", "Launch at login", "Show on all displays".

# 10. PERFORMANCE &amp; QUALITY REQUIREMENTS

- Use `LazyHStack`/pagination so only the current page ±1 is rendered; use `.drawingGroup()` carefully for the jiggle layers

- Cold show time &lt; 150 ms (keep the window pre-created and hidden, refresh data in the background)

- Memory &lt; 200 MB with 300 apps

- No main-thread I/O; use `Task`/actors for scanning and icon loading

- Full VoiceOver support (labels = app names, hints, rotor for pages), full keyboard navigation, `Reduce Transparency` fallback to a solid dark gray 85% background

- Localized strings via `String(localized:)`, English + French at minimum

- Unit tests for: search ranking, layout pagination math, folder merge/dissolve rules, JSON persistence

# 11. OUTPUT FORMAT

Provide, in this order:

1. Project structure (folders/files tree)

2. `Info.plist` keys and entitlements

3. Complete source code, file by file, each in its own code block with the file path as a heading (Models, Services/AppScanner, Services/LayoutStore, ViewModels, Views/{LaunchpadView, PageView, IconView, FolderView, SearchBar, PageDots}, Window/LaunchpadWindowController, Input/HotKeyManager, Preferences)

4. A "Design Constants" Swift file (`Metrics.swift`) centralizing every number above (sizes, spacing, fonts, durations, spring values) so they can be tweaked in one place

5. Build/run instructions and a manual QA checklist covering every behavior in sections 4–8

6. A short list of known limitations (e.g., system 4-finger pinch cannot be hooked)

Write clean, commented, idiomatic Swift. Do not skip files or use "// TODO" placeholders. If a feature needs a workaround on a given macOS version, implement it and explain it in a comment.

# 12. IMPLEMENTATION CLARIFICATIONS (AGREED)

These clarifications resolve contradictions and platform limitations in the original brief. They are part of the requirements.

- **Product identity:** product name `Launchpad`; bundle identifier `com.soufiane.launchpad`; data directory `~/Library/Application Support/Launchpad/`.
- **Grid minimum gaps:** the 40 pt horizontal / 32 pt vertical minimums are measured between icon frames, excluding labels. At 1440×900 with 7×5 and 96 pt icons, the label block nearly fills the row. The effective icon size must shrink automatically when the requested icon size or grid density cannot satisfy the minimums and fit the labels.
- **Click precedence:** when edit mode is active, a blank click exits edit mode; another blank click closes Launchpad. Return exits edit mode before it can launch an item.
- **Search overflow:** results use the same grid and paginate internally when they exceed one page capacity; page dots remain hidden while searching.
- **Paging snap:** a trackpad swipe or background drag previews at most one page width. The pages follow the gesture 1:1 within that bound, rubber-band at the first/last page, and spring to the adjacent page (or back) when the gesture ends. Inertial momentum events after the fingers lift are ignored so the page cannot drift past its neighbour. Folder paging uses the folder panel width for the same bounds and commit distance. The live offset is held in a dedicated observable (`PageDragState`) so updating it only invalidates the offset modifier, not the icon grids on the visible pages. A committed turn slides the existing pages for 0.30 s and swaps the page index only after the slide, which keeps icon bodies out of the animation entirely.
- **Folder removal:** "Remove from Launchpad" dissolves the folder and releases its apps back onto the grid. It never deletes app files.
- **Get Info:** show a native SwiftUI/AppKit information sheet instead of using Finder automation or AppleScript.
- **Blur intensity:** use public `NSVisualEffectView` materials plus tint/dimming. A continuous 40–60 pt Gaussian radius is not publicly exposed by AppKit; document this limitation.
- **App discovery source of truth:** `FileManager` performs the authoritative scan; `NSMetadataQuery` is the live change signal and triggers debounced rescans. This prevents Spotlight indexing gaps, especially under `/System`.
- **Multi-display:** "Show on all displays" mirrors the same UI on each display. Only the display under the cursor is interactive; cross-display dragging is not supported.
- **App identity:** `AppItem.id` uses the bundle identifier when available and a canonical-path fallback otherwise. The application excludes itself from discovery.
- **Folder title editing:** a single click opens a folder; a double-click edits its title.
- **Reset Layout:** available from both the status-bar menu and Preferences.
- **Delivery:** the implementation is a buildable Xcode project in this workspace. `README.md` contains the project tree, Info.plist/entitlement notes, build/run instructions, manual QA checklist, and known limitations. The source files themselves are the complete source-code deliverable.