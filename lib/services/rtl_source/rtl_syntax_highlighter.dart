// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// What kind of token a span represents in highlighted RTL source.
enum RtlTokenKind {
  /// Plain text (default).
  plain,

  /// Reserved language keyword.
  keyword,

  /// Built-in or primitive type identifier.
  typeKeyword,

  /// Single-line `// ...` or block `/* ... */` comment.
  comment,

  /// Numeric literal — integer, real, or sized Verilog literal (e.g.
  /// `8'hFF`, `4'b1010`, `3.14`).
  number,

  /// Quoted string literal.
  string,
}

/// A contiguous run of highlighted source text with a single [kind].
@immutable
class RtlTokenSpan {
  const RtlTokenSpan({required this.text, required this.kind});

  final String text;
  final RtlTokenKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtlTokenSpan &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => 'RtlTokenSpan($kind, ${text.length} chars)';
}

/// Which RTL dialect to highlight as.
enum RtlSourceDialect { verilog, vhdl }

/// Lightweight line-based keyword highlighter for Verilog / SystemVerilog and
/// VHDL source listings.
///
/// Block comments (`/* */` for Verilog, `--` for VHDL line-only) are tracked
/// across lines via the [carryBlockComment] helper. The highlighter is
/// pragmatic, not a full lexer — it's tuned for fast incremental rendering of
/// the lines visible in the RTL source panel, not for ASTs.
class RtlSyntaxHighlighter {
  const RtlSyntaxHighlighter();

  /// Detects the dialect from a file extension. Defaults to [RtlSourceDialect.verilog].
  RtlSourceDialect dialectFor(String? path) {
    if (path == null) return RtlSourceDialect.verilog;
    final lower = path.toLowerCase();
    if (lower.endsWith('.vhd') || lower.endsWith('.vhdl')) {
      return RtlSourceDialect.vhdl;
    }
    return RtlSourceDialect.verilog;
  }

  /// Tokenises [line] into a list of contiguous [RtlTokenSpan]s.
  ///
  /// [inBlockComment] — pass `true` when the previous line ended inside a
  /// `/* ... */` block comment, so this line continues the comment until the
  /// closing `*/`. VHDL has no block comments; the parameter is ignored
  /// for [RtlSourceDialect.vhdl].
  ///
  /// Returns at least one span (possibly the empty-text plain span when
  /// [line] is empty).
  List<RtlTokenSpan> tokenize(
    String line,
    RtlSourceDialect dialect, {
    bool inBlockComment = false,
  }) {
    if (line.isEmpty) {
      return const [RtlTokenSpan(text: '', kind: RtlTokenKind.plain)];
    }

    final spans = <RtlTokenSpan>[];
    var i = 0;
    var blockComment = inBlockComment && dialect == RtlSourceDialect.verilog;

    while (i < line.length) {
      // Block comment continuation/close (Verilog only).
      if (blockComment) {
        final end = line.indexOf('*/', i);
        if (end < 0) {
          spans.add(
            RtlTokenSpan(
              text: line.substring(i),
              kind: RtlTokenKind.comment,
            ),
          );
          return spans;
        }
        spans.add(
          RtlTokenSpan(
            text: line.substring(i, end + 2),
            kind: RtlTokenKind.comment,
          ),
        );
        i = end + 2;
        blockComment = false;
        continue;
      }

      final ch = line[i];

      // Line comment.
      if (dialect == RtlSourceDialect.verilog &&
          ch == '/' &&
          i + 1 < line.length &&
          line[i + 1] == '/') {
        spans.add(
          RtlTokenSpan(
            text: line.substring(i),
            kind: RtlTokenKind.comment,
          ),
        );
        return spans;
      }
      if (dialect == RtlSourceDialect.vhdl &&
          ch == '-' &&
          i + 1 < line.length &&
          line[i + 1] == '-') {
        spans.add(
          RtlTokenSpan(
            text: line.substring(i),
            kind: RtlTokenKind.comment,
          ),
        );
        return spans;
      }

      // Block comment start (Verilog).
      if (dialect == RtlSourceDialect.verilog &&
          ch == '/' &&
          i + 1 < line.length &&
          line[i + 1] == '*') {
        final end = line.indexOf('*/', i + 2);
        if (end < 0) {
          spans.add(
            RtlTokenSpan(
              text: line.substring(i),
              kind: RtlTokenKind.comment,
            ),
          );
          return spans;
        }
        spans.add(
          RtlTokenSpan(
            text: line.substring(i, end + 2),
            kind: RtlTokenKind.comment,
          ),
        );
        i = end + 2;
        continue;
      }

      // String literal.
      if (ch == '"') {
        var j = i + 1;
        while (j < line.length && line[j] != '"') {
          if (line[j] == r'\' && j + 1 < line.length) {
            j += 2;
          } else {
            j++;
          }
        }
        if (j < line.length) j++; // include closing quote
        spans.add(
          RtlTokenSpan(
            text: line.substring(i, j),
            kind: RtlTokenKind.string,
          ),
        );
        i = j;
        continue;
      }

      // Verilog sized literal: `<digits>'<base><digits>` e.g. `8'hFF`,
      // `4'b1010`, `3'd5`.
      if (dialect == RtlSourceDialect.verilog &&
          _isDigit(ch) &&
          _matchesVerilogSized(line, i)) {
        final j = _scanVerilogSized(line, i);
        spans.add(
          RtlTokenSpan(
            text: line.substring(i, j),
            kind: RtlTokenKind.number,
          ),
        );
        i = j;
        continue;
      }

      // Plain numeric literal: 0–9 then digits / `.` / `_`.
      if (_isDigit(ch)) {
        var j = i + 1;
        while (j < line.length &&
            (_isDigit(line[j]) || line[j] == '.' || line[j] == '_')) {
          j++;
        }
        spans.add(
          RtlTokenSpan(
            text: line.substring(i, j),
            kind: RtlTokenKind.number,
          ),
        );
        i = j;
        continue;
      }

      // Identifier / keyword.
      if (_isIdentStart(ch)) {
        var j = i + 1;
        while (j < line.length && _isIdentPart(line[j])) {
          j++;
        }
        final word = line.substring(i, j);
        final lowered = dialect == RtlSourceDialect.vhdl
            ? word.toLowerCase()
            : word;
        final kind = _keywordKind(lowered, dialect);
        spans.add(RtlTokenSpan(text: word, kind: kind));
        i = j;
        continue;
      }

      // Anything else: emit as plain, coalesced into runs.
      var j = i + 1;
      while (j < line.length &&
          !_isIdentStart(line[j]) &&
          !_isDigit(line[j]) &&
          line[j] != '"' &&
          line[j] != '/' &&
          line[j] != '-') {
        j++;
      }
      spans.add(
        RtlTokenSpan(
          text: line.substring(i, j),
          kind: RtlTokenKind.plain,
        ),
      );
      i = j;
    }

    return spans;
  }

  /// Whether [line] ends inside an unclosed Verilog `/* ... */` block comment,
  /// given that it started with [inBlockComment] from the previous line.
  ///
  /// Always false for VHDL.
  bool carryBlockComment(
    String line,
    RtlSourceDialect dialect, {
    bool inBlockComment = false,
  }) {
    if (dialect != RtlSourceDialect.verilog) return false;
    var open = inBlockComment;
    var i = 0;
    while (i < line.length) {
      if (open) {
        final end = line.indexOf('*/', i);
        if (end < 0) return true;
        i = end + 2;
        open = false;
        continue;
      }
      // Skip strings.
      if (line[i] == '"') {
        var j = i + 1;
        while (j < line.length && line[j] != '"') {
          if (line[j] == r'\' && j + 1 < line.length) {
            j += 2;
          } else {
            j++;
          }
        }
        i = j < line.length ? j + 1 : j;
        continue;
      }
      // Line comment terminates further parsing.
      if (line[i] == '/' && i + 1 < line.length && line[i + 1] == '/') {
        return false;
      }
      // Block-comment open.
      if (line[i] == '/' && i + 1 < line.length && line[i + 1] == '*') {
        i += 2;
        open = true;
        continue;
      }
      i++;
    }
    return open;
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static bool _isDigit(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return c >= 0x30 && c <= 0x39;
  }

  static bool _isIdentStart(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        c == 0x5F /* _ */ ||
        c == 0x24 /* $ — Verilog system tasks */;
  }

  static bool _isIdentPart(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        c == 0x5F ||
        c == 0x24;
  }

  static bool _matchesVerilogSized(String line, int i) {
    // Already at a digit. Look ahead for `digits' [base]`.
    var j = i;
    while (j < line.length && _isDigit(line[j])) {
      j++;
    }
    if (j >= line.length || line[j] != "'") return false;
    if (j + 1 >= line.length) return false;
    final base = line[j + 1].toLowerCase();
    return base == 'h' || base == 'd' || base == 'b' || base == 'o';
  }

  static int _scanVerilogSized(String line, int i) {
    var j = i;
    while (j < line.length && _isDigit(line[j])) {
      j++;
    }
    if (j < line.length && line[j] == "'") j++;
    if (j < line.length) j++; // base char
    while (j < line.length &&
        (_isDigit(line[j]) ||
            _isIdentPart(line[j]) ||
            line[j] == '_' ||
            line[j] == 'x' ||
            line[j] == 'z')) {
      j++;
    }
    return j;
  }

  RtlTokenKind _keywordKind(String word, RtlSourceDialect dialect) {
    switch (dialect) {
      case RtlSourceDialect.verilog:
        if (_verilogKeywords.contains(word)) return RtlTokenKind.keyword;
        if (_verilogTypes.contains(word)) return RtlTokenKind.typeKeyword;
        return RtlTokenKind.plain;
      case RtlSourceDialect.vhdl:
        if (_vhdlKeywords.contains(word)) return RtlTokenKind.keyword;
        if (_vhdlTypes.contains(word)) return RtlTokenKind.typeKeyword;
        return RtlTokenKind.plain;
    }
  }

  // Verilog / SystemVerilog reserved words (control-flow + structure).
  static const _verilogKeywords = <String>{
    'always',
    'always_comb',
    'always_ff',
    'always_latch',
    'and',
    'assign',
    'automatic',
    'begin',
    'break',
    'case',
    'casex',
    'casez',
    'class',
    'continue',
    'default',
    'defparam',
    'disable',
    'do',
    'else',
    'end',
    'endcase',
    'endclass',
    'endfunction',
    'endgenerate',
    'endinterface',
    'endmodule',
    'endpackage',
    'endprimitive',
    'endprogram',
    'endspecify',
    'endtable',
    'endtask',
    'extends',
    'for',
    'foreach',
    'forever',
    'fork',
    'function',
    'generate',
    'genvar',
    'if',
    'import',
    'initial',
    'input',
    'inout',
    'interface',
    'join',
    'localparam',
    'module',
    'negedge',
    'new',
    'output',
    'package',
    'parameter',
    'posedge',
    'primitive',
    'program',
    'property',
    'pure',
    'rand',
    'randc',
    'repeat',
    'return',
    'specify',
    'static',
    'super',
    'task',
    'this',
    'typedef',
    'unique',
    'unique0',
    'virtual',
    'while',
  };

  static const _verilogTypes = <String>{
    'bit',
    'byte',
    'chandle',
    'event',
    'int',
    'integer',
    'logic',
    'longint',
    'real',
    'realtime',
    'reg',
    'shortint',
    'shortreal',
    'signed',
    'string',
    'supply0',
    'supply1',
    'time',
    'tri',
    'tri0',
    'tri1',
    'triand',
    'trior',
    'trireg',
    'unsigned',
    'wand',
    'wire',
    'wor',
  };

  static const _vhdlKeywords = <String>{
    'abs',
    'access',
    'after',
    'alias',
    'all',
    'and',
    'architecture',
    'array',
    'assert',
    'attribute',
    'begin',
    'block',
    'body',
    'buffer',
    'bus',
    'case',
    'component',
    'configuration',
    'constant',
    'disconnect',
    'downto',
    'else',
    'elsif',
    'end',
    'entity',
    'exit',
    'file',
    'for',
    'function',
    'generate',
    'generic',
    'group',
    'guarded',
    'if',
    'impure',
    'in',
    'inertial',
    'inout',
    'is',
    'label',
    'library',
    'linkage',
    'literal',
    'loop',
    'map',
    'mod',
    'nand',
    'new',
    'next',
    'nor',
    'not',
    'null',
    'of',
    'on',
    'open',
    'or',
    'others',
    'out',
    'package',
    'port',
    'postponed',
    'procedure',
    'process',
    'pure',
    'range',
    'record',
    'register',
    'reject',
    'rem',
    'report',
    'return',
    'rol',
    'ror',
    'select',
    'severity',
    'signal',
    'shared',
    'sla',
    'sll',
    'sra',
    'srl',
    'subtype',
    'then',
    'to',
    'transport',
    'type',
    'unaffected',
    'units',
    'until',
    'use',
    'variable',
    'wait',
    'when',
    'while',
    'with',
    'xnor',
    'xor',
  };

  static const _vhdlTypes = <String>{
    'bit',
    'bit_vector',
    'boolean',
    'character',
    'integer',
    'natural',
    'positive',
    'real',
    'std_logic',
    'std_logic_vector',
    'std_ulogic',
    'std_ulogic_vector',
    'string',
    'time',
    'unsigned',
    'signed',
  };
}
