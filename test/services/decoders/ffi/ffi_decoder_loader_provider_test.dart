// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader_provider.dart';

void main() {
  setUp(resetStartupScanCacheForTesting);

  group('scanPluginsOnStartup', () {
    test('returns empty when pluginSafetyAcknowledged is false', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      TestWidgetsFlutterBinding.ensureInitialized();

      final infos = await scanPluginsOnStartup();

      expect(infos, isEmpty);
    });

    test(
      'returns empty when settings load fails (no platform channel)',
      () async {
        // With no SharedPreferences mock and no widgets binding, the
        // WaveCruxSettingsService load() call should fail and bootstrap should
        // fall back to "no plugins this run" without throwing.
        final infos = await scanPluginsOnStartup();
        expect(infos, isEmpty);
      },
    );
  });

  group('DecoderRegistry.unregister', () {
    test('removes a registered decoder and returns true', () {
      final registry = DecoderRegistry.forTesting();
      const def = DecoderDefinition(
        id: 'transient',
        displayName: 'Transient',
        description: 'fixture',
        requiredSignals: <SignalBinding>[],
        category: DecoderCategory.userPlugin,
      );
      registry.register(def, _StubDecoder.factory);
      expect(registry.isRegistered('transient'), isTrue);

      final removed = registry.unregister('transient');

      expect(removed, isTrue);
      expect(registry.isRegistered('transient'), isFalse);
      expect(registry.getFactory('transient'), isNull);
    });

    test('returns false when no registration exists for the id', () {
      final registry = DecoderRegistry.forTesting();
      expect(registry.unregister('never_registered'), isFalse);
    });
  });
}

class _StubDecoder implements ProtocolDecoder {
  const _StubDecoder();
  static ProtocolDecoder factory(DecoderConfig _) => const _StubDecoder();
  @override
  DecoderDefinition get definition => const DecoderDefinition(
    id: 'transient',
    displayName: 'Transient',
    description: 'fixture',
    requiredSignals: <SignalBinding>[],
    category: DecoderCategory.userPlugin,
  );
  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => const <DecodedTransaction>[];
}
