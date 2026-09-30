// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: a `finally` block that runs after an `await` reads no
// provider, and reaches through `ref` or `context` only behind a `mounted`
// check. The Pro overlay carries its own copy.
//
// A `finally` is the cleanup that has to run. The one this guard exists for
// ends `systemDialogInFlightProvider`, which is set while an OS file picker
// is up and makes the viewer absorb every pointer event. On Windows and Linux
// the app stays live behind the picker, so the widget that opened it can be
// disposed before the picker answers. Its `ref` then throws, and
// `finally { ref.read(systemDialogInFlightProvider.notifier).end(); }` throws
// before the flag clears: the viewer ignores the mouse for the rest of the
// session. A disposed `ProviderContainer` throws the same way, and so does
// `context` once its element is unmounted.
//
// THE RULE. Inside a `finally` block of an async function, anything that
// comes after an `await` (or `await for`) of that function:
//  * reads no provider: no `.read(...)`, `.watch(...)`, `.listen(...)`,
//    `.invalidate(...)` or `.refresh(...)` whose argument names a provider,
//    whatever the receiver. A `mounted` check is no fix here, because
//    skipping the read skips the cleanup. Read the notifier before the first
//    `await` and call it in the `finally`;
//  * uses `ref` or `context` only after a `mounted` reference earlier in the
//    same `finally` (`if (context.mounted) Navigator.pop(context);`). The
//    `.mounted` check itself is not a use.
// A use inside a closure in the `finally` counts: the closure runs later
// still.
//
// WHAT IT DOES NOT SEE. The scan is syntactic, a deliberate trade for speed
// and zero false alarms on this tree:
//  * a helper called from the `finally` that reads `ref` itself;
//  * a `ref` or `context` held under another name;
//  * a synchronous function that runs after an await elsewhere.
// The planted samples at the bottom pin what is and is not caught.
//
// When this fails, read what the `finally` needs before the first `await`:
// `final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();`
// and `inFlight.end();` in the `finally`. There is no allowlist.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Source roots scanned.
const _roots = ['lib'];

/// A floor on the `finally` blocks found after an `await`, so a scan that
/// silently stops finding them fails instead of passing vacuously.
const _minimumBlocks = 20;

void main() {
  test('no finally block reads a provider, ref or context after an await', () {
    final findings = <String>[];
    var scannedBlocks = 0;
    for (final root in _roots) {
      final dir = Directory(root);
      expect(dir.existsSync(), isTrue, reason: 'run from the package root');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !_isHandWritten(entity.path)) continue;
        final source = entity.readAsStringSync();
        if (!source.contains('finally')) continue;
        final result = scanFinallyAfterAwait(source, path: entity.path);
        scannedBlocks += result.blocks;
        for (final finding in result.findings) {
          findings.add('${p.normalize(entity.path)}:$finding');
        }
      }
    }
    expect(
      scannedBlocks,
      greaterThanOrEqualTo(_minimumBlocks),
      reason:
          'sanity: far fewer finally blocks than expected were scanned, so '
          'the scan, not the tree, changed',
    );
    expect(
      findings,
      isEmpty,
      reason:
          'A finally block reaches, after an await, through something that '
          'may be gone by then. When it throws, the rest of the cleanup never '
          'runs: for systemDialogInFlightProvider, the viewer then ignores '
          'every pointer event for the session. Read what the finally needs '
          'before the first await:\n${findings.join('\n')}',
    );
  });

  group('the rule', () {
    List<String> flagged(String body) => scanFinallyAfterAwait(
      'class S { Future<void> f() async { $body } }',
    ).findings;

    test('catches the in-flight flag ended through ref', () {
      expect(
        flagged(
          'try { await x(); } finally { '
          'ref.read(systemDialogInFlightProvider.notifier).end(); }',
        ),
        hasLength(1),
      );
    });

    test('catches a provider read through any receiver', () {
      expect(
        flagged(
          'try { await x(); } finally { '
          'container.read(systemDialogInFlightProvider.notifier).end(); }',
        ),
        hasLength(1),
      );
      expect(
        flagged('try { await x(); } finally { ref.invalidate(aProvider); }'),
        hasLength(1),
      );
    });

    test('does not accept a mounted check in front of a provider read', () {
      expect(
        flagged(
          'try { await x(); } finally { if (mounted) '
          'ref.read(systemDialogInFlightProvider.notifier).end(); }',
        ),
        hasLength(1),
        reason: 'skipping the read skips the cleanup',
      );
    });

    test('catches context used without a mounted check', () {
      expect(
        flagged('try { await x(); } finally { L10N.of(context); }'),
        hasLength(1),
      );
      expect(
        flagged(
          'try { await x(); } finally { '
          'ProviderScope.containerOf(context).dispose(); }',
        ),
        hasLength(1),
      );
    });

    test('catches an await before the try, or earlier in the finally', () {
      expect(
        flagged(
          'await x(); try { y(); } finally { '
          'ref.read(aProvider.notifier).end(); }',
        ),
        hasLength(1),
      );
      expect(
        flagged(
          'try { y(); } finally { await x(); '
          'ref.read(aProvider.notifier).end(); }',
        ),
        hasLength(1),
      );
    });

    test('catches a use inside a closure in the finally', () {
      expect(
        flagged(
          'try { await x(); } finally { '
          'later(() => ref.read(aProvider.notifier).end()); }',
        ),
        hasLength(1),
      );
    });

    test('accepts the notifier read before the await', () {
      expect(
        flagged(
          'final inFlight = ref.read(systemDialogInFlightProvider.notifier) '
          '..begin(); try { await x(); } finally { inFlight.end(); }',
        ),
        isEmpty,
      );
    });

    test('accepts ref or context behind a mounted check', () {
      expect(
        flagged(
          'try { await x(); } finally { '
          'if (context.mounted) Navigator.pop(context); }',
        ),
        isEmpty,
      );
      expect(
        flagged(
          'try { await x(); } finally { if (mounted) { useRef(ref); } }',
        ),
        isEmpty,
      );
    });

    test('ignores a finally no await precedes', () {
      expect(
        flagged(
          'try { y(); } finally { ref.read(aProvider.notifier).end(); } '
          'await x();',
        ),
        isEmpty,
      );
    });

    test('ignores a synchronous function', () {
      final result = scanFinallyAfterAwait(
        'class S { void f() { try { y(); } finally { '
        'ref.read(aProvider.notifier).end(); } } }',
      );
      expect(result.findings, isEmpty);
    });

    test('ignores an await in a nested function', () {
      expect(
        flagged(
          'final g = () async { await x(); }; try { y(); } finally { '
          'ref.read(aProvider.notifier).end(); }',
        ),
        isEmpty,
      );
    });

    test('ignores names that only look like ref or context', () {
      expect(
        flagged(
          'try { await x(); } finally { p.context.join(a, b); '
          'f(context: 1, ref: 2); raf.read(4); }',
        ),
        isEmpty,
      );
    });
  });
}

bool _isHandWritten(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.endsWith('.dart') &&
      !normalized.endsWith('.g.dart') &&
      !normalized.endsWith('.freezed.dart') &&
      !normalized.contains('/l10n/generated/');
}

/// The outcome of scanning one compilation unit.
class FinallyScan {
  FinallyScan(this.blocks, this.findings);

  /// How many `finally` blocks were found after an `await` in their function.
  final int blocks;

  /// `line: what` for each use that breaks the rule, one per line.
  final List<String> findings;
}

/// The methods whose provider argument makes a call a provider read.
const _providerMethods = {'read', 'watch', 'listen', 'invalidate', 'refresh'};

/// Scans [source] for `finally` blocks that, after an `await` in the same
/// function body, read a provider or use `ref` or `context` unguarded.
FinallyScan scanFinallyAfterAwait(String source, {String path = 'x.dart'}) {
  final unit = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  ).unit;
  final collector = _Collector();
  unit.accept(collector);

  var blocks = 0;
  final byLine = <int, String>{};
  for (final statement in collector.tries) {
    final block = statement.finallyBlock!;
    final body = _enclosingBody(statement);
    if (body == null || !body.isAsynchronous) continue;
    final gapEnds = [
      for (final gap in collector.gaps)
        if (_enclosingBody(gap.node) == body && gap.end <= block.end) gap.end,
    ];
    if (gapEnds.isEmpty) continue;
    blocks++;
    bool afterAwait(AstNode node) => gapEnds.any((end) => end <= node.offset);

    final uses = _FinallyUses();
    block.accept(uses);
    void report(AstNode node, String what) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      byLine.putIfAbsent(line, () => what);
    }

    for (final read in uses.providerReads) {
      if (afterAwait(read)) report(read, '${read.methodName.name}s a provider');
    }
    for (final id in uses.lifecycle) {
      if (!afterAwait(id)) continue;
      final guarded = uses.mounted.any((m) => m.offset < id.offset);
      if (!guarded) report(id, 'uses `${id.name}` with no mounted check');
    }
  }
  final lines = byLine.keys.toList()..sort();
  return FinallyScan(blocks, [for (final l in lines) '$l: ${byLine[l]}']);
}

/// One asynchronous gap: an `await` expression, or an `await for` loop, whose
/// gap ends at the `await` keyword (every iteration resumes after it).
class _Gap {
  _Gap(this.node, this.end);

  final AstNode node;
  final int end;
}

class _Collector extends RecursiveAstVisitor<void> {
  final tries = <TryStatement>[];
  final gaps = <_Gap>[];

  @override
  void visitTryStatement(TryStatement node) {
    if (node.finallyBlock != null) tries.add(node);
    super.visitTryStatement(node);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    gaps.add(_Gap(node, node.end));
    super.visitAwaitExpression(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    final keyword = node.awaitKeyword;
    if (keyword != null) gaps.add(_Gap(node, keyword.end));
    super.visitForStatement(node);
  }
}

/// What a `finally` block touches: provider reads, `ref` and `context` uses,
/// and `mounted` references.
class _FinallyUses extends RecursiveAstVisitor<void> {
  final providerReads = <MethodInvocation>[];
  final lifecycle = <SimpleIdentifier>[];
  final mounted = <SimpleIdentifier>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final args = node.argumentList.arguments;
    if (_providerMethods.contains(node.methodName.name) &&
        node.target != null &&
        args.isNotEmpty &&
        args.first.toSource().contains('Provider')) {
      providerReads.add(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (name == 'mounted') {
      mounted.add(node);
    } else if ((name == 'ref' || name == 'context') && _isUse(node)) {
      lifecycle.add(node);
    }
    super.visitSimpleIdentifier(node);
  }

  /// Whether [node] is a `ref` or `context` of its own: not a property of
  /// something else (`p.context`), not a named-argument label, and not the
  /// target of a `.mounted` check.
  static bool _isUse(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is Label) return false;
    if (parent is PrefixedIdentifier) {
      if (identical(parent.identifier, node)) return false;
      return parent.identifier.name != 'mounted';
    }
    if (parent is PropertyAccess) {
      if (identical(parent.propertyName, node)) return false;
      return parent.propertyName.name != 'mounted';
    }
    if (parent is MethodInvocation && identical(parent.methodName, node)) {
      return false;
    }
    return true;
  }
}

FunctionBody? _enclosingBody(AstNode node) {
  for (var n = node.parent; n != null; n = n.parent) {
    if (n is FunctionBody) return n;
  }
  return null;
}
