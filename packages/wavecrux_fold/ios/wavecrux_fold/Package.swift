// swift-tools-version: 5.9
// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "wavecrux_fold",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "wavecrux-fold", targets: ["wavecrux_fold"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "wavecrux_fold",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            cSettings: [
                .headerSearchPath("include/wavecrux_fold")
            ]
        )
    ]
)
