#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

echo "=== Building Rust universal library ==="
cd native/wellen_ffi
rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null || true
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
mkdir -p target/universal-release
lipo -create \
  target/aarch64-apple-darwin/release/libwellen_ffi.dylib \
  target/x86_64-apple-darwin/release/libwellen_ffi.dylib \
  -output target/universal-release/libwellen_ffi.dylib
echo "Universal dylib:"
lipo -info target/universal-release/libwellen_ffi.dylib
cd ../..

echo "=== Running code generation ==="
dart run build_runner build --delete-conflicting-outputs

echo "=== Building Flutter macOS release ==="
flutter build macos --release

echo "=== Verifying architectures ==="
APP="build/macos/Build/Products/Release/wavecrux.app"
file "$APP/Contents/MacOS/wavecrux"
file "$APP/Contents/Frameworks/libwellen_ffi.dylib"

# libwellen_ffi.dylib also carries the LXT/LXT2 converter (wellen_ffi links
# native/lxt2fst); a bundle without its symbols fails every LXT/LXT2 open.
echo "=== Verifying bundled FFI exports ==="
EXPORTS="$(nm -gU "$APP/Contents/Frameworks/libwellen_ffi.dylib")"
for SYMBOL in _wellen_open _lxt2fst_convert; do
  if ! grep " T ${SYMBOL}\$" <<<"$EXPORTS" >/dev/null; then
    echo "ERROR: bundled libwellen_ffi.dylib does not export $SYMBOL"
    exit 1
  fi
done
echo "wellen_* and lxt2fst_* exports present"
echo ""
echo "Build complete: $APP"