#!/bin/sh

set -eu

cd "$(dirname "$0")/.."

VARIANTS_DIR=${1:-}
OUTPUT_XCFRAMEWORK=${2:-}
OUTPUT_ZIP=${3:-}

if [ -z "$VARIANTS_DIR" ] || [ -z "$OUTPUT_XCFRAMEWORK" ]; then
    echo "Usage: $0 <variants_dir> <output_xcframework> [output_zip]"
    exit 1
fi

if [ ! -d "$VARIANTS_DIR" ]; then
    echo "[!] variants directory not found: $VARIANTS_DIR"
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "[!] xcodebuild not found"
    exit 1
fi

FOUND_VARIANTS=0
set --
for variant in "$VARIANTS_DIR"/*; do
    [ -d "$variant" ] || continue
    [ -f "$variant/lib/libghostty-vt.a" ] || continue

    if [ ! -f "$variant/include/ghostty/vt.h" ] || [ ! -f "$variant/include/module.modulemap" ]; then
        echo "[!] incomplete headers in $variant"
        exit 1
    fi

    set -- "$@" -library "$variant/lib/libghostty-vt.a" -headers "$variant/include"
    FOUND_VARIANTS=$((FOUND_VARIANTS + 1))
done

if [ "$FOUND_VARIANTS" -eq 0 ]; then
    echo "[!] no variants found in $VARIANTS_DIR"
    exit 1
fi

rm -rf "$OUTPUT_XCFRAMEWORK"
mkdir -p "$(dirname "$OUTPUT_XCFRAMEWORK")"

xcodebuild -create-xcframework -output "$OUTPUT_XCFRAMEWORK" "$@"

if [ -n "$OUTPUT_ZIP" ]; then
    if ! command -v ditto >/dev/null 2>&1; then
        echo "[!] ditto not found"
        exit 1
    fi

    rm -f "$OUTPUT_ZIP"
    mkdir -p "$(dirname "$OUTPUT_ZIP")"
    (
        cd "$(dirname "$OUTPUT_XCFRAMEWORK")"
        ditto -c -k --sequesterRsrc --keepParent "$(basename "$OUTPUT_XCFRAMEWORK")" "$(basename "$OUTPUT_ZIP")"
    )
    mv "$(dirname "$OUTPUT_XCFRAMEWORK")/$(basename "$OUTPUT_ZIP")" "$OUTPUT_ZIP"
fi
