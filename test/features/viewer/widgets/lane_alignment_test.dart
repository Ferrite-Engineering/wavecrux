// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_panel.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

// ── fixture ─────────────────────────────────────────────────────────────────
//
// A waveform arrangement exercising every row type plus the raw-vs-clamped
// rule: signals with custom lane heights, a signal whose stored laneHeight is
// BELOW the touch min (must clamp at render to 44 on touch, both top-level and
// nested in a group), a group header, an expanded group with children, a
// separator, and a comment. Flattens (model order) to:
//
//   0 sig 'a'        1 grp 'cpu'   2 child 'g0'   3 child 'g1' (sub-min)
//   4 separator      5 comment     6 sig 'b'      7 sig 'tiny' (sub-min)
List<SignalEntry> _fixtureEntries() => [
  // laneHeight omitted → default 30; clamps up to 44 on touch.
  SignalEntry.signal(signalRef: 'a', displayName: 'a'),
  SignalEntry.group(
    groupName: 'cpu',
    children: [
      SignalEntry.signal(signalRef: 'g0', displayName: 'g0'),
      // Stored below the 44 dp touch floor — the raw-vs-clamped guard.
      SignalEntry.signal(signalRef: 'g1', displayName: 'g1', laneHeight: 8),
    ],
  ),
  const SignalEntry.separator(),
  const SignalEntry.comment(text: 'note'),
  SignalEntry.signal(signalRef: 'b', displayName: 'b', laneHeight: 60),
  // Top-level sub-min signal — also clamps to 44 on touch.
  SignalEntry.signal(signalRef: 'tiny', displayName: 'tiny', laneHeight: 8),
];

/// The fixture, built once: signal rows are keyed by `SignalEntry.id`, which
/// is minted per instance, so the key map has to name the *same* entries the
/// panel renders.
final List<SignalEntry> _fixture = _fixtureEntries();

// model row index → the SignalListPanel widget key that renders it. Signal
// rows are keyed by identity; structural rows carry no id and stay
// positional (by top-level entry index).
String _signalListKeyForRow(int row) => switch (row) {
  0 => SignalListPanel.signalRowKeyValue(_fixture[0]), // a
  1 => 'grp_1', // cpu header
  2 => 'child_1_0', // g0
  3 => 'child_1_1', // g1
  4 => 'sep_2', // separator
  5 => 'cmt_3', // comment
  6 => SignalListPanel.signalRowKeyValue(_fixture[4]), // b
  7 => SignalListPanel.signalRowKeyValue(_fixture[5]), // tiny
  _ => throw ArgumentError.value(row, 'row', 'no key for this fixture row'),
};

class _MockSource extends Mock implements WaveformDataSource {}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _FixtureGroupsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(entries: _fixture);
}

WaveformDataSource _source() {
  final s = _MockSource();
  when(() => s.startTime).thenReturn(0);
  when(() => s.endTime).thenReturn(1000);
  when(() => s.timescale).thenReturn(null);
  when(() => s.rootScopes).thenReturn([]);
  when(() => s.isSignalLoaded(any())).thenReturn(false);
  when(() => s.changesInRange(any(), any(), any())).thenReturn([]);
  return s;
}

/// Renders the three per-row columns side by side in one tree so a single
/// pump lays them all out under the same providers.
Widget _threeColumns({Locale? locale}) => ProviderScope(
  overrides: [
    signalGroupsProvider.overrideWith(_FixtureGroupsNotifier.new),
    waveformSourceProvider.overrideWith(() => _LoadedSourceNotifier(_source())),
  ],
  child: MaterialApp(
    // iOS host → touch metrics (minLaneHeight = 44) regardless of size,
    // so the sub-min lanes exercise the render-time clamp.
    theme: WavecruxTheme.dark.copyWith(platform: TargetPlatform.iOS),
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 360,
            child: SignalListPanel(scrollController: ScrollController()),
          ),
          const SizedBox(width: 360, child: ValueColumnPanel()),
          const SizedBox(width: 360, child: WaveformCanvas()),
        ],
      ),
    ),
  ),
);

// Touch metrics: the panels resolve minLaneHeight = 44 under an iOS host.
const _metrics = LaneMetrics(minLaneHeight: 44);

double _signalListRowTop(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key))).dy;

List<double> _valueColumnRowTops(WidgetTester tester) => tester
    .widgetList<ValueColumnRow>(find.byType(ValueColumnRow))
    .toList()
    .asMap()
    .entries
    .map((e) => tester.getTopLeft(find.byType(ValueColumnRow).at(e.key)).dy)
    .toList();

void main() {
  group('lane alignment invariant — all three columns share one geometry', () {
    late List<WaveformLaneData> canvasLanes;

    setUp(() {
      WaveformCanvas.debugOnLanesBuilt = (lanes) => canvasLanes = lanes;
    });
    tearDown(() {
      WaveformCanvas.debugOnLanesBuilt = null;
    });

    testWidgets('every row y-position matches the shared model in all columns', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_threeColumns());
      await tester.pump(); // let the canvas postframe refresh settle

      void assertAligned(LaneGeometry model) {
        // Canvas: lanes are absolute from y=0 (no diff/transaction in fixture),
        // so each lane's y/height equals the model row directly.
        expect(canvasLanes.length, model.rows.length);
        for (var i = 0; i < model.rows.length; i++) {
          expect(
            canvasLanes[i].y,
            model.rows[i].top,
            reason: 'canvas lane $i y',
          );
          expect(
            canvasLanes[i].height,
            model.rows[i].height,
            reason: 'canvas lane $i height',
          );
        }

        // Signal-names list and value column lay rows out sequentially, so
        // compare each row's offset RELATIVE to that column's first row (this
        // cancels each panel's header spacer) against the model.
        final valueTops = _valueColumnRowTops(tester);
        expect(valueTops.length, model.rows.length);
        final valueFirst = valueTops.first;
        final namesFirst = _signalListRowTop(tester, _signalListKeyForRow(0));

        for (var i = 0; i < model.rows.length; i++) {
          final expected = model.rows[i].top; // top - rows[0].top (== 0)
          expect(
            valueTops[i] - valueFirst,
            moreOrLessEquals(expected),
            reason: 'value column row $i',
          );
          final namesTop = _signalListRowTop(tester, _signalListKeyForRow(i));
          expect(
            namesTop - namesFirst,
            moreOrLessEquals(expected),
            reason: 'signal-names row $i',
          );
        }
      }

      // Initial geometry (touch: 'a' & 'tiny' & 'g1' all clamp up to 44).
      assertAligned(
        LaneGeometry(entries: _fixture, metrics: _metrics),
      );

      // ── Resize step: the signal-names column is the sole writer. Simulate
      // its resize handle writing through setLaneHeight (the handle GESTURE
      // itself is covered by signal_list_panel_test). Grow 'b' (top-level
      // index 4) from 60 → 100; the single write must reflow all three
      // columns to stay aligned, live.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ValueColumnPanel)),
      );
      container
          .read(signalGroupsProvider.notifier)
          .setLaneHeight(4, 100, minHeight: 44);
      await tester.pump();

      final resized = [..._fixture];
      resized[4] = resized[4].copyWith(laneHeight: 100);
      assertAligned(LaneGeometry(entries: resized, metrics: _metrics));
    });
  });

  group('lane alignment — locale sweep', () {
    setUp(() {
      WaveformCanvas.debugOnLanesBuilt = (_) {};
    });
    tearDown(() {
      WaveformCanvas.debugOnLanesBuilt = null;
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets(
        'renders all three columns without exception (${locale.languageCode})',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1100, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(_threeColumns(locale: locale));
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
