#!/usr/bin/env bash
# Regenerates App/Ian.xcodeproj from App/project.yml with XcodeGen.
set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode 26 or the Swift 6 toolchain and re-run." >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift run --package-path scripts/tools xcodegen generate --spec App/project.yml
