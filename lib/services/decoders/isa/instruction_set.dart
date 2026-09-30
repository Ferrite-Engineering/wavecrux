// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Instruction-decoder data model. A faithful port of the JKU
// `instruction-decoder` Rust crate's runtime types
// (https://github.com/ics-jku/instruction-decoder, MIT). Same shape, same
// semantics; the TOML schema is identical so files written for either tool
// are interchangeable. See assets/decoders/isa/riscv/NOTICE.md.
//
// Nothing here is ISA-specific: the schema is a generic formats / parts /
// mappings encoding description. The ISA lives entirely in the TOML corpus
// under assets/decoders/isa/<architecture>/.

import 'package:meta/meta.dart';

/// The data type of one bit-field "part" in the instruction encoding.
///
/// Mirrors the third positional element of `[formats.parts]` entries in the
/// TOML schema. Unknown type names are routed to [PartType.mapping]; the
/// empty string `""` becomes [PartType.none] (filler slices that should not
/// render as operands).
enum PartType {
  boolean,
  char,
  i8,
  i16,
  i32,
  i64,
  u8,
  u16,
  u32,
  u64,
  f32,
  f64,
  vint,
  none,
  mapping,
}

/// Numeric display radix for a part. Matches the optional 4th positional
/// element of `[formats.parts]` (e.g. `["himm", 32, "VInt", "hex"]`).
enum NumberRadix {
  decimal,
  hexadecimal,
  octal,
  binary;

  /// Format an integer using this radix's conventional representation.
  String formatInt(int value) {
    final negative = value < 0;
    final absValue = negative ? -value : value;
    final body = switch (this) {
      NumberRadix.decimal => absValue.toString(),
      NumberRadix.hexadecimal => '0x${absValue.toRadixString(16)}',
      NumberRadix.octal => '0o${absValue.toRadixString(8)}',
      NumberRadix.binary => '0b${absValue.toRadixString(2)}',
    };
    return negative ? '-$body' : body;
  }
}

/// Decoder for one named part in `[formats.parts]`.
@immutable
class PartDecoder {
  const PartDecoder({
    required this.partType,
    required this.numberRadix,
    this.mappingName,
  });

  final PartType partType;
  final NumberRadix numberRadix;

  /// When [partType] is [PartType.mapping], the name of the mapping table
  /// that translates raw integer values to display strings.
  final String? mappingName;
}

/// One slice of a decoded part.
///
/// **[top] and [bot] are positions within the named part's *value*, not
/// within the instruction word.** A slice's position in the instruction word
/// is implied: slices tile the word MSB-first in declaration order, each
/// consuming [bitWidth] bits from a running cursor. This is exactly JKU's
/// semantics (`position += slice_top - slice_bottom` in `InstructionType::new`,
/// then `value << slice_bottom` in `SliceValue::new`), and it is what lets a
/// scrambled immediate such as RISC-V B-type be described declaratively:
/// each fragment states where in the assembled value it belongs, and bit
/// positions no fragment claims (e.g. B-type's `imm[0]`) stay zero.
///
/// JKU's loader internally stores `slice_top = top + 1`; we keep [top]
/// inclusive here and adjust at extraction time.
///
/// For `name = "none"` filler slices only [bitWidth] is meaningful — the
/// value is discarded — so [top]/[bot] may be written any way that yields
/// the right width.
@immutable
class InstructionSlice {
  const InstructionSlice({
    required this.name,
    required this.top,
    required this.bot,
    this.extendTop = 0,
  });

  /// Name referencing a `[formats.parts]` entry. Multiple slices with the
  /// same [name] are OR'd together, each at its own [bot] offset, to
  /// assemble multi-segment immediates.
  final String name;

  /// Inclusive MSB of this fragment *within the assembled part value*.
  final int top;

  /// Inclusive LSB of this fragment *within the assembled part value* —
  /// equivalently, the left-shift applied to the extracted bits.
  final int bot;

  /// Number of additional bits to widen the value by when its sign bit is
  /// set. Signed parts are already sign-extended to full width from the
  /// assembled value width, so this is a no-op for them; it is retained
  /// because the schema defines it and upstream files may carry it.
  final int extendTop;

  /// Number of instruction-word bits this slice consumes.
  int get bitWidth => top - bot + 1;
}

/// The bit-slice layout for one format. Slices tile the instruction word
/// MSB-first in declaration order; each slice's `top`/`bot` say where its
/// bits land in the named part's value.
@immutable
class InstructionType {
  const InstructionType({required this.slices});

  final List<InstructionSlice> slices;
}

/// One decoded instruction in a format's `[<format>.instructions.<name>]`.
@immutable
class InstructionDef {
  const InstructionDef({
    required this.name,
    required this.mask,
    required this.match,
    this.unsignedImm = false,
  });

  final String name;
  final int mask;
  final int match;

  /// When true, [PartType.vint] parts decode as unsigned. Per-instruction,
  /// not per-part — exactly mirrors JKU's `unsigned = true` flag.
  final bool unsignedImm;

  bool matches(int instruction) => (instruction & mask) == match;
}

/// One format declared by `[<format-name>]` plus its `repr` and
/// `instructions` sub-tables.
@immutable
class InstructionFormat {
  const InstructionFormat({
    required this.name,
    required this.type,
    required this.repr,
    required this.instructions,
  });

  final String name;
  final InstructionType type;

  /// Map of repr template names → format string.
  /// `"default"` is the fallback; per-instruction keys override.
  final Map<String, String> repr;

  final List<InstructionDef> instructions;
}

/// A `[mappings]` entry — list-form is strict (out-of-range = error),
/// table-form is non-strict (missing key = display the raw integer).
@immutable
class Mapping {
  const Mapping({required this.names, required this.strict});

  /// Raw integer value → display string.
  final Map<int, String> names;

  /// True when this mapping was declared as a list (strict). Out-of-range
  /// lookups should be reported as decode errors.
  final bool strict;

  String? lookup(int value) => names[value];
}

/// One TOML file's worth of decoder data — the top-level container that
/// `Decoder` aggregates across multiple files when the user enables
/// multiple ISAs/extensions.
@immutable
class InstructionSet {
  const InstructionSet({
    required this.setName,
    required this.bitWidth,
    required this.parts,
    required this.mappings,
    required this.formats,
  });

  /// Human label from the TOML's `set` field. Decorative — the loader does
  /// not consult this for routing (matches JKU behavior).
  final String setName;

  /// Encoding width in bits (32 for RV32/64, 16 for native-RVC files).
  final int bitWidth;

  /// `[formats.parts]` parsed into per-name decoder records.
  final Map<String, PartDecoder> parts;

  /// `[mappings]` parsed into named lookup tables.
  final Map<String, Mapping> mappings;

  /// `[<format-name>]` blocks in declaration order (matters for tie-breaking
  /// when multiple instructions match — JKU returns the *last* match).
  final List<InstructionFormat> formats;
}
