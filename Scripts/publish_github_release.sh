#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DEFAULT_DMG_DIR="$PROJECT_DIR/build/dmg"
GITHUB_API_BASE="https://api.github.com"

DMG_PATH=""
REPO=""
TAG=""
TITLE=""
NOTES=""
NOTES_FILE=""
GENERATE_NOTES=false
DRAFT=false
PRERELEASE=false

usage() {
    cat <<EOF
Usage:
  ./Scripts/publish_github_release.sh [--dmg PATH] [--repo OWNER/REPO] [--tag TAG]
                                      [--title TITLE] [--notes TEXT | --notes-file FILE | --generate-notes]
                                      [--draft] [--prerelease]
EOF
}

find_latest_dmg() {
    local latest_path=""
    local latest_mtime=0
    local file_path
    local file_mtime

    shopt -s nullglob
    for file_path in "$DEFAULT_DMG_DIR"/${APP_NAME}_V_*.dmg; do
        [[ -f "$file_path" ]] || continue
        file_mtime="$(stat -f '%m' "$file_path")"
        if [[ -z "$latest_path" || "$file_mtime" -gt "$latest_mtime" ]]; then
            latest_path="$file_path"
            latest_mtime="$file_mtime"
        fi
    done
    shopt -u nullglob

    printf '%s\n' "$latest_path"
}

infer_version_from_dmg() {
    local dmg_name
    dmg_name="$(basename "$1")"

    if [[ "$dmg_name" =~ ^${APP_NAME}_V_(.+)\.dmg$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

resolve_github_token() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        printf '%s\n' "$GITHUB_TOKEN"
        return 0
    fi

    if [[ -n "${GH_TOKEN:-}" ]]; then
        printf '%s\n' "$GH_TOKEN"
        return 0
    fi

    local credential_output
    local password

    credential_output="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null || true)"
    password="$(printf '%s\n' "$credential_output" | sed -n 's/^password=//p' | head -1)"

    if [[ -n "$password" ]]; then
        printf '%s\n' "$password"
        return 0
    fi

    return 1
}

url_encode() {
    /usr/bin/python3 - "$1" <<'PY'
import sys
import urllib.parse

print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

json_get() {
    local path="$1"

    /usr/bin/python3 - "$path" <<'PY'
import json
import sys

path = [part for part in sys.argv[1].split('.') if part]
value = json.load(sys.stdin)

for part in path:
    if isinstance(value, dict):
        value = value.get(part)
    elif isinstance(value, list):
        try:
            index = int(part)
        except ValueError:
            value = None
            break
        value = value[index] if 0 <= index < len(value) else None
    else:
        value = None
        break

if value is None:
    raise SystemExit(1)

if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

json_find_release_asset_id() {
    local asset_name="$1"

    /usr/bin/python3 - "$asset_name" <<'PY'
import json
import sys

asset_name = sys.argv[1]
assets = json.load(sys.stdin).get("assets") or []

for asset in assets:
    if asset.get("name") == asset_name:
        asset_id = asset.get("id")
        if asset_id is not None:
            print(asset_id)
        break
PY
}

github_api_request() {
    local method="$1"
    local url="$2"
    shift 2

    curl -fsSL \
        -X "$method" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_API_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$@" \
        "$url"
}

github_create_release_payload() {
    local tag="$1"
    local title="$2"
    local draft="$3"
    local prerelease="$4"
    local generate_notes="$5"

    RELEASE_NOTES_CONTENT="${RELEASE_NOTES_CONTENT:-}" /usr/bin/python3 - "$tag" "$title" "$draft" "$prerelease" "$generate_notes" <<'PY'
import json
import os
import sys

tag, title, draft, prerelease, generate_notes = sys.argv[1:6]
payload = {
    "tag_name": tag,
    "name": title,
    "draft": draft == "true",
    "prerelease": prerelease == "true",
}

if generate_notes == "true":
    payload["generate_release_notes"] = True
else:
    payload["body"] = os.environ.get("RELEASE_NOTES_CONTENT", "")

print(json.dumps(payload))
PY
}

publish_with_github_api() {
    local dmg_name
    local release_json
    local release_id
    local release_url
    local release_body
    local asset_id
    local notes_content
    local payload
    local upload_name
    local encoded_name
    local upload_url

    GITHUB_API_TOKEN="$(resolve_github_token)"
    if [[ -z "$GITHUB_API_TOKEN" ]]; then
        echo "error: missing GitHub credentials" >&2
        exit 1
    fi

    dmg_name="$(basename "$DMG_PATH")"

    if release_json="$(github_api_request GET "$GITHUB_API_BASE/repos/$REPO/releases/tags/$TAG" 2>/dev/null)"; then
        echo "release exists; replacing asset"
    else
        echo "creating release"

        if [[ "$GENERATE_NOTES" == true ]]; then
            RELEASE_NOTES_CONTENT=""
        elif [[ -n "$NOTES_FILE" ]]; then
            RELEASE_NOTES_CONTENT="$(<"$NOTES_FILE")"
        else
            RELEASE_NOTES_CONTENT="${NOTES:-Release $TAG}"
        fi

        payload="$(github_create_release_payload "$TAG" "$TITLE" "$DRAFT" "$PRERELEASE" "$GENERATE_NOTES")"
        release_json="$(github_api_request POST "$GITHUB_API_BASE/repos/$REPO/releases" \
            -H "Content-Type: application/json" \
            -d "$payload")"
    fi

    release_id="$(printf '%s' "$release_json" | json_get "id")"
    release_url="$(printf '%s' "$release_json" | json_get "html_url")"
    release_body="$(printf '%s' "$release_json" | json_get "body" 2>/dev/null || true)"

    asset_id="$(printf '%s' "$release_json" | json_find_release_asset_id "$dmg_name")"
    if [[ -n "$asset_id" ]]; then
        github_api_request DELETE "$GITHUB_API_BASE/repos/$REPO/releases/assets/$asset_id" >/dev/null
    fi

    upload_name="$dmg_name"
    encoded_name="$(url_encode "$upload_name")"
    upload_url="https://uploads.github.com/repos/$REPO/releases/$release_id/assets?name=$encoded_name"

    github_api_request POST "$upload_url" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$DMG_PATH" >/dev/null

    echo "published: $release_url"

    APPCAST_NOTES="$release_body"
    if [[ -z "$APPCAST_NOTES" ]]; then
        notes_content="$(github_api_request GET "$GITHUB_API_BASE/repos/$REPO/releases/tags/$TAG")"
        APPCAST_NOTES="$(printf '%s' "$notes_content" | json_get "body" 2>/dev/null || true)"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)
            DMG_PATH="${2:-}"
            shift 2
            ;;
        --repo)
            REPO="${2:-}"
            shift 2
            ;;
        --tag)
            TAG="${2:-}"
            shift 2
            ;;
        --title)
            TITLE="${2:-}"
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
        --generate-notes)
            GENERATE_NOTES=true
            shift
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --prerelease)
            PRERELEASE=true
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

if [[ -n "$NOTES" && -n "$NOTES_FILE" ]]; then
    echo "error: --notes and --notes-file are mutually exclusive" >&2
    exit 1
fi

if [[ "$GENERATE_NOTES" == true && ( -n "$NOTES" || -n "$NOTES_FILE" ) ]]; then
    echo "error: --generate-notes cannot be combined with --notes or --notes-file" >&2
    exit 1
fi

require_command git

if gh auth status >/dev/null 2>&1; then
    HAS_GH=true
else
    HAS_GH=false
fi

if [[ -n "$DMG_PATH" ]]; then
    DMG_PATH="$(resolve_existing_path "$DMG_PATH")"
else
    DMG_PATH="$(find_latest_dmg)"
fi

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
    echo "error: DMG not found" >&2
    exit 1
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

VERSION="$(infer_version_from_dmg "$DMG_PATH" || true)"
if [[ -z "$VERSION" ]]; then
    VERSION="$(read_marketing_version)"
fi
if [[ -z "$VERSION" ]]; then
    echo "error: failed to infer version" >&2
    exit 1
fi

if [[ -z "$TAG" ]]; then
    TAG="v$VERSION"
fi

if [[ -z "$TITLE" ]]; then
    TITLE="$APP_NAME v$VERSION"
fi

echo "repo: $REPO"
echo "tag: $TAG"
echo "title: $TITLE"
echo "dmg: $DMG_PATH"

if [[ "$HAS_GH" == true ]]; then
    if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
        echo "release exists; uploading asset"
        gh release upload "$TAG" "$DMG_PATH" -R "$REPO" --clobber

        if [[ -n "$NOTES_FILE" ]]; then
            gh release edit "$TAG" -R "$REPO" --notes-file "$NOTES_FILE"
        elif [[ -n "$NOTES" ]]; then
            gh release edit "$TAG" -R "$REPO" --notes "$NOTES"
        fi
    else
        echo "creating release"
        create_args=(release create "$TAG" "$DMG_PATH" -R "$REPO" --title "$TITLE")

        if [[ "$GENERATE_NOTES" == true ]]; then
            create_args+=(--generate-notes)
        elif [[ -n "$NOTES_FILE" ]]; then
            create_args+=(--notes-file "$NOTES_FILE")
        else
            create_args+=(--notes "${NOTES:-Release $TAG}")
        fi

        if [[ "$DRAFT" == true ]]; then
            create_args+=(--draft)
        fi

        if [[ "$PRERELEASE" == true ]]; then
            create_args+=(--prerelease)
        fi

        gh "${create_args[@]}"
    fi

    APPCAST_NOTES="$(gh release view "$TAG" -R "$REPO" --json body --jq '.body // ""' 2>/dev/null || true)"
else
    publish_with_github_api
fi

APPCAST_ARGS=(--repo "$REPO" --archive "$DMG_PATH")
if [[ -n "${APPCAST_NOTES:-}" ]]; then
    APPCAST_ARGS+=(--notes "$APPCAST_NOTES")
fi

"$PROJECT_DIR/Scripts/generate_appcast.sh" "${APPCAST_ARGS[@]}"

echo "appcast updated: $PROJECT_DIR/Resources/Updates/appcast.xml"
