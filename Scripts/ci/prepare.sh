#!/bin/sh

set -eu

RELEASE=${1:-false}
OUTPUT_FILE=${GITHUB_OUTPUT:-/dev/stdout}
CONFIG_FILE=GhosttyVt.config
MANIFEST_FILE=Package.swift

write_outputs() {
    {
        echo "build_ref=$1"
        echo "release_tag=$2"
        echo "do_release=$3"
    } >> "$OUTPUT_FILE"
}

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[!] missing Ghostty build configuration: $CONFIG_FILE"
    exit 1
fi

BUILD_REF=$(sed -nE 's/^[[:space:]]*ghostty_ref[[:space:]]*=[[:space:]]*"([0-9a-f]{40})"[[:space:]]*(#.*)?$/\1/p' "$CONFIG_FILE")
MATCH_COUNT=$(printf '%s\n' "$BUILD_REF" | grep -c . || true)
if [ "$MATCH_COUNT" -ne 1 ]; then
    echo "[!] $CONFIG_FILE must define exactly one lowercase 40-character ghostty_ref"
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "[!] missing package manifest: $MANIFEST_FILE"
    exit 1
fi

RELEASE_TAG=$(sed -nE 's/^[[:space:]]*let releaseVersion = "([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*$/\1/p' "$MANIFEST_FILE")
MATCH_COUNT=$(printf '%s\n' "$RELEASE_TAG" | grep -c . || true)
if [ "$MATCH_COUNT" -ne 1 ]; then
    echo "[!] $MANIFEST_FILE must define exactly one semantic releaseVersion"
    exit 1
fi

case "$RELEASE" in
    true)
        if [ "${GITHUB_REF_NAME:-main}" != "${DEFAULT_BRANCH:-main}" ]; then
            echo "[!] releases must run from ${DEFAULT_BRANCH:-main}"
            exit 1
        fi

        DO_RELEASE=true
        git fetch --tags origin
        if git rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null; then
            echo "[!] release $RELEASE_TAG already exists; bump releaseVersion in $MANIFEST_FILE"
            exit 1
        fi
        ;;
    false)
        DO_RELEASE=false
        ;;
    *)
        echo "[!] release must be true or false: $RELEASE"
        exit 1
        ;;
esac

write_outputs "$BUILD_REF" "$RELEASE_TAG" "$DO_RELEASE"
