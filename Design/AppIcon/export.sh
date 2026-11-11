#!/bin/bash
set -euo pipefail

design_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$design_dir/../.." && pwd)"
asset_dir="$project_dir/ANY/Resources/Assets.xcassets/AppIcon.appiconset"
iconset_dir="$(mktemp -d)/ANY.iconset"
trap 'rm -rf "$(dirname "$iconset_dir")"' EXIT
mkdir -p "$iconset_dir"

# Keep the macOS 26 source square and full-bleed; the system supplies the mask.
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((points * scale))
        suffix=""
        if [ "$scale" -eq 2 ]; then suffix="@2x"; fi
        filename="icon_${points}x${points}${suffix}.png"
        sips -z "$pixels" "$pixels" "$design_dir/any-icon-master.png" --out "$asset_dir/$filename" >/dev/null
        cp "$asset_dir/$filename" "$iconset_dir/$filename"
    done
done

iconutil -c icns "$iconset_dir" -o "$design_dir/ANY.icns"
echo "Exported AppIcon assets and Design/AppIcon/ANY.icns"
