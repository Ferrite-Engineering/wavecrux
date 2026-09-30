// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/domain/models/translation_result.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/value_format/builtin_value_translator.dart';

/// Instruction-disassembly [Translator] (`id = 'builtin.riscvDisasm'`).
///
/// Wraps the open-core [InstructionDisassembler] so an
/// instruction-bus signal can be rendered as disassembled text inline in the
/// value column (`addi x1, x0, 5`) — a different surface from the
/// transaction-overlay RISC-V *decoder*. Mnemonic + operands are also surfaced
/// as [TranslationResult.fields].
///
/// **Open Core, never Pro-gated.** RISC-V stays open per the RISC-V decoder
/// decision; instruction disassembly carries no tier badge or feature gate.
///
/// The encoding is never re-derived here: this is a thin adapter over the
/// existing disassembler. When the disassembler is unavailable (assets still
/// loading) or no instruction matches, it falls back to the flat built-in hex
/// format so the value column never goes blank.
class RiscvDisasmTranslator implements Translator {
  const RiscvDisasmTranslator(this._disassembler);

  /// Stable registry id.
  static const String translatorId = 'builtin.riscvDisasm';

  static const BuiltinValueTranslator _builtin = BuiltinValueTranslator();

  final InstructionDisassembler _disassembler;

  @override
  String get id => translatorId;

  @override
  TranslationResult translate(TranslationRequest request) {
    final width = request.bitWidth;
    if (width <= 0) return _builtin.translate(request);

    final bits = _normalizeBits(request.rawValue, width);
    if (_isNonBitString(bits) || bits.contains('x') || bits.contains('z')) {
      return _builtin.translate(request);
    }

    final instr = int.tryParse(bits, radix: 2);
    if (instr == null) return _builtin.translate(request);

    // RV32/RV64 share 32-bit encoding; RVC occupies the low 16 bits of a
    // 32-bit container per the *-lower instruction sets, exactly as the
    // open-core RISC-V decoder samples it.
    const instructionBitWidth = 32;
    final disasm = _disassembler.decode(instr, instructionBitWidth);
    if (disasm == null) return _builtin.translate(request);

    return TranslationResult(
      text: disasm.text,
      fields: _operandFields(disasm, width),
    );
  }

  /// Splits the disassembly into a mnemonic field plus one field per operand.
  ///
  /// The bit ranges are coarse (the whole instruction word) — operand-level bit
  /// extents are not exposed by the disassembler, and RISC-V disassembly is
  /// rendered inline rather than as geometry-expanded child lanes.
  List<TranslatedField> _operandFields(
    DisassembledInstruction disasm,
    int width,
  ) {
    final hi = width - 1;
    final fields = <TranslatedField>[
      TranslatedField(
        name: 'mnemonic',
        text: disasm.mnemonic,
        hiBit: hi,
        loBit: 0,
      ),
    ];
    final spaceIdx = disasm.text.indexOf(' ');
    if (spaceIdx >= 0 && spaceIdx + 1 < disasm.text.length) {
      final operandStr = disasm.text.substring(spaceIdx + 1).trim();
      final operands = operandStr
          .split(',')
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty);
      var i = 0;
      for (final op in operands) {
        fields.add(
          TranslatedField(
            name: 'op$i',
            text: op,
            hiBit: hi,
            loBit: 0,
          ),
        );
        i++;
      }
    }
    return fields;
  }

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
}
