// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_timeline_overlay.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

class _PreloadedLog extends CocotbLog {
  _PreloadedLog(this._initial);
  final CocotbLogFile? _initial;
  @override
  CocotbLogFile? build() => _initial;
}

class _FixedMapper extends TimeMapperNotifier {
  _FixedMapper(this._mapper);
  final TimeMapper _mapper;
  @override
  TimeMapper build() => _mapper;
}

CocotbLogFile _file(List<CocotbLogEntry> entries) => CocotbLogFile(
  filePath: '/tmp/run.log',
  entries: List.unmodifiable(entries),
  testNames: const [],
  severityCounts: const {},
  testResults: const {},
);

CocotbLogEntry _e(
  int line,
  int? ticks, [
  CocotbLogSeverity sev = CocotbLogSeverity.info,
]) => CocotbLogEntry(
  severity: sev,
  loggerName: 'cocotb.test',
  message: 'm$line',
  lineNumber: line,
  simTimeTicks: ticks,
);

Widget _wrap({
  CocotbLogFile? file,
  TimeMapper? mapper,
  (int, int) range = (0, 1000),
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      cocotbLogProvider.overrideWith(() => _PreloadedLog(file)),
      if (mapper != null)
        timeMapperProvider.overrideWith(() => _FixedMapper(mapper)),
      visibleTimeRangeProvider.overrideWith((ref) => range),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: SizedBox(
          width: 400,
          child: CocotbTimelineOverlay(),
        ),
      ),
    ),
  );
}

void main() {
  group('CocotbTimelineOverlay', () {
    testWidgets('locale sweep with loaded log', (tester) async {
      const locales = ['en', 'zh_CN', 'ja', 'ko'];
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 400,
        ticksPerPixel: 2.5,
        panOffsetTicks: 0,
      );
      final file = _file([_e(1, 100), _e(2, 500)]);
      for (final tag in locales) {
        final parts = tag.split('_');
        final locale = parts.length == 2
            ? Locale(parts[0], parts[1])
            : Locale(parts[0]);
        await tester.pumpWidget(
          _wrap(file: file, mapper: mapper, locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'locale $tag');
      }
    });

    testWidgets('renders zero-size box when no log loaded', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      // The overlay collapses to SizedBox.shrink(), so its rendered height
      // is 0 px — the strip's documented height is only used when a log
      // is loaded.
      final size = tester.getSize(find.byType(CocotbTimelineOverlay));
      expect(size.height, 0);
    });

    testWidgets('renders RepaintBoundary when log loaded', (tester) async {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 400,
        ticksPerPixel: 2.5,
        panOffsetTicks: 0,
      );
      await tester.pumpWidget(
        _wrap(file: _file([_e(1, 100), _e(2, 500)]), mapper: mapper),
      );
      await tester.pumpAndSettle();
      // The overlay wraps its painter in a RepaintBoundary when active.
      expect(
        find.descendant(
          of: find.byType(CocotbTimelineOverlay),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
    });

    testWidgets('overlay has the documented height', (tester) async {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 400,
        ticksPerPixel: 2.5,
        panOffsetTicks: 0,
      );
      await tester.pumpWidget(
        _wrap(file: _file([_e(1, 100)]), mapper: mapper),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(CocotbTimelineOverlay));
      expect(size.height, cocotbTimelineOverlayHeight);
    });
  });
}
