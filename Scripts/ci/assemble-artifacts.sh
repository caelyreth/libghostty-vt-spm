#!/bin/sh

set -eu

cd "$(dirname "$0")/../.."

TARBALLS_DIR=${1:-}
OUTPUT_DIR=${2:-}

if [ -z "$TARBALLS_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <tarballs_dir> <output_dir>"
    exit 1
fi

TARGETS_DIR="$OUTPUT_DIR/../targets"
rm -rf "$TARGETS_DIR" "$OUTPUT_DIR"
mkdir -p "$TARGETS_DIR" "$OUTPUT_DIR"

FOUND_TARBALLS=0
for tarball in "$TARBALLS_DIR"/ghostty-vt-*.tar.gz; do
    [ -f "$tarball" ] || continue
    FOUND_TARBALLS=$((FOUND_TARBALLS + 1))

    name=$(basename "$tarball" .tar.gz)
    name=${name#ghostty-vt-}
    sdk=${name%-*}
    arch=${name##*-}

    if [ -z "$sdk" ] || [ -z "$arch" ] || [ "$sdk" = "$arch" ]; then
        echo "[!] malformed target artifact name: $tarball"
        exit 1
    fi

    mkdir -p "$TARGETS_DIR/$sdk/$arch"
    tar -xzf "$tarball" -C "$TARGETS_DIR/$sdk/$arch"
done

if [ "$FOUND_TARBALLS" -eq 0 ]; then
    echo "[!] no target tarballs found in $TARBALLS_DIR"
    exit 1
fi

for sdk_dir in "$TARGETS_DIR"/*; do
    [ -d "$sdk_dir" ] || continue

    sdk=$(basename "$sdk_dir")
    mkdir -p "$OUTPUT_DIR/$sdk/lib" "$OUTPUT_DIR/$sdk/include"

    lib_count=0
    first_headers=
    set --
    for arch_dir in "$sdk_dir"/*; do
        [ -d "$arch_dir" ] || continue
        archive="$arch_dir/lib/libghostty-vt.a"
        [ -f "$archive" ] || continue

        set -- "$@" "$archive"
        lib_count=$((lib_count + 1))
        if [ -z "$first_headers" ]; then
            first_headers="$arch_dir/include"
        fi
    done

    if [ "$lib_count" -eq 0 ]; then
        echo "[!] no libraries found for $sdk"
        exit 1
    fi

    cp -R "$first_headers/." "$OUTPUT_DIR/$sdk/include/"

    if [ "$lib_count" -eq 1 ]; then
        cp "$1" "$OUTPUT_DIR/$sdk/lib/libghostty-vt.a"
    else
        lipo -create "$@" -output "$OUTPUT_DIR/$sdk/lib/libghostty-vt.a"
    fi
done
