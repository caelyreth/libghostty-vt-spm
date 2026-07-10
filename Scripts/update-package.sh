#!/bin/sh

set -eu

cd "$(dirname "$0")/.."

XCFRAMEWORK_ZIP=${1:-}
RELEASE_VERSION=${2:-}
DOWNLOAD_URL=${3:-}

if [ -z "$XCFRAMEWORK_ZIP" ] || [ -z "$RELEASE_VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Usage: $0 <xcframework_zip> <release_version> <download_url>"
    exit 1
fi

if [ ! -f "$XCFRAMEWORK_ZIP" ]; then
    echo "[!] xcframework zip not found: $XCFRAMEWORK_ZIP"
    exit 1
fi

if ! echo "$RELEASE_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "[!] release_version must be a semantic version like 1.2.0: $RELEASE_VERSION"
    exit 1
fi

DOWNLOAD_URL_SUFFIX="/$RELEASE_VERSION/GhosttyVtPrebuilt.xcframework.zip"
case "$DOWNLOAD_URL" in
    *"$DOWNLOAD_URL_SUFFIX")
        DOWNLOAD_URL_PREFIX=${DOWNLOAD_URL%"$DOWNLOAD_URL_SUFFIX"}
        ;;
    *)
        echo "[!] download_url must end with $DOWNLOAD_URL_SUFFIX"
        exit 1
        ;;
esac

CHECKSUM=$(swift package compute-checksum "$XCFRAMEWORK_ZIP")
sed \
    -e "s|__DOWNLOAD_URL_PREFIX__|$DOWNLOAD_URL_PREFIX|g" \
    -e "s|__CHECKSUM__|$CHECKSUM|g" \
    -e "s|__RELEASE_VERSION__|$RELEASE_VERSION|g" \
    -e "s|__BINARY_ARTIFACT_VERSION__|$RELEASE_VERSION|g" \
    Scripts/templates/Package.swift.template > Package.swift

echo "[*] package checksum: $CHECKSUM"
