#!/bin/sh

set -eu

EVENT=${1:-}
INPUT_REF=${2:-}
INPUT_RELEASE_TAG=${3:-}
SKIP_RELEASE=${4:-false}
OUTPUT_FILE=${GITHUB_OUTPUT:-/dev/stdout}
DEFAULT_GHOSTTY_REF=${DEFAULT_GHOSTTY_REF:-main}

next_release_tag() {
    latest=$(git tag --list '[0-9]*.[0-9]*.[0-9]*' --sort='version:refname' | tail -n 1)
    if [ -z "$latest" ]; then
        echo "0.0.1"
        return
    fi

    IFS=. read -r major minor patch <<EOF
$latest
EOF
    echo "$major.$minor.$((patch + 1))"
}

write_outputs() {
    {
        echo "build_needed=$1"
        echo "build_ref=$2"
        echo "resolved_sha=$3"
        echo "release_tag=$4"
        echo "do_release=$5"
    } >> "$OUTPUT_FILE"
}

if [ "$EVENT" = "schedule" ]; then
    SKIP_RELEASE=false
elif [ "$EVENT" != "workflow_dispatch" ]; then
    SKIP_RELEASE=true
fi

if [ -n "$INPUT_REF" ]; then
    BUILD_REF=$INPUT_REF
else
    BUILD_REF=$DEFAULT_GHOSTTY_REF
fi

if [ -z "$BUILD_REF" ]; then
    write_outputs false "" "" "" false
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
    RELEASE_TAG=$(next_release_tag)
fi

if [ "$SKIP_RELEASE" = "true" ]; then
    DO_RELEASE=false
else
    DO_RELEASE=true
fi

BUILD_NEEDED=true
if [ "$DO_RELEASE" = "true" ]; then
    git fetch --tags origin
    if git rev-parse "$RELEASE_TAG" >/dev/null 2>&1; then
        echo "[*] release $RELEASE_TAG already exists, skipping"
        BUILD_NEEDED=false
    fi
fi

write_outputs "$BUILD_NEEDED" "$BUILD_REF" "$RESOLVED_SHA" "$RELEASE_TAG" "$DO_RELEASE"
