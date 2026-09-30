// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Size;

/// Viewport width below which the side panes take their narrow (220 / 160)
/// defaults — see [paneDefaultsForViewport].
///
/// 800 dp is deliberately the desktop window minimum (see CLAUDE.md's
/// native-desktop-host exception): a real desktop window can never be narrower,
/// so this arm is unreachable on macOS / Windows / Linux and only ever fires on
/// the hosts that can genuinely be this narrow — a foldable's inner display in
/// portrait, a small tablet in portrait, and a narrow browser tab.
const double kNarrowViewportWidth = 800;

/// Default left (signal-tree) and right (value-column) pane widths in logical
/// pixels for a viewer hosted at [viewport].
///
/// Side panes are absolute-width and the waveform canvas greedily absorbs the
/// remaining horizontal space, so the canvas is whatever the panes leave. That
/// cuts both ways, and this function handles both ends.
///
/// **Wide.** On a very wide display the canvas is already enormous and the
/// ergonomic gap is the *side* panes: at the standard 280 / 220 defaults, deep
/// hierarchical signal names (`top.cpu.decode.alu.result[31:0]`) and wide bus
/// values truncate even though there is ample room. On an ultrawide viewport —
/// the headline mode of XR glasses such as the Viture Beast (32:9), and of any
/// ultrawide desktop monitor — we widen the defaults so names and values stop
/// truncating, while the canvas still keeps the lion's share of the width.
///
/// **Narrow.** Below [kNarrowViewportWidth] the arithmetic inverts: the panes
/// are a fixed 500 dp and it is the *canvas* that starves. The worst case we
/// ship to is the iPhone Duo's inner display in portrait (669 dp), which
/// classifies as `DeviceClass.tablet` and would hand the waveform ~157 dp —
/// under a quarter of the width, and narrower than the same device gives it on
/// the folded cover screen. Nothing overflows (`CruxIdeLayout` clamps to its
/// 120 dp centre floor), it is simply a waveform viewer with no room for the
/// waveform. The narrow defaults trade some name/value truncation — recoverable
/// by dragging a splitter, or by hiding a dock — for a canvas that is worth
/// looking at. A small tablet in portrait (iPad mini, 744 dp) gets the same
/// treatment.
///
/// Thresholds (aspect ratio = width / height):
///   * `width < 800 dp`  → `220 / 160`, whatever the aspect.
///   * `< 21:9` (≈2.33)  → standard `280 / 220` — unchanged for every normal
///     laptop / desktop / large-tablet / phone screen.
///   * `≥ 21:9`          → `360 / 280`.
///   * `≥ 32:9` (≈3.55)  → `420 / 320`.
///
/// Both narrow values clear `CruxIdeLayout`'s 150 dp per-pane minimum, so the
/// layout never has to clamp them back up.
///
/// Only the *default* (unset) size is affected: once the user drags a splitter,
/// their pixel width is persisted in `PanelLayoutState.leftPaneSize` /
/// `rightPaneSize` and wins over this default. Pane *visibility* is untouched —
/// that is per-tab user state, not a layout decision. Returns logical pixels.
({double left, double right}) paneDefaultsForViewport(Size viewport) {
  const standard = (left: 280.0, right: 220.0);
  const narrow = (left: 220.0, right: 160.0);

  final width = viewport.width;
  final height = viewport.height;
  // Degenerate viewport (pre-layout, or a zero-sized test surface): the
  // standard defaults are the only honest answer — a zero width is not
  // evidence of a narrow display.
  if (width <= 0 || height <= 0) return standard;

  if (width < kNarrowViewportWidth) return narrow;

  final aspect = width / height;
  if (aspect >= 32 / 9) return (left: 420.0, right: 320.0);
  if (aspect >= 21 / 9) return (left: 360.0, right: 280.0);
  return standard;
}
