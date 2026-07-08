#!/bin/sh

set -eu

cd "$(dirname "$0")/.."

XCFRAMEWORK_ZIP=${1:-}
DOWNLOAD_URL=${2:-}

if [ -z "$XCFRAMEWORK_ZIP" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Usage: $0 <xcframework_zip> <download_url>"
    exit 1
fi

if [ ! -f "$XCFRAMEWORK_ZIP" ]; then
    echo "[!] xcframework zip not found: $XCFRAMEWORK_ZIP"
    exit 1
fi

CHECKSUM=$(swift package compute-checksum "$XCFRAMEWORK_ZIP")
sed \
    -e "s|__DOWNLOAD_URL__|$DOWNLOAD_URL|g" \
    -e "s|__CHECKSUM__|$CHECKSUM|g" \
    Scripts/templates/Package.swift.template > Package.swift

echo "[*] package checksum: $CHECKSUM"
