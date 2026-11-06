// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/fold_state.dart';
import 'package:wavecrux/features/panes/providers/split_pane_allowed_provider.dart';
import 'package:wavecrux/features/viewer/hinge_zoom.dart';
import 'package:wavecrux/services/platform/fold_source.dart';
import 'package:wavecrux/shared/layouts/fold_layout.dart';
import 'package:wavecrux/shared/layouts/fold_local_crease.dart';
import 'package:wavecrux/shared/layouts/fold_state_provider.dart';
import 'package:wavecrux/shared/widgets/fold_feed.dart';

// iPhone Duo inner panel as published (D4 measures the real figure): about
// 669 × 951 pt upright, with a 40 pt division region across the middle.
const _upright = Size(669, 951);
const _horizontalCrease = Rect.fromLTWH(0, 455.5, 669, 40);
const _verticalCrease = Rect.fromLTWH(455.5, 0, 40, 669);

class _FakeFoldSource implements FoldSource {
  _FakeFoldSource(this.events);
  final Stream<FoldState> events;
  @override
  Stream<FoldState> watch() => events;
}

void main() {
  group('FoldState.posture', () {
    test('none without a hinge', () {
      expect(FoldState.none.posture, FoldPosture.none);
      expect(FoldState.none.hasHinge, isFalse);
    });

    test('a crease counts only while partly open', () {
      for (final status in [HingeStatus.closed, HingeStatus.fullyOpen]) {
        expect(
          FoldState(status: status, crease: _horizontalCrease).posture,
          FoldPosture.none,
          reason:
              '$status: regions lag the hinge, so a flat device can '
              'still report an active division for a moment',
        );
      }
    });

    test('horizontal crease is tabletop, vertical is book', () {
      expect(
        const FoldState(
          status: HingeStatus.partiallyOpen,
          crease: _horizontalCrease,
        ).posture,
        FoldPosture.tabletop,
      );
      expect(
        const FoldState(
          status: HingeStatus.partiallyOpen,
          crease: _verticalCrease,
        ).posture,
        FoldPosture.book,
      );
    });

    test('partly open with no crease yet is none', () {
      expect(
        const FoldState(status: HingeStatus.partiallyOpen).posture,
        FoldPosture.none,
      );
    });
  });

  group('foldStateFromPlatformEvent', () {
    test('decodes status, angle (degrees) and crease', () {
      final s = foldStateFromPlatformEvent({
        'status': 'partiallyOpen',
        'angle': 95.0,
        'crease': [0, 455.5, 669, 40],
      });
      expect(s.status, HingeStatus.partiallyOpen);
      expect(s.hingeAngle, 95.0);
      expect(s.crease, _horizontalCrease);
      expect(s.posture, FoldPosture.tabletop);
    });

    test('anything malformed is FoldState.none, never a throw', () {
      for (final bad in <Object?>[
        null,
        'partiallyOpen',
        <String, Object>{},
        {'status': 'sideways'},
        {
          'status': 'none',
          'crease': [0, 0, 10, 10],
        },
      ]) {
        expect(foldStateFromPlatformEvent(bad), FoldState.none, reason: '$bad');
      }
    });

    test('a degenerate or non-numeric crease is dropped, the hinge kept', () {
      for (final crease in <Object?>[
        [0, 0, 0, 40],
        [0, 0, 669],
        ['a', 0, 1, 1],
        [0, 0, double.infinity, 40],
      ]) {
        final s = foldStateFromPlatformEvent({
          'status': 'partiallyOpen',
          'crease': crease,
        });
        expect(s.status, HingeStatus.partiallyOpen);
        expect(s.crease, isNull, reason: '$crease');
      }
    });
  });

  group('applyFlatBand', () {
    FoldState partly(double angle) => FoldState(
      status: HingeStatus.partiallyOpen,
      hingeAngle: angle,
      crease: _verticalCrease,
    );

    test('a nearly flat hinge lays out as flat', () {
      // The simulator passes through ~174° on its way to 180°.
      final r = applyFlatBand(partly(174), wasFlat: false);
      expect(r.flat, isTrue);
      expect(r.state.status, HingeStatus.fullyOpen);
      expect(r.state.posture, FoldPosture.none);
    });

    test("the simulator's 134° open is still half-folded", () {
      final r = applyFlatBand(partly(134), wasFlat: false);
      expect(r.flat, isFalse);
      expect(r.state.posture, FoldPosture.book);
    });

    test('hysteresis: enter at 160°, leave below 150°', () {
      expect(applyFlatBand(partly(155), wasFlat: false).flat, isFalse);
      expect(applyFlatBand(partly(155), wasFlat: true).flat, isTrue);
      expect(applyFlatBand(partly(149), wasFlat: true).flat, isFalse);
    });

    test('closed and no-hinge readings pass through and reset the band', () {
      const closed = FoldState(status: HingeStatus.closed, hingeAngle: 0);
      final r = applyFlatBand(closed, wasFlat: true);
      expect(r.state, closed);
      expect(r.flat, isFalse);
      expect(
        applyFlatBand(FoldState.none, wasFlat: true).state,
        FoldState.none,
      );
    });
  });

  group('foldStateFromDisplayFeatures (Android)', () {
    test('no fold feature is none', () {
      expect(foldStateFromDisplayFeatures(const []), FoldState.none);
      expect(
        foldStateFromDisplayFeatures(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(10, 0, 50, 30),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ]),
        FoldState.none,
      );
    });

    test(
      'half-opened fold is partly open; a zero-width line becomes a band',
      () {
        final s = foldStateFromDisplayFeatures(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 400, 600, 0),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ]);
        expect(s.status, HingeStatus.partiallyOpen);
        expect(s.crease!.height, kMinCreaseBand);
        expect(s.crease!.center.dy, 400);
        expect(s.posture, FoldPosture.tabletop);
      },
    );

    test('flat fold is fully open, so no posture', () {
      final s = foldStateFromDisplayFeatures(const [
        DisplayFeature(
          bounds: Rect.fromLTWH(400, 0, 0, 600),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ]);
      expect(s.status, HingeStatus.fullyOpen);
      expect(s.posture, FoldPosture.none);
    });
  });

  group('tabletopSplit', () {
    test('puts the dock boundary on the crease centre line', () {
      // Dock area 800 tall, crease 40 tall centred at 420.
      final split = tabletopSplit(const Rect.fromLTWH(0, 400, 669, 40), 800);
      expect(split, isNotNull);
      expect(split!.bottomSize, 380);
      expect(split.inset, 20);
    });

    test('null without a horizontal crease', () {
      expect(tabletopSplit(null, 800), isNull);
      expect(tabletopSplit(_verticalCrease, 800), isNull);
    });

    test('null when either half would be unusably short', () {
      expect(tabletopSplit(const Rect.fromLTWH(0, 60, 669, 40), 800), isNull);
      expect(tabletopSplit(const Rect.fromLTWH(0, 700, 669, 40), 800), isNull);
    });
  });

  group('bookSplit', () {
    test('one pane per page, crease as the gap', () {
      final split = bookSplit(const Rect.fromLTWH(455, 0, 40, 600), 951);
      expect(split, (leftWidth: 455.0, gap: 40.0, rightWidth: 456.0));
    });

    test('null without a vertical crease or with a sliver pane', () {
      expect(bookSplit(null, 951), isNull);
      expect(bookSplit(_horizontalCrease, 951), isNull);
      expect(bookSplit(const Rect.fromLTWH(120, 0, 40, 600), 951), isNull);
    });
  });

  group('isSplitPaneAllowed on a foldable', () {
    test('tablet threshold drops to 900 only with a hinge', () {
      expect(isSplitPaneAllowed(DeviceClass.tablet, 951), isFalse);
      expect(
        isSplitPaneAllowed(DeviceClass.tablet, 951, foldable: true),
        isTrue,
      );
      expect(
        isSplitPaneAllowed(DeviceClass.tablet, 669, foldable: true),
        isFalse,
        reason: 'inner panel upright stays one pane',
      );
      expect(
        isSplitPaneAllowed(DeviceClass.phone, 951, foldable: true),
        isFalse,
      );
    });
  });

  group('hingeZoomStep', () {
    test('dead band keeps the reference', () {
      expect(hingeZoomStep(100, 101.5), isNull);
      expect(hingeZoomStep(100, 98.5), isNull);
    });

    test('closing towards you zooms in, opening zooms out', () {
      final closer = hingeZoomStep(110, 95)!;
      expect(closer.zoomIn, isTrue);
      expect(closer.factor, closeTo(2, 1e-9));
      final away = hingeZoomStep(95, 125)!;
      expect(away.zoomIn, isFalse);
      expect(away.factor, closeTo(4, 1e-9));
    });
  });

  group('FoldFeed', () {
    testWidgets('no hinge: provider stays none and MediaQuery is untouched', (
      tester,
    ) async {
      late List<DisplayFeature> seen;
      final container = ProviderContainer(
        overrides: [
          foldSourceProvider.overrideWithValue(
            _FakeFoldSource(const Stream.empty()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(size: _upright),
            child: FoldFeed(
              child: Builder(
                builder: (context) {
                  seen = MediaQuery.displayFeaturesOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(container.read(foldStateProvider), FoldState.none);
      expect(seen, isEmpty);
    });

    testWidgets(
      'native tabletop: provider follows, crease added to MediaQuery, '
      'removed again when flat',
      (tester) async {
        late List<DisplayFeature> seen;
        final controller = StreamController<FoldState>();
        addTearDown(controller.close);
        final container = ProviderContainer(
          overrides: [
            foldSourceProvider.overrideWithValue(
              _FakeFoldSource(controller.stream),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: const MediaQueryData(size: _upright),
              child: FoldFeed(
                child: Builder(
                  builder: (context) {
                    seen = MediaQuery.displayFeaturesOf(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        );
        const tabletop = FoldState(
          status: HingeStatus.partiallyOpen,
          hingeAngle: 100,
          crease: _horizontalCrease,
        );
        controller.add(tabletop);
        await tester.pump();
        await tester.pump();
        expect(container.read(foldStateProvider), tabletop);
        expect(container.read(foldPostureProvider), FoldPosture.tabletop);
        expect(seen, hasLength(1));
        expect(seen.single.bounds, _horizontalCrease);
        expect(seen.single.type, DisplayFeatureType.fold);

        controller.add(
          const FoldState(status: HingeStatus.fullyOpen, hingeAngle: 180),
        );
        await tester.pump();
        await tester.pump();
        expect(container.read(foldPostureProvider), FoldPosture.none);
        expect(seen, isEmpty);
      },
    );
  });

  group('FoldLocalCrease', () {
    testWidgets('null without a fold; local rect once half-folded', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final seen = <Rect?>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              // The measured box starts 100 px down, like a dock area below
              // a toolbar.
              padding: const EdgeInsets.only(top: 100),
              child: FoldLocalCrease(
                posture: FoldPosture.tabletop,
                builder: (context, crease) {
                  seen.add(crease);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen.last, isNull);

      container
          .read(foldStateProvider.notifier)
          .set(
            const FoldState(
              status: HingeStatus.partiallyOpen,
              crease: Rect.fromLTWH(0, 400, 800, 40),
            ),
          );
      await tester.pump();
      await tester.pump();
      expect(seen.last, const Rect.fromLTWH(0, 300, 800, 40));

      // Book posture is not asked for here.
      container
          .read(foldStateProvider.notifier)
          .set(
            const FoldState(
              status: HingeStatus.partiallyOpen,
              crease: Rect.fromLTWH(380, 0, 40, 600),
            ),
          );
      await tester.pump();
      expect(seen.last, isNull);
    });
  });
}
