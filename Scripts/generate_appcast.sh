#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DEFAULT_ARCHIVES_DIR="$PROJECT_DIR/build/appcast-archives"
DEFAULT_OUTPUT_PATH="$PROJECT_DIR/Resources/Updates/appcast.xml"

ARCHIVE_PATH=""
ARCHIVES_DIR="$DEFAULT_ARCHIVES_DIR"
OUTPUT_PATH="$DEFAULT_OUTPUT_PATH"
REPO=""
ACCOUNT="$DEFAULT_SPARKLE_ACCOUNT"
NOTES=""
NOTES_FILE=""

usage() {
    cat <<EOF
Usage:
  ./Scripts/generate_appcast.sh [--archive PATH] [--archives-dir DIR] [--output PATH]
                                [--repo OWNER/REPO] [--account ACCOUNT]
                                [--notes TEXT | --notes-file FILE]
EOF
}

copy_release_notes() {
    local archive_dest="$1"
    local base_path="${archive_dest%.*}"

    if [[ -n "$NOTES_FILE" ]]; then
        local extension="${NOTES_FILE##*.}"
        cp "$NOTES_FILE" "${base_path}.${extension}"
    elif [[ -n "$NOTES" ]]; then
        printf '%s\n' "$NOTES" > "${base_path}.md"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            ARCHIVE_PATH="${2:-}"
            shift 2
            ;;
        --archives-dir)
            ARCHIVES_DIR="${2:-}"
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

require_command /usr/bin/python3

ARCHIVES_DIR="$(expand_path "$ARCHIVES_DIR")"
OUTPUT_PATH="$(expand_path "$OUTPUT_PATH")"

if [[ -n "$ARCHIVE_PATH" ]]; then
    ARCHIVE_PATH="$(resolve_existing_path "$ARCHIVE_PATH")"
    if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
        echo "error: archive not found" >&2
        exit 1
    fi
fi

if [[ -n "$NOTES_FILE" ]]; then
    NOTES_FILE="$(resolve_existing_path "$NOTES_FILE")"
    if [[ -z "$NOTES_FILE" || ! -f "$NOTES_FILE" ]]; then
        echo "error: notes file not found" >&2
        exit 1
    fi
fi

if [[ -z "$REPO" ]]; then
    REPO="$(detect_repo)"
fi

if ! [[ "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
    echo "error: invalid repo format: $REPO" >&2
    exit 1
fi

GENERATE_KEYS_TOOL="$(ensure_sparkle_tool generate_keys)"
GENERATE_APPCAST_TOOL="$(ensure_sparkle_tool generate_appcast)"

if ! "$GENERATE_KEYS_TOOL" --account "$ACCOUNT" -p >/dev/null 2>&1; then
    echo "error: Sparkle key is missing for account $ACCOUNT" >&2
    echo "run: $GENERATE_KEYS_TOOL --account $ACCOUNT" >&2
    exit 1
fi

mkdir -p "$ARCHIVES_DIR" "$(dirname "$OUTPUT_PATH")"

if [[ -n "$ARCHIVE_PATH" ]]; then
    archive_dest="$ARCHIVES_DIR/$(basename "$ARCHIVE_PATH")"
    cp "$ARCHIVE_PATH" "$archive_dest"
    copy_release_notes "$archive_dest"
fi

shopt -s nullglob
archives=( "$ARCHIVES_DIR"/*.dmg )
shopt -u nullglob

if [[ ${#archives[@]} -eq 0 ]]; then
    echo "error: no DMGs found in $ARCHIVES_DIR" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/machoknife-appcast.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$ARCHIVES_DIR"/*.dmg "$TMP_DIR/"
for notes_path in "$ARCHIVES_DIR"/*.md "$ARCHIVES_DIR"/*.txt "$ARCHIVES_DIR"/*.html; do
    [[ -e "$notes_path" ]] || continue
    cp "$notes_path" "$TMP_DIR/"
done

TMP_APPCAST="$TMP_DIR/appcast.xml"
TMP_PRIVATE_KEY="$TMP_DIR/private_ed25519.key"
"$GENERATE_KEYS_TOOL" --account "$ACCOUNT" -x "$TMP_PRIVATE_KEY"
"$GENERATE_APPCAST_TOOL" \
    --account "$ACCOUNT" \
    --ed-key-file "$TMP_PRIVATE_KEY" \
    --embed-release-notes \
    --link "https://github.com/$REPO" \
    -o "$TMP_APPCAST" \
    "$TMP_DIR"

/usr/bin/python3 - "$TMP_APPCAST" "$OUTPUT_PATH" "$REPO" "$APP_NAME" <<'PY'
import pathlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET

input_path, output_path, repo, app_name = sys.argv[1:5]
sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
dc_ns = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", sparkle_ns)
ET.register_namespace("dc", dc_ns)

tree = ET.parse(input_path)
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    raise SystemExit("missing channel node")

def find_or_create(parent, tag):
    node = parent.find(tag)
    if node is None:
        node = ET.SubElement(parent, tag)
    return node

title_node = find_or_create(channel, "title")
if not (title_node.text or "").strip():
    title_node.text = f"{app_name} Updates"

link_node = find_or_create(channel, "link")
link_node.text = f"https://github.com/{repo}"

description_node = find_or_create(channel, "description")
if not (description_node.text or "").strip():
    description_node.text = f"{app_name} release feed."

language_node = find_or_create(channel, "language")
if not (language_node.text or "").strip():
    language_node.text = "en"

pattern = re.compile(rf"{re.escape(app_name)}_V_(.+)\.dmg$")

for item in channel.findall("item"):
    enclosure = item.find("enclosure")
    if enclosure is None:
        continue

    raw_url = enclosure.attrib.get("url", "")
    parsed_path = urllib.parse.urlparse(raw_url).path
    filename = pathlib.PurePosixPath(parsed_path).name or pathlib.Path(raw_url).name
    if not filename:
        continue

    match = pattern.match(filename)
    version = match.group(1) if match else None

    if version is None:
        short_version = item.find(f"{{{sparkle_ns}}}shortVersionString")
        version = (short_version.text or "").strip() if short_version is not None else ""

    if not version:
        sparkle_version = item.find(f"{{{sparkle_ns}}}version")
        version = (sparkle_version.text or "").strip() if sparkle_version is not None else ""

    if not version:
        raise SystemExit(f"failed to infer version for {filename}")

    version = version.lstrip("vV")
    tag = f"v{version}"
    quoted_tag = urllib.parse.quote(tag, safe="")
    quoted_file = urllib.parse.quote(filename, safe="")
    release_url = f"https://github.com/{repo}/releases/tag/{quoted_tag}"
    download_url = f"https://github.com/{repo}/releases/download/{quoted_tag}/{quoted_file}"

    enclosure.set("url", download_url)
    find_or_create(item, "link").text = release_url

    for removable_tag in (
        f"{{{sparkle_ns}}}deltas",
        f"{{{sparkle_ns}}}releaseNotesLink",
        f"{{{sparkle_ns}}}fullReleaseNotesLink",
    ):
        node = item.find(removable_tag)
        if node is not None:
            item.remove(node)

ET.indent(tree, space="    ")
tree.write(output_path, encoding="utf-8", xml_declaration=True)
PY

echo "appcast written to $OUTPUT_PATH"
