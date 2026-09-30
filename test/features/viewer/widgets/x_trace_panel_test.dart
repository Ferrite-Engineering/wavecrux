// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/widgets/x_trace_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/signal_query/x_trace_service.dart';

// ── fake notifier ─────────────────────────────────────────────────────────────

class _FakeXTraceNotifier extends XTraceNotifier {
  _FakeXTraceNotifier(this._initial);
  final XTraceState _initial;

  @override
  XTraceState build() => _initial;

  @override
  Future<void> traceX(String signalRef, int time) async {}

  @override
  void clearTrace() {
    state = const XTraceState();
  }

  @override
  void jumpToNode(XCausalNode node) {}
}

// ── helpers ───────────────────────────────────────────────────────────────────

const _root = XCausalNode(
  signalPath: 'top.status',
  signalRef: 'ref_status',
  xStartTime: 400,
  previousValue: '0',
);

const _child = XCausalNode(
  signalPath: 'top.data',
  signalRef: 'ref_data',
  xStartTime: 350,
  previousValue: '1',
);

Widget _wrap(XTraceState state, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: [
        xTraceProvider.overrideWith(() => _FakeXTraceNotifier(state)),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: XTracePanel()),
      ),
    );

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── locale sweep ─────────────────────────────────────────────────────────────

  group('XTracePanel — locale sweep', () {
    testWidgets('renders without exception — en', (tester) async {
      await tester.pumpWidget(_wrap(const XTraceState()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — zh_CN', (tester) async {
      await tester.pumpWidget(
        _wrap(const XTraceState(), locale: const Locale('zh', 'CN')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — ja', (tester) async {
      await tester.pumpWidget(
        _wrap(const XTraceState(), locale: const Locale('ja')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without exception — ko', (tester) async {
      await tester.pumpWidget(
        _wrap(const XTraceState(), locale: const Locale('ko')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ── empty / error state ───────────────────────────────────────────────────────

  group('XTracePanel — empty state', () {
    testWidgets('shows empty prompt when no trace active', (tester) async {
      await tester.pumpWidget(_wrap(const XTraceState()));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Right-click a signal with value 'x' at cursor to trace its X origin.",
        ),
        findsOneWidget,
      );
      expect(find.text('X-Trace'), findsNothing);
    });

    testWidgets('shows error text when trace inactive with error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const XTraceState(error: 'Signal is not X.')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Signal is not X.'), findsOneWidget);
    });
  });

  // ── active trace ──────────────────────────────────────────────────────────────

  group('XTracePanel — active trace', () {
    testWidgets('shows panel header and root signal path', (tester) async {
      await tester.pumpWidget(_wrap(const XTraceState(rootNode: _root)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('X-Trace'), findsOneWidget);
      expect(find.text('top.status'), findsOneWidget);
    });

    testWidgets('shows previous value label for root node', (tester) async {
      await tester.pumpWidget(_wrap(const XTraceState(rootNode: _root)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Was: 0'), findsOneWidget);
    });

    testWidgets('no previous value label when previousValue is null', (
      tester,
    ) async {
      const nodeNoPrev = XCausalNode(
        signalPath: 'top.sig',
        signalRef: 'ref_sig',
        xStartTime: 100,
      );
      await tester.pumpWidget(_wrap(const XTraceState(rootNode: nodeNoPrev)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.textContaining('Was:'), findsNothing);
    });

    testWidgets('shows sibling header and child path when children present', (
      tester,
    ) async {
      const rootWithChild = XCausalNode(
        signalPath: 'top.status',
        signalRef: 'ref_status',
        xStartTime: 400,
        children: [_child],
      );
      await tester.pumpWidget(
        _wrap(const XTraceState(rootNode: rootWithChild)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('CO-TEMPORAL X IN SCOPE'), findsOneWidget);
      expect(find.text('top.data'), findsOneWidget);
    });

    testWidgets('no sibling section when root has no children', (tester) async {
      await tester.pumpWidget(_wrap(const XTraceState(rootNode: _root)));
      await tester.pumpAndSettle();

      expect(find.text('CO-TEMPORAL X IN SCOPE'), findsNothing);
    });
  });

  // ── overflow / constrained height ────────────────────────────────────────────

  group('XTracePanel — overflow prevention', () {
    // Wraps the panel in a tight height container that is smaller than the
    // natural height of header + root tile + section label to confirm the
    // Expanded(ListView) layout prevents a RenderFlex overflow.
    Widget wrapConstrained(XTraceState state, double height) => ProviderScope(
      overrides: [
        xTraceProvider.overrideWith(() => _FakeXTraceNotifier(state)),
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(height: height, child: const XTracePanel()),
        ),
      ),
    );

    testWidgets('no overflow at 105 px with root + previous value + children', (
      tester,
    ) async {
      const rootWithAll = XCausalNode(
        signalPath: 'top.status',
        signalRef: 'ref_status',
        xStartTime: 400,
        previousValue: '0',
        children: [_child],
      );
      await tester.pumpWidget(
        wrapConstrained(const XTraceState(rootNode: rootWithAll), 105),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 80 px minimum panel height (root only)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapConstrained(const XTraceState(rootNode: _root), 80),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 80 px with root + children', (tester) async {
      const rootWithChild = XCausalNode(
        signalPath: 'top.status',
        signalRef: 'ref_status',
        xStartTime: 400,
        children: [_child],
      );
      await tester.pumpWidget(
        wrapConstrained(const XTraceState(rootNode: rootWithChild), 80),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ── interactions ──────────────────────────────────────────────────────────────

  group('XTracePanel — interactions', () {
    testWidgets('clear button resets to empty state', (tester) async {
      await tester.pumpWidget(_wrap(const XTraceState(rootNode: _root)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('X-Trace'), findsNothing);
      expect(find.textContaining('Right-click'), findsOneWidget);
    });

    testWidgets('tapping root node tile does not throw', (tester) async {
      await tester.pumpWidget(_wrap(const XTraceState(rootNode: _root)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('top.status'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping child tile does not throw', (tester) async {
      const rootWithChild = XCausalNode(
        signalPath: 'top.status',
        signalRef: 'ref_status',
        xStartTime: 400,
        children: [_child],
      );
      await tester.pumpWidget(
        _wrap(const XTraceState(rootNode: rootWithChild)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('top.data'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
