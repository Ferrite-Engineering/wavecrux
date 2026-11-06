// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/layouts/fold_state_provider.dart';

/// Minimum window width (in dp) at which a tablet may split panes.
///
/// Two panes side by side on a portrait tablet are too cramped to read, so a
/// tablet narrower than this shows one pane; the desktop class is
/// unrestricted.
const double kPaneHostMinSplitWidthDp = 1000;

/// The tablet split floor on a device with a hinge.
///
/// A foldable's inner panel held sideways (the iPhone Duo's is about 951 dp)
/// is narrower than [kPaneHostMinSplitWidthDp] but folds down the middle like
/// a book, and one pane per page is the layout it is shaped for: the pane
/// splitter then sits on the crease (`bookSplit`). Held upright (about
/// 669 dp) it stays one pane.
const double kFoldableMinSplitWidthDp = 900;

/// Whether a window [width] dp wide on [deviceClass] shows split panes.
///
/// Phones never do; a tablet needs [kPaneHostMinSplitWidthDp], or
/// [kFoldableMinSplitWidthDp] when [foldable]; desktop always does. The pane
/// host renders only the active pane when this is false, so every way of
/// splitting — the tab-bar button, the menu action and its chord — must ask
/// the same question, or a split made where it cannot be shown hides the pane
/// the other tabs stay in.
bool isSplitPaneAllowed(
  DeviceClass deviceClass,
  double width, {
  bool foldable = false,
}) => switch (deviceClass) {
  DeviceClass.phone || DeviceClass.phoneLandscape => false,
  DeviceClass.tablet =>
    width >= (foldable ? kFoldableMinSplitWidthDp : kPaneHostMinSplitWidthDp),
  DeviceClass.desktop => true,
};

/// [isSplitPaneAllowed] for the current window, for the action layer.
///
/// A size not yet reported counts as wide enough; the device class then
/// decides, which matches [deviceClassProvider]'s own not-yet-known default.
final splitPaneAllowedProvider = Provider<bool>((ref) {
  final width = ref.watch(displaySizeProvider)?.width ?? double.infinity;
  return isSplitPaneAllowed(
    ref.watch(deviceClassProvider),
    width,
    foldable: ref.watch(hasHingeProvider),
  );
}, name: 'splitPaneAllowedProvider');
