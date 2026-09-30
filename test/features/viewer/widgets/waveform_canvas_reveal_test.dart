// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure scroll/behavior regression test (cross-probe
// auto-reveal). Renders no user-facing localized text — the L10N delegates are
// only present so WaveformCanvas can build; there is nothing CJK-dependent to
// sweep.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// P1.2: an inbound cross-probe (programmatic) selection auto-reveals the
// selected signal — scrolling its lane into view and expanding its group if
// collapsed. Reveal is driven by `revealSignalRequestProvider`, which the CXP
// inbound handler sets. These tests drive that provider directly.

class _MockSource extends Mock implements WaveformDataSource {}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

const _signalCount = 40;

/// Builds `_signalCount` variables `top.sig0..sigN` under one root scope.
List<Variable> _variables() => [
  for (var i = 0; i < _signalCount; i++)
    Variable(
      name: 'sig$i',
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: 'sig$i',
      scopePath: 'top',
      bitWidth: 1,
    ),
];

class _ManySignalGroupsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [
      for (var i = 0; i < _signalCount; i++)
        SignalEntry.signal(signalRef: 'sig$i', displayName: 'sig$i'),
    ],
  );
}

/// One collapsed group holding the last signal, preceded by tall filler so the
/// collapsed group starts below the fold.
class _CollapsedGroupNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [
      for (var i = 0; i < _signalCount; i++)
        SignalEntry.signal(signalRef: 'sig$i', displayName: 'sig$i'),
      SignalEntry.group(
        groupName: 'grp',
        collapsed: true,
        children: [
          SignalEntry.signal(signalRef: 'hidden', displayName: 'hidden'),
        ],
      ),
    ],
  );
}

_MockSource _buildSource({List<Variable>? extra}) {
  final source = _MockSource();
  when(() => source.startTime).thenReturn(0);
  when(() => source.endTime).thenReturn(1000);
  when(() => source.timescale).thenReturn(null);
  when(() => source.rootScopes).thenReturn([
    Scope(
      name: 'top',
      type: ScopeType.module,
      path: 'top',
      variables: [...?extra, ..._variables()],
    ),
  ]);
  when(() => source.isSignalLoaded(any())).thenReturn(true);
  when(() => source.loadSignal(any())).thenAnswer((_) async {});
  when(() => source.unloadSignal(any())).thenAnswer((_) async {});
  when(() => source.changesInRange(any(), any(), any())).thenReturn([]);
  when(() => source.valueAt(any(), any())).thenReturn(null);
  return source;
}

Future<ProviderContainer> _pumpCanvas(
  WidgetTester tester, {
  required _MockSource source,
  required SignalGroupsNotifier Function() groups,
  required ScrollController scroll,
  List<Override> extraOverrides = const [],
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        waveformSourceProvider.overrideWith(
          () => _LoadedSourceNotifier(source),
        ),
        signalGroupsProvider.overrideWith(groups),
        ...extraOverrides,
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return Scaffold(
              body: SizedBox(
                width: 800,
                height: 300,
                child: WaveformCanvas(externalScrollController: scroll),
              ),
            );
          },
        ),
      ),
    ),
  );
  // Flush the mount post-frame callbacks + initial data refresh.
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('WaveformCanvas cross-probe auto-reveal', () {
    testWidgets('reveal request scrolls a below-the-fold signal into view', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final source = _buildSource();

      final container = await _pumpCanvas(
        tester,
        source: source,
        groups: _ManySignalGroupsNotifier.new,
        scroll: scroll,
      );

      expect(scroll.offset, 0, reason: 'starts at the top');

      // Simulate the inbound cross-probe: request the last signal's lane.
      container
          .read(revealSignalRequestProvider.notifier)
          .request('top.sig${_signalCount - 1}');
      await tester.pumpAndSettle();

      expect(
        scroll.offset,
        greaterThan(0),
        reason: 'the viewport should scroll down to reveal the last signal',
      );
    });

    testWidgets('reveal expands a collapsed group holding the signal', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final source = _buildSource(
        extra: [
          const Variable(
            name: 'hidden',
            varType: VarType.wire,
            direction: VarDirection.unknown,
            signalRef: 'hidden',
            scopePath: 'top',
            bitWidth: 1,
          ),
        ],
      );

      final container = await _pumpCanvas(
        tester,
        source: source,
        groups: _CollapsedGroupNotifier.new,
        scroll: scroll,
      );

      // The group starts collapsed.
      final before = container.read(signalGroupsProvider).entries;
      expect(before.last.collapsed, isTrue);

      container
          .read(revealSignalRequestProvider.notifier)
          .request('top.hidden');
      await tester.pumpAndSettle();

      final after = container.read(signalGroupsProvider).entries;
      expect(
        after.last.collapsed,
        isFalse,
        reason: 'revealing a signal in a collapsed group must expand it',
      );
    });

    testWidgets(
      'a reveal already pending when the canvas mounts still scrolls '
      '(fresh-open / reverse cross-probe recovery)',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final source = _buildSource();

        // The reveal is written BEFORE the canvas mounts — the reverse cross-
        // probe case where a just-opened tab's provider already holds the
        // request. The `ref.listen` never sees a transition here, so only the
        // build-time one-shot read can recover it.
        await _pumpCanvas(
          tester,
          source: source,
          groups: _ManySignalGroupsNotifier.new,
          scroll: scroll,
          extraOverrides: [
            revealSignalRequestProvider.overrideWithValue(
              const RevealSignalRequest(
                fullPath: 'top.sig39',
                token: 1,
              ),
            ),
          ],
        );

        expect(
          scroll.offset,
          greaterThan(0),
          reason:
              'a reveal present at mount must still scroll the last signal '
              'into view',
        );
      },
    );

    testWidgets('tapping the waveform (wave) area does not change selection', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final source = _buildSource();

      final container = await _pumpCanvas(
        tester,
        source: source,
        groups: _ManySignalGroupsNotifier.new,
        scroll: scroll,
      );

      expect(container.read(selectedVariablesProvider), isEmpty);

      // A tap in the wave/trace area is a cursor gesture, never a selection —
      // selection is originated from the name column, not by hijacking the
      // canvas's measurement gestures.
      await tester.tapAt(tester.getCenter(find.byType(WaveformCanvas)));
      await tester.pumpAndSettle();

      expect(container.read(selectedVariablesProvider), isEmpty);
    });

    testWidgets('a signal already in view is not scrolled', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final source = _buildSource();

      final container = await _pumpCanvas(
        tester,
        source: source,
        groups: _ManySignalGroupsNotifier.new,
        scroll: scroll,
      );

      container.read(revealSignalRequestProvider.notifier).request('top.sig0');
      await tester.pumpAndSettle();

      expect(
        scroll.offset,
        0,
        reason: 'the first signal is already visible — do not disturb scroll',
      );
    });
  });
}
