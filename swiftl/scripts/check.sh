#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" "$repo_dir/swiftl/Sources/TranslatorViewModel.swift" \
  "$repo_dir/swiftl/Sources/TranslationResult.swift" \
  "$repo_dir/swiftl/Sources/SelectedTextReader.swift" \
  "$repo_dir/swiftl/Tests/TranslationChecks.swift" -o "$check_dir/checks"
"$check_dir/checks" "$@"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" "$repo_dir/swiftl/Sources/UpdateChecker.swift" \
  "$repo_dir/swiftl/Sources/UpdateInstaller.swift" \
  "$repo_dir/swiftl/Tests/UpdateChecks.swift" -o "$check_dir/update-checks"
"$check_dir/update-checks" "$@"
