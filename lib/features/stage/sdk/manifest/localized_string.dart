// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A user-facing string that may either be a single language or a per-
/// locale map.
///
/// Manifest authors can write either:
///
/// ```yaml
/// display_name: "PWM Analyzer"
/// ```
///
/// or:
///
/// ```yaml
/// display_name:
///   en: "PWM Analyzer"
///   zh_CN: "PWM 分析仪"
///   ja: "PWM アナライザ"
///   ko: "PWM 분석기"
/// ```
///
/// At resolve time the runtime asks for the active app locale; the value
/// falls back to `en` and then to the first declared key when an exact
/// match is missing — matching the four-locale rule in
/// `wavecrux/CLAUDE.md` ("`app_zh.arb` mirrors `app_zh_CN.arb`").
@immutable
class LocalizedString {
  /// Construct from a single string (treated as `en` only).
  const LocalizedString.single(String value)
    : _entries = const <String, String>{},
      _singleValue = value;

  /// Construct from a map of locale code → translated string.
  ///
  /// At least one entry is required; the constructor panics on an empty
  /// map because that produces a string that resolves to nothing.
  LocalizedString.localized(Map<String, String> entries)
    : assert(entries.isNotEmpty, 'localized map must have at least 1 entry'),
      _entries = Map<String, String>.unmodifiable(entries),
      _singleValue = null;

  final Map<String, String> _entries;
  final String? _singleValue;

  /// True when this string was constructed via [LocalizedString.single].
  bool get isSingle => _singleValue != null;

  /// Returns the locale → text map. Empty for [isSingle] strings.
  Map<String, String> get entries => _entries;

  /// Returns the single string value, or null if this was constructed
  /// via [LocalizedString.localized].
  String? get singleValue => _singleValue;

  /// Resolves the best-match string for [localeCode].
  ///
  /// Resolution order:
  /// 1. [LocalizedString.single] always returns its single value.
  /// 2. Exact key match on [_entries].
  /// 3. Language-code prefix (e.g. `zh_CN` requested, `zh` available).
  /// 4. `en` fallback.
  /// 5. First declared entry (insertion order).
  ///
  /// Throws [StateError] only if [_entries] is somehow empty (impossible
  /// by construction — both factories enforce non-empty input).
  String resolve(String localeCode) {
    if (_singleValue != null) return _singleValue;
    if (_entries.isEmpty) {
      throw StateError('LocalizedString has no entries to resolve');
    }
    final exact = _entries[localeCode];
    if (exact != null) return exact;
    // Language-code prefix: `zh_CN` → try `zh`.
    final underscore = localeCode.indexOf('_');
    if (underscore > 0) {
      final base = localeCode.substring(0, underscore);
      final baseMatch = _entries[base];
      if (baseMatch != null) return baseMatch;
    }
    final en = _entries['en'];
    if (en != null) return en;
    return _entries.values.first;
  }

  /// Serialises back to either a string or a map for round-trip output.
  Object toYamlValue() {
    if (_singleValue != null) return _singleValue;
    return Map<String, String>.from(_entries);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LocalizedString) return false;
    if (_singleValue != other._singleValue) return false;
    if (_entries.length != other._entries.length) return false;
    for (final key in _entries.keys) {
      if (_entries[key] != other._entries[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(_singleValue, _entries.length);

  @override
  String toString() {
    if (_singleValue != null) return 'LocalizedString.single($_singleValue)';
    return 'LocalizedString.localized($_entries)';
  }
}
