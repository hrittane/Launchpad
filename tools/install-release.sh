#!/bin/zsh
# Builds the universal Release app and installs it in /Applications.
#
# The build is ad-hoc signed ("Sign to Run Locally"). macOS ties an ad-hoc
# signature's Accessibility grant to that build's code hash, so every new
# install makes the existing Privacy switch stale: System Settings still shows
# Launchpad as enabled while the new binary is not trusted. Use Settings →
# General → Trackpad → Grant Access once after each install; it removes the
# stale entry and asks for the current build.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

installed="/Applications/Launchpad.app"
derived="$HOME/Library/Caches/Launchpad/Release"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

xcodebuild -project Launchpad.xcodeproj -scheme Launchpad -configuration Release \
    -derivedDataPath "$derived" ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO build

app="$derived/Build/Products/Release/Launchpad.app"
# The cached product may still carry a signature from an earlier build, so the
# ad-hoc signature is applied explicitly rather than trusting incremental builds.
codesign --force --options runtime --timestamp=none --sign - "$app"
codesign --verify --verbose=2 "$app"

pkill -x Launchpad >/dev/null 2>&1 || true
sleep 1
rm -rf "$installed"
ditto "$app" "$installed"
"$lsregister" -f "$installed"
open -n "$installed"
echo "Installed $installed"
