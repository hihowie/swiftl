#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
output_dir="${1:-$repo_dir/../dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
build_dir="$output_dir/../build"

build_settings=(CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO "ARCHS=arm64 x86_64")
if [[ -n "${APP_VERSION:-}" ]]; then
  if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'APP_VERSION must have the format 1.2.3\n' >&2
    exit 1
  fi
  build_settings+=("MARKETING_VERSION=$APP_VERSION")
fi
if [[ -n "${APP_BUILD_NUMBER:-}" ]]; then
  if [[ ! "$APP_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    printf 'APP_BUILD_NUMBER must be numeric\n' >&2
    exit 1
  fi
  build_settings+=("CURRENT_PROJECT_VERSION=$APP_BUILD_NUMBER")
fi

xcodebuild -project "$repo_dir/swiftl/SwifTL.xcodeproj" \
  -scheme SwifTL -configuration Release \
  -derivedDataPath "$build_dir" -destination 'generic/platform=macOS' \
  "${build_settings[@]}" build

ditto "$build_dir/Build/Products/Release/SwifTL.app" "$output_dir/SwifTL.app"
codesign --force --sign - \
  --entitlements "$repo_dir/swiftl/Resources/swiftl.entitlements" \
  "$output_dir/SwifTL.app"
codesign --verify --deep --strict "$output_dir/SwifTL.app"
for architecture in arm64 x86_64; do
  xcrun lipo "$output_dir/SwifTL.app/Contents/MacOS/SwifTL" -verify_arch "$architecture"
done

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$output_dir/SwifTL.app" "$staging_dir/SwifTL.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname SwifTL -srcfolder "$staging_dir" \
  -ov -format UDZO "$output_dir/SwifTL.dmg"
hdiutil verify "$output_dir/SwifTL.dmg"
printf '\nApp: %s\nDMG: %s\n' "$output_dir/SwifTL.app" "$output_dir/SwifTL.dmg"
