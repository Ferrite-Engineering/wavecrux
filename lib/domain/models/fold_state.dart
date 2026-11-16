// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Rect;

import 'package:meta/meta.dart';

/// What the device's hinge reports. [none] on every device without one.
enum HingeStatus {
  /// No hinge (every non-foldable device, every desktop, the web).
  none,

  /// Folded shut: the app is on the cover display.
  closed,

  /// Partly open: the crease is a physical gap in the panel.
  partiallyOpen,

  /// Open flat: the inner panel is one continuous surface.
  fullyOpen,
}

/// How WaveCrux lays out around the fold.
enum FoldPosture {
  /// No fold to respect: no hinge, closed, flat, or the crease not known yet.
  none,

  /// Half-folded with a horizontal crease, like a laptop: one half stands up,
  /// the other lies flat. The waveform goes up, Stage goes down.
  tabletop,

  /// Half-folded with a vertical crease, like a book: two pages side by side.
  book,
}

/// Screen areas the hardware covers (cameras, sensors), as the platform
/// reports them: global logical pixels, the system's margin for interactive
/// content included.
///
/// On the iPhone Duo's cover screen this is the camera corner (84 × 82 pt at
/// the top right in portrait, top left in landscape), while the safe area
/// claims that whole edge from top to bottom. Value-equal, so a layout that
/// watches it rebuilds only when the regions move, not on every hinge update.
@immutable
class FoldOcclusions {
  /// Wraps [rects].
  const FoldOcclusions(this.rects);

  /// No covered areas.
  static const FoldOcclusions none = FoldOcclusions([]);

  /// The covered areas.
  final List<Rect> rects;

  /// Whether there are none.
  bool get isEmpty => rects.isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! FoldOcclusions || other.rects.length != rects.length) {
      return false;
    }
    for (var i = 0; i < rects.length; i++) {
      if (other.rects[i] != rects[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(rects);

  @override
  String toString() => 'FoldOcclusions($rects)';
}

/// The fold, as the layout needs it: hinge status, angle and the crease.
///
/// Immutable. [FoldState.none] is the value on every device without a hinge,
/// and every layout must be exactly what it was before fold support existed
/// when it sees that value.
@immutable
class FoldState {
  /// Creates a fold state.
  const FoldState({
    required this.status,
    this.hingeAngle,
    this.crease,
    this.occlusions = FoldOcclusions.none,
  });

  /// No hinge, no crease.
  static const FoldState none = FoldState(status: HingeStatus.none);

  /// What the hinge reports.
  final HingeStatus status;

  /// Hinge angle in degrees, 0 folded shut to 180 flat, when the platform
  /// reports one (iOS does; Android's display features do not).
  final double? hingeAngle;

  /// The crease band in global logical pixels (the iPhone Duo reports 40 pt:
  /// 20 either side of the fold line), or null when none is reported.
  final Rect? crease;

  /// Areas the hardware covers on the current screen. Only the iPhone Duo's
  /// native bridge reports these; elsewhere [FoldOcclusions.none].
  final FoldOcclusions occlusions;

  /// Whether the device has a hinge at all.
  bool get hasHinge => status != HingeStatus.none;

  /// The layout posture: a crease counts only while the device is partly
  /// open, because the platform's crease region lags the hinge and may still
  /// read active for a moment after the device goes flat.
  FoldPosture get posture {
    final c = crease;
    if (status != HingeStatus.partiallyOpen || c == null) {
      return FoldPosture.none;
    }
    return c.width >= c.height ? FoldPosture.tabletop : FoldPosture.book;
  }

  /// A copy with the given fields replaced. Pass [clearCrease] to drop the
  /// crease (a nullable field cannot be cleared through a null argument).
  FoldState copyWith({
    HingeStatus? status,
    double? hingeAngle,
    Rect? crease,
    bool clearCrease = false,
    FoldOcclusions? occlusions,
  }) => FoldState(
    status: status ?? this.status,
    hingeAngle: hingeAngle ?? this.hingeAngle,
    crease: clearCrease ? null : (crease ?? this.crease),
    occlusions: occlusions ?? this.occlusions,
  );

  @override
  bool operator ==(Object other) =>
      other is FoldState &&
      other.status == status &&
      other.hingeAngle == hingeAngle &&
      other.crease == crease &&
      other.occlusions == occlusions;

  @override
  int get hashCode => Object.hash(status, hingeAngle, crease, occlusions);

  @override
  String toString() =>
      'FoldState(status: ${status.name}, angle: $hingeAngle, '
      'crease: $crease, posture: ${posture.name}'
      '${occlusions.isEmpty ? '' : ', occlusions: ${occlusions.rects}'})';
}
