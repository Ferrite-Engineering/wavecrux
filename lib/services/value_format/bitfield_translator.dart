// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/value_validity.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/services/value_format/builtin_value_translator.dart';

/// Declarative struct/bitfield [Translator] (`id = 'builtin.bitfield'`).
///
/// Reads a [BitfieldTranslatorConfig] from [TranslationRequest.config] and
/// decomposes the parent bus value into named subfields. Each subfield is a
/// MSB-indexed slice `[hiBit:loBit]` formatted via the built-in translator (so
/// every per-field [DisplayFormat] renders byte-for-byte identically to a flat
/// signal). The returned [TranslationResult.text] is a compact summary
/// (`{valid=1, len=8}`) and [TranslationResult.fields] are the per-field
/// [TranslatedField]s — rendered as expandable child rows in the value column.
///
/// **Silent fallback:** when the config is absent/empty, the parent value is
/// real/analog, or *no* field spec is structurally valid for the parent width,
/// this returns the flat built-in format for [TranslationRequest.format] with no
/// fields — matching the established `namedEnum` fallback behavior. Individual
/// invalid specs render as `X` but still occupy a child row so the row geometry
/// stays in sync.
class BitfieldTranslator implements Translator, ChildRowTranslator {
  const BitfieldTranslator();

  /// Stable registry id.
  static const String translatorId = 'builtin.bitfield';

  static const BuiltinValueTranslator _builtin = BuiltinValueTranslator();

  @override
  String get id => translatorId;

  @override
  int childRowCount(Map<String, Object?>? config) {
    final raw = config?['fields'];
    return raw is List ? raw.length : 0;
  }

  @override
  TranslationResult translate(TranslationRequest request) {
    final config = request.config;
    final width = request.bitWidth;
    // No config or non-vector signal → flat fallback.
    if (config == null || width <= 0) return _builtin.translate(request);

    final bits = _normalizeBits(request.rawValue, width);
    if (_isNonBitString(bits)) return _builtin.translate(request);

    final cfg = BitfieldTranslatorConfig.fromMap(config);
    if (cfg.fields.isEmpty) return _builtin.translate(request);

    // Require at least one structurally valid field; otherwise fall back flat.
    final anyValid = cfg.fields.any((f) => f.isValidFor(width));
    if (!anyValid) return _builtin.translate(request);

    final padded = bits.padLeft(width, '0');
    final fields = <TranslatedField>[];
    final summary = StringBuffer('{');
    var first = true;
    for (final spec in cfg.fields) {
      final field = _translateField(spec, padded, width);
      fields.add(field);
      if (!first) summary.write(', ');
      summary
        ..write(field.name)
        ..write('=')
        ..write(field.text);
      first = false;
    }
    summary.write('}');

    return TranslationResult(
      text: summary.toString(),
      fields: fields,
      validity: _validityOf(bits),
    );
  }

  TranslatedField _translateField(
    BitFieldSpec spec,
    String paddedBits,
    int parentWidth,
  ) {
    if (!spec.isValidFor(parentWidth)) {
      return TranslatedField(
        name: spec.name.isEmpty ? '?' : spec.name,
        text: 'X',
        hiBit: spec.hiBit,
        loBit: spec.loBit,
      );
    }
    // MSB-first string: parent bit p sits at string index (parentWidth-1-p).
    final start = parentWidth - 1 - spec.hiBit;
    final end = parentWidth - 1 - spec.loBit; // inclusive
    final slice = paddedBits.substring(start, end + 1);

    // Nested struct-in-struct: recurse when the sub-config carries `fields`.
    final sub = spec.subConfig;
    if (sub != null && sub.containsKey('fields')) {
      final nested = translate(
        TranslationRequest(
          rawValue: slice,
          bitWidth: spec.width,
          format: spec.format,
          config: sub,
        ),
      );
      return TranslatedField(
        name: spec.name,
        text: nested.text,
        hiBit: spec.hiBit,
        loBit: spec.loBit,
        fields: nested.fields,
      );
    }

    final formatted = _builtin.translate(
      TranslationRequest(
        rawValue: slice,
        bitWidth: spec.width,
        format: spec.format,
        config: sub,
      ),
    );
    return TranslatedField(
      name: spec.name,
      text: formatted.text,
      hiBit: spec.hiBit,
      loBit: spec.loBit,
    );
  }

  // ── helpers (mirror ValueFormatService normalization) ──────────────────────

  static String _normalizeBits(String rawValue, int bitWidth) {
    var s = rawValue.toLowerCase();
    if (s.startsWith('b')) s = s.substring(1);
    if (s.startsWith('r')) s = s.substring(1);
    if (!_isNonBitString(s) && s.length < bitWidth && bitWidth > 0) {
      s = s.padLeft(bitWidth, '0');
    }
    return s;
  }

  static bool _isNonBitString(String s) {
    for (final c in s.runes) {
      if (c != 0x30 && c != 0x31 && c != 0x78 && c != 0x7a) return true;
    }
    return false;
  }

  static ValueValidity _validityOf(String bits) {
    if (bits.contains('x')) return ValueValidity.hasX;
    if (bits.contains('z')) return ValueValidity.hasZ;
    return ValueValidity.ok;
  }
}
