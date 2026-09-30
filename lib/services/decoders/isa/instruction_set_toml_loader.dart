// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Loader for the JKU `instruction-decoder` TOML schema. Parses one TOML
// document into an [InstructionSet]. The schema is:
//
//   set    = "<label>"
//   width  = <int>
//   [formats] names = […]; parts = [[name, bitwidth, type, radix?], …]
//   [types]   names = […]; [[types.<typeName>]] name/top/bot/extend_top…
//
// Slice `top`/`bot` are positions within the named part's *value*, not
// within the instruction word — see [InstructionSlice]. Slices tile the
// word MSB-first in declaration order, so a type's slice widths should sum
// to `width` (asserted for the bundled corpus in the loader's tests).
//   [mappings] names = […]; <mapName> = [list] | { table }
//   [<format-name>] type = "<typeName>"
//   [<format-name>.repr] default = "…"; <insn> = "…"
//   [<format-name>.instructions.<insn>] mask, match, unsigned?
//
// Unknown top-level keys are tolerated for forward-compat with future
// upstream additions (matches JKU's accidental-but-useful behavior).

import 'package:toml/toml.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';

/// Thrown when a TOML document does not conform to the schema. The message
/// names the offending key path so authors can correct it.
class InstructionSetTomlException implements Exception {
  InstructionSetTomlException(this.message);
  final String message;
  @override
  String toString() => 'InstructionSetTomlException: $message';
}

/// Parses one TOML document into an [InstructionSet]. Throws
/// [InstructionSetTomlException] on schema violations.
///
/// [sourceLabel] is prefixed onto **every** message this raises, not just the
/// TOML syntax error. An author correcting their own table needs to know which
/// file the complaint is about, and while the corpus was ours and every file
/// was under test only one of the two dozen throw sites bothered to say.
InstructionSet parseInstructionSetToml(String tomlText, {String? sourceLabel}) {
  try {
    return _parseInstructionSetToml(tomlText, sourceLabel);
  } on InstructionSetTomlException catch (e) {
    if (sourceLabel == null || e.message.startsWith('$sourceLabel:')) rethrow;
    throw InstructionSetTomlException('$sourceLabel: ${e.message}');
  }
}

InstructionSet _parseInstructionSetToml(String tomlText, String? sourceLabel) {
  final Map<String, dynamic> doc;
  try {
    doc = TomlDocument.parse(tomlText).toMap();
  } on Object catch (e) {
    // The label is added once, by the wrapper — this was the one throw site
    // that used to apply it itself, and leaving that in place would name the
    // file twice in the only message that already got it right.
    throw InstructionSetTomlException('TOML parse error: $e');
  }

  final setName = _requireString(doc, 'set');
  final bitWidth = _requireInt(doc, 'width');
  if (bitWidth <= 0 || bitWidth > 64) {
    throw InstructionSetTomlException('width must be in 1..64 (got $bitWidth)');
  }

  // Validate the [formats] block is present even though we read its
  // contents via dotted-path lookups below.
  _requireTable(doc, 'formats');
  final partsRaw = _requireList(doc, 'formats.parts');
  final formatNames = _requireStringList(doc, 'formats.names');

  final parts = <String, PartDecoder>{};
  for (var i = 0; i < partsRaw.length; i++) {
    final entry = partsRaw[i];
    if (entry is! List) {
      throw InstructionSetTomlException(
        'formats.parts[$i] must be an array (got ${entry.runtimeType})',
      );
    }
    if (entry.length < 3 || entry.length > 4) {
      throw InstructionSetTomlException(
        'formats.parts[$i] must have 3 or 4 elements '
        '[name, bitwidth, type, radix?] (got ${entry.length})',
      );
    }
    final name = entry[0];
    final bw = entry[1];
    final type = entry[2];
    if (name is! String || bw is! int || type is! String) {
      throw InstructionSetTomlException(
        'formats.parts[$i] elements must be [String, int, String, String?]',
      );
    }
    final radixStr = entry.length == 4 ? entry[3] : '';
    if (radixStr is! String) {
      throw InstructionSetTomlException(
        'formats.parts[$i] radix (4th element) must be a string',
      );
    }
    final partType = _parsePartType(type);
    final radix = _parseRadix(radixStr, fullKey: 'formats.parts[$i] ($name)');
    parts[name] = PartDecoder(
      partType: partType,
      numberRadix: radix,
      mappingName: partType == PartType.mapping ? type : null,
    );
  }

  // [types] block
  final typesTable = _requireTable(doc, 'types');
  final typeNames = _requireStringList(doc, 'types.names');
  final types = <String, InstructionType>{};
  for (final typeName in typeNames) {
    final raw = typesTable[typeName];
    if (raw is! List) {
      throw InstructionSetTomlException(
        'types.$typeName must be an array of slice tables',
      );
    }
    final slices = <InstructionSlice>[];
    for (var i = 0; i < raw.length; i++) {
      final slice = raw[i];
      if (slice is! Map) {
        throw InstructionSetTomlException(
          'types.$typeName[$i] must be a table',
        );
      }
      final name = slice['name'];
      final top = slice['top'];
      final bot = slice['bot'];
      final extend = slice['extend_top'] ?? 0;
      if (name is! String || top is! int || bot is! int || extend is! int) {
        throw InstructionSetTomlException(
          'types.$typeName[$i] must declare name (String), top (int), '
          'bot (int), extend_top (int, optional)',
        );
      }
      if (top < bot) {
        throw InstructionSetTomlException(
          'types.$typeName[$i]: top ($top) < bot ($bot) — a slice names an '
          'inclusive MSB-first range within the part value',
        );
      }
      if (top >= bitWidth || bot >= bitWidth) {
        throw InstructionSetTomlException(
          'types.$typeName[$i]: slice $top downto $bot is out of range for '
          'width $bitWidth',
        );
      }
      slices.add(
        InstructionSlice(
          name: name,
          top: top,
          bot: bot,
          extendTop: extend,
        ),
      );
    }
    // Slices tile the instruction word MSB-first from a running cursor, so a
    // type whose slice widths do not sum to `width` silently mis-reads every
    // field after the gap — the decode succeeds and the operands are wrong,
    // which is the failure mode this schema is most prone to and the hardest
    // for an author to spot. The bundled corpus has been checked for this in
    // a test since the loader was written; a stranger's table gets no test, so
    // the check belongs here.
    final covered = slices.fold<int>(0, (a, s) => a + s.bitWidth);
    if (covered != bitWidth) {
      throw InstructionSetTomlException(
        'types.$typeName covers $covered bits, not $bitWidth — slices tile '
        'the word MSB-first and must account for every bit. Add a slice for '
        'the gap, or widen an existing one.',
      );
    }
    types[typeName] = InstructionType(slices: slices);
  }

  // [mappings] block
  final mappingsTable =
      (doc['mappings'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final mappingNames =
      (mappingsTable['names'] as List?)?.cast<String>() ?? const <String>[];
  final mappings = <String, Mapping>{};
  for (final mapName in mappingNames) {
    final raw = mappingsTable[mapName];
    if (raw is List) {
      // List form — strict. Index is the raw value.
      final names = <int, String>{};
      for (var i = 0; i < raw.length; i++) {
        final v = raw[i];
        if (v is! String) {
          throw InstructionSetTomlException(
            'mappings.$mapName[$i] must be a string (got ${v.runtimeType})',
          );
        }
        names[i] = v;
      }
      mappings[mapName] = Mapping(names: names, strict: true);
    } else if (raw is Map) {
      // Table form — non-strict. Keys must be parseable as integers.
      final names = <int, String>{};
      raw.forEach((k, v) {
        if (k is! String || v is! String) {
          throw InstructionSetTomlException(
            'mappings.$mapName: keys/values must be strings',
          );
        }
        final intKey =
            int.tryParse(k) ??
            (k.startsWith('0x')
                ? int.tryParse(k.substring(2), radix: 16)
                : null);
        if (intKey == null) {
          throw InstructionSetTomlException(
            'mappings.$mapName: key "$k" is not a parseable integer',
          );
        }
        names[intKey] = v;
      });
      mappings[mapName] = Mapping(names: names, strict: false);
    } else {
      throw InstructionSetTomlException(
        'mappings.$mapName must be a list or table (got ${raw.runtimeType})',
      );
    }
  }

  // Every part whose type named a mapping must find that mapping.
  //
  // This is the last of the schema's silent-wrong-output paths, and the most
  // likely to be hit: a part's `type` is either a builtin (`u8`, `i32`, …) or
  // the name of a mapping table, and anything unrecognised is *correctly*
  // treated as the latter — the schema has no other way to spell "look this up
  // by name". So a typo (`regsiter` for `register`) is not a syntax error; it
  // becomes a mapping reference that resolves to nothing, and the disassembler
  // renders the raw integer. `5` instead of `x5`, in every instruction using
  // that part, with no error anywhere. Checking the reference here is the only
  // place the mistake is still visible as a mistake.
  for (final entry in parts.entries) {
    final mapName = entry.value.mappingName;
    if (mapName == null || mappings.containsKey(mapName)) continue;
    final known = <String>[...mappings.keys]..sort();
    throw InstructionSetTomlException(
      'part "${entry.key}" has type "$mapName", which is neither a builtin '
      'type nor a declared mapping. '
      '${known.isEmpty ? 'This table declares no mappings.' : 'Declared '
                'mappings: ${known.join(', ')}.'} '
      'Builtin types: boolean, char, i8, i16, i32, i64, u8, u16, u32, u64, '
      'isize, usize, f32, f64, VInt.',
    );
  }

  // Per-format sections.
  final formats = <InstructionFormat>[];
  for (final formatName in formatNames) {
    final raw = doc[formatName];
    if (raw is! Map) {
      throw InstructionSetTomlException(
        'Format "$formatName" referenced in formats.names is not a table',
      );
    }
    final formatTable = raw.cast<String, dynamic>();
    final typeName = formatTable['type'];
    if (typeName is! String) {
      throw InstructionSetTomlException(
        '$formatName.type must be a string (referencing types.<name>)',
      );
    }
    final type = types[typeName];
    if (type == null) {
      throw InstructionSetTomlException(
        '$formatName.type "$typeName" is not declared in [types.names]',
      );
    }

    // repr block (optional but expected; missing means default = name only)
    final reprRaw = formatTable['repr'];
    final repr = <String, String>{};
    if (reprRaw is Map) {
      reprRaw.forEach((k, v) {
        if (k is String && v is String) repr[k] = v;
      });
    }
    repr.putIfAbsent('default', () => r'$name$');

    // instructions block
    final insnsRaw = formatTable['instructions'];
    final instructions = <InstructionDef>[];
    if (insnsRaw is Map) {
      insnsRaw.forEach((insnName, insnTable) {
        if (insnName is! String) return;
        if (insnTable is! Map) {
          throw InstructionSetTomlException(
            '$formatName.instructions.$insnName must be a table',
          );
        }
        final mask = insnTable['mask'];
        final match = insnTable['match'];
        if (mask is! int || match is! int) {
          throw InstructionSetTomlException(
            '$formatName.instructions.$insnName: mask and match must be '
            'integers',
          );
        }
        final unsigned = insnTable['unsigned'] == true;
        instructions.add(
          InstructionDef(
            name: insnName,
            mask: mask,
            match: match,
            unsignedImm: unsigned,
          ),
        );
      });
    }

    formats.add(
      InstructionFormat(
        name: formatName,
        type: type,
        repr: repr,
        instructions: instructions,
      ),
    );
  }

  return InstructionSet(
    setName: setName,
    bitWidth: bitWidth,
    parts: parts,
    mappings: mappings,
    formats: formats,
  );
}

// ── helpers ──────────────────────────────────────────────────────────────────

String _requireString(Map<String, dynamic> doc, String key) {
  final v = doc[key];
  if (v is! String) {
    throw InstructionSetTomlException(
      'Missing or non-string top-level key "$key"',
    );
  }
  return v;
}

int _requireInt(Map<String, dynamic> doc, String key) {
  final v = doc[key];
  if (v is! int) {
    throw InstructionSetTomlException(
      'Missing or non-integer top-level key "$key"',
    );
  }
  return v;
}

Map<String, dynamic> _requireTable(Map<String, dynamic> doc, String key) {
  final v = doc[key];
  if (v is! Map) {
    throw InstructionSetTomlException(
      'Missing or non-table top-level key "$key"',
    );
  }
  return v.cast<String, dynamic>();
}

List<dynamic> _requireList(Map<String, dynamic> doc, String fullKey) {
  final parts = fullKey.split('.');
  final last = parts.removeLast();
  var cur = doc;
  for (final p in parts) {
    final next = cur[p];
    if (next is! Map) {
      throw InstructionSetTomlException(
        'Missing intermediate table "$p" in $fullKey',
      );
    }
    cur = next.cast<String, dynamic>();
  }
  final v = cur[last];
  if (v is! List) {
    throw InstructionSetTomlException('Missing or non-array key "$fullKey"');
  }
  return v;
}

List<String> _requireStringList(Map<String, dynamic> doc, String fullKey) {
  final raw = _requireList(doc, fullKey);
  return [
    for (final e in raw)
      if (e is String)
        e
      else
        throw InstructionSetTomlException('$fullKey must be a list of strings'),
  ];
}

PartType _parsePartType(String type) => switch (type) {
  'boolean' => PartType.boolean,
  'char' => PartType.char,
  'i8' => PartType.i8,
  'i16' => PartType.i16,
  'i32' => PartType.i32,
  'i64' => PartType.i64,
  'u8' => PartType.u8,
  'u16' => PartType.u16,
  'u32' => PartType.u32,
  'u64' => PartType.u64,
  'isize' => PartType.i64,
  'usize' => PartType.u64,
  'f32' => PartType.f32,
  'f64' => PartType.f64,
  'VInt' => PartType.vint,
  '' => PartType.none,
  _ => PartType.mapping, // unknown → routed to a mapping by type-name
};

/// Parses a radix name.
///
/// **Throws on an unknown name rather than defaulting to decimal.** While the
/// only tables in the tree were our own and every one was under test, a silent
/// fallback was harmless. It stops being harmless the moment a stranger authors
/// a table: `radix = "hexidecimal"` would render every immediate in the wrong
/// base, silently, and the author would have no way to discover it short of
/// noticing that their disassembly is wrong. A typo must fail loudly.
NumberRadix _parseRadix(String radix, {String? fullKey}) {
  final r = radix.toLowerCase();
  return switch (r) {
    '' || 'decimal' || 'dec' || 'd' || '10' => NumberRadix.decimal,
    'hexadecimal' ||
    'hex' ||
    'h' ||
    'x' ||
    '0x' ||
    '16' => NumberRadix.hexadecimal,
    'octal' || 'oct' || 'o' || '0o' || '8' => NumberRadix.octal,
    'binary' || 'bin' || 'b' || '0b' || '2' => NumberRadix.binary,
    _ => throw InstructionSetTomlException(
      '${fullKey ?? 'radix'}: unknown radix "$radix". Expected one of '
      'decimal / hexadecimal / octal / binary (or dec / hex / oct / bin, '
      'd / h / o / b, 10 / 16 / 8 / 2).',
    ),
  };
}
