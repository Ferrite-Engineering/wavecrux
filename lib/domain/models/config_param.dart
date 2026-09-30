// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Kind of a [ConfigParam] — drives which sub-widget the generic editor
/// renders for it.
///
/// Pure Dart — no Flutter imports.
enum ConfigParamType {
  /// Integer-valued. Stored as `int` in the configuration map. Renders as
  /// a [Slider] when both [ConfigParam.min] and [ConfigParam.max] are
  /// supplied; otherwise renders as a numeric [TextField].
  integer,

  /// Real-valued. Stored as `double` in the configuration map. Same
  /// rendering rules as [integer].
  decimal,

  /// Boolean toggle. Stored as `bool`. Renders as a [Switch].
  toggle,

  /// Free-form short text. Stored as `String`. Renders as a single-line
  /// [TextField].
  text,

  /// One-of-N selection. Stored as a `String` id from
  /// [ConfigParam.choices]. Renders as a [DropdownButton].
  enumChoice,
}

/// Discrete choice for a [ConfigParamType.enumChoice] parameter.
///
/// [id] is the value stored in the configuration map (always a String).
/// Widget code maps it back to a typed value (an enum, an int, etc.) in
/// `parseConfig`.
///
/// [labelKey] is the ARB key the editor looks up to render the choice.
/// Pure Dart — no Flutter imports.
@immutable
class ConfigParamChoice {
  const ConfigParamChoice({required this.id, required this.labelKey});

  /// Stored value. Round-trips verbatim through the configuration map.
  final String id;

  /// ARB key for the user-visible label. Resolved by the editor at
  /// render time against the active [Locale].
  final String labelKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigParamChoice &&
          id == other.id &&
          labelKey == other.labelKey;

  @override
  int get hashCode => Object.hash(id, labelKey);

  @override
  String toString() => 'ConfigParamChoice(id: $id)';
}

/// One per-instance configuration parameter declared by a [StageWidget].
///
/// The Stage bindings pane and the workspace-tile "Configure…" shortcut
/// render a generic editor that reads the schema from
/// [StageWidget.configParams] and binds it two-way against the instance's
/// `configuration` map. Widgets that need bespoke UI return an empty
/// schema and supply a custom editor instead — see ARCHITECTURE.md §10
/// (Pro Overlay Seams).
///
/// Stored values are scalar (`int` / `double` / `bool` / `String`) so the
/// configuration map is JSON-natural and forward-compatible. Widgets
/// translate the stored values to and from typed payloads
/// ([AudioWaveformConfig], [FramebufferConfig], …) in their own
/// `parseConfig` / `serializeConfig` helpers.
///
/// Pure Dart — no Flutter imports.
@immutable
class ConfigParam {
  const ConfigParam({
    required this.id,
    required this.labelKey,
    required this.type,
    required this.defaultValue,
    this.descriptionKey,
    this.min,
    this.max,
    this.step,
    this.choices,
    this.groupId,
    this.visibleWhenKey,
    this.visibleWhenValue,
    this.visibleWhenValues,
  }) : assert(
         visibleWhenValue == null || visibleWhenValues == null,
         'set at most one of visibleWhenValue / visibleWhenValues',
       );

  /// Key in the instance's `configuration` map. Stable across session
  /// save / load and across version upgrades (renames are migrations).
  final String id;

  /// ARB key for the user-visible label. Resolved at render time.
  final String labelKey;

  /// Optional ARB key for a one-line helper / tooltip rendered next to
  /// the field.
  final String? descriptionKey;

  /// Param kind — drives the renderer.
  final ConfigParamType type;

  /// Default value. Used when the configuration map has no entry for
  /// [id]. The runtime [Object?] type is constrained by [type] —
  /// `int` for [ConfigParamType.integer], `String` (a choice id) for
  /// [ConfigParamType.enumChoice], etc.
  final Object? defaultValue;

  /// Minimum (inclusive) for [ConfigParamType.integer] and
  /// [ConfigParamType.decimal]. When both [min] and [max] are set the
  /// editor renders a [Slider]; otherwise a numeric text field.
  final num? min;

  /// Maximum (inclusive) for [ConfigParamType.integer] and
  /// [ConfigParamType.decimal].
  final num? max;

  /// Slider step for bounded numeric params. Defaults to 1 for
  /// [ConfigParamType.integer] and a sensible auto step for
  /// [ConfigParamType.decimal] when omitted.
  final num? step;

  /// Choices for [ConfigParamType.enumChoice]. Required when [type] is
  /// [ConfigParamType.enumChoice], otherwise null.
  final List<ConfigParamChoice>? choices;

  /// Optional grouping. The editor renders [ConfigParamGroup]s as
  /// section headers and packs all params with that [groupId] under it.
  /// Params without a [groupId] render at the top of the editor.
  final String? groupId;

  /// Conditional visibility: when set, the editor renders this param only
  /// when `instance.configuration[visibleWhenKey]` matches [visibleWhenValue]
  /// (single-value equality) or is a member of [visibleWhenValues]
  /// (OR-of-discrete-values), whichever is supplied.
  ///
  /// Limited but const-friendly — see ARCHITECTURE.md §10. If a widget needs
  /// richer predicates (comparisons, cross-field boolean logic) it should
  /// fall back to a custom editor rather than growing this into an arbitrary
  /// predicate.
  final String? visibleWhenKey;

  /// Visibility comparison value paired with [visibleWhenKey]. Compared
  /// with `==` against the live config value. Mutually exclusive with
  /// [visibleWhenValues] — set at most one.
  final Object? visibleWhenValue;

  /// Visibility comparison set paired with [visibleWhenKey], for a param
  /// that stays visible across more than one (but not all) values of a
  /// multi-choice key — e.g. visible for 2 of 3 `enumChoice` options.
  /// Mutually exclusive with [visibleWhenValue] — set at most one. Still a
  /// const-friendly declarative set (a `Set` literal), not an arbitrary
  /// predicate — see the [visibleWhenKey] doc.
  final Set<Object?>? visibleWhenValues;

  /// Whether [config] currently satisfies this param's visibility
  /// predicate. Returns `true` when no predicate is set.
  bool isVisibleIn(Map<String, Object?> config) {
    if (visibleWhenKey == null) return true;
    final values = visibleWhenValues;
    if (values != null) return values.contains(config[visibleWhenKey]);
    return config[visibleWhenKey] == visibleWhenValue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigParam &&
          id == other.id &&
          labelKey == other.labelKey &&
          descriptionKey == other.descriptionKey &&
          type == other.type &&
          defaultValue == other.defaultValue &&
          min == other.min &&
          max == other.max &&
          step == other.step &&
          _choicesEqual(choices, other.choices) &&
          groupId == other.groupId &&
          visibleWhenKey == other.visibleWhenKey &&
          visibleWhenValue == other.visibleWhenValue &&
          _setEquals(visibleWhenValues, other.visibleWhenValues);

  @override
  int get hashCode => Object.hash(
    id,
    labelKey,
    descriptionKey,
    type,
    defaultValue,
    min,
    max,
    step,
    choices == null ? null : Object.hashAll(choices!),
    groupId,
    visibleWhenKey,
    visibleWhenValue,
    // Order-independent hash so two equal sets built in different insertion
    // orders still hash the same.
    visibleWhenValues?.fold<int>(0, (acc, v) => acc ^ v.hashCode),
  );

  @override
  String toString() => 'ConfigParam(id: $id, type: $type)';

  static bool _choicesEqual(
    List<ConfigParamChoice>? a,
    List<ConfigParamChoice>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _setEquals(Set<Object?>? a, Set<Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

/// Optional named group of [ConfigParam]s. The generic editor renders
/// each group as a section header with the group's localized [labelKey]
/// and packs its params underneath.
///
/// Group [id] is referenced by [ConfigParam.groupId]. The order of
/// entries in [StageWidget.configGroups] is the render order.
///
/// Pure Dart — no Flutter imports.
@immutable
class ConfigParamGroup {
  const ConfigParamGroup({required this.id, required this.labelKey});

  /// Stable group id referenced by [ConfigParam.groupId].
  final String id;

  /// ARB key for the section header.
  final String labelKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigParamGroup && id == other.id && labelKey == other.labelKey;

  @override
  int get hashCode => Object.hash(id, labelKey);

  @override
  String toString() => 'ConfigParamGroup(id: $id)';
}
