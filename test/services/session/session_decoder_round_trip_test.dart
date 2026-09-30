// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/services/session/session_service.dart';

/// `SessionState.decoders` round-trips through
/// `SessionService.saveSession` / `loadSession`. Companion tests cover
/// the backward-read (no decoders key) case in
/// `session_decoder_backward_read_test.dart` and the unknown-id restore
/// in `session_decoder_unknown_id_test.dart`.

const _service = SessionService();

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_dec_');
  final path = '${dir.path}/session.wavecrux';
  try {
    return await fn(path);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

void main() {
  group('SessionService — decoder round-trip', () {
    test('two persisted decoders survive a save → load cycle', () async {
      const original = SessionState(
        sourceFilePath: '/sim/dump.vcd',
        decoders: [
          PersistedDecoder(
            decoderId: 'spi',
            instanceNumber: 1,
            config: DecoderConfig(
              signalBindings: {
                'sclk': 'top.spi.sclk',
                'mosi': 'top.spi.mosi',
                'miso': 'top.spi.miso',
                'cs': 'top.spi.cs',
              },
              parameters: {'cpol': false, 'cpha': false},
            ),
          ),
          PersistedDecoder(
            decoderId: 'i2c',
            instanceNumber: 2,
            config: DecoderConfig(
              signalBindings: {
                'scl': 'top.i2c.scl',
                'sda': 'top.i2c.sda',
              },
            ),
          ),
        ],
      );

      await _withTempFile((path) async {
        await _service.saveSession(original, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.decoders, hasLength(2));
        expect(loaded.decoders[0], equals(original.decoders[0]));
        expect(loaded.decoders[1], equals(original.decoders[1]));
        // Full SessionState equality (decoders + every other field) holds.
        expect(loaded, equals(original));

        // Save again from the loaded state — the decoders block must be
        // byte-stable through a second roundtrip.
        await _withTempFile((path2) async {
          await _service.saveSession(loaded, path2);
          final firstJson =
              jsonDecode(await File(path).readAsString())
                  as Map<String, Object?>;
          final secondJson =
              jsonDecode(await File(path2).readAsString())
                  as Map<String, Object?>;
          expect(secondJson['decoders'], firstJson['decoders']);
        });
      });
    });

    test('decoders block preserves order across the round-trip', () async {
      // Ordering is the order the transaction-table tabs render — a
      // post-restore reorder would silently rearrange the user's panel.
      const original = SessionState(
        decoders: [
          PersistedDecoder(
            decoderId: 'uart',
            instanceNumber: 1,
            config: DecoderConfig(signalBindings: {'tx': 'top.uart.tx'}),
          ),
          PersistedDecoder(
            decoderId: 'spi',
            instanceNumber: 3,
            config: DecoderConfig(signalBindings: {'sclk': 'top.spi.sclk'}),
          ),
          PersistedDecoder(
            decoderId: 'uart',
            instanceNumber: 2,
            config: DecoderConfig(signalBindings: {'rx': 'top.uart.rx'}),
          ),
        ],
      );

      await _withTempFile((path) async {
        await _service.saveSession(original, path);
        final loaded = await _service.loadSession(path);
        expect(
          loaded.decoders.map((d) => '${d.decoderId}#${d.instanceNumber}'),
          ['uart#1', 'spi#3', 'uart#2'],
        );
      });
    });

    test(
      'two AHB-Lite instances round-trip distinct mixed-type per-instance '
      'configuration (int / enum-string / bool params stay independent)',
      () async {
        // Verification §5.8 "Per-instance configuration round-trip through
        // session save/load" — the existing SPI/I2C cases above only exercise
        // boolean parameters. AHB-Lite carries the full type spread:
        // `addr_width`/`wait_state_threshold` (integer), `data_width`
        // (enumeration persisted as a String), and `check_alignment`
        // (boolean). Two instances with deliberately different values prove
        // (a) integers survive JSON without an int→double coercion, (b)
        // enum-as-String params round-trip, and (c) the two instances stay
        // independent rather than collapsing onto a shared config.
        const original = SessionState(
          sourceFilePath: '/sim/soc.fst',
          decoders: [
            PersistedDecoder(
              decoderId: 'ahb_lite',
              instanceNumber: 1,
              config: DecoderConfig(
                signalBindings: {
                  'hclk': 'top.cpu.hclk',
                  'haddr': 'top.cpu.haddr',
                  'htrans': 'top.cpu.htrans',
                },
                parameters: {
                  'addr_width': 32,
                  'data_width': '64',
                  'check_alignment': false,
                  'wait_state_threshold': 2,
                },
              ),
            ),
            PersistedDecoder(
              decoderId: 'ahb_lite',
              instanceNumber: 2,
              config: DecoderConfig(
                signalBindings: {
                  'hclk': 'top.dma.hclk',
                  'haddr': 'top.dma.haddr',
                  'htrans': 'top.dma.htrans',
                },
                parameters: {
                  'addr_width': 16,
                  'data_width': '32',
                  'check_alignment': true,
                  'wait_state_threshold': 512,
                },
              ),
            ),
          ],
        );

        await _withTempFile((path) async {
          await _service.saveSession(original, path);
          final loaded = await _service.loadSession(path);

          expect(loaded, equals(original));
          expect(loaded.decoders, hasLength(2));

          final first = loaded.decoders[0].config.parameters;
          final second = loaded.decoders[1].config.parameters;

          // Integers must come back as `int`, not `double` — a JSON coercion
          // here would break the decoder's `wait_state_threshold` comparison.
          expect(first['addr_width'], isA<int>());
          expect(first['addr_width'], 32);
          expect(first['wait_state_threshold'], isA<int>());
          expect(first['wait_state_threshold'], 2);
          expect(first['data_width'], '64');
          expect(first['check_alignment'], isFalse);

          // The second instance keeps its own distinct values.
          expect(second['addr_width'], 16);
          expect(second['wait_state_threshold'], 512);
          expect(second['data_width'], '32');
          expect(second['check_alignment'], isTrue);
        });
      },
    );

    test('empty decoders list does NOT emit a decoders key on disk', () async {
      // Keeps pre-decoder session files byte-stable across the schema bump.
      await _withTempFile((path) async {
        await _service.saveSession(const SessionState(), path);
        final json =
            jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
        expect(json.containsKey('decoders'), isFalse);
      });
    });
  });
}
