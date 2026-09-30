// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_validation_error.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_yaml_parser.dart';
import 'package:wavecrux/features/stage/sdk/normalization/bit_field_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/boolean_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/enum_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalizer_chain.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';

const _minimalManifest = '''
id: com.acme.minimal
version: "0.1.0"
display_name: "Minimal"
category: primitive
runtime: rive
runtime_asset_path: animations/minimal.riv
required_api_version: 1
''';

const _fullManifest = '''
id: com.acme.gauge
version: "1.2.3"
display_name:
  en: "Gauge Cluster"
  zh_CN: "仪表组"
  ja: "ゲージクラスタ"
  ko: "게이지 클러스터"
category: instrument
runtime: rive
runtime_asset_path: animations/gauge.riv
required_api_version: 1
icon_asset_path: icons/gauge.png
signal_bindings:
  - name: data
    description: 16-bit data bus driving the gauge
    signal_type: vector
    bit_width:
      min: 8
      max: 32
    value_range:
      min: 0
      max: 65535
    required: true
    default_policy: hold_last
  - name: enable
    description: Active-high enable
    signal_type: scalar
    direction: input
    required: false
    default_policy: treat_as_zero
parameters:
  - binding: data
    normalizer:
      chain:
        - kind: bit_field
          high_bit: 15
          low_bit: 8
        - kind: linear
          input_min: 0
          input_max: 255
          output_min: 0.0
          output_max: 1.0
  - binding: enable
    normalizer:
      kind: boolean
''';

void main() {
  group('parseStageWidgetManifest — happy path', () {
    test('parses minimal manifest', () {
      final m = parseStageWidgetManifest(_minimalManifest);
      expect(m.id, 'com.acme.minimal');
      expect(m.version, '0.1.0');
      expect(m.displayName.resolve('en'), 'Minimal');
      expect(m.category, StageWidgetCategory.primitive);
      expect(m.runtime, ManifestRuntime.rive);
      expect(m.runtimeAssetPath, 'animations/minimal.riv');
      expect(m.requiredApiVersion, 1);
      expect(m.iconAssetPath, isNull);
      expect(m.signalBindings, isEmpty);
      expect(m.parameters, isEmpty);
    });

    test('parses fully-populated manifest', () {
      final m = parseStageWidgetManifest(_fullManifest);
      expect(m.id, 'com.acme.gauge');
      expect(m.displayName.resolve('zh_CN'), '仪表组');
      expect(m.displayName.resolve('ja'), 'ゲージクラスタ');
      expect(m.displayName.resolve('ko'), '게이지 클러스터');
      expect(m.signalBindings, hasLength(2));
      expect(m.signalBindings[0].name, 'data');
      expect(m.signalBindings[0].signalType, SignalType.vector);
      expect(m.signalBindings[0].bitWidth?.min, 8);
      expect(m.signalBindings[0].bitWidth?.max, 32);
      expect(m.signalBindings[0].valueRange?.min, 0.0);
      expect(m.signalBindings[0].valueRange?.max, 65535.0);
      expect(m.signalBindings[1].defaultPolicy, DefaultPolicy.treatAsZero);
      expect(m.parameters, hasLength(2));
      expect(m.parameters[0].normalizer, isA<NormalizerChain>());
      final chain = m.parameters[0].normalizer as NormalizerChain;
      expect(chain.stages, hasLength(2));
      expect(chain.stages[0], isA<BitFieldNormalizer>());
      expect(chain.stages[1], isA<LinearNormalizer>());
      expect(m.parameters[1].normalizer, isA<BooleanNormalizer>());
    });
  });

  group('parseStageWidgetManifest — round-trip', () {
    test('minimal manifest round-trips through serialize/parse', () {
      final original = parseStageWidgetManifest(_minimalManifest);
      final yaml = serializeStageWidgetManifest(original);
      final reparsed = parseStageWidgetManifest(yaml);
      expect(reparsed, equals(original));
    });

    test('fully-populated manifest round-trips through serialize/parse', () {
      final original = parseStageWidgetManifest(_fullManifest);
      final yaml = serializeStageWidgetManifest(original);
      final reparsed = parseStageWidgetManifest(yaml);
      expect(reparsed, equals(original));
      // Spot-check serialised YAML contains expected keys.
      expect(yaml, contains('id: com.acme.gauge'));
      expect(yaml, contains('signal_bindings:'));
      expect(yaml, contains('high_bit: 15'));
    });

    test('enum normalizer round-trips its labels', () {
      const yaml = '''
id: com.acme.fsm
version: "1.0.0"
display_name: "FSM"
category: instrument
runtime: painter
runtime_asset_path: code/painter.dart
required_api_version: 1
signal_bindings:
  - name: state
    description: Current FSM state
    signal_type: vector
    bit_width:
      min: 2
      max: 4
parameters:
  - binding: state
    normalizer:
      kind: enum
      labels:
        0: IDLE
        1: RUNNING
        2: ERROR
      default_label: UNKNOWN
''';
      final parsed = parseStageWidgetManifest(yaml);
      final reparsed = parseStageWidgetManifest(
        serializeStageWidgetManifest(parsed),
      );
      expect(reparsed, equals(parsed));
      final normalizer = parsed.parameters.single.normalizer as EnumNormalizer;
      expect(normalizer.labels[BigInt.from(2)], 'ERROR');
      expect(normalizer.defaultLabel, 'UNKNOWN');
    });
  });

  group('parseStageWidgetManifest — malformed manifests', () {
    test('missing required field surfaces a clear error', () {
      const yaml = '''
id: com.acme.bad
version: "0.0.1"
display_name: "Bad"
category: primitive
runtime: rive
runtime_asset_path: a.riv
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(e.errors, isNotEmpty);
        expect(
          e.errors.any(
            (err) =>
                err.path == '/required_api_version' &&
                err.message.contains('missing'),
          ),
          isTrue,
        );
      }
    });

    test('unknown enum value reports allowed values', () {
      const yaml = '''
id: com.acme.bad
version: "0.0.1"
display_name: "Bad"
category: not_a_category
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path == '/category' &&
                err.message.contains('Invalid value'),
          ),
          isTrue,
        );
      }
    });

    test('parameter referencing unknown binding flagged', () {
      const yaml = '''
id: com.acme.bad
version: "0.0.1"
display_name: "Bad"
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
signal_bindings:
  - name: data
    description: bus
    signal_type: vector
parameters:
  - binding: missing_binding
    normalizer:
      kind: linear
      input_min: 0
      input_max: 1
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) => err.message.contains('unknown binding "missing_binding"'),
          ),
          isTrue,
        );
      }
    });

    test('multiple errors are collected, not fail-fast', () {
      const yaml = '''
id: ""
version: 1.0
display_name: "X"
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: -3
unknown_field: oops
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(e.errors.length, greaterThanOrEqualTo(3));
        final paths = e.errors.map((err) => err.path).toSet();
        // version provided as 1.0 (a double) — not a string.
        expect(paths, contains('/version'));
        // required_api_version is -3, below min.
        expect(paths, contains('/required_api_version'));
        // unknown_field rejected.
        expect(paths.any((p) => p.contains('unknown_field')), isTrue);
      }
    });

    test('errors carry source line and column', () {
      const yaml = '''
id: ok
version: "1.0"
display_name: "Bad"
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
parameters:
  - binding: nope
    normalizer:
      kind: not_a_kind
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        final unknownKind = e.errors.firstWhere(
          (err) => err.message.contains('Unknown normalizer kind'),
        );
        expect(unknownKind.line, isNotNull);
        expect(unknownKind.line, greaterThan(0));
        expect(unknownKind.column, isNotNull);
      }
    });
  });

  group('serializeStageWidgetManifest', () {
    test('produces deterministic output for equal manifests', () {
      final a = parseStageWidgetManifest(_fullManifest);
      final b = parseStageWidgetManifest(_fullManifest);
      expect(
        serializeStageWidgetManifest(a),
        serializeStageWidgetManifest(b),
      );
    });
  });

  group('integration: load, validate, normalize cursor sample', () {
    test('full flow produces normalized values for fixture sample', () {
      // Acceptance criterion from prompt: a fully-validated manifest can be
      // loaded, its signal bindings resolved against a fake waveform fixture,
      // and normalized values produced for the cursor sample.
      final manifest = parseStageWidgetManifest(_fullManifest);
      // Fake waveform fixture: signal "data" carries 0xAB55, "enable" = 1.
      final fixture = <String, RawSignalSample>{
        'data': const RawSignalSample(
          rawValue: '1010101101010101',
          bitWidth: 16,
        ),
        'enable': const RawSignalSample(rawValue: '1', bitWidth: 1),
      };

      // Resolve each binding against the fixture (acceptance check).
      for (final binding in manifest.signalBindings) {
        expect(
          fixture[binding.name],
          isNotNull,
          reason: 'fixture missing binding ${binding.name}',
        );
      }

      // Run each parameter's normalizer over its bound sample.
      final results = <String, NormalizedValue>{};
      for (final param in manifest.parameters) {
        final sample = fixture[param.binding]!;
        results[param.binding] = param.normalizer.normalize(sample);
      }

      // Data: bit_field [15:8] of 0xAB55 = 0xAB = 171; linear 0–255 ⇒ 171/255
      final dataResult = results['data']! as NormalizedDouble;
      expect(dataResult.value, closeTo(0xAB / 255, 1e-9));
      // Enable: boolean of '1' ⇒ true
      expect(
        results['enable'],
        equals(const NormalizedBool(value: true)),
      );
    });
  });

  // ── additional parser error paths (coverage gap closure) ─────────────────

  group('parseStageWidgetManifest — root shape errors', () {
    test('root is a YAML scalar (not a map) surfaces type error', () {
      try {
        parseStageWidgetManifest('"just a string"');
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(e.errors, isNotEmpty);
        expect(e.errors.first.path, '/');
      }
    });

    test('YAML syntax error surfaces parse failure', () {
      const yaml = '''
key: value
  bad: indentation: here
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(e.errors, isNotEmpty);
        expect(
          e.errors.any((err) => err.message.contains('YAML syntax error')),
          isTrue,
        );
      }
    });
  });

  group('parseStageWidgetManifest — localized field errors', () {
    test('display_name as integer (non-string scalar) is rejected', () {
      const yaml = '''
id: com.acme.test
version: "1.0"
display_name: 42
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path.contains('display_name') &&
                err.message.contains('Expected'),
          ),
          isTrue,
        );
      }
    });

    test('locale map with non-string value is rejected', () {
      const yaml = '''
id: com.acme.test
version: "1.0"
display_name:
  en: 42
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any((err) => err.path.contains('display_name')),
          isTrue,
        );
      }
    });

    test('empty locale map is rejected', () {
      const yaml = '''
id: com.acme.test
version: "1.0"
display_name: {}
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path.contains('display_name') &&
                err.message.contains('empty'),
          ),
          isTrue,
        );
      }
    });

    test('optional string field with non-string value is rejected', () {
      const yaml = '''
id: com.acme.test
version: "1.0"
display_name: "Test"
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
icon_asset_path: 42
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any((err) => err.path.contains('icon_asset_path')),
          isTrue,
        );
      }
    });
  });

  group('parseStageWidgetManifest — signal_bindings structural errors', () {
    const baseBinding = '''
id: com.acme.test
version: "1.0"
display_name: "Test"
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
''';

    test('signal_bindings as scalar (not a list) is rejected', () {
      const yaml = '${baseBinding}signal_bindings: "not-a-list"\n';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path == '/signal_bindings' &&
                err.message.contains('a list'),
          ),
          isTrue,
        );
      }
    });

    test('signal_bindings item that is a string (not a map) is rejected', () {
      const yaml =
          '''
${baseBinding}signal_bindings:
  - "not-a-map"
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path.contains('/signal_bindings/') &&
                err.message.contains('a map'),
          ),
          isTrue,
        );
      }
    });

    test('duplicate binding name produces error', () {
      const yaml =
          '''
${baseBinding}signal_bindings:
  - name: clk
    description: clock
    signal_type: scalar
  - name: clk
    description: duplicate clock
    signal_type: scalar
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any((err) => err.message.contains('Duplicate binding name')),
          isTrue,
        );
      }
    });

    test('scalar binding with bit_width declared is rejected', () {
      const yaml =
          '''
${baseBinding}signal_bindings:
  - name: enable
    description: Enable
    signal_type: scalar
    bit_width:
      min: 1
      max: 4
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) => err.message.contains(
              'Scalar bindings cannot declare a bit_width',
            ),
          ),
          isTrue,
        );
      }
    });
  });

  group('parseStageWidgetManifest — bit_width validation', () {
    const base = '''
id: com.acme.test
version: "1.0"
display_name: "Test"
category: primitive
runtime: rive
runtime_asset_path: a.riv
required_api_version: 1
signal_bindings:
  - name: data
    description: bus
    signal_type: vector
''';

    test('bit_width as a string (not a map) is rejected', () {
      const yaml = '$base    bit_width: "8 bits"\n';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path.contains('bit_width') && err.message.contains('a map'),
          ),
          isTrue,
        );
      }
    });

    test('bit_width min negative is rejected', () {
      const yaml =
          '''
$base    bit_width:
      min: -1
      max: 8
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path.contains('bit_width') && err.message.contains('>= 0'),
          ),
          isTrue,
        );
      }
    });

    test('bit_width max less than min is rejected', () {
      const yaml =
          '''
$base    bit_width:
      min: 16
      max: 8
''';
      try {
        parseStageWidgetManifest(yaml);
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(
          e.errors.any(
            (err) =>
                err.path.contains('bit_width') &&
                err.message.contains('must be >='),
          ),
          isTrue,
        );
      }
    });
  });

  // ── ManifestValidationError model coverage ────────────────────────────────

  group('ManifestValidationError', () {
    test('toString with coordinates shows line:column', () {
      const e = ManifestValidationError(
        message: 'bad field',
        path: '/foo',
        line: 3,
        column: 7,
      );
      expect(e.toString(), contains('3:7'));
      expect(e.toString(), contains('/foo'));
      expect(e.toString(), contains('bad field'));
    });

    test('toString without coordinates shows ?:?', () {
      const e = ManifestValidationError(message: 'oops', path: '/bar');
      expect(e.toString(), contains('?:?'));
    });

    test('== true for identical values', () {
      const a = ManifestValidationError(
        message: 'x',
        path: '/p',
        line: 1,
        column: 2,
      );
      const b = ManifestValidationError(
        message: 'x',
        path: '/p',
        line: 1,
        column: 2,
      );
      expect(a, b);
    });

    test('== false when message differs', () {
      const a = ManifestValidationError(message: 'a', path: '/p');
      const b = ManifestValidationError(message: 'b', path: '/p');
      expect(a, isNot(b));
    });

    test('hashCode consistent with ==', () {
      const a = ManifestValidationError(
        message: 'x',
        path: '/p',
        line: 1,
        column: 2,
      );
      const b = ManifestValidationError(
        message: 'x',
        path: '/p',
        line: 1,
        column: 2,
      );
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ManifestValidationException', () {
    test('toString lists errors with bullets', () {
      const e = ManifestValidationException([
        ManifestValidationError(message: 'err1', path: '/a'),
        ManifestValidationError(message: 'err2', path: '/b'),
      ]);
      final s = e.toString();
      expect(s, contains('2 error(s)'));
      expect(s, contains('err1'));
      expect(s, contains('err2'));
    });
  });

  // ── manifest enum wireName / fromWire coverage ────────────────────────────

  group('BindingDirection', () {
    test('output wireName is "output"', () {
      expect(BindingDirection.output.wireName, 'output');
    });

    test('fromWire("input") returns input', () {
      expect(BindingDirection.fromWire('input'), BindingDirection.input);
    });

    test('fromWire("output") returns output', () {
      expect(BindingDirection.fromWire('output'), BindingDirection.output);
    });

    test('fromWire unknown value returns null', () {
      expect(BindingDirection.fromWire('unknown'), isNull);
    });
  });

  group('SignalType', () {
    test('busGroup wireName is "bus_group"', () {
      expect(SignalType.busGroup.wireName, 'bus_group');
    });

    test('fromWire("bus_group") returns busGroup', () {
      expect(SignalType.fromWire('bus_group'), SignalType.busGroup);
    });

    test('fromWire("analog") returns analog', () {
      expect(SignalType.fromWire('analog'), SignalType.analog);
    });

    test('fromWire unknown value returns null', () {
      expect(SignalType.fromWire('not_a_type'), isNull);
    });
  });

  group('DefaultPolicy', () {
    test('treatAsX wireName is "treat_as_x"', () {
      expect(DefaultPolicy.treatAsX.wireName, 'treat_as_x');
    });

    test('fromWire("treat_as_x") returns treatAsX', () {
      expect(DefaultPolicy.fromWire('treat_as_x'), DefaultPolicy.treatAsX);
    });

    test('fromWire("hold_last") returns holdLast', () {
      expect(DefaultPolicy.fromWire('hold_last'), DefaultPolicy.holdLast);
    });

    test('fromWire unknown value returns null', () {
      expect(DefaultPolicy.fromWire('bogus'), isNull);
    });
  });

  group('ManifestRuntime', () {
    test('fromWire("rive") returns rive', () {
      expect(ManifestRuntime.fromWire('rive'), ManifestRuntime.rive);
    });

    test('fromWire("painter") returns painter', () {
      expect(ManifestRuntime.fromWire('painter'), ManifestRuntime.painter);
    });

    test('fromWire unknown value returns null', () {
      expect(ManifestRuntime.fromWire('unknown'), isNull);
    });
  });
}
