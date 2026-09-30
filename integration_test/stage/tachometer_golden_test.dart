// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/stage/tachometer_golden_test.dart
//
// Tachometer visual-finalization pass — golden baselines for the beautified
// Rive artboard (assets/stage/widgets/rive/runtime/tachometer.riv). Replaces
// the deferred stub at
// test/features/stage/widgets/tachometer/tachometer_golden_test.dart, which
// could never render the real artboard: RiveNative.init fails to resolve its
// FFI symbol under headless `flutter test`, so the artboard only paints on a
// real desktop/device runtime (this integration_test target on macOS).
//
// Matrix: 3 RPM stops (0 / 50 / 100 %) × redline {off, on} at 2 MobileMetrics
// surfaces (tablet, phone) = 12 baselines, under
// integration_test/stage/goldens/tachometer/.
//
// WHY DRIVE THE ARTBOARD DIRECTLY (not through TachometerStageRenderer +
// waveformSourceProvider): the goldens exist to pin the GAUGE'S VISUALS at a
// known input state — needle deflection at each rpm, redline glow on/off. The
// deferred stub's recipe suggested routing rpm through the full
// stageBoundSignalProvider → normalizer → cursor pipeline, but that couples a
// pure-visual golden to the value-mapping layer, which is already exhaustively
// unit-tested (tachometer_input_mapper_test / tachometer_rpm_normalizer_test)
// and would inject nondeterminism (cursor timing, async signal load) into an
// image comparison. Instead we mount the real artboard + StateMachinePainter
// and push the exact normalized inputs through the production
// RiveBackedAnimationController — the SAME type routing the renderer uses —
// then capture. The renderer's own asset-load / placeholder / fit-into-panel
// behavior is covered by tachometer_stage_renderer_test (headless placeholder
// branches) + the tachometer_rive_test controller contract; these goldens
// isolate the finished visual.
//
// The captured RiveArtboardWidget paints into the Flutter Canvas
// (FlutterRiveRenderBox — the artboard decodes with Factory.flutter), so
// matchesGoldenFile rasterizes the real gauge pixels rather than an empty
// platform-texture layer. devicePixelRatio is pinned to 1.0 for stable
// dimensions; the baselines are authored ON THE CI MACOS RUNNER — "macOS" on
// its own is not specific enough, because a dev Mac and the runner diff these
// curve-dense artboards by ~1% (Rive's Flutter renderer is Skia-backed, so
// neither cross-OS nor cross-host pixel parity is guaranteed). Rebaseline with
// .github/workflows/rebaseline-goldens.yml, not `--update-goldens` locally. The comparison is
// therefore GATED to the macOS golden host — the Windows/Linux integration legs
// skip these tests (via [_skipOffGoldenHost]) rather than diff an artboard we
// never rebaseline for them (Windows diffs the same gauge by 1–2%). Even on
// macOS, successive CI runner images shift antialiasing by a fraction of a
// percent, so a small pixel tolerance ([_goldenTolerance]) absorbs that
// environment noise; a wrong gauge state (needle at the wrong rpm, redline glow
// toggled) diverges by orders of magnitude more and still fails.

import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wavecrux/features/stage/runtime/rive_backed_animation_controller.dart';
import 'package:wavecrux/features/stage/runtime/rive_runtime_state_machine_host.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';

import '../helpers/app_driver.dart';

const _tachometerRivAsset = 'assets/stage/widgets/rive/runtime/tachometer.riv';

/// MobileMetrics gauge-cell surfaces. The tachometer's natural aspect is
/// 320 × 220 (`TachometerStageWidget.defaultSize`); a tablet Stage panel
/// affords a larger cell than a phone. Both at devicePixelRatio 1.0 so the
/// golden files are deterministic.
const _surfaces = <(String, double, double)>[
  ('tablet', 384, 264),
  ('phone', 240, 165),
];

const _rpmStops = <(String, double)>[
  ('0pct', 0.0),
  ('50pct', 0.5),
  ('100pct', 1.0),
];

/// Skip the golden comparison off the macOS golden host (see file header): the
/// baselines are macOS-authored and Rive's Skia renderer is not pixel-identical
/// across OSes, so the Windows/Linux integration legs must not diff artboards
/// we never rebaseline for them.
final bool _skipOffGoldenHost = !Platform.isMacOS;

/// Fraction of differing pixels (0..1) still treated as a match on the golden
/// host. The Jul 2026 macOS runner diffs the committed baselines by ~0.09%
/// (pure antialiasing drift); 0.5% leaves generous headroom while a real visual
/// regression — needle at the wrong rpm, redline glow toggled — diverges by far
/// more.
///
/// **Do not raise this to paper over a host mismatch.** Measured 2026-09-06:
/// baselines regenerated on a dev Mac diffed the CI macOS runner by
/// 0.86%–1.35% on these artboards. A tolerance wide enough to absorb that
/// would also absorb a needle at the wrong rpm, which moves only ~0.9% of the
/// pixels on the phone artboard — i.e. it would blind the test to the first
/// thing it is meant to catch. The fix for a host mismatch is to rebaseline
/// ON the golden host (`.github/workflows/rebaseline-goldens.yml`), never to
/// widen the tolerance.
const double _goldenTolerance = 0.005;

/// [LocalFileComparator] that tolerates sub-percent antialiasing drift on the
/// golden host, mirroring the Flutter cookbook tolerant-comparator pattern. A
/// diff at or under [tolerance] passes; anything larger still throws the normal
/// pixel-diff failure with its side-by-side output.
class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(super.testFile, {required this.tolerance});

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      return true;
    }
    throw FlutterError(await generateFailureOutput(result, golden, basedir));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  // Wrap the framework's local comparator so sub-percent AA drift on the macOS
  // golden host does not fail an otherwise-correct gauge. Done in setUp, not at
  // main() scope: the framework only installs the test-file-relative
  // LocalFileComparator (with the correct basedir) once the file's tests begin,
  // so capturing it too early would inherit the wrong root. Reusing basedir
  // keeps golden paths resolving unchanged; the guard avoids re-wrapping our own
  // comparator. Only relevant on macOS — the tests skip elsewhere via
  // [_skipOffGoldenHost].
  setUp(() {
    final current = goldenFileComparator;
    if (current is LocalFileComparator &&
        current is! _TolerantGoldenComparator) {
      // Hand the constructor a FILE inside basedir, not the directory itself:
      // LocalFileComparator derives its own basedir via `Uri.resolve('.')`,
      // which climbs one level, so passing the bare directory would drop the
      // final path segment and misresolve every golden.
      goldenFileComparator = _TolerantGoldenComparator(
        current.basedir.resolve('tachometer_golden_test.dart'),
        tolerance: _goldenTolerance,
      );
    }
  });

  for (final (surfaceLabel, width, height) in _surfaces) {
    for (final (rpmLabel, rpmValue) in _rpmStops) {
      for (final redline in const [false, true]) {
        final redlineLabel = redline ? 'redline_on' : 'redline_off';
        final goldenName =
            'tachometer_${surfaceLabel}_${rpmLabel}_$redlineLabel';

        testWidgets('golden $goldenName', (tester) async {
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final loaded = await loadRiveFileForStageWidget(
            assetPath: _tachometerRivAsset,
          );
          final painter = rive.RivePainter.stateMachine(
            stateMachineName: 'Tachometer',
          );
          addTearDown(() {
            painter.dispose();
            loaded.file.dispose();
          });

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: rive.RiveArtboardWidget(
                        artboard: loaded.artboard,
                        painter: painter,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          final ready = await pumpUntil(
            tester,
            () => painter.stateMachine != null,
            timeout: const Duration(seconds: 5),
          );
          expect(ready, isTrue, reason: 'Tachometer state machine resolves');

          final host = RiveRuntimeStateMachineHost(
            stateMachine: painter.stateMachine!,
          );
          final controller = RiveBackedAnimationController(host: host);
          addTearDown(controller.dispose);
          controller
            ..setInput('rpm', NormalizedDouble(rpmValue))
            ..setInput('redline', NormalizedBool(value: redline))
            // shift held low — the pulse animation is edge-triggered and
            // must not fire during a static golden capture.
            ..setInput('shift', const NormalizedBool(value: false));

          // Advance the needle-deflection blend to steady state. A bounded
          // frame loop (never pumpAndSettle — the gauge's idle ticker never
          // settles) gives the blend ~0.6 s to converge on the target angle.
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          await expectLater(
            find.byType(RepaintBoundary).first,
            matchesGoldenFile('goldens/tachometer/$goldenName.png'),
          );
        }, skip: _skipOffGoldenHost);
      }
    }
  }
}
