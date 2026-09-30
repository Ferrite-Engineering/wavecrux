// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';

void main() {
  group('DecoderPluginInfo', () {
    const info = DecoderPluginInfo(
      pluginId: 'plugin-abc',
      displayName: 'Demo Plugin',
      filePath: '/plugins/demo.dylib',
      declaredAbiVersion: 0x00010002,
      loadStatus: DecoderPluginLoadStatus.loaded,
      registeredDecoderIds: ['examples.demo'],
    );

    test('default value of registeredDecoderIds is empty', () {
      const minimal = DecoderPluginInfo(
        pluginId: 'a',
        displayName: 'A',
        filePath: '/a.so',
        declaredAbiVersion: 0,
        loadStatus: DecoderPluginLoadStatus.loaded,
      );
      expect(minimal.registeredDecoderIds, isEmpty);
      expect(minimal.errorMessage, isNull);
      expect(minimal.pluginDescription, isNull);
    });

    test('declaredAbiMajor / declaredAbiMinor decode the version word', () {
      expect(info.declaredAbiMajor, 1);
      expect(info.declaredAbiMinor, 2);
    });

    test('major/minor decode handles MAJOR=2 / MINOR=0', () {
      const v = DecoderPluginInfo(
        pluginId: 'x',
        displayName: 'X',
        filePath: '/x.so',
        declaredAbiVersion: 0x00020000,
        loadStatus: DecoderPluginLoadStatus.abiMismatch,
      );
      expect(v.declaredAbiMajor, 2);
      expect(v.declaredAbiMinor, 0);
    });

    group('copyWith', () {
      test('no args returns equal object', () {
        expect(info.copyWith(), info);
      });

      test('updates loadStatus', () {
        final updated = info.copyWith(
          loadStatus: DecoderPluginLoadStatus.disabled,
        );
        expect(updated.loadStatus, DecoderPluginLoadStatus.disabled);
        expect(updated.pluginId, info.pluginId);
      });

      test('updates errorMessage', () {
        final updated = info.copyWith(errorMessage: 'boom');
        expect(updated.errorMessage, 'boom');
      });

      test('clearErrorMessage drops the existing message', () {
        const withErr = DecoderPluginInfo(
          pluginId: 'a',
          displayName: 'A',
          filePath: '/a.so',
          declaredAbiVersion: 0,
          loadStatus: DecoderPluginLoadStatus.loadError,
          errorMessage: 'failed',
        );
        final cleared = withErr.copyWith(clearErrorMessage: true);
        expect(cleared.errorMessage, isNull);
      });

      test('updates registeredDecoderIds', () {
        final updated = info.copyWith(registeredDecoderIds: ['a', 'b']);
        expect(updated.registeredDecoderIds, ['a', 'b']);
      });

      test('updates pluginDescription', () {
        final updated = info.copyWith(pluginDescription: 'GPLv3+ bridge');
        expect(updated.pluginDescription, 'GPLv3+ bridge');
      });

      test('clearPluginDescription drops the existing description', () {
        const withDesc = DecoderPluginInfo(
          pluginId: 'a',
          displayName: 'A',
          filePath: '/a.so',
          declaredAbiVersion: 0,
          loadStatus: DecoderPluginLoadStatus.loaded,
          pluginDescription: 'origin notice',
        );
        final cleared = withDesc.copyWith(clearPluginDescription: true);
        expect(cleared.pluginDescription, isNull);
      });
    });

    group('equality', () {
      test('identical instances are equal', () {
        const a = DecoderPluginInfo(
          pluginId: 'p',
          displayName: 'P',
          filePath: '/p.so',
          declaredAbiVersion: 0x00010000,
          loadStatus: DecoderPluginLoadStatus.loaded,
        );
        const b = DecoderPluginInfo(
          pluginId: 'p',
          displayName: 'P',
          filePath: '/p.so',
          declaredAbiVersion: 0x00010000,
          loadStatus: DecoderPluginLoadStatus.loaded,
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('differing pluginId breaks equality', () {
        const a = info;
        final b = info.copyWith(pluginId: 'other');
        expect(a, isNot(b));
      });

      test('differing registeredDecoderIds breaks equality', () {
        const a = info;
        final b = info.copyWith(registeredDecoderIds: ['examples.other']);
        expect(a, isNot(b));
      });

      test('differing errorMessage breaks equality', () {
        const a = info;
        final b = info.copyWith(errorMessage: 'something');
        expect(a, isNot(b));
      });

      test('differing pluginDescription breaks equality', () {
        const a = info;
        final b = info.copyWith(pluginDescription: 'a bridge');
        expect(a, isNot(b));
      });
    });

    test('toString embeds all fields', () {
      final s = info.toString();
      expect(s, contains('plugin-abc'));
      expect(s, contains('Demo Plugin'));
      expect(s, contains('/plugins/demo.dylib'));
      expect(s, contains('loaded'));
      expect(s, contains('examples.demo'));
      expect(s, contains('pluginDescription'));
    });
  });
}
