// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: selection-to-broadcast regression test; it asserts what
// is sent to peers, not any localized text.

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../../helpers/cxp_test_overrides.dart';
import '../../../support/fake_waveform_source.dart';

// The reference fake source keys `top.clk` by the opaque ref `s_clk`.
const _clkRef = 's_clk';

Variable _clk() => const Variable(
  name: 'clk',
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: _clkRef,
  scopePath: 'top',
);

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource> build() => AsyncData(_source);
}

final _refProvider = Provider<Ref>((ref) => ref);

/// Pumps a [SignalListPanel] with the live selection emitter attached, and
/// returns what the emitter sent to its sink.
Future<List<NotifySelection>> _pumpPanel(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  final sent = <NotifySelection>[];
  final emitter = CxpSelectionEmitter(
    ref: container.read(_refProvider),
    sink: (message, {summary}) {
      if (message is NotifySelection) sent.add(message);
    },
  )..start();
  addTearDown(emitter.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SignalListPanel(scrollController: ScrollController()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sent;
}

Future<void> _clickClkRow(WidgetTester tester) async {
  await tester.tap(find.text('clk'));
  // The row also has a double-tap recognizer; wait out its window.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      ...cxpTestOverrides,
      deviceClassProvider.overrideWithValue(DeviceClass.desktop),
      waveformSourceProvider.overrideWith(
        () => _PreloadedSourceNotifier(FakeWaveformSource.reference()),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(signalGroupsProvider.notifier).addSignal(_clk());
  return container;
}

void main() {
  group('signal row click with auto-broadcast', () {
    testWidgets('sends notify_selection for a freshly clicked row', (
      tester,
    ) async {
      final container = _container();
      final sent = await _pumpPanel(tester, container: container);

      await _clickClkRow(tester);

      expect(sent, hasLength(1));
      expect(sent.single.elements.single.path, 'top.clk');
    });

    testWidgets(
      'sends notify_selection when the clicked row is already the root focus '
      '(a cross-probe or earlier tab left the same signalRef selected)',
      (tester) async {
        final container = _container();
        // The root focus already holds this ref: an inbound cross-probe, or a
        // selection in another tab of the same design, wrote it earlier.
        container.read(selectedSignalProvider.notifier).select(_clkRef);
        final sent = await _pumpPanel(tester, container: container);

        await _clickClkRow(tester);

        expect(sent, hasLength(1));
        expect(sent.single.elements.single.path, 'top.clk');
      },
    );

    testWidgets('clicking the same row again sends again', (tester) async {
      final container = _container();
      final sent = await _pumpPanel(tester, container: container);

      await _clickClkRow(tester);
      await _clickClkRow(tester);

      expect(sent, hasLength(2));
    });
  });
}
