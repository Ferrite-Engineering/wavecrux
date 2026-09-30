// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Logical device class derived from the current display dimensions.
///
/// Consumed across the UI (via `deviceClassProvider`) to choose between phone,
/// tablet, and desktop chrome — e.g. `ViewerScreen`'s phone side-pane
/// force-hide, the status-bar panel-toggle chevrons, and `MobileMetrics`
/// sizing. The classification considers both width and height — width alone
/// would mis-classify a phone in landscape (which crosses the 600 dp tablet
/// width threshold but lacks vertical space for persistent side panels).
///
/// Layout widgets must derive [DeviceClass] from `MediaQuery` dimensions,
/// not from `Platform.isIOS` / `Platform.isAndroid`. This ensures correct
/// behaviour for tablets in split-screen, desktop windows resized narrow,
/// and web browsers at any size.
///
/// Pure Dart — no Flutter imports.
enum DeviceClass {
  /// Width < 600 dp. Single-pane scaffold with drawers/sheets for
  /// secondary panels.
  phone,

  /// Width ≥ 600 dp but height < 500 dp. Phone in landscape orientation:
  /// tablet-class width, but insufficient vertical space for persistent
  /// side panels. Uses a waveform-focused layout with overlay panels.
  phoneLandscape,

  /// 600 dp ≤ width < 1200 dp and height ≥ 500 dp. Simplified multi-pane
  /// layout with narrower proportions than desktop.
  tablet,

  /// Width ≥ 1200 dp. Full `IdeLayout` with resizable splitters.
  desktop;

  /// Primary width breakpoint between phone and tablet (in logical pixels).
  static const double phoneTabletBreakpoint = 600;

  /// Primary width breakpoint between tablet and desktop (in logical pixels).
  static const double tabletDesktopBreakpoint = 1200;

  /// Secondary height breakpoint: at width ≥ 600 dp but height below this
  /// value, the device is treated as phone-landscape rather than tablet.
  static const double phoneLandscapeHeightThreshold = 500;

  /// Classifies a display of the given [width] and [height] (in logical
  /// pixels) into a [DeviceClass].
  ///
  /// The classification rules:
  /// - `width < 600 dp` → [phone] (regardless of height)
  /// - `width ≥ 600 dp` and `height < 500 dp` → [phoneLandscape]
  /// - `600 dp ≤ width < 1200 dp` and `height ≥ 500 dp` → [tablet]
  /// - `width ≥ 1200 dp` and `height ≥ 500 dp` → [desktop]
  ///
  /// Negative or non-finite inputs are clamped to zero.
  static DeviceClass fromSize(double width, double height) {
    final w = width.isFinite && width > 0 ? width : 0.0;
    final h = height.isFinite && height > 0 ? height : 0.0;

    if (w < phoneTabletBreakpoint) {
      return DeviceClass.phone;
    }
    if (h < phoneLandscapeHeightThreshold) {
      return DeviceClass.phoneLandscape;
    }
    if (w < tabletDesktopBreakpoint) {
      return DeviceClass.tablet;
    }
    return DeviceClass.desktop;
  }

  /// True for [phone] and [phoneLandscape] — display is phone-sized.
  bool get isPhoneClass =>
      this == DeviceClass.phone || this == DeviceClass.phoneLandscape;

  /// True for [tablet] and [desktop] — display has enough room for a
  /// persistent multi-pane layout.
  bool get isMultiPane =>
      this == DeviceClass.tablet || this == DeviceClass.desktop;
}
