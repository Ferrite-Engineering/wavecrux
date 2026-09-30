// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/enums/display_format.dart';

import 'package:wavecrux/domain/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('default values', () {
      const s = AppSettings();
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.waveformFontSize, 12);
      expect(s.defaultDisplayFormat, DisplayFormat.hexadecimal);
      expect(s.defaultLaneHeight, 30);
      expect(s.autoReloadMode, AutoReloadMode.prompt);
      expect(s.autoSaveIntervalSeconds, 60);
      expect(s.autoConvertLargeVcd, isTrue);
      expect(s.remoteControlEnabled, isFalse);
      expect(s.remoteControlPort, 54321);
      expect(s.suppressLegacyFormatBanner, isFalse);
      expect(s.diagnosticsEnabled, isFalse);
      expect(s.orientationLockMode, OrientationLockMode.auto);
      expect(s.autoHideChromeSeconds, 3);
      expect(s.userPluginDirectories, isEmpty);
      expect(s.pluginSafetyAcknowledged, isFalse);
      expect(s.pluginLoadingDisabled, isFalse);
      expect(s.perPluginDisabled, isEmpty);
      expect(s.autoCheckForUpdates, isTrue);
    });

    test('autoCheckForUpdates copyWith and equality', () {
      const base = AppSettings();
      final off = base.copyWith(autoCheckForUpdates: false);
      expect(off.autoCheckForUpdates, isFalse);
      expect(off, isNot(base));
      expect(off.copyWith(autoCheckForUpdates: true), base);
    });

    test('canvasLegibilityBoost defaults off, copyWith and equality', () {
      const base = AppSettings();
      expect(base.canvasLegibilityBoost, isFalse);
      final on = base.copyWith(canvasLegibilityBoost: true);
      expect(on.canvasLegibilityBoost, isTrue);
      expect(on, isNot(base));
      expect(on.copyWith(canvasLegibilityBoost: false), base);
    });

    test('custom constructor values', () {
      final s = const AppSettings().copyWith(
        themeMode: AppThemeMode.light,
        waveformFontSize: 14,
        defaultDisplayFormat: DisplayFormat.binary,
        defaultLaneHeight: 40,
        autoReloadMode: AutoReloadMode.auto,
        autoSaveIntervalSeconds: 120,
        autoConvertLargeVcd: false,
      );
      expect(s.themeMode, AppThemeMode.light);
      expect(s.waveformFontSize, 14);
      expect(s.defaultDisplayFormat, DisplayFormat.binary);
      expect(s.defaultLaneHeight, 40);
      expect(s.autoReloadMode, AutoReloadMode.auto);
      expect(s.autoSaveIntervalSeconds, 120);
      expect(s.autoConvertLargeVcd, isFalse);
    });

    group('copyWith', () {
      test('no args returns equal object', () {
        const s = AppSettings();
        expect(s.copyWith(), s);
      });

      test('copies themeMode', () {
        const s = AppSettings();
        expect(
          s.copyWith(themeMode: AppThemeMode.system).themeMode,
          AppThemeMode.system,
        );
      });

      test('copies waveformFontSize', () {
        const s = AppSettings();
        expect(s.copyWith(waveformFontSize: 18).waveformFontSize, 18);
      });

      test('copies defaultDisplayFormat', () {
        const s = AppSettings();
        expect(
          s
              .copyWith(defaultDisplayFormat: DisplayFormat.octal)
              .defaultDisplayFormat,
          DisplayFormat.octal,
        );
      });

      test('copies defaultLaneHeight', () {
        const s = AppSettings();
        expect(s.copyWith(defaultLaneHeight: 50).defaultLaneHeight, 50);
      });

      test('copies autoReloadMode', () {
        const s = AppSettings();
        expect(
          s.copyWith(autoReloadMode: AutoReloadMode.off).autoReloadMode,
          AutoReloadMode.off,
        );
      });

      test('copies autoSaveIntervalSeconds', () {
        const s = AppSettings();
        expect(
          s.copyWith(autoSaveIntervalSeconds: 300).autoSaveIntervalSeconds,
          300,
        );
      });

      test('copies autoConvertLargeVcd', () {
        const s = AppSettings();
        expect(
          s.copyWith(autoConvertLargeVcd: false).autoConvertLargeVcd,
          isFalse,
        );
      });

      test('copies remoteControlEnabled', () {
        const s = AppSettings();
        expect(
          s.copyWith(remoteControlEnabled: true).remoteControlEnabled,
          isTrue,
        );
      });

      test('copies suppressLegacyFormatBanner', () {
        const s = AppSettings();
        expect(
          s
              .copyWith(suppressLegacyFormatBanner: true)
              .suppressLegacyFormatBanner,
          isTrue,
        );
      });

      test('copies wheelNavigatesTime', () {
        const s = AppSettings();
        expect(s.wheelNavigatesTime, isFalse);
        expect(s.copyWith(wheelNavigatesTime: true).wheelNavigatesTime, isTrue);
      });

      test('different wheelNavigatesTime not equal', () {
        expect(
          const AppSettings(wheelNavigatesTime: true),
          isNot(const AppSettings()),
        );
      });

      test('copies remoteControlPort', () {
        const s = AppSettings();
        expect(s.copyWith(remoteControlPort: 8080).remoteControlPort, 8080);
      });

      test('copies diagnosticsEnabled', () {
        const s = AppSettings();
        expect(s.copyWith(diagnosticsEnabled: true).diagnosticsEnabled, isTrue);
      });

      test('copies orientationLockMode', () {
        const s = AppSettings();
        expect(
          s
              .copyWith(orientationLockMode: OrientationLockMode.landscapeLock)
              .orientationLockMode,
          OrientationLockMode.landscapeLock,
        );
      });

      test('copies autoHideChromeSeconds', () {
        const s = AppSettings();
        expect(s.copyWith(autoHideChromeSeconds: 12).autoHideChromeSeconds, 12);
      });

      test('copies userPluginDirectories', () {
        const s = AppSettings();
        final updated = s.copyWith(
          userPluginDirectories: ['/opt/wc', '/srv/decoders'],
        );
        expect(updated.userPluginDirectories, ['/opt/wc', '/srv/decoders']);
      });

      test('copies pluginSafetyAcknowledged', () {
        const s = AppSettings();
        expect(
          s.copyWith(pluginSafetyAcknowledged: true).pluginSafetyAcknowledged,
          isTrue,
        );
      });

      test('copies pluginLoadingDisabled', () {
        const s = AppSettings();
        expect(
          s.copyWith(pluginLoadingDisabled: true).pluginLoadingDisabled,
          isTrue,
        );
      });

      test('copies perPluginDisabled', () {
        const s = AppSettings();
        final updated = s.copyWith(perPluginDisabled: {'a': true, 'b': false});
        expect(updated.perPluginDisabled, {'a': true, 'b': false});
      });

      test('original is unmodified after copyWith', () {
        const original = AppSettings();
        final mutated = original.copyWith(
          themeMode: AppThemeMode.light,
          waveformFontSize: 20,
        );
        expect(mutated.themeMode, AppThemeMode.light);
        expect(original.themeMode, AppThemeMode.dark);
        expect(original.waveformFontSize, 12);
      });
    });

    group('equality', () {
      test('two defaults are equal', () {
        expect(const AppSettings(), const AppSettings());
      });

      test('same values are equal', () {
        final a = const AppSettings().copyWith(
          themeMode: AppThemeMode.light,
          waveformFontSize: 16,
        );
        final b = const AppSettings().copyWith(
          themeMode: AppThemeMode.light,
          waveformFontSize: 16,
        );
        expect(a, b);
      });

      test('different themeMode not equal', () {
        expect(
          const AppSettings().copyWith(themeMode: AppThemeMode.light),
          isNot(const AppSettings()),
        );
      });

      test('different waveformFontSize not equal', () {
        expect(
          const AppSettings(waveformFontSize: 10),
          isNot(const AppSettings(waveformFontSize: 14)),
        );
      });

      test('different autoConvertLargeVcd not equal', () {
        expect(
          const AppSettings(autoConvertLargeVcd: false),
          isNot(const AppSettings()),
        );
      });

      test('different remoteControlEnabled not equal', () {
        expect(
          const AppSettings(remoteControlEnabled: true),
          isNot(const AppSettings()),
        );
      });

      test('different suppressLegacyFormatBanner not equal', () {
        expect(
          const AppSettings(suppressLegacyFormatBanner: true),
          isNot(const AppSettings()),
        );
      });

      test('different remoteControlPort not equal', () {
        expect(
          const AppSettings(remoteControlPort: 1111),
          isNot(const AppSettings(remoteControlPort: 2222)),
        );
      });

      test('different diagnosticsEnabled not equal', () {
        expect(
          const AppSettings().copyWith(diagnosticsEnabled: true),
          isNot(const AppSettings()),
        );
      });

      test('different orientationLockMode not equal', () {
        expect(
          const AppSettings().copyWith(
            orientationLockMode: OrientationLockMode.landscapeLock,
          ),
          isNot(const AppSettings()),
        );
      });

      test('different autoHideChromeSeconds not equal', () {
        expect(
          const AppSettings().copyWith(autoHideChromeSeconds: 10),
          isNot(const AppSettings()),
        );
      });

      test('different userPluginDirectories not equal', () {
        expect(
          const AppSettings().copyWith(userPluginDirectories: ['/x']),
          isNot(const AppSettings()),
        );
      });

      test('different pluginSafetyAcknowledged not equal', () {
        expect(
          const AppSettings().copyWith(pluginSafetyAcknowledged: true),
          isNot(const AppSettings()),
        );
      });

      test('different pluginLoadingDisabled not equal', () {
        expect(
          const AppSettings().copyWith(pluginLoadingDisabled: true),
          isNot(const AppSettings()),
        );
      });

      test('different perPluginDisabled not equal', () {
        expect(
          const AppSettings().copyWith(perPluginDisabled: {'p': true}),
          isNot(const AppSettings()),
        );
      });

      test('matching userPluginDirectories preserve equality', () {
        expect(
          const AppSettings().copyWith(userPluginDirectories: ['/x', '/y']),
          const AppSettings().copyWith(userPluginDirectories: ['/x', '/y']),
        );
      });

      test('matching perPluginDisabled preserve equality', () {
        expect(
          const AppSettings().copyWith(
            perPluginDisabled: {'p': true, 'q': false},
          ),
          const AppSettings().copyWith(
            perPluginDisabled: {'p': true, 'q': false},
          ),
        );
      });

      test('userPluginDirectories order matters', () {
        expect(
          const AppSettings().copyWith(userPluginDirectories: ['/x', '/y']),
          isNot(
            const AppSettings().copyWith(userPluginDirectories: ['/y', '/x']),
          ),
        );
      });

      test('hashCode is consistent', () {
        const a = AppSettings();
        const b = AppSettings();
        expect(a.hashCode, b.hashCode);
      });

      test('not equal to non-AppSettings object', () {
        expect(const AppSettings(), isNot('string'));
      });

      test('identical instance equals itself', () {
        const s = AppSettings();
        expect(s == s, isTrue);
      });
    });

    test('toString contains all field names', () {
      final s = const AppSettings().toString();
      expect(s, contains('themeMode'));
      expect(s, contains('waveformFontSize'));
      expect(s, contains('defaultDisplayFormat'));
      expect(s, contains('defaultLaneHeight'));
      expect(s, contains('autoReloadMode'));
      expect(s, contains('autoSaveIntervalSeconds'));
      expect(s, contains('autoConvertLargeVcd'));
      expect(s, contains('remoteControlEnabled'));
      expect(s, contains('remoteControlPort'));
      expect(s, contains('diagnosticsEnabled'));
      expect(s, contains('orientationLockMode'));
      expect(s, contains('autoHideChromeSeconds'));
      expect(s, contains('userPluginDirectories'));
      expect(s, contains('pluginSafetyAcknowledged'));
      expect(s, contains('pluginLoadingDisabled'));
      expect(s, contains('perPluginDisabled'));
      expect(s, contains('suppressLegacyFormatBanner'));
      expect(s, contains('wheelNavigatesTime'));
    });

    group('AI settings fields', () {
      test('default to off / Anthropic / empty endpoint', () {
        const s = AppSettings();
        expect(s.aiExperimentalEnabled, isFalse);
        expect(s.aiProvider, AiProvider.anthropic);
        expect(s.aiEndpoint, '');
      });

      test('copyWith overrides each AI field independently', () {
        final s = const AppSettings().copyWith(
          aiExperimentalEnabled: true,
          aiProvider: AiProvider.ollama,
          aiEndpoint: 'http://localhost:11434',
        );
        expect(s.aiExperimentalEnabled, isTrue);
        expect(s.aiProvider, AiProvider.ollama);
        expect(s.aiEndpoint, 'http://localhost:11434');
        // Unrelated fields are preserved.
        expect(s.waveformFontSize, const AppSettings().waveformFontSize);
      });

      test('equality and hashCode account for the AI fields', () {
        const base = AppSettings();
        final providerChanged = base.copyWith(aiProvider: AiProvider.openai);
        final enabledChanged = base.copyWith(aiExperimentalEnabled: true);
        final endpointChanged = base.copyWith(aiEndpoint: 'x');

        expect(providerChanged, isNot(base));
        expect(enabledChanged, isNot(base));
        expect(endpointChanged, isNot(base));
        expect(
          base.copyWith(aiProvider: AiProvider.anthropic),
          base,
        );
        expect(enabledChanged.hashCode, isNot(base.hashCode));
      });
    });
  });
}
