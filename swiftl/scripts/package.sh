#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
output_dir="${1:-$repo_dir/../dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
build_dir="$output_dir/../build"

xcodebuild -project "$repo_dir/swiftl/SwifTL.xcodeproj" \
  -scheme SwifTL -configuration Release \
  -derivedDataPath "$build_dir" -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

ditto "$build_dir/Build/Products/Release/SwifTL.app" "$output_dir/SwifTL.app"
codesign --force --sign - \
  --entitlements "$repo_dir/swiftl/Resources/swiftl.entitlements" \
  "$output_dir/SwifTL.app"
codesign --verify --deep --strict "$output_dir/SwifTL.app"

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$output_dir/SwifTL.app" "$staging_dir/SwifTL.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname SwifTL -srcfolder "$staging_dir" \
  -ov -format UDZO "$output_dir/SwifTL.dmg"
hdiutil verify "$output_dir/SwifTL.dmg"
printf '\nApp: %s\nDMG: %s\n' "$output_dir/SwifTL.app" "$output_dir/SwifTL.dmg"
