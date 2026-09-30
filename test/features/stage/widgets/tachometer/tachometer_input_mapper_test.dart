// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_parameter.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/boolean_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/domain/tachometer_config.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_input_mapper.dart';

/// VCD-style binary string of [value] zero-padded to [width] bits.
String _bits(int value, int width) =>
    value.toRadixString(2).padLeft(width, '0');

/// Builds a manifest mirroring the real tachometer.yaml shape — three
/// bindings (rpm vector, redline scalar, shift scalar), an rpm linear
/// normalizer parameter — so the mapper's manifest lookup behaves the
/// way it does in production.
StageWidgetManifest _buildManifest({
  bool includeParameters = true,
}) {
  return StageWidgetManifest(
    id: 'com.wavecrux.test.tachometer',
    version: '1.0.0',
    displayName: const LocalizedString.single('Tachometer'),
    category: StageWidgetCategory.instrument,
    runtime: ManifestRuntime.rive,
    runtimeAssetPath: 'runtime/tachometer.riv',
    requiredApiVersion: 1,
    signalBindings: const [
      ManifestSignalBinding(
        name: 'rpm',
        description: 'rpm',
        signalType: SignalType.vector,
      ),
      ManifestSignalBinding(
        name: 'redline',
        description: 'redline',
        signalType: SignalType.scalar,
      ),
      ManifestSignalBinding(
        name: 'shift',
        description: 'shift',
        signalType: SignalType.scalar,
      ),
    ],
    parameters: includeParameters
        ? const [
            ManifestParameter(
              binding: 'rpm',
              normalizer: LinearNormalizer(inputMin: 0, inputMax: 8192),
            ),
            ManifestParameter(
              binding: 'redline',
              normalizer: BooleanNormalizer(),
            ),
          ]
        : const [],
  );
}

const _boundRef = 'top.engine.rpm';
const _redlineRef = 'top.engine.redline';
const _shiftRef = 'top.engine.shift';

const _allBoundBindings = <String, StageSignalBinding>{
  'rpm': StageSignalBinding(signalRef: _boundRef),
  'redline': StageSignalBinding(signalRef: _redlineRef),
  'shift': StageSignalBinding(signalRef: _shiftRef),
};

void main() {
  group('tachometerBindingNames', () {
    test('lists the three canonical pins in manifest order', () {
      expect(tachometerBindingNames, ['rpm', 'redline', 'shift']);
    });
  });

  group('TachometerInputMapper.snapshotToRawSample', () {
    test('value-kind snapshot becomes a RawSignalSample tagged with '
        'cursorTicks and the snapshot fields', () {
      const snapshot = StageSignalSnapshot.value(
        rawValue: '00110011',
        bitWidth: 8,
      );
      final raw = TachometerInputMapper.snapshotToRawSample(snapshot, 12345);
      expect(raw, isNotNull);
      expect(raw!.rawValue, '00110011');
      expect(raw.bitWidth, 8);
      expect(raw.timeTicks, 12345);
      expect(raw.isAnalog, isFalse);
    });

    test('real-typed value snapshot forwards isReal as isAnalog', () {
      const snapshot = StageSignalSnapshot.value(
        rawValue: '3.14',
        bitWidth: 0,
        isReal: true,
      );
      final raw = TachometerInputMapper.snapshotToRawSample(snapshot, 0);
      expect(raw, isNotNull);
      expect(raw!.isAnalog, isTrue);
    });

    test('non-value lifecycle states return null (held-stale semantics)', () {
      for (final s in const [
        StageSignalSnapshot.unbound(),
        StageSignalSnapshot.noFile(),
        StageSignalSnapshot.loading(),
        StageSignalSnapshot.unknown(),
      ]) {
        expect(
          TachometerInputMapper.snapshotToRawSample(s, 100),
          isNull,
          reason: 'snapshot kind ${s.kind} must map to null',
        );
      }
    });
  });

  group('TachometerInputMapper.defaultNormalize', () {
    test('any X bit produces NormalizedXZ(isX: true)', () {
      const raw = RawSignalSample(rawValue: '00x1', bitWidth: 4);
      final r = TachometerInputMapper.defaultNormalize(raw);
      expect(r, isA<NormalizedXZ>());
      expect((r as NormalizedXZ).isX, isTrue);
    });

    test('any Z bit (no X) produces NormalizedXZ(isX: false)', () {
      const raw = RawSignalSample(rawValue: '00z1', bitWidth: 4);
      final r = TachometerInputMapper.defaultNormalize(raw);
      expect(r, isA<NormalizedXZ>());
      expect((r as NormalizedXZ).isX, isFalse);
    });

    test('1-bit scalar "1" produces NormalizedBool(true)', () {
      const raw = RawSignalSample(rawValue: '1', bitWidth: 1);
      final r = TachometerInputMapper.defaultNormalize(raw);
      expect(r, isA<NormalizedBool>());
      expect((r as NormalizedBool).value, isTrue);
    });

    test('1-bit scalar "0" produces NormalizedBool(false)', () {
      const raw = RawSignalSample(rawValue: '0', bitWidth: 1);
      final r = TachometerInputMapper.defaultNormalize(raw);
      expect(r, isA<NormalizedBool>());
      expect((r as NormalizedBool).value, isFalse);
    });

    test('VCD "b"-prefixed value strips the prefix before bigint parse', () {
      const raw = RawSignalSample(rawValue: 'b00001010', bitWidth: 8);
      final r = TachometerInputMapper.defaultNormalize(raw);
      expect(r, isA<NormalizedDouble>());
      expect((r as NormalizedDouble).value, 10.0);
    });

    test('wider vector parses as unsigned-int double', () {
      const raw = RawSignalSample(rawValue: '00001111', bitWidth: 8);
      final r = TachometerInputMapper.defaultNormalize(raw);
      expect(r, isA<NormalizedDouble>());
      expect((r as NormalizedDouble).value, 15.0);
    });

    test('non-parsable string fallback returns NormalizedXZ(isX: true)', () {
      const raw = RawSignalSample(rawValue: 'not-a-bit-string', bitWidth: 8);
      final r = TachometerInputMapper.defaultNormalize(raw);
      expect(r, isA<NormalizedXZ>());
      expect((r as NormalizedXZ).isX, isTrue);
    });
  });

  group('TachometerInputMapper.normalizerFor', () {
    test('rpm always returns a LinearNormalizer built from the config '
        'range, overriding the manifest', () {
      final manifest = _buildManifest();
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(minRpm: 1000, maxRpm: 12000),
        manifest: manifest,
      );
      final n = mapper.normalizerFor('rpm');
      expect(n, isA<LinearNormalizer>());
      final ln = n! as LinearNormalizer;
      expect(ln.inputMin, 1000.0);
      expect(ln.inputMax, 12000.0);
    });

    test('rpm normalizer ignores manifest declaration even when present', () {
      // Manifest declares rpm linear 0..8192; config says 1000..12000.
      // Mapper's rpm normalizer must come from config.
      final manifest = _buildManifest();
      const config = TachometerConfig(minRpm: 500, maxRpm: 9500);
      final mapper = TachometerInputMapper(config: config, manifest: manifest);
      final ln = mapper.normalizerFor('rpm')! as LinearNormalizer;
      expect(ln.inputMin, 500.0);
      expect(ln.inputMax, 9500.0);
    });

    test('non-rpm binding returns the manifest-declared normalizer when '
        'one is provided', () {
      final manifest = _buildManifest();
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: manifest,
      );
      final n = mapper.normalizerFor('redline');
      expect(n, isA<BooleanNormalizer>());
    });

    test('non-rpm binding returns null when manifest has no parameter for '
        'it', () {
      final manifest = _buildManifest(includeParameters: false);
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: manifest,
      );
      expect(mapper.normalizerFor('shift'), isNull);
      expect(mapper.normalizerFor('redline'), isNull);
    });

    test('null manifest returns null for any non-rpm binding', () {
      const mapper = TachometerInputMapper(
        config: TachometerConfig(),
        manifest: null,
      );
      expect(mapper.normalizerFor('redline'), isNull);
      expect(mapper.normalizerFor('shift'), isNull);
    });
  });

  group('TachometerInputMapper.missingBindings', () {
    test('all-bound map yields the empty set', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      expect(mapper.missingBindings(_allBoundBindings), isEmpty);
    });

    test('empty map yields every pin name as missing', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      expect(
        mapper.missingBindings(const {}),
        unorderedEquals(<String>{'rpm', 'redline', 'shift'}),
      );
    });

    test('partial map flags only the missing pins', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      const bindings = {
        'rpm': StageSignalBinding(signalRef: _boundRef),
        'shift': StageSignalBinding(signalRef: _shiftRef),
      };
      expect(
        mapper.missingBindings(bindings),
        unorderedEquals(<String>{'redline'}),
      );
    });

    test('empty-string signalRef counts as missing', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      const bindings = {
        'rpm': StageSignalBinding(signalRef: ''),
        'redline': StageSignalBinding(signalRef: _redlineRef),
        'shift': StageSignalBinding(signalRef: _shiftRef),
      };
      expect(
        mapper.missingBindings(bindings),
        unorderedEquals(<String>{'rpm'}),
      );
    });
  });

  group('TachometerInputMapper.map — happy path', () {
    test(
      'value snapshots produce normalized inputs for every pin, '
      'missingBindings empty',
      () {
        final manifest = _buildManifest();
        final mapper = TachometerInputMapper(
          config: const TachometerConfig(maxRpm: 8192),
          manifest: manifest,
        );
        final rpm = StageSignalSnapshot.value(
          rawValue: _bits(4096, 14),
          bitWidth: 14,
        );
        const redline = StageSignalSnapshot.value(
          rawValue: '1',
          bitWidth: 1,
        );
        const shift = StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        );
        final inputs = mapper.map(
          bindings: _allBoundBindings,
          rpmSnapshot: rpm,
          redlineSnapshot: redline,
          shiftSnapshot: shift,
          cursorTicks: 42,
        );
        expect(inputs.missingBindings, isEmpty);
        expect(inputs.hasMissingBindings, isFalse);
        // rpm: 4096 / 8192 = 0.5.
        expect(inputs.rpmInput, isA<NormalizedDouble>());
        expect(
          (inputs.rpmInput! as NormalizedDouble).value,
          closeTo(0.5, 1e-12),
        );
        // redline: manifest's BooleanNormalizer maps '1' to true.
        expect(inputs.redlineInput, isA<NormalizedBool>());
        expect((inputs.redlineInput! as NormalizedBool).value, isTrue);
        // shift: no manifest normalizer → default path → 1-bit scalar.
        expect(inputs.shiftInput, isA<NormalizedBool>());
        expect((inputs.shiftInput! as NormalizedBool).value, isFalse);
      },
    );

    test('per-instance config remaps rpm: minRpm=1000 maxRpm=12000, '
        '6500 → ~0.5', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(
          minRpm: 1000,
          maxRpm: 12000,
        ),
        manifest: _buildManifest(),
      );
      final rpm = StageSignalSnapshot.value(
        rawValue: _bits(6500, 14),
        bitWidth: 14,
      );
      final inputs = mapper.map(
        bindings: _allBoundBindings,
        rpmSnapshot: rpm,
        redlineSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        shiftSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        cursorTicks: 0,
      );
      expect(
        (inputs.rpmInput! as NormalizedDouble).value,
        closeTo((6500 - 1000) / (12000 - 1000), 1e-12),
      );
    });

    test('cursorTicks propagates to RawSignalSample.timeTicks for '
        'time-aware normalizers', () {
      // We can't observe timeTicks through map's output since the
      // default normalize path discards it, but we can observe it via
      // snapshotToRawSample. Validate the static helper here as the
      // contract surface map() depends on.
      const snapshot = StageSignalSnapshot.value(
        rawValue: '0',
        bitWidth: 1,
      );
      final raw = TachometerInputMapper.snapshotToRawSample(snapshot, 9999);
      expect(raw!.timeTicks, 9999);
    });
  });

  group('TachometerInputMapper.map — held-stale and missing cases', () {
    test('non-value snapshots produce null inputs (renderer holds prior '
        'value)', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      final inputs = mapper.map(
        bindings: _allBoundBindings,
        rpmSnapshot: const StageSignalSnapshot.loading(),
        redlineSnapshot: const StageSignalSnapshot.unknown(),
        shiftSnapshot: const StageSignalSnapshot.noFile(),
        cursorTicks: 0,
      );
      expect(inputs.rpmInput, isNull);
      expect(inputs.redlineInput, isNull);
      expect(inputs.shiftInput, isNull);
    });

    test('XZ samples on rpm propagate through the linear normalizer to '
        'NormalizedXZ', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      const rpm = StageSignalSnapshot.value(
        rawValue: 'xxxxxxxxxxxxxx',
        bitWidth: 14,
      );
      final inputs = mapper.map(
        bindings: _allBoundBindings,
        rpmSnapshot: rpm,
        redlineSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        shiftSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        cursorTicks: 0,
      );
      expect(inputs.rpmInput, isA<NormalizedXZ>());
      expect((inputs.rpmInput! as NormalizedXZ).isX, isTrue);
    });

    test('over-range rpm clamps to 1.0 (default clamp policy)', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      // 65535 > 8000 → expect clamp to 1.0.
      final rpm = StageSignalSnapshot.value(
        rawValue: _bits(65535, 16),
        bitWidth: 16,
      );
      final inputs = mapper.map(
        bindings: _allBoundBindings,
        rpmSnapshot: rpm,
        redlineSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        shiftSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        cursorTicks: 0,
      );
      expect((inputs.rpmInput! as NormalizedDouble).value, 1.0);
    });

    test('missing rpm binding is enumerated in missingBindings', () {
      final mapper = TachometerInputMapper(
        config: const TachometerConfig(),
        manifest: _buildManifest(),
      );
      final inputs = mapper.map(
        bindings: const {
          'redline': StageSignalBinding(signalRef: _redlineRef),
          'shift': StageSignalBinding(signalRef: _shiftRef),
        },
        rpmSnapshot: const StageSignalSnapshot.unbound(),
        redlineSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        shiftSnapshot: const StageSignalSnapshot.value(
          rawValue: '0',
          bitWidth: 1,
        ),
        cursorTicks: 0,
      );
      expect(inputs.hasMissingBindings, isTrue);
      expect(inputs.missingBindings, contains('rpm'));
    });

    test(
      'null manifest falls back to defaultNormalize for redline / shift',
      () {
        const mapper = TachometerInputMapper(
          config: TachometerConfig(),
          manifest: null,
        );
        final inputs = mapper.map(
          bindings: _allBoundBindings,
          rpmSnapshot: const StageSignalSnapshot.value(
            rawValue: '00000000000001',
            bitWidth: 14,
          ),
          redlineSnapshot: const StageSignalSnapshot.value(
            rawValue: '1',
            bitWidth: 1,
          ),
          shiftSnapshot: const StageSignalSnapshot.value(
            rawValue: '0',
            bitWidth: 1,
          ),
          cursorTicks: 0,
        );
        // rpm: rpm normalizer is config-driven, not manifest-driven.
        expect(inputs.rpmInput, isA<NormalizedDouble>());
        // redline / shift: default path → 1-bit → bool.
        expect(inputs.redlineInput, isA<NormalizedBool>());
        expect((inputs.redlineInput! as NormalizedBool).value, isTrue);
        expect(inputs.shiftInput, isA<NormalizedBool>());
        expect((inputs.shiftInput! as NormalizedBool).value, isFalse);
      },
    );
  });

  group('TachometerInputMapper.defaultNormalizeSnapshot', () {
    test('value snapshot routes through defaultNormalize', () {
      const mapper = TachometerInputMapper(
        config: TachometerConfig(),
        manifest: null,
      );
      final r = mapper.defaultNormalizeSnapshot(
        const StageSignalSnapshot.value(rawValue: '1', bitWidth: 1),
        0,
      );
      expect(r, isA<NormalizedBool>());
      expect((r! as NormalizedBool).value, isTrue);
    });

    test('non-value snapshot returns null', () {
      const mapper = TachometerInputMapper(
        config: TachometerConfig(),
        manifest: null,
      );
      expect(
        mapper.defaultNormalizeSnapshot(
          const StageSignalSnapshot.unbound(),
          0,
        ),
        isNull,
      );
    });
  });

  group('TachometerInputs value type', () {
    test(
      'inputFor returns the matching field, or null for an unknown name',
      () {
        const inputs = TachometerInputs(
          rpmInput: NormalizedDouble(0.42),
          redlineInput: NormalizedBool(value: true),
          shiftInput: NormalizedBool(value: false),
        );
        expect(inputs.inputFor('rpm'), const NormalizedDouble(0.42));
        expect(inputs.inputFor('redline'), const NormalizedBool(value: true));
        expect(inputs.inputFor('shift'), const NormalizedBool(value: false));
        expect(inputs.inputFor('bogus'), isNull);
      },
    );

    test('equal when every field matches', () {
      const a = TachometerInputs(
        rpmInput: NormalizedDouble(0.5),
        redlineInput: NormalizedBool(value: false),
        shiftInput: NormalizedBool(value: false),
        missingBindings: {'rpm'},
      );
      const b = TachometerInputs(
        rpmInput: NormalizedDouble(0.5),
        redlineInput: NormalizedBool(value: false),
        shiftInput: NormalizedBool(value: false),
        missingBindings: {'rpm'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('hasMissingBindings reflects the set', () {
      const a = TachometerInputs(missingBindings: {'rpm'});
      const b = TachometerInputs();
      expect(a.hasMissingBindings, isTrue);
      expect(b.hasMissingBindings, isFalse);
    });

    test('toString surfaces every field for debugging', () {
      const inputs = TachometerInputs(
        rpmInput: NormalizedDouble(0.1),
        missingBindings: {'redline'},
      );
      final s = inputs.toString();
      expect(s, contains('rpm'));
      expect(s, contains('redline'));
      expect(s, contains('shift'));
      expect(s, contains('missing'));
    });

    test('unequal when missingBindings differ', () {
      const a = TachometerInputs(missingBindings: {'rpm'});
      const b = TachometerInputs(missingBindings: {'shift'});
      expect(a, isNot(equals(b)));
    });

    test('unequal when a per-input field differs', () {
      const a = TachometerInputs(rpmInput: NormalizedDouble(0.1));
      const b = TachometerInputs(rpmInput: NormalizedDouble(0.2));
      expect(a, isNot(equals(b)));
    });
  });
}
