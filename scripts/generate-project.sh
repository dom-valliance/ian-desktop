#!/usr/bin/env bash
# Regenerates App/Ian.xcodeproj from App/project.yml with XcodeGen, then copies IanKit's pins into
# the project, because Xcode ignores a local package's Package.resolved (ADR 0010).
set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode 27 (ADR 0010) and re-run." >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift run --package-path scripts/tools --force-resolved-versions xcodegen generate --spec App/project.yml

resolved_dir=App/Ian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$resolved_dir"
cp Packages/IanKit/Package.resolved "$resolved_dir/Package.resolved"
