// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/license/tier_unlocked_provider.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/settings/settings_service.dart';
import 'package:wavecrux/services/value_format/bitfield_translator.dart';
import 'package:wavecrux/services/value_format/builtin_value_translator.dart';
import 'package:wavecrux/services/value_format/riscv_disasm_translator.dart';

part 'translator_registry.g.dart';

/// Registry of value [Translator]s (mirrors `DecoderRegistry`).
///
/// Every registry is seeded with the built-in translator
/// ([BuiltinValueTranslator], id `builtin.valueFormat`) so [resolve] always has
/// a fallback. Additional translators — the Stage 1 declarative tier and the
/// curated Pro pack (Stage 2) — register themselves on top.
///
/// Most consumers obtain the registry through [translatorRegistryProvider],
/// which builds it from the built-in set plus the overridable
/// [extraTranslatorsProvider]. Non-Riverpod code (painters) may use the
/// process-wide [instance].
class TranslatorRegistry {
  /// Creates a registry seeded with the always-present stateless translators:
  /// the built-in flat formatter ([BuiltinValueTranslator]) and the declarative
  /// [BitfieldTranslator] (config-driven, so a single instance serves every
  /// bitfield-bound signal). Translators needing async assets (the RISC-V
  /// disassembler) are added by [translatorRegistryProvider].
  TranslatorRegistry() {
    register(const BuiltinValueTranslator());
    register(const BitfieldTranslator());
  }

  /// Creates an empty registry — for tests that need to assert without the
  /// built-in seeded. Production code uses the default constructor.
  @visibleForTesting
  TranslatorRegistry.empty();

  /// Process-wide registry for non-Riverpod consumers. Riverpod code should
  /// prefer [translatorRegistryProvider] so Pro overrides are honored.
  static final TranslatorRegistry instance = TranslatorRegistry();

  /// Registry id of the always-present built-in translator.
  static const String builtinId = BuiltinValueTranslator.translatorId;

  final Map<String, Translator> _translators = {};
  final Map<String, LicenseTier> _withheld = {};

  /// Registers [translator], replacing any existing one with the same
  /// [Translator.id].
  void register(Translator translator) {
    _translators[translator.id] = translator;
    _withheld.remove(translator.id);
  }

  /// Records that the translator [id] is part of this build but not
  /// available to this seat, which lacks [requiredTier]. The translator itself
  /// is not registered.
  ///
  /// So a withheld id resolves as an unknown one does: [resolve] falls back to
  /// the built-in translator (or to whatever is already registered under
  /// [id], if the withheld translator would have replaced it). The record is
  /// what tells the two apart, so the value column can say that the value it
  /// shows stands in for a translator the licence does not include (see
  /// [TierGatedTranslator]).
  void withhold(String id, LicenseTier requiredTier) {
    _withheld[id] = requiredTier;
  }

  /// The tier the translator [id] needs, when this build has it and this seat
  /// may not use it; `null` for a translator that resolves, and for one the
  /// build does not have.
  LicenseTier? withheldTier(String id) => _withheld[id];

  /// Returns the translator registered under [id], or `null` if none.
  Translator? get(String id) => _translators[id];

  /// Returns `true` when a translator with [id] is registered.
  bool isRegistered(String id) => _translators.containsKey(id);

  /// Removes the translator with [id]. Returns `true` when one was removed.
  bool unregister(String id) => _translators.remove(id) != null;

  /// Every registered translator, ordered by id for determinism.
  List<Translator> get translators =>
      _translators.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  /// Resolves a translator by [id], falling back to the built-in translator
  /// when [id] is `null` or unregistered. Never returns `null`.
  Translator resolve([String? id]) =>
      (id != null ? _translators[id] : null) ?? _translators[builtinId]!;

  /// Convenience: resolve [translatorId] (built-in fallback) and translate
  /// [request] in one call.
  TranslationResult translate(
    TranslationRequest request, {
    String? translatorId,
  }) => resolve(translatorId).translate(request);

  /// Removes all registrations — intended for tests only.
  @visibleForTesting
  void clear() {
    _translators.clear();
    _withheld.clear();
  }
}

/// Extra translators contributed on top of the built-in set.
///
/// Defaults to an empty list in open-core. **The Pro pack overrides this
/// provider** (via `proOverrides` at the root `ProviderScope`) to contribute
/// its curated translators — this is the single seam through which Stage 2
/// translators enter the registry. Keep the override surface here stable.
@riverpod
List<Translator> extraTranslators(Ref ref) => const [];

/// The shared RISC-V [InstructionDisassembler], built once from the bundled
/// instruction-set TOML corpus (RV32I/RV64I + M/A/F/D/C). Async because the
/// TOML assets load from the root bundle. Reused by the
/// [RiscvDisasmTranslator]; the heavy parse happens once per process.
@riverpod
Future<InstructionDisassembler> riscvDisassembler(Ref ref) async {
  // Same user tables the decoder composes, so the translator and the decoder
  // cannot disagree about what a word disassembles to.
  final assets = await IsaDecoderAssets.loadFromBundle(
    userTableDirectories: await peekIsaTableDirectories(),
  );
  final sets = assets.availableSets
      .map(assets.get)
      .whereType<InstructionSet>()
      .toList();
  return InstructionDisassembler(sets);
}

/// The RISC-V instruction-disassembly translator, or `null` while the
/// disassembler assets are still loading. [translatorRegistryProvider]
/// registers it once it resolves.
@riverpod
RiscvDisasmTranslator? riscvDisasmTranslator(Ref ref) {
  final disasm = ref.watch(riscvDisassemblerProvider).asData?.value;
  return disasm == null ? null : RiscvDisasmTranslator(disasm);
}

/// The app-wide [TranslatorRegistry], built from the built-in translator plus
/// every translator from [extraTranslatorsProvider].
///
/// Rebuilds when [extraTranslatorsProvider] changes (e.g. a Pro override is
/// applied). Watch this from providers/widgets; pass the resolved registry (or
/// a resolved [Translator]) into painters and other non-Riverpod code.
///
/// **A contributed translator is registered only where its tier allows.** The
/// Pro overlay contributes its pack at every tier, and a session restore puts
/// back every signal's binding without passing the bind dialog's gate. So a
/// [TierGatedTranslator] whose tier this seat lacks is recorded with
/// [TranslatorRegistry.withhold] instead: its binding stays on the signal, the
/// value renders through the built-in fallback, and the value column says why.
/// The tier is watched, so a licence change rebuilds the registry and every
/// value that resolves through it, in either direction, without a restart.
@riverpod
TranslatorRegistry translatorRegistry(Ref ref) {
  final registry = TranslatorRegistry();
  // Open-core RISC-V disassembly translator (added once its assets resolve).
  final riscv = ref.watch(riscvDisasmTranslatorProvider);
  if (riscv != null) registry.register(riscv);
  // Pro pack (Stage 2) and any other contributed translators win last.
  for (final translator in ref.watch(extraTranslatorsProvider)) {
    final requiredTier = translator is TierGatedTranslator
        ? translator.requiredTier
        : LicenseTier.openCore;
    if (ref.watch(tierUnlockedProvider(requiredTier))) {
      registry.register(translator);
    } else {
      registry.withhold(translator.id, requiredTier);
    }
  }
  return registry;
}
