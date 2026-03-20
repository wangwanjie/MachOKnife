#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$(mktemp -d "${TMPDIR:-/tmp}/MachOKnifeReadmeScreenshots.XXXXXX")"
SANDBOX_SCREENSHOT_DIR="$HOME/Library/Containers/cn.vanjay.MachOKnife/Data/Library/Application Support/MachOKnife/ReadmeScreenshots"
REPO_SCREENSHOT_DIR="$REPO_ROOT/docs/screenshots"

cleanup() {
  rm -rf "$DERIVED_DATA_PATH"
}
trap cleanup EXIT

rm -rf "$SANDBOX_SCREENSHOT_DIR" "$REPO_SCREENSHOT_DIR"

echo "[readme-assets] render screenshots"
xcodebuild test \
  -project "$REPO_ROOT/MachOKnife.xcodeproj" \
  -scheme MachOKnife \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:MachOKnifeTests/ReadmeAssetsTests

if [[ ! -f "$SANDBOX_SCREENSHOT_DIR/main-window.png" ]]; then
  echo "missing main-window.png at $SANDBOX_SCREENSHOT_DIR" >&2
  exit 1
fi

if [[ ! -f "$SANDBOX_SCREENSHOT_DIR/preferences-updates.png" ]]; then
  echo "missing preferences-updates.png at $SANDBOX_SCREENSHOT_DIR" >&2
  exit 1
fi

mkdir -p "$REPO_SCREENSHOT_DIR"
cp "$SANDBOX_SCREENSHOT_DIR/main-window.png" "$REPO_SCREENSHOT_DIR/main-window.png"
cp "$SANDBOX_SCREENSHOT_DIR/preferences-updates.png" "$REPO_SCREENSHOT_DIR/preferences-updates.png"

echo "[readme-assets] copied screenshots to $REPO_SCREENSHOT_DIR"
