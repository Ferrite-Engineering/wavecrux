// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_validation_error.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_yaml_parser.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Loads the bundled tachometer manifest from disk for round-trip testing.
///
/// Tests load the source via `File` rather than `rootBundle.loadString`
/// because the round-trip test exercises the parser/serializer pair
/// without needing a Flutter widget tree.
String _loadManifestSource() {
  final file = File('assets/stage/widgets/rive/manifest.yaml');
  if (!file.existsSync()) {
    fail(
      'Tachometer manifest fixture missing at ${file.path}. The '
      'reference widget ships its manifest under assets/stage/widgets/rive — '
      'if this file moved, update the test path.',
    );
  }
  return file.readAsStringSync();
}

void main() {
  group('Tachometer manifest — parse', () {
    test('declares the documented identity and runtime metadata', () {
      final manifest = parseStageWidgetManifest(_loadManifestSource());

      expect(manifest.id, 'com.wavecrux.pro.stage.tachometer');
      expect(manifest.version, '1.0.0');
      expect(manifest.category, StageWidgetCategory.instrument);
      expect(manifest.runtime, ManifestRuntime.rive);
      expect(manifest.runtimeAssetPath, 'runtime/tachometer.riv');
      expect(manifest.requiredApiVersion, 1);
    });

    test('localized display name covers every Stage Pro locale', () {
      final manifest = parseStageWidgetManifest(_loadManifestSource());
      // The manifest's display_name must include en plus all four
      // CJK locales the Pro pack ARB files cover. LocalizedString.resolve
      // takes a string locale code (e.g. "en", "zh_CN") — not a Locale.
      expect(manifest.displayName.resolve('en'), 'Tachometer');
      expect(manifest.displayName.resolve('zh'), '转速表');
      expect(manifest.displayName.resolve('zh_CN'), '转速表');
      expect(manifest.displayName.resolve('ja'), 'タコメーター');
      expect(manifest.displayName.resolve('ko'), '타코미터');
    });

    test('declares three required signal bindings — rpm, redline, shift', () {
      final manifest = parseStageWidgetManifest(_loadManifestSource());
      expect(manifest.signalBindings, hasLength(3));

      final byName = {
        for (final b in manifest.signalBindings) b.name: b,
      };
      expect(byName.keys, containsAll(['rpm', 'redline', 'shift']));

      for (final binding in manifest.signalBindings) {
        expect(
          binding.required,
          isTrue,
          reason:
              '${binding.name} should be required — the Tachometer '
              'binding contract requires every state-machine input to be '
              'bound for the gauge to animate correctly',
        );
      }
    });

    test('rpm binding is a vector with min bit-width = 1', () {
      final manifest = parseStageWidgetManifest(_loadManifestSource());
      final rpm = manifest.signalBindings.firstWhere((b) => b.name == 'rpm');
      expect(rpm.signalType, SignalType.vector);
      expect(rpm.bitWidth, isNotNull);
      expect(rpm.bitWidth!.min, 1);
      // No max declared — any RPM bus width is accepted; the widget's
      // per-instance LinearNormalizer overrides the manifest's static
      // 0..8192 mapping with the user's configured range.
      expect(rpm.bitWidth!.max, isNull);
    });

    test('redline + shift are scalar bindings (1-bit booleans)', () {
      final manifest = parseStageWidgetManifest(_loadManifestSource());
      for (final name in const ['redline', 'shift']) {
        final binding = manifest.signalBindings.firstWhere(
          (b) => b.name == name,
        );
        expect(binding.signalType, SignalType.scalar);
      }
    });

    test('rpm parameter declares a clamping LinearNormalizer onto 0..1', () {
      final manifest = parseStageWidgetManifest(_loadManifestSource());
      // Exactly one parameters entry — the rpm normalizer. redline and
      // shift route directly through the controller's default boolean
      // path (no transformation).
      expect(manifest.parameters, hasLength(1));
      final rpmParam = manifest.parameters.firstWhere(
        (p) => p.binding == 'rpm',
      );
      expect(rpmParam.normalizer, isA<LinearNormalizer>());
      final n = rpmParam.normalizer as LinearNormalizer;
      expect(n.inputMin, 0.0);
      expect(n.inputMax, 8192.0);
      expect(n.outputMin, 0.0);
      expect(n.outputMax, 1.0);
      expect(n.clamp, isTrue);
      // X/Z policy defaults to propagate so out-of-band samples surface
      // through the NormalizedXZ → "hold previous value" path.
      expect(n.xzPolicy, XZPolicy.propagate);
    });

    test('source has no validation errors', () {
      // A parser failure throws ManifestValidationException with a list
      // of every collected error; this assertion guards against silent
      // regressions in the bundled manifest as the schema evolves.
      expect(
        () => parseStageWidgetManifest(_loadManifestSource()),
        returnsNormally,
      );
    });
  });

  group('Tachometer manifest — round-trip', () {
    test('parse → serialize → re-parse yields an equal manifest', () {
      final source = _loadManifestSource();
      final original = parseStageWidgetManifest(source);
      final yaml = serializeStageWidgetManifest(original);
      final reparsed = parseStageWidgetManifest(yaml);
      expect(reparsed, equals(original));
    });

    test(
      'serialized YAML preserves every signal binding, parameter, and '
      'normalizer field',
      () {
        final original = parseStageWidgetManifest(_loadManifestSource());
        final yaml = serializeStageWidgetManifest(original);

        // Spot-check structural anchors that round-trip must preserve.
        expect(yaml, contains('id: com.wavecrux.pro.stage.tachometer'));
        expect(yaml, contains('runtime: rive'));
        expect(yaml, contains('runtime_asset_path: runtime/tachometer.riv'));
        expect(yaml, contains('signal_bindings:'));
        expect(yaml, contains('name: rpm'));
        expect(yaml, contains('name: redline'));
        expect(yaml, contains('name: shift'));
        expect(yaml, contains('parameters:'));
        expect(yaml, contains('kind: linear'));
        expect(yaml, contains('input_max: 8192'));
      },
    );

    test('two round trips converge to the same canonical YAML', () {
      // The first serialize may canonicalize key order or quoting; the
      // second must be byte-identical because the parser consumed a
      // canonical form. Guards against non-idempotent formatters.
      final original = parseStageWidgetManifest(_loadManifestSource());
      final once = serializeStageWidgetManifest(original);
      final twice = serializeStageWidgetManifest(
        parseStageWidgetManifest(once),
      );
      expect(twice, equals(once));
    });
  });

  group('Tachometer manifest — validation errors', () {
    test('rejects a manifest missing required top-level fields', () {
      const broken = '''
id: com.wavecrux.pro.stage.tachometer
version: "1.0.0"
display_name: "Tachometer"
''';
      try {
        parseStageWidgetManifest(broken);
        fail('Expected ManifestValidationException for missing fields');
      } on ManifestValidationException catch (e) {
        expect(e.errors, isNotEmpty);
        // Each missing required field should produce its own error so
        // authors see the full list — not just the first failure.
        final messages = e.errors.map((err) => err.message).toList();
        // category, runtime, runtime_asset_path, required_api_version
        // are all required.
        expect(messages.length, greaterThanOrEqualTo(4));
      }
    });

    test('rejects an unknown normalizer kind', () {
      const broken = '''
id: com.wavecrux.pro.stage.tachometer
version: "1.0.0"
display_name: "Tachometer"
category: instrument
runtime: rive
runtime_asset_path: runtime/tachometer.riv
required_api_version: 1
signal_bindings:
  - name: rpm
    description: RPM bus
    signal_type: vector
parameters:
  - binding: rpm
    normalizer:
      kind: voodoo
      magic: 42
''';
      expect(
        () => parseStageWidgetManifest(broken),
        throwsA(isA<ManifestValidationException>()),
      );
    });

    test('rejects a parameters entry that targets an undeclared binding', () {
      const broken = '''
id: com.wavecrux.pro.stage.tachometer
version: "1.0.0"
display_name: "Tachometer"
category: instrument
runtime: rive
runtime_asset_path: runtime/tachometer.riv
required_api_version: 1
signal_bindings:
  - name: rpm
    description: RPM bus
    signal_type: vector
parameters:
  - binding: not_declared
    normalizer:
      kind: linear
      input_min: 0
      input_max: 1
''';
      expect(
        () => parseStageWidgetManifest(broken),
        throwsA(isA<ManifestValidationException>()),
      );
    });

    test('rejects a non-numeric required_api_version', () {
      const broken = '''
id: com.wavecrux.pro.stage.tachometer
version: "1.0.0"
display_name: "Tachometer"
category: instrument
runtime: rive
runtime_asset_path: runtime/tachometer.riv
required_api_version: "v1"
''';
      expect(
        () => parseStageWidgetManifest(broken),
        throwsA(isA<ManifestValidationException>()),
      );
    });

    test('rejects empty source', () {
      expect(
        () => parseStageWidgetManifest(''),
        throwsA(isA<ManifestValidationException>()),
      );
    });
  });
}
