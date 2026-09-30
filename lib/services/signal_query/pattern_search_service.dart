// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/pattern_expression.dart';
import 'package:wavecrux/domain/models/pattern_match.dart';
import 'package:wavecrux/domain/models/pattern_search_result.dart';
import 'package:wavecrux/domain/models/time_range.dart';

/// Stateless service for searching multi-signal boolean pattern matches over
/// a waveform time range.
///
/// All signals referenced in an expression must be pre-loaded on [source] via
/// [WaveformDataSource.loadSignal] before calling [search].
///
/// ### Expression text syntax (for [parseExpression])
///
/// ```text
/// signal_path op value  [AND | OR  signal_path op value ...]
/// NOT (expr)
/// ```
///
/// - **Operators**: `==`, `!=`, `>`, `<`, `>=`, `<=`, `&`, `|`
/// - **Logical**: `AND`, `OR`, `NOT` (uppercase keywords)
/// - **Values**: `0x1F` (hex), `0b1010` (binary), `42` (decimal)
/// - **Grouping**: `(expr)`
/// - **Signal paths**: any identifier with dots, underscores, and bracket
///   notation — e.g. `top.cpu.data[7:0]`.
///
/// ### x/z handling
///
/// When a signal has an unknown (`x`) or high-impedance (`z`) value at the
/// evaluated time, **all** comparison operators return `false`.  Unknown values
/// never satisfy any condition, including `!=`.
class PatternSearchService {
  const PatternSearchService();

  // ── public API ──────────────────────────────────────────────────────────────

  /// Searches `[startTime, endTime)` for all regions where [expression] is
  /// continuously true.
  ///
  /// Returns a [PatternSearchResult] with matches in ascending time order.
  /// Adjacent true-regions are merged into a single [PatternMatch].
  PatternSearchResult search(
    PatternExpression expression,
    WaveformDataSource source,
    int startTime,
    int endTime,
  ) {
    final paths = expression.signalPaths;

    // Collect every tick at which at least one involved signal changes,
    // plus the explicit start boundary.
    final timesSet = <int>{startTime};
    for (final path in paths) {
      for (final change in source.changesInRange(path, startTime, endTime)) {
        if (change.time > startTime && change.time < endTime) {
          timesSet.add(change.time);
        }
      }
    }

    final sortedTimes = [...timesSet]..sort();

    // Evaluate the expression at each interval boundary, building match regions.
    final matches = <PatternMatch>[];
    int? matchStart;
    Map<String, String>? matchValues;

    for (var i = 0; i < sortedTimes.length; i++) {
      final t = sortedTimes[i];
      // The next boundary — or the explicit end of the search range.
      final nextT = i + 1 < sortedTimes.length ? sortedTimes[i + 1] : endTime;

      if (nextT <= t) continue; // Zero-duration interval — skip.

      final snapshot = <String, String>{
        for (final path in paths) path: source.valueAt(path, t) ?? 'x',
      };

      final isTrue = evaluate(expression, snapshot);

      if (isTrue && matchStart == null) {
        matchStart = t;
        matchValues = snapshot;
      } else if (!isTrue && matchStart != null) {
        matches.add(
          PatternMatch(
            time: matchStart,
            endTime: t,
            signalValues: Map.of(matchValues!),
          ),
        );
        matchStart = null;
        matchValues = null;
      }
    }

    // Close any match that extends to the end of the search range.
    if (matchStart != null) {
      matches.add(
        PatternMatch(
          time: matchStart,
          endTime: endTime,
          signalValues: Map.of(matchValues!),
        ),
      );
    }

    return PatternSearchResult(
      matches: matches,
      expression: expression,
      searchRange: TimeRange(start: startTime, end: endTime),
    );
  }

  /// Evaluates [expression] against a snapshot of raw VCD [signalValues].
  ///
  /// [signalValues] maps signal path → raw VCD value string
  /// (e.g. `'1'`, `'b1011'`, `'x'`).
  ///
  /// x/z values always produce `false` for every operator.
  bool evaluate(
    PatternExpression expression,
    Map<String, String> signalValues,
  ) {
    if (expression is SignalCondition) {
      return _evaluateCondition(expression, signalValues);
    }
    if (expression is AndExpression) {
      return evaluate(expression.left, signalValues) &&
          evaluate(expression.right, signalValues);
    }
    if (expression is OrExpression) {
      return evaluate(expression.left, signalValues) ||
          evaluate(expression.right, signalValues);
    }
    if (expression is NotExpression) {
      return !evaluate(expression.operand, signalValues);
    }
    // Sealed class — all subtypes are handled above.
    throw StateError('Unhandled PatternExpression: ${expression.runtimeType}');
  }

  /// Parses a text expression into a [PatternExpression].
  ///
  /// Throws [FormatException] for syntax errors or unknown operators.
  PatternExpression parseExpression(String text) {
    final tokens = _tokenize(text.trim());
    if (tokens.isEmpty) {
      throw const FormatException('Expression must not be empty');
    }
    final parser = _ExpressionParser(tokens);
    final expr = parser.parseOr();
    if (!parser.isAtEnd) {
      throw FormatException(
        'Unexpected token at position ${parser.pos}: '
        '"${parser.currentText}"',
      );
    }
    return expr;
  }

  // ── evaluation helpers ──────────────────────────────────────────────────────

  bool _evaluateCondition(
    SignalCondition cond,
    Map<String, String> signalValues,
  ) {
    final raw = signalValues[cond.signalPath];
    if (raw == null) return false; // Signal not in snapshot.

    final signalInt = _parseVcdValue(raw);
    if (signalInt == null) return false; // x, z, or real value → unknown.

    final condInt = _parseConditionValue(cond.value);
    if (condInt == null) return false; // x/z condition literal never matches.

    return switch (cond.operator) {
      ConditionOperator.eq => signalInt == condInt,
      ConditionOperator.neq => signalInt != condInt,
      ConditionOperator.gt => signalInt > condInt,
      ConditionOperator.lt => signalInt < condInt,
      ConditionOperator.gte => signalInt >= condInt,
      ConditionOperator.lte => signalInt <= condInt,
      ConditionOperator.bitAnd => (signalInt & condInt) != BigInt.zero,
      ConditionOperator.bitOr => (signalInt & condInt) == condInt,
    };
  }

  // ── value parsing ───────────────────────────────────────────────────────────

  /// Parses a raw VCD bit-string into a [BigInt], or returns `null` for x/z
  /// or real-valued signals.
  ///
  /// Handles optional `b`/`B` prefix (VCD multi-bit notation).
  BigInt? _parseVcdValue(String raw) {
    var s = raw.toLowerCase();
    if (s.startsWith('b')) s = s.substring(1);
    if (s.isEmpty) return null;
    // Real-valued signals contain '.' — skip them.
    if (s.contains('.')) return null;
    // x/z anywhere in the string → unknown.
    if (s.contains('x') || s.contains('z')) return null;
    try {
      return BigInt.parse(s, radix: 2);
    } on FormatException {
      return null;
    }
  }

  /// Parses a numeric condition literal into a [BigInt], or returns `null` for
  /// x/z literals (e.g. `x`, `xx`, `bzz`) which never match any comparison.
  ///
  /// Supports `0x`/`0X` (hex), `0b`/`0B` (binary), and plain decimal.
  static BigInt? _parseConditionValue(String text) {
    // x/z literals are valid syntax but never satisfy any comparison.
    if (RegExp(r'^[xXzZ]+$').hasMatch(text)) return null;
    if (RegExp(r'^[bB][xXzZ]+$').hasMatch(text)) return null;
    if (text.startsWith('0x') || text.startsWith('0X')) {
      return BigInt.parse(text.substring(2), radix: 16);
    }
    if (text.startsWith('0b') || text.startsWith('0B')) {
      return BigInt.parse(text.substring(2), radix: 2);
    }
    return BigInt.parse(text);
  }

  // ── tokenizer ───────────────────────────────────────────────────────────────

  List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    var i = 0;

    while (i < input.length) {
      // Skip whitespace.
      if (input[i] == ' ' ||
          input[i] == '\t' ||
          input[i] == '\r' ||
          input[i] == '\n') {
        i++;
        continue;
      }

      final ch = input[i];

      // Parentheses.
      if (ch == '(') {
        tokens.add(const _Token(_TokenKind.lparen, '('));
        i++;
        continue;
      }
      if (ch == ')') {
        tokens.add(const _Token(_TokenKind.rparen, ')'));
        i++;
        continue;
      }

      // Two-character operators — must be checked before single-char.
      if (i + 1 < input.length) {
        final two = input.substring(i, i + 2);
        if (two == '==' || two == '!=' || two == '>=' || two == '<=') {
          tokens.add(_Token(_TokenKind.compOp, two));
          i += 2;
          continue;
        }
      }

      // Single-character operators.
      if (ch == '>') {
        tokens.add(const _Token(_TokenKind.compOp, '>'));
        i++;
        continue;
      }
      if (ch == '<') {
        tokens.add(const _Token(_TokenKind.compOp, '<'));
        i++;
        continue;
      }
      if (ch == '&') {
        tokens.add(const _Token(_TokenKind.compOp, '&'));
        i++;
        continue;
      }
      if (ch == '|') {
        tokens.add(const _Token(_TokenKind.compOp, '|'));
        i++;
        continue;
      }

      // Hex literal: 0x...
      if (ch == '0' &&
          i + 1 < input.length &&
          (input[i + 1] == 'x' || input[i + 1] == 'X')) {
        i += 2;
        final start = i;
        while (i < input.length && _isHexDigit(input[i])) {
          i++;
        }
        final digits = input.substring(start, i);
        if (digits.isEmpty) {
          throw FormatException(
            'Expected hex digits after "0x" at position ${i - 2}',
          );
        }
        tokens.add(_Token(_TokenKind.value, '0x$digits'));
        continue;
      }

      // Binary literal: 0b...
      if (ch == '0' &&
          i + 1 < input.length &&
          (input[i + 1] == 'b' || input[i + 1] == 'B')) {
        i += 2;
        final start = i;
        while (i < input.length && (input[i] == '0' || input[i] == '1')) {
          i++;
        }
        final digits = input.substring(start, i);
        if (digits.isEmpty) {
          throw FormatException(
            'Expected binary digits after "0b" at position ${i - 2}',
          );
        }
        tokens.add(_Token(_TokenKind.value, '0b$digits'));
        continue;
      }

      // Decimal literal.
      if (_isDigit(ch)) {
        final start = i;
        while (i < input.length && _isDigit(input[i])) {
          i++;
        }
        tokens.add(_Token(_TokenKind.value, input.substring(start, i)));
        continue;
      }

      // Identifier: keyword (AND, OR, NOT) or signal path.
      if (_isIdentStart(ch)) {
        final start = i;
        while (i < input.length && _isIdentPart(input[i])) {
          i++;
        }
        final word = input.substring(start, i);
        if (word == 'AND' || word == 'OR' || word == 'NOT') {
          tokens.add(_Token(_TokenKind.keyword, word));
        } else {
          tokens.add(_Token(_TokenKind.signal, word));
        }
        continue;
      }

      throw FormatException(
        'Unexpected character "$ch" at position $i',
      );
    }

    return tokens;
  }

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57; // '0'–'9'
  }

  static bool _isHexDigit(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 48 && code <= 57) || // '0'–'9'
        (code >= 65 && code <= 70) || // 'A'–'F'
        (code >= 97 && code <= 102); // 'a'–'f'
  }

  static bool _isIdentStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // 'A'–'Z'
        (code >= 97 && code <= 122) || // 'a'–'z'
        code == 95; // '_'
  }

  /// Continues an identifier: letters, digits, `_`, `.`, `[`, `]`, `:`.
  ///
  /// Covers fully-qualified signal paths like `top.cpu.data[7:0]`.
  static bool _isIdentPart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // 'A'–'Z'
        (code >= 97 && code <= 122) || // 'a'–'z'
        (code >= 48 && code <= 57) || // '0'–'9'
        code == 95 || // '_'
        code == 46 || // '.'
        code == 91 || // '['
        code == 93 || // ']'
        code == 58; // ':'
  }
}

// ── token types ───────────────────────────────────────────────────────────────

enum _TokenKind {
  keyword, // AND, OR, NOT
  compOp, // ==, !=, >, <, >=, <=, &, |
  value, // 0x…, 0b…, decimal
  signal, // identifier (signal path)
  lparen,
  rparen,
}

class _Token {
  const _Token(this.kind, this.text);
  final _TokenKind kind;
  final String text;

  @override
  String toString() => '${kind.name}("$text")';
}

// ── recursive-descent parser ──────────────────────────────────────────────────

/// Parses a flat token list into a [PatternExpression] tree.
///
/// Grammar (lowest to highest precedence):
/// ```text
/// or_expr  := and_expr ('OR' and_expr)*
/// and_expr := not_expr ('AND' not_expr)*
/// not_expr := 'NOT' not_expr | primary
/// primary  := signal_path compOp value | '(' or_expr ')'
/// ```
class _ExpressionParser {
  _ExpressionParser(this._tokens);

  final List<_Token> _tokens;
  int pos = 0;

  bool get isAtEnd => pos >= _tokens.length;
  String get currentText => isAtEnd ? '<end>' : _tokens[pos].text;

  PatternExpression parseOr() {
    var left = _parseAnd();
    while (_check(_TokenKind.keyword, 'OR')) {
      pos++;
      final right = _parseAnd();
      left = OrExpression(left: left, right: right);
    }
    return left;
  }

  PatternExpression _parseAnd() {
    var left = _parseNot();
    while (_check(_TokenKind.keyword, 'AND')) {
      pos++;
      final right = _parseNot();
      left = AndExpression(left: left, right: right);
    }
    return left;
  }

  PatternExpression _parseNot() {
    if (_check(_TokenKind.keyword, 'NOT')) {
      pos++;
      return NotExpression(operand: _parseNot());
    }
    return _parsePrimary();
  }

  PatternExpression _parsePrimary() {
    // Parenthesised sub-expression.
    if (_check(_TokenKind.lparen)) {
      pos++;
      final expr = parseOr();
      _expect(_TokenKind.rparen, ')');
      return expr;
    }

    // Signal condition: signal_path compOp value
    if (_check(_TokenKind.signal)) {
      final signalPath = _tokens[pos].text;
      pos++;

      if (isAtEnd || _tokens[pos].kind != _TokenKind.compOp) {
        throw FormatException(
          'Expected comparison operator after signal path "$signalPath"',
        );
      }
      final opText = _tokens[pos].text;
      pos++;

      // Accept a numeric value token, OR an x/z-only identifier that the
      // tokenizer classified as _TokenKind.signal (since x/z start with a letter).
      final nextIsValue = !isAtEnd && _tokens[pos].kind == _TokenKind.value;
      final nextIsXz =
          !isAtEnd &&
          _tokens[pos].kind == _TokenKind.signal &&
          RegExp(r'^[xXzZ]+$').hasMatch(_tokens[pos].text);

      if (!nextIsValue && !nextIsXz) {
        throw FormatException(
          'Expected numeric value after operator "$opText"',
        );
      }
      final valueText = _tokens[pos].text;
      pos++;

      // Validate numeric literals (catches e.g. empty hex "0x").
      // _parseConditionValue returns null for x/z — no exception, no problem.
      try {
        PatternSearchService._parseConditionValue(valueText);
      } on FormatException {
        throw FormatException('Invalid numeric literal: "$valueText"');
      }

      return SignalCondition(
        signalPath: signalPath,
        operator: _operatorFor(opText),
        value: valueText,
      );
    }

    throw FormatException(
      'Expected signal path or "(" but got "$currentText"',
    );
  }

  bool _check(_TokenKind kind, [String? text]) {
    if (isAtEnd) return false;
    final t = _tokens[pos];
    return t.kind == kind && (text == null || t.text == text);
  }

  void _expect(_TokenKind kind, String text) {
    if (isAtEnd || _tokens[pos].kind != kind || _tokens[pos].text != text) {
      throw FormatException('Expected "$text" but got "$currentText"');
    }
    pos++;
  }

  static ConditionOperator _operatorFor(String text) => switch (text) {
    '==' => ConditionOperator.eq,
    '!=' => ConditionOperator.neq,
    '>' => ConditionOperator.gt,
    '<' => ConditionOperator.lt,
    '>=' => ConditionOperator.gte,
    '<=' => ConditionOperator.lte,
    '&' => ConditionOperator.bitAnd,
    '|' => ConditionOperator.bitOr,
    _ => throw FormatException('Unknown comparison operator: "$text"'),
  };
}
