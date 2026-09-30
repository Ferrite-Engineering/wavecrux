#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build the wellen_ffi Rust static library for iOS and package it as an XCFramework.
#
# Run from the repository root:
#   ./scripts/build_ios.sh
#
# Prerequisites:
#   - Xcode installed (provides iOS SDK)
#   - Rust targets installed: rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#
# The xcframework produced here is consumed by the local Swift Package at
# native/wellen_ffi/Package.swift, which the iOS Runner depends on via an
# XCLocalSwiftPackageReference. The archive is committed and Xcode never runs
# cargo, so rerun this script (and commit the result) after any change to
# native/wellen_ffi, native/lxt2fst — which wellen_ffi links, so the archive
# also carries the LXT/LXT2 converter's lxt2fst_* symbols — or
# native/vendor/fst-writer.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$REPO_ROOT/native/wellen_ffi"
XCFRAMEWORK="$CRATE_DIR/WellenFFI.xcframework"

echo "==> Ensuring iOS Rust targets are installed..."
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

echo "==> Building for aarch64-apple-ios (device)..."
cargo build --release --target aarch64-apple-ios --manifest-path "$CRATE_DIR/Cargo.toml"

echo "==> Building for aarch64-apple-ios-sim (simulator)..."
cargo build --release --target aarch64-apple-ios-sim --manifest-path "$CRATE_DIR/Cargo.toml"

echo "==> Assembling XCFramework..."
rm -rf "$XCFRAMEWORK"

# Headers directory (required by xcodebuild -create-xcframework for static libs)
HEADERS_DIR="$CRATE_DIR/include"
mkdir -p "$HEADERS_DIR"
cp "$CRATE_DIR/wellen_ffi.h" "$HEADERS_DIR/"

xcodebuild -create-xcframework \
  -library "$CRATE_DIR/target/aarch64-apple-ios/release/libwellen_ffi.a" \
  -headers "$HEADERS_DIR" \
  -library "$CRATE_DIR/target/aarch64-apple-ios-sim/release/libwellen_ffi.a" \
  -headers "$HEADERS_DIR" \
  -output "$XCFRAMEWORK"

echo "==> Verifying XCFramework..."
ls -la "$XCFRAMEWORK"
plutil -p "$XCFRAMEWORK/Info.plist" | grep Identifier
for ARCHIVE in "$XCFRAMEWORK"/*/libwellen_ffi.a; do
  # Xcode's nm exits non-zero on the Rust std members' embedded bitcode (a
  # newer LLVM than Apple's reader) while still listing every Mach-O symbol,
  # so its status is ignored and the listing is checked instead.
  EXPORTS="$(nm -gU "$ARCHIVE" 2>/dev/null || true)"
  for SYMBOL in _wellen_open _lxt2fst_convert; do
    if ! grep " T ${SYMBOL}\$" <<<"$EXPORTS" >/dev/null; then
      echo "ERROR: $ARCHIVE does not export $SYMBOL"
      exit 1
    fi
  done
done
echo "    wellen_* and lxt2fst_* symbols present in every slice"

echo ""
echo "XCFramework built successfully at:"
echo "  $XCFRAMEWORK"
echo ""
echo "Next step: flutter build ios (Swift Package resolves it automatically)"
