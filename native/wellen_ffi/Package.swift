// swift-tools-version: 5.9
// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0
//
// The tools-version comment must stay on line 1: SwiftPM before 6.0 rejects a
// manifest whose tools-version follows any other line, which fails package
// resolution for every iOS build. The SPDX check only needs the header within
// the first lines.
//
// WellenFFI — Swift Package wrapper around the prebuilt WellenFFI.xcframework.
//
// The xcframework ships the Rust-built static archive (libwellen_ffi.a) for
// iOS device (arm64) and iOS simulator (arm64); the archive also carries the
// LXT/LXT2 converter's `lxt2fst_*` C ABI, which wellen_ffi links. The
// WellenFFIKeepalive C target ships the dead-strip-prevention translation unit
// that forces ld64 to retain every `wellen_*` and `lxt2fst_*` symbol so Dart's
// runtime DynamicLibrary.process() + dlsym can find them. See
// Sources/WellenFFIKeepalive/wellen_ffi_keepalive.c for the full rationale.
//
// Rebuild the xcframework after Rust changes by running scripts/build_ios.sh
// from the wavecrux repo root.

import PackageDescription

let package = Package(
  name: "WellenFFI",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "WellenFFI", targets: ["WellenFFIKeepalive"]),
  ],
  targets: [
    .binaryTarget(
      name: "WellenFFIBinary",
      path: "WellenFFI.xcframework"
    ),
    .target(
      name: "WellenFFIKeepalive",
      dependencies: ["WellenFFIBinary"],
      path: "Sources/WellenFFIKeepalive"
    ),
  ]
)
