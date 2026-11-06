// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/fold_state.dart';
import 'package:wavecrux/services/platform/fold_source.dart';
import 'package:wavecrux/shared/layouts/fold_state_provider.dart';

/// Keeps [foldStateProvider] current, and tells Flutter about the crease.
///
/// Two sources: the native hinge bridge (iPhone Duo, via [foldSourceProvider])
/// and Flutter's own `MediaQuery.displayFeatures` (Android foldables). The
/// native source wins when it reports a hinge.
///
/// While the device is half-folded and Flutter's display features do not
/// already carry the crease (iOS never does, flutter/flutter#192515), the
/// crease is added to the [MediaQuery] below this widget. Material dialogs,
/// sheets and popups read it through `DisplayFeatureSubScreen` and open in one
/// half instead of across the fold. Flat and closed postures add nothing, so
/// a dialog on a flat panel still uses the whole screen.
///
/// Mount once near the app root, inside `MaterialApp.builder` next to
/// `DisplaySizeFeed`. On a device without a hinge it pushes nothing and
/// returns its child unchanged.
class FoldFeed extends ConsumerStatefulWidget {
  /// Creates the feed.
  const FoldFeed({required this.child, super.key});

  /// The app below the feed.
  final Widget child;

  @override
  ConsumerState<FoldFeed> createState() => _FoldFeedState();
}

class _FoldFeedState extends ConsumerState<FoldFeed> {
  StreamSubscription<FoldState>? _sub;
  FoldState _native = FoldState.none;
  FoldState _fromFeatures = FoldState.none;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(foldSourceProvider).watch().listen(
      (state) {
        if (!mounted || state == _native) return;
        // Debug builds only: the real crease and panel size, for checking a
        // new device against the layout's assumptions (campaign D4).
        if (kDebugMode &&
            (state.posture != _native.posture ||
                state.status != _native.status)) {
          debugPrint(
            'WaveCrux fold: $state, view ${MediaQuery.sizeOf(context)}',
          );
        }
        setState(() => _native = state);
        _push();
      },
      onError: (Object _) {},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = foldStateFromDisplayFeatures(
      MediaQuery.displayFeaturesOf(context),
    );
    if (next != _fromFeatures) {
      _fromFeatures = next;
      _push();
    }
  }

  FoldState get _effective => _native.hasHinge ? _native : _fromFeatures;

  /// Riverpod forbids writing a provider during build; the write goes after
  /// the frame, as `DisplaySizeFeed` does.
  void _push() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(foldStateProvider.notifier).set(_effective);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final crease = _native.posture == FoldPosture.none ? null : _native.crease;
    if (crease == null) return widget.child;
    final data = MediaQuery.of(context);
    final alreadyThere = data.displayFeatures.any(
      (f) =>
          f.type == DisplayFeatureType.fold ||
          f.type == DisplayFeatureType.hinge,
    );
    if (alreadyThere) return widget.child;
    return MediaQuery(
      data: data.copyWith(
        displayFeatures: [
          ...data.displayFeatures,
          DisplayFeature(
            bounds: crease,
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      ),
      child: widget.child,
    );
  }
}
