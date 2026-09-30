// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/runtime/generic_manifest_input_mapper.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_parameter.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';

StageWidgetManifest _manifest({
  List<ManifestSignalBinding> bindings = const [],
  List<ManifestParameter> parameters = const [],
}) => StageWidgetManifest(
  id: 'com.acme.gauge',
  version: '1.0.0',
  displayName: const LocalizedString.single('Gauge'),
  category: StageWidgetCategory.instrument,
  runtime: ManifestRuntime.rive,
  runtimeAssetPath: 'runtime/gauge.riv',
  requiredApiVersion: 1,
  signalBindings: bindings,
  parameters: parameters,
);

ManifestSignalBinding _binding(
  String name, {
  SignalType type = SignalType.vector,
  bool required = true,
}) => ManifestSignalBinding(
  name: name,
  description: 'binding $name',
  signalType: type,
  required: required,
);

void main() {
  group('GenericManifestInputMapper.missingRequiredBindings', () {
    test('reports required bindings whose ref is unset/empty', () {
      final mapper = GenericManifestInputMapper(
        manifest: _manifest(
          bindings: [
            _binding('rpm'),
            _binding('redline'),
            _binding('shift', required: false),
          ],
        ),
      );
      final missing = mapper.missingRequiredBindings({
        'rpm': const StageSignalBinding(signalRef: 'top.rpm'),
        'redline': const StageSignalBinding(signalRef: ''),
        // 'shift' absent entirely.
      });
      // redline is required + empty → missing. shift is optional → ignored.
      expect(missing, {'redline'});
    });

    test('returns empty when every required binding is wired', () {
      final mapper = GenericManifestInputMapper(
        manifest: _manifest(bindings: [_binding('rpm'), _binding('redline')]),
      );
      expect(
        mapper.missingRequiredBindings({
          'rpm': const StageSignalBinding(signalRef: 'top.rpm'),
          'redline': const StageSignalBinding(signalRef: 'top.redline'),
        }),
        isEmpty,
      );
    });

    test('optional bindings are never reported even when fully absent', () {
      final mapper = GenericManifestInputMapper(
        manifest: _manifest(
          bindings: [_binding('aux', required: false)],
        ),
      );
      expect(mapper.missingRequiredBindings(const {}), isEmpty);
    });
  });

  group('GenericManifestInputMapper.normalizerFor', () {
    test('resolves the manifest-declared normalizer for a binding', () {
      const norm = LinearNormalizer(inputMin: 0, inputMax: 100);
      final mapper = GenericManifestInputMapper(
        manifest: _manifest(
          bindings: [_binding('rpm')],
          parameters: const [
            ManifestParameter(binding: 'rpm', normalizer: norm),
          ],
        ),
      );
      expect(mapper.normalizerFor('rpm'), same(norm));
      expect(mapper.normalizerFor('other'), isNull);
    });
  });

  group('GenericManifestInputMapper.inputFor', () {
    test('applies the declared normalizer to a value snapshot', () {
      final mapper = GenericManifestInputMapper(
        manifest: _manifest(
          bindings: [_binding('rpm')],
          parameters: const [
            ManifestParameter(
              binding: 'rpm',
              // 8-bit 0..255 → 0.0..1.0.
              normalizer: LinearNormalizer(inputMin: 0, inputMax: 255),
            ),
          ],
        ),
      );
      final value = mapper.inputFor(
        'rpm',
        const StageSignalSnapshot.value(rawValue: '11111111', bitWidth: 8),
        0,
      );
      expect(value, const NormalizedDouble(1));
    });

    test('falls back to defaultNormalize when no normalizer is declared', () {
      final mapper = GenericManifestInputMapper(
        manifest: _manifest(
          bindings: [_binding('led', type: SignalType.scalar)],
        ),
      );
      final value = mapper.inputFor(
        'led',
        const StageSignalSnapshot.value(rawValue: '1', bitWidth: 1),
        0,
      );
      expect(value, const NormalizedBool(value: true));
    });

    test('returns null for a non-value snapshot (hold prior value)', () {
      final mapper = GenericManifestInputMapper(
        manifest: _manifest(bindings: [_binding('rpm')]),
      );
      expect(
        mapper.inputFor('rpm', const StageSignalSnapshot.noFile(), 0),
        isNull,
      );
      expect(
        mapper.inputFor('rpm', const StageSignalSnapshot.unbound(), 0),
        isNull,
      );
    });
  });

  group('GenericManifestInputMapper.snapshotToRawSample', () {
    test('maps a value snapshot to a raw sample with cursor ticks', () {
      final raw = GenericManifestInputMapper.snapshotToRawSample(
        const StageSignalSnapshot.value(rawValue: '1010', bitWidth: 4),
        42,
      );
      expect(
        raw,
        const RawSignalSample(rawValue: '1010', bitWidth: 4, timeTicks: 42),
      );
    });

    test('returns null for non-value snapshots', () {
      expect(
        GenericManifestInputMapper.snapshotToRawSample(
          const StageSignalSnapshot.loading(),
          0,
        ),
        isNull,
      );
    });
  });

  group('GenericManifestInputMapper.defaultNormalize', () {
    test('1-bit scalar → bool', () {
      expect(
        GenericManifestInputMapper.defaultNormalize(
          const RawSignalSample(rawValue: '0', bitWidth: 1),
        ),
        const NormalizedBool(value: false),
      );
    });

    test('wider vector → double (unsigned int)', () {
      expect(
        GenericManifestInputMapper.defaultNormalize(
          const RawSignalSample(rawValue: '1010', bitWidth: 4),
        ),
        const NormalizedDouble(10),
      );
    });

    test('analog → parsed double', () {
      expect(
        GenericManifestInputMapper.defaultNormalize(
          const RawSignalSample(rawValue: '3.5', bitWidth: 0, isAnalog: true),
        ),
        const NormalizedDouble(3.5),
      );
    });

    test('X sample → NormalizedXZ(isX: true)', () {
      expect(
        GenericManifestInputMapper.defaultNormalize(
          const RawSignalSample(rawValue: '10x1', bitWidth: 4),
        ),
        const NormalizedXZ(isX: true),
      );
    });

    test('Z sample → NormalizedXZ(isX: false)', () {
      expect(
        GenericManifestInputMapper.defaultNormalize(
          const RawSignalSample(rawValue: 'zzzz', bitWidth: 4),
        ),
        const NormalizedXZ(isX: false),
      );
    });
  });
}
