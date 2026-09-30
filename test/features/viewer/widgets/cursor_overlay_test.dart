// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/cursor_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

// ── test helpers ──────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 800, height: 400, child: child),
        ),
      ),
    );

/// [TimeMapperNotifier] that starts fit-all over [0, 1000] at 800 px width.
class _InitializedTimeMapperNotifier extends TimeMapperNotifier {
  @override
  TimeMapper build() => TimeMapper.fitAll(
    startTime: 0,
    endTime: 1000,
    viewportWidth: 800,
  );
}

/// [CursorStateNotifier] pre-loaded with primary at 200, secondary at 600.
class _PreloadedCursorNotifier extends CursorStateNotifier {
  @override
  CursorState build() => const CursorState(
    primaryCursorTime: 200,
    secondaryCursorTime: 600,
  );
}

void main() {
  group('CursorOverlay', () {
    testWidgets('renders without exceptions when both cursors are null', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const CursorOverlay()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exceptions with primary cursor only', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CursorOverlay(),
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(() {
              return _PrimaryOnlyCursorNotifier();
            }),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exceptions with both cursors and delta', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CursorOverlay(),
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
            cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'is wrapped in a RepaintBoundary so cursor changes are layer-isolated',
      (tester) async {
        // The architectural guarantee that motivates this widget: cursor moves
        // must not invalidate the lane painter behind it. Verify the
        // RepaintBoundary is present in the rendered tree.
        await tester.pumpWidget(_wrap(const CursorOverlay()));
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(CursorOverlay),
            matching: find.byType(RepaintBoundary),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'is wrapped in IgnorePointer so it does not block touch gestures',
      (tester) async {
        // Mobile (iOS/iPadOS/Android) and the WaveformGestureHandler underneath
        // depend on this — pinch-zoom, drag-pan, tap, and long-press must
        // continue to reach the canvas with the overlay stacked above.
        await tester.pumpWidget(_wrap(const CursorOverlay()));
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(CursorOverlay),
            matching: find.byType(IgnorePointer),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('locale sweep — no exceptions in en/zh_CN/ja/ko', (
      tester,
    ) async {
      const locales = [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ];
      for (final locale in locales) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              timeMapperProvider.overrideWith(
                _InitializedTimeMapperNotifier.new,
              ),
              cursorStateProvider.overrideWith(_PreloadedCursorNotifier.new),
            ],
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 400,
                  child: CursorOverlay(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'CursorOverlay threw under locale $locale',
        );
      }
    });

    testWidgets(
      'cursor state change rebuilds without throwing (smooth scrub path)',
      (tester) async {
        // Simulates the scrubbing cursor path: an external state change updates
        // the cursor multiple times in a row. The overlay must rebuild cleanly
        // for every step.
        final container = ProviderContainer(
          overrides: [
            timeMapperProvider.overrideWith(_InitializedTimeMapperNotifier.new),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 400,
                  child: CursorOverlay(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Scrub through 10 cursor positions.
        final notifier = container.read(cursorStateProvider.notifier);
        for (var t = 100; t <= 900; t += 100) {
          notifier.placePrimary(t);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'CursorOverlay threw during scrub at t=$t',
          );
        }
      },
    );
  });
}

class _PrimaryOnlyCursorNotifier extends CursorStateNotifier {
  @override
  CursorState build() => const CursorState(primaryCursorTime: 250);
}
