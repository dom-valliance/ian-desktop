#!/usr/bin/env bash
# Regenerates the contract code and the Xcode project, and fails if either differs from the commit.
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$scripts_dir/.."

"$scripts_dir/generate-contract.sh"
"$scripts_dir/generate-project.sh"

# XcodeGen writes these three project paths. Xcode itself writes Package.resolved and workspace
# checks under project.xcworkspace/xcshareddata on a developer's first build, so those stay out.
drift="$(git status --porcelain -- \
  Packages/IanKit/Sources/Contract/Generated \
  Packages/IanKit/Tests/ContractTests/Fixtures \
  App/Ian.xcodeproj/project.pbxproj \
  App/Ian.xcodeproj/project.xcworkspace/contents.xcworkspacedata \
  App/Ian.xcodeproj/xcshareddata)"
if [[ -n "$drift" ]]; then
  echo "Generated files are out of date:" >&2
  echo "$drift" >&2
  echo "Run scripts/generate-contract.sh and scripts/generate-project.sh, then commit." >&2
  exit 1
fi
