// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regenerates the iOS launch-screen mark from the master app icon.
//
// Run from the repo root:
//   swift tool/generate_ios_launch_images.swift
//
// Writes LaunchImage.png / @2x / @3x into
// ios/Runner/Assets.xcassets/LaunchImage.imageset/.
//
// ## Why this exists
//
// Flutter ships a 1x1 transparent placeholder as the launch image, centered on
// a hardcoded white storyboard background. That produced a full-brightness
// white flash on every cold start — worst on a dark-mode OLED phone — and
// `flutter build ipa` warns about it ("Launch image is set to the default
// placeholder icon"). It is also exactly the kind of unfinished-looking detail
// that invited the App Store Guideline 2.2 rejection of 0.1.0 (2).
//
// The master icon (`assets/images/wavecrux_icon_1024.png`) is full-bleed
// artwork with a dark vignette, so its four corners are different shades
// (sampled: 14,14,40 / 24,53,69 / 5,7,32 / 21,21,49). Dropping it square onto
// any flat colour leaves a visible seam on at least one corner. Rounding it to
// the iOS icon radius instead makes it read as a deliberate app-icon tile —
// the launch screen then echoes the icon the user just tapped, which is the
// continuity Apple's HIG asks for.
//
// The storyboard background is set to the artwork's mean corner navy
// (#101830) in both light and dark appearance. A single fixed colour is
// intentional: the icon is inherently dark, so a light-mode variant would show
// a dark tile floating on white — worse than a consistently dark launch. Dark
// also matches the app icon far better than white ever did.

import AppKit
import Foundation

/// Point size of the centred mark. The storyboard pins the image view to the
/// view centre and uses `contentMode="center"`, so the 1x pixel size is the
/// rendered point size; @2x/@3x are the same mark at device scale.
let markPointSize = 160

/// iOS icon corner radius as a fraction of the icon's edge. Apple's real mask
/// is a continuous-curvature squircle; a plain rounded rect is visually
/// indistinguishable at this size and needs no bezier hand-rolling.
let cornerRadiusFraction = 0.2237

let repoRoot = FileManager.default.currentDirectoryPath
let sourcePath = "\(repoRoot)/assets/images/wavecrux_icon_1024.png"
let outputDir =
    "\(repoRoot)/ios/Runner/Assets.xcassets/LaunchImage.imageset"

guard let source = NSImage(contentsOfFile: sourcePath) else {
    FileHandle.standardError.write(
        Data("error: cannot read \(sourcePath)\n".utf8))
    exit(1)
}

/// Draws [source] into a square [pixels]×[pixels] bitmap, clipped to a rounded
/// rect, and returns the PNG bytes.
func renderMark(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write(Data("error: bitmap alloc failed\n".utf8))
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let side = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    let radius = side * CGFloat(cornerRadiusFraction)
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        .addClip()
    source.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: PNG encode failed\n".utf8))
        exit(1)
    }
    return png
}

for (suffix, scale) in [("", 1), ("@2x", 2), ("@3x", 3)] {
    let pixels = markPointSize * scale
    let path = "\(outputDir)/LaunchImage\(suffix).png"
    do {
        try renderMark(pixels: pixels).write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(pixels)x\(pixels))")
    } catch {
        FileHandle.standardError.write(
            Data("error: cannot write \(path): \(error)\n".utf8))
        exit(1)
    }
}
