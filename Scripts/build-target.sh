#!/bin/sh

set -eu

cd "$(dirname "$0")/.."

SOURCE_DIR=${1:-}
ZIG_TARGET=${2:-}
OUTPUT_DIR=${3:-}

if [ -z "$SOURCE_DIR" ] || [ -z "$ZIG_TARGET" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <ghostty_source_dir> <zig_target> <output_dir>"
    exit 1
fi

if [ ! -f "$SOURCE_DIR/include/ghostty/vt.h" ]; then
    echo "[!] missing Ghostty VT headers: $SOURCE_DIR/include/ghostty/vt.h"
    exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
    echo "[!] zig not found"
    exit 1
fi

CACHE_ROOT="${BUILD_CACHE_ROOT:-$PWD/build/cache}"
LOCAL_CACHE_DIR="$CACHE_ROOT/$ZIG_TARGET/zig-local"
MODULE_CACHE_DIR="$CACHE_ROOT/$ZIG_TARGET/clang-module-cache"
GLOBAL_CACHE_DIR="$CACHE_ROOT/zig-global"

rm -rf "$OUTPUT_DIR" "$LOCAL_CACHE_DIR" "$MODULE_CACHE_DIR" "$SOURCE_DIR/zig-out"
mkdir -p "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include" "$LOCAL_CACHE_DIR" "$MODULE_CACHE_DIR" "$GLOBAL_CACHE_DIR"

echo "[*] build $ZIG_TARGET"

set -- \
    build \
    "-Doptimize=${ZIG_OPTIMIZE:-ReleaseFast}" \
    -Demit-lib-vt=true \
    -Demit-xcframework=false \
    -Demit-macos-app=false \
    -Demit-docs=false \
    -Dtarget="$ZIG_TARGET"

if [ -n "${ZIG_CPU:-}" ]; then
    set -- "$@" "-Dcpu=$ZIG_CPU"
fi

(
    cd "$SOURCE_DIR"
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
    ZIG_GLOBAL_CACHE_DIR="$GLOBAL_CACHE_DIR" \
    ZIG_LOCAL_CACHE_DIR="$LOCAL_CACHE_DIR" \
    zig "$@"
)

LIBRARY_PATH="$SOURCE_DIR/zig-out/lib/libghostty-vt.a"
if [ ! -f "$LIBRARY_PATH" ]; then
    LIBRARY_PATH=$(find "$LOCAL_CACHE_DIR/o" -type f -name "libghostty-vt.a" -print 2>/dev/null | sort | tail -n 1)
fi

if [ -z "$LIBRARY_PATH" ] || [ ! -f "$LIBRARY_PATH" ]; then
    echo "[!] failed to find libghostty-vt.a"
    find "$LOCAL_CACHE_DIR" -maxdepth 4 -type f | sort | tail -n 80
    exit 1
fi

cp -R "$SOURCE_DIR/include/ghostty" "$OUTPUT_DIR/include/"
cp "scripts/templates/GhosttyVtPrebuilt.modulemap" "$OUTPUT_DIR/include/module.modulemap"

cp "$LIBRARY_PATH" "$OUTPUT_DIR/lib/libghostty-vt.a"

echo "[*] wrote $OUTPUT_DIR"
