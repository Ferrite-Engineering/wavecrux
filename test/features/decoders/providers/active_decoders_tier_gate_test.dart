// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A session restore brings back every decoder the build has registered, and
// the Pro overlay registers its decoders at every tier: the picker is the only
// door that asks. So the decoder run itself asks the tier, and these tests
// restore a session naming a Pro decoder the way a file saved during the beta
// would name one.

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

import '../../../helpers/fake_waveform_data_source.dart';

const _proDefinition = DecoderDefinition(
  id: 'pro_stub',
  displayName: 'Pro Stub',
  description: 'A decoder sold at Pro',
  requiredSignals: [SignalBinding(name: 'sig', description: 'test signal')],
  requiredTier: LicenseTier.pro,
);

const _openDefinition = DecoderDefinition(
  id: 'open_stub',
  displayName: 'Open Stub',
  description: 'A decoder every tier has',
  requiredSignals: [SignalBinding(name: 'sig', description: 'test signal')],
);

const _stackedDefinition = DecoderDefinition(
  id: 'pro_stacked',
  displayName: 'Pro Stacked',
  description: 'A Pro decoder that stacks on an open-core one',
  requiredSignals: [],
  requiredTier: LicenseTier.pro,
  parentDecoderId: 'open_stub',
);

const _enterpriseDefinition = DecoderDefinition(
  id: 'ent_stub',
  displayName: 'Ent Stub',
  description: 'A decoder sold at Enterprise',
  requiredSignals: [SignalBinding(name: 'sig', description: 'test signal')],
  requiredTier: LicenseTier.enterprise,
);

const _session = SessionState(
  decoders: [
    PersistedDecoder(
      decoderId: 'pro_stub',
      instanceNumber: 1,
      config: DecoderConfig(signalBindings: {'sig': 'top.sig'}),
    ),
    PersistedDecoder(
      decoderId: 'open_stub',
      instanceNumber: 1,
      config: DecoderConfig(signalBindings: {'sig': 'top.sig'}),
    ),
  ],
);

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);

  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// A `licenseTierProvider` source a test can change after the container is
/// built, the way a stored licence resolves after startup.
final _tier = NotifierProvider<_TierNotifier, LicenseTier>(_TierNotifier.new);

class _TierNotifier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get tier => state;
  set tier(LicenseTier value) => state = value;
}

ProviderContainer _container({
  required bool beta,
  LicenseTier? tier,
}) {
  final source = FakeWaveformDataSource(
    signals: {
      'top.sig': const [SignalChange(time: 0, value: '0')],
    },
  );
  final c = ProviderContainer(
    overrides: <Override>[
      waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
      betaPeriodProvider.overrideWithValue(beta),
      if (tier != null)
        licenseTierProvider.overrideWithValue(tier)
      else
        licenseTierProvider.overrideWith((ref) => ref.watch(_tier)),
    ],
  )..listen(activeDecodersProvider, (_, _) {});
  addTearDown(c.dispose);
  return c;
}

Future<void> _restore(ProviderContainer c) =>
    c.read(sessionProvider.notifier).restoreFromState(_session);

List<DecodedTransaction> _transactions(ProviderContainer c, String id) => c
    .read(activeDecodersProvider)
    .singleWhere((d) => d.decoderId == id)
    .transactions;

void main() {
  setUp(() {
    DecoderRegistry.instance
      ..clear()
      ..register(_proDefinition, (_) => const _StubDecoder('Pro TX'))
      ..register(_openDefinition, (_) => const _StubDecoder('Open TX'))
      ..register(_stackedDefinition, (_) => const _StackedStub())
      ..register(_enterpriseDefinition, (_) => const _StubDecoder('Ent TX'));
  });
  tearDown(DecoderRegistry.instance.clear);

  group('Restored Pro decoder — tier gate', () {
    test('Open Core during the beta: the Pro decoder runs', () async {
      final c = _container(beta: true, tier: LicenseTier.openCore);
      await _restore(c);
      expect(_transactions(c, 'pro_stub'), hasLength(1));
    });

    test(
      'Open Core after the beta: the Pro decoder is withheld, not dropped',
      () async {
        final c = _container(beta: false, tier: LicenseTier.openCore);
        await _restore(c);

        expect(_transactions(c, 'pro_stub'), isEmpty);
        // The open-core decoder beside it is untouched.
        expect(_transactions(c, 'open_stub'), hasLength(1));
        // Still in the session model, so the next save writes it back and an
        // upgrade brings it back.
        final saved = c.read(sessionProvider.notifier).snapshot().decoders;
        expect(saved.map((d) => d.decoderId), ['pro_stub', 'open_stub']);
      },
    );

    for (final tier in const [
      LicenseTier.edu,
      LicenseTier.pro,
      LicenseTier.enterprise,
    ]) {
      test('${tier.name} after the beta: the Pro decoder runs', () async {
        final c = _container(beta: false, tier: tier);
        await _restore(c);
        expect(_transactions(c, 'pro_stub'), hasLength(1));
      });
    }

    test(
      'an Enterprise decoder is withheld at Pro and runs at Enterprise',
      () async {
        const session = SessionState(
          decoders: [
            PersistedDecoder(
              decoderId: 'ent_stub',
              instanceNumber: 1,
              config: DecoderConfig(signalBindings: {'sig': 'top.sig'}),
            ),
          ],
        );
        final pro = _container(beta: false, tier: LicenseTier.pro);
        await pro.read(sessionProvider.notifier).restoreFromState(session);
        expect(_transactions(pro, 'ent_stub'), isEmpty);

        final enterprise = _container(
          beta: false,
          tier: LicenseTier.enterprise,
        );
        await enterprise
            .read(sessionProvider.notifier)
            .restoreFromState(session);
        expect(_transactions(enterprise, 'ent_stub'), hasLength(1));
      },
    );

    test('a stacked Pro decoder is withheld in the second pass too', () async {
      const session = SessionState(
        decoders: [
          PersistedDecoder(
            decoderId: 'open_stub',
            instanceNumber: 1,
            config: DecoderConfig(signalBindings: {'sig': 'top.sig'}),
          ),
          PersistedDecoder(
            decoderId: 'pro_stacked',
            instanceNumber: 1,
            config: DecoderConfig(signalBindings: {}),
          ),
        ],
      );
      final openCore = _container(beta: false, tier: LicenseTier.openCore);
      await openCore.read(sessionProvider.notifier).restoreFromState(session);
      expect(_transactions(openCore, 'open_stub'), hasLength(1));
      expect(_transactions(openCore, 'pro_stacked'), isEmpty);

      final pro = _container(beta: false, tier: LicenseTier.pro);
      await pro.read(sessionProvider.notifier).restoreFromState(session);
      expect(_transactions(pro, 'pro_stacked'), hasLength(1));
    });

    test('a licence change mid-session follows, both ways', () async {
      final c = _container(beta: false);
      await _restore(c);
      expect(_transactions(c, 'pro_stub'), isEmpty);

      c.read(_tier.notifier).tier = LicenseTier.pro;
      await pumpEventQueue();
      expect(_transactions(c, 'pro_stub'), hasLength(1));

      c.read(_tier.notifier).tier = LicenseTier.openCore;
      await pumpEventQueue();
      expect(_transactions(c, 'pro_stub'), isEmpty);
      expect(_transactions(c, 'open_stub'), hasLength(1));
    });
  });
}

class _StubDecoder implements ProtocolDecoder {
  const _StubDecoder(this._label);

  final String _label;

  @override
  DecoderDefinition get definition => _proDefinition;

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => [DecodedTransaction(startTime: 0, endTime: 100, label: _label)];
}

/// Stacks on `open_stub` and relabels each parent transaction.
class _StackedStub implements StackedDecoder {
  const _StackedStub();

  @override
  DecoderDefinition get definition => _stackedDefinition;

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => const [];

  @override
  List<DecodedTransaction> decodeStacked(
    List<DecodedTransaction> parentTransactions,
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => [
    for (final t in parentTransactions)
      DecodedTransaction(
        startTime: t.startTime,
        endTime: t.endTime,
        label: 'Stacked ${t.label}',
      ),
  ];
}
