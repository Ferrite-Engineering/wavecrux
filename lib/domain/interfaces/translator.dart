// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Domain layer — ZERO Flutter imports.
import 'package:crux_license/crux_license_core.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/translation_result.dart';

/// The inputs a [Translator] needs to render one raw signal value.
///
/// Mirrors the parameter list of the legacy `ValueFormatService.format`
/// (raw bit-string + bit width + [DisplayFormat] selector + per-signal config),
/// packaged as a value object so translators beyond the built-in one can
/// receive the same context without growing the call signature.
@immutable
class TranslationRequest {
  const TranslationRequest({
    required this.rawValue,
    required this.bitWidth,
    required this.format,
    this.config,
  });

  /// Raw VCD/wellen bit-string (e.g. `"0101xxzz"`, `"b1010"`) or real/analog
  /// literal (e.g. `"3.14"`). Empty string is passed through verbatim.
  final String rawValue;

  /// The signal's declared bit width. `0` for real/analog signals where width
  /// is not meaningful.
  final int bitWidth;

  /// The built-in format selector. The built-in translator switches on this;
  /// declarative / Pro translators may ignore it.
  final DisplayFormat format;

  /// The per-signal translator configuration map (`SignalEntry.translatorConfig`).
  /// Required by some built-in formats (`fixedPointQ`, `namedEnum`) and by
  /// declarative translators; ignored by the rest.
  final Map<String, Object?>? config;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationRequest &&
          rawValue == other.rawValue &&
          bitWidth == other.bitWidth &&
          format == other.format &&
          _configEquals(config, other.config);

  @override
  int get hashCode => Object.hash(
    rawValue,
    bitWidth,
    format,
    config == null
        ? null
        : Object.hashAllUnordered(
            config!.entries.map((e) => Object.hash(e.key, e.value)),
          ),
  );

  @override
  String toString() =>
      'TranslationRequest(rawValue: $rawValue, '
      'bitWidth: $bitWidth, format: $format, config: $config)';
}

bool _configEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

/// A value translator: turns one raw signal value into a [TranslationResult].
///
/// The built-in translator (`builtin.valueFormat`) wraps `ValueFormatService`
/// and is always registered. Declarative (Stage 1) and curated Pro (Stage 2)
/// translators register additional implementations through the
/// `TranslatorRegistry` extension point.
abstract interface class Translator {
  /// Stable, unique identifier — e.g. `'builtin.valueFormat'`. Used as the
  /// registry key and persisted as the per-signal translator binding.
  String get id;

  /// Translate [request] into a structured [TranslationResult].
  TranslationResult translate(TranslationRequest request);
}

/// Optional capability for a [Translator] that decomposes a value into a
/// **statically-countable** number of expandable child (subfield) rows.
///
/// The value column reserves child-row geometry *before* rendering — the
/// waveform canvas and signal-names list must reserve the identical vertical
/// span so subfields never drift off their wave — so the row count has to be
/// derivable from the per-signal config alone, without a cursor value. A
/// translator whose subfield count varies per value (e.g. instruction
/// disassembly, where the operand count depends on the opcode) does **not**
/// implement this and renders inline instead.
///
/// The returned count must equal the number of [TranslationResult.fields] the
/// translator produces for a well-formed value of that config; for x/z or
/// fall-back values the value column pads the reserved rows with blanks, so a
/// stable count keeps the three columns aligned.
///
/// Extends [Translator] so a `Translator?` resolved from the registry can be
/// promoted with `is ChildRowTranslator` (Dart only promotes to a subtype of
/// the current type).
abstract interface class ChildRowTranslator implements Translator {
  /// The number of child rows this translator reserves for [config], or `0`
  /// when it produces none for that config.
  int childRowCount(Map<String, Object?>? config);
}

/// Optional capability for a [Translator] sold at a tier above Open Core.
///
/// The bind dialog's presets carry a tier and gate *binding*, but a binding
/// also arrives without the dialog: a session restore puts back every
/// signal's `translatorConfig`, and the Pro overlay registers its translators
/// at every tier. So the tier belongs to the translator itself, and
/// `translatorRegistryProvider` registers one only on a seat whose tier
/// includes it. On any other seat it is recorded as *withheld*, which the
/// value column shows beside the plain value it falls back to, rather than
/// falling back without a word.
///
/// A translator that does not implement this is Open Core, and is registered
/// at every tier.
abstract interface class TierGatedTranslator implements Translator {
  /// The tier this translator needs: [LicenseTier.pro] or
  /// [LicenseTier.enterprise].
  LicenseTier get requiredTier;
}
