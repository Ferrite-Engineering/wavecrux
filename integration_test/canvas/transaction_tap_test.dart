// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('tap transaction block places cursor at transaction startTime', (
    tester,
  ) async {
    await loadFixtureVcd(tester, 'protocol/spi/generated/spi_basic.vcd');
    await activateDecoder(tester, 'SPI');

    // The canvas key is present once transaction lanes are rendered.
    final canvasFinder = find.byKey(WaveformCanvas.waveformCanvasKey);
    expect(canvasFinder, findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(canvasFinder),
    );

    final timeMapper = container.read(timeMapperProvider);

    // First SPI transaction: startTime=10, endTime=180.
    // Tap at the horizontal midpoint (tick 95) of the tx block.
    // _onTap overrides the cursor to tx.startTime (10) when a tx lane is hit.
    // Transaction lane height = 28 dp; no user signals → tx lane at y=0,
    // center y = 14.
    final canvasTopLeft = tester.getTopLeft(canvasFinder);
    final tapX = canvasTopLeft.dx + timeMapper.timeToPixel(95);
    final tapY = canvasTopLeft.dy + 14.0;

    await tester.tapAt(Offset(tapX, tapY));
    await tester.pumpAndSettle();

    final cursor = container.read(cursorStateProvider).primaryCursorTime;
    expect(cursor, isNotNull);
    expect(cursor, closeTo(10, 1));
  });
}
