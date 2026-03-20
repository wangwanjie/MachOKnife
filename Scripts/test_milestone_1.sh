#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$(mktemp -d "${TMPDIR:-/tmp}/MachOKnifeDerivedData.XXXXXX")"
PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/Debug"

cleanup() {
  rm -rf "$DERIVED_DATA_PATH"
}
trap cleanup EXIT

echo "[milestone-1] swift test CoreMachO"
swift test --package-path "$REPO_ROOT/Packages/CoreMachO"

echo "[milestone-1] swift test MachOKnifeKit"
swift test --package-path "$REPO_ROOT/Packages/MachOKnifeKit"

echo "[milestone-1] swift test MachOKnifeDB"
swift test --package-path "$REPO_ROOT/Packages/MachOKnifeDB"

echo "[milestone-1] xcodebuild UI and settings tests"
xcodebuild test \
  -project "$REPO_ROOT/MachOKnife.xcodeproj" \
  -scheme MachOKnife \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'platform=macOS,arch=x86_64' \
  -only-testing:MachOKnifeTests/AppSettingsTests \
  -only-testing:MachOKnifeUITests/WorkspaceLaunchUITests

echo "[milestone-1] build fixtures"
bash "$REPO_ROOT/Scripts/build_fixtures.sh"

echo "[milestone-1] run CLI against fixture"
CLI="$PRODUCTS_DIR/machoe-cli"
FIXTURE="$REPO_ROOT/Resources/Fixtures/generated/libFixture.dylib"

if [[ ! -x "$CLI" ]]; then
  echo "machoe-cli not found at $CLI" >&2
  exit 1
fi

INFO_OUTPUT="$("$CLI" info "$FIXTURE")"
DYLIB_OUTPUT="$("$CLI" list-dylibs "$FIXTURE")"

[[ "$INFO_OUTPUT" == *"Slices:"* ]] || { echo "missing slice summary in info output" >&2; exit 1; }
[[ "$INFO_OUTPUT" == *"Install Name: @rpath/libFixture.dylib"* ]] || { echo "missing fixture install name in info output" >&2; exit 1; }
[[ "$DYLIB_OUTPUT" == *"RPATH @loader_path"* ]] || { echo "missing fixture rpath in list-dylibs output" >&2; exit 1; }
[[ "$DYLIB_OUTPUT" == *"@rpath/libFixtureDependency.dylib"* ]] || { echo "missing dependency path in list-dylibs output" >&2; exit 1; }

echo "[milestone-1] verification complete"
