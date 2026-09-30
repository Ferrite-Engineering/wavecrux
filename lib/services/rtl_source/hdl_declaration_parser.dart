// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/services/rtl_source/hdl_module.dart';

/// HDL source dialect understood by [HdlDeclarationParser].
enum HdlDialect { verilog, vhdl }

/// A best-effort, dependency-free parser that extracts the declaration sites a
/// stems file needs — modules/entities, their signals/ports, and their child
/// instantiations — from Verilog/SystemVerilog and VHDL source text.
///
/// It is deliberately **not** a full HDL front-end. It recognises the common
/// synthesizable subset by structural pattern-matching on comment-stripped
/// text, which is all the stems mapping requires (an identifier → file:line
/// table, not an elaborated netlist). Known limitations, documented so callers
/// can set expectations:
///
/// * `generate` blocks, parameter-dependent array sizing, and macro-expanded
///   (`\`define`) declarations are not elaborated.
/// * Declarations or instantiation headers that span multiple lines before the
///   instance name / first signal name may be missed.
/// * Verilog instantiation vs. user-defined-type disambiguation is heuristic.
///
/// Anything it cannot resolve is simply omitted from the stems file — the RTL
/// panel then shows "no source mapping" for that signal, which is a graceful
/// degradation, never a crash.
class HdlDeclarationParser {
  const HdlDeclarationParser();

  /// Verilog reserved words / type keywords that must never be treated as a
  /// module-instance type or a signal name.
  static const Set<String> _verilogKeywords = {
    'module',
    'endmodule',
    'input',
    'output',
    'inout',
    'wire',
    'reg',
    'logic',
    'bit',
    'byte',
    'tri',
    'triand',
    'trior',
    'wand',
    'wor',
    'supply0',
    'supply1',
    'integer',
    'genvar',
    'real',
    'realtime',
    'time',
    'shortint',
    'int',
    'longint',
    'parameter',
    'localparam',
    'assign',
    'always',
    'always_ff',
    'always_comb',
    'always_latch',
    'initial',
    'final',
    'begin',
    'end',
    'if',
    'else',
    'for',
    'while',
    'repeat',
    'forever',
    'do',
    'case',
    'casez',
    'casex',
    'endcase',
    'generate',
    'endgenerate',
    'function',
    'endfunction',
    'task',
    'endtask',
    'typedef',
    'struct',
    'union',
    'enum',
    'packed',
    'package',
    'endpackage',
    'import',
    'export',
    'return',
    'posedge',
    'negedge',
    'default',
    'signed',
    'unsigned',
    'wait',
    'fork',
    'join',
    'disable',
    'force',
    'release',
    'assert',
    'assume',
    'cover',
    'property',
    'endproperty',
    'sequence',
    'endsequence',
    'interface',
    'endinterface',
    'modport',
    'class',
    'endclass',
    'extends',
    'virtual',
    'static',
    'automatic',
    'const',
    'var',
    'void',
    'string',
    'event',
    'specify',
    'endspecify',
  };

  /// Parses [content] (the text of [sourceFile]) into the modules it declares.
  /// The dialect is chosen by [sourceFile]'s extension, falling back to a
  /// content heuristic.
  List<HdlModule> parse({
    required String sourceFile,
    required String content,
  }) {
    final dialect = _dialectFor(sourceFile, content);
    final stripped = _stripComments(content, dialect);
    return switch (dialect) {
      HdlDialect.verilog => _parseVerilog(sourceFile, stripped),
      HdlDialect.vhdl => _parseVhdl(sourceFile, stripped),
    };
  }

  // ── dialect ──────────────────────────────────────────────────────────────

  HdlDialect _dialectFor(String path, String content) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.vhd') || lower.endsWith('.vhdl')) {
      return HdlDialect.vhdl;
    }
    if (lower.endsWith('.v') ||
        lower.endsWith('.sv') ||
        lower.endsWith('.vh') ||
        lower.endsWith('.svh')) {
      return HdlDialect.verilog;
    }
    // Heuristic for unknown extensions.
    if (RegExp(r'\bentity\b|\barchitecture\b').hasMatch(content)) {
      return HdlDialect.vhdl;
    }
    return HdlDialect.verilog;
  }

  // ── comment stripping (offset-preserving) ────────────────────────────────

  /// Replaces comment characters with spaces, preserving every newline so that
  /// byte offsets — and therefore line numbers — are unchanged.
  String _stripComments(String content, HdlDialect dialect) {
    final out = StringBuffer();
    final n = content.length;
    var i = 0;
    while (i < n) {
      final c = content[i];
      final next = i + 1 < n ? content[i + 1] : '';
      // C-style line comment (both dialects accept `//` in tooling; Verilog
      // uses it natively).
      if (c == '/' && next == '/') {
        while (i < n && content[i] != '\n') {
          out.write(' ');
          i++;
        }
        continue;
      }
      // Block comment (Verilog; harmless for VHDL which lacks it).
      if (c == '/' && next == '*') {
        out.write('  ');
        i += 2;
        while (i < n &&
            !(content[i] == '*' && i + 1 < n && content[i + 1] == '/')) {
          out.write(content[i] == '\n' ? '\n' : ' ');
          i++;
        }
        if (i < n) {
          out.write('  ');
          i += 2;
        }
        continue;
      }
      // VHDL line comment.
      if (dialect == HdlDialect.vhdl && c == '-' && next == '-') {
        while (i < n && content[i] != '\n') {
          out.write(' ');
          i++;
        }
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  // ── line helpers ───────────────────────────────────────────────────────────

  /// Index of the `)` matching the `(` at [open] in [text], or -1 if unbalanced.
  int _matchParen(String text, int open) {
    var depth = 0;
    for (var i = open; i < text.length; i++) {
      final c = text[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 1-based line number of [offset] within [content].
  int _lineOf(String content, int offset) {
    var line = 1;
    final limit = offset.clamp(0, content.length);
    for (var i = 0; i < limit; i++) {
      if (content[i] == '\n') line++;
    }
    return line;
  }

  /// The declared name of a single comma-separated declaration piece: strip
  /// `[...]` ranges/dims, cut at `=` initialisers, and take the LAST identifier
  /// (so leading type keywords like `logic`/`signed` are skipped).
  String? _nameOfPiece(String piece) {
    var p = piece.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    final eq = p.indexOf('=');
    if (eq >= 0) p = p.substring(0, eq);
    final ids = RegExp(r'[A-Za-z_]\w*').allMatches(p).toList();
    if (ids.isEmpty) return null;
    return ids.last.group(0);
  }

  /// Splits [list] on top-level commas (ignoring commas inside `[...]`/`(...)`).
  List<String> _splitTopCommas(String list) {
    final pieces = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (var i = 0; i < list.length; i++) {
      final ch = list[i];
      if (ch == '[' || ch == '(') depth++;
      if (ch == ']' || ch == ')') depth = depth > 0 ? depth - 1 : 0;
      if (ch == ',' && depth == 0) {
        pieces.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) pieces.add(buf.toString());
    return pieces;
  }

  /// Yields an [HdlSignal] for each declared name in [list] (a comma-separated
  /// declaration tail or port segment). [listOffset] is [list]'s absolute
  /// offset in [content], used to compute each name's line number.
  Iterable<HdlSignal> _namesWithLines(
    String list,
    int listOffset,
    String content,
  ) sync* {
    var pos = 0; // offset of the current piece within `list`
    for (final piece in _splitTopCommas(list)) {
      final name = _nameOfPiece(piece);
      if (name != null && !_verilogKeywords.contains(name)) {
        final idx = piece.lastIndexOf(name);
        final abs = listOffset + pos + (idx >= 0 ? idx : 0);
        yield HdlSignal(name: name, lineNumber: _lineOf(content, abs));
      }
      pos += piece.length + 1; // +1 for the comma consumed by the split
    }
  }

  // ── Verilog ──────────────────────────────────────────────────────────────

  List<HdlModule> _parseVerilog(String file, String content) {
    final modules = <HdlModule>[];
    final moduleRe = RegExp(r'\bmodule\s+(\w+)');
    for (final m in moduleRe.allMatches(content)) {
      final name = m.group(1)!;
      final declLine = _lineOf(content, m.start);
      // Region: module keyword → matching endmodule (modules don't nest).
      final endMatch = RegExp(
        r'\bendmodule\b',
      ).firstMatch(content.substring(m.end));
      final regionEnd = endMatch == null
          ? content.length
          : m.end + endMatch.start;
      final region = content.substring(m.end, regionEnd);
      final regionOffset = m.end;

      final signals = <String, HdlSignal>{};
      final instances = <String, HdlInstance>{};

      // Header ANSI ports: from after the module name to the first ';'.
      final semi = region.indexOf(';');
      if (semi > 0) {
        final header = region.substring(0, semi);
        for (final s in _verilogHeaderPorts(header, regionOffset, content)) {
          signals.putIfAbsent(s.name, () => s);
        }
      }

      // Body: line-by-line declarations + instantiations.
      _scanVerilogBody(region, regionOffset, content, signals, instances);

      modules.add(
        HdlModule(
          name: name,
          sourceFile: file,
          declarationLine: declLine,
          signals: signals.values.toList(),
          instances: instances.values.toList(),
        ),
      );
    }
    return modules;
  }

  /// ANSI ports declared in the module header (e.g. inline on the `module`
  /// line: `module foo(input clk, output [7:0] q);`). Each direction keyword
  /// introduces one-or-more comma-separated ports sharing that direction.
  List<HdlSignal> _verilogHeaderPorts(
    String header,
    int headerOffset,
    String content,
  ) {
    final result = <HdlSignal>[];
    final dirRe = RegExp(r'\b(input|output|inout)\b');
    final dirs = dirRe.allMatches(header).toList();
    for (var i = 0; i < dirs.length; i++) {
      final start = dirs[i].end;
      final end = i + 1 < dirs.length ? dirs[i + 1].start : header.length;
      // Replace parens (length-preserving) so the port-list terminator `)` and
      // any `#(...)` artefacts don't confuse name extraction.
      final segment = header
          .substring(start, end)
          .replaceAll(RegExp('[()]'), ' ');
      result.addAll(_namesWithLines(segment, headerOffset + start, content));
    }
    return result;
  }

  void _scanVerilogBody(
    String region,
    int regionOffset,
    String content,
    Map<String, HdlSignal> signals,
    Map<String, HdlInstance> instances,
  ) {
    // Instantiations come in two shapes, both of which routinely span lines in
    // real RTL.
    //
    // (a) Parameterized: `Type #( …possibly multi-line param list… ) inst (`.
    //     The `#(...)` is matched by balancing parens, so the instance name and
    //     port-list `(` may sit many lines below the type.
    final paramRe = RegExp(r'([A-Za-z_]\w*)\s*#\s*\(');
    final afterParams = RegExp(r'^\s*([A-Za-z_]\w*)\s*\(');
    for (final m in paramRe.allMatches(region)) {
      final type = m.group(1)!;
      if (_verilogKeywords.contains(type)) continue;
      final close = _matchParen(region, m.end - 1);
      if (close < 0) continue;
      final after = afterParams.firstMatch(region.substring(close + 1));
      if (after == null) continue;
      final inst = after.group(1)!;
      if (_verilogKeywords.contains(inst)) continue;
      instances.putIfAbsent(
        inst,
        () => HdlInstance(
          moduleType: type,
          instanceName: inst,
          lineNumber: _lineOf(content, regionOffset + m.start),
        ),
      );
    }

    // (b) Plain (no params): `Type inst (` at statement start (the `(` may be on
    //     the next line). Keyword filtering rejects control-flow / declarations.
    final plainRe = RegExp(r'(^|\n)\s*([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\(');
    for (final m in plainRe.allMatches(region)) {
      final type = m.group(2)!;
      final inst = m.group(3)!;
      if (_verilogKeywords.contains(type) || _verilogKeywords.contains(inst)) {
        continue;
      }
      instances.putIfAbsent(
        inst,
        () => HdlInstance(
          moduleType: type,
          instanceName: inst,
          lineNumber: _lineOf(content, regionOffset + m.start),
        ),
      );
    }

    // Declarations: `<keyword> … ;`. The tail is everything between the keyword
    // and the terminating `;` (its absolute span is derivable from the match
    // end, since the regex ends exactly at `;`).
    final declRe = RegExp(
      '(input|output|inout|wire|reg|logic|bit|tri|wand|wor|'
      'supply0|supply1|integer|genvar|real|realtime|time|int|shortint|'
      r'longint|byte)\b([^;]*);',
    );
    for (final m in declRe.allMatches(region)) {
      final tail = m.group(2)!;
      // tail occupies [m.end - 1 - tail.length, m.end - 1) within the region
      // (the `;` is the single char at m.end - 1).
      final tailOffset = regionOffset + (m.end - 1 - tail.length);
      for (final s in _namesWithLines(tail, tailOffset, content)) {
        signals.putIfAbsent(s.name, () => s);
      }
    }
  }

  // ── VHDL ─────────────────────────────────────────────────────────────────

  List<HdlModule> _parseVhdl(String file, String content) {
    final modules = <HdlModule>[];

    // Entities: ports become the module's signals.
    final entityRe = RegExp(r'\bentity\s+(\w+)\s+is\b', caseSensitive: false);
    for (final m in entityRe.allMatches(content)) {
      final name = m.group(1)!;
      final declLine = _lineOf(content, m.start);
      final endRe = RegExp(
        r'\bend\b[^;]*;',
        caseSensitive: false,
      ).firstMatch(content.substring(m.end));
      final regionEnd = endRe == null ? content.length : m.end + endRe.end;
      final region = content.substring(m.end, regionEnd);
      final ports = _vhdlPorts(region, m.end, content);
      modules.add(
        HdlModule(
          name: name,
          sourceFile: file,
          declarationLine: declLine,
          signals: ports,
        ),
      );
    }

    // Architectures: internal signals + instantiations, keyed to their entity.
    final archRe = RegExp(
      r'\barchitecture\s+(\w+)\s+of\s+(\w+)\s+is\b',
      caseSensitive: false,
    );
    for (final m in archRe.allMatches(content)) {
      final entity = m.group(2)!;
      final declLine = _lineOf(content, m.start);
      final beginRe = RegExp(r'\bbegin\b', caseSensitive: false).firstMatch(
        content.substring(m.end),
      );
      final declEnd = beginRe == null ? content.length : m.end + beginRe.start;
      final declRegion = content.substring(m.end, declEnd);

      final signals = <String, HdlSignal>{};
      final signalRe = RegExp(
        r'\bsignal\s+([\w\s,]+?)\s*:',
        caseSensitive: false,
      );
      for (final s in signalRe.allMatches(declRegion)) {
        final list = s.group(1)!;
        for (final piece in _splitTopCommas(list)) {
          final name = _nameOfPiece(piece);
          if (name == null) continue;
          final off = m.end + s.start;
          signals.putIfAbsent(
            name,
            () => HdlSignal(name: name, lineNumber: _lineOf(content, off)),
          );
        }
      }

      final instances = <HdlInstance>[];
      final bodyStart = beginRe == null ? content.length : m.end + beginRe.end;
      final bodyEnd = () {
        final e = RegExp(
          r'\bend\b',
          caseSensitive: false,
        ).allMatches(content.substring(bodyStart));
        return e.isEmpty ? content.length : bodyStart + e.last.start;
      }();
      final body = content.substring(bodyStart, bodyEnd);
      final instRe = RegExp(
        r'(^|\n)\s*(\w+)\s*:\s*(?:entity\s+(?:\w+\.)?(\w+)|component\s+(\w+)|(\w+))'
        r'\s*(?:generic\s+map|port\s+map)',
        caseSensitive: false,
      );
      for (final inst in instRe.allMatches(body)) {
        final label = inst.group(2)!;
        final type = inst.group(3) ?? inst.group(4) ?? inst.group(5);
        if (type == null) continue;
        final off = bodyStart + inst.start;
        instances.add(
          HdlInstance(
            moduleType: type,
            instanceName: label,
            lineNumber: _lineOf(content, off),
          ),
        );
      }

      modules.add(
        HdlModule(
          name: entity,
          sourceFile: file,
          declarationLine: declLine,
          signals: signals.values.toList(),
          instances: instances,
        ),
      );
    }
    return modules;
  }

  List<HdlSignal> _vhdlPorts(String region, int regionOffset, String content) {
    final result = <HdlSignal>[];
    final portRe = RegExp(r'\bport\s*\(', caseSensitive: false);
    final pm = portRe.firstMatch(region);
    if (pm == null) return result;
    // Capture to the matching close paren of the port list.
    var depth = 0;
    var end = pm.end;
    for (var i = pm.end - 1; i < region.length; i++) {
      if (region[i] == '(') depth++;
      if (region[i] == ')') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    final portList = region.substring(pm.end, end);
    // Each port decl: `name[, name] : in|out|inout|buffer type`.
    final declRe = RegExp(
      r'([\w\s,]+?)\s*:\s*(in|out|inout|buffer)\b',
      caseSensitive: false,
    );
    for (final d in declRe.allMatches(portList)) {
      final names = d.group(1)!;
      for (final piece in _splitTopCommas(names)) {
        final name = _nameOfPiece(piece);
        if (name == null) continue;
        final off = regionOffset + pm.end + d.start;
        result.add(
          HdlSignal(name: name, lineNumber: _lineOf(content, off)),
        );
      }
    }
    return result;
  }
}
