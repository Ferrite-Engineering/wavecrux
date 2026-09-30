// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// ISA-neutral disassembler that walks one or more loaded [InstructionSet]s,
// finds the instruction matching a given instruction word, extracts slice
// values, reassembles multi-segment immediates, applies mapping lookups, and
// renders the disassembly via the format's `repr` template.
//
// It takes a bare List<InstructionSet> and knows nothing about any specific
// ISA; the RISC-V-ness lives in the TOML corpus the caller composes.
//
// Behavior matches the JKU `instruction-decoder` Rust crate:
//   • Multiple ISets are searched together; only those whose bit_width
//     equals the caller's bit_width participate.
//   • When more than one instruction matches, the *last* match wins
//     (set load order is the tiebreaker — see `compareIsaSetNames` in
//     isa_decoder_assets.dart, which makes that order deterministic).
//   • Slices tile the instruction word MSB-first in declaration order; each
//     slice's `top`/`bot` name the bit range it occupies in the *assembled
//     part value*, so same-name slices are OR'd in at their own offsets and
//     any value bit no slice claims stays zero. Signed parts sign-extend
//     from the assembled width (`max(top) + 1`).
//   • Per-instruction `unsigned = true` flips VInt parts to unsigned.
//   • `%name%` interpolates a slice value via its part decoder; `$name$`
//     interpolates the matching instruction's name.

import 'package:wavecrux/services/decoders/isa/instruction_set.dart';

/// Result of a successful disassembly.
class DisassembledInstruction {
  const DisassembledInstruction({
    required this.text,
    required this.mnemonic,
    required this.formatName,
    required this.setName,
    this.operands = const <String, int>{},
  });

  /// Full disassembled string, e.g. `"addi t0, t1, 10"`.
  final String text;

  /// Just the mnemonic, e.g. `"addi"`.
  final String mnemonic;

  /// The format that matched (e.g. `"itype_alu"`).
  final String formatName;

  /// The TOML `set` field of the matched InstructionSet.
  final String setName;

  /// Decoded operand values by part name — `{'rd': 5, 'rs1': 0, 'imm': 42}`.
  ///
  /// The renderer computes these to build [text] and used to discard them.
  /// Exposing them costs nothing and is what makes alias rendering possible:
  /// recognizing that `addi rd, x0, 42` should print as `li rd, 42` needs the
  /// *values*, and recovering them by re-parsing [text] would be both fragile
  /// and wrong for any table with a custom `repr`.
  ///
  /// Values are post-interpretation — sign-extended, `extend_top` applied, and
  /// mapped through `[mappings]` where the part declares one — so a consumer
  /// reads the same number the renderer printed.
  final Map<String, int> operands;
}

/// Aggregates one or more [InstructionSet]s and decodes instructions
/// against them.
class InstructionDisassembler {
  InstructionDisassembler(List<InstructionSet> sets)
    : _sets = List.unmodifiable(sets);

  final List<InstructionSet> _sets;

  List<InstructionSet> get sets => _sets;

  /// Disassembles [instruction], where [instructionBitWidth] is the width of
  /// the encoding (32 for standard RISC-V instructions; 16 for native RVC).
  ///
  /// Returns null when no matching instruction is found across all loaded
  /// sets at the given bit width.
  DisassembledInstruction? decode(int instruction, int instructionBitWidth) {
    DisassembledInstruction? lastMatch;
    final mask = instructionBitWidth >= 64
        ? -1
        : (1 << instructionBitWidth) - 1;
    final masked = instruction & mask;
    for (final iset in _sets) {
      if (iset.bitWidth != instructionBitWidth) continue;
      for (final format in iset.formats) {
        for (final insn in format.instructions) {
          if (insn.matches(masked)) {
            final operands = _extractParts(
              type: format.type,
              instruction: masked,
              instructionBitWidth: instructionBitWidth,
              unsignedImm: insn.unsignedImm,
              parts: iset.parts,
            );
            final text = _renderInstruction(
              iset: iset,
              format: format,
              insn: insn,
              instruction: masked,
              instructionBitWidth: instructionBitWidth,
            );
            lastMatch = DisassembledInstruction(
              text: text,
              mnemonic: insn.name,
              formatName: format.name,
              setName: iset.setName,
              operands: operands,
            );
          }
        }
      }
    }
    return lastMatch;
  }

  /// Returns every matching disassembly across all loaded sets — useful
  /// when the caller wants to surface ambiguity.
  List<DisassembledInstruction> decodeAll(
    int instruction,
    int instructionBitWidth,
  ) {
    final result = <DisassembledInstruction>[];
    final mask = instructionBitWidth >= 64
        ? -1
        : (1 << instructionBitWidth) - 1;
    final masked = instruction & mask;
    for (final iset in _sets) {
      if (iset.bitWidth != instructionBitWidth) continue;
      for (final format in iset.formats) {
        for (final insn in format.instructions) {
          if (insn.matches(masked)) {
            result.add(
              DisassembledInstruction(
                text: _renderInstruction(
                  iset: iset,
                  format: format,
                  insn: insn,
                  instruction: masked,
                  instructionBitWidth: instructionBitWidth,
                ),
                mnemonic: insn.name,
                formatName: format.name,
                setName: iset.setName,
              ),
            );
          }
        }
      }
    }
    return result;
  }

  // ── private ────────────────────────────────────────────────────────────────

  /// Extracts each slice's contribution and assembles per-name values.
  ///
  /// Slices tile the instruction word MSB-first in declaration order: a
  /// running cursor advances by each slice's `bitWidth`, so a slice never
  /// states where in the *word* it sits. What it does state — via `top`/`bot`
  /// — is where its bits land in the assembled *value*: the extracted bits
  /// are shifted left by `bot` and OR'd in. Value bits no slice claims stay
  /// zero, which is how RISC-V's implicit `imm[0] = 0` on branch and jump
  /// offsets is expressed without any scaling field in the schema.
  ///
  /// The assembled width of a part is `max(top) + 1` over its slices, and
  /// signed parts are sign-extended from that width. Both match JKU's
  /// `InstructionType::parse` / `SliceValue::new`.
  ///
  /// Returns a map from part-name to the assembled (and sign-extended where
  /// the part type is signed) integer value.
  Map<String, int> _extractParts({
    required InstructionType type,
    required int instruction,
    required int instructionBitWidth,
    required bool unsignedImm,
    required Map<String, PartDecoder> parts,
  }) {
    // Assembled value width per part name: the highest value-bit any of its
    // slices writes, plus one.
    final widths = <String, int>{};
    final extendTops = <String, int>{};
    for (final slice in type.slices) {
      final w = slice.top + 1;
      if (w > (widths[slice.name] ?? 0)) widths[slice.name] = w;
      final e = slice.extendTop;
      if (e > (extendTops[slice.name] ?? 0)) extendTops[slice.name] = e;
    }

    final values = <String, int>{};
    var cursor = 0; // bits consumed from the top of the instruction word
    for (final slice in type.slices) {
      final w = slice.bitWidth;
      final hiExclusive = instructionBitWidth - cursor;
      final lo = hiExclusive - w;
      cursor += w;
      if (lo < 0) continue; // type over-declares the word; ignore the tail
      if (slice.name == 'none') continue;
      final part = parts[slice.name];
      if (part == null || part.partType == PartType.none) continue;

      final lowMask = w >= 63 ? -1 : (1 << w) - 1;
      final extracted = (instruction >> lo) & lowMask;
      values[slice.name] = (values[slice.name] ?? 0) | (extracted << slice.bot);
    }

    final out = <String, int>{};
    values.forEach((name, raw) {
      final w = widths[name]!;
      final part = parts[name]!;
      final signBitSet = w > 0 && w < 64 && ((raw >> (w - 1)) & 1) != 0;
      // `extend_top` widens the unsigned reading by that many bits when the
      // sign bit is set (JKU's first branch in SliceValue::new). Signed
      // readings are extended all the way below, so it changes nothing there.
      var unsignedValue = raw;
      final extend = extendTops[name] ?? 0;
      if (extend > 0 && signBitSet && w + extend < 63) {
        unsignedValue |= (1 << (w + extend)) - (1 << w);
      }
      final signedValue = signBitSet ? (raw | -(1 << w)) : raw;
      out[name] = _interpretByType(
        signedValue: signedValue,
        unsignedValue: unsignedValue,
        partType: part.partType,
        unsignedImm: unsignedImm,
      );
    });
    return out;
  }

  int _interpretByType({
    required int signedValue,
    required int unsignedValue,
    required PartType partType,
    required bool unsignedImm,
  }) {
    switch (partType) {
      case PartType.vint:
        return unsignedImm ? unsignedValue : signedValue;
      case PartType.i8:
      case PartType.i16:
      case PartType.i32:
      case PartType.i64:
        return signedValue;
      case PartType.u8:
      case PartType.u16:
      case PartType.u32:
      case PartType.u64:
      case PartType.boolean:
      case PartType.char:
      case PartType.f32:
      case PartType.f64:
      case PartType.mapping:
      case PartType.none:
        return unsignedValue;
    }
  }

  /// Renders [template] against an already-decoded instruction, using exactly
  /// the semantics the built-in `repr` templates use.
  ///
  /// Exposed because rendering an alias any other way gets it subtly wrong.
  /// A caller that formatted `%rd%` itself would print `10` where the table
  /// prints `a0`, because register spelling comes from the set's `[mappings]`
  /// — so an aliased line would disagree with every unaliased line around it.
  /// Re-parsing the base text to recover the spelling is the other obvious
  /// approach and is worse: a table with a custom `repr` need not be
  /// comma-separated, or ordered, or even contain every operand.
  ///
  /// Returns null when [decoded]'s set is not loaded here, which can only
  /// happen if the caller mixed disassemblers.
  String? renderTemplate({
    required DisassembledInstruction decoded,
    required String template,
    String? mnemonic,
  }) {
    for (final iset in _sets) {
      if (iset.setName != decoded.setName) continue;
      return _expandTemplate(
        template: template,
        insnName: mnemonic ?? decoded.mnemonic,
        partValues: decoded.operands,
        iset: iset,
      );
    }
    return null;
  }

  /// Renders one instruction into its display string.
  String _renderInstruction({
    required InstructionSet iset,
    required InstructionFormat format,
    required InstructionDef insn,
    required int instruction,
    required int instructionBitWidth,
  }) {
    final partValues = _extractParts(
      type: format.type,
      instruction: instruction,
      instructionBitWidth: instructionBitWidth,
      unsignedImm: insn.unsignedImm,
      parts: iset.parts,
    );
    final template =
        format.repr[insn.name] ?? format.repr['default'] ?? r'$name$';
    return _expandTemplate(
      template: template,
      insnName: insn.name,
      partValues: partValues,
      iset: iset,
    );
  }

  /// Expands `%name%` and `$name$` placeholders in [template].
  String _expandTemplate({
    required String template,
    required String insnName,
    required Map<String, int> partValues,
    required InstructionSet iset,
  }) {
    final out = StringBuffer();
    var i = 0;
    while (i < template.length) {
      final ch = template[i];
      if (ch == r'$') {
        final end = template.indexOf(r'$', i + 1);
        if (end < 0) {
          throw FormatException(
            'Unterminated \$ placeholder in repr template: $template',
          );
        }
        final name = template.substring(i + 1, end);
        if (name == 'name') {
          out.write(insnName);
        } else {
          out.write('\$$name\$');
        }
        i = end + 1;
      } else if (ch == '%') {
        final end = template.indexOf('%', i + 1);
        if (end < 0) {
          throw FormatException(
            'Unterminated % placeholder in repr template: $template',
          );
        }
        final name = template.substring(i + 1, end);
        out.write(_renderPart(name: name, partValues: partValues, iset: iset));
        i = end + 1;
      } else {
        out.write(ch);
        i++;
      }
    }
    return out.toString();
  }

  String _renderPart({
    required String name,
    required Map<String, int> partValues,
    required InstructionSet iset,
  }) {
    final part = iset.parts[name];
    if (part == null) return '%$name%';
    final value = partValues[name];
    if (value == null) return '%$name%';

    if (part.partType == PartType.mapping) {
      final mapName = part.mappingName;
      if (mapName == null) return value.toString();
      final mapping = iset.mappings[mapName];
      if (mapping == null) return value.toString();
      final lookup = mapping.lookup(value);
      if (lookup != null) return lookup;
      // Non-strict mappings fall back to raw value display.
      return part.numberRadix.formatInt(value);
    }
    if (part.partType == PartType.boolean) return value != 0 ? 'true' : 'false';
    if (part.partType == PartType.char) {
      // Print as a single ASCII character if printable, else hex.
      if (value >= 0x20 && value < 0x7f) return String.fromCharCode(value);
      return part.numberRadix.formatInt(value);
    }
    return part.numberRadix.formatInt(value);
  }
}
