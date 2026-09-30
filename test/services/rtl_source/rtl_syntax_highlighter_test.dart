// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/rtl_source/rtl_syntax_highlighter.dart';

void main() {
  const highlighter = RtlSyntaxHighlighter();

  // ── dialect detection ──────────────────────────────────────────────────────
  group('dialectFor', () {
    test('verilog by default', () {
      expect(
        highlighter.dialectFor(null),
        RtlSourceDialect.verilog,
      );
      expect(
        highlighter.dialectFor('top.v'),
        RtlSourceDialect.verilog,
      );
      expect(
        highlighter.dialectFor('top.sv'),
        RtlSourceDialect.verilog,
      );
    });

    test('vhdl when extension is .vhd or .vhdl', () {
      expect(
        highlighter.dialectFor('top.vhd'),
        RtlSourceDialect.vhdl,
      );
      expect(
        highlighter.dialectFor('TOP.VHDL'),
        RtlSourceDialect.vhdl,
      );
    });
  });

  // ── empty input ────────────────────────────────────────────────────────────
  test('empty line returns single empty plain span', () {
    final result = highlighter.tokenize('', RtlSourceDialect.verilog);
    expect(result, hasLength(1));
    expect(result.single.text, '');
    expect(result.single.kind, RtlTokenKind.plain);
  });

  // ── verilog ────────────────────────────────────────────────────────────────
  group('verilog tokenisation', () {
    test('keyword is tagged as keyword', () {
      final spans = highlighter.tokenize(
        'always @(posedge clk)',
        RtlSourceDialect.verilog,
      );
      final kinds = spans.map((s) => s.kind).toSet();
      expect(kinds, contains(RtlTokenKind.keyword));
      expect(
        spans.where((s) => s.text == 'always').single.kind,
        RtlTokenKind.keyword,
      );
      expect(
        spans.where((s) => s.text == 'posedge').single.kind,
        RtlTokenKind.keyword,
      );
    });

    test('type keyword tagged as typeKeyword', () {
      final spans = highlighter.tokenize(
        'reg [7:0] data;',
        RtlSourceDialect.verilog,
      );
      expect(
        spans.where((s) => s.text == 'reg').single.kind,
        RtlTokenKind.typeKeyword,
      );
    });

    test('plain identifier is tagged as plain', () {
      final spans = highlighter.tokenize('my_signal', RtlSourceDialect.verilog);
      expect(spans.single.kind, RtlTokenKind.plain);
      expect(spans.single.text, 'my_signal');
    });

    test('line comment captures everything to EOL', () {
      final spans = highlighter.tokenize(
        'reg x; // tail comment with `keywords` inside',
        RtlSourceDialect.verilog,
      );
      final comment = spans.last;
      expect(comment.kind, RtlTokenKind.comment);
      expect(comment.text, '// tail comment with `keywords` inside');
    });

    test('block comment on a single line', () {
      final spans = highlighter.tokenize(
        'reg /* inline */ x;',
        RtlSourceDialect.verilog,
      );
      expect(
        spans.any(
          (s) => s.kind == RtlTokenKind.comment && s.text == '/* inline */',
        ),
        isTrue,
      );
    });

    test('unclosed block comment runs to end of line', () {
      final spans = highlighter.tokenize(
        'reg x; /* still open',
        RtlSourceDialect.verilog,
      );
      expect(spans.last.kind, RtlTokenKind.comment);
      expect(spans.last.text, '/* still open');
    });

    test('block-comment continuation across lines via inBlockComment', () {
      final spans = highlighter.tokenize(
        'still in comment */ x = 1;',
        RtlSourceDialect.verilog,
        inBlockComment: true,
      );
      expect(spans.first.kind, RtlTokenKind.comment);
      expect(spans.first.text, 'still in comment */');
    });

    test('string literal', () {
      final spans = highlighter.tokenize(
        r'$display("hello \"world\"");',
        RtlSourceDialect.verilog,
      );
      final str = spans.firstWhere((s) => s.kind == RtlTokenKind.string);
      expect(str.text, contains('"hello'));
      expect(str.text, endsWith('"'));
    });

    test('verilog sized literal hex', () {
      final spans = highlighter.tokenize(
        "data = 8'hFF;",
        RtlSourceDialect.verilog,
      );
      expect(
        spans.any((s) => s.text == "8'hFF" && s.kind == RtlTokenKind.number),
        isTrue,
      );
    });

    test('verilog sized literal binary with x/z digits', () {
      final spans = highlighter.tokenize(
        "x = 4'b10x1;",
        RtlSourceDialect.verilog,
      );
      expect(
        spans.any((s) => s.text == "4'b10x1" && s.kind == RtlTokenKind.number),
        isTrue,
      );
    });

    test('plain decimal and real numbers', () {
      final spans1 = highlighter.tokenize('42', RtlSourceDialect.verilog);
      expect(spans1.single.kind, RtlTokenKind.number);
      final spans2 = highlighter.tokenize('3.14', RtlSourceDialect.verilog);
      expect(spans2.single.kind, RtlTokenKind.number);
    });

    test(r'system task with $ prefix is identifier', () {
      final spans = highlighter.tokenize(
        r'$display("x");',
        RtlSourceDialect.verilog,
      );
      // The `$display` token is plain (not a keyword) — that's fine.
      final dollarToken = spans.firstWhere((s) => s.text == r'$display');
      expect(dollarToken.kind, RtlTokenKind.plain);
    });
  });

  // ── vhdl ──────────────────────────────────────────────────────────────────
  group('vhdl tokenisation', () {
    test('uppercase keyword is recognised case-insensitively', () {
      final spans = highlighter.tokenize(
        'ARCHITECTURE rtl OF top IS',
        RtlSourceDialect.vhdl,
      );
      expect(
        spans.where((s) => s.text == 'ARCHITECTURE').single.kind,
        RtlTokenKind.keyword,
      );
      expect(
        spans.where((s) => s.text == 'OF').single.kind,
        RtlTokenKind.keyword,
      );
    });

    test('std_logic recognised as type keyword', () {
      final spans = highlighter.tokenize(
        'signal a : std_logic;',
        RtlSourceDialect.vhdl,
      );
      expect(
        spans.where((s) => s.text == 'std_logic').single.kind,
        RtlTokenKind.typeKeyword,
      );
    });

    test('-- line comment to EOL', () {
      final spans = highlighter.tokenize(
        'a := b; -- comment // not nested',
        RtlSourceDialect.vhdl,
      );
      expect(spans.last.kind, RtlTokenKind.comment);
      expect(spans.last.text, '-- comment // not nested');
    });

    test('block comment is NOT recognised in VHDL (treated as plain)', () {
      final spans = highlighter.tokenize(
        '/* not a comment */',
        RtlSourceDialect.vhdl,
      );
      expect(
        spans.any((s) => s.kind == RtlTokenKind.comment),
        isFalse,
      );
    });
  });

  // ── carryBlockComment ──────────────────────────────────────────────────────
  group('carryBlockComment', () {
    test('false for VHDL regardless of input', () {
      expect(
        highlighter.carryBlockComment(
          '/* anything */',
          RtlSourceDialect.vhdl,
        ),
        isFalse,
      );
      expect(
        highlighter.carryBlockComment(
          'still in comment',
          RtlSourceDialect.vhdl,
          inBlockComment: true,
        ),
        isFalse,
      );
    });

    test('opens and closes on same line', () {
      expect(
        highlighter.carryBlockComment(
          'reg x; /* inline */ wire y;',
          RtlSourceDialect.verilog,
        ),
        isFalse,
      );
    });

    test('opens but does not close', () {
      expect(
        highlighter.carryBlockComment(
          'reg x; /* still open',
          RtlSourceDialect.verilog,
        ),
        isTrue,
      );
    });

    test('was open and closes on this line', () {
      expect(
        highlighter.carryBlockComment(
          'continuation */ wire y;',
          RtlSourceDialect.verilog,
          inBlockComment: true,
        ),
        isFalse,
      );
    });

    test('was open and stays open', () {
      expect(
        highlighter.carryBlockComment(
          'continuation without close',
          RtlSourceDialect.verilog,
          inBlockComment: true,
        ),
        isTrue,
      );
    });

    test('strings do not contain false positives', () {
      expect(
        highlighter.carryBlockComment(
          r'$display("/* fake comment */");',
          RtlSourceDialect.verilog,
        ),
        isFalse,
      );
    });

    test('line comment does not start a block comment', () {
      expect(
        highlighter.carryBlockComment(
          '// /* not a block start',
          RtlSourceDialect.verilog,
        ),
        isFalse,
      );
    });
  });

  // ── span equality ──────────────────────────────────────────────────────────
  test('RtlTokenSpan equality and hashCode', () {
    const a = RtlTokenSpan(text: 'reg', kind: RtlTokenKind.typeKeyword);
    const b = RtlTokenSpan(text: 'reg', kind: RtlTokenKind.typeKeyword);
    const c = RtlTokenSpan(text: 'reg', kind: RtlTokenKind.plain);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a.toString(), contains('typeKeyword'));
  });
}
