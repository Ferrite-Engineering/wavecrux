// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/web/web_legacy_lxt_open_test.dart
//
// On the web — LXT / LXT2 convert-on-open, end to end in a real
// browser.
//
// The web path has three moving parts that no VM test can reach:
//
//   1. `web/wasm/lxt2fst_loader.js`, loaded by `web/index.html`, publishing
//      `globalThis.waveCruxLxt2Fst` and lazily importing the wasm module.
//   2. The `lxt2fst` wasm converting entirely in memory (wasm32 has no
//      filesystem, so an FST written through a file path cannot exist).
//   3. `WaveformSourceNotifier.openFromBytes` routing a legacy buffer through
//      the converter and handing the FST bytes to `WellenWasmProvider`.
//
// The converter tests drive (1)+(2) for every legacy fixture and check the
// converted waveform against the source VCD's ground truth — the same
// `.expected.json` companions `lxt2fst_bridge_equivalence_test.dart` uses on
// the FFI path. The last tests drive (3) through
// `WaveformSourceNotifier.openFromBytes`, the call every browser drop, picker
// upload and `?file=` URL load converges on (`web_drag_drop_test.dart` covers
// the drop-zone wiring above it).
//
// Gated to web only via `skip: !kIsWeb`. Run with:
//   tool/run_web_integration_tests.sh web_legacy_lxt_open_test

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/telemetry/wavecrux_telemetry_overrides.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform/lxt2fst_converter.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider.dart';

import 'web_app_driver.dart';
import 'web_fixture_bundle.g.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  for (final fx in kWebLegacyFixtures) {
    testWidgets(
      'lxt2fst WASM converts ${fx.displayName} to an FST matching its source',
      (tester) async {
        final ticks = <(int, int)>[];
        final fst = await Lxt2FstConverter().convertBytes(
          fx.bytes,
          onProgress: (done, total) => ticks.add((done, total)),
        );
        expect(fst, isNotEmpty, reason: 'converter returned no FST bytes');
        expect(ticks, isNotEmpty, reason: 'no progress reported');
        expect(ticks.last.$1, ticks.last.$2, reason: 'progress ends at total');

        final provider = WellenWasmProvider();
        addTearDown(provider.close);
        await provider.openBytes(fst, '${fx.name}.fst');
        await _expectMatchesGroundTruth(provider, fx);
      },
      skip: !kIsWeb,
    );
  }

  testWidgets(
    'the converter rejects a non-legacy buffer with an error, not a crash',
    (tester) async {
      await expectLater(
        Lxt2FstConverter().convertBytes(Uint8List.fromList([0x24, 0x76, 1])),
        throwsA(isA<Lxt2FstConverterException>()),
      );
    },
    skip: !kIsWeb,
  );

  for (final format in ['LXT2', 'LXT']) {
    testWidgets(
      'openFromBytes routes a picked .${format.toLowerCase()} through the '
      'converter into a WellenWasmProvider',
      (tester) async {
        final fx = kWebLegacyFixtures.firstWhere((f) => f.format == format);

        // These two tests drive `openFromBytes` through a container of their
        // own rather than booting the app, so nothing here picks up the root
        // overrides `app.dart` spreads. `cruxTelemetryConfigProvider` is the
        // one binding in that set with no working default — it throws at
        // wiring rather than report another product's slug — so once the open
        // path started emitting telemetry, a bare container failed with
        // "cruxTelemetryConfigProvider has no default binding" and the LXT
        // assertion below was never reached. Bind the product's real override
        // list, which is what a running WaveCrux binds, so this container
        // cannot drift from the app it stands in for.
        await seedFirstLaunchAnswers();
        final container = ProviderContainer(
          overrides: [...wavecruxTelemetryOverrides],
        );
        addTearDown(container.dispose);
        final notifier = container.read(waveformSourceProvider.notifier);

        // openFromBytes waits out one frame before parsing so the loading
        // state can paint; pump frames until the open settles.
        final open = notifier.openFromBytes(fx.bytes, fx.displayName);
        var settled = false;
        unawaited(open.whenComplete(() => settled = true));
        for (var i = 0; i < 200 && !settled; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await open;

        final state = container.read(waveformSourceProvider);
        if (state case AsyncError(:final error, :final stackTrace)) {
          fail('the open failed: $error\n$stackTrace');
        }
        expect(
          state.value,
          isA<WellenWasmProvider>(),
          reason: 'a legacy open must install a WellenWasmProvider',
        );
        expect(notifier.originalFormat?.name, format.toLowerCase());
        expect(notifier.convertedAt, isNotNull);
        await _expectMatchesGroundTruth(
          state.value! as WellenWasmProvider,
          fx,
        );
      },
      skip: !kIsWeb,
    );
  }
}

/// A 4-state bit-vector value; anything else in a companion is a real.
final _bitString = RegExp(r'^[01xzXZ]+$');

/// Asserts every signal in [fx]'s companion is present in [provider] with its
/// full change history. Bit-vectors compare exactly; reals numerically, since
/// wellen may render a real in a different textual form than its source VCD.
Future<void> _expectMatchesGroundTruth(
  WellenWasmProvider provider,
  WebFixture fx,
) async {
  final byPath = {
    for (final v in provider.findVariables(const SignalFilter()))
      v.fullPath: v.signalRef,
  };
  final signals = fx.expected['signals'] as Map<String, dynamic>;
  expect(signals, isNotEmpty);
  for (final MapEntry(key: path, value: gold) in signals.entries) {
    final ref = byPath[path];
    expect(ref, isNotNull, reason: '${fx.displayName}: $path missing');
    await provider.loadSignal(ref!);
    final actual = provider.changesInRange(ref, 0, provider.endTime + 1);
    final expected = (gold as Map<String, dynamic>)['allChanges'] as List;
    expect(
      actual,
      hasLength(expected.length),
      reason: '${fx.displayName}: $path change count',
    );
    for (var i = 0; i < expected.length; i++) {
      final want = expected[i] as Map<String, dynamic>;
      final got = actual[i];
      final label = '${fx.displayName}: $path change $i';
      expect(got.time, want['time'], reason: '$label time');
      final wantValue = want['value'] as String;
      final wantReal = _bitString.hasMatch(wantValue)
          ? null
          : double.tryParse(wantValue);
      final gotReal = double.tryParse(got.value);
      if (wantReal != null && gotReal != null) {
        expect(gotReal, closeTo(wantReal, 1e-12), reason: '$label value');
      } else {
        expect(got.value, wantValue, reason: '$label value');
      }
    }
  }
}
