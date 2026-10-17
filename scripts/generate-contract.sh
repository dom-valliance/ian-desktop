#!/usr/bin/env bash
# Regenerates the Contract target's Swift code and the ContractTests fixtures from the contract.
set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode 26 (Swift 6.2 or later, ADR 0008) and re-run." >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift run --package-path scripts/tools --force-resolved-versions swift-openapi-generator generate \
  --config Packages/IanKit/Sources/Contract/openapi-generator-config.yaml \
  --output-directory Packages/IanKit/Sources/Contract/Generated \
  contract/ian-desktop.v1.yaml

swift run --package-path scripts/tools --force-resolved-versions extract-examples \
  contract/ian-desktop.v1.yaml Packages/IanKit/Tests/ContractTests/Fixtures
