// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/auto_bind_result.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/decoders/decoder_auto_bind_service.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Result of a preview dialog interaction.
///
/// `null` from the [showDialog] return value means the user cancelled. A
/// non-null instance carries the bindings the user chose to apply, ready
/// to be merged into the parent [DecoderConfigDialog]'s `_bindings` map.
@immutable
class DecoderAutoBindPreviewOutcome {
  const DecoderAutoBindPreviewOutcome({
    required this.appliedBindings,
    this.appliedPaths = const {},
  });

  /// `name → signalRef` pairs the user accepted. Only non-null entries are
  /// returned — bindings that the user did not apply are absent so the
  /// caller can preserve any existing manual bindings for those names.
  final Map<String, String> appliedBindings;

  /// `name → fullPath` of the signal name each applied binding matched on,
  /// for the entries of [appliedBindings] that came from a name match. An
  /// aliased signal has several names for one signalRef; this keeps the one
  /// the match was made on.
  final Map<String, String> appliedPaths;
}

/// Modal preview of the [DecoderAutoBindService] result with per-binding
/// confidence chips, an ambiguous-prefix banner with disambiguation
/// dropdown, and Apply-confirmed-only / Apply-all action buttons.
///
/// The dialog renders the same single-column scrollable list at every
/// device class — wider on desktop (560 dp) and edge-to-edge on phone.
/// All sizing reads from [MobileMetrics] so the row height and chip text
/// scale to a touch-friendly 44 dp on phone/tablet.
class DecoderAutoBindPreviewDialog extends ConsumerStatefulWidget {
  const DecoderAutoBindPreviewDialog({
    required this.definition,
    required this.availableSignals,
    required this.currentParameters,
    required this.existingBindings,
    this.service = const DecoderAutoBindService(),
    super.key,
  });

  final DecoderDefinition definition;
  final Map<String, Variable> availableSignals;
  final Map<String, dynamic> currentParameters;
  final Map<String, String?> existingBindings;
  final DecoderAutoBindService service;

  /// Convenience launcher returning the user's chosen bindings, or `null`
  /// if they cancelled.
  static Future<DecoderAutoBindPreviewOutcome?> show(
    BuildContext context, {
    required DecoderDefinition definition,
    required Map<String, Variable> availableSignals,
    required Map<String, dynamic> currentParameters,
    required Map<String, String?> existingBindings,
    DecoderAutoBindService service = const DecoderAutoBindService(),
  }) {
    return showDialog<DecoderAutoBindPreviewOutcome>(
      context: context,
      builder: (context) => DecoderAutoBindPreviewDialog(
        definition: definition,
        availableSignals: availableSignals,
        currentParameters: currentParameters,
        existingBindings: existingBindings,
        service: service,
      ),
    );
  }

  @override
  ConsumerState<DecoderAutoBindPreviewDialog> createState() =>
      _DecoderAutoBindPreviewDialogState();
}

class _DecoderAutoBindPreviewDialogState
    extends ConsumerState<DecoderAutoBindPreviewDialog> {
  late AutoBindResult _result;
  String? _selectedPrefix;

  @override
  void initState() {
    super.initState();
    _result = _compute();
  }

  AutoBindResult _compute() {
    return widget.service.computeBindings(
      definition: widget.definition,
      availableSignals: widget.availableSignals,
      currentParameters: widget.currentParameters,
      existingBindings: widget.existingBindings,
      forcedPrefix: _selectedPrefix,
    );
  }

  void _setForcedPrefix(String? prefix) {
    setState(() {
      _selectedPrefix = prefix;
      _result = _compute();
    });
  }

  void _applyAll() {
    _apply((candidate) => candidate.signalRef != null);
  }

  void _applyConfirmedOnly() {
    _apply(
      (candidate) =>
          candidate.signalRef != null &&
          candidate.confidence != AutoBindConfidence.fuzzyMatch &&
          candidate.confidence != AutoBindConfidence.noMatch,
    );
  }

  void _apply(bool Function(AutoBindCandidate candidate) accept) {
    final accepted = {
      for (final entry in _result.candidates.entries)
        if (accept(entry.value)) entry.key: entry.value,
    };
    Navigator.of(context).pop(
      DecoderAutoBindPreviewOutcome(
        appliedBindings: {
          for (final entry in accepted.entries)
            entry.key: entry.value.signalRef!,
        },
        appliedPaths: {
          for (final entry in accepted.entries)
            if (entry.value.fullPath != null) entry.key: entry.value.fullPath!,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final theme = Theme.of(context);
    final def = widget.definition;

    final allBindings = <SignalBinding>[
      ...def.requiredSignals,
      ...def.optionalSignals,
    ];
    final requiredNames = {for (final b in def.requiredSignals) b.name};

    final exactCount = _result.candidates.values
        .where(
          (c) =>
              c.confidence == AutoBindConfidence.exactSuffix ||
              c.confidence == AutoBindConfidence.caseInsensitive ||
              c.confidence == AutoBindConfidence.knownAlias,
        )
        .length;
    final fuzzyCount = _result.candidates.values
        .where((c) => c.confidence == AutoBindConfidence.fuzzyMatch)
        .length;
    final unmatchedCount = _result.candidates.values
        .where((c) => c.confidence == AutoBindConfidence.noMatch)
        .length;

    return AlertDialog(
      title: Text(l10n.decoderAutoBindPreviewTitle(def.displayName)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_result.hasAmbiguity)
                _AmbiguousPrefixBanner(
                  prefixes: _result.ambiguousPrefixes,
                  selected: _selectedPrefix ?? _result.detectedPrefix,
                  onSelected: _setForcedPrefix,
                  metrics: metrics,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.decoderAutoBindSummary(
                      exactCount,
                      fuzzyCount,
                      unmatchedCount,
                      _result.candidates.length,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: metrics.bodyText,
                    ),
                  ),
                ),
              const Divider(),
              for (final binding in allBindings)
                _BindingPreviewRow(
                  binding: binding,
                  isRequired: requiredNames.contains(binding.name),
                  candidate: _result.candidates[binding.name],
                  signalMap: widget.availableSignals,
                  metrics: metrics,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.decoderAutoBindCancelButton),
        ),
        TextButton(
          onPressed: _applyConfirmedOnly,
          child: Text(l10n.decoderAutoBindApplyConfirmedOnlyButton),
        ),
        FilledButton(
          onPressed: _applyAll,
          child: Text(l10n.decoderAutoBindApplyAllButton),
        ),
      ],
    );
  }
}

// ── ambiguous-prefix banner ──────────────────────────────────────────────────

class _AmbiguousPrefixBanner extends StatelessWidget {
  const _AmbiguousPrefixBanner({
    required this.prefixes,
    required this.selected,
    required this.onSelected,
    required this.metrics,
  });

  final List<String> prefixes;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final MobileMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: metrics.iconSize,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.decoderAutoBindAmbiguousBanner,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontSize: metrics.bodyText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                l10n.decoderAutoBindPrefixDropdownLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontSize: metrics.labelText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  value: selected != null && prefixes.contains(selected)
                      ? selected
                      : prefixes.first,
                  isExpanded: true,
                  items: prefixes
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p,
                          child: Text(
                            p,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: onSelected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── per-binding preview row ──────────────────────────────────────────────────

class _BindingPreviewRow extends StatelessWidget {
  const _BindingPreviewRow({
    required this.binding,
    required this.isRequired,
    required this.candidate,
    required this.signalMap,
    required this.metrics,
  });

  final SignalBinding binding;
  final bool isRequired;
  final AutoBindCandidate? candidate;
  final Map<String, Variable> signalMap;
  final MobileMetrics metrics;

  /// A name for [signalRef] when the candidate carries none (a manual binding
  /// passed through). [signalMap] may be keyed by path or by reference, so
  /// this searches its values.
  String _pathForRef(String signalRef) {
    final direct = signalMap[signalRef];
    if (direct != null && direct.signalRef == signalRef) {
      return direct.fullPath;
    }
    for (final v in signalMap.values) {
      if (v.signalRef == signalRef) return v.fullPath;
    }
    return signalRef;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final signalRef = candidate?.signalRef;
    final resolvedPath = signalRef == null
        ? l10n.decoderAutoBindNoMatchPlaceholder
        : (candidate?.fullPath ?? _pathForRef(signalRef));

    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.isTouch ? 8 : 4),
      child: Row(
        children: [
          // ── binding name + required/optional badge ──────────────────────
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        binding.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: metrics.monoText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _RequiredOptionalBadge(
                      isRequired: isRequired,
                      label: isRequired
                          ? l10n.decoderAutoBindRequiredBadge
                          : l10n.decoderAutoBindOptionalBadge,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── resolved signal path ────────────────────────────────────────
          Expanded(
            child: Tooltip(
              message: candidate?.matchReason ?? '',
              triggerMode: TooltipTriggerMode.manual,
              child: Text(
                resolvedPath,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: metrics.monoText,
                  color: signalRef == null
                      ? scheme.onSurface.withValues(alpha: 0.6)
                      : scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── confidence chip ─────────────────────────────────────────────
          _ConfidenceChip(
            confidence: candidate?.confidence ?? AutoBindConfidence.noMatch,
            metrics: metrics,
          ),
        ],
      ),
    );
  }
}

class _RequiredOptionalBadge extends StatelessWidget {
  const _RequiredOptionalBadge({
    required this.isRequired,
    required this.label,
  });

  final bool isRequired;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isRequired ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final fg = isRequired ? scheme.onErrorContainer : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: fg),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({
    required this.confidence,
    required this.metrics,
  });

  final AutoBindConfidence confidence;
  final MobileMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (label, bg, fg, icon) = switch (confidence) {
      AutoBindConfidence.exactSuffix || AutoBindConfidence.caseInsensitive => (
        l10n.decoderAutoBindConfidenceExact,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      AutoBindConfidence.knownAlias => (
        l10n.decoderAutoBindConfidenceAlias,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.swap_horiz,
      ),
      AutoBindConfidence.fuzzyMatch => (
        l10n.decoderAutoBindConfidenceFuzzy,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.help_outline,
      ),
      AutoBindConfidence.noMatch => (
        l10n.decoderAutoBindConfidenceNoMatch,
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.cancel_outlined,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: metrics.labelText,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
