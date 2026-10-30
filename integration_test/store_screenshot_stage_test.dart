// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/store_screenshot_stage_test.dart
//
// Stages the states the App Store and Play Store screenshots show, and holds
// each one on screen long enough for an external capture. The capture itself
// is `xcrun simctl io <udid> screenshot` (or `adb exec-out screencap`), driven
// by `tool/store_screenshots.sh`, which watches this test's output for
// `STORE_SHOT <name> READY` lines. Native capture gives the exact pixel size
// the stores require, with the status bar, which an in-test
// `RepaintBoundary.toImage` cannot.
//
// Run, from wavecrux/:
//   flutter test integration_test/store_screenshot_stage_test.dart -d <udid> \
//     > /tmp/store-stage.log 2>&1 &
//   tool/store_screenshots.sh /tmp/store-stage.log <udid> <outdir>
//
// The states are the bundled sample ("Open Sample Waveform", the five-decoder
// fixture) rather than a host fixture, so the run needs nothing from the
// host filesystem and shows exactly what a first launch shows. Decoders are
// bound and added through the same services the picker dialog uses, because
// at phone width the toolbar's decoder button sits past the right edge.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/decoder_auto_bind_service.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import 'helpers/app_driver.dart';

/// How long each staged state stays on screen for the external capture.
const _hold = Duration(seconds: 14);

Future<void> _show(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  // ignore: avoid_print — the capture script keys on this line.
  print('STORE_SHOT $name READY');
  final end = DateTime.now().add(_hold);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Adds the built-in decoder [id] with the bindings auto-bind would propose,
/// the same call the config dialog makes when it opens.
void _addDecoder(ProviderContainer tab, String id) {
  final definition = DecoderRegistry.instance.getDefinition(id)!;
  final result = const DecoderAutoBindService().computeBindings(
    definition: definition,
    availableSignals: tab.read(signalVariablesByPathProvider),
    currentParameters: const {},
  );
  final bindings = <String, String>{
    for (final e in result.candidates.entries)
      if (e.value.signalRef != null) e.key: e.value.signalRef!,
  };
  tab
      .read(activeDecodersProvider.notifier)
      .addDecoder(id, DecoderConfig(signalBindings: bindings));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets('stage the store screenshots', (tester) async {
    await clearPersistedWorkspace();
    await seedFirstLaunchAnswers();
    await bootstrap();
    await tester.pump();

    // The empty canvas offers the bundled sample; that is the first thing a
    // new install can do, so it is also what the screenshots show.
    final sample = find.text('Open Sample Waveform');
    await pumpUntil(
      tester,
      () => sample.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    await tester.tap(sample);
    await tester.pump();
    await pumpUntilWaveformReady(tester, timeout: const Duration(seconds: 60));
    await tester.pumpAndSettle();

    final root = rootContainer(tester);
    final deviceClass = root.read(deviceClassProvider);
    final phone =
        deviceClass == DeviceClass.phone ||
        deviceClass == DeviceClass.phoneLandscape;

    final tab = activeTabContainer(tester);
    final source = tab.read(waveformSourceProvider).value!;
    final all = source.findVariables(const SignalFilter());
    List<Variable> under(String scope) =>
        all.where((v) => v.fullPath.startsWith('$scope.')).toList();

    // A phone shows about a dozen lanes; a tablet has room for the AXI bus.
    final chosen = <Variable>[
      ...under('spi_tb'),
      ...under('i2c_tb'),
      ...under('uart_tb'),
      if (!phone) ...under('axi4lite_tb'),
    ];
    tab.read(signalGroupsProvider.notifier).addSignals(chosen);
    await tester.pumpAndSettle();

    for (final id in ['spi', 'i2c', 'uart', if (!phone) 'axi4_lite']) {
      _addDecoder(tab, id);
    }
    await tab.read(activeDecodersProvider.notifier).decodeAll();
    await tester.pump();
    await pumpUntil(tester, () {
      final decoders = tab.read(activeDecodersProvider);
      return decoders.isNotEmpty &&
          decoders.every((d) => d.transactions.isNotEmpty);
    }, timeout: const Duration(seconds: 60));
    await tester.pumpAndSettle();

    // The sample spans 54 µs; the first few microseconds hold a transaction
    // on every bus, and at that scale the decoded labels are readable.
    tab.read(timeMapperProvider.notifier).zoomToRange(0, phone ? 6000 : 12000);
    await _show(tester, '01-waveform');

    if (phone) {
      // The signal tree is a drawer at phone width.
      final scaffold = find.byWidgetPredicate(
        (w) => w is Scaffold && w.drawer != null,
      );
      tester.state<ScaffoldState>(scaffold.first).openDrawer();
      await _show(tester, '02-signal-tree');
      tester.state<ScaffoldState>(scaffold.first).closeDrawer();
      await tester.pumpAndSettle();
    }

    paneContainer(
          tester,
        )
        .read(panelLayoutProvider.notifier)
        .setTransactionViewVisible(visible: true);
    await _show(tester, phone ? '03-transactions' : '02-transactions');

    if (!phone) {
      paneContainer(tester)
          .read(panelLayoutProvider.notifier)
          .setTransactionViewVisible(visible: false);
      await tester.pumpAndSettle();
      // The decoder picker: the breadth of the built-in decoders in one view.
      await tester.tap(find.byIcon(Icons.developer_board).first);
      await _show(tester, '03-decoders');
    }

    // ignore: avoid_print — the capture script keys on this line.
    print('STORE_SHOT DONE READY');
  });
}
