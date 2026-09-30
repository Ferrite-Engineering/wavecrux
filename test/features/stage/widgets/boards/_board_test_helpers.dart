// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/widgets/primitives/builtin_stage_widgets.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with WaveCrux's L10N
/// configuration and overrides [stageBoundSignalProvider] to return
/// [defaultSnapshot] for any non-null signal ref. Bindings to specific
/// refs may be customised through [snapshots].
///
/// Used by board widget tests to render compound widgets without spinning
/// up a real waveform source. Each test creates a parent [StageInstance]
/// whose `signalBindings` map references signal paths that the override
/// resolves to deterministic snapshots.
Widget wrapBoardWidget(
  Widget child, {
  StageSignalSnapshot defaultSnapshot = const StageSignalSnapshot.unbound(),
  Map<String, StageSignalSnapshot> snapshots = const {},
  Locale locale = const Locale('en'),
  Size size = const Size(800, 480),
}) {
  return ProviderScope(
    overrides: [
      stageBoundSignalProvider(null).overrideWith(
        (ref) => const StageSignalSnapshot.unbound(),
      ),
      for (final entry in snapshots.entries)
        stageBoundSignalProvider(
          StageSignalBinding(signalRef: entry.key),
        ).overrideWith((ref) => entry.value),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Registers built-in widgets (primitives + boards) in a `setUp` and
/// pairs the call with a `tearDown` clear.
void useBuiltinStageWidgets() {
  registerBuiltinStageWidgets();
}

/// Clears built-in widget registrations.
void clearStageRegistries() {
  clearBuiltinStageWidgets();
}
