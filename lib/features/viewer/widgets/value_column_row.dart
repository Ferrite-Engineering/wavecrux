// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart' show showCruxInfoSnack;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/translator_expansion_provider.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/widgets/bind_custom_translator_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/translator_child_row.dart';
import 'package:wavecrux/features/viewer/widgets/value_color_swatch.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/extra_translator_presets_provider.dart';
import 'package:wavecrux/plugins/translator_preset.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/named_enum_editor_dialog.dart';
import 'package:wavecrux/shared/widgets/platform_context_menu.dart';
import 'package:wavecrux/shared/widgets/q_format_config_dialog.dart';
import 'package:wavecrux/shared/widgets/wavecrux_withheld_notice.dart';

// Sentinel values for non-format context-menu actions.
const _kAssignFilter = 'assign_filter';
const _kRemoveFilter = 'remove_filter';
const _kConfigureFormat = 'configure_format';
const _kOpenFormatMenu = 'open_format_menu';
const _kEditEnumLabels = 'edit_enum_labels';
const _kToggleRenderAsAnalog = 'toggle_render_as_analog';
const _kBindCustomTranslator = 'bind_custom_translator';
const _kClearCustomTranslator = 'clear_custom_translator';
const _kSelectSignal = 'select_signal';

// Basic formats shown above the "Advanced" divider.
const List<DisplayFormat> _kBasicFormats = [
  DisplayFormat.binary,
  DisplayFormat.hexadecimal,
  DisplayFormat.octal,
  DisplayFormat.unsignedDecimal,
  DisplayFormat.signedDecimal,
  DisplayFormat.ascii,
];

// Advanced formats shown below the "Advanced" divider.
const List<DisplayFormat> _kAdvancedFormats = [
  DisplayFormat.ieee754Single,
  DisplayFormat.ieee754Double,
  DisplayFormat.fixedPointQ,
  DisplayFormat.signedMagnitude,
  DisplayFormat.grayCode,
  DisplayFormat.namedEnum,
];

/// A single row in the [ValueColumnPanel].
///
/// For [SignalEntryKind.signal] entries, shows the formatted value at the
/// current cursor time. Tap copies the value to clipboard. Right-click opens
/// a context menu for changing the [DisplayFormat].
///
/// Group, separator, and comment entries render blank placeholder rows at the
/// correct height to maintain vertical alignment with [SignalListPanel] and
/// [WaveformCanvas].
class ValueColumnRow extends ConsumerWidget {
  const ValueColumnRow({
    required this.entry,
    required this.signalValue,
    this.childRows = 0,
    super.key,
  });

  /// The entry this row represents.
  final SignalEntry entry;

  /// The resolved value for signal entries, or null when unloaded / not a signal.
  final SignalValue? signalValue;

  /// Number of translator child (subfield) rows reserved within this row's
  /// height (from the shared [LaneGeometry]). `0` when collapsed. When `> 0`
  /// the signal row renders that many child rows below the parent value.
  final int childRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every row's height comes from the shared [LaneGeometry] model so this
    // column can't drift out of alignment with the signal-names list and the
    // waveform canvas. The model clamps a signal row's stored laneHeight up to
    // LaneMetrics.minLaneHeight at render time only (store raw, render
    // clamped), and renders group/separator/comment rows at their fixed
    // structural heights on every device class (bumping them to the 44 dp
    // touch floor would misalign the columns).
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final laneMetrics = LaneMetrics(minLaneHeight: metrics.minLaneHeight);
    // The parent value occupies a base lane; child rows are reserved below it.
    final baseHeight = LaneGeometry.heightForEntry(entry, laneMetrics);
    final height = LaneGeometry.heightForEntry(
      entry,
      laneMetrics,
      childRows: childRows,
    );
    return switch (entry.kind) {
      SignalEntryKind.signal => _buildSignalRow(
        context,
        ref,
        metrics,
        baseHeight,
        height,
      ),
      SignalEntryKind.group => _buildGroupRow(context, height),
      SignalEntryKind.separator => SizedBox(height: height),
      SignalEntryKind.comment => _buildCommentRow(context, height),
    };
  }

  // ── signal row ──────────────────────────────────────────────────────────────

  Widget _buildSignalRow(
    BuildContext context,
    WidgetRef ref,
    MobileMetrics metrics,
    double height,
    double totalHeight,
  ) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final value = signalValue;
    final displayText = value?.formatted ?? '—';
    final isFiltered = value?.isFiltered ?? false;

    // Selection highlight — a signal row is "selected" when its signalPath
    // (hierarchy row identity — the selection set is keyed by fullPath, not
    // signalRef, because FST aliasing maps many rows onto one ref) is in
    // `selectedVariablesProvider` (the same set the Signal Tree leaf
    // highlights and the AI Assistant's getSelectionContext reads). We tint
    // with the theme's primary at low opacity, mirroring VariableTreeLeaf so
    // the two panels agree on what "selected" looks like.
    final signalRef = entry.signalRef;
    final signalPath = entry.signalPath;
    final isSelected =
        signalPath != null &&
        ref.watch(selectedVariablesProvider).contains(signalPath);
    final selectionTint = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.18)
        : null;

    final Color textColor;
    if (value == null) {
      textColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    } else if (value.hasX) {
      textColor = WavecruxColors.xValue;
    } else if (value.hasZ) {
      textColor = Theme.of(context).extension<WavecruxColorExtension>()!.zValue;
    } else {
      textColor = theme.colorScheme.onSurface;
    }

    final fields = value?.fields ?? const <TranslatedField>[];
    // The chevron shows only when the bound translator reserves a static
    // number of child rows (a [ChildRowTranslator] with count > 0) — *not*
    // merely because the value produced fields. An inline-only translator
    // like RISC-V disassembly produces operand fields but reserves no rows,
    // so it must not render a dead chevron. The capacity is config-driven
    // (expansion-independent), unlike `childRows` which is the reserved count
    // only while expanded.
    final registry = ref.watch(translatorRegistryProvider);
    final childRowCapacity = translatorChildRowCount(
      registry,
      entry.translatorConfig,
    );
    // A binding to a translator this seat's tier does not include (a Pro
    // translator a restored session bound during the beta) resolves to the
    // built-in formatter, so the value shown is the plain one. Say so beside
    // it, rather than let the binding look as if it had silently broken.
    final boundId = entry.translatorConfig?[kTranslatorIdConfigKey];
    final withheldTier = boundId is String
        ? registry.withheldTier(boundId)
        : null;
    final expandable = childRowCapacity > 0;
    // childRows is non-zero only when the row is expanded (geometry reflects
    // the expansion-state provider), so it doubles as the "is expanded" flag.
    final expanded = childRows > 0;

    final parentCell = Container(
      height: height,
      color: selectionTint,
      // Issue 14: Row's default CrossAxisAlignment.center gives the value
      // column's containing widget loose vertical constraints, so the
      // Padding + Align combination ended up sized to the Text's intrinsic
      // height and the centering had no effect. SizedBox.expand inside the
      // GestureDetector forces the Align to span the full lane height so
      // Alignment.centerLeft vertically centers the value against the lane.
      child: Row(
        children: [
          // Colour swatch for translators that emit a colour hint (the
          // packed-pixel pack). Decorative — the value text keeps the gestures.
          if (value?.colorArgb != null) ...[
            const SizedBox(width: 8),
            ValueColorSwatch(colorArgb: value!.colorArgb!),
          ],
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Ctrl/Cmd-click toggles this signal's selection (mirroring the
              // Signal Tree leaf's modifier branch); a plain tap keeps copying
              // the value. The modifier is checked inside onTap so the inner
              // detector does not claim any new gesture — the outer
              // PlatformContextMenu's long-press path is untouched.
              onTap: (signalRef != null || value != null)
                  ? () => _handleValueTap(ref, signalPath, l10n, context, value)
                  : null,
              // Visual centering nudge: see signal_list_panel.dart for the full
              // rationale. The user's diagnostic-build screenshot confirmed
              // the 2 dp shift was too subtle to perceive; 5 dp is the
              // empirical sweet spot — clearly visible at small lane heights
              // without pushing the value out of even the 16 dp minimum lane
              // on touch. Must stay in sync with the signal-list-row Transform
              // so the name on the left and the value on the right sit at the
              // same vertical position in their shared row.
              child: Transform.translate(
                offset: const Offset(0, 5),
                child: SizedBox.expand(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        // Font metric tuning to visually center the painted
                        // glyph at the lane's vertical middle. See
                        // signal_list_panel.dart for the full rationale.
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false,
                          applyHeightToLastDescent: false,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                        strutStyle: const StrutStyle(
                          forceStrutHeight: true,
                          height: 1,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                        style: TextStyle(
                          fontFamily: WavecruxColors.monoFontFamily,
                          fontFamilyFallback:
                              WavecruxColors.monoFontFamilyFallback,
                          fontSize: 12,
                          color: textColor,
                          // Italic distinguishes translated labels from raw
                          // numeric formats so users know a filter is active.
                          fontStyle: isFiltered
                              ? FontStyle.italic
                              : FontStyle.normal,
                          height: 1,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (withheldTier != null)
            WaveCruxWithheldNotice(
              featureLabel:
                  presetForBinding(
                    ref.watch(extraTranslatorPresetsProvider),
                    entry.translatorConfig!,
                  )?.labelResolver(context) ??
                  '$boundId',
              requiredTier: withheldTier,
              // The bind dialog's id: the same presets, reached through a
              // restore instead of the dialog.
              gateFeatureId: 'translator_preset',
              layout: WithheldNoticeLayout.chip,
            ),
          if (expandable)
            _ExpandTranslatorAffordance(
              expanded: expanded,
              size: metrics.touchTarget,
              tooltip: expanded
                  ? l10n.translatorCollapseFields
                  : l10n.translatorExpandFields,
              onTap: () => ref
                  .read(expandedTranslatorRowsProvider.notifier)
                  .toggle(entry.id),
            ),
        ],
      ),
    );

    return PlatformContextMenu(
      onContextMenu: (pos) => _showContextMenu(context, ref, l10n, pos),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          parentCell,
          if (expanded)
            for (var i = 0; i < childRows; i++)
              TranslatorChildRow(
                field: i < fields.length ? fields[i] : null,
                height: kChildRowHeight,
                hasX: value?.hasX ?? false,
                hasZ: value?.hasZ ?? false,
              ),
        ],
      ),
    );
  }

  /// Handles a plain tap on the value cell. Ctrl/Cmd held → toggle this
  /// signal's selection (mirrors [VariableTreeLeaf]); otherwise copy the value.
  void _handleValueTap(
    WidgetRef ref,
    String? signalPath,
    L10N l10n,
    BuildContext context,
    SignalValue? value,
  ) {
    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl && signalPath != null) {
      ref.read(selectedVariablesProvider.notifier).toggle(signalPath);
      return;
    }
    if (value != null) {
      _copyValue(context, l10n, value.formatted);
    }
  }

  void _copyValue(BuildContext context, L10N l10n, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    showCruxInfoSnack(context, l10n.valueColumnCopied);
  }

  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
    Offset position,
  ) async {
    final rect = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    );

    final signalRef = entry.signalRef;
    final hasFilter =
        signalRef != null &&
        ref.read(translateFilterProvider).containsKey(signalRef);

    final items = <PopupMenuEntry<Object?>>[
      // Select Signal — the touch-input equivalent of Ctrl/Cmd-clicking the
      // row. Toggles this signal's membership in `selectedVariablesProvider`
      // (keyed by signalPath — row identity).
      // Only meaningful for a real signal (signalRef != null).
      if (signalRef != null && entry.signalPath != null) ...[
        PopupMenuItem<Object?>(
          value: _kSelectSignal,
          height: 32,
          child: Text(
            l10n.valueColumnSelectSignal,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const PopupMenuDivider(),
      ],
      // Format opens a nested menu rather than listing all 12 formats inline:
      // showMenu does not scroll on desktop, so an inline format list pushed
      // the translator entries below the window's bottom edge (issue #40).
      PopupMenuItem<Object?>(
        value: _kOpenFormatMenu,
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.valueColumnFormatHeader,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text(
              _formatLabel(l10n, entry.format),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<Object?>(
        value: _kConfigureFormat,
        enabled: entry.format == DisplayFormat.fixedPointQ,
        height: 32,
        child: Text(
          l10n.valueColumnConfigureFormat,
          style: TextStyle(
            fontSize: 13,
            color: entry.format == DisplayFormat.fixedPointQ
                ? null
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
      PopupMenuItem<Object?>(
        value: _kEditEnumLabels,
        enabled: entry.format == DisplayFormat.namedEnum,
        height: 32,
        child: Text(
          l10n.valueColumnEditEnumLabels,
          style: TextStyle(
            fontSize: 13,
            color: entry.format == DisplayFormat.namedEnum
                ? null
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
      PopupMenuItem<Object?>(
        value: _kToggleRenderAsAnalog,
        height: 32,
        child: Text(
          entry.renderAsAnalog
              ? l10n.valueColumnRenderAsDigital
              : l10n.valueColumnRenderAsAnalog,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<Object?>(
        value: _kBindCustomTranslator,
        height: 32,
        child: Text(
          l10n.valueColumnBindCustomTranslator,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      if (entry.translatorConfig?.containsKey(kTranslatorIdConfigKey) ?? false)
        PopupMenuItem<Object?>(
          value: _kClearCustomTranslator,
          height: 32,
          child: Text(
            l10n.valueColumnClearCustomTranslator,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<Object?>(
        enabled: signalValue != null,
        height: 32,
        onTap: signalValue != null
            ? () => Clipboard.setData(
                ClipboardData(text: signalValue!.formatted),
              )
            : null,
        child: Text(
          l10n.valueColumnCopyValue,
          style: TextStyle(
            fontSize: 13,
            color: signalValue != null
                ? null
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<Object?>(
        value: _kAssignFilter,
        height: 32,
        child: Text(
          l10n.translateFilterAssign,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      if (hasFilter)
        PopupMenuItem<Object?>(
          value: _kRemoveFilter,
          height: 32,
          child: Text(
            l10n.translateFilterRemove,
            style: const TextStyle(fontSize: 13),
          ),
        ),
    ];

    final selected = await showMenu<Object?>(
      context: context,
      position: rect,
      items: items,
    );

    if (!context.mounted) return;

    if (selected == _kSelectSignal && entry.signalPath != null) {
      ref.read(selectedVariablesProvider.notifier).toggle(entry.signalPath!);
    } else if (selected == _kOpenFormatMenu) {
      await _showFormatMenu(context, ref, l10n, rect);
    } else if (selected == _kConfigureFormat && signalRef != null) {
      await _openConfigureDialog(context, ref, l10n, signalRef);
    } else if (selected == _kEditEnumLabels && signalRef != null) {
      await _openEnumLabelsDialog(context, ref, l10n, signalRef);
    } else if (selected == _kAssignFilter && signalRef != null) {
      await _assignTranslateFilter(context, ref, l10n, signalRef);
    } else if (selected == _kRemoveFilter && signalRef != null) {
      ref.read(translateFilterProvider.notifier).removeFilter(signalRef);
    } else if (selected == _kToggleRenderAsAnalog) {
      ref
          .read(signalGroupsProvider.notifier)
          .setSignalRenderAsAnalog(
            entry.id,
            renderAsAnalog: !entry.renderAsAnalog,
          );
    } else if (selected == _kBindCustomTranslator && signalRef != null) {
      await _bindCustomTranslator(context, ref, signalRef);
    } else if (selected == _kClearCustomTranslator && signalRef != null) {
      // Clears the binding *and* resets the row's format to the default, so a
      // non-default format set before the translator was bound doesn't leave
      // the value still looking translated. See issue #41.
      ref
          .read(signalGroupsProvider.notifier)
          .clearSignalTranslatorById(entry.id);
    }
  }

  Future<void> _bindCustomTranslator(
    BuildContext context,
    WidgetRef ref,
    String signalRef,
  ) async {
    final config = await BindCustomTranslatorDialog.show(context);
    if (!context.mounted || config == null) return;
    ref
        .read(signalGroupsProvider.notifier)
        .setSignalTranslatorConfigById(entry.id, config);
  }

  Future<void> _openConfigureDialog(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
    String signalRef,
  ) async {
    final current = entry.translatorConfig;
    final updated = await QFormatConfigDialog.show(context, config: current);
    if (!context.mounted || updated == null) return;
    ref
        .read(signalGroupsProvider.notifier)
        .setSignalTranslatorConfigById(entry.id, updated);
  }

  Future<void> _openEnumLabelsDialog(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
    String signalRef,
  ) async {
    final current = entry.translatorConfig;
    final updated = await NamedEnumEditorDialog.show(context, config: current);
    if (!context.mounted || updated == null) return;
    ref
        .read(signalGroupsProvider.notifier)
        .setSignalTranslatorConfigById(entry.id, updated);
  }

  Future<void> _assignTranslateFilter(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
    String signalRef,
  ) async {
    if (ref.read(systemDialogInFlightProvider)) return;
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: l10n.translateFilterPickerTitle,
      );
    } finally {
      inFlight.end();
    }
    if (!context.mounted) return;
    final path = result?.files.firstOrNull?.path;
    if (path != null) {
      await ref
          .read(translateFilterProvider.notifier)
          .assignFilter(signalRef, path);
    }
  }

  // ── group / comment rows ────────────────────────────────────────────────────

  Widget _buildGroupRow(BuildContext context, double height) {
    final groupBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    final labelColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: groupBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              entry.groupName ?? '',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: WavecruxColors.monoFontFamily,
                fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentRow(BuildContext context, double height) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            entry.text ?? '',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the nested display-format picker as a second [showMenu] at [rect]
  /// (the original right-click position). Split out of the main context menu so
  /// the top-level menu stays short enough to fit the window without scrolling
  /// (issue #40); this format-only menu fits within the 500 dp minimum window
  /// height. Applies the chosen format per-row via [setSignalFormatById].
  Future<void> _showFormatMenu(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
    RelativeRect rect,
  ) async {
    final items = <PopupMenuEntry<Object?>>[
      PopupMenuItem<Object?>(
        enabled: false,
        height: 28,
        child: Text(
          l10n.valueColumnFormatHeader,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      ..._kBasicFormats.map((fmt) => _formatMenuItem(context, l10n, fmt)),
      PopupMenuItem<Object?>(
        enabled: false,
        height: 24,
        child: Text(
          l10n.settingsAdvancedSection,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      ..._kAdvancedFormats.map((fmt) => _formatMenuItem(context, l10n, fmt)),
    ];

    final selected = await showMenu<Object?>(
      context: context,
      position: rect,
      items: items,
    );
    if (!context.mounted) return;
    if (selected is DisplayFormat) {
      ref
          .read(signalGroupsProvider.notifier)
          .setSignalFormatById(entry.id, selected);
      // Recorded here rather than in the notifier because the notifier's two
      // setters are also the bulk path, which would emit one event per selected
      // signal for one keypress. A dismissed menu (`selected == null`) is an
      // attempt and stays uncounted.
      ref
          .read(telemetryServiceProvider)
          .record(
            TelemetryEvent(
              'format.set',
              properties: <String, Object?>{
                'format': telemetryEnumToken(selected),
              },
            ),
          );
    }
  }

  PopupMenuItem<Object?> _formatMenuItem(
    BuildContext context,
    L10N l10n,
    DisplayFormat fmt,
  ) => PopupMenuItem<Object?>(
    value: fmt,
    height: 32,
    child: Row(
      children: [
        SizedBox(
          width: 18,
          child: fmt == entry.format ? const Icon(Icons.check, size: 14) : null,
        ),
        const SizedBox(width: 4),
        Text(_formatLabel(l10n, fmt), style: const TextStyle(fontSize: 13)),
      ],
    ),
  );

  String _formatLabel(L10N l10n, DisplayFormat fmt) => switch (fmt) {
    DisplayFormat.binary => l10n.displayFormatBinary,
    DisplayFormat.hexadecimal => l10n.displayFormatHexadecimal,
    DisplayFormat.octal => l10n.displayFormatOctal,
    DisplayFormat.unsignedDecimal => l10n.displayFormatUnsignedDecimal,
    DisplayFormat.signedDecimal => l10n.displayFormatSignedDecimal,
    DisplayFormat.ascii => l10n.displayFormatAscii,
    DisplayFormat.ieee754Single => l10n.displayFormatIeee754Single,
    DisplayFormat.ieee754Double => l10n.displayFormatIeee754Double,
    DisplayFormat.fixedPointQ => l10n.displayFormatFixedPointQ,
    DisplayFormat.signedMagnitude => l10n.displayFormatSignedMagnitude,
    DisplayFormat.grayCode => l10n.displayFormatGrayCode,
    DisplayFormat.namedEnum => l10n.displayFormatNamedEnum,
  };
}

/// The expand/collapse chevron for a translator-bound value row.
///
/// The visible chevron is small, but the tappable [GestureDetector] is sized to
/// [size] × full-row-height so the hit target meets the 44 × 44 dp touch floor
/// on touch device classes (`MobileMetrics.touchTarget` is 44 on touch, where
/// the parent lane is itself ≥ 44 dp tall). The tooltip uses manual trigger
/// mode so its long-press recognizer never beats the row's
/// `PlatformContextMenu`.
class _ExpandTranslatorAffordance extends StatelessWidget {
  const _ExpandTranslatorAffordance({
    required this.expanded,
    required this.size,
    required this.tooltip,
    required this.onTap,
  });

  final bool expanded;
  final double size;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(
        key: const ValueKey('translator_expand_affordance'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: double.infinity,
          child: Icon(
            expanded ? Icons.expand_more : Icons.chevron_right,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
