// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';

import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WaveCruxSettingsService', () {
    const service = WaveCruxSettingsService();

    test('load returns defaults when nothing is persisted', () async {
      final settings = await service.load();
      expect(settings, const AppSettings());
    });

    test('round-trip: save then load returns same values', () async {
      final original = const AppSettings().copyWith(
        themeMode: AppThemeMode.system,
        waveformFontSize: 16,
        defaultDisplayFormat: DisplayFormat.binary,
        defaultLaneHeight: 40,
        autoReloadMode: AutoReloadMode.auto,
        autoSaveIntervalSeconds: 300,
        autoConvertLargeVcd: false,
      );
      await service.save(original);
      final loaded = await service.load();
      expect(loaded, original);
    });

    test('round-trip: signalTreeNaturalSort survives (default true)', () async {
      // Default is ON; persisting the non-default (off) value must survive.
      expect((await service.load()).signalTreeNaturalSort, isTrue);
      await service.save(
        const AppSettings().copyWith(signalTreeNaturalSort: false),
      );
      final loaded = await service.load();
      expect(loaded.signalTreeNaturalSort, isFalse);
    });

    test('round-trip: wheelNavigatesTime survives', () async {
      await service.save(
        const AppSettings().copyWith(wheelNavigatesTime: true),
      );
      final loaded = await service.load();
      expect(loaded.wheelNavigatesTime, isTrue);
    });

    test('round-trip: canvasLegibilityBoost survives', () async {
      await service.save(
        const AppSettings().copyWith(canvasLegibilityBoost: true),
      );
      final loaded = await service.load();
      expect(loaded.canvasLegibilityBoost, isTrue);
    });

    test('canvasLegibilityBoost defaults to false', () async {
      final loaded = await service.load();
      expect(loaded.canvasLegibilityBoost, isFalse);
    });

    test('autoCheckForUpdates defaults to true', () async {
      final loaded = await service.load();
      expect(loaded.autoCheckForUpdates, isTrue);
    });

    test('round-trip: autoCheckForUpdates survives', () async {
      await service.save(
        const AppSettings().copyWith(autoCheckForUpdates: false),
      );
      final loaded = await service.load();
      expect(loaded.autoCheckForUpdates, isFalse);
    });

    test('round-trip: all AppThemeMode values survive', () async {
      for (final mode in AppThemeMode.values) {
        await service.save(const AppSettings().copyWith(themeMode: mode));
        final loaded = await service.load();
        expect(loaded.themeMode, mode, reason: 'mode: $mode');
      }
    });

    test('round-trip: all AutoReloadMode values survive', () async {
      for (final mode in AutoReloadMode.values) {
        await service.save(const AppSettings().copyWith(autoReloadMode: mode));
        final loaded = await service.load();
        expect(loaded.autoReloadMode, mode, reason: 'autoReloadMode: $mode');
      }
    });

    test('round-trip: all DisplayFormat values survive', () async {
      for (final fmt in DisplayFormat.values) {
        await service.save(
          const AppSettings().copyWith(defaultDisplayFormat: fmt),
        );
        final loaded = await service.load();
        expect(loaded.defaultDisplayFormat, fmt, reason: 'format: $fmt');
      }
    });

    test('logVerbosity defaults to normal', () async {
      final loaded = await service.load();
      expect(loaded.logVerbosity, LogVerbosity.normal);
    });

    test('round-trip: all LogVerbosity values survive', () async {
      for (final v in LogVerbosity.values) {
        await service.save(const AppSettings().copyWith(logVerbosity: v));
        final loaded = await service.load();
        expect(loaded.logVerbosity, v, reason: 'verbosity: $v');
      }
    });

    test('load uses default when logVerbosity index out of range', () async {
      SharedPreferences.setMockInitialValues({'settings.logVerbosity': 999});
      final loaded = await service.load();
      expect(loaded.logVerbosity, LogVerbosity.normal);
    });

    test('AI settings default to off / Anthropic / empty endpoint', () async {
      final loaded = await service.load();
      expect(loaded.aiExperimentalEnabled, isFalse);
      expect(loaded.aiProvider, AiProvider.anthropic);
      expect(loaded.aiEndpoint, '');
    });

    test('round-trip: aiExperimentalEnabled + endpoint survive', () async {
      await service.save(
        const AppSettings().copyWith(
          aiExperimentalEnabled: true,
          aiEndpoint: 'http://localhost:11434',
        ),
      );
      final loaded = await service.load();
      expect(loaded.aiExperimentalEnabled, isTrue);
      expect(loaded.aiEndpoint, 'http://localhost:11434');
    });

    test('round-trip: all AiProvider values survive', () async {
      for (final p in AiProvider.values) {
        await service.save(const AppSettings().copyWith(aiProvider: p));
        final loaded = await service.load();
        expect(loaded.aiProvider, p, reason: 'provider: $p');
      }
    });

    test('load uses default when aiProvider index out of range', () async {
      SharedPreferences.setMockInitialValues({'settings.aiProvider': 999});
      final loaded = await service.load();
      expect(loaded.aiProvider, AiProvider.anthropic);
    });

    test('the API key is never persisted to shared_preferences', () async {
      await service.save(
        const AppSettings().copyWith(aiExperimentalEnabled: true),
      );
      final prefs = await SharedPreferences.getInstance();
      // No settings.* key should resemble an AI API key store — the secret
      // lives only in platform secure storage via AiKeyStore.
      expect(
        prefs.getKeys().where((k) => k.toLowerCase().contains('apikey')),
        isEmpty,
      );
    });

    test('load clamps font size below minimum', () async {
      SharedPreferences.setMockInitialValues({
        'settings.waveformFontSize': 4.0,
      });
      final loaded = await service.load();
      expect(loaded.waveformFontSize, 8);
    });

    test('load clamps font size above maximum', () async {
      SharedPreferences.setMockInitialValues({
        'settings.waveformFontSize': 999.0,
      });
      final loaded = await service.load();
      expect(loaded.waveformFontSize, 24);
    });

    test('load clamps lane height below minimum', () async {
      SharedPreferences.setMockInitialValues({'settings.defaultLaneHeight': 0});
      final loaded = await service.load();
      expect(loaded.defaultLaneHeight, 16);
    });

    test('load clamps lane height above maximum', () async {
      SharedPreferences.setMockInitialValues({
        'settings.defaultLaneHeight': 9999,
      });
      final loaded = await service.load();
      expect(loaded.defaultLaneHeight, 200);
    });

    test('load clamps auto-save interval below minimum', () async {
      SharedPreferences.setMockInitialValues({
        'settings.autoSaveIntervalSeconds': 0,
      });
      final loaded = await service.load();
      expect(loaded.autoSaveIntervalSeconds, 10);
    });

    test('load clamps auto-save interval above maximum', () async {
      SharedPreferences.setMockInitialValues({
        'settings.autoSaveIntervalSeconds': 9999,
      });
      final loaded = await service.load();
      expect(loaded.autoSaveIntervalSeconds, 600);
    });

    test('load uses default when themeMode index out of range', () async {
      SharedPreferences.setMockInitialValues({'settings.themeMode': 999});
      final loaded = await service.load();
      expect(loaded.themeMode, AppThemeMode.dark);
    });

    test('load uses default when autoReloadMode index out of range', () async {
      SharedPreferences.setMockInitialValues({'settings.autoReloadMode': 999});
      final loaded = await service.load();
      expect(loaded.autoReloadMode, AutoReloadMode.prompt);
    });

    test('load uses default when displayFormat index out of range', () async {
      SharedPreferences.setMockInitialValues({
        'settings.defaultDisplayFormat': 999,
      });
      final loaded = await service.load();
      expect(loaded.defaultDisplayFormat, DisplayFormat.hexadecimal);
    });

    test('load uses default when themeMode index is negative', () async {
      SharedPreferences.setMockInitialValues({'settings.themeMode': -1});
      final loaded = await service.load();
      expect(loaded.themeMode, AppThemeMode.dark);
    });

    test('autoConvertLargeVcd false round-trips', () async {
      await service.save(const AppSettings(autoConvertLargeVcd: false));
      final loaded = await service.load();
      expect(loaded.autoConvertLargeVcd, isFalse);
    });

    test('diagnosticsEnabled true round-trips', () async {
      await service.save(
        const AppSettings().copyWith(diagnosticsEnabled: true),
      );
      final loaded = await service.load();
      expect(loaded.diagnosticsEnabled, isTrue);
    });

    test('diagnosticsEnabled defaults to false when key is absent', () async {
      final loaded = await service.load();
      expect(loaded.diagnosticsEnabled, isFalse);
    });

    test('round-trip: all OrientationLockMode values survive', () async {
      for (final mode in OrientationLockMode.values) {
        await service.save(
          const AppSettings().copyWith(orientationLockMode: mode),
        );
        final loaded = await service.load();
        expect(loaded.orientationLockMode, mode, reason: 'mode: $mode');
      }
    });

    test('orientationLockMode defaults to auto when key is absent', () async {
      final loaded = await service.load();
      expect(loaded.orientationLockMode, OrientationLockMode.auto);
    });

    test(
      'load uses default when orientationLockMode index out of range',
      () async {
        SharedPreferences.setMockInitialValues({
          'settings.orientationLockMode': 999,
        });
        final loaded = await service.load();
        expect(loaded.orientationLockMode, OrientationLockMode.auto);
      },
    );

    test('autoHideChromeSeconds round-trips', () async {
      await service.save(
        const AppSettings().copyWith(autoHideChromeSeconds: 7),
      );
      final loaded = await service.load();
      expect(loaded.autoHideChromeSeconds, 7);
    });

    test('load clamps autoHideChromeSeconds below minimum', () async {
      SharedPreferences.setMockInitialValues({
        'settings.autoHideChromeSeconds': 0,
      });
      final loaded = await service.load();
      expect(loaded.autoHideChromeSeconds, 1);
    });

    test('load clamps autoHideChromeSeconds above maximum', () async {
      SharedPreferences.setMockInitialValues({
        'settings.autoHideChromeSeconds': 9999,
      });
      final loaded = await service.load();
      expect(loaded.autoHideChromeSeconds, 30);
    });

    test('autoHideChromeSeconds defaults to 3 when key is absent', () async {
      final loaded = await service.load();
      expect(loaded.autoHideChromeSeconds, 3);
    });

    group('decoder plugin fields', () {
      test('userPluginDirectories round-trips as a string list', () async {
        await service.save(
          const AppSettings().copyWith(
            userPluginDirectories: ['/opt/wc/plugins', '/srv/team/decoders'],
          ),
        );
        final loaded = await service.load();
        expect(loaded.userPluginDirectories, [
          '/opt/wc/plugins',
          '/srv/team/decoders',
        ]);
      });

      test('userPluginDirectories defaults to empty', () async {
        final loaded = await service.load();
        expect(loaded.userPluginDirectories, isEmpty);
      });

      test('pluginSafetyAcknowledged round-trips', () async {
        await service.save(
          const AppSettings().copyWith(pluginSafetyAcknowledged: true),
        );
        final loaded = await service.load();
        expect(loaded.pluginSafetyAcknowledged, isTrue);
      });

      test('pluginSafetyAcknowledged defaults to false', () async {
        final loaded = await service.load();
        expect(loaded.pluginSafetyAcknowledged, isFalse);
      });

      test('pluginLoadingDisabled round-trips', () async {
        await service.save(
          const AppSettings().copyWith(pluginLoadingDisabled: true),
        );
        final loaded = await service.load();
        expect(loaded.pluginLoadingDisabled, isTrue);
      });

      test('pluginLoadingDisabled defaults to false', () async {
        final loaded = await service.load();
        expect(loaded.pluginLoadingDisabled, isFalse);
      });

      test('perPluginDisabled round-trips', () async {
        await service.save(
          const AppSettings().copyWith(
            perPluginDisabled: {'plugin-a': true, 'plugin-b': false},
          ),
        );
        final loaded = await service.load();
        expect(loaded.perPluginDisabled, {
          'plugin-a': true,
          'plugin-b': false,
        });
      });

      test('perPluginDisabled defaults to empty', () async {
        final loaded = await service.load();
        expect(loaded.perPluginDisabled, isEmpty);
      });

      test('malformed perPluginDisabled JSON falls back to empty', () async {
        SharedPreferences.setMockInitialValues({
          'settings.perPluginDisabled': 'not-json',
        });
        final loaded = await service.load();
        expect(loaded.perPluginDisabled, isEmpty);
      });

      test('non-map perPluginDisabled JSON falls back to empty', () async {
        SharedPreferences.setMockInitialValues({
          'settings.perPluginDisabled': '[]',
        });
        final loaded = await service.load();
        expect(loaded.perPluginDisabled, isEmpty);
      });

      test('perPluginDisabled drops non-bool values', () async {
        SharedPreferences.setMockInitialValues({
          'settings.perPluginDisabled':
              '{"a": true, "b": "yes", "c": 1, "d": false}',
        });
        final loaded = await service.load();
        expect(loaded.perPluginDisabled, {'a': true, 'd': false});
      });

      test('all four plugin fields round-trip together', () async {
        final original = const AppSettings().copyWith(
          userPluginDirectories: ['/abs/one'],
          pluginSafetyAcknowledged: true,
          pluginLoadingDisabled: true,
          perPluginDisabled: {'p': true},
        );
        await service.save(original);
        final loaded = await service.load();
        expect(loaded, original);
      });
    });
  });
}
