#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
output="$root/dist/Coding Limits.app"
installed="/Applications/Coding Limits.app"

install=false
case "${1:-}" in
  "") ;;
  --install) install=true ;;
  *) echo "usage: $0 [--install]" >&2; exit 64 ;;
esac

swift build --package-path "$root" -c release
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
cp "$root/.build/release/CodingLimitsMenuBar" "$output/Contents/MacOS/CodingLimitsMenuBar"
cp "$root/Resources/Info.plist" "$output/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$output/Contents/Resources/AppIcon.icns"

if ! $install; then
  echo "$output"
  exit 0
fi

pkill -x CodingLimitsMenuBar && while pgrep -x CodingLimitsMenuBar >/dev/null; do sleep 0.1; done || true
rm -rf "$installed"
ditto "$output" "$installed"
open "$installed"
echo "$installed"
