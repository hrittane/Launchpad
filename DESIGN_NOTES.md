# Launchpad — DESIGN_NOTES

Analysis of `./screenshots/` (72 frames, 1107 × 720 px, `ezgif-frame-001.png` … `072.png`).
The frames are **excerpts from a promotional video with scene cuts**, not one continuous 60 fps take:
identical-looking shots differ in layout (2 vs 3 pages, different app positions), so they are best
read as "shots" of one reference replica app running on macOS 26 (Tahoe) with the default blue
"arch" wallpaper, an active system Dock and a hidden menu bar.

All measurements below are in **reference-frame pixels (1107 × 720)** and are converted to
proportions of screen width (W) / height (H). "measured" = pixel-scanned with
`tools/measure.swift`; "estimated" = read from magnified crops (`tools/overlay.swift`).

---

## 1. Frame table

| File | State shown | Notable details |
|---|---|---|
| 001 | Desktop (Finder active) | Tahoe blue-arch wallpaper, menu bar, glass Dock with classic Launchpad icon. Baseline for wallpaper/blur comparison. |
| 002 | Desktop | Same, cursor moved; no Launchpad. |
| 003 | **Main grid, page 1**, idle | 7×5 grid, search pill top-centre, 2 page dots, Dock visible, menu bar hidden. Wallpaper heavily blurred + dimmed vs 001. |
| 004 | Zoomed grid (5 visible cols), **folder drag** in progress | Tools folder lifted (scale ≈1.25, shadow) over Dia; 3 page dots; hover/lift. |
| 005–008 | Same scene as 004 | Drag continues; only a few % of pixels differ (folder position). 008 settles. |
| 009 | Zoomed grid, page 1 | Search pill floating over row 1; app grid scrolled up; no Dock in frame. |
| 010 | Zoomed grid | Search pill visible; cursor over grid. |
| 011 | Zoomed grid | Search pill with the clear “×” visible (text field focused but empty). |
| 012 | Zoomed grid, page 1 | Search pill scaled larger (≈1.5×), overlapping System Settings icon; page-2/3 content. |
| 013 | Zoomed grid | Search pill overlaps System Settings; icon labels visibly enlarged. |
| 014 | Zoomed grid, page 1 | 5 cols × 5 rows, icons ≈90 px; 2 dots at bottom-centre; Dock visible. No search field (above crop). |
| 015 | Zoomed grid | Similar, cursor on grid. |
| 016 | Zoomed grid, **page indicator hover** | Page dots sit inside a small **glass capsule** (≈53 × 32 px) under the cursor; 2 dots. Dock visible. |
| 017 | Zoomed grid, late page (Podcasts/Games/Chess/…) | Single page dot capsule; large blurred wallpaper band. |
| 018 | Zoomed grid, page 1 with **folder “Untitled”** | Folder icon = translucent glass tile with 2 mini app icons; Keynote has hover glass plate; 3 dots. |
| 019 | **Drag folder onto app** | “Untitled” folder dragged over Keynote; Keynote hover plate; 3 dots. |
| 020 | Drag reorder | “Untitled” folder dropped (Keynote gone), Shortcuts lifted from row 4 toward row 3; 3 dots. |
| 021 | Main grid, page 1 (unzoomed) | Same as 003; cursor absent; 2 dots only. Used for measurements. |
| 022 | **Folder “Tools” open** | Glass panel 957×328 px, title above, 7×3 inner grid, backdrop dimmed, Dock visible. |
| 023 | Folder “Tools” open | Same, hover row change. |
| 024 | Main grid, page 1 | Identical layout to 021; 2 dots. |
| 025 | Zoomed grid, search pill + “…” hovered | Search chip’s right “…” button highlighted with a white circle. |
| 026 | **Search “…” popover** opened | Glass menu under search pill: Settings, Sort By ▸, Browsing Style, Check for Update, Quit. |
| 027 | Popover, **Sort By** submenu highlighted | “Custom” checked; Name / Date Added / Date Last Opened. |
| 028 | Popover, “Browsing Style” | Paged checked, Scroll option. |
| 029 | Popover + Settings… hover | Same menu, different hover. |
| 030 | Main grid, page 1 | No settings; 7×5; 2 dots. |
| 031 | **Main grid re-sorted alphabetically** | Apps App Store Apps Automator Books … Passwords; 2 dots; demonstrates Sort By = Name. |
| 032 | **Settings — General** (tall window) | Launch group (Start at Login, Hotkey ⌘2, System F4 Key, Trackpad pinch, Hot Corner), Appearance (Show Menu Bar Icon, App Icon choices). Red-only close button. |
| 033–035 | Settings — General | Toggle/segmented animations. |
| 036 | Settings — General | Same, slightly different position/scale. |
| 037–038 | Settings — General | Same, cursor/toggle changes. |
| 039 | Zoomed grid page 1, **folder “Untitled”** with 4 apps | Cursor over folder; 3 dots; Dock partly cut. |
| 040 | **Folder context menu** | Open / Rename / Ungroup, glass menu, SF-symbol icons. |
| 041–043 | **App context menu** (Untitled app) | Open / Rename / Uninstall (red) — earlier iteration of the menu. |
| 044 | Zoomed grid page 1 | Folder “Untitled” dissolved → Pages, Numbers, Keynote in row 3; 3 dots. |
| 045 | **Settings — Interface** (7×5) | Sort By Custom, Browsing Style Paged/Scroll, Icon Grid 7×5, Fill Empty Slots + Reorganize, Hide Dock, Background Type, Blur Wallpaper. |
| 046 | Settings — Interface, **8×5** grid | 8 columns visible behind (icon size shrinks). |
| 047–048 | Settings — Interface, **9×5** grid | 9 columns visible behind. |
| 049 | Settings — Interface, 7×5 | Same as 045, cursor on slider. |
| 050–052 | **App context menu** (Keynote) | Open, Show in Finder, Add App to Dock, Move to ▸, Hide, Rename; glass. |
| 053–055 | Keynote menu with **Move to ▸** submenu open | “Move to ▸” hovered, submenu not visible. |
| 056 | **Drag reorder in progress** | Music/Find My moved to right column; icons reflow; zoomed. |
| 057 | Zoomed grid, drag settling | Page 3 content. |
| 058 | Settings — Interface, **Background: Glass Effect** | Frosted milky full-screen overlay, “Glass Material” slider, wallpaper faintly visible. |
| 059 | Settings — Interface | Glass Effect + slider, panel moves. |
| 060 | Settings — Interface | Glass Effect at higher material value (much lighter background). |
| 061 | Zoomed grid, **edit mode starting** | No badges yet; Dock partly cut; 2 dots. |
| 062 | **Edit mode** | White “×” glass badges on Numbers, Pages, Keynote, Dia only (deletable apps); icons jiggle. |
| 063–064 | Edit mode | Badges persist; grid settles. |
| 065 | **Uninstall confirmation**, edit mode | White dialog 420×290: app icon, “Dia — Zero KB”, Cancel / Move to Trash; Safari + Dia badges. |
| 066 | **Uninstall detail list** | Application Files / Support / Caches / Preferences with sizes, Move to Trash. |
| 067 | Zoomed grid, hover highlight | Keynote hovered: glass plate behind icon, icon lifted; 3 dots. |
| 068–072 | **Dock hover on Launchpad icon** | System Dock magnification, tooltip “Launchpad” (black pill), classic white Launchpad icon with 3×3 coloured tiles. |

---

## 2. Measurements

### 2.1 Grid (frames 003 / 021 / 024 / 030 — measured)

| Metric | Reference px | Proportion | Notes |
|---|---|---|---|
| Columns × rows | 7 × 5 (35 slots) | — | default; Settings offers 7/8/9 columns × 5 rows |
| Column centres | 137.5 … 967.5 | first 12.42 % W, last 87.4 % W | pitch **138.33 px = 12.49 % W** |
| Row centres | 123.5, 231, 338.5, 446, 553.5 | 17.15 % … 76.9 % H | pitch **107.5 px = 14.93 % H** |
| Icon size | **59 × 59** | 5.33 % W (8.19 % H) | macOS 26 squircle, real app icons, no glass wrap |
| Label | 13 px SF Pro, medium | 1.17 % W | cap height 9–10 px, white ~92 %, soft 1 px shadow |
| Icon → label gap | 17 px (label centre +46 from icon centre) | 2.4 % H | single line, tail truncation |
| Grid block | icons y 94 … 574 | top 13.1 % H | block is centred (equal 108/110 px side margins) |
| Horizontal gap | 79 px | 7.1 % W | pitch − icon |
| Vertical gap | 48 px | 6.7 % H | pitch − icon − label |

> **Verified on device (milestone a).** `NSWorkspace` icons are full 1024 px canvases whose artwork
> occupies ≈ 824 px, so drawing one at 59 px yields a visible 48 px squircle. The drawn image is
> therefore scaled by **1.243** and the visible icon matches the reference to the pixel
> (60 px at 1107 W, column centres identical). Labels measured 48 × 10 px in the reference;
> 17 pt at 1920 W reproduces that exactly at equal scale.

The grid follows the **system icon style**. `NSWorkspace.icon(forFile:)` returns the current
Normal / Clear / Dark / Tinted variant, and `IconProvider` keys its cache by the icon style,
`AppleInterfaceStyle`, and — for Tinted — the tint color. When any of them changes, the cache is
dropped and the visible tiles reload; a one-second poll covers the change while Launchpad is
open, and every presentation refreshes first. In-flight loads from the previous style are never
written back into the new cache.

At 8×5 (frame 046) and 9×5 (frame 048) the same total width/height is divided, so icons and labels
shrink (≈51 px icons at 8 cols, ≈46 px at 9 cols) and gaps compress. Icon size is therefore
**derived from column count**, not fixed.

Labels are **not** in a glass pill; no per-icon background in idle state.

### 2.2 Search pill (frames 003 / 021 — measured)

| Metric | Value | Proportion |
|---|---|---|
| Size | **178 × 34 px** | 16.1 % W × 4.72 % H |
| Centre | x = 553.5 (screen centre), y = 55 | top edge 38 px = 5.28 % H |
| Shape | capsule, radius 17 | — |
| Fill | transparent, white ≈ 3 % | wallpaper clearly visible |
| Border | 1 px white ≈ 20 %, slightly brighter on top | glass “clear” look |
| Magnifier | 14 px SF Symbol, inset 17 px, white 70 % | 1.26 % W |
| Placeholder | “Search Applications”, 11–12 px, white 55 % | starts x + 33 |
| Right button | 20 px circle, 1 px white 30 % border, “…” 3 dots | inset 12 px from right |
| Focus (frame 011) | clear “×” appears, pill expands slightly | frame 025 “…” hovered gets a white filled circle |

The pill floats over the grid (frames 009/012/013 show it overlapping row 1 when content is zoomed),
i.e. it is an overlay, not a grid row.

> **Re-measured (milestone a).** Tight bounding box of the capsule stroke is **181 × 30 px** with its top
> edge at 37 px (5.14 % H). Implemented as 16.35 % W × 4.25 % H, top 5.14 % H; a window-server capture
> reproduces 181 × 29 px at 1107 W with the same left/right edges (463…643 vs 463…643).

The pill is the one surface excluded from the panel's open zoom/fade (`scaleEffect` 1.04 → 1 plus
opacity). Its Liquid Glass layer and the native field editor do not inherit an animated scale/opacity
cleanly and flashed for a frame while the window alpha was still rising. The pill now fades with the
window alone. The close mirrors the open on the grid — it scales back out to 1.04 while the window
fades — and the pill still only fades. Closing the panel also resigns first responder, so a shared
field editor cannot survive into the next presentation and repaint a stale selection over the field.

### 2.3 Page indicator (frames 003 / 021 / 016)

| Metric | Value |
|---|---|
| Dot diameter | **6 px** (1.5 px at 4× crop) |
| Pitch | **18 px** centre-to-centre |
| Position | y centre 640.5 = 89.0 % H, horizontally centred |
| Active | white 100 % |
| Inactive | white ≈ 30 % |
| At rest | **no capsule** — dots sit directly on the wallpaper |
| Hover (frame 016) | small glass capsule ≈ 53 × 32 px (r ≈ 12) appears around the dots; dots 7–8 px. Cursor over it. |

### 2.4 Folder icon and open panel

Folder icon (frames 018/039/004): same 59 px slot; translucent glass squircle (light blue tint,
1 px white ~25 % border, soft shadow) containing a **3 × 3 mini grid of real app icons**
(2 × 2 shown for 4 apps, 2 icons for 2 apps); mini icons ≈ 14 px with 2 px gaps, inset 8 px.
No classic dark “folder” shape. While dragged: scale ≈ 1.25 + stronger shadow.

Open folder (frames 022/023 — measured):

| Metric | Reference px | Proportion |
|---|---|---|
| Panel | **957 × 328** | 86.5 % W × 45.6 % H |
| Panel rect | x 75 … 1032, y 192 … 520 | top 26.7 % H |
| Corner radius | **30** | 3.13 % W |
| Fill | light glass: white ≈ 8–12 % + heavy blur | wallpaper tint visible inside |
| Border | 1 px white ≈ 30 %, brighter top rim | “regular” glass |
| Title | “Tools”, 15 px medium white, centred, y ≈ 161 | 31 px above panel |
| Inner grid | 7 × 3, icon **52 px**, col pitch 137.5, row pitch 110 | icon 4.7 % W |
| Inner labels | 12 px | single line |
| Padding | top 26 px, bottom 9 px, sides 57/75 px | — |
| Page dots | none for a single page (none observed) | — |
| Backdrop | wallpaper dims further (≈ +15–20 % black) + stronger blur | — |

### 2.5 Backdrop (frames 001 vs 003 — measured colours)

| Point | Desktop (001) | Launchpad (003) | Delta |
|---|---|---|---|
| 100,300 | #765ED3 | #5346B7 | ×0.71 luminance |
| 553,400 | #4C75BA | #315BA0 | ×0.75 |
| 900,600 | #7A88C0 | #54649E | ×0.73 |

→ **heavy blur + ≈ 25–30 % black dim + vignette**; no colour shift (blue stays blue).
The arch highlight of the wallpaper is completely diffused, so blur radius is large
(estimated 80–120 px at this resolution). Icons/labels are always treated as “dark mode”
(white labels, white dots) regardless of the system appearance.
“Glass Effect” background mode (frames 058–060) replaces this with a **milky frosted white
overlay (~35–45 % white) + adjustable material slider**; wallpaper still faintly visible.

### 2.6 Hover / press / drag (frames 018/019/067)

- Hover: rounded-square glass plate behind the icon, ≈ icon + 22 px at zoomed scale
  (≈ icon + 15 px at 1×), radius ≈ 18 px, fill white ≈ 8 %, 1 px white ≈ 20 % border;
  icon lifts (shadow grows), scale ≈ 1.03.
- Press: not captured; task default 0.94.
- Drag: lifted icon scale ≈ 1.2–1.25, drop shadow ≈ 0 12 24 rgba(0,0,0,.35); neighbours animate
  to make room (frame 056), folder-on-icon hover ≈ 0.5 s before merge (frames 019–020).
- No “wobble” or badge on the dragged icon.

### 2.7 Edit mode (frames 061–066)

- Jiggle: still frames only; icons rotate ±2–3°, staggered by column (estimated, classic Launchpad).
- Badge: **22 px** white translucent circle (not red), centred on the icon’s **top-left corner**
  (badge centre ≈ icon left + 3, icon top + 3), 1 px white border + soft shadow, dark grey “×”
  (≈ 10 px, 2 px stroke). Only apps considered removable show it (in 062: Numbers, Pages, Keynote,
  Dia; Calculator/Phone/Messages have none).
- **No “Done” button** anywhere in the frames; edit mode ends via Esc / background click /
  context-menu action.
- Delete flow: opaque white dialog (420 × 290, r 12, standard macOS alert look, **not glass**),
  app icon + name + size, grey Cancel and blue “Move to Trash”.

### 2.8 Overflow menu (“…” in search pill, frames 026–029)

- Glass popover ≈ 250 × 335 px, r 14, 1 px light border, drop shadow, anchored under the pill’s
  right button (x ≈ 480…730, y ≈ 70…405).
- Headers “Sort By” / “Browsing Style”: 11 px, grey, semibold, inset 12 px.
- Items 22 px tall, 13 px text, SF symbols 13 px on the left, checkmark for selected, chevrons for
  submenus; hover = accent-blue rounded (6 px) row with white text.
- Items: Settings ⌘, · Sort By (Custom / Name / Date Added / Date Last Opened ▸) · Browsing Style
  (Paged / Scroll) · Check for Update · Quit ⌘Q.

### 2.9 Settings window (frames 032/033, 045/046/048, 058–060)

- Floating panel, **two widths**: 448 px (General) / 300 px (Interface), r 20, white opaque content
  (≈ #F7F7F7) with 1 px light border and large soft shadow. **Red-only traffic light** (close);
  no title text, no yellow/green buttons.
- Tab strip: 6 tabs (General, Interface, Apps, Advanced, About) with SF symbols above 10 px labels;
  selected tab = white pill + accent-blue icon/text; unselected grey.
- Groups: header 11–12 px semibold grey; rows 32 px, white group r 10, separators #E8E8E8,
  labels 13 px; toggles standard 26 × 15; segmented Paged/Scroll; steppers for grid rows/cols;
  explanations 10 px grey wrapping two lines.
- Settings content observed: Start at Login; Hotkey ⌘2 (editable, clear ×); System F4 Key (on);
  Trackpad “Pinch with 4 or 5 fingers”; Hot Corner “Top Left”; Show Menu Bar Icon (on);
  App Icon (4 choices); Sort By; Browsing Style; Icon Grid 7|8|9 × 5; Fill Empty Slots +
  Reorganize; Hide Dock; Background Type System Wallpaper / Glass Effect; Blur Wallpaper toggle;
  Glass Material slider.
- Settings window is **above** the Launchpad grid but below the search pill? No — in frame 045 the
  search pill is above the window (y 38…67), window starts at 116; in 032 the window overlaps the
  grid and the search pill is hidden behind it. So the settings panel is a separate floating panel
  that can overlap the pill depending on position.

---

## 3. Behaviours reconstructed from sequences

1. **Open**: Dock Launchpad icon (classic white 3×3 tiles) → full-screen grid; menu bar hidden,
   Dock remains visible above the grid. No frame of the transition itself.
2. **Idle layout**: 7×5 grid; search pill overlay top-centre; dots at 89 % H; Dock untouched.
3. **Hover**: glass plate behind the hovered icon, small lift; “…“ button gets a filled circle.
4. **Context menus**: native-style glass menus. App: Open / Show in Finder / Add App to Dock /
   Move to ▸ / Hide / Rename. Folder: Open / Rename / Ungroup. (An earlier build used
   Open / Rename / Uninstall with a red destructive item.)
5. **Drag reorder**: icon lifts, neighbours reflow live; dragging a folder onto an app creates a
   folder (or adds to it) after a dwell; folder icon preview updates immediately (2 → 4 minis).
6. **Folder open**: backdrop dims, centred glass panel with title above, 7×3 inner grid, no dots
   for one page.
7. **Edit mode**: triggered (not captured) → white × badges on deletable apps, jiggle, no Done
   button; “Uninstall” → confirmation dialog listing app support files → Move to Trash.
8. **Search**: focus reflows; pill gains an “×” clear button; “…” opens the overflow menu with
   sorting/browsing-style settings. No typed-results frame exists.
9. **Paging**: 2–3 dots; paged vs “Scroll” browsing style selectable; dots reveal a glass capsule
   on hover.
10. **Settings**: live reflow when the column count changes (7 → 8 → 9) and when the background
    type changes (blurred wallpaper ↔ frosted glass), with the grid staying interactive behind.
11. **Closing**: reverse of opening — the grid scales back out to its pre-open 1.04 and fades
    with the window (0.22 s).

All animation **durations are unknown** (frame extraction rate not provided; frame gaps are
irregular because the video is cut). Use task defaults: open 0.30 s spring, close 0.22 s,
page 0.35 s, folder morph 0.40 s, hover 0.12 s, badge pop 0.20 s.

---

## 4. Differences vs. classic Launchpad

- Icons are the modern **macOS 26 squircle** icons (the reference does not draw legacy folder
  shapes for folders — folders are glass tiles with mini icons).
- **Folders** are glass panels, not the grey blurred “folder” sheet; title sits *outside/above*
  the panel.
- **Search** field is a real glass capsule with an ellipsis menu, labelled “Search Applications”
  (classic Launchpad had no visible field until typing).
- **Page dots** are bare at rest but get a glass capsule on hover.
- **Backdrop** is a blurred + dimmed wallpaper; optional milky “Glass Effect” theme.
- **Context menus** offer “Add App to Dock”, “Hide”, “Rename”, “Ungroup”, “Uninstall”.
- **Settings** are a floating panel with a red-only close button and a custom tab strip.
- Dock stays visible; menu bar is hidden.
- Grid is user-configurable 7/8/9 columns and 5 rows.

---

## 5. Gaps (no frame) — defaults used

| Missing state | Default |
|---|---|
| Open/close transition | grid 1.04 → 1 + fade, backdrop blur 0 → full, 0.30 s alpha with a 0.42 s spring on the grid; close reverses the grid to 1.04 under the 0.22 s fade |
| Typed search + results | the pages are replaced by a single results grid; ranking = exact → prefix → word-prefix → substring → initials; Return launches the selected tile, arrows move a 2 pt white ring |
| Page swipe mid-animation | horizontal slide with rubber band + spring snap, 0.35 s |
| Folder morph animation | `glassEffectID` + `@Namespace` matched geometry from icon to panel, 0.40 s |
| Edit-mode jiggle | iOS-style: ±1.8–2.2° off-centre swing (pivot near the icon top), 0.24–0.30 s per cycle, sub-point bounce; period, pivot and phase vary per slot (see `IconWiggle`) |
| Edge-drag page flip | dwell **0.55 s** in the outer **5 %** bands, driven by a timer so a motionless pointer still flips; holding at the right edge of the last page creates one new page per drag (shipped; the strip itself does not follow the drag while editing) |
| “Done” control in edit mode | **not in reference and not implemented**: screenshots win, so edit mode ends via Esc, background click, or launching an app |
| Status-bar item/menu | Show Launchpad / Settings / Quit |
| About / Apps / Advanced settings tabs | not captured; About = version + credits; Apps = launch-at-login info + “Reset layout”; Advanced = reduce motion/transparency overrides |
| Reduce Transparency / Motion / Increase Contrast | follow system + manual overrides in Settings |
| Right-to-left | mirror grid, panel and pill (SwiftUI layout direction) |
| Light mode | reference is dark-on-blurred-wallpaper only; use same treatment with a slightly lighter tint in light mode |
| Multi-display | show on cursor’s screen |
| “Apps” icon on page 1 | reference has a special “Apps” item with a search bar glyph; treat as a normal folder-like tile or omit (we omit special pseudo-apps and show real apps) |

---

## 6. Liquid Glass API plan (to be validated against Xcode 26 SDK)

- `.glassEffect(.regular, in: .capsule)` / `.clear` + `.interactive()` for the search pill and
  hover plates; `.buttonStyle(.glass)` for small buttons.
- `GlassEffectContainer` wrapping the search pill + overflow button + dots capsule + badges so
  they can blend/morph with shared sampling.
- `glassEffectID(_:in:)` + `@Namespace` for the folder icon ↔ panel morph and search focus.
- `NSGlassEffectView` / `NSGlassEffectContainerView` for the full-screen glass backdrop if the
  SwiftUI path cannot blur the desktop wallpaper. **Superseded**: the backdrop is drawn from the
  desktop *picture* (see *Backdrop* in section 7), which is also what keeps other windows from
  showing through.
- `@Environment(\.accessibilityReduceTransparency/.accessibilityReduceMotion)` fallbacks to
  solid frost / fades.
- macOS 15 fallback: `.ultraThinMaterial`, `.background(.regularMaterial)`, `NSVisualEffectView`,
  behind `#available(macOS 26, *)`.

> Note on window level: the reference keeps the **Dock visible** and hides the **menu bar**.
> A window at `.mainMenu + 1`/`.screenSaver` would cover the Dock. Plan: floating borderless
> window below Dock level + `NSApp.presentationOptions = [.autoHideMenuBar]` while shown.

---

## 7. Milestone (a) — implementation findings

Validated on the build machine: macOS 26.7.2, Xcode 26.5, 1920 × 1200 @2× (Intel).

| Item | Result |
|---|---|
| Icon footprint | Reference 60 px wide at 1107 W (x 108…167); ours 60 px (x 109…168) at the same scale |
| Column centres | Identical (137.5 … 967.5 at 1107 W) |
| Label metrics | Reference 48 × 10 px; ours 44 × 9 px before, 48 × 10 px after the font change |
| Search pill | Reference 181 × 30 px at x 463…643 y 37…66; ours 181 × 29 px at x 463…643 y 36…64 |
| Page dots | 6 px dots, 18 px pitch at 1107 W → 10.4 pt / 21.7 pt at 1920 W |

### Build environment

- **Derived data must live outside the Desktop.** The project folder is File-Provider (iCloud)
  managed, which re-attaches `com.apple.fileprovider.fpfs#P` and `com.apple.FinderInfo` to the
  freshly built `.app`; `codesign` then fails with *“resource fork, Finder information, or similar
  detritus not allowed”*. `xattr -cr` does not help because the attributes come back immediately.
  Build with an explicit `-derivedDataPath` outside the synced folder.

### Liquid Glass findings

- Children positioned with `.position(...)` **inside `GlassEffectContainer` do not render**
  (the pill and page dots disappeared). Moving them out of the container into the surrounding
  `ZStack` fixed it; the container now wraps only the icon grid, where it is still needed for the
  upcoming hover plates and folder morph.
- `GlassEffectContainer` also renders nothing through `NSView.cacheDisplay` — offscreen snapshots
  therefore use a plain `ZStack` path guarded by `DebugSnapshot.flattenGlass`.
- `.clear` glass over a bright blurred wallpaper is nearly invisible (only the 1 px border reads),
  which matches the reference. On dark wallpapers the same code produces the frosted pill seen in
  the frames.

### Paging

- State lives in `AppModel` (`currentPage`, `pageCount`) so the AppKit scroll handler
  and the SwiftUI interface share it.
- Pages are laid out side by side and translated as one strip, so a drag moves the
  content with the pointer and the snap animates the remainder.
- Inputs: mouse drag (min 10 pt; turn at 16 % of the width or on a projected flick),
  two-finger trackpad swipe (follows the fingers live: each scroll event adds its horizontal
  delta to `pageDragOffset`; on release the distance is projected 0.15 s along the release
  velocity, so a quick short flick still turns the page, and the gesture commits past 16 % of
  the width; otherwise the strip springs back; inertial events are ignored), mouse wheel
  (accumulated 6, one notch one page), and left/right arrow keys. Dots are clickable.
- The live swipe is deliberately not animated per event: `pageDragOffset` is applied straight to
  the strip offset, and only the release runs `withAnimation`, so the page travels with the
  fingers instead of jumping as soon as a threshold is crossed.
- Dragging past the first/last page is rubber-banded to a third of the distance.
- The reference frames never show a second page, so the 0.34 s spring and its 0.08
  bounce are defaults.

### Menu bar and the Dock

The Dock must stay visible while the panel is up (user requirement, and the reference frames show it).

- `NSMenu.setMenuBarVisible(false)` hides the menu bar **and the Dock**.
- `NSApp.presentationOptions = [.hideMenuBar]` deadlocks the main thread in an `.accessory` app
  (verified: the setter never returns, active or not), so it is unusable.
- The menu bar is therefore not hidden but **painted over**: `MenuBarCoverWindow` sits at
  `statusBar + 1` (above the menu bar at 24 and the control-centre extras at 25), ignores the
  mouse, and shows the top slice of a screen-sized `BackdropView`. The panel stays at `.floating`
  (3), below the Dock (20), which then draws normally.
- Two windows never render a vibrancy material *exactly* alike (measured: ~2 % brighter in blue),
  so a hard edge shows. The panel's backdrop stops at the menu bar height and the cover fades out
  over the following 10 pt, which blends the two renderings into an invisible gradient.
- A window whose backdrop simply ended above the Dock would be wrong too: the Dock is translucent,
  so the blur must continue behind it.

### Backdrop

The backdrop is **not** a window-server material. `BackdropView` reads the screen's desktop
picture (`NSWorkspace.desktopImageURL(for:)`), composes it the way the Finder does (scaling and
fill colour from `desktopImageOptions`), blurs it with `CIGaussianBlur` and draws the result.
Launchpad thus *replaces* the desktop instead of looking through it: other applications'
windows, their video, and the desktop icons are all invisible behind the panel. The tint
(0.22 black) and vignette are untouched, so only what is behind the glass changed.

`desktopImageURL` is not the whole story on macOS 14 and later. When the wallpaper comes from
a wallpaper extension — which is every system wallpaper, including the default — it reports
`/System/Library/CoreServices/DefaultDesktop.heic`, the old Tahoe Lake aerial, instead of the
picture on screen. `SystemWallpaper` reads the active provider from
`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` (`Displays` first, then
`Spaces`, `AllSpacesAndDisplays`, `SystemDefault`, following `linked` sections to the first
`choices` entry), then takes the provider's bundled still (`TahoeLight`/`TahoeDark` by system
appearance) or, for extensions that only ship thumbnails, the newest frame the wallpaper agent
rendered for that provider at this screen's pixel size. Extension wallpapers report no picture
options at all and are composed as “Fill Screen”; fitting them would letterbox a square still
with bars of the fill colour. The reported file still wins whenever it is a real picture, so
picked photos are unaffected.

The picture is rendered at a quarter of the pixel size — the blur makes the difference
invisible and it costs ~20 ms instead of ~600 ms on this integrated GPU — and cached per
picture and screen size. Core Image's one-off shader compilation is paid at launch
(`BackdropView.preheat()`), so the first presentation is instant. If no picture can be read
or Reduce Transparency is on, the opaque gradient takes over; either way nothing from behind
the panel shows through. Both the panel and the menu-bar cover call `present(on:)` with the
same screen, so they draw the same cached image and join without a seam.

`desktopImageURL` can be **stale**: the Finder keeps drawing a picture after its file is
deleted or moved, because picking one copies it into the Wallpaper settings extension's
container (`~/Library/Containers/com.apple.wallpaper.extension.image/…/Caches`) and that list
survives the original. The reported URL then points at nothing, and the panel used to drop to
the gradient while the desktop still showed the picture. `WallpaperStore` therefore reads the
extension's `ChoiceRequests.ImageFiles` (each entry records the `originalURL` it was made
from and the `copyURL` it made), matches the reported URL — falling back to a matching file
name, for a picture that was moved — and renders that copy. This is a fallback only: a
readable desktop picture always wins. Verified on a wallpaper whose source had been deleted
from `~/Downloads`: the backdrop became the desktop picture again, dimmed and blurred
exactly as before.

### Global shortcut

**⌥Space** toggles the panel from any application. It is a Carbon hot key
(`RegisterEventHotKey` in `GlobalHotKey`): it is the only API that delivers a shortcut while
another app is frontmost without an Accessibility permission prompt — `NSEvent`'s global
monitor needs that permission and only observes. It is installed on the application event
target, so the handler runs on the main thread and hops straight back into the main actor.
The status item's "Show Launchpad" item carries the same glyph as a hint. If another
application already owns ⌥Space the registration fails; the menu bar item keeps working.

### Focus

`NSApp.activate()` is a no-op for an accessory app that was summoned by a hotkey, leaving the panel
unfocused and unable to receive a keystroke. The legacy
`NSApplication.ActivationOptions.activateIgnoringOtherApps` still works; it is spelled as
`ActivationOptions(rawValue: 1 << 1)` to keep the deprecation warning out of the build. The same
call is used to hand focus back when the panel is dismissed.

### Launching

A click runs `NSWorkspace.openApplication(at:configuration:)` with `activates = true`, then hides
the panel with `restoreFocus: false` so the launched app takes focus instead of the previous one.

Hit testing stops at the icon square and its name. The tap and hover gestures live on those two
shapes in `AppIconView`; the empty space around the icon inside its grid cell and the wide band
the label frame used to occupy are not targets. A click there never highlights or launches an
icon — it dismisses the panel instead, as does a click on any other empty part of the grid.

That dismiss tap sits on the canvas, not on the paged strip, because the strip's offset made tap
coordinates page-relative. It reads the location in a named coordinate space and ignores the
search pill and the page dots, so clicking the chrome does not close the panel. The first enemy
here was the opposite bug: a tap on the whole strip let a click in a gap close the panel while a
tap on the whole grid cell launched whichever icon owned that cell.

Only Esc (and the hotkey / status item toggle) closes the panel without a click, and a swipe is
still a swipe: the drag gesture takes the click before the tap can fire.

### Snapshot tooling (DEBUG only)`--snapshot <path>` waits for the catalog scan and the entrance animation, captures the app's own
window through `CGWindowListCreateImage` (resolved via `dlsym` to stay warning-free) and quits.
If the window-server capture is unavailable it falls back to a flattened `cacheDisplay` render.
`--screen` additionally allows a full-screen capture (used while checking the Dock and the top
strip); it needs the screen-recording permission.

---

## 8. Milestone (b) — Launchpad behaviours

Everything below was exercised on the build machine against the running panel (HID-level
clicks/keys), not only in unit tests. Release build: `x86_64 arm64`, no Swift warnings;
49 tests in 6 suites pass.

### 8.1 Grid model and persistence

- The grid is stored page by page as a list of `LauncherItem` slots: `.app(bundleID)` or
  `.folder(AppFolder)`. A page holds at most `columns × rows` slots (35 at 7×5), so folders
  consume one slot no matter how many apps they hold. Pages pack towards the top-left but may
  be sparse, so a new page can hold a single icon. Layouts saved before pages were explicit
  are read from their flat `items` list and split at 35 slots.
- Layout is stored at `~/Library/Application Support/Launchpad/layout.json`
  (ordered pages + folder names/ids). It is reconciled with the live catalog on launch:
  missing app IDs are dropped, unknown catalog apps are appended in catalog order, and
  reconciliation is skipped while the catalog is still empty so a slow scan cannot
  wipe the file.
- A folder with one remaining app collapses back to that app; a folder emptied by
  uninstalls is removed. Both are visible in the grid immediately and persisted.

### 8.2 Edit mode, reorder, removal

| Behaviour | Implementation |
|---|---|
| Enter edit mode | Long-press **0.65 s** on an icon (14 pt tolerance) or the “Edit” toggle; all icons jiggle with the iOS-style `IconWiggle` swing (±1.8–2.2°, off-centre pivot, 0.24–0.30 s cycle) |
| Leave | Esc, background click, or launching an app. A background click steps out one layer at a time: the first stops the jiggle, the next closes the panel |
| Reorder | Drag an icon straight from the resting grid: the page switches to jiggle mode and the icons slide aside live to open the gap under the pointer. Dropping on an empty slot reorders (persisted); dropping on an icon creates a folder or adds to one. A long-press without moving also enters jiggle mode |
| Page from edit mode | Dragging into the outer **5 %** bands for **0.55 s** turns one page; a timer drives the dwell, so a pointer that arrives and stops still flips. Holding at the right edge of the last page creates one new page per drag, even if that page will hold a single icon |
| Uninstall badge | White translucent “×” only on apps the catalog marks removable; system apps have none |
| Dock pin | Crossing into the Dock's reserved strip hands the custom drag to a real `NSDraggingSession` carrying the app's file URL, so the Dock provides its own insertion gap, icon slide and pin. The drag image is the app icon. No Dock preference write and no restart |
| Trash drop | A transparent guard window one level above the Dock covers the Trash tile for the duration of that native drag (Accessibility subrole `AXTrashDockItem`, else the bar's trailing tile). It accepts the file URL before the Dock can move the bundle and opens the same uninstall panel as the “×”. If the Dock gets the drop anyway, the catalog drops the app and the panel offers the remaining Library data |
| Confirmation | White 420 × 300 panel (frames 065–066): the app’s icon, name and total footprint, then checkable **Application Files / Application Support / Caches / Preferences / Saved State / Containers / Other Data** rows with per-item sizes, an **All** switch and Cancel / Move to Trash. Sizes are measured recursively off the main thread while the panel shows the reference spinner |
| Delete | `FileManager.trashItem` on every checked component; the app is removed from the catalog **and** `layout.json` only when its bundle was trashed, and failures are reported in a follow-up alert |

Verified: a throwaway app in `~/Applications` moved to the Trash through the badge flow,
and the layout lost its ID (`grep` count 0). The panel carries the app’s own icon, matching
frame 065; unchecking a category keeps that data on disk.

Reorder and folder creation were verified with direct drags (no prior hold): a press-and-drag
of Activity Monitor into a neighbouring slot reordered `layout.json`, dropping an icon on
another icon created a folder (three consistent runs) and dropping one on a folder added it
(three apps, one slot). This revision also switches the page into jiggle mode as soon as the
drag starts — the folder plate swap is held off while a drag is in flight so the Live Glass
subtree cannot tear down the gesture. The live gap was confirmed on the running build
(“reordering is fine now”).

**Live drop gap.** While a drag is in flight the grid renders a *preview* layout, not the
persisted one: `dragPreview` removes the dragged item from `model.items` and re-inserts it at
the slot under the pointer, every page is re-sliced from that array, and the tiles animate to
their new slots (`spring(0.26 s)`). The dragged tile itself is invisible in the grid — the
floating 1.12× tile is the only copy — so the preview leaves a real gap. Nothing is written
until the drop; `performDrop` then commits the same order, so the grid does not jump. When
the pointer is centred on another app or a folder, the preview is suppressed so that icon
stays under the cursor and the drop groups instead of reordering.

**No drop highlight.** No ring or marker is drawn anywhere, dashed or otherwise: reorders
and folder drag-outs alike show only the live gap. When an app hovers another app or a
folder, the target grows the folder plate instead: the same frosted squircle the folder
tiles use, 1.28× the icon and centred on it. The plate is never hit-tested and moves with
the wiggling grid. While the plate is showing, the target folder's own tile is hidden (its
name label stays) and the plate carries the folder's miniatures at the plate's scale, so
the hover previews the result instead of showing an empty outline. The floating drag icon
is never hidden and never resized while the gesture is live: it follows the pointer at full
size over folders too, and only becomes a miniature when the mouse is released and the drop
is committed. Shrinking it into the plate's free cell during the drag was tried and
reverted: the app left the pointer, and animating its position and scale every time the
drag crossed a folder made tracking visibly laggy. The plate springs in when the drag
reaches the tile and disappears **without animating**: the add-pop starts on the drop, and
a plate still fading out reads as a second, static folder behind the one that is
magnifying.

**The jiggle itself.** `IconWiggle` models the iOS Home Screen effect from its observable
parts: a ±1.8–2.2° swing eased at each end (sine), a pivot near the top of the icon so the
bottom edge travels further than the top, and a sub-point vertical bounce on a slower clock.
Every icon derives its own period (0.24–0.30 s per cycle), amplitude, pivot and phase from
its slot index, so the page never rocks in lockstep. That is faster than the first shipped
version (±1.2°, 0.30–0.42 s, centred pivot), which read as a slow metronome. Two approaches
were tried and rejected. A
`repeatForever` animation keeps running after the state flips back to idle: the delete
badges would vanish while every tile kept rocking, and neither a finite animation nor a
transaction with `disablesAnimations` stopped it. `phaseAnimator` did not animate at all on
this target (measured zero pixel movement). Because the timeline only *renders* the angle,
leaving edit mode simply returns 0° on the next frame — nothing is left running. The same
`TimelineView` at 60 Hz is used on folder tiles and on apps inside an open folder; its angle,
pivot and bounce all come from the same `IconWiggle` motion.

### 8.3 Folders

- **Create**: drag an app onto another app → both move into a new folder named
  “Untitled”. **Add**: drag an app onto a folder tile. The tile’s mini-grid updates on drop.
  Both work directly from the resting grid, with no hold-to-jiggle step first.
- **Naming a new folder**: a folder created by dropping one app onto another opens straight
  away with its name field focused and the suggested name selected, so typing replaces it
  (`AppModel.openFolder(_:promptingName:)` + `FolderView.promptsForName`). Opening an
  existing folder never takes the keyboard. Drops that only reorder or add to an existing
  folder leave the sheet closed.
- **Adding to a folder**: the target tile plays a one-shot pop — 1.16× over a 0.16 s spring,
  then back over 0.32 s (`FolderIconView.magnifyForAddition`, driven by `apps.count`) — so
  the addition is visible even when the new app is the fourth miniature and the tile barely
  changes. Only additions animate; removals do not. The whole tile scales as one layer: edit
  mode (and therefore the addition itself) draws a plain plate rather than hoisted glass,
  which `scaleEffect` cannot move.
- **Open**: click the tile → dimmed backdrop + glass panel. The app grid behind is dimmed,
  not removed. Esc or a click on the dimmed area (outside the panel) closes it; the panel
  itself swallows clicks so it cannot close by accident. Opening a folder does **not** end
  edit mode: apps inside jiggle with the rest of the grid, and closing the folder returns to
  the still-wobbling grid.
- **The dim covers the menu-bar strip too.** The 18 % black layer sits above the grid in the
  panel window, not in the folder sheet, but the menu bar is painted by
  `MenuBarCoverWindow`, a separate window above it. Left alone, the strip stayed undimmed and
  read as a bar across the top the moment a folder opened. `FolderDim` owns both layers — the
  grid's `FolderDimView` and the cover's — and animates them in a single animation group, so
  the two windows cannot disagree: a state flag only reaching one of them, or the two
  animating on different clocks, is what left a bright strip at the top while an app was
  dragged out of a folder. The cover's bottom fade and the panel's layer meet at the same
  value, so there is no edge. The dim resets on every presentation and on hide.
- **Rename**: triple-click the title (select-all), type, Return commits, Esc cancels;
  whitespace is trimmed (blank names are rejected). Double-clicking the title also enters
  the field.
- **Title placement** (frame 022 re-measured): the title is **above** the glass panel, not
  inside it — 31 px from the title’s baseline to the panel’s top edge at 1107 W. Implemented
  as a `VStack` whose spacing is `0.014 × W` plus the field’s own 30 pt height.
- **Panel metrics** (frame 022): width **86.5 % W**, height **0.2963 × W** (328 px at 1107),
  corner radius `0.027 × W` (30 px), inner grid **7 × 3**, icon `0.047 × W` (52 px),
  grid padding **42 px top / 14 px bottom** at 1107 W, labels at 0.9 × the grid label size.
  The height is capped at 62 % H so short displays never overflow.
- The glass is attached to the **panel view that contains the mini-grid**, not to a
  sibling layered above it. An earlier build sampled the app grid through the glass and
  left visible smears behind the miniature icons.

Verified end-to-end: created a folder from AirPort Utility + the test app, opened it,
launched AirPort Utility from inside (panel hid, app frontmost), renamed it twice, closed
with Esc and with an outside click, and confirmed the name persisted.

**Dragging an app out.** While a folder is open, dragging one of its icons switches the
whole sheet off (`FolderView.opacity(isDraggingOut:)`, 0.15 s) so the grid behind it is
revealed at full opacity and becomes the drop surface. A 1.12× tile follows the pointer and
the grid renders the same live preview a grid drag does: `AppModel.liftedItems(appID:)`
returns the grid as it will be after the lift (a two-app folder collapses to its survivor,
an emptied folder disappears), the app is re-inserted under the pointer, and the tiles slide
aside over the same 0.26 s spring. No ring or marker is drawn. Hovering another app or
folder keeps the app off the grid (it is about to go into that tile) and shows the folder
plate on that target instead; the *lift* stays visible in every state, so a two-app folder
collapses to its survivor — or vanishes — the moment the pointer leaves the panel and does
not flicker back as the pointer crosses icon centres. Releasing outside the panel resolves
through `AppModel.dropAppFromFolder(appID:slot:onto:)`: another app creates a folder named
after the pair — which opens immediately for naming, exactly like a grid-created folder — an
existing folder takes the app in, and any other slot reorders the grid
through `LauncherLayout.moveAppOutOfFolder(appID:toSlot:)`. Only the *icon* under the
pointer counts as a folder target, so a drop in the gap between two cells reorders even when
the nearest slot happens to hold an app. Dropping back on the folder it came from is a no-op
that returns the app to the panel unchanged.

**Reordering inside the panel.** Dragging an icon that stays within the panel never closes
it and never touches the grid: the pointer's cell (`row × 7 + column` of the panel's inner
grid, computed in `LaunchpadView.folderSlot(at:metrics:)`) becomes the destination, and
`folderPreview(metrics:)` re-renders the panel from a reordered copy of the folder's apps —
icons slide aside over a 0.26 s spring and leave a real gap, exactly like the grid's live
preview. The dragged cell (icon *and* label) is invisible; the floating 1.12× tile is drawn
in the panel's own icon size at the pointer. Nothing is committed until release, when
`LauncherLayout.moveApp(inFolder:appID:toSlot:)` writes the new order (clamped to the child
range) through `AppModel.moveApp(inFolder:appID:toIndex:)`. A drag that starts inside a
resting (non-jiggling) folder switches edit mode on, the same way a grid drag does.
Verified: three apps dragged from slot 1 to slot 3 and back, order persisted, panel stayed
open; dragging past the panel edge lifts the app out onto the grid with the live preview
described above.

### 8.4 Search

The pill is an AppKit-owned text field inside a SwiftUI capsule, but the AppKit key
monitor is the source of truth for typing:

| Input | Effect |
|---|---|
| First printable character | opens the search with that character as the query (no focus race, no lost first key) |
| Further printable characters | appended by the monitor while the field is **not** first responder |
| Click on the pill | focus moves to the field; from then on the field editor owns typing and deletion |
| Delete | monitor removes the last character; on the last one the search ends |
| ← → ↑ ↓ | move the selection by 1 / `columns` within the results |
| Return / keypad Enter | launches the selected result and hides the panel |
| Esc | clears the query first; a second Esc hides the panel |

- Ranking (`SearchRanking`): exact name, prefix, word-prefix, substring, initials — each
  tier sorted by name length then alphabetically. Result tiles use the normal 102 pt icons
  in the same 7-column rhythm; the selected tile gets a 2 pt white ring plus a 12 % white
  fill. Typing “cal” yields Calculator then Calendar; → selects Calendar; Return opened it.
- The empty state (no matches) is a centred muted message, and the pill keeps the typed
  text so backspace can recover.
- The field forces `.environment(\.colorScheme, .dark)` and draws its own white placeholder text
  behind it: the native prompt is rendered by the field editor with the system's secondary label
  colour, which turns black in macOS light mode on top of the glass. The folder name field does
  the same.

### 8.5 Dismissal and focus

- Any click on empty grid space (including between icons) hides the panel; clicks on the
  pill, dots and page chrome do not.
- Clicking an icon or its label launches the app and hides the panel without restoring
  focus to the previous app, so the launched app comes forward.
- The panel also hides when another app becomes active (`didResignActive`), matching
  Launchpad: switching to another app or ⌘-Tab dismisses it. The Dock remains visible
  throughout (panel at level 3, Dock at 20).

### 8.6 Known limits / defaults kept

- Folder morph uses `glassEffectID`; the reference video only shows the settled panel, so
  the 0.30 s spring is our default.
- The edge-drag page turn is implemented (5 % bands, 0.55 s dwell) but was not exercised
  end-to-end; only programmatic paging and the arrow keys are verified.
- Edit mode has no “Done” button, matching the reference frames.
- The uninstall panel scans the app bundle plus the matching folders under `~/Library`
  (Application Support, Caches, Preferences, Saved Application State, Containers, WebKit,
  HTTPStorages, Application Scripts, LaunchAgents, Logs) for the bundle identifier and, where
  installers commonly use it, the display name. It does not enumerate `ByHost` preferences or
  team-prefixed group containers.
- Measuring a large app (Chrome-sized caches, multi-GB bundles) can keep the spinner up for a
  moment; the scan runs on a detached task, so the panel still responds and can be cancelled.
- The uninstall panel is drawn in the light appearance even when the launcher is dark, because
  frame 065 is a white dialog; the rest of the UI keeps Liquid Glass.
- The Dock handoff uses a real file drag, so once the pointer enters the Dock area the grid
  reorder gesture is over; dragging back into the grid cancels the pin instead of reordering.
  Without Accessibility the Trash guard falls back to the bar's trailing tile; if even the Dock
  bar cannot be found, the Dock's own Trash behavior is left alone.
- A folder dragged to the Dock is not pinned; only app tiles can leave the grid. Dropping a
  system app on the Trash does nothing because it cannot be uninstalled.

### 8.7 Deliberate deviations from the reference (user requests)

- **No hover highlight, no hover magnification.** Frames 018/067 show a glass plate behind
  the hovered icon (and the icons in an opened folder get the same treatment); the shipped
  build draws every icon at rest. `hoverPlate` was removed from `AppIconView`, the halo and
  4 % scale from `FolderIconView`, and the halo + 4 % scale from `FolderAppIcon`. A
  pixel-diff of the icon region with the pointer on and off the icon shows 0 differing
  pixels, so the pointer has no effect on any icon. The search tile's selection ring
  (keyboard/arrow selection) and the page-dot hover capsule are unaffected.

### 8.8 Folder wiggle and Liquid Glass

The folder tile uses the same `IconWiggle` swing as an app icon (its own seed keeps
neighbouring folders out of sync). Frame-capturing the edit-mode animation exposed a
compositing trap:

- `.glassEffect` is not drawn by the view it is attached to. SwiftUI hoists it into the
  enclosing `GlassEffectContainer` (rendered in container space) and the rotated subtree is
  composited separately. The glass plate therefore stayed **axis-aligned** while the
  miniature icons swung inside it — visually a bounce, not a wiggle. Measuring the tile's
  top edge over time gave only ≈ 0.05–0.13° of apparent tilt.
- `.compositingGroup()` before the rotation does not help: the plate is hoisted before the
  group is flattened.
- Dropping `GlassEffectContainer` in edit mode does make the plate rotate, but it then
  renders at roughly **2×** the intended size, because the container is what sizes and
  merges the glass.

Shipped fix: `FolderTileGlass` applies `.glassEffect` **only when not editing**. In edit
mode the tile is the plain translucent fill (`.white.opacity(0.13)` + 1 pt border) plus the
miniature grid, so rotation moves the whole square as one piece. The measured top-edge tilt
tracks the `IconWiggle` swing (±1.8–2.2°; the sampling threshold on anti-aliased edges
under-reads it), and the at-rest appearance is unchanged — the non-edit capture still shows the glass
plate, specular rim and miniatures. The swap is invisible in practice because the wiggle
only exists while editing and the two fills are close in value on the dark backdrop.

A dragged folder used to leave a **clone** at its old slot. The hoisted glass plate ignores both
the tile's rotation and its `opacity(0)`, so hiding the tile for the drag hid only its fill and
miniatures; the glass stayed drawn under the floating tile. The plate now also follows
`!isEditing`, and a drag always runs in edit mode, so the hidden tile leaves nothing behind.
The floating drag tile draws its own glass outside the container.

Two consequences, both verified:

- The **add-to-folder pop** scales one layer. When the plate was live in edit mode, the pop's
  `scaleEffect` moved the fill and miniatures but not the hoisted glass, which stayed at 1× —
  the “folder icon plus a second folder” the pop appeared to leave behind.
- The **gestures moved out of the swapped subtree**. Toggling edit mode swaps the plate inside
  the tile; with the tap/long-press/drag gestures attached inside, the swap could tear down a
  drag that had just begun (folder drags start by entering edit mode). They now sit on a
  transparent `Color.clear` layer over the icon, so the artwork can change structure mid-gesture
  without losing the drag.

### 8.9 Lifted folder plate

The reference frames 004–008 show a folder being carried: a clear glass squircle, about 1.28×
an icon, holding the 3 × 3 miniatures and floating over the wallpaper and the icons it passes.
The look has four parts, and all of them are public API:

- **Material.** `.glassEffect(.clear, in:)` on a continuous-corner squircle. `.clear` keeps the
  wallpaper and the icon underneath readable and lets the system's edge lensing bend them;
  `.regular` would frost the plate into an opaque tile. A `.white.opacity(0.11)` fill inside the
  glass supplies the slight milkiness the reference plate has without hiding the backdrop.
- **Content above the glass.** The miniatures are the glass view's own content (`FolderPlate`),
  so they stay crisp instead of being sampled as backdrop. This is the same layering rule the
  resting tile already follows.
- **Rim.** The system rim is subtle; `GlassRim` overlays a 1.2 pt specular gradient (bright
  top-leading, fading across, with a faint reflected edge at the opposite corner) plus a soft
  inner bevel. A resting folder tile and a lifted plate use full intensity; the large opened
  panel uses 0.8, where a full-strength outline would read as a drawn border.
- **Lift.** The floating plate is drawn at its final size — never `scaleEffect` — because the
  hoisted glass ignores render transforms (8.8). For the same reason the drop plate's spring
  grows its **frame** from 92 % to 100 % instead of scaling. The drag preview keeps a wider,
  softer shadow (radius 18, y 9) to separate it from the grid.

Glass stays opt-in for `FolderDropPlate`: over a bare app icon the plate must remain a plain
fill, because a hoisted glass surface is composited above sibling content and would blur the
icon it is meant to sit behind. Folder targets pass `.clear` and get the full plate.

Result: the folder has one material in every state — resting tile, lifted plate and opened
panel all use the same `.clear` glass, milkiness and specular rim — and dragging a folder, or
hovering a dragged app over one, shows the same lifted lens as the reference, with the wallpaper
and neighbouring icons visible through it.

### 8.10 Desktop swipe while Launchpad is open

The three- or four-finger “Swipe between full-screen applications” gesture belongs to the Dock,
not to the frontmost app. Paging the grid with that gesture therefore slid the whole desktop
away instead of turning the page, and the Dock exposes no public switch to pause it.

The gesture reaches the session as a private `dockControl` event (CGEvent type 30) and companion
`gesture` events (type 29); the same pair carries Mission Control, App Exposé and Show Desktop.
`TrackpadGestureBlocker` installs head-insert taps for exactly those two event types on both the
session and the annotated session stream, because the Dock does not use one location exclusively.
While the panel is visible every event of those types is dropped before the Dock sees it.

The block itself only changes at a trackpad contact boundary. Switching it in the middle of a
gesture gave the Dock an incomplete sequence: it saw the beginning of the pinch that opened
Launchpad but never its end, stayed armed, and spent the next gesture finishing it. The visible
symptom was that the first spread or desktop swipe after closing Launchpad did nothing and the
second one worked. `GestureBlockGate` now holds a change while any finger is down and applies it
when the contact ends; a sequence that starts while a change is waiting settles it on its first
frame, so a gesture is either wholly blocked or wholly passed through. Waiting is capped so a
resting finger or a missing end frame cannot leave the block on. Two-finger paging arrives as
scroll-wheel events (type 22) and is untouched, and the raw
contacts behind pinch, spread and the three-, four- and five-finger page swipes are read straight
from the trackpad, so they keep working while their system equivalents stand down. A multi-finger
sideways swipe is recognised from those contacts and pages the grid instead of switching desktops
or full-screen apps; two fingers deliberately stay on the scroll path so a page cannot move twice.
The tap also survives the system disabling it (timeout / user input) by re-enabling itself.

While **Pinch with four fingers** is on, together with **Block system gestures while open** and
Accessibility, the Dock's own Apps pinch is disabled through `showSpotlightGestureEnabled` (plus
the legacy launchpad key), so macOS's Apps view cannot open instead of Launchpad; Spotlight itself
remains on `⌘Space`. Turning the pinch switch off hands the Dock's Apps pinch back — the block
setting still keeps system gestures from interrupting an open Launchpad. Spread and multi-finger
paging need the block setting and grant without the pinch switch. Without the grant the Dock would
still act, so Launchpad would race it instead of replacing it; the banner asks for the grant
instead. Its **Grant Permissions in Settings** button opens Settings on General and highlights the
Accessibility row in red until it is clicked (or the grant arrives), so the next step is not lost
among the other rows. The Apps override is restored as soon as the switch or the block setting is turned off or
the grant is missing, which a small trust poll in `AppDelegate` notices even while Launchpad is
hidden.

The same gestures belong to macOS's **Show Desktop**: a spread reveals the desktop, and the next
pinch restores the windows. Without care, that restoring pinch also opened Launchpad. The
recognizer emits one gesture per contact sequence and requires the fingers to lift between them,
so a spread is always observed first. `DesktopRevealState` arms on a spread seen with no panel on
screen and consumes the following pinch, which then only restores the desktop. No timeout is used:
a user may work on the desktop for an arbitrary length of time before pinching the windows back,
and a deadline would turn that restore into an unwanted Launchpad activation. An explicit hotkey,
menu bar or hot-corner activation clears the pending restore. A spread while the panel is visible
does not arm the state — the Dock is blocked then, so no desktop was revealed.

The taps need Accessibility access. macOS keys an ad-hoc signature's grant to the build's code
hash, so a new install leaves System Settings showing an enabled switch that no longer applies to
the running binary — the silent failure that made both the spread and the desktop swipe still
fire. `AccessibilityAccess.grant()` clears that stale entry and requests access again, which is
what the Settings button does; it has to be clicked once after each install. A certificate-based
signature would keep the grant across rebuilds, but it requires a trusted signing identity and is
not used here.

