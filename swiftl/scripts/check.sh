#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" "$repo_dir/swiftl/Sources/TranslatorViewModel.swift" \
  "$repo_dir/swiftl/Tests/TranslationChecks.swift" -o "$check_dir/checks"
"$check_dir/checks" "$@"
