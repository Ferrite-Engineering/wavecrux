// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/session/session_service.dart';

/// Backward-read: a `.wavecrux` document written BEFORE the
/// decoders seam landed has no `decoders` key. The loader must
/// (1) NOT throw, (2) populate `SessionState.decoders` as an empty list,
/// (3) keep the document byte-stable on a no-op resave (no
/// `"decoders"` key sneaks in when none was there to begin with).

const _service = SessionService();

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_dec_bwd_');
  final path = '${dir.path}/legacy.wavecrux';
  try {
    return await fn(path);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

void main() {
  group('SessionService — pre-decoder-seam backward read', () {
    test('a session without a decoders key loads as decoders == []', () async {
      // Hand-crafted v1-shape document (no version field, no decoders
      // key) — minimal but valid.
      final legacy = <String, Object?>{
        'sourceFilePath': '/sim/legacy.vcd',
        'signals': <Map<String, Object?>>[],
        'cursor': <String, Object?>{'primary': null, 'secondary': null},
        'markers': <String, Object?>{},
        'view': <String, Object?>{
          'ticksPerPixel': 1.0,
          'panOffsetTicks': 0.0,
          'scrollOffset': 0.0,
        },
        'panels': <String, Object?>{
          'signalTree': true,
          'valueColumn': true,
          'transactionView': false,
          'stageView': false,
          'statisticsStrip': false,
        },
        'translateFilters': <String, Object?>{},
        'stage': <String, Object?>{'panels': <Map<String, Object?>>[]},
        'activeTheme': 'wavecrux-dark',
      };

      await _withTempFile((path) async {
        await File(path).writeAsString(
          const JsonEncoder.withIndent('  ').convert(legacy),
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.decoders, isEmpty);
      });
    });

    test('a session with decoders == null in JSON loads as []', () async {
      // Defensive: a document where the field is present but null
      // must not crash the loader (could happen if a user edited the
      // sidecar by hand or a future bug emits the field unconditionally).
      final withNull = <String, Object?>{
        'sourceFilePath': '/sim/legacy.vcd',
        'signals': <Map<String, Object?>>[],
        'cursor': <String, Object?>{'primary': null, 'secondary': null},
        'markers': <String, Object?>{},
        'view': <String, Object?>{
          'ticksPerPixel': 1.0,
          'panOffsetTicks': 0.0,
          'scrollOffset': 0.0,
        },
        'panels': <String, Object?>{
          'signalTree': true,
          'valueColumn': true,
          'transactionView': false,
          'stageView': false,
          'statisticsStrip': false,
        },
        'translateFilters': <String, Object?>{},
        'stage': <String, Object?>{'panels': <Map<String, Object?>>[]},
        'activeTheme': 'wavecrux-dark',
        'decoders': null,
      };

      await _withTempFile((path) async {
        await File(path).writeAsString(
          const JsonEncoder.withIndent('  ').convert(withNull),
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.decoders, isEmpty);
      });
    });

    test('a session with malformed entries in decoders array silently '
        'drops them rather than failing the whole load', () async {
      final malformed = <String, Object?>{
        'sourceFilePath': '/sim/dump.vcd',
        'signals': <Map<String, Object?>>[],
        'cursor': <String, Object?>{'primary': null, 'secondary': null},
        'markers': <String, Object?>{},
        'view': <String, Object?>{
          'ticksPerPixel': 1.0,
          'panOffsetTicks': 0.0,
          'scrollOffset': 0.0,
        },
        'panels': <String, Object?>{
          'signalTree': true,
          'valueColumn': true,
          'transactionView': false,
          'stageView': false,
          'statisticsStrip': false,
        },
        'translateFilters': <String, Object?>{},
        'stage': <String, Object?>{'panels': <Map<String, Object?>>[]},
        'activeTheme': 'wavecrux-dark',
        'decoders': <Object?>[
          'this is not a map',
          42,
          null,
          <String, Object?>{
            'decoderId': 'spi',
            'instanceNumber': 1,
            'config': <String, Object?>{
              'bindings': <String, Object?>{'sclk': 'top.spi.sclk'},
            },
          },
        ],
      };

      await _withTempFile((path) async {
        await File(path).writeAsString(
          const JsonEncoder.withIndent('  ').convert(malformed),
        );
        final loaded = await _service.loadSession(path);
        // Only the well-formed entry survives.
        expect(loaded.decoders, hasLength(1));
        expect(loaded.decoders.first.decoderId, 'spi');
      });
    });
  });
}
