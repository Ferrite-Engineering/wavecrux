// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/value_validity.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

/// The default built-in [Translator] (`id = 'builtin.valueFormat'`).
///
/// A thin adapter over [ValueFormatService]: it delegates the [TranslationResult.text]
/// to `ValueFormatService.format` unchanged (so every [DisplayFormat] renders
/// byte-for-byte identically to the pre-registry call sites), returns no
/// structured [TranslationResult.fields], and surfaces the x/z state of the raw
/// value as [TranslationResult.validity].
///
/// [ValueFormatService] remains the formatting engine and is intentionally left
/// untouched — this class only lifts its output into the structured result type.
class BuiltinValueTranslator implements Translator {
  const BuiltinValueTranslator();

  /// Stable registry id for the built-in translator.
  static const String translatorId = 'builtin.valueFormat';

  static const ValueFormatService _service = ValueFormatService();

  @override
  String get id => translatorId;

  @override
  TranslationResult translate(TranslationRequest request) {
    final text = _service.format(
      request.rawValue,
      request.bitWidth,
      request.format,
      request.config,
    );
    return TranslationResult(
      text: text,
      validity: _validityOf(request.rawValue),
    );
  }

  /// Derives [ValueValidity] from the raw bit-string, matching the established
  /// x/z detection convention used by `SignalValue` (lowercase substring scan).
  static ValueValidity _validityOf(String rawValue) {
    final lower = rawValue.toLowerCase();
    if (lower.contains('x')) return ValueValidity.hasX;
    if (lower.contains('z')) return ValueValidity.hasZ;
    return ValueValidity.ok;
  }
}
