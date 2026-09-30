// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/session/session_service.dart';

/// Open-core `extensions` map round-trip + forward-compat
/// schema-version policy. These tests cover the SessionService side of
/// the codec seam only (no provider registration, no Ref). The codec
/// runtime is exercised in `session_extensions_codec_test.dart`.

const _service = SessionService();

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_ext_');
  final path = '${dir.path}/session.wavecrux';
  try {
    return await fn(path);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

Map<String, Object?> _decode(String json) =>
    jsonDecode(json) as Map<String, Object?>;

void main() {
  group('SessionService — extensions preserve-unknown round-trip', () {
    test('unknown namespace survives load + save with no codec registered '
        '(byte-identical modulo whitespace)', () async {
      // Hand-crafted v3 document carrying a namespace the current build
      // has no codec for. The seam must hand it back unchanged on save.
      final original = <String, Object?>{
        'version': 3,
        'sourceFilePath': '/sim/dump.vcd',
        'signals': <Map<String, Object?>>[],
        'cursor': <String, Object?>{'primary': 1000, 'secondary': null},
        'markers': <String, Object?>{},
        'view': <String, Object?>{
          'ticksPerPixel': 1.5,
          'panOffsetTicks': 0.0,
          'scrollOffset': 0.0,
        },
        'panels': <String, Object?>{
          'signalTree': true,
          'valueColumn': true,
          'transactionView': false,
          'stageView': false,
          'statisticsStrip': false,
          'cocotbLogPanel': false,
          'rtlSource': false,
        },
        'translateFilters': <String, Object?>{},
        'stage': <String, Object?>{
          'panels': <Map<String, Object?>>[],
        },
        'activeTheme': 'wavecrux-dark',
        'extensions': <String, Object?>{
          'pro.unknown': <String, Object?>{
            'logPath': '/abs/run.log',
            'filters': <String>['rule_a', 'rule_b'],
            'cursor': 42,
          },
          'future.feature': <String, Object?>{'flag': true},
        },
      };

      await _withTempFile((path) async {
        await File(path).writeAsString(
          const JsonEncoder.withIndent('  ').convert(original),
        );

        final loaded = await _service.loadSession(path);
        expect(
          loaded.extensions.keys.toSet(),
          {'pro.unknown', 'future.feature'},
          reason:
              'every namespace must survive a load on a build with no '
              'codec registered for it',
        );

        // Save through the round-trip and compare the decoded JSON to
        // the original. Byte-equality of the encoded string is not the
        // contract — key ordering inside each map is JSON-undefined —
        // but the decoded structures must match field-for-field,
        // including the unknown namespaces.
        const outPath = 'out.wavecrux';
        await _withTempFile((tempOut) async {
          await _service.saveSession(loaded, tempOut);
          final reEncoded = await File(tempOut).readAsString();
          final reDecoded = _decode(reEncoded);

          // Re-stamped at this build's version by design — the seam carries
          // payloads forward, it does not preserve the source's version.
          expect(reDecoded['version'], SessionService.currentSchemaVersion);
          expect(reDecoded['extensions'], original['extensions']);
          expect(
            reDecoded['sourceFilePath'],
            original['sourceFilePath'],
          );
          // Each top-level field must match the source after a clean
          // round-trip. The `extensions` map is the focus, but a
          // regression in any other field would tell us the seam
          // change accidentally broke unrelated state. `version` is
          // deliberately absent — it is re-stamped, and asserted above.
          for (final key in const [
            'sourceFilePath',
            'cursor',
            'markers',
            'view',
            'panels',
            'translateFilters',
            'stage',
            'activeTheme',
            'extensions',
          ]) {
            expect(
              reDecoded[key],
              original[key],
              reason: 'top-level field "$key" diverged after round-trip',
            );
          }
        });
        // outPath is only used inside the inner _withTempFile closure.
        expect(outPath, 'out.wavecrux');
      });
    });

    test(
      'v1 document (no extensions field) loads as an empty extensions map',
      () async {
        // Pre-extensions documents have no `version` / `extensions` keys.
        // _fromJson must treat missing as empty and the post-load state's
        // extensions must round-trip back to no `extensions` key on save.
        final v1 = <String, Object?>{
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
            const JsonEncoder.withIndent('  ').convert(v1),
          );

          final loaded = await _service.loadSession(path);
          expect(loaded.extensions, isEmpty);

          await _withTempFile((outPath) async {
            await _service.saveSession(loaded, outPath);
            final decoded = _decode(await File(outPath).readAsString());
            expect(
              decoded.containsKey('extensions'),
              isFalse,
              reason:
                  'empty extensions must NOT emit a key — keeps existing '
                  'sessions byte-stable across the v1→v2 bump',
            );
          });
        });
      },
    );
  });

  group('SessionService — schema-version forward-compat policy', () {
    test(
      'newer schema version (v99) reads silently and preserves extensions',
      () async {
        // The seam's documented policy is "lenient read" — a hypothetical
        // future v99 carrying a `pro.future` payload must still round-trip
        // that payload through the extensions map on this build.
        final v99 = <String, Object?>{
          'version': 99,
          'sourceFilePath': '/sim/future.vcd',
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
          'extensions': <String, Object?>{
            'pro.future': <String, Object?>{'whoami': 'tomorrow'},
          },
        };

        await _withTempFile((path) async {
          await File(path).writeAsString(
            const JsonEncoder.withIndent('  ').convert(v99),
          );

          // No throw: lenient read.
          final loaded = await _service.loadSession(path);
          final futureExtensions = v99['extensions']! as Map<String, Object?>;
          expect(
            loaded.extensions['pro.future'],
            futureExtensions['pro.future'],
          );

          // Save: the document is re-stamped at _kCurrentVersion (the seam
          // does not pretend to be a future build) but the extensions map
          // rides through verbatim.
          await _withTempFile((outPath) async {
            await _service.saveSession(loaded, outPath);
            final decoded = _decode(await File(outPath).readAsString());
            expect(decoded['version'], SessionService.currentSchemaVersion);
            expect(
              decoded['extensions'],
              v99['extensions'],
              reason:
                  'the preserve-unknown invariant is the whole point of '
                  'the lenient-read policy',
            );
          });
        });
      },
    );
  });
}
