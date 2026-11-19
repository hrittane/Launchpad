# Landing page copy

Paste-ready text for the download page. Replace the version and checksum with the values printed
by `./tools/make-dmg.sh` for each release.

---

## Launchpad, the way you remember it

A native macOS 26 app grid: Liquid Glass folders, live search, finger-following paging, icon
jiggle and drag-to-reorder — over your real desktop wallpaper. Runs on Intel and Apple silicon.

![The app grid](images/launchpad-grid.png)
![A folder open](images/launchpad-folder.png)

### Features

- **Familiar grid** — 7×5 by default, with optional 7/8/9 × 4/5/6 layouts.
- **Folders** — drag apps together to create one, drag between folders to reorganise.
- **Trackpad gestures** — four-finger pinch to open, spread to close, sideways swipe to turn a
  page. Two-finger swipes work too, and follow your fingers.
- **Quick find** — start typing to search every app.
- **Your wallpaper** — the real desktop picture, blurred and dimmed behind the grid.
- **Keyboard first** — `⌥Space` toggles Launchpad from anywhere; arrow keys and Return launch.

### Download

**Launchpad 1.0** · macOS 26 or later · universal (Intel + Apple silicon)

[Download the DMG](https://example.com/Launchpad-1.0.dmg) ·
[SHA-256](https://example.com/Launchpad-1.0.dmg.sha256) ·
[Source code](https://github.com/hrittane/Launchpad)

Verify the download in Terminal:

```sh
shasum -a 256 ~/Downloads/Launchpad-1.0.dmg
```

Expected: `d51177c2b05bb077db16a986068b663be3dced8f1e0a58f090390b97f8ee76da`
_(replace this with the checksum of the build you publish)_

### macOS says the app can't be opened

This app is distributed independently, without Apple notarization, so macOS quarantines the
first download. It is a one-time step per version:

1. Open the downloaded DMG and drag **Launchpad** to **Applications**.
2. Double-click Launchpad. macOS will say it **cannot check the app for malicious software**.
3. Open **System Settings → Privacy & Security**.
4. Scroll down to the security section and click **Open Anyway** next to the Launchpad message.
5. Confirm, then launch Launchpad again.

If the message does not appear, run `xattr -d com.apple.quarantine /Applications/Launchpad.app`
in Terminal once, then launch again.

### Why Launchpad asks for Accessibility

macOS sends four-finger swipes, Mission Control and Show Desktop to the Dock. If Launchpad let
those gestures through, paging the grid would slide your desktop away, and the spread that closes
Launchpad would also reveal the desktop.

To prevent that, Launchpad asks for **Accessibility** access and temporarily intercepts those
gesture events while the grid is on screen. Nothing is recorded and nothing is sent anywhere:
the app contains no analytics or network code. In **Settings → General → Trackpad** you can turn
this off at any time.

After an update, macOS may show the Accessibility switch as on while it no longer applies to the
new build. If the desktop starts sliding behind the grid, open Launchpad and click **Allow gesture
blocking → Grant Access** in the banner next to the search field, then switch Launchpad on in
System Settings. That is a one-time step for each new version.

### FAQ

**Does it replace the Dock?** No. The Dock stays visible; this is an app grid, not a Dock
replacement.

**Does it hide the menu bar?** No. The strip is painted over while Launchpad is on screen.

**Why isn't this on the App Store / why no notarization?** It is an independent, free download.
The DMG checksum and the full source are published so you can verify what you are installing.

**Does it work on Intel Macs?** Yes. The download contains both x86_64 and arm64 builds.

**Where are my apps and folders stored?** In `~/Library/Application Support/Launchpad/layout.json`
on your Mac. Preferences are in `UserDefaults`. Nothing is uploaded.
