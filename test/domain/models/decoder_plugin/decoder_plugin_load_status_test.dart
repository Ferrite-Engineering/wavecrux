// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';

void main() {
  group('DecoderPluginLoadStatus', () {
    test('exposes the seven expected values', () {
      expect(DecoderPluginLoadStatus.values, hasLength(7));
      expect(
        DecoderPluginLoadStatus.values,
        containsAll(<DecoderPluginLoadStatus>[
          DecoderPluginLoadStatus.loaded,
          DecoderPluginLoadStatus.abiMismatch,
          DecoderPluginLoadStatus.missingSymbol,
          DecoderPluginLoadStatus.manifestInvalid,
          DecoderPluginLoadStatus.loadError,
          DecoderPluginLoadStatus.disabled,
          DecoderPluginLoadStatus.notAllowlisted,
        ]),
      );
    });

    test('a policy refusal is its own value, not disabled or an error', () {
      // The three are different facts and the panel colours them differently:
      // `disabled` is the user's own choice and reversible in Settings,
      // `loadError` is a broken plugin, and `notAllowlisted` is the
      // organization's decision — the file is fine and Settings cannot
      // override it. Collapsing any pair sends somebody to the wrong place.
      expect(
        DecoderPluginLoadStatus.notAllowlisted,
        isNot(DecoderPluginLoadStatus.disabled),
      );
      expect(
        DecoderPluginLoadStatus.notAllowlisted,
        isNot(DecoderPluginLoadStatus.loadError),
      );
    });

    test('values are distinct', () {
      final asSet = DecoderPluginLoadStatus.values.toSet();
      expect(asSet.length, DecoderPluginLoadStatus.values.length);
    });
  });
}
