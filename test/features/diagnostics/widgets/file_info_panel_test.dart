// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/diagnostics/widgets/file_info_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

FileStats _stats({
  String filePath = '/tmp/trace.vcd',
  int fileSizeBytes = 1024 * 1024,
  String formatName = 'VCD',
  double parseTimeMs = 120.5,
  int totalSignals = 10,
  int scalarCount = 7,
  int vectorCount = 2,
  int realCount = 1,
  int inputCount = 3,
  int outputCount = 4,
  int inoutCount = 1,
  int unknownDirectionCount = 2,
  int totalTransitions = 5000,
  int hierarchyDepth = 3,
  int scopeCount = 8,
  int startTime = 0,
  int endTime = 10000,
  String? timescaleDisplay = '1ns',
  String? simulationDate,
  String? simulatorVersion,
  WaveformFormat? originalFormat,
  DateTime? convertedAt,
}) => FileStats(
  filePath: filePath,
  fileSizeBytes: fileSizeBytes,
  formatName: formatName,
  parseTimeMs: parseTimeMs,
  totalSignals: totalSignals,
  scalarCount: scalarCount,
  vectorCount: vectorCount,
  realCount: realCount,
  inputCount: inputCount,
  outputCount: outputCount,
  inoutCount: inoutCount,
  unknownDirectionCount: unknownDirectionCount,
  totalTransitions: totalTransitions,
  hierarchyDepth: hierarchyDepth,
  scopeCount: scopeCount,
  startTime: startTime,
  endTime: endTime,
  timescaleDisplay: timescaleDisplay,
  simulationDate: simulationDate,
  simulatorVersion: simulatorVersion,
  originalFormat: originalFormat,
  convertedAt: convertedAt,
);

Widget _wrap(
  Widget child, {
  FileStats? stats,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      fileStatsProvider.overrideWithValue(stats),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      // The panel is designed to be hosted inside a scrollable container
      // (Tab Diagnostics drawer); wrap with SingleChildScrollView so the
      // standalone test surface can render the panel's full intrinsic
      // height without RenderFlex overflow.
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FileInfoPanel — locale sweep', () {
    for (final locale in [
      const Locale('en'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('renders in ${locale.toLanguageTag()} without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const FileInfoPanel(), stats: _stats(), locale: locale),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FileInfoPanel — no file loaded', () {
    testWidgets('shows placeholder when stats is null', (tester) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel()));
      await tester.pump();
      // Matches diagnosticsDiagNoWaveform l10n key
      expect(find.text('No waveform loaded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not show section headers when stats is null', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel()));
      await tester.pump();
      expect(find.text('File'), findsNothing);
      expect(find.text('Parse'), findsNothing);
    });
  });

  group('FileInfoPanel — sections present when loaded', () {
    testWidgets('shows File section header', (tester) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel(), stats: _stats()));
      await tester.pump();
      expect(find.text('File'), findsOneWidget);
    });

    testWidgets('shows Parse section header', (tester) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel(), stats: _stats()));
      await tester.pump();
      expect(find.text('Parse'), findsOneWidget);
    });

    testWidgets('shows Signals by Type section header', (tester) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel(), stats: _stats()));
      await tester.pump();
      expect(find.text('Signals by Type'), findsOneWidget);
    });

    testWidgets('shows Signals by Direction section header', (tester) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel(), stats: _stats()));
      await tester.pump();
      expect(find.text('Signals by Direction'), findsOneWidget);
    });

    testWidgets('shows Hierarchy section header', (tester) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel(), stats: _stats()));
      await tester.pump();
      expect(find.text('Hierarchy'), findsOneWidget);
    });

    testWidgets('shows Time section header', (tester) async {
      await tester.pumpWidget(_wrap(const FileInfoPanel(), stats: _stats()));
      await tester.pump();
      expect(find.text('Time'), findsOneWidget);
    });
  });

  group('FileInfoPanel — metric values', () {
    testWidgets('displays format name', (tester) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(formatName: 'FST')),
      );
      await tester.pump();
      expect(find.text('FST'), findsOneWidget);
    });

    testWidgets('displays parse time in ms', (tester) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(parseTimeMs: 250)),
      );
      await tester.pump();
      expect(find.text('250.0 ms'), findsOneWidget);
    });

    testWidgets('displays parse time in seconds when >= 1000ms', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(parseTimeMs: 2500)),
      );
      await tester.pump();
      expect(find.text('2.50 s'), findsOneWidget);
    });

    testWidgets('displays total signals count', (tester) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(totalSignals: 1234)),
      );
      await tester.pump();
      expect(find.text('1,234'), findsWidgets);
    });

    testWidgets('shows N/A for transitions when totalTransitions is 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(totalTransitions: 0)),
      );
      await tester.pump();
      expect(find.text('N/A'), findsWidgets);
    });

    testWidgets('shows transition count when non-zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(totalTransitions: 50000),
        ),
      );
      await tester.pump();
      expect(find.text('50,000'), findsOneWidget);
    });

    testWidgets('displays hierarchy depth', (tester) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(hierarchyDepth: 5)),
      );
      await tester.pump();
      expect(find.text('5'), findsWidgets);
    });

    testWidgets('displays timescale when present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(timescaleDisplay: '10ns'),
        ),
      );
      await tester.pump();
      expect(find.text('10ns'), findsOneWidget);
    });

    testWidgets('shows N/A for timescale when null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(timescaleDisplay: null),
        ),
      );
      await tester.pump();
      expect(find.text('N/A'), findsWidgets);
    });
  });

  group('FileInfoPanel — metadata section', () {
    testWidgets('metadata section hidden when date and version are null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats()),
      );
      await tester.pump();
      expect(find.text('Metadata'), findsNothing);
    });

    testWidgets('metadata section shown when date is present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(simulationDate: '2026-01-01'),
        ),
      );
      await tester.pump();
      expect(find.text('Metadata'), findsOneWidget);
      expect(find.text('2026-01-01'), findsOneWidget);
    });

    testWidgets('metadata section shown when version is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(simulatorVersion: 'Icarus 12'),
        ),
      );
      await tester.pump();
      expect(find.text('Metadata'), findsOneWidget);
      expect(find.text('Icarus 12'), findsOneWidget);
    });

    testWidgets('shows both date and version when both present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(
            simulationDate: '2026-04-23',
            simulatorVersion: 'Verilator 5.0',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2026-04-23'), findsOneWidget);
      expect(find.text('Verilator 5.0'), findsOneWidget);
    });
  });

  group('FileInfoPanel — file size formatting', () {
    testWidgets('shows N/A when fileSizeBytes is 0', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(fileSizeBytes: 0),
        ),
      );
      await tester.pump();
      expect(find.text('N/A'), findsWidgets);
    });

    testWidgets('formats bytes < 1KB as B', (tester) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(fileSizeBytes: 512)),
      );
      await tester.pump();
      expect(find.text('512 B'), findsOneWidget);
    });

    testWidgets('formats bytes >= 1KB as KB', (tester) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(fileSizeBytes: 2048)),
      );
      await tester.pump();
      expect(find.text('2.0 KB'), findsOneWidget);
    });

    testWidgets('formats bytes >= 1MB as MB', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(fileSizeBytes: 5 * 1024 * 1024),
        ),
      );
      await tester.pump();
      expect(find.text('5.0 MB'), findsOneWidget);
    });
  });

  // ── Issue 23 — File Path truncated-text reveal ─────────────────────────────
  // Per ARCHITECTURE.md §3.1.8.14 the truncated File Path row must have a
  // hover-tooltip reveal AND a context-menu reveal that doubles as a copy
  // action. The fix wraps the value text in a manual-trigger Tooltip and
  // attaches a `PlatformContextMenu` whose first item is the
  // non-interactive monospace full path; a "Copy File Path" item writes the
  // path to the clipboard.
  group('FileInfoPanel — File Path truncation reveal (Issue 23)', () {
    const longPath =
        '/home/rtl/projects/soc/verification/fixtures/protocol/spi/generated/spi_basic.vcd';

    testWidgets('wraps the value in a manual-trigger Tooltip', (tester) async {
      await tester.pumpWidget(
        _wrap(const FileInfoPanel(), stats: _stats(filePath: longPath)),
      );
      await tester.pump();
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text(longPath),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, equals(longPath));
      expect(tooltip.triggerMode, equals(TooltipTriggerMode.manual));
    });

    testWidgets(
      'right-click opens a context menu with the full path header and Copy File Path action that writes to clipboard',
      (tester) async {
        // Capture clipboard writes via the system-channel mock so we can
        // assert "Copy File Path" actually writes the full absolute path.
        String? clipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboardText = (call.arguments as Map)['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(
          _wrap(const FileInfoPanel(), stats: _stats(filePath: longPath)),
        );
        await tester.pump();

        // The value text lives inside a `PlatformContextMenu`. Right-clicking
        // (secondary-button down) is the desktop entry; on touch the same menu
        // surfaces via long-press. Drive the secondary tap-down here so we
        // exercise the desktop code path the user reported missing. Match
        // [test/shared/widgets/platform_context_menu_test.dart] which uses
        // `startGesture` to simulate the mouse-secondary-button press.
        final valueText = find.text(longPath);
        final gesture = await tester.startGesture(
          tester.getCenter(valueText),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        // Two occurrences of the full path are now in the tree: the original
        // truncated row value (ellipsised at the row width) AND the
        // monospace header inside the popup menu. Asserting `findsNWidgets(2)`
        // is the cleanest "the menu opened and the header is there" check.
        expect(find.text(longPath), findsNWidgets(2));
        // The Copy File Path action label is the popup-specific surface.
        expect(find.text('Copy File Path'), findsOneWidget);

        // Click "Copy File Path" → clipboard receives the full path.
        await tester.tap(find.text('Copy File Path'));
        await tester.pumpAndSettle();
        expect(clipboardText, equals(longPath));
        // Snackbar confirmation surfaces.
        expect(find.text('Copied path to clipboard'), findsOneWidget);
      },
    );
  });

  // ── Original Format row ───────────────────────────────────────────────────
  // Renders only when the active source came from the lxt2fst convert-on-open
  // path. Absent for native FST/VCD/GHW opens; included with the conversion
  // date when both origin format and convertedAt are known; falls back to
  // the no-date variant when convertedAt is null (cache-hit reopens).
  group('FileInfoPanel — Original Format row', () {
    testWidgets('hidden for native FST opens', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(formatName: 'FST'),
        ),
      );
      await tester.pump();
      expect(find.text('Original Format'), findsNothing);
    });

    testWidgets('shown for LXT2 opens with conversion date', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(
            formatName: 'FST',
            originalFormat: WaveformFormat.lxt2,
            convertedAt: DateTime(2026, 5, 28),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Original Format'), findsOneWidget);
      expect(
        find.text('LXT2 (converted to FST on 2026-05-28)'),
        findsOneWidget,
      );
    });

    testWidgets('shown for LXT opens with conversion date', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(
            formatName: 'FST',
            originalFormat: WaveformFormat.lxt,
            convertedAt: DateTime(2026, 1, 2),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('LXT (converted to FST on 2026-01-02)'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to no-date variant when convertedAt is null '
        '(cache-hit reopen)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FileInfoPanel(),
          stats: _stats(
            formatName: 'FST',
            originalFormat: WaveformFormat.lxt2,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Original Format'), findsOneWidget);
      expect(find.text('LXT2 (converted to FST)'), findsOneWidget);
    });
  });
}
