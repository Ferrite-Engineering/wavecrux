// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/process_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Variable _variable(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'top.$name',
  scopePath: 'top',
);

Widget _wrap(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) {
  final scroll = ScrollController();
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: SignalListPanel(scrollController: scroll)),
    ),
  );
}

/// Returns a container with one signal pre-added and no process filter active.
ProviderContainer _plainContainer(String signalName) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(signalGroupsProvider.notifier).addSignal(_variable(signalName));
  return c;
}

/// Returns a container with one signal and a fake process filter active for it.
ProviderContainer _filteredContainer(String signalName) {
  final signalRef = 'top.$signalName';
  final c = ProviderContainer(
    overrides: [
      processFilterProvider.overrideWith(
        () => _FakeProcessFilterNotifier(signalRef),
      ),
    ],
  );
  addTearDown(c.dispose);
  c.read(signalGroupsProvider.notifier).addSignal(_variable(signalName));
  return c;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SignalListPanel — process filter UI', () {
    // ── locale sweep ──────────────────────────────────────────────────────────

    testWidgets('renders without exception — en', (tester) async {
      final c = _plainContainer('clk');
      await tester.pumpWidget(_wrap(c));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — zh_CN', (tester) async {
      final c = _plainContainer('clk');
      await tester.pumpWidget(_wrap(c, locale: const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — ja', (tester) async {
      final c = _plainContainer('clk');
      await tester.pumpWidget(_wrap(c, locale: const Locale('ja')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — ko', (tester) async {
      final c = _plainContainer('clk');
      await tester.pumpWidget(_wrap(c, locale: const Locale('ko')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ── context menu items ────────────────────────────────────────────────────

    testWidgets('"Set Translate Filter Process" appears in right-click menu', (
      tester,
    ) async {
      final c = _plainContainer('data');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      await tester.tap(find.text('data'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Set Translate Filter Process…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '"Clear Translate Filter Process" absent when no filter active',
      (tester) async {
        final c = _plainContainer('data');
        await tester.pumpWidget(_wrap(c));
        await tester.pump();

        await tester.tap(find.text('data'), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        expect(find.text('Clear Translate Filter Process'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('"Clear Translate Filter Process" appears when filter active', (
      tester,
    ) async {
      final c = _filteredContainer('data');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      await tester.tap(find.text('data'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Clear Translate Filter Process'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ── indicator icon ────────────────────────────────────────────────────────

    testWidgets('terminal icon absent when no process filter active', (
      tester,
    ) async {
      final c = _plainContainer('clk');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      expect(find.byIcon(Icons.terminal), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('terminal icon shown when process filter is active', (
      tester,
    ) async {
      final c = _filteredContainer('clk');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      expect(find.byIcon(Icons.terminal), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('terminal icon tooltip reads "Process filter active"', (
      tester,
    ) async {
      final c = _filteredContainer('clk');
      await tester.pumpWidget(_wrap(c));
      await tester.pump();

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byIcon(Icons.terminal),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Process filter active');
      expect(tester.takeException(), isNull);
    });
  });
}

// ── Fake notifier ─────────────────────────────────────────────────────────────

/// Overrides [ProcessFilterNotifier] to report [activeSignalRef] as having an
/// active process filter, without launching a real process.
class _FakeProcessFilterNotifier extends ProcessFilterNotifier {
  _FakeProcessFilterNotifier(this.activeSignalRef);

  final String activeSignalRef;

  @override
  Map<String, String?> build() => {activeSignalRef: null};

  @override
  Future<String?> setProcessFilter(
    String signalRef,
    String executablePath, [
    List<String> arguments = const [],
  ]) async => null;

  @override
  void removeProcessFilter(String signalRef) {}

  @override
  Future<String?> translateValue(
    String signalRef,
    String rawValue, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async => null;
}
