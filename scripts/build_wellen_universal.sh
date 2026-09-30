# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Navigate to the Rust crate
cd native/wellen_ffi

# Ensure both targets are installed
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin

# Build for ARM64 (native on your M4)
cargo build --release --target aarch64-apple-darwin

# Build for x86_64 (cross-compile — Xcode provides the linker)
cargo build --release --target x86_64-apple-darwin

# Merge into a universal dylib
mkdir -p target/universal-release
lipo -create \
  target/aarch64-apple-darwin/release/libwellen_ffi.dylib \
  target/x86_64-apple-darwin/release/libwellen_ffi.dylib \
  -output target/universal-release/libwellen_ffi.dylib

# Verify it's truly universal
lipo -info target/universal-release/libwellen_ffi.dylib
# Expected: "Architectures in the fat file: ... are: x86_64 arm64"

file target/universal-release/libwellen_ffi.dylib
# Expected: "Mach-O universal binary with 2 architectures:
#   [x86_64: Mach-O 64-bit dynamically linked shared library x86_64]
#   [arm64:  Mach-O 64-bit dynamically linked shared library arm64]"