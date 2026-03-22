#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="MachOKnife"
SCHEME="MachOKnife"
APP_PROJECT="$PROJECT_DIR/MachOKnife.xcodeproj"
APP_WORKSPACE="$PROJECT_DIR/MachOKnife.xcworkspace"
PBXPROJ="$APP_PROJECT/project.pbxproj"
SPARKLE_DERIVED_DATA="$PROJECT_DIR/build/SparkleTools"
DEFAULT_REPO="VanJay/MachOKnife"
DEFAULT_SPARKLE_ACCOUNT="cn.vanjay.MachOKnife.sparkle"
DEFAULT_NOTARY_PROFILE="vanjay_mac_stapler"

if [[ -d "$APP_WORKSPACE" ]]; then
    XCODE_APP_CONTAINER_ARGS=(-workspace "$APP_WORKSPACE")
else
    XCODE_APP_CONTAINER_ARGS=(-project "$APP_PROJECT")
fi

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "error: missing command: $command_name" >&2
        exit 1
    fi
}

expand_path() {
    local input_path="$1"
    local candidate="${input_path/#\~/$HOME}"

    if [[ "$candidate" = /* ]]; then
        printf '%s\n' "$candidate"
    else
        printf '%s\n' "$PROJECT_DIR/$candidate"
    fi
}

resolve_existing_path() {
    local candidate
    candidate="$(expand_path "$1")"

    if [[ -e "$candidate" ]]; then
        printf '%s\n' "$candidate"
    fi
}

read_pbxproj_setting() {
    local key="$1"
    if [[ ! -f "$PBXPROJ" ]]; then
        return 1
    fi

    grep -m1 "$key" "$PBXPROJ" | sed "s/.*$key = \([^;]*\);/\1/" | tr -d ' "'
}

read_marketing_version() {
    read_pbxproj_setting "MARKETING_VERSION"
}

read_build_number() {
    read_pbxproj_setting "CURRENT_PROJECT_VERSION"
}

read_development_team() {
    read_pbxproj_setting "DEVELOPMENT_TEAM"
}

extract_github_repo_from_url() {
    local url="$1"

    if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?/?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi

    if [[ "$url" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi

    if [[ "$url" =~ ^ssh://git@github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
        printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        return 0
    fi

    return 1
}

detect_repo() {
    local repo_url

    if repo_url="$(git remote get-url origin 2>/dev/null)"; then
        extract_github_repo_from_url "$repo_url" && return 0
    fi

    while IFS=$'\t' read -r _remote_name candidate_url; do
        extract_github_repo_from_url "$candidate_url" && return 0
    done < <(git remote -v | awk '$3=="(push)" {print $1 "\t" $2}' | awk '!seen[$1]++')

    printf '%s\n' "$DEFAULT_REPO"
}

resolve_package_dependencies() {
    require_command xcodebuild
    xcodebuild "${XCODE_APP_CONTAINER_ARGS[@]}" -resolvePackageDependencies >/dev/null
}

find_sparkle_checkout_dir() {
    if [[ -n "${SPARKLE_CHECKOUT_DIR:-}" && -d "$SPARKLE_CHECKOUT_DIR/Sparkle.xcodeproj" ]]; then
        printf '%s\n' "$SPARKLE_CHECKOUT_DIR"
        return 0
    fi

    local candidate
    while IFS= read -r candidate; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/SourcePackages/checkouts/Sparkle' -type d 2>/dev/null | sort -r)

    resolve_package_dependencies

    while IFS= read -r candidate; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/SourcePackages/checkouts/Sparkle' -type d 2>/dev/null | sort -r)

    return 1
}

ensure_sparkle_tool() {
    local tool_name="$1"
    local tool_path="$SPARKLE_DERIVED_DATA/Build/Products/Release/$tool_name"
    local sparkle_checkout
    local sparkle_project

    if [[ -x "$tool_path" ]]; then
        printf '%s\n' "$tool_path"
        return 0
    fi

    sparkle_checkout="$(find_sparkle_checkout_dir)"
    sparkle_project="$sparkle_checkout/Sparkle.xcodeproj"

    if [[ ! -d "$sparkle_project" ]]; then
        echo "error: Sparkle checkout not found" >&2
        exit 1
    fi

    mkdir -p "$PROJECT_DIR/build"

    echo "building Sparkle tool: $tool_name" >&2
    xcodebuild \
        -project "$sparkle_project" \
        -scheme "$tool_name" \
        -configuration Release \
        -derivedDataPath "$SPARKLE_DERIVED_DATA" \
        -destination 'generic/platform=macOS' \
        CODE_SIGNING_ALLOWED=NO \
        build >&2

    if [[ ! -x "$tool_path" ]]; then
        echo "error: Sparkle tool not found after build: $tool_path" >&2
        exit 1
    fi

    printf '%s\n' "$tool_path"
}

find_developer_id_identity() {
    local team_id
    local identities
    local matching_identity

    team_id="$(read_development_team)"
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

    if [[ -n "$team_id" ]]; then
        matching_identity="$(printf '%s\n' "$identities" | sed -n "s/.*\"\(Developer ID Application:.*(${team_id})\)\"/\1/p" | head -1)"
        if [[ -n "$matching_identity" ]]; then
            printf '%s\n' "$matching_identity"
            return 0
        fi
    fi

    matching_identity="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
    if [[ -n "$matching_identity" ]]; then
        printf '%s\n' "$matching_identity"
        return 0
    fi

    return 1
}

verify_developer_id_signature() {
    local target_path="$1"
    local target_name="$2"
    local sign_info

    sign_info="$(codesign -dv --verbose=4 "$target_path" 2>&1)"

    if ! grep -q "Authority=Developer ID Application" <<<"$sign_info"; then
        echo "error: $target_name is not signed with Developer ID Application" >&2
        echo "$sign_info" >&2
        exit 1
    fi

    if ! grep -q "Timestamp=" <<<"$sign_info"; then
        echo "error: $target_name signature is missing a secure timestamp" >&2
        echo "$sign_info" >&2
        exit 1
    fi
}
