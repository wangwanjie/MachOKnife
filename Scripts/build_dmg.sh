#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
DMG_OUTPUT_DIR="$BUILD_DIR/dmg"
KEYCHAIN_PROFILE="$DEFAULT_NOTARY_PROFILE"
SKIP_NOTARIZE=false
SIGNING_IDENTITY=""

generate_dmg_background() {
    local output_path="$1"

    /usr/bin/swift - "$output_path" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("missing output path\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 640, height: 380)
let rect = NSRect(origin: .zero, size: size)
let base = NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.97, alpha: 1)
let top = NSColor(calibratedRed: 0.89, green: 0.93, blue: 0.96, alpha: 1)
let accent = NSColor(calibratedRed: 0.81, green: 0.35, blue: 0.13, alpha: 1)
let steel = NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.30, alpha: 1)
let text = NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.22, alpha: 1)
let subtitle = NSColor(calibratedRed: 0.34, green: 0.40, blue: 0.46, alpha: 1)
let panel = NSColor(calibratedWhite: 1.0, alpha: 0.94)
let stroke = NSColor(calibratedRed: 0.77, green: 0.84, blue: 0.89, alpha: 1)

let image = NSImage(size: size)
image.lockFocus()

NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26).fill(with: .sourceOver)
base.setFill()
NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26).fill()

let headerRect = NSRect(x: 0, y: 250, width: size.width, height: 130)
let gradient = NSGradient(colorsAndLocations: (top, 0.0), (base, 1.0))
gradient?.draw(in: headerRect, angle: -90)

func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    let bounds = attributed.boundingRect(with: NSSize(width: rect.width, height: .greatestFiniteMagnitude), options: options)
    let drawRect = NSRect(x: rect.minX, y: rect.midY - ceil(bounds.height) / 2, width: rect.width, height: ceil(bounds.height))
    attributed.draw(with: drawRect, options: options)
}

func drawPanel(_ rect: NSRect) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
    panel.setFill()
    path.fill()
    stroke.setStroke()
    path.lineWidth = 2
    path.stroke()
}

let leftPanel = NSRect(x: 68, y: 82, width: 200, height: 176)
let rightPanel = NSRect(x: 390, y: 82, width: 200, height: 176)
drawPanel(leftPanel)
drawPanel(rightPanel)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 294, y: 168))
arrow.line(to: NSPoint(x: 364, y: 168))
arrow.lineWidth = 14
arrow.lineCapStyle = .round
accent.setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 362, y: 190))
arrowHead.line(to: NSPoint(x: 398, y: 168))
arrowHead.line(to: NSPoint(x: 362, y: 146))
arrowHead.close()
accent.setFill()
arrowHead.fill()

drawText(
    "Drag MachOKnife to Applications",
    rect: NSRect(x: 60, y: 300, width: 520, height: 32),
    font: NSFont(name: "Avenir Next Demi Bold", size: 28) ?? .systemFont(ofSize: 28, weight: .semibold),
    color: text
)

drawText(
    "Install the native Mach-O inspection and retag tool by dropping it onto Applications",
    rect: NSRect(x: 72, y: 258, width: 496, height: 22),
    font: NSFont(name: "Avenir Next Regular", size: 14) ?? .systemFont(ofSize: 14, weight: .regular),
    color: subtitle
)

drawText("MachO", rect: NSRect(x: leftPanel.minX, y: leftPanel.maxY - 56, width: leftPanel.width, height: 24), font: .systemFont(ofSize: 26, weight: .bold), color: steel)
drawText("Knife", rect: NSRect(x: leftPanel.minX, y: leftPanel.maxY - 84, width: leftPanel.width, height: 24), font: .systemFont(ofSize: 26, weight: .bold), color: accent)
drawText("Mach-O", rect: NSRect(x: leftPanel.minX, y: leftPanel.minY + 68, width: leftPanel.width, height: 20), font: .systemFont(ofSize: 15, weight: .medium), color: subtitle)
drawText("surgery", rect: NSRect(x: leftPanel.minX, y: leftPanel.minY + 44, width: leftPanel.width, height: 20), font: .systemFont(ofSize: 15, weight: .medium), color: subtitle)

let appsPath = NSBezierPath(roundedRect: NSRect(x: rightPanel.minX + 44, y: rightPanel.minY + 52, width: 112, height: 86), xRadius: 22, yRadius: 22)
NSColor(calibratedRed: 0.86, green: 0.92, blue: 0.98, alpha: 1).setFill()
appsPath.fill()
stroke.setStroke()
appsPath.lineWidth = 2
appsPath.stroke()
drawText("A", rect: NSRect(x: rightPanel.minX, y: rightPanel.minY + 78, width: rightPanel.width, height: 34), font: .systemFont(ofSize: 40, weight: .bold), color: accent)
drawText("Applications", rect: NSRect(x: rightPanel.minX, y: rightPanel.minY + 34, width: rightPanel.width, height: 20), font: .systemFont(ofSize: 15, weight: .medium), color: subtitle)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render png\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT
}

extract_sanitized_entitlements() {
    local source_path="$1"
    local output_path="$2"

    if ! /usr/bin/codesign -d --entitlements :- "$source_path" >"$output_path" 2>/dev/null; then
        rm -f "$output_path"
        return 1
    fi

    /usr/bin/python3 - "$output_path" <<'PY'
import pathlib
import plistlib
import sys

path = pathlib.Path(sys.argv[1])
data = plistlib.loads(path.read_bytes())
data.pop("com.apple.security.get-task-allow", None)
data.pop("application-identifier", None)
data.pop("com.apple.developer.team-identifier", None)
path.write_bytes(plistlib.dumps(data))
PY
}

sign_nested_target() {
    local target_path="$1"
    local identity="$2"
    local entitlements_file

    entitlements_file="$(mktemp "${TMPDIR:-/tmp}/machoknife-sign.XXXXXX")"
    if extract_sanitized_entitlements "$target_path" "$entitlements_file"; then
        /usr/bin/codesign \
            --force \
            --sign "$identity" \
            --timestamp \
            --options runtime \
            --entitlements "$entitlements_file" \
            --preserve-metadata=identifier \
            "$target_path"
    else
        /usr/bin/codesign \
            --force \
            --sign "$identity" \
            --timestamp \
            --options runtime \
            --preserve-metadata=identifier \
            "$target_path"
    fi

    rm -f "$entitlements_file"
}

resign_for_distribution() {
    local app_path="$1"
    local identity="$2"
    local nested_bundle
    local file_path
    local entitlements_file

    entitlements_file="$(mktemp "${TMPDIR:-/tmp}/machoknife-entitlements.XXXXXX")"
    if ! extract_sanitized_entitlements "$app_path" "$entitlements_file"; then
        rm -f "$entitlements_file"
        entitlements_file=""
    fi

    trap '[[ -n "${entitlements_file:-}" ]] && rm -f "$entitlements_file"' RETURN

    while IFS= read -r -d '' file_path; do
        if file "$file_path" | grep -q "Mach-O"; then
            sign_nested_target "$file_path" "$identity"
        fi
    done < <(find "$app_path" -type f -print0)

    while IFS= read -r nested_bundle; do
        [[ -n "$nested_bundle" ]] || continue
        sign_nested_target "$nested_bundle" "$identity"
    done < <(
        find "$app_path" -mindepth 2 \
            \( -name "*.app" -o -name "*.framework" -o -name "*.xpc" -o -name "*.appex" -o -name "*.bundle" \) \
            -print | /usr/bin/awk '{ print length, $0 }' | sort -rn | cut -d" " -f2-
    )

    if [[ -n "$entitlements_file" ]]; then
        /usr/bin/codesign \
            --force \
            --sign "$identity" \
            --timestamp \
            --options runtime \
            --entitlements "$entitlements_file" \
            "$app_path"
    else
        /usr/bin/codesign \
            --force \
            --sign "$identity" \
            --timestamp \
            --options runtime \
            "$app_path"
    fi
}

create_pretty_dmg() {
    local app_path="$1"
    local dmg_path="$2"
    local volume_name="$3"
    local work_dir="$BUILD_DIR/dmg-tmp"
    local staging_dir="$work_dir/staging"
    local background_dir="$staging_dir/.background"
    local background_path="$background_dir/installer-background.png"
    local fsevents_dir="$staging_dir/.fseventsd"
    local rw_dmg_path="$work_dir/${volume_name}.temp.dmg"
    local app_name
    local device
    local attach_output
    local mounted_volume_path
    local mounted_volume_name

    app_name="$(basename "$app_path")"

    rm -rf "$work_dir"
    mkdir -p "$staging_dir" "$background_dir" "$fsevents_dir"
    cp -R "$app_path" "$staging_dir/"
    ln -s /Applications "$staging_dir/Applications"
    generate_dmg_background "$background_path"
    touch "$fsevents_dir/no_log"
    chflags hidden "$background_dir" 2>/dev/null || true
    chflags hidden "$fsevents_dir" 2>/dev/null || true

    hdiutil create -volname "$volume_name" \
        -srcfolder "$staging_dir" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" \
        -ov -format UDRW \
        "$rw_dmg_path"

    attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg_path")"
    device="$(printf '%s\n' "$attach_output" | awk -F '\t' '/\/Volumes\// {print $1; exit}')"
    mounted_volume_path="$(printf '%s\n' "$attach_output" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
    mounted_volume_name="$(basename "$mounted_volume_path")"

    if [[ -z "$device" || -z "$mounted_volume_name" ]]; then
        echo "error: failed to mount temporary DMG" >&2
        echo "$attach_output" >&2
        exit 1
    fi

    chflags hidden "$mounted_volume_path/.background" 2>/dev/null || true
    chflags hidden "$mounted_volume_path/.fseventsd" 2>/dev/null || true

    osascript <<EOF
tell application "Finder"
    tell disk "$mounted_volume_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {220, 120, 860, 540}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:installer-background.png"
        set position of item "$app_name" of container window to {164, 190}
        set position of item "Applications" of container window to {478, 190}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

    sync
    sleep 1
    hdiutil detach "$mounted_volume_path" || hdiutil detach "$device" -force
    hdiutil convert "$rw_dmg_path" -format UDZO -imagekey zlib-level=9 -o "$dmg_path"
    rm -rf "$work_dir"
}

usage() {
    cat <<EOF
Usage:
  ./Scripts/build_dmg.sh [--keychain-profile PROFILE] [--signing-identity IDENTITY] [--no-notarize]

Options:
  --keychain-profile PROFILE   Notarytool keychain profile. Default: $DEFAULT_NOTARY_PROFILE
  --signing-identity IDENTITY  Developer ID Application identity to use
  --no-notarize                Skip notarization
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keychain-profile)
            KEYCHAIN_PROFILE="${2:-}"
            shift 2
            ;;
        --signing-identity)
            SIGNING_IDENTITY="${2:-}"
            shift 2
            ;;
        --no-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_command xcodebuild
require_command codesign
require_command hdiutil
require_command osascript
require_command xcrun

VERSION="$(read_marketing_version)"
if [[ -z "$VERSION" ]]; then
    echo "error: failed to read MARKETING_VERSION from $PBXPROJ" >&2
    exit 1
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(find_developer_id_identity || true)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "error: failed to find a Developer ID Application identity" >&2
    exit 1
fi

DMG_NAME="${APP_NAME}_V_${VERSION}.dmg"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/${APP_NAME}.app"
DMG_PATH="$DMG_OUTPUT_DIR/$DMG_NAME"
VOLUME_NAME="${APP_NAME} V$VERSION"

mkdir -p "$DMG_OUTPUT_DIR"

echo "building $APP_NAME $VERSION"
xcodebuild \
    -project "$APP_PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found: $APP_PATH" >&2
    exit 1
fi

echo "re-signing app with $SIGNING_IDENTITY"
resign_for_distribution "$APP_PATH" "$SIGNING_IDENTITY"
verify_developer_id_signature "$APP_PATH" "$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$DMG_PATH"
echo "creating DMG: $DMG_PATH"
create_pretty_dmg "$APP_PATH" "$DMG_PATH" "$VOLUME_NAME"

if [[ "$SKIP_NOTARIZE" == false ]]; then
    echo "submitting DMG for notarization"
    NOTARY_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait 2>&1)" || true
    echo "$NOTARY_OUTPUT"

    if ! grep -q "status: Accepted" <<<"$NOTARY_OUTPUT"; then
        echo "error: notarization failed" >&2
        exit 1
    fi

    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
else
    echo "skipping notarization"
fi

echo "done: $DMG_PATH"
