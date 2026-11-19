#!/bin/zsh
# Builds an ad-hoc signed universal Release app and packages it for direct
# download from a landing page.
#
# There is no Developer ID or notarization here. macOS will therefore quarantine
# the download and ask the user to approve it once (System Settings → Privacy &
# Security → Open Anyway). LANDING.md contains the user-facing copy for that.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

derived="$HOME/Library/Caches/Launchpad/Release"
output="$root/dist"
mkdir -p "$output"

xcodebuild -project Launchpad.xcodeproj -scheme Launchpad -configuration Release \
    -derivedDataPath "$derived" ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO build

app="$derived/Build/Products/Release/Launchpad.app"
# Apply the ad-hoc signature explicitly: an incremental build may leave a
# previous signature on the cached product.
codesign --force --options runtime --timestamp=none --sign - "$app"
codesign --verify --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
    "$app/Contents/Info.plist")"
dmg="$output/Launchpad-$version.dmg"
stage="$(mktemp -d "${TMPDIR:-/tmp}/launchpad-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

ditto "$app" "$stage/Launchpad.app"
ln -s /Applications "$stage/Applications"

hdiutil create -volname "Launchpad" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null
shasum -a 256 "$dmg" | tee "$dmg.sha256"

echo "Created $dmg"
