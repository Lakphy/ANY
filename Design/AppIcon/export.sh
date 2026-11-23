#!/bin/bash
set -euo pipefail

design_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$design_dir/../.." && pwd)"
resources_dir="$project_dir/ANY/Resources"
icon_bundle="$resources_dir/AppIcon.icon"
compass="$icon_bundle/Assets/compass.svg"
menu_glyph="$resources_dir/Assets.xcassets/ANYCompass.imageset/compass.svg"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Crop the app icon's transparent foreground to a 20 pt menu bar template.
sed '1c\
<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="180 180 664 664">
' "$compass" > "$menu_glyph"

# Export the square artwork with the same solid background as the Icon Composer file.
sed '1a\
  <rect width="1024" height="1024" fill="#252525"/>
' "$compass" > "$work_dir/compass.svg"
sips -s format png "$work_dir/compass.svg" --out "$design_dir/any-icon-master.png" >/dev/null

xcrun actool "$icon_bundle" --compile "$work_dir" --app-icon AppIcon \
    --platform macosx --target-device mac --minimum-deployment-target 27.0 \
    --output-format human-readable-text --warnings --output-partial-info-plist "$work_dir/Info.plist"
cp "$work_dir/AppIcon.icns" "$design_dir/ANY.icns"
echo "Exported the menu bar template, PNG artwork, and ANY.icns"
