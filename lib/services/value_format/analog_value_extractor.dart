// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart'
    show kTranslatorIdConfigKey;
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

/// Turns one raw signal value into a number the analog renderer can plot.
///
/// [double.nan] means "no value here" and is drawn as a gap in the trace, not
/// as zero.
typedef AnalogValueExtractor = double Function(String rawValue);

/// Config key under which a signal records the translator bound to it.
///
/// Mirrors the key the value column reads; duplicated as a private constant
/// would drift, so it is imported from the registry.
const String _translatorIdKey = kTranslatorIdConfigKey;

/// Builders for the [AnalogValueExtractor] the analog painter uses.
///
/// There are exactly two, and the distinction is the whole feature:
///
/// * [real] — the signal's values *are* numbers already (VCD `real`,
///   `realtime`, SystemVerilog `shortreal`). This is what WaveCrux has always
///   done and remains the default, so nothing about existing analog lanes
///   changes.
/// * [forDigitalLane] — the signal is a digital bus that the user has asked to
///   see drawn as a curve. Its bits become a number through the lane's own
///   numeric interpretation, so a Q4.12 lane plots 1.5 where a hex lane plots
///   6144 for the identical bits. That is the correct behaviour: the format
///   answers "what number is this", the analog toggle answers "draw it how".
///
/// **Seam note.** A Pro translator (bf16, FP8, the pixel formats) reaches this
/// renderer through [Translator.translate] and nothing else — [forDigitalLane]
/// reads the resulting [TranslationResult.text] and parses it as a decimal
/// number. Open core never learns what bf16 is. If a future change here starts
/// wanting to know, that is the signal the extractor is being wired at the
/// wrong layer.
abstract final class AnalogValueExtractors {
  const AnalogValueExtractors._();

  /// The historical extractor: parse a real literal, NaN for `x`/`z` and for
  /// anything unparseable.
  static double real(String rawValue) {
    final s = rawValue.trim().toLowerCase();
    if (s.isEmpty || s == 'x' || s == 'z' || s == 'nan') return double.nan;
    return double.tryParse(s) ?? double.nan;
  }

  /// Builds the extractor for a digital lane rendered as analog.
  ///
  /// [format] and [config] are the lane's own display settings; [registry]
  /// resolves a bound non-built-in translator, falling back to the built-in
  /// numeric reading when there is none or when the translator's text is not a
  /// decimal number (a named-enum label, say, or a pixel swatch).
  static AnalogValueExtractor forDigitalLane({
    required int bitWidth,
    required DisplayFormat format,
    Map<String, Object?>? config,
    TranslatorRegistry? registry,
    ValueFormatService formatter = const ValueFormatService(),
  }) {
    final translatorId = config?[_translatorIdKey] as String?;

    // No custom translator: the built-in numeric reading is the whole answer,
    // and skipping the registry keeps the common path allocation-free.
    if (translatorId == null || translatorId == TranslatorRegistry.builtinId) {
      return (raw) => formatter.numericValue(raw, bitWidth, format, config);
    }

    final resolved = (registry ?? TranslatorRegistry.instance).get(
      translatorId,
    );
    if (resolved == null) {
      return (raw) => formatter.numericValue(raw, bitWidth, format, config);
    }

    return (raw) {
      if (raw.isEmpty) return double.nan;
      final TranslationResult result;
      try {
        result = resolved.translate(
          TranslationRequest(
            rawValue: raw,
            bitWidth: bitWidth,
            format: format,
            config: config,
          ),
        );
      } on Object {
        // A translator that throws must not take the canvas down with it. Fall
        // back to the built-in reading, the same as an unresolvable id.
        return formatter.numericValue(raw, bitWidth, format, config);
      }
      final parsed = parseTranslatedText(result.text);
      if (parsed != null) return parsed;
      // Not a decimal number — a label, a colour name, a bit-field summary.
      // The bus still has a magnitude, so plot that rather than a gap.
      return formatter.numericValue(raw, bitWidth, format, config);
    };
  }

  /// Parses the decimal text a translator produced, or null when it is not a
  /// number.
  ///
  /// Deliberately strict about what counts. `double.tryParse` accepts
  /// `"Infinity"`, `"NaN"` and leading `+`, and the built-in formatters emit
  /// `"X"` / `"Z"` for unknown values and a Unicode minus (U+2212) for negative
  /// sign-magnitude — all of which have to be handled here rather than
  /// surprising the renderer.
  static double? parseTranslatedText(String text) {
    var s = text.trim();
    if (s.isEmpty) return null;
    // The sign-magnitude formatter emits U+2212 MINUS SIGN, which
    // double.tryParse does not accept.
    s = s.replaceAll('−', '-');
    final upper = s.toUpperCase();
    if (upper == 'X' || upper == 'Z' || upper == 'NAN') return double.nan;
    if (upper == '+INF' || upper == 'INF') return double.infinity;
    if (upper == '-INF') return double.negativeInfinity;
    final parsed = double.tryParse(s);
    if (parsed == null) return null;
    // `double.tryParse('Infinity')` succeeds; a translator emitting that word
    // is describing a value, not naming a magnitude we should scale an axis to.
    if (!parsed.isFinite) return null;
    return parsed;
  }
}
