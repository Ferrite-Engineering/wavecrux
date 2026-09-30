// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Conventional signal ref used by every primitive Stage widget test.
const String testSignalRef = 'top.test';

/// Convenience binding for [testSignalRef] without bit slicing — every
/// primitive test wraps its bound pins in this.
const StageSignalBinding testBinding = StageSignalBinding(
  signalRef: testSignalRef,
);

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with WaveCrux's L10N
/// configuration and overrides the [stageBoundSignalProvider] for
/// [testSignalRef] to return [snapshot] (or [StageSignalSnapshot.unbound] when
/// null).
///
/// Used by every primitive Stage widget test so we can render the widget
/// against any synthetic snapshot without spinning up a real waveform
/// source. Each test creates a [StageInstance] whose `signalBindings` map
/// every required pin to [testSignalRef].
Widget wrapStageWidget(
  Widget child, {
  required StageSignalSnapshot snapshot,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      stageBoundSignalProvider(testBinding).overrideWith((ref) => snapshot),
      stageBoundSignalProvider(null).overrideWith(
        (ref) => const StageSignalSnapshot.unbound(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
