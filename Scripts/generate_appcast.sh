#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DEFAULT_OUTPUT_PATH="$PROJECT_DIR/Resources/Updates/appcast.xml"

ARCHIVES=()
OUTPUT_PATH="$DEFAULT_OUTPUT_PATH"
REPO=""
ACCOUNT="$DEFAULT_SPARKLE_ACCOUNT"
NOTES=""
NOTES_FILE=""
BUILD_NUMBER=""
MINIMUM_SYSTEM_VERSION=""

usage() {
    cat <<EOF
Usage:
  ./Scripts/generate_appcast.sh --archive PATH [--archive PATH ...] [--output PATH]
                                [--repo OWNER/REPO] [--account ACCOUNT]
                                [--build-number N] [--minimum-system-version X.Y]
                                [--notes TEXT | --notes-file FILE]

Signs each DMG with Sparkle's EdDSA key and merges one <item> per DMG into the feed.
DMG names must look like ${APP_NAME}_V_<version>_<arch>.dmg (arch: arm64 / x86_64).

Items of the same version are written arm64 first, carrying
<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>, then x86_64.
Sparkle drops the arm64 item on Intel Macs and, for equal versions, picks the first
item on Apple Silicon, so one feed serves both architectures (including older
universal builds that still read this feed).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            ARCHIVES+=("${2:-}")
            shift 2
            ;;
        --output)
            OUTPUT_PATH="${2:-}"
            shift 2
            ;;
        --repo)
            REPO="${2:-}"
            shift 2
            ;;
        --account)
            ACCOUNT="${2:-}"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="${2:-}"
            shift 2
            ;;
        --minimum-system-version)
            MINIMUM_SYSTEM_VERSION="${2:-}"
            shift 2
            ;;
        --notes)
            NOTES="${2:-}"
            shift 2
            ;;
        --notes-file)
            NOTES_FILE="${2:-}"
            shift 2
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

if [[ -n "$NOTES" && -n "$NOTES_FILE" ]]; then
    echo "error: --notes and --notes-file are mutually exclusive" >&2
    exit 1
fi

if [[ ${#ARCHIVES[@]} -eq 0 ]]; then
    echo "error: at least one --archive is required" >&2
    usage >&2
    exit 1
fi

require_command /usr/bin/python3

OUTPUT_PATH="$(expand_path "$OUTPUT_PATH")"

if [[ -n "$NOTES_FILE" ]]; then
    NOTES_FILE="$(resolve_existing_path "$NOTES_FILE")"
    if [[ -z "$NOTES_FILE" || ! -f "$NOTES_FILE" ]]; then
        echo "error: notes file not found" >&2
        exit 1
    fi
    NOTES="$(<"$NOTES_FILE")"
fi

if [[ -z "$REPO" ]]; then
    REPO="$(detect_repo)"
fi

if ! [[ "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
    echo "error: invalid repo format: $REPO" >&2
    exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(read_build_number)"
fi

if [[ -z "$MINIMUM_SYSTEM_VERSION" ]]; then
    # 测试 target 的部署版本可能更高，取工程中最低的部署版本作为应用的最低系统要求
    MINIMUM_SYSTEM_VERSION="$(grep "MACOSX_DEPLOYMENT_TARGET" "$PBXPROJ" | sed 's/.*= *\([^;]*\);/\1/' | tr -d ' "' | sort -V | head -1)"
fi

if [[ -z "$BUILD_NUMBER" || -z "$MINIMUM_SYSTEM_VERSION" ]]; then
    echo "error: failed to resolve build number or minimum system version" >&2
    exit 1
fi

GENERATE_KEYS_TOOL="$(ensure_sparkle_tool generate_keys)"
SIGN_UPDATE_TOOL="$(ensure_sparkle_tool sign_update)"

if ! "$GENERATE_KEYS_TOOL" --account "$ACCOUNT" -p >/dev/null 2>&1; then
    echo "error: Sparkle key is missing for account $ACCOUNT" >&2
    echo "run: $GENERATE_KEYS_TOOL --account $ACCOUNT" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/machoknife-appcast.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

TMP_PRIVATE_KEY="$TMP_DIR/private_ed25519.key"
"$GENERATE_KEYS_TOOL" --account "$ACCOUNT" -x "$TMP_PRIVATE_KEY"

# 每行一个安装包：<version>\t<arch>\t<file name>\t<length>\t<signature>
ENTRIES_FILE="$TMP_DIR/entries.tsv"
: >"$ENTRIES_FILE"

for archive in "${ARCHIVES[@]}"; do
    archive_path="$(resolve_existing_path "$archive")"
    if [[ -z "$archive_path" || ! -f "$archive_path" ]]; then
        echo "error: archive not found: $archive" >&2
        exit 1
    fi

    if ! parsed="$(parse_dmg_file_name "$archive_path")"; then
        echo "error: unexpected DMG name: $(basename "$archive_path")" >&2
        exit 1
    fi
    read -r version arch <<<"$parsed"

    # sign_update 输出形如：sparkle:edSignature="..." length="..."
    sign_output="$("$SIGN_UPDATE_TOOL" --ed-key-file "$TMP_PRIVATE_KEY" "$archive_path")"
    signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$sign_output")"
    length="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$sign_output")"

    if [[ -z "$signature" || -z "$length" ]]; then
        echo "error: failed to sign $archive_path" >&2
        echo "$sign_output" >&2
        exit 1
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$version" "$arch" "$(basename "$archive_path")" "$length" "$signature" >>"$ENTRIES_FILE"
    echo "signed $(basename "$archive_path") ($arch, $length bytes)"
done

mkdir -p "$(dirname "$OUTPUT_PATH")"

APPCAST_NOTES="$NOTES" /usr/bin/python3 - "$OUTPUT_PATH" "$ENTRIES_FILE" "$REPO" "$APP_NAME" "$BUILD_NUMBER" "$MINIMUM_SYSTEM_VERSION" <<'PY'
import email.utils
import os
import pathlib
import sys
import urllib.parse
import xml.etree.ElementTree as ET

output_path, entries_path, repo, app_name, build_number, minimum_system_version = sys.argv[1:7]
notes = os.environ.get("APPCAST_NOTES", "").strip()

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle_ns)


def sparkle(tag):
    return f"{{{sparkle_ns}}}{tag}"


output = pathlib.Path(output_path)
if output.exists():
    tree = ET.parse(output)
    root = tree.getroot()
else:
    root = ET.Element("rss", {"version": "2.0"})
    tree = ET.ElementTree(root)

channel = root.find("channel")
if channel is None:
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = app_name

# 同版本 arm64 必须排在 x86_64 之前：Sparkle 对版本相同的条目取第一个可用条目
arch_order = {"arm64": 0, "x86_64": 1, "universal": 2}
entries = []
for line in pathlib.Path(entries_path).read_text().splitlines():
    if not line.strip():
        continue
    version, arch, file_name, length, signature = line.split("\t")
    entries.append((version, arch, file_name, length, signature))
entries.sort(key=lambda entry: arch_order.get(entry[1], 99))

new_versions = {entry[0] for entry in entries}
if len(new_versions) != 1:
    raise SystemExit(f"all archives must share one version, got: {sorted(new_versions)}")

# 移除同版本的旧条目，便于重复执行（例如重新上传某个架构的安装包）
for item in list(channel.findall("item")):
    short_version = item.find(sparkle("shortVersionString"))
    if short_version is not None and (short_version.text or "").strip() in new_versions:
        channel.remove(item)

existing_items = channel.findall("item")
insert_index = list(channel).index(existing_items[0]) if existing_items else len(channel)
pub_date = email.utils.formatdate(localtime=True)

for offset, (version, arch, file_name, length, signature) in enumerate(entries):
    tag = f"v{version}"
    quoted_tag = urllib.parse.quote(tag, safe="")
    quoted_file = urllib.parse.quote(file_name, safe="")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = version
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, "link").text = f"https://github.com/{repo}/releases/tag/{quoted_tag}"
    ET.SubElement(item, sparkle("version")).text = build_number
    ET.SubElement(item, sparkle("shortVersionString")).text = version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = minimum_system_version
    if arch == "arm64":
        ET.SubElement(item, sparkle("hardwareRequirements")).text = "arm64"
    if notes:
        description = ET.SubElement(item, "description", {sparkle("format"): "markdown"})
        description.text = notes + "\n"
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/{repo}/releases/download/{quoted_tag}/{quoted_file}",
        "length": length,
        "type": "application/octet-stream",
        sparkle("edSignature"): signature,
    })
    channel.insert(insert_index + offset, item)

ET.indent(tree, space="    ")
tree.write(output_path, encoding="utf-8", xml_declaration=True)
PY

echo "appcast written to $OUTPUT_PATH"
