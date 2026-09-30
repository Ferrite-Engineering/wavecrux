#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build the wellen_ffi Rust shared library for Android and install the .so files
# into the Flutter jniLibs directories for APK/AAB bundling.
#
# libwellen_ffi.so is the app's one native library: besides wellen's parser it
# exports the LXT/LXT2 → FST converter (lxt2fst_*), because wellen_ffi links
# native/lxt2fst. android/app/build.gradle.kts reruns this script when either
# crate (or the vendored native/vendor/fst-writer) changes.
#
# Run from the repository root:
#   ./scripts/build_android.sh
#
# Prerequisites:
#   - Android NDK installed via Android Studio → SDK Manager → SDK Tools → NDK (Side by side)
#     (NDK r28 / 28.2.13676358 is recommended — matches the ndkVersion in build.gradle.kts)
#   - Rust Android targets:
#       rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   - ANDROID_NDK_HOME set, or ANDROID_HOME / ANDROID_SDK_ROOT pointing to the SDK root,
#     or the NDK is in the default location ($HOME/Library/Android/sdk on macOS).
#
# Output (.so files written to jniLibs — included automatically by the Flutter build):
#   android/app/src/main/jniLibs/
#   ├── arm64-v8a/libwellen_ffi.so     ← aarch64-linux-android  (64-bit ARM devices)
#   ├── armeabi-v7a/libwellen_ffi.so   ← armv7-linux-androideabi (32-bit ARM devices)
#   └── x86_64/libwellen_ffi.so        ← x86_64-linux-android   (Android emulators)
#
# For size-optimized mobile release builds, use --profile release-mobile:
#   CARGO_PROFILE=release-mobile ./scripts/build_android.sh
# The default profile is "release" (standard desktop-optimized release).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$REPO_ROOT/native/wellen_ffi"
JNILIBS_DIR="$REPO_ROOT/android/app/src/main/jniLibs"
MIN_API=24
CARGO_PROFILE="${CARGO_PROFILE:-release}"

# ── NDK discovery ──────────────────────────────────────────────────────────────

if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
  NDK_ROOT="$ANDROID_NDK_HOME"
else
  # Resolve SDK root from common env vars and default locations.
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
    SDK_ROOT="$ANDROID_HOME"
  elif [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    SDK_ROOT="$ANDROID_SDK_ROOT"
  elif [ "$(uname)" = "Darwin" ]; then
    SDK_ROOT="$HOME/Library/Android/sdk"
  else
    SDK_ROOT="$HOME/Android/Sdk"
  fi

  NDK_DIR="$SDK_ROOT/ndk"
  if [ ! -d "$NDK_DIR" ]; then
    echo "ERROR: Android NDK not found."
    echo "  Install via Android Studio: SDK Manager → SDK Tools → NDK (Side by side)"
    echo "  Or set ANDROID_NDK_HOME to the NDK root directory."
    exit 1
  fi

  # Pick the latest installed NDK version.
  NDK_ROOT="$(ls -d "$NDK_DIR"/*/ 2>/dev/null | sort -V | tail -1)"
  NDK_ROOT="${NDK_ROOT%/}"  # Strip trailing slash from ls -d output.
fi

if [ ! -d "$NDK_ROOT" ]; then
  echo "ERROR: NDK root not found: $NDK_ROOT"
  exit 1
fi

echo "NDK:     $NDK_ROOT"

# ── Host tag detection (toolchain subdir name) ────────────────────────────────

case "$(uname -sm)" in
  "Darwin "*)   HOST_TAG="darwin-x86_64"  ;;
  "Linux x86_64") HOST_TAG="linux-x86_64" ;;
  *)
    echo "ERROR: Unsupported host platform: $(uname -sm)"
    echo "  Supported platforms: macOS (any arch), Linux x86_64"
    exit 1
    ;;
esac

TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin"

if [ ! -d "$TOOLCHAIN" ]; then
  echo "ERROR: NDK toolchain directory not found: $TOOLCHAIN"
  exit 1
fi

echo "Toolchain: $TOOLCHAIN"
echo "Min API:   $MIN_API"
echo "Profile:   $CARGO_PROFILE"

# ── Rust Android target installation ──────────────────────────────────────────

echo ""
echo "==> Ensuring Android Rust targets are installed..."
rustup target add \
  aarch64-linux-android \
  armv7-linux-androideabi \
  x86_64-linux-android

# ── Build function ─────────────────────────────────────────────────────────────

# build_target RUST_TARGET ABI_SUBDIR LINKER_BIN
#   RUST_TARGET  — Rust target triple (e.g. aarch64-linux-android)
#   ABI_SUBDIR   — jniLibs ABI directory name (e.g. arm64-v8a)
#   LINKER_BIN   — NDK linker binary filename (e.g. aarch64-linux-android24-clang)
build_target() {
  local RUST_TARGET="$1"
  local ABI_SUBDIR="$2"
  local LINKER_BIN="$3"

  # Compute the Cargo linker env var name for this target.
  # e.g. aarch64-linux-android → CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
  local ENV_NAME
  ENV_NAME="CARGO_TARGET_$(echo "$RUST_TARGET" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_LINKER"
  local LINKER_PATH="$TOOLCHAIN/$LINKER_BIN"

  if [ ! -f "$LINKER_PATH" ]; then
    echo "ERROR: NDK linker not found: $LINKER_PATH"
    echo "  Ensure NDK r28 (28.2.13676358) or later is installed."
    exit 1
  fi

  echo ""
  echo "==> Building $RUST_TARGET (ABI: $ABI_SUBDIR)..."

  export "$ENV_NAME=$LINKER_PATH"
  cargo build \
    "--profile=$CARGO_PROFILE" \
    --target "$RUST_TARGET" \
    --manifest-path "$CRATE_DIR/Cargo.toml"
  unset "$ENV_NAME"

  # The Cargo output directory uses "release" for the standard release profile and
  # the profile name for custom profiles (e.g. release-mobile → release-mobile/).
  local OUT_DIR="$CRATE_DIR/target/$RUST_TARGET/$CARGO_PROFILE"

  # Fail the build rather than ship a library without the converter: the
  # Dart side resolves lxt2fst_* from this same .so. llvm-nm ships in every
  # NDK toolchain, so no host tool is assumed.
  local EXPORTS
  EXPORTS="$("$TOOLCHAIN/llvm-nm" -D --defined-only "$OUT_DIR/libwellen_ffi.so")"
  for SYMBOL in wellen_open lxt2fst_convert; do
    if ! grep " T ${SYMBOL}\$" <<<"$EXPORTS" >/dev/null; then
      echo "ERROR: $OUT_DIR/libwellen_ffi.so does not export $SYMBOL"
      exit 1
    fi
  done

  mkdir -p "$JNILIBS_DIR/$ABI_SUBDIR"
  cp "$OUT_DIR/libwellen_ffi.so" "$JNILIBS_DIR/$ABI_SUBDIR/libwellen_ffi.so"
  echo "    ✓ $JNILIBS_DIR/$ABI_SUBDIR/libwellen_ffi.so (wellen_* + lxt2fst_*)"
}

# ── Compile all three Android ABI targets ─────────────────────────────────────

build_target \
  "aarch64-linux-android" \
  "arm64-v8a" \
  "aarch64-linux-android${MIN_API}-clang"

build_target \
  "armv7-linux-androideabi" \
  "armeabi-v7a" \
  "armv7a-linux-androideabi${MIN_API}-clang"

build_target \
  "x86_64-linux-android" \
  "x86_64" \
  "x86_64-linux-android${MIN_API}-clang"

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "==> Android native libraries ready:"
for ABI in arm64-v8a armeabi-v7a x86_64; do
  SO="$JNILIBS_DIR/$ABI/libwellen_ffi.so"
  if [ -f "$SO" ]; then
    SIZE="$(du -sh "$SO" | cut -f1)"
    echo "    $ABI/libwellen_ffi.so  ($SIZE)"
  else
    echo "    MISSING: $ABI/libwellen_ffi.so"
  fi
done

echo ""
echo "Next steps:"
echo "  flutter build apk --release     # Build release APK"
echo "  flutter build appbundle         # Build release AAB for Google Play"
