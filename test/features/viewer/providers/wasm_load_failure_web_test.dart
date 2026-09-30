// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// test/features/viewer/providers/wasm_load_failure_web_test.dart
//
// WASM-load-failure path, exercised for real on the web.
//
// `WaveformSourceNotifier.openFromBytes` is the single web open path. When the
// `wellen` WebAssembly module cannot load — a CSP that blocks `unsafe-eval`, an
// ancient browser, or simply the loader script not being present — it must fail
// with [WebAssemblyRequiredError] for every supported format (VCD, FST, GHW),
// and `WaveformViewCenter` must render the "WebAssembly is required" guidance UI
// rather than a generic parse error.
//
// This runs under `flutter test --platform chrome` (`@TestOn('browser')`), so
// `kIsWeb` is true and the real web `WellenWasmProvider` implementation is
// compiled in. Crucially, the bare Chrome test harness does NOT inject
// `web/index.html`'s `wellen_wasm_loader.js`, so `globalThis.waveCruxWellen` is
// absent and `WellenWasmProvider.ensureInitialized()` genuinely throws — i.e.
// the module-load failure is real, not mocked. The desktop widget test in
// `test/features/viewer/widgets/waveform_view_center_test.dart` asserts the
// same guidance UI from a hand-injected error state; this test proves the live
// open path actually reaches that state.
//
// Skipped on the VM runner via `@TestOn('browser')` — the failure path it
// exercises only exists on web (desktop/mobile use the FFI provider).
@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_view_center.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider.dart';

// Minimal payloads keyed by the extension the open path detects. The bytes are
// never parsed: `openFromBytes` fails at `ensureInitialized()` — before any
// format detection — so a placeholder buffer per format is sufficient to prove
// the failure is format-independent. (A real VCD body is used for the VCD case
// so the test still documents the "valid file, dead WASM" scenario.)
const _vcd =
    '\$timescale 1 ns \$end\n\$scope module top \$end\n'
    '\$var wire 1 ! clk \$end\n\$upscope \$end\n\$enddefinitions \$end\n'
    '\$dumpvars\n0!\n\$end\n#10\n1!\n';

final _payloads = <String, Uint8List>{
  'x.vcd': Uint8List.fromList(_vcd.codeUnits),
  'x.fst': Uint8List.fromList(const [0, 0, 0, 0, 0, 0, 0, 1]),
  'x.ghw': Uint8List.fromList('GHDLwave\n'.codeUnits),
};

/// Runs the real web open to completion under the widget-test clock.
///
/// `openFromBytes` waits for one painted frame before it starts, so the
/// "Parsing…" placeholder is on screen for the length of a synchronous WASM
/// parse. A test binding paints only when told to, so an open that nothing
/// pumps waits for that frame forever, which is what these tests did as plain
/// `test()`s: every case hung until its timeout, and the provider then threw
/// from a container the teardown had already disposed. One pump produces the
/// frame; the rest of the failing open is microtasks. The last pump advances
/// the clock by zero, which fires the zero-duration timer the open leaves
/// behind; a pump with no duration only paints, so the timer would still be
/// pending when the test ends, and that fails it.
Future<void> _openUnderTestClock(
  WidgetTester tester,
  ProviderContainer container,
  Uint8List bytes,
  String displayName,
) async {
  final open = container
      .read(waveformSourceProvider.notifier)
      .openFromBytes(bytes, displayName);
  await tester.pump();
  await open;
  await tester.pump(Duration.zero);
}

void main() {
  for (final entry in _payloads.entries) {
    final displayName = entry.key;
    final bytes = entry.value;
    final format = displayName.split('.').last.toUpperCase();

    testWidgets(
      'open path raises WebAssemblyRequiredError when WASM is unavailable '
      '($format)',
      (tester) async {
        // Force a fresh init attempt so the failure is observed per-format
        // rather than served from the first call's cached future.
        WellenWasmProvider.resetInitForTests();
        expect(kIsWeb, isTrue, reason: 'this test only runs under Chrome');

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await _openUnderTestClock(tester, container, bytes, displayName);

        final state = container.read(waveformSourceProvider);
        expect(
          state,
          isA<AsyncError<dynamic>>(),
          reason: '$format open must fail when the WASM module is absent',
        );
        expect(
          (state as AsyncError).error,
          isA<WebAssemblyRequiredError>(),
          reason:
              '$format must surface WebAssemblyRequiredError, not a '
              'generic parse error',
        );
      },
    );
  }

  testWidgets(
    'WaveformViewCenter shows the WebAssembly-required guidance UI after a '
    'real failed web open',
    (tester) async {
      WellenWasmProvider.resetInitForTests();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Drive the real open path to the real failure state.
      await _openUnderTestClock(
        tester,
        container,
        _payloads['x.vcd']!,
        'x.vcd',
      );
      expect(
        (container.read(waveformSourceProvider) as AsyncError).error,
        isA<WebAssemblyRequiredError>(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
          ),
        ),
      );
      await tester.pump();

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.waveformCenterWebAssemblyRequiredTitle),
        findsOneWidget,
      );
      expect(
        find.text(l10n.waveformCenterWebAssemblyRequiredMessage),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      // Generic-error chrome must NOT be shown for this path.
      expect(find.byIcon(Icons.error_outline), findsNothing);
    },
  );
}
