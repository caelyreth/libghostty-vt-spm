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
for tarball in "$TARBALLS_DIR"/target--*.tar.gz; do
    [ -f "$tarball" ] || continue
    FOUND_TARBALLS=$((FOUND_TARBALLS + 1))

    name=$(basename "$tarball" .tar.gz)
    name=${name#target--}
    variant=${name%%--*}
    target=${name#*--}

    if [ -z "$variant" ] || [ -z "$target" ] || [ "$variant" = "$target" ]; then
        echo "[!] malformed target artifact name: $tarball"
        exit 1
    fi

    mkdir -p "$TARGETS_DIR/$variant/$target"
    tar -xzf "$tarball" -C "$TARGETS_DIR/$variant/$target"
done

if [ "$FOUND_TARBALLS" -eq 0 ]; then
    echo "[!] no target tarballs found in $TARBALLS_DIR"
    exit 1
fi

for variant_dir in "$TARGETS_DIR"/*; do
    [ -d "$variant_dir" ] || continue

    variant=$(basename "$variant_dir")
    mkdir -p "$OUTPUT_DIR/$variant/lib" "$OUTPUT_DIR/$variant/include"

    lib_count=0
    first_headers=
    set --
    for target_dir in "$variant_dir"/*; do
        [ -d "$target_dir" ] || continue
        archive="$target_dir/lib/libghostty-vt.a"
        [ -f "$archive" ] || continue

        set -- "$@" "$archive"
        lib_count=$((lib_count + 1))
        if [ -z "$first_headers" ]; then
            first_headers="$target_dir/include"
        fi
    done

    if [ "$lib_count" -eq 0 ]; then
        echo "[!] no libraries found for $variant"
        exit 1
    fi

    cp -R "$first_headers/." "$OUTPUT_DIR/$variant/include/"

    if [ "$lib_count" -eq 1 ]; then
        cp "$1" "$OUTPUT_DIR/$variant/lib/libghostty-vt.a"
    else
        lipo -create "$@" -output "$OUTPUT_DIR/$variant/lib/libghostty-vt.a"
    fi
done
