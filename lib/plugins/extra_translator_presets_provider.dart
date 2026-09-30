// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/plugins/translator_preset.dart';

/// Open-core extension point through which the Pro overlay contributes
/// ready-made translator presets to the value-column "Custom translator…"
/// dialog ([BindCustomTranslatorDialog]).
///
/// The open-core default returns an empty list — open core ships only the
/// hard-wired RISC-V disassembly entry plus the user's authored bit-field
/// translators. The Pro overlay's `proOverrides` replaces this provider with
/// one that returns the curated Pro translator pack (AMBA
/// control-word expanders, extended/ML floats, pixel formats). Each preset
/// carries its own tier gate and binding builder — see [TranslatorPreset].
///
/// This is a *discovery* seam, distinct from the *registration* seam
/// (`extraTranslatorsProvider`, which inserts the actual [Translator]
/// implementations into the [TranslatorRegistry]). A Pro pack overrides both:
/// the registry provider so the translator resolves at render time, and this
/// provider so the user can find and bind it.
final extraTranslatorPresetsProvider = Provider<List<TranslatorPreset>>(
  (_) => const [],
);
