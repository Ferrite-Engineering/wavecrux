// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform/legacy_conversion_controller.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Modal progress dialog shown above the viewer while an LXT/LXT2 → FST
/// convert-on-open pass is running.
///
/// The dialog binds to [legacyConversionControllerProvider] for live progress
/// updates and to its `cancel()` for the Cancel-button action. To avoid a
/// flash on conversions that complete in well under human-perceptible time
/// the host call ([showIfNeeded]) waits [showAfter] before opening the
/// dialog and re-checks whether the conversion is still in progress; sub-250
/// ms conversions therefore never produce a visible dialog. The dialog
/// dismisses itself the moment the controller transitions back to
/// [LegacyConversionState.idle].
class LegacyConversionProgressDialog extends ConsumerWidget {
  const LegacyConversionProgressDialog({super.key});

  /// Default debounce — the dialog is suppressed for conversions that finish
  /// in less than this: a file converting in under 250 ms never flashes a
  /// dialog.
  static const Duration defaultShowAfter = Duration(milliseconds: 250);

  /// Helper used by the open path. Waits [showAfter] (default
  /// [defaultShowAfter]) and then opens the dialog *only if* the controller
  /// still reports `inProgress`. Returns the [Future] that completes when
  /// the dialog closes — caller awaits at most until conversion completes
  /// (the dialog closes itself on idle).
  ///
  /// Safe to fire-and-forget. The host BuildContext is captured at call
  /// time, so call from a viewer-screen scope before `await openFile`.
  static Future<void> showIfNeeded({
    required BuildContext context,
    required WidgetRef ref,
    Duration showAfter = defaultShowAfter,
  }) async {
    await Future<void>.delayed(showAfter);
    if (!context.mounted) return;
    final inProgress = ref.read(legacyConversionControllerProvider).inProgress;
    if (!inProgress) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LegacyConversionProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);

    final state = ref.watch(legacyConversionControllerProvider);

    // Auto-dismiss on idle transition: the open path drives the controller
    // back to idle on success / error / cancel, and the dialog disappears
    // exactly when that happens.
    ref.listen<LegacyConversionState>(
      legacyConversionControllerProvider,
      (previous, next) {
        if (!next.inProgress && (previous?.inProgress ?? false)) {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        }
      },
    );

    final originLabel = _originLabel(state.origin);
    final filename = _basename(state.sourcePath);
    final progress = state.progress;
    final cancelLabel = l10n.lxt2ConversionCancel;

    return AlertDialog(
      title: Text(l10n.lxt2ConversionTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filename != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.lxt2ConversionFile(filename),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            LinearProgressIndicator(
              value: progress == null || progress.total == 0
                  ? null
                  : progress.fraction.clamp(0.0, 1.0),
            ),
            const SizedBox(height: 12),
            Text(l10n.lxt2ConversionStatus(originLabel)),
          ],
        ),
      ),
      actions: [
        // Wrap the Cancel button in a ConstrainedBox so the test that
        // verifies the ≥ 44 dp touch-target compliance has a stable surface
        // to measure (rather than the inner TextButton's text-padded
        // intrinsic size).
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: metrics.touchTarget,
            minHeight: metrics.touchTarget,
          ),
          child: TextButton(
            key: const Key('legacyConversionCancelButton'),
            onPressed: () {
              ref.read(legacyConversionControllerProvider.notifier).cancel();
            },
            child: Text(cancelLabel),
          ),
        ),
      ],
    );
  }

  /// Returns the visible label for an origin format. The acronyms `LXT`
  /// and `LXT2` are not localized — they are file-format identifiers.
  static String _originLabel(WaveformFormat? origin) {
    if (origin == WaveformFormat.lxt) return 'LXT';
    if (origin == WaveformFormat.lxt2) return 'LXT2';
    return '';
  }

  /// Strip directory components from [path] using a manual lastIndexOf on
  /// both separators. Avoids depending on `package:path` from a widget file.
  static String? _basename(String? path) {
    if (path == null || path.isEmpty) return null;
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf(r'\');
    final cut = slash > backslash ? slash : backslash;
    if (cut < 0 || cut + 1 >= path.length) return path;
    return path.substring(cut + 1);
  }
}
