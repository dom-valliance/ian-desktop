#!/usr/bin/env bash
# Regenerates the Contract target's Swift code and the ContractTests fixtures from the contract.
set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode 26 or the Swift 6 toolchain and re-run." >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift run --package-path scripts/tools swift-openapi-generator generate \
  --config Packages/IanKit/Sources/Contract/openapi-generator-config.yaml \
  --output-directory Packages/IanKit/Sources/Contract/Generated \
  contract/ian-desktop.v1.yaml

swift run --package-path scripts/tools extract-examples \
  contract/ian-desktop.v1.yaml Packages/IanKit/Tests/ContractTests/Fixtures
