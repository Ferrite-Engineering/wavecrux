// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter/services.dart'
    show EventChannel, MissingPluginException;
import 'package:wavecrux/domain/models/fold_state.dart';

/// Where fold events come from. Tests substitute a fake.
abstract interface class FoldSource {
  /// Hinge and crease updates, newest last. Empty on a device with no hinge.
  Stream<FoldState> watch();
}

/// The native hinge bridge (`packages/wavecrux_fold`), iOS only.
///
/// Apple's hinge and crease APIs (iOS 27.1: `UIHingeInteraction`, reserved
/// regions) are not reached by Flutter's iOS embedder: `MediaQuery.displayFeatures`
/// is empty there (flutter/flutter#192515). The plugin forwards them on an
/// event channel. On a build without the plugin, or an iOS without the API,
/// the stream ends at once and the app stays on [FoldState.none].
class PlatformFoldSource implements FoldSource {
  /// Creates the platform source.
  const PlatformFoldSource();

  static const EventChannel _channel = EventChannel('com.wavecrux/fold');

  @override
  Stream<FoldState> watch() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Stream<FoldState>.empty();
    }
    return _channel
        .receiveBroadcastStream()
        .map(foldStateFromPlatformEvent)
        .handleError((Object _) {}, test: (e) => e is MissingPluginException);
  }
}

/// Decodes one event from the native bridge.
///
/// Shape: `{status: 'none'|'closed'|'partiallyOpen'|'fullyOpen',
/// angle: double?, crease: [left, top, width, height]?}`, coordinates in the
/// Flutter view's logical pixels. Anything malformed decodes to
/// [FoldState.none] rather than throwing: a bad event must never take the
/// viewer's layout down with it.
FoldState foldStateFromPlatformEvent(Object? event) {
  if (event is! Map) return FoldState.none;
  final status = switch (event['status']) {
    'closed' => HingeStatus.closed,
    'partiallyOpen' => HingeStatus.partiallyOpen,
    'fullyOpen' => HingeStatus.fullyOpen,
    _ => HingeStatus.none,
  };
  if (status == HingeStatus.none) return FoldState.none;
  final angle = event['angle'];
  final crease = event['crease'];
  Rect? rect;
  if (crease is List && crease.length == 4 && crease.every((v) => v is num)) {
    final v = crease.cast<num>().map((n) => n.toDouble()).toList();
    if (v[2] > 0 && v[3] > 0 && v.every((n) => n.isFinite)) {
      rect = Rect.fromLTWH(v[0], v[1], v[2], v[3]);
    }
  }
  return FoldState(
    status: status,
    hingeAngle: angle is num && angle.isFinite ? angle.toDouble() : null,
    crease: rect,
  );
}

/// A partly open hinge at or above this angle counts as flat.
///
/// Hands rarely hold a foldable at exactly 180°, and the hinge reports
/// "partially open" for any angle short of its stop (the iOS simulator passes
/// through about 174° on the way to flat). Without a band, a phone held open
/// but slightly bent would keep the book or tabletop layout.
const double kFoldFlatEnterDegrees = 160;

/// Once counted as flat, the hinge must close below this angle to count as
/// half-folded again, so a hand resting near the threshold does not flip the
/// layout back and forth.
const double kFoldFlatLeaveDegrees = 150;

/// Applies the flat band to a hinge reading.
///
/// Returns the reading to lay out with (a partly open hinge inside the band
/// is reported as [HingeStatus.fullyOpen]) and whether it is now in the band,
/// which the caller passes back as [wasFlat] with the next reading.
({FoldState state, bool flat}) applyFlatBand(
  FoldState reading, {
  required bool wasFlat,
}) {
  switch (reading.status) {
    case HingeStatus.fullyOpen:
      return (state: reading, flat: true);
    case HingeStatus.partiallyOpen:
      final angle = reading.hingeAngle;
      if (angle == null) return (state: reading, flat: false);
      final threshold = wasFlat ? kFoldFlatLeaveDegrees : kFoldFlatEnterDegrees;
      if (angle < threshold) return (state: reading, flat: false);
      return (
        state: reading.copyWith(status: HingeStatus.fullyOpen),
        flat: true,
      );
    case HingeStatus.none:
    case HingeStatus.closed:
      return (state: reading, flat: false);
  }
}

/// The thinnest crease band WaveCrux lays out around. Android reports a fold
/// as a zero-width line; the iPhone Duo reports a 40 pt band.
const double kMinCreaseBand = 24;

/// Reads a fold from Flutter's own display features (Android foldables).
///
/// Returns [FoldState.none] when there is no fold or hinge feature, which is
/// always the case on iOS today.
FoldState foldStateFromDisplayFeatures(List<DisplayFeature> features) {
  for (final f in features) {
    if (f.type != DisplayFeatureType.fold &&
        f.type != DisplayFeatureType.hinge) {
      continue;
    }
    final status = f.state == DisplayFeatureState.postureHalfOpened
        ? HingeStatus.partiallyOpen
        : HingeStatus.fullyOpen;
    return FoldState(status: status, crease: _atLeastBand(f.bounds));
  }
  return FoldState.none;
}

Rect _atLeastBand(Rect r) {
  if (r.width >= r.height) {
    if (r.height >= kMinCreaseBand) return r;
    final cy = r.center.dy;
    return Rect.fromLTRB(
      r.left,
      cy - kMinCreaseBand / 2,
      r.right,
      cy + kMinCreaseBand / 2,
    );
  }
  if (r.width >= kMinCreaseBand) return r;
  final cx = r.center.dx;
  return Rect.fromLTRB(
    cx - kMinCreaseBand / 2,
    r.top,
    cx + kMinCreaseBand / 2,
    r.bottom,
  );
}
