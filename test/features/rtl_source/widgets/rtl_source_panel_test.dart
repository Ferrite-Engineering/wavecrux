// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/rtl_source/widgets/rtl_source_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/rtl_source/rtl_source_loader.dart';

// ── Fake notifier ────────────────────────────────────────────────────────────

class _FakeNotifier extends RtlSourceNotifier {
  _FakeNotifier(this._initial);
  final RtlSourceState _initial;

  @override
  RtlSourceState build() => _initial;

  @override
  Future<void> loadStemsFile(String path) async {}

  @override
  Future<bool> showSignal({
    required String signalRef,
    required String signalPath,
  }) async => true;

  @override
  Future<bool> showByName(String name) async => true;

  @override
  void clearStems() {
    state = const RtlSourceState();
  }

  @override
  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _stems = StemsFile(
  entries: [
    StemsEntry(
      path: 'top.cpu',
      sourceFile: '/src/cpu.v',
      lineNumber: 1,
      kind: StemsEntryKind.scope,
    ),
    StemsEntry(
      path: 'top.cpu.clk',
      sourceFile: '/src/cpu.v',
      lineNumber: 5,
      kind: StemsEntryKind.variable,
    ),
  ],
);

const _verilogSource = RtlSourceFile(
  path: '/src/cpu.v',
  lines: [
    'module cpu (',
    '  input  wire clk,',
    '  input  wire rst,',
    '  output reg  [7:0] data',
    ');',
    '  // posedge clock body',
    "  always @(posedge clk) data <= 8'h00;",
    'endmodule',
  ],
);

Widget _wrap(
  RtlSourceState state, {
  Locale locale = const Locale('en'),
  VoidCallback? onLoadStems,
  VoidCallback? onClose,
  double width = 400,
  EditorHostKind hostKind = EditorHostKind.none,
}) {
  final container = ProviderContainer(
    overrides: [
      rtlSourceProvider.overrideWith(() => _FakeNotifier(state)),
    ],
  );
  container.read(editorHostKindProvider.notifier).set(hostKind);
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 600,
          child: RtlSourcePanel(
            onLoadStems: onLoadStems,
            onClose: onClose,
          ),
        ),
      ),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // Locale sweep — empty state.
  group('RtlSourcePanel — locale sweep (empty)', () {
    for (final pair in const [
      ('en', null),
      ('zh', 'CN'),
      ('ja', null),
      ('ko', null),
    ]) {
      testWidgets('renders without exception in ${pair.$1}', (tester) async {
        await tester.pumpWidget(
          _wrap(
            const RtlSourceState(),
            locale: Locale(pair.$1, pair.$2),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Narrow-pane regression: the panel docks in the right pane, which can be as
  // narrow as the IdeLayout rightMinSize (150 dp). The header must not overflow
  // (it previously did by ~185 dp because the title + labelled load button were
  // a fixed-width Row). Exercised with both action buttons present and across
  // the locale sweep so CJK label widths are covered too.
  group('RtlSourcePanel — narrow right pane (no overflow)', () {
    for (final pair in const [
      ('en', null),
      ('zh', 'CN'),
      ('ja', null),
      ('ko', null),
    ]) {
      testWidgets('header fits at 150 dp in ${pair.$1}', (tester) async {
        await tester.pumpWidget(
          _wrap(
            const RtlSourceState(),
            locale: Locale(pair.$1, pair.$2),
            width: 150,
            onLoadStems: () {},
            onClose: () {},
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Locale sweep — ready with selected source.
  group('RtlSourcePanel — locale sweep (ready)', () {
    for (final pair in const [
      ('en', null),
      ('zh', 'CN'),
      ('ja', null),
      ('ko', null),
    ]) {
      testWidgets('renders source view without exception in ${pair.$1}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const RtlSourceState(
              status: RtlStemsStatus.ready,
              stems: _stems,
              currentSourceFile: _verilogSource,
              currentLine: 5,
              currentSignalPath: 'top.cpu.clk',
            ),
            locale: Locale(pair.$1, pair.$2),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Empty state when no stems loaded.
  testWidgets('shows "no stems loaded" message when status is idle', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const RtlSourceState()));
    await tester.pumpAndSettle();
    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.textContaining('No stems file loaded'), findsOneWidget);
    expect(find.text(l10n.rtlSourcePanelTitle), findsOneWidget);
  });

  // Empty state when stems loaded but no signal selected.
  testWidgets(
    'shows "select a signal" hint when stems loaded but no selection',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RtlSourceState(status: RtlStemsStatus.ready, stems: _stems),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Select a signal'), findsOneWidget);
    },
  );

  // Loading spinner.
  testWidgets('shows progress indicator while loading', (tester) async {
    await tester.pumpWidget(
      _wrap(const RtlSourceState(status: RtlStemsStatus.loading)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // Error display in body.
  testWidgets('displays error text in empty state when error is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RtlSourceState(error: 'cannot read'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('cannot read'), findsOneWidget);
  });

  // Source view shows file path and line number label.
  testWidgets('shows source file path and line number when source loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RtlSourceState(
          status: RtlStemsStatus.ready,
          stems: _stems,
          currentSourceFile: _verilogSource,
          currentLine: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('/src/cpu.v'), findsOneWidget);
    expect(find.textContaining('5'), findsWidgets);
  });

  // Stem count in header.
  testWidgets('shows stems-loaded count in header when ready', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RtlSourceState(status: RtlStemsStatus.ready, stems: _stems),
      ),
    );
    await tester.pumpAndSettle();
    // 2 entries in fixture → "2 mappings"
    expect(find.textContaining('2'), findsWidgets);
  });

  // Load button callback.
  testWidgets('Load Stems File button invokes onLoadStems callback', (
    tester,
  ) async {
    var loadCount = 0;
    await tester.pumpWidget(
      _wrap(const RtlSourceState(), onLoadStems: () => loadCount++),
    );
    await tester.pumpAndSettle();
    final l10n = await L10N.delegate.load(const Locale('en'));
    final btn = find.text(l10n.rtlSourceLoadStemsButton);
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    expect(loadCount, 1);
  });

  // Close button callback.
  testWidgets('close button invokes onClose callback', (tester) async {
    var closeCount = 0;
    await tester.pumpWidget(
      _wrap(const RtlSourceState(), onClose: () => closeCount++),
    );
    await tester.pumpAndSettle();
    final close = find.byIcon(Icons.close);
    expect(close, findsOneWidget);
    await tester.tap(close);
    expect(closeCount, 1);
  });

  // Header title is always present.
  testWidgets('header title is always rendered', (tester) async {
    await tester.pumpWidget(_wrap(const RtlSourceState()));
    await tester.pumpAndSettle();
    expect(find.text('RTL Source'), findsOneWidget);
  });

  // Click hint visible in source view.
  testWidgets('source view shows the click hint', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RtlSourceState(
          status: RtlStemsStatus.ready,
          stems: _stems,
          currentSourceFile: _verilogSource,
          currentLine: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Click an identifier'), findsOneWidget);
  });

  // Editor host — RTL source annotation. The panel keeps its
  // header and its place in the layout; only the body becomes the
  // explanation. Present and explained, never omitted.
  group('RtlSourcePanel — editor host boundary', () {
    testWidgets('under a VSCode host the body states the boundary', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RtlSourceState(
            stems: _stems,
            currentSourceFile: _verilogSource,
          ),
          hostKind: EditorHostKind.vscode,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editorHostBoundaryTitle')), findsOneWidget);
      expect(
        find.textContaining('RTL source is annotated in your editor'),
        findsOneWidget,
      );
      // What, why, and what to do — the fsdbWebUnsupportedMessage shape.
      expect(find.textContaining('stems file names'), findsOneWidget);
      // The "what to do" is no longer "go and get the desktop app": the
      // extension annotates the real editor instead, so the
      // boundary has to point at the command rather than out of the product.
      expect(
        find.textContaining('Toggle RTL Value Annotation'),
        findsOneWidget,
      );
      // …and the source view it replaces is genuinely gone.
      expect(find.textContaining('Click an identifier'), findsNothing);
    });

    testWidgets('the header survives — the panel is present, not omitted', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RtlSourceState(),
          hostKind: EditorHostKind.vscode,
          onClose: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('RTL Source'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('the stems-load action is withheld under an editor host', (
      tester,
    ) async {
      // A stems file names HDL paths the webview cannot read; a picker that
      // can only end in an empty source view is a worse answer than the
      // sentence.
      await tester.pumpWidget(
        _wrap(
          const RtlSourceState(),
          hostKind: EditorHostKind.vscode,
          onLoadStems: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.folder_open), findsNothing);
    });

    testWidgets('nothing changes off an editor host', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RtlSourceState(),
          onLoadStems: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editorHostBoundaryTitle')), findsNothing);
      expect(find.byIcon(Icons.folder_open), findsWidgets);
    });

    testWidgets('the boundary survives the narrow right pane', (tester) async {
      // The right pane's floor is 150 dp; a split VSCode editor is wider but
      // the same wrap-not-overflow rule has to hold at both.
      for (final width in const <double>[150, 400, 500]) {
        await tester.pumpWidget(
          _wrap(
            const RtlSourceState(),
            hostKind: EditorHostKind.vscode,
            width: width,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'RTL boundary overflowed at ${width}dp',
        );
      }
    });
  });
}
