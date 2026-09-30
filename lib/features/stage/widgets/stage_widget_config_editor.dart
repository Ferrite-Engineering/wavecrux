// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Resolves a [ConfigParam.labelKey] (or any other ARB key on the schema)
/// to a user-visible string. Pro widgets supply their own resolver that
/// switches on the key and returns the matching `L10NPro.<keyName>`;
/// open-core's default resolver returns the key unchanged so a widget
/// that ships without a resolver still renders something readable
/// (config keys are typically short identifier-style strings like
/// `'fftSize'` that work as fallback labels).
typedef ConfigLabelResolver = String Function(String key);

/// Generic, schema-driven editor for [ConfigParam]s declared on a
/// [StageWidget]. Two-way binds against [StageInstance.configuration]
/// via [StageWorkspaceNotifier.setConfigurationValue] so each user
/// edit produces one minimal state transition.
///
/// The editor groups params by [ConfigParam.groupId] (rendering each
/// group's localized [ConfigParamGroup.labelKey] as a section header),
/// honors [ConfigParam.visibleWhenKey] / `visibleWhenValue` so widgets
/// can hide irrelevant params (e.g., stereo-display when the channel
/// mode is mono), and renders one of four sub-widgets per type:
///
/// - [ConfigParamType.toggle]      → [SwitchListTile]
/// - [ConfigParamType.integer]     → [Slider] when both `min` and `max`
///                                   are set, else a numeric [TextField]
/// - [ConfigParamType.decimal]     → same as integer, parsed as `double`
/// - [ConfigParamType.text]        → [TextField]
/// - [ConfigParamType.enumChoice]  → [DropdownButton]
///
/// Widgets needing bespoke editing UI (palette tables, layout grids)
/// should leave [StageWidget.configParams] empty and supply their own
/// editor — see ARCHITECTURE.md §10 (Pro Overlay Seams).
class StageWidgetConfigEditor extends ConsumerWidget {
  const StageWidgetConfigEditor({
    required this.instance,
    required this.params,
    this.groups = const [],
    this.labelResolver,
    super.key,
  });

  /// Instance whose configuration map the editor binds to.
  final StageInstance instance;

  /// Schema. Sourced from [StageWidget.configParams] of the instance's
  /// widget definition.
  final List<ConfigParam> params;

  /// Optional grouping. Sourced from [StageWidget.configGroups]. Render
  /// order is the declaration order of this list.
  final List<ConfigParamGroup> groups;

  /// Optional ARB resolver for [ConfigParam.labelKey] /
  /// [ConfigParam.descriptionKey] / [ConfigParamGroup.labelKey] /
  /// [ConfigParamChoice.labelKey]. Defaults to `(key) => key` when
  /// omitted.
  final ConfigLabelResolver? labelResolver;

  String _resolve(String key) => labelResolver?.call(key) ?? key;

  /// Returns the live value for [param]: the instance's configuration
  /// entry for [ConfigParam.id] when set, otherwise the schema default.
  Object? _liveValue(ConfigParam param) {
    if (instance.configuration.containsKey(param.id)) {
      return instance.configuration[param.id];
    }
    return param.defaultValue;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (params.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);

    // Filter to visible params, then group.
    final visible = [
      for (final p in params)
        if (p.isVisibleIn(instance.configuration)) p,
    ];
    final byGroup = <String?, List<ConfigParam>>{};
    for (final p in visible) {
      byGroup.putIfAbsent(p.groupId, () => []).add(p);
    }

    // Order: ungrouped params first (groupId == null), then groups in
    // their declaration order.
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (byGroup[null] != null)
          for (final p in byGroup[null]!)
            _buildParamRow(context, ref, p, metrics, theme),
        for (final group in groups) ...[
          if (byGroup[group.id] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                _resolve(group.labelKey),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: metrics.labelText,
                ),
              ),
            ),
            for (final p in byGroup[group.id]!)
              _buildParamRow(context, ref, p, metrics, theme),
          ],
        ],
      ],
    );
  }

  Widget _buildParamRow(
    BuildContext context,
    WidgetRef ref,
    ConfigParam param,
    MobileMetrics metrics,
    ThemeData theme,
  ) {
    final live = _liveValue(param);

    void commit(Object? value) => ref
        .read(stageWorkspaceProvider.notifier)
        .setConfigurationValue(instance.id, param.id, value: value);

    switch (param.type) {
      case ConfigParamType.toggle:
        return _ToggleRow(
          key: ValueKey('configParam:${param.id}'),
          param: param,
          value: (live as bool?) ?? false,
          metrics: metrics,
          resolveLabel: _resolve,
          onChanged: commit,
        );
      case ConfigParamType.enumChoice:
        return _EnumChoiceRow(
          key: ValueKey('configParam:${param.id}'),
          param: param,
          value: live as String?,
          metrics: metrics,
          resolveLabel: _resolve,
          onChanged: commit,
        );
      case ConfigParamType.integer:
      case ConfigParamType.decimal:
        return _NumericRow(
          key: ValueKey('configParam:${param.id}'),
          param: param,
          value: live as num?,
          metrics: metrics,
          resolveLabel: _resolve,
          onChanged: commit,
        );
      case ConfigParamType.text:
        return _TextRow(
          key: ValueKey('configParam:${param.id}'),
          param: param,
          value: live as String?,
          metrics: metrics,
          resolveLabel: _resolve,
          onChanged: commit,
        );
    }
  }
}

// ── Per-type rows ────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.param,
    required this.value,
    required this.metrics,
    required this.resolveLabel,
    required this.onChanged,
    super.key,
  });

  final ConfigParam param;
  final bool value;
  final MobileMetrics metrics;
  final ConfigLabelResolver resolveLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // SwitchListTile builds an internal ListTile, which paints its background
    // and ink splashes on the nearest Material ancestor. The bindings pane
    // that hosts this editor paints its surface with a ColoredBox
    // (`stage_bindings_pane.dart`), which sits *below* the pane's nearest
    // Material — so without a Material of its own the splash is hidden and
    // Flutter's debug assertion "ListTile background color or ink splashes
    // may be invisible" fires on every build.
    //
    // MaterialType.transparency gives the tile its own ink surface without
    // painting a background, so the pane's ColoredBox colour still shows
    // through. This mirrors what the binding rows already do
    // (`stage_bindings_pane.dart`, the Material wrapping their InkWell).
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        title: Text(
          resolveLabel(param.labelKey),
          style: TextStyle(fontSize: metrics.bodyText),
        ),
        subtitle: param.descriptionKey == null
            ? null
            : Text(
                resolveLabel(param.descriptionKey!),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: metrics.labelText,
                ),
              ),
        value: value,
        onChanged: onChanged,
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _EnumChoiceRow extends StatelessWidget {
  const _EnumChoiceRow({
    required this.param,
    required this.value,
    required this.metrics,
    required this.resolveLabel,
    required this.onChanged,
    super.key,
  });

  final ConfigParam param;
  final String? value;
  final MobileMetrics metrics;
  final ConfigLabelResolver resolveLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = param.choices ?? const <ConfigParamChoice>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resolveLabel(param.labelKey),
            style: TextStyle(fontSize: metrics.labelText),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: value,
            // isExpanded forces the dropdown to size to the column width
            // and ellipsize its closed-state selected-value display, rather
            // than sizing to the widest menu item's intrinsic width — which
            // overflows the bindings pane's narrow column when a Pro pack
            // widget has long enum-choice labels (e.g. the orientation
            // widget's "Accelerometer + gyroscope (fusion)"). The full
            // text is still visible when the dropdown is opened.
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: TextStyle(
              fontSize: metrics.bodyText,
              color: theme.colorScheme.onSurface,
            ),
            items: [
              for (final c in choices)
                DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(
                    resolveLabel(c.labelKey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _NumericRow extends StatefulWidget {
  const _NumericRow({
    required this.param,
    required this.value,
    required this.metrics,
    required this.resolveLabel,
    required this.onChanged,
    super.key,
  });

  final ConfigParam param;
  final num? value;
  final MobileMetrics metrics;
  final ConfigLabelResolver resolveLabel;
  final ValueChanged<num?> onChanged;

  @override
  State<_NumericRow> createState() => _NumericRowState();
}

class _NumericRowState extends State<_NumericRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value?.toString() ?? '',
    );
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  /// Commits the field's current text whenever it loses focus — tabbing
  /// to the next field, clicking elsewhere, or any focus traversal — so
  /// a typed value isn't silently discarded when the user doesn't press
  /// Enter. (Previously only `onSubmitted` committed, so tab/blur lost
  /// the edit.)
  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  /// Parses, clamps, and pushes the field's current text. Shared by the
  /// Enter (`onSubmitted`) and focus-loss paths. A blank or unparseable
  /// field is left untouched — no spurious write.
  void _commit() {
    final parsed = _parseRaw(_controller.text);
    if (parsed == null) return;
    final clamped = _clamp(parsed);
    widget.onChanged(_isInt ? clamped.toInt() : clamped.toDouble());
  }

  @override
  void didUpdateWidget(covariant _NumericRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.value?.toString() ?? '';
    if (_controller.text != newText && !_controller.value.composing.isValid) {
      _controller.text = newText;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  num _clamp(num v) {
    if (widget.param.min != null && v < widget.param.min!) {
      return widget.param.min!;
    }
    if (widget.param.max != null && v > widget.param.max!) {
      return widget.param.max!;
    }
    return v;
  }

  bool get _isInt => widget.param.type == ConfigParamType.integer;

  num? _parseRaw(String raw) {
    if (raw.isEmpty) return null;
    if (_isInt) return int.tryParse(raw);
    return double.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final useSlider = widget.param.min != null && widget.param.max != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.resolveLabel(widget.param.labelKey),
                  style: TextStyle(fontSize: widget.metrics.labelText),
                ),
              ),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !_isInt,
                    signed: true,
                  ),
                  inputFormatters: [
                    if (_isInt)
                      FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))
                    else
                      FilteringTextInputFormatter.allow(
                        RegExp(r'-?\d*\.?\d*'),
                      ),
                  ],
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: widget.metrics.monoText),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            ],
          ),
          if (useSlider) ...[
            const SizedBox(height: 4),
            CruxSlider(
              min: widget.param.min!.toDouble(),
              max: widget.param.max!.toDouble(),
              divisions: widget.param.step == null
                  ? null
                  : ((widget.param.max! - widget.param.min!) /
                            widget.param.step!)
                        .round()
                        .clamp(1, 1000),
              value: (widget.value ?? widget.param.min!).toDouble().clamp(
                widget.param.min!.toDouble(),
                widget.param.max!.toDouble(),
              ),
              onChanged: (v) {
                final value = _isInt ? v.round() : v;
                widget.onChanged(value);
                _controller.text = value.toString();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TextRow extends StatefulWidget {
  const _TextRow({
    required this.param,
    required this.value,
    required this.metrics,
    required this.resolveLabel,
    required this.onChanged,
    super.key,
  });

  final ConfigParam param;
  final String? value;
  final MobileMetrics metrics;
  final ConfigLabelResolver resolveLabel;
  final ValueChanged<String> onChanged;

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _TextRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != (widget.value ?? '') &&
        !_controller.value.composing.isValid) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.resolveLabel(widget.param.labelKey),
            style: TextStyle(fontSize: widget.metrics.labelText),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _controller,
            style: TextStyle(fontSize: widget.metrics.bodyText),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onSubmitted: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
