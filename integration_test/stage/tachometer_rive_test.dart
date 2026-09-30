// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/stage/tachometer_rive_test.dart
//
// Tachometer visual-finalization pass — the REAL rive_native runtime
// coverage that cannot run under headless `flutter test` (RiveNative.init
// fails to resolve its FFI `init` symbol there). This file replaces the
// deferred stub bodies of the former
// test/features/stage/widgets/tachometer/tachometer_rive_controller_integration_test.dart.
//
// What it covers, against the bundled tachometer.riv authored to the
// Rive binding contract (assets/stage/widgets/rive/README.md):
//
//   1. RiveBackedAnimationController type routing — NormalizedDouble →
//      Number input, NormalizedBool → Boolean input, NormalizedXZ holds the
//      previous Number value, and the shift Boolean's rising/falling edge is
//      delivered to the state machine. These drive the controller against
//      the production RiveRuntimeStateMachineHost wrapping the real resolved
//      StateMachine, then read the input value back off the state machine.
//   2. Renderer full-Rive smoke — TachometerStageRenderer, fed a non-null
//      waveform source + bound-signal snapshots, mounts the real
//      RiveArtboardWidget rather than an asset-error / not-ready placeholder,
//      exercising the renderer's own manifest → asset → state-machine-
//      validation → mount glue end to end.
//   3. Locale sweep + surface metrics — every placeholder path renders
//      without throwing in en / zh_CN / ja / ko, and the bound state lays
//      out cleanly at the tablet and phone surfaces used elsewhere in the
//      suite's mobile coverage. Promoted verbatim from the former
//      tachometer_stage_renderer_test.dart (deleted — this was its entire
//      content), whose mount tests could never run headless: mounting the
//      renderer calls `RiveNative.init()` in `initState` regardless of
//      binding state, and the pure-Dart `flutter test` process cannot
//      resolve that FFI symbol (no host app build links the native Rive
//      runtime). This file already proves the same `RiveNative.init()` call
//      resolves on a real desktop runtime, so the placeholder + layout
//      assertions now run for real instead of being skipped.
//
// The finished VISUALS (needle deflection per rpm, redline glow) are pinned
// separately by the golden baselines in tachometer_golden_test.dart.

// The tests read state-machine input values back via `StateMachine.number /
// boolean`, which the Rive 0.14 SDK marks `@Deprecated` in favor of data
// binding. The Stage Pro SDK contract is built on
// state-machine inputs by name — see RiveRuntimeStateMachineHost for the
// rationale. The deprecation is suppressed at file scope, matching the
// runtime host + renderer that consume the same API.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/runtime/rive_backed_animation_controller.dart';
import 'package:wavecrux/features/stage/runtime/rive_runtime_state_machine_host.dart';
import 'package:wavecrux/features/stage/runtime/stage_widget_animation_controller.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../test/helpers/fake_waveform_data_source.dart';
import '../helpers/app_driver.dart';

const _tachometerRivAsset = 'assets/stage/widgets/rive/runtime/tachometer.riv';
const _stateMachineName = 'Tachometer';

const _rpmBinding = StageSignalBinding(signalRef: 'top.engine.rpm');
const _redlineBinding = StageSignalBinding(signalRef: 'top.engine.redline');
const _shiftBinding = StageSignalBinding(signalRef: 'top.engine.shift');

const _boundInstance = StageInstance(
  id: 'i_smoke',
  widgetId: TachometerStageWidget.widgetId,
  signalBindings: {
    'rpm': _rpmBinding,
    'redline': _redlineBinding,
    'shift': _shiftBinding,
  },
);

/// Seeds a non-null waveform source so the renderer clears its no-file
/// placeholder guard and reaches the RiveArtboardWidget mount path.
class _FakeWaveformSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      AsyncData(FakeWaveformDataSource());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  /// Loads the real tachometer artboard, mounts a StateMachinePainter that
  /// resolves the 'Tachometer' state machine, pumps a RiveArtboardWidget
  /// until the state machine is available, and returns it wrapped in the
  /// production host + controller. The returned StateMachine lets the test
  /// read input values back after the controller writes them.
  Future<(rive.StateMachine, RiveBackedAnimationController)> mount(
    WidgetTester tester,
  ) async {
    final loaded = await loadRiveFileForStageWidget(
      assetPath: _tachometerRivAsset,
    );
    final painter = rive.RivePainter.stateMachine(
      stateMachineName: _stateMachineName,
    );
    addTearDown(() {
      painter.dispose();
      loaded.file.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 220,
              child: rive.RiveArtboardWidget(
                artboard: loaded.artboard,
                painter: painter,
              ),
            ),
          ),
        ),
      ),
    );

    // The painter resolves + exposes the state machine in artboardChanged,
    // which fires once the RenderBox attaches the artboard on first
    // layout/paint. Poll until it is available (bounded — never a bare
    // pumpAndSettle, which would spin forever on the gauge's idle ticker).
    final ready = await pumpUntil(
      tester,
      () => painter.stateMachine != null,
      timeout: const Duration(seconds: 5),
    );
    expect(
      ready,
      isTrue,
      reason:
          'StateMachinePainter should resolve the "$_stateMachineName" state '
          'machine on the bundled tachometer.riv',
    );

    final stateMachine = painter.stateMachine!;
    final host = RiveRuntimeStateMachineHost(stateMachine: stateMachine);
    final controller = RiveBackedAnimationController(host: host);
    addTearDown(controller.dispose);
    return (stateMachine, controller);
  }

  group(
    'TachometerRiveBackedAnimationController — type routing',
    () {
      testWidgets(
        'NormalizedDouble for rpm routes to the Rive Number input',
        (tester) async {
          final (sm, controller) = await mount(tester);

          final result = controller.setInput(
            'rpm',
            const NormalizedDouble(0.5),
          );

          expect(result.kind, SetInputResultKind.applied);
          expect(
            sm.number('rpm')?.value,
            closeTo(0.5, 1e-6),
            reason: 'NormalizedDouble must write the matching Number input',
          );
        },
      );

      testWidgets(
        'NormalizedBool for redline routes to the Rive Boolean input',
        (tester) async {
          final (sm, controller) = await mount(tester);

          final result = controller.setInput(
            'redline',
            const NormalizedBool(value: true),
          );

          expect(result.kind, SetInputResultKind.applied);
          expect(
            sm.boolean('redline')?.value,
            isTrue,
            reason: 'NormalizedBool must flip the matching Boolean input',
          );

          controller.setInput('redline', const NormalizedBool(value: false));
          expect(sm.boolean('redline')?.value, isFalse);
        },
      );

      testWidgets(
        'NormalizedXZ holds the previous Number value',
        (tester) async {
          final (sm, controller) = await mount(tester);

          controller.setInput('rpm', const NormalizedDouble(0.42));
          expect(sm.number('rpm')?.value, closeTo(0.42, 1e-6));

          final result = controller.setInput(
            'rpm',
            const NormalizedXZ(isX: true),
          );

          expect(
            result.kind,
            SetInputResultKind.heldStale,
            reason: 'NormalizedXZ must report held-stale, not applied',
          );
          expect(
            sm.number('rpm')?.value,
            closeTo(0.42, 1e-6),
            reason:
                'NormalizedXZ must LEAVE the Number input at its previous '
                'value — not zero or NaN it',
          );
        },
      );

      testWidgets(
        'shift Boolean rising + falling edges reach the state machine',
        (tester) async {
          // shift is a Boolean input (NormalizedBool → BooleanInput per the
          // binding contract); the redline-pulse edge detection lives INSIDE
          // the artboard's state machine, not in the runtime (the runtime
          // does not use a Rive Trigger here — see the README). So the
          // runtime-observable contract is that each edge is delivered to
          // the Boolean input; the pulse animation the artboard plays off
          // that edge is a visual detail covered by the golden pass, not a
          // runtime-input assertion.
          final (sm, controller) = await mount(tester);

          // Rising edge.
          final rising = controller.setInput(
            'shift',
            const NormalizedBool(value: true),
          );
          expect(rising.kind, SetInputResultKind.applied);
          expect(sm.boolean('shift')?.value, isTrue);

          // Falling edge.
          final falling = controller.setInput(
            'shift',
            const NormalizedBool(value: false),
          );
          expect(falling.kind, SetInputResultKind.applied);
          expect(sm.boolean('shift')?.value, isFalse);
        },
      );
    },
  );

  group('Tachometer renderer — full Rive smoke', () {
    testWidgets(
      'mounts the real .riv via TachometerStageRenderer without surfacing '
      'an asset-error placeholder',
      (tester) async {
        // The renderer reaches its RiveArtboardWidget mount branch only when
        // all three pins are bound (no unbound placeholder) AND a waveform
        // source is present (no no-file placeholder). Seed both, then confirm
        // the real Rive artboard mounted rather than a _Placeholder — proving
        // the renderer's own glue (manifest parse → asset resolve → state-
        // machine validation → mount) works end to end on the real runtime,
        // which headless flutter test cannot exercise (RiveNative.init fails
        // there — the placeholder branches are covered by the locale-sweep
        // group below).
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                _FakeWaveformSourceNotifier.new,
              ),
              // Stable snapshots so the renderer's per-frame Rive writes have
              // real values and don't kick off an async signal load against
              // the fake source.
              stageBoundSignalProvider(_rpmBinding).overrideWith(
                (ref) => const StageSignalSnapshot.value(
                  rawValue: '100',
                  bitWidth: 16,
                ),
              ),
              stageBoundSignalProvider(_redlineBinding).overrideWith(
                (ref) => const StageSignalSnapshot.value(
                  rawValue: '1',
                  bitWidth: 1,
                ),
              ),
              stageBoundSignalProvider(_shiftBinding).overrideWith(
                (ref) => const StageSignalSnapshot.value(
                  rawValue: '0',
                  bitWidth: 1,
                ),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    height: 220,
                    child: TachometerStageRenderer(
                      instance: _boundInstance,
                      widget: TachometerStageWidget(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Wait for the async runtime init (manifest + .riv load + state-
        // machine resolve) to mount the artboard.
        final mounted = await pumpUntil(
          tester,
          () => find.byType(rive.RiveArtboardWidget).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 8),
        );

        expect(
          mounted,
          isTrue,
          reason:
              'the renderer should mount a RiveArtboardWidget (not the '
              'asset-error / not-ready placeholder) once bound + a source '
              'is present',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('TachometerStageRenderer — locale sweep (real Rive runtime)', () {
    // Promoted verbatim from the former tachometer_stage_renderer_test.dart
    // (deleted — this group, plus the surface-metrics group below, was its
    // entire content): every bound-signal lookup short-circuits to no-file
    // so the renderer never reaches the per-frame Rive write path — these
    // placeholder branches are what the group exercises — but it now runs
    // where `RiveNative.init()` actually resolves, instead of being
    // `skip: true` under headless `flutter test`.
    const instanceUnbound = StageInstance(
      id: 'i_locale_unbound',
      widgetId: TachometerStageWidget.widgetId,
    );

    Widget wrapLocale({required Widget child, required Locale locale}) {
      return ProviderScope(
        overrides: [
          stageBoundSignalProvider(
            _rpmBinding,
          ).overrideWith((ref) => const StageSignalSnapshot.noFile()),
          stageBoundSignalProvider(
            _redlineBinding,
          ).overrideWith((ref) => const StageSignalSnapshot.noFile()),
          stageBoundSignalProvider(
            _shiftBinding,
          ).overrideWith((ref) => const StageSignalSnapshot.noFile()),
          stageBoundSignalProvider(
            null,
          ).overrideWith((ref) => const StageSignalSnapshot.unbound()),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: SizedBox(width: 320, height: 220, child: child),
          ),
        ),
      );
    }

    const locales = [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];

    for (final locale in locales) {
      testWidgets('renders without exceptions in $locale (unbound state)', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrapLocale(
            locale: locale,
            child: const TachometerStageRenderer(
              instance: instanceUnbound,
              widget: TachometerStageWidget(),
            ),
          ),
        );
        final rendered = await pumpUntil(
          tester,
          () => find.byType(Text).evaluate().isNotEmpty,
        );
        expect(
          rendered,
          isTrue,
          reason: 'the unbound placeholder must render text in $locale',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('renders without exceptions in $locale (bound, no file)', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrapLocale(
            locale: locale,
            child: const TachometerStageRenderer(
              instance: _boundInstance,
              widget: TachometerStageWidget(),
            ),
          ),
        );
        final rendered = await pumpUntil(
          tester,
          () => find.byType(Text).evaluate().isNotEmpty,
        );
        expect(
          rendered,
          isTrue,
          reason: 'the no-file placeholder must render text in $locale',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group(
    'TachometerStageRenderer — surface metrics (real Rive runtime)',
    () {
      // The bound-no-file placeholder must lay out cleanly at the tablet and
      // phone surfaces the rest of the suite's mobile coverage uses — no
      // RenderFlex overflow, no exceptions. Promoted verbatim from the
      // former tachometer_stage_renderer_test.dart.
      Widget wrapDefault({required Widget child}) {
        return ProviderScope(
          overrides: [
            stageBoundSignalProvider(
              _rpmBinding,
            ).overrideWith((ref) => const StageSignalSnapshot.noFile()),
            stageBoundSignalProvider(
              _redlineBinding,
            ).overrideWith((ref) => const StageSignalSnapshot.noFile()),
            stageBoundSignalProvider(
              _shiftBinding,
            ).overrideWith((ref) => const StageSignalSnapshot.noFile()),
            stageBoundSignalProvider(
              null,
            ).overrideWith((ref) => const StageSignalSnapshot.unbound()),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(width: 320, height: 220, child: child),
            ),
          ),
        );
      }

      testWidgets(
        'renders at the standard tablet surface (768 × 1024) without '
        'overflow',
        (tester) async {
          tester.view.physicalSize = const Size(768, 1024);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            wrapDefault(
              child: const TachometerStageRenderer(
                instance: _boundInstance,
                widget: TachometerStageWidget(),
              ),
            ),
          );
          final rendered = await pumpUntil(
            tester,
            () => find.byType(Text).evaluate().isNotEmpty,
          );
          expect(rendered, isTrue);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'renders at a phone surface (380 × 720) without overflow',
        (tester) async {
          tester.view.physicalSize = const Size(380, 720);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            wrapDefault(
              child: const TachometerStageRenderer(
                instance: _boundInstance,
                widget: TachometerStageWidget(),
              ),
            ),
          );
          final rendered = await pumpUntil(
            tester,
            () => find.byType(Text).evaluate().isNotEmpty,
          );
          expect(rendered, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
