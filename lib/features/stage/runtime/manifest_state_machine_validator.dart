// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/runtime/custom_stage_widget_runtime_descriptor.dart';
import 'package:wavecrux/features/stage/runtime/rive_state_machine_host.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';

/// Outcome of cross-checking a [StageWidgetManifest]'s required signal
/// bindings against the named inputs declared by a live Rive state
/// machine (as exposed by a [RiveStateMachineHost]).
///
/// Two terminal states:
///
/// - [ManifestHostValidationOk] — every required binding maps to a
///   host input. The renderer can safely begin pushing samples.
/// - [ManifestHostValidationMismatch] — at least one required binding
///   is missing from the host. The renderer surfaces the
///   "Widget failed to load" placeholder; the bundled
///   [StageWidgetRuntimeException] is ready to drop straight into the
///   error-state path.
///
/// Pure value types — no Rive, no Flutter imports — testable with a
/// fake [RiveStateMachineHost].
@immutable
sealed class ManifestHostValidationResult {
  const ManifestHostValidationResult();
}

/// Success outcome from [validateManifestAgainstHost].
@immutable
final class ManifestHostValidationOk extends ManifestHostValidationResult {
  const ManifestHostValidationOk();
}

/// Failure outcome from [validateManifestAgainstHost]. The renderer
/// uses [exception] verbatim to populate its load-error state.
@immutable
final class ManifestHostValidationMismatch
    extends ManifestHostValidationResult {
  const ManifestHostValidationMismatch({
    required this.missingBindingName,
    required this.exception,
  });

  /// Name of the first required binding whose declaration is missing
  /// from the host.
  final String missingBindingName;

  /// Pre-built [StageWidgetRuntimeException] tagged
  /// [StageWidgetRuntimeFailureKind.inputUndeclared] with a developer
  /// diagnostic mentioning both the binding name and the host's state
  /// machine name.
  final StageWidgetRuntimeException exception;
}

/// Cross-checks each required binding on [manifest] against the named
/// inputs exposed by [host]. Returns the first failure (matching the
/// renderer's pre-refactor short-circuit semantics) or
/// [ManifestHostValidationOk] when every required binding maps.
///
/// Non-required bindings are not checked — they are advisory only per
/// the manifest schema's `required: true|false` knob.
///
/// This function does not consult input *types* — a number-vs-boolean
/// mismatch surfaces later at write time as a
/// [SetInputResultKind.typeMismatch]. The renderer treats the missing-
/// input case as fatal at construction time because the input cannot
/// be cached at all; type mismatches are recoverable.
ManifestHostValidationResult validateManifestAgainstHost({
  required StageWidgetManifest manifest,
  required RiveStateMachineHost host,
}) {
  for (final binding in manifest.signalBindings) {
    if (!binding.required) continue;
    if (!host.hasInput(binding.name)) {
      return ManifestHostValidationMismatch(
        missingBindingName: binding.name,
        exception: StageWidgetRuntimeException(
          userMessageKey: StageWidgetRuntimeFailureKind.inputUndeclared,
          diagnostic:
              'Manifest "${manifest.id}" declares required input '
              '"${binding.name}" but state machine '
              '"${host.stateMachineName}" does not expose it.',
        ),
      );
    }
  }
  return const ManifestHostValidationOk();
}
