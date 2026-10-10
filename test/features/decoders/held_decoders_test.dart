// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Session decoders this build cannot load are held for the next save
// (session_decoder_unknown_id_test.dart) and shown in the signal list as
// "not available in this build" with their id. The collaboration follower
// neither shows nor saves them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_list_entry.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';

import '../../helpers/product_telemetry_config.dart';

class _NoSource extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncData(null);
}

const _proDecoder = PersistedDecoder(
  decoderId: 'pro.usb',
  instanceNumber: 2,
  config: DecoderConfig(
    signalBindings: {'dp': 'top.usb.dp', 'dm': 'top.usb.dm'},
    parameters: {'speed': 'full'},
  ),
);

const _known = PersistedDecoder(
  decoderId: 'spi',
  instanceNumber: 1,
  config: DecoderConfig(signalBindings: {'sclk': 'top.spi.sclk'}),
);

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      waveformSourceProvider.overrideWith(_NoSource.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The decoder band follows the signal rows, so the list needs one signal.
void _addSignal(ProviderContainer container) => container
    .read(signalGroupsProvider.notifier)
    .addSignal(
      const Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.unknown,
        signalRef: 'ref_clk',
        scopePath: 'top',
      ),
    );

Widget _panel(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: SignalListPanel(scrollController: ScrollController())),
  ),
);

void main() {
  setUp(() {
    DecoderRegistry.instance
      ..clear()
      ..register(SpiDecoder.decoderDefinition, SpiDecoder.new);
  });
  tearDown(DecoderRegistry.instance.clear);

  group('heldDecodersProvider', () {
    test('publishes what a session restore holds', () {
      final container = _container();
      container.read(activeDecodersProvider.notifier).restoreDecoders(const [
        _known,
        _proDecoder,
      ]);

      expect(container.read(heldDecodersProvider), [_proDecoder]);
    });

    test('is empty for the collaboration follower', () {
      final container = _container();
      final notifier = container.read(activeDecodersProvider.notifier);
      final outcome = notifier.applyCompositionRecipe(
        const [_proDecoder],
        SignalIdentityResolver(pathToRef: const {}, refToPath: const {}),
      );

      expect(outcome.missingDecoderIds, ['pro.usb']);
      expect(container.read(heldDecodersProvider), isEmpty);
      expect(notifier.snapshot(), isEmpty);
    });

    test('follows clearAll even when no decoder is active', () {
      final container = _container();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [_proDecoder]);
      expect(container.read(heldDecodersProvider), hasLength(1));

      notifier.clearAll();
      expect(container.read(heldDecodersProvider), isEmpty);
    });

    test('removeHeldDecoder drops it from the list and the next save', () {
      final container = _container();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [_known, _proDecoder])
        ..removeHeldDecoder(0);

      expect(container.read(heldDecodersProvider), isEmpty);
      expect(notifier.snapshot().map((p) => p.decoderId), ['spi']);
    });
  });

  group('signal list', () {
    testWidgets('shows a held decoder as not available in this build', (
      tester,
    ) async {
      final container = _container();
      container.read(activeDecodersProvider.notifier).restoreDecoders(const [
        _known,
        _proDecoder,
      ]);

      _addSignal(container);
      await tester.pumpWidget(_panel(container));
      await tester.pump();

      expect(find.byType(DecoderListEntry), findsOneWidget);
      expect(find.byType(HeldDecoderListEntry), findsOneWidget);
      final l10n = L10N.of(tester.element(find.byType(SignalListPanel)));
      expect(
        find.textContaining('pro.usb #2', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          l10n.decoderNotAvailableInBuild,
          findRichText: true,
        ),
        findsOneWidget,
      );
      // Shown, and still saved verbatim.
      expect(
        container.read(activeDecodersProvider.notifier).snapshot().last,
        _proDecoder,
      );
    });

    testWidgets('the collaboration follower shows no held row', (
      tester,
    ) async {
      final container = _container();
      container.read(activeDecodersProvider.notifier).applyCompositionRecipe(
        const [_proDecoder],
        SignalIdentityResolver(pathToRef: const {}, refToPath: const {}),
      );

      _addSignal(container);
      await tester.pumpWidget(_panel(container));
      await tester.pump();

      expect(find.byType(HeldDecoderListEntry), findsNothing);
    });
  });
}
