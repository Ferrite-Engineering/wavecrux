// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/runtime/custom_stage_widget_runtime_descriptor.dart';
import 'package:wavecrux/features/stage/runtime/manifest_state_machine_validator.dart';
import 'package:wavecrux/features/stage/runtime/rive_state_machine_host.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';

import '_fakes.dart';

/// Builds a manifest with [bindings] required/optional layout.
StageWidgetManifest _buildManifest(List<ManifestSignalBinding> bindings) {
  return StageWidgetManifest(
    id: 'com.wavecrux.test.validator',
    version: '1.0.0',
    displayName: const LocalizedString.single('Validator Test'),
    category: StageWidgetCategory.instrument,
    runtime: ManifestRuntime.rive,
    runtimeAssetPath: 'runtime/x.riv',
    requiredApiVersion: 1,
    signalBindings: bindings,
  );
}

void main() {
  group('validateManifestAgainstHost', () {
    test('returns Ok when every required binding maps to a host input', () {
      final manifest = _buildManifest(const [
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
      ]);
      final host = FakeRiveHost(
        stateMachineName: 'Tachometer',
        inputs: const {
          'rpm': RiveInputType.number,
          'redline': RiveInputType.boolean,
          'shift': RiveInputType.boolean,
        },
      );
      final result = validateManifestAgainstHost(
        manifest: manifest,
        host: host,
      );
      expect(result, isA<ManifestHostValidationOk>());
    });

    test('returns Mismatch carrying the first missing binding name', () {
      final manifest = _buildManifest(const [
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
      ]);
      final host = FakeRiveHost(
        stateMachineName: 'Tachometer',
        inputs: const {
          'rpm': RiveInputType.number,
          // redline missing
        },
      );
      final result = validateManifestAgainstHost(
        manifest: manifest,
        host: host,
      );
      expect(result, isA<ManifestHostValidationMismatch>());
      final m = result as ManifestHostValidationMismatch;
      expect(m.missingBindingName, 'redline');
      expect(
        m.exception.userMessageKey,
        StageWidgetRuntimeFailureKind.inputUndeclared,
      );
      expect(m.exception.diagnostic, contains('redline'));
      expect(m.exception.diagnostic, contains('Tachometer'));
      expect(m.exception.diagnostic, contains('com.wavecrux.test.validator'));
    });

    test('non-required bindings are skipped — missing optional input is '
        'not a failure', () {
      final manifest = _buildManifest(const [
        ManifestSignalBinding(
          name: 'rpm',
          description: 'rpm',
          signalType: SignalType.vector,
        ),
        ManifestSignalBinding(
          name: 'optional',
          description: 'optional',
          signalType: SignalType.scalar,
          required: false,
        ),
      ]);
      final host = FakeRiveHost(
        stateMachineName: 'Tachometer',
        inputs: const {
          'rpm': RiveInputType.number,
          // 'optional' deliberately missing.
        },
      );
      final result = validateManifestAgainstHost(
        manifest: manifest,
        host: host,
      );
      expect(result, isA<ManifestHostValidationOk>());
    });

    test('returns Ok for an empty signalBindings list', () {
      final manifest = _buildManifest(const []);
      final host = FakeRiveHost(stateMachineName: 'Empty');
      final result = validateManifestAgainstHost(
        manifest: manifest,
        host: host,
      );
      expect(result, isA<ManifestHostValidationOk>());
    });

    test('short-circuits at the first missing required binding — does '
        'not enumerate later mismatches', () {
      final manifest = _buildManifest(const [
        ManifestSignalBinding(
          name: 'a',
          description: 'a',
          signalType: SignalType.vector,
        ),
        ManifestSignalBinding(
          name: 'b',
          description: 'b',
          signalType: SignalType.vector,
        ),
        ManifestSignalBinding(
          name: 'c',
          description: 'c',
          signalType: SignalType.vector,
        ),
      ]);
      // Host has 'b' but not 'a' or 'c'. We expect the first manifest
      // binding to be reported — short-circuit at 'a'.
      final host = FakeRiveHost(
        stateMachineName: 'X',
        inputs: const {'b': RiveInputType.number},
      );
      final result = validateManifestAgainstHost(
        manifest: manifest,
        host: host,
      );
      expect(result, isA<ManifestHostValidationMismatch>());
      expect(
        (result as ManifestHostValidationMismatch).missingBindingName,
        'a',
      );
    });

    test('ignores input type — only checks "input exists by name"', () {
      final manifest = _buildManifest(const [
        ManifestSignalBinding(
          name: 'pin',
          description: 'pin',
          signalType: SignalType.vector,
        ),
      ]);
      // Manifest says vector (number-ish); host declares 'pin' as a
      // trigger. The validator does NOT reject this — type mismatch is
      // a runtime concern, not a validation concern.
      final host = FakeRiveHost(
        stateMachineName: 'X',
        inputs: const {'pin': RiveInputType.trigger},
      );
      final result = validateManifestAgainstHost(
        manifest: manifest,
        host: host,
      );
      expect(result, isA<ManifestHostValidationOk>());
    });

    test('Mismatch exception text identifies the host state-machine name '
        'so developers can correlate', () {
      final manifest = _buildManifest(const [
        ManifestSignalBinding(
          name: 'needle',
          description: 'needle',
          signalType: SignalType.vector,
        ),
      ]);
      final host = FakeRiveHost(stateMachineName: 'CustomSM');
      final result = validateManifestAgainstHost(
        manifest: manifest,
        host: host,
      );
      final mismatch = result as ManifestHostValidationMismatch;
      expect(mismatch.exception.diagnostic, contains('"needle"'));
      expect(mismatch.exception.diagnostic, contains('"CustomSM"'));
    });
  });

  group('ManifestHostValidationOk', () {
    test('is constructible as const', () {
      const ok = ManifestHostValidationOk();
      expect(ok, isA<ManifestHostValidationResult>());
    });
  });
}
