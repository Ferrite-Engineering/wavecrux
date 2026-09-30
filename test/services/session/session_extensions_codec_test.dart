// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/services/session/session_extension_codec.dart';
import 'package:wavecrux/services/session/session_service.dart';

/// Exercise the [SessionExtensions.capture] /
/// [SessionExtensions.restore] runtime against a [ProviderContainer]
/// with a single registered codec. The SessionService side of the seam
/// is covered by `session_extensions_round_trip_test.dart`.

const _service = SessionService();

/// Minimal int-bag notifier — Riverpod 3 dropped `StateProvider`, so the
/// codec target is a tiny `Notifier<int>` subclass exposing an `update`
/// method.
class _IntBag extends Notifier<int> {
  @override
  int build() => 0;

  // A method (not a setter) keeps the call-site explicit at use — the
  // codec restore path reads naturally as `notifier.update(7)`.
  // ignore: use_setters_to_change_properties
  void update(int value) => state = value;
}

/// Target that the codec writes during restore.
final _restoredValueProvider = NotifierProvider<_IntBag, int>(_IntBag.new);

/// Source the codec reads during capture.
final _liveValueProvider = NotifierProvider<_IntBag, int>(_IntBag.new);

/// Surfaces the container's own [Ref] to test bodies — the codec helpers
/// only call `ref.read`, so exposing a provider that returns its own ref
/// is enough.
final _refProvider = Provider<Ref>((ref) => ref);

final _echoCodec = SessionExtensionCodec(
  capture: (ref) => <String, Object?>{'n': ref.read(_liveValueProvider)},
  restore: (ref, payload) {
    if (payload is! Map) return;
    final n = payload['n'];
    if (n is int) {
      ref.read(_restoredValueProvider.notifier).update(n);
    }
  },
);

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_codec_');
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
  group('SessionExtensions — codec round-trip via ProviderContainer', () {
    test(
      'captures from live provider, persists, restores to target provider',
      () async {
        // SAVE leg: container with the `test.echo` codec registered and the
        // live-value provider primed to 7.
        final saveContainer = ProviderContainer(
          overrides: [
            extraSessionPayloadCodecsProvider.overrideWithValue(
              <String, SessionExtensionCodec>{'test.echo': _echoCodec},
            ),
          ],
        );
        addTearDown(saveContainer.dispose);
        saveContainer.read(_liveValueProvider.notifier).update(7);

        // Snapshot: codec contributes {n: 7} under "test.echo". Empty base
        // map mimics a tab that has never been loaded from disk.
        final capturedExtensions = SessionExtensions.capture(
          saveContainer.read(_refProvider),
          const <String, Object?>{},
        );
        expect(capturedExtensions, {
          'test.echo': {'n': 7},
        });

        final stateToSave = const SessionState().copyWith(
          extensions: capturedExtensions,
        );

        await _withTempFile((path) async {
          await _service.saveSession(stateToSave, path);

          // Sanity: the on-disk JSON carries the codec payload under the
          // reserved top-level key.
          final decoded =
              jsonDecode(await File(path).readAsString())
                  as Map<String, Object?>;
          expect(decoded['extensions'], {
            'test.echo': {'n': 7},
          });

          // RESTORE leg: fresh container with the same codec registered.
          // The codec is responsible for writing 7 back into
          // _restoredValueProvider; it starts at 0.
          final restoreContainer = ProviderContainer(
            overrides: [
              extraSessionPayloadCodecsProvider.overrideWithValue(
                <String, SessionExtensionCodec>{'test.echo': _echoCodec},
              ),
            ],
          );
          addTearDown(restoreContainer.dispose);
          expect(restoreContainer.read(_restoredValueProvider), 0);

          final loaded = await _service.loadSession(path);
          SessionExtensions.restore(
            restoreContainer.read(_refProvider),
            loaded.extensions,
          );

          expect(
            restoreContainer.read(_restoredValueProvider),
            7,
            reason:
                'codec restore must drive the target provider to the '
                'value captured at snapshot time',
          );
        });
      },
    );

    test('unknown-namespace payload is preserved on the SessionState side '
        'even when a different codec is registered', () async {
      // Container with only the test codec; the loaded payload contains
      // both "test.echo" and an unknown "pro.unseen" namespace. The codec
      // runtime restores test.echo and leaves pro.unseen alone — the
      // unknown payload survives on SessionState.extensions so the next
      // save can emit it.
      final container = ProviderContainer(
        overrides: [
          extraSessionPayloadCodecsProvider.overrideWithValue(
            <String, SessionExtensionCodec>{'test.echo': _echoCodec},
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = const SessionState().copyWith(
        extensions: <String, Object?>{
          'test.echo': <String, Object?>{'n': 3},
          'pro.unseen': <String, Object?>{'preserve': true},
        },
      );

      SessionExtensions.restore(container.read(_refProvider), state.extensions);
      expect(container.read(_restoredValueProvider), 3);

      // The SessionState carrying the unknown payload remains the source
      // of truth for the next snapshot. Capture with the same base map
      // should retain "pro.unseen" verbatim.
      container.read(_liveValueProvider.notifier).update(9);
      final captured = SessionExtensions.capture(
        container.read(_refProvider),
        state.extensions,
      );
      expect(captured, {
        'test.echo': {'n': 9},
        'pro.unseen': {'preserve': true},
      });
    });

    test(
      'capture is a no-op when no codecs are registered (preserves base)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final base = <String, Object?>{
          'pro.foreign': <String, Object?>{'a': 1},
        };
        final captured = SessionExtensions.capture(
          container.read(_refProvider),
          base,
        );
        expect(captured, base);
        // Defensive copy: mutating the returned map must not bleed back.
        captured['mutated'] = true;
        expect(base.containsKey('mutated'), isFalse);
      },
    );
  });
}
