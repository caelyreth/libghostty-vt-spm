#!/bin/sh

set -eu

EVENT=${1:-}
INPUT_REF=${2:-}
INPUT_RELEASE_TAG=${3:-}
SKIP_RELEASE=${4:-false}
OUTPUT_FILE=${GITHUB_OUTPUT:-/dev/stdout}

if [ "$EVENT" = "schedule" ]; then
    SKIP_RELEASE=false
elif [ "$EVENT" != "workflow_dispatch" ]; then
    SKIP_RELEASE=true
fi

if [ -n "$INPUT_REF" ]; then
    BUILD_REF=$INPUT_REF
else
    BUILD_REF=$(
        gh api "repos/ghostty-org/ghostty/tags?per_page=100" --paginate --jq '.[].name' |
            python3 -c 'import re, sys; tags = [line.strip() for line in sys.stdin if re.fullmatch(r"v?\d+\.\d+\.\d+", line.strip())]; print(max(tags, key=lambda tag: tuple(int(part) for part in (tag[1:] if tag.startswith("v") else tag).split("."))), end="")'
    )
fi

if [ -z "$BUILD_REF" ]; then
    {
        echo "build_needed=false"
        echo "build_ref="
        echo "resolved_sha="
        echo "release_tag="
        echo "storage_release_tag="
        echo "do_release=false"
    } >> "$OUTPUT_FILE"
    exit 0
fi

RESOLVED_SHA=$(gh api "repos/ghostty-org/ghostty/commits/$BUILD_REF" --jq '.sha')

if [ -n "$INPUT_RELEASE_TAG" ]; then
    if ! echo "$INPUT_RELEASE_TAG" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "[!] release_tag must be a semantic version like 1.2.0: $INPUT_RELEASE_TAG"
        exit 1
    fi
    RELEASE_TAG=$INPUT_RELEASE_TAG
else
    RELEASE_TAG=$(
        git tag --list |
            python3 -c 'import re, sys; versions = [tuple(int(part) for part in tag.split(".")) for tag in (line.strip() for line in sys.stdin) if re.fullmatch(r"\d+\.\d+\.\d+", tag)]; major, minor, patch = max(versions) if versions else (0, 0, 0); print(f"{major}.{minor}.{patch + 1}", end="")'
    )
fi

STORAGE_RELEASE_TAG="storage.$RELEASE_TAG"

if [ "$SKIP_RELEASE" = "true" ]; then
    DO_RELEASE=false
else
    DO_RELEASE=true
fi

BUILD_NEEDED=true
if [ "$DO_RELEASE" = "true" ]; then
    git fetch --tags origin
    if git rev-parse "$STORAGE_RELEASE_TAG" >/dev/null 2>&1; then
        echo "[*] release $STORAGE_RELEASE_TAG already exists, skipping"
        BUILD_NEEDED=false
    fi
fi

{
    echo "build_needed=$BUILD_NEEDED"
    echo "build_ref=$BUILD_REF"
    echo "resolved_sha=$RESOLVED_SHA"
    echo "release_tag=$RELEASE_TAG"
    echo "storage_release_tag=$STORAGE_RELEASE_TAG"
    echo "do_release=$DO_RELEASE"
} >> "$OUTPUT_FILE"
