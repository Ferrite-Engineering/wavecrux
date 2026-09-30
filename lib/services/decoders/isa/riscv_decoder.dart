// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// RISC-V instruction-stream decoder. Walks rising clock edges, queries
// the bound `instruction` (and optional `pc`/`valid`) at each edge, and
// emits one [DecodedTransaction] per fetched instruction.
//
// This is the one genuinely RISC-V-specific file in `decoders/isa/`: it owns
// the `riscv` decoder id, the XLEN/extension parameters, and the mapping
// from those parameters onto the RISC-V TOML corpus. Everything else in this
// directory is ISA-neutral.
//
// XLEN and extension selection are expressed by which TOML files are
// bundled into the disassembler — exactly matching JKU's
// `instruction-decoder` model. The user picks XLEN (32/64) and the
// extension toggles (M/A/F/D/C) via [DecoderConfig.parameters]; this
// decoder maps those choices onto the right subset of pre-loaded
// [InstructionSet]s from [IsaDecoderAssets].
//
// The instruction bit-width is always 32: standard RISC-V encoding is
// 32 bits, and RVC instructions occupy the low 16 bits of a 32-bit word
// via the `*-lower.toml` schema variants.

import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/isa_trace_decoder.dart';

/// Public id used in [DecoderRegistry].
const String kRiscvDecoderId = 'riscv';

/// RISC-V instruction-trace decoder.
///
/// Everything architecture-neutral — sampling the fetch clock, the valid
/// strobe, reading instruction and PC words, building transactions — lives in
/// [IsaTraceDecoder]. What is RISC-V about RISC-V is the *composition rule*
/// below: which extension tables to load, in what order, from the user's
/// XLEN and extension parameters.
class RiscvDecoder extends IsaTraceDecoder {
  /// Creates the decoder.
  RiscvDecoder(super.config, super.assets, {super.renderer});

  /// Static metadata. Built once at class load; the bundled assets are
  /// resolved per-instance so the static definition does not depend on
  /// I/O having completed yet.
  static const decoderDefinition = DecoderDefinition(
    id: kRiscvDecoderId,
    displayName: 'RISC-V Instruction Trace',
    description:
        'Disassembles a RISC-V instruction-fetch trace into mnemonics and '
        'operands. RV32I / RV64I plus M/A/F/D/C extensions; cross-tool '
        'compatible with Surfer instruction-decoder TOML files.',
    category: DecoderCategory.instructionTrace,
    requiredSignals: [
      SignalBinding(
        name: 'clk',
        description: 'Instruction-fetch clock — sampled on rising edges.',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'instruction',
        description: 'Fetched 32-bit instruction word.',
        bitWidth: 32,
      ),
    ],
    optionalSignals: [
      SignalBinding(
        name: 'valid',
        description:
            'Fetch-valid strobe (1-bit). When unbound, every rising clock '
            'edge is treated as a valid fetch.',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'pc',
        description: 'Program counter at fetch (XLEN bits).',
      ),
    ],
    parameters: [
      DecoderParameter(
        name: 'xlen',
        displayName: 'XLEN',
        labelKey: 'riscvParamXlen',
        descriptionKey: 'riscvParamXlenDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '32',
        description: 'Register width: 32 or 64 bits.',
        enumValues: ['32', '64'],
      ),
      DecoderParameter(
        name: 'ext_m',
        displayName: 'M (mul / div)',
        labelKey: 'riscvParamExtM',
        descriptionKey: 'riscvParamExtMDescription',
        type: DecoderParameterType.boolean,
        defaultValue: true,
        description: 'Multiply and divide instructions.',
      ),
      DecoderParameter(
        name: 'ext_a',
        displayName: 'A (atomics)',
        labelKey: 'riscvParamExtA',
        descriptionKey: 'riscvParamExtADescription',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'Atomic memory operations (lr/sc/amo*).',
      ),
      DecoderParameter(
        name: 'ext_f',
        displayName: 'F (single-precision FP)',
        labelKey: 'riscvParamExtF',
        descriptionKey: 'riscvParamExtFDescription',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'Single-precision floating-point.',
      ),
      DecoderParameter(
        name: 'ext_d',
        displayName: 'D (double-precision FP, RV64 only)',
        labelKey: 'riscvParamExtD',
        descriptionKey: 'riscvParamExtDDescription',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description:
            'Double-precision floating-point. Available on XLEN=64 only — '
            'matches the JKU bundle. RV32D is out of scope for launch.',
      ),
      DecoderParameter(
        name: 'ext_c',
        displayName: 'C (compressed)',
        labelKey: 'riscvParamExtC',
        descriptionKey: 'riscvParamExtCDescription',
        type: DecoderParameterType.boolean,
        defaultValue: true,
        description: 'Compressed (RVC) 16-bit instructions in low half.',
      ),
    ],
  );

  @override
  DecoderDefinition get definition => RiscvDecoder.decoderDefinition;

  @override
  int get pcHexNibbles => intParam('xlen', 32) == 64 ? 16 : 8;

  // ── ISA composition ───────────────────────────────────────────────────────

  /// Resolves the [DecoderConfig] to the list of [InstructionSet]s that the
  /// disassembler should consult. Order matters: RV32I goes first so that
  /// RV64I's 6-bit-shamt slli/srli/srai (loaded later) wins via "last
  /// match wins" semantics.
  ///
  /// The set names are listed explicitly here rather than derived from
  /// [IsaDecoderAssets.availableSets], so this composition order is
  /// independent of how the assets were discovered. `IsaDecoderAssets` is a
  /// name-keyed cache; the RISC-V composition rule lives with the RISC-V
  /// decoder.
  @override
  List<InstructionSet> resolveInstructionSets() {
    final xlen = int.tryParse(strParam('xlen', '32')) ?? 32;
    final extM = boolParam('ext_m', defaultValue: true);
    final extA = boolParam('ext_a', defaultValue: false);
    final extF = boolParam('ext_f', defaultValue: false);
    final extD = boolParam('ext_d', defaultValue: false);
    final extC = boolParam('ext_c', defaultValue: true);

    final out = <InstructionSet>[];
    void addIfPresent(String name) {
      final s = assets.get(name);
      if (s != null) out.add(s);
    }

    addIfPresent('RV32I');
    if (extM) addIfPresent('RV32M');
    if (extA) addIfPresent('RV32A');
    if (extF) addIfPresent('RV32F');
    if (extC) addIfPresent('RV32C-lower');

    if (xlen == 64) {
      addIfPresent('RV64I');
      if (extM) addIfPresent('RV64M');
      if (extA) addIfPresent('RV64A');
      if (extD) addIfPresent('RV64D');
      if (extC) addIfPresent('RV64C-lower');
    }

    // Any set that is not one of the canonical RISC-V names above is a
    // user-supplied table, and it is appended last.
    //
    // **This is the line that makes bring-your-own-ISA work at all.** Without
    // it a user table was discovered by `IsaDecoderAssets`, listed in the
    // config UI, and then never composed — so it appeared to be installed and
    // decoded nothing, which is the worst of both outcomes. A settings path
    // alone would not have fixed that.
    //
    // Last is the correct position because the disassembler resolves by
    // last-match-wins: a user table describing a custom instruction in an
    // otherwise-RISC-V core must win over the base set it overlaps, which is
    // exactly why someone would author one. Sets are appended in
    // `compareIsaSetNames` order so composition stays deterministic.
    for (final name in assets.availableSets) {
      if (_kCanonicalRiscvSets.contains(name)) continue;
      addIfPresent(name);
    }
    return out;
  }

  /// The set names this decoder composes by rule. Everything else discovered
  /// alongside them is user-supplied.
  static const Set<String> _kCanonicalRiscvSets = <String>{
    'RV32I',
    'RV32M',
    'RV32A',
    'RV32F',
    'RV32C-lower',
    'RV64I',
    'RV64M',
    'RV64A',
    'RV64D',
    'RV64C-lower',
  };
}
