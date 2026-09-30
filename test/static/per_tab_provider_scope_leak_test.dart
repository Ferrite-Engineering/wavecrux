// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail against the "per-tab provider scope leak" bug class,
// scanning the open-core `lib/`. Identical in shape to the Pro overlay's copy;
// the source roots and the repo whose violations are reported differ per repo.
//
// WaveCrux gives every open tab its own child `ProviderContainer` whose
// per-tab providers are overridden by `wavecruxTabOverrides`
// (`lib/services/tabs/wavecrux_tab_overrides.dart`), with the Pro overlay
// adding `proTabOverrides`. Widgets in a
// tab's subtree read providers from that child container.
//
// THE BUG CLASS (GitHub issues #44, #17, #20):
// A provider whose body reads a per-tab provider (waveformSource, cursorState,
// signalGroups, cocotbLog, …) but which is NOT itself made per-tab is hoisted
// to the ROOT container and reads the EMPTY root-scope versions of those
// per-tab providers. The symptom is silent: no exception, just wrong output in
// every tab (every Stage widget renders "–", the value column blanks, the FSM
// diagram never highlights, the cocotb overlay shows another tab's markers).
//
// WHY UNIT TESTS DON'T CATCH IT:
// Every provider unit test builds a single FLAT `ProviderContainer` with the
// per-tab dependency overridden inline. With no parent container there is no
// fallthrough, so the scoping defect is structurally invisible. This is why the
// guard is static and source-driven.
//
// THE TWO WAYS A PROVIDER IS MADE PER-TAB:
//   (a) it is listed in `wavecruxTabOverrides` (`xProvider.overrideWith(…)`), OR
//   (b) it declares the per-tab seed in `@Riverpod(dependencies: [...])`, so
//       Riverpod auto-scopes it into any container that overrides that seed
//       (the `laneGeometry` / `signalValueAtCursor` pattern).
// A bare `@riverpod` reader that reads per-tab state and does NEITHER is a leak.
//
// ANALYSIS MODEL
// The scan resolves every library under the source roots with
// `package:analyzer` and works on elements, not on text. Four steps:
//
//  1. PROVIDER REGISTRY. A top-level variable is a provider when its static
//     type, or any of its supertypes, is declared in a riverpod library. That
//     is a type test, so it covers hand-written providers, generated providers
//     and families alike, and it does not depend on the variable being named
//     `…Provider`. Each provider is keyed by `<library uri>::<name>`, which is
//     stable across the two analysis contexts a cross-repo scan needs.
//
//  2. BODIES. A provider's build logic is whatever its initializer supplies:
//     an inline closure (scanned in place), a referenced top-level function, or
//     a `Notifier` class named by a `Foo.new` tear-off. For a `@riverpod`
//     declaration the generated variable lives in the library's `.g.dart` part,
//     so it is matched back to its annotated function or class by the
//     generator's naming convention within the same library. When that
//     annotation carries a `dependencies:` list the generated provider is
//     recorded as auto-scoped (mechanism (b) above).
//
//  3. READS. A read is a `watch`/`read`/`listen`/`refresh`/`invalidate`
//     invocation whose *receiver's static type* is riverpod's `Ref` or
//     `WidgetRef`. Testing the receiver's type rather than the token `ref` is
//     what makes a read through a stored `Ref` field visible. The provider being
//     read is then taken from every element referenced in the argument
//     expression, so a family applied to a run-time argument, a conditional and
//     a `.select(…)` chain all resolve to the underlying symbol.
//
//     Reads are collected over the call graph, not just the provider's own
//     body: every invocation resolving to a declaration inside the source roots
//     is followed, memoized per declaration and guarded against cycles. This is
//     what reaches a read hidden in a helper object, an extension method on
//     `Ref`, or a private method of the notifier. The reported reach names the
//     helper chain it travelled.
//
//     The analysis is deliberately a may-analysis: a run-time selection between
//     two providers contributes both. Over-approximating costs an occasional
//     allowlist entry; under-approximating reinstates the blind spot the guard
//     exists to close.
//
//  4. TAINT CLOSURE. A provider is tainted if it reads a per-tab provider or
//     any other tainted provider — a consumer reading only a leaky intermediate
//     inherits the leak without naming a seed anywhere in its own body. Every
//     tainted provider that is not itself per-tab (neither listed nor
//     auto-scoped via `dependencies:`) is a violation. Both the open-core `lib/`
//     and (when this repo is checked out as the Pro overlay's submodule) the
//     Pro `lib/` contribute definitions, so a chain crossing the repo boundary
//     still resolves.
//
// The shapes this model resolves are pinned by `scope_leak_shapes/shapes.dart`
// and asserted below, so a future simplification of the analysis cannot quietly
// reopen a closed blind spot.
//
// When this test fails it has almost certainly found a real latent bug. The fix
// is one line in `wavecruxTabOverrides` (`xProvider.overrideWith(…)`) or a
// `@Riverpod(dependencies: [...])` declaration on the provider. Add to the
// allowlist below ONLY for a provider that is intentionally root-scoped (an
// app-global service), with a documented reason.
//
// COST AND HOW TO RUN
// Resolving the tree costs roughly ten seconds per source root, which is why
// this file carries a raised timeout. It runs in the default suite; see
// `docs/ARCHITECTURE.md` if that ever has to change.

@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Providers that read per-tab state but are *intentionally* root-scoped, with
/// the reason they are exempt. Keep this list tiny and well-justified. Every
/// entry below is a genuinely root-scoped provider whose per-tab access is
/// either routed through the active tab's container at run time or performed by
/// a stored handler with a caller-supplied `Ref` — cases a provider-level
/// may-analysis over-approximates. Real leaks are fixed, not listed.
const Map<String, String> _allowlist = <String, String>{
  // The action-discovery surfaces (toolbar / menu bar / palette) live at the
  // root scope, so `fileLoaded` is derived from the active tab's `filePath`;
  // the `|| ref.watch(waveformIsLoadedProvider)` clause is documented as inert
  // in production (false at root) and exists only so widget tests can drive the
  // loaded-state branch. See the doc-comment on `actionContextProvider`.
  'actionContextProvider':
      'root action-context; the per-tab read is a documented inert '
      'test-only fallback (false at the root scope in production).',
  // The registry is a process-global tool set. Its handlers read per-tab state
  // through the `Ref` passed at TOOL-EXECUTION time (per-tab once the executing
  // controller is scoped), not during the registry build; the scanner attributes
  // those stored-closure reads to the registry provider.
  'aiToolRegistryProvider':
      'process-global AI tool registry; per-tab reads happen at tool-execution '
      'time via a caller-supplied per-tab Ref, not during the build.',
  // Root `keepAlive` collaboration bridge. Per-tab cursor/marker/identity access
  // is routed through the active tab container (`_activeContainer`), with the
  // stored root `_ref` used only as the non-tabbed-host / unit-test fallback.
  // The correct routing is validated by root_host_per_tab_scope_leak_test.dart.
  'collabViewerBridgeProvider':
      'root-host bridge; per-tab access routed through the active tab '
      'container, root Ref is the cleared unit-test fallback (see root_host '
      'guard).',
  // Root `keepAlive` CXP selection emitter, same shape as the collab bridge:
  // `_activeContainer?.read(...) ?? _ref.read(...)`, active-container first.
  'cxpSelectionEmitterProvider':
      'root-host CXP emitter; per-tab access routed through the active tab '
      'container, root Ref is the cleared unit-test fallback (see root_host '
      'guard).',
  'editorHostBridgeProvider':
      'root-host editor-host bridge; the per-tab reach is the SAME '
      'CxpSelectionEmitter allowlisted above, driving a different sink, and '
      'every inbound write goes through `readActive` — per-tab access is '
      'routed through the active tab container in both directions.',
};

void main() {
  late final ScopeGraph graph;

  setUpAll(() async {
    expect(
      Directory('lib').existsSync(),
      isTrue,
      reason: 'run this test from the package root (flutter test)',
    );
    graph = await ScopeGraph.resolve(_sourceRoots());
  });

  test('resolution covered the tree', () {
    expect(
      graph.unresolved,
      isEmpty,
      reason:
          'these libraries did not resolve, so any provider they declare is '
          'invisible to the scan — run `dart run build_runner build` and '
          '`flutter pub get`',
    );
    expect(
      graph.providers.length,
      greaterThan(80),
      reason:
          'sanity: far fewer providers than expected were registered, which '
          'means the registry, not the tree, changed',
    );
  });

  test(
    'no open-core provider reads per-tab state (directly or transitively) '
    'without being scoped per-tab',
    () {
      final perTab = _perTabSeedSet(graph);
      expect(
        perTab.length,
        greaterThan(40),
        reason:
            'sanity: expected a sizeable per-tab seed set; did the override '
            'file shape or path change?',
      );
      expect(
        perTab.map(graph.nameOf),
        containsAll(<String>[
          'waveformSourceProvider',
          'cursorStateProvider',
          'signalGroupsProvider',
          'cocotbLogProvider',
        ]),
      );

      // A provider is properly per-tab if it is listed in an override list
      // (seeded above) or auto-scoped via `@Riverpod(dependencies: [...])`.
      final scoped = <String>{...perTab, ...graph.autoScoped};

      final reach = taintClosure(graph.reads(), perTab);

      final violations = <_Leak>[];
      for (final entry in reach.entries) {
        if (scoped.contains(entry.key)) continue;
        final provider = graph.providers[entry.key]!;
        if (_allowlist.containsKey(provider.name)) continue;
        // Report only what this repo owns; the Pro overlay runs its own
        // scanner over its own `lib/`.
        if (!_isOpenCorePath(provider.path)) continue;
        violations.add(
          _Leak(
            provider.name,
            provider.path,
            <String>[for (final k in entry.value) graph.nameOf(k)],
            graph.viaFor(entry.value),
          ),
        );
      }

      if (violations.isNotEmpty) {
        violations.sort((a, b) => a.symbol.compareTo(b.symbol));
        final buf = StringBuffer()
          ..writeln('Per-tab provider scope leak(s) detected in open-core:')
          ..writeln();
        for (final v in violations) {
          buf
            ..writeln('  ${v.symbol}')
            ..writeln('    in ${v.path}')
            ..writeln('    per-tab reach: ${v.reach.join(' -> ')}');
          if (v.via.isNotEmpty) {
            buf.writeln('    read reached through: ${v.via.join(' > ')}');
          }
          buf.writeln();
        }
        buf
          ..writeln(
            'Each provider above is hoisted to the ROOT container and will '
            'read the empty root-scope versions of those per-tab providers, '
            'silently producing wrong output in every tab.',
          )
          ..writeln('Fix by EITHER:')
          ..writeln(
            '  (a) adding `<symbol>.overrideWith(<fn|Notifier.new>)` to '
            '`wavecruxTabOverrides`, OR',
          )
          ..writeln(
            '  (b) declaring the per-tab seed(s) in '
            '`@Riverpod(dependencies: [...])` on the provider.',
          )
          ..writeln(
            'If the provider is intentionally root-scoped (an app-global '
            'service), add it to `_allowlist` with a reason.',
          );
        fail(buf.toString());
      }
    },
  );

  test('scope-leak allowlist entries still exist as providers', () {
    final known = graph.providers.values.map((i) => i.name).toSet();
    for (final symbol in _allowlist.keys) {
      expect(
        known,
        contains(symbol),
        reason:
            'allowlisted provider `$symbol` no longer exists — remove or '
            'update its entry in _allowlist.',
      );
    }
  });

  test('taint closure propagates through intermediate providers', () {
    // Guards the guard: a two-hop chain (leaf -> middle -> per-tab seed) must
    // flag BOTH hops. A direct-reads-only scan flags `middle` and lets `leaf`
    // through — the escape path a transitively-leaking consumer would take.
    final reads = <String, List<ProviderRead>>{
      'middle': <ProviderRead>[ProviderRead('seed', const <String>[])],
      'leaf': <ProviderRead>[ProviderRead('middle', const <String>[])],
      'unrelated': <ProviderRead>[ProviderRead('root', const <String>[])],
      // A self-read must not taint (a notifier reading its own provider).
      'self': <ProviderRead>[ProviderRead('self', const <String>[])],
    };

    final reach = taintClosure(reads, <String>{'seed'});

    expect(reach.keys, containsAll(<String>['middle', 'leaf']));
    expect(reach.keys, isNot(contains('unrelated')));
    expect(reach.keys, isNot(contains('self')));
    expect(
      reach['leaf'],
      <String>['leaf', 'middle', 'seed'],
      reason: 'the reported reach must name every hop down to the seed',
    );
  });

  group('reach analysis resolves indirect reads', () {
    late final ScopeGraph shapes;
    late final Map<String, List<ProviderRead>> reads;

    setUpAll(() async {
      shapes = await ScopeGraph.resolve(<Directory>[
        Directory('test/static/scope_leak_shapes'),
      ]);
      expect(shapes.unresolved, isEmpty);
      reads = shapes.reads();
    });

    Set<String> readsOf(String provider) {
      final key = shapes.keyOf(provider);
      expect(key, isNotNull, reason: '`$provider` was not registered');
      return <String>{
        for (final r in reads[key] ?? const <ProviderRead>[])
          shapes.nameOf(r.target),
      };
    }

    // A `Ref` captured on a field is still a `Ref`; matching on the receiver's
    // type rather than the identifier `ref` is what makes this visible.
    test('through a Ref stored on a field', () {
      expect(readsOf('storedRefProvider'), contains('seedProvider'));
    });

    test('through a helper object taking a Ref', () {
      expect(readsOf('helperObjectProvider'), contains('seedProvider'));
    });

    test('through an extension method on Ref', () {
      expect(readsOf('extensionProvider'), contains('seedProvider'));
    });

    // May-analysis: a run-time choice between providers contributes every
    // candidate, so the per-tab one cannot hide behind the branch.
    test('through a run-time provider selection', () {
      expect(readsOf('runtimeSelectedProvider'), contains('seedProvider'));
    });

    test('through a family applied to a run-time argument', () {
      expect(readsOf('familyArgProvider'), contains('familyProvider'));
    });

    test('and reports the helper chain it travelled', () {
      final key = shapes.keyOf('helperObjectProvider')!;
      final read = reads[key]!.firstWhere(
        (r) => shapes.nameOf(r.target) == 'seedProvider',
      );
      expect(read.via, isNotEmpty);
    });

    test('without over-reporting a provider that reads only root state', () {
      expect(readsOf('decoyProvider'), isNot(contains('seedProvider')));
    });

    test('and the closure reaches a two-hop chain', () {
      final seed = shapes.keyOf('seedProvider')!;
      final reach = taintClosure(reads, <String>{seed});
      expect(reach.keys, contains(shapes.keyOf('leafProvider')));
      expect(reach.keys, isNot(contains(shapes.keyOf('decoyProvider'))));
    });
  });
}

/// Source roots contributing provider definitions to the read-graph. The Pro
/// overlay's `lib/` is included when this repo is checked out as the
/// Pro overlay's submodule, so a taint chain crossing the repo boundary still
/// resolves; a standalone open-core checkout scans open-core only.
List<Directory> _sourceRoots() {
  final roots = <Directory>[Directory('lib')];
  final proLib = Directory('../lib');
  if (proLib.existsSync() && File('../lib/overrides.dart').existsSync()) {
    roots.add(proLib);
  }
  return roots;
}

bool _isOpenCorePath(String path) => !path.startsWith('..');

/// The per-tab seed set: the open-core `wavecruxTabOverrides` symbols, unioned
/// with the Pro `proTabOverrides` symbols when the Pro overlay is present. A
/// provider re-bound per tab by *either* list is per-tab in a real tab
/// container, since `bootstrap` spreads both.
Set<String> _perTabSeedSet(ScopeGraph graph) {
  final seeds = graph.overrideTargets(
    'lib/services/tabs/wavecrux_tab_overrides.dart',
    null,
  );
  expect(
    seeds,
    isNotEmpty,
    reason: 'open-core per-tab override file is missing or changed shape',
  );
  if (File('../lib/overrides.dart').existsSync()) {
    seeds.addAll(
      graph.overrideTargets('../lib/overrides.dart', 'proTabOverrides'),
    );
  }
  return seeds;
}

class _Leak {
  _Leak(this.symbol, this.path, this.reach, this.via);
  final String symbol;
  final String path;

  /// The reach chain from this provider down to the per-tab seed it depends on.
  final List<String> reach;

  /// The helper declarations the first hop's read was found behind, if any.
  final List<String> via;
}

// ---------------------------------------------------------------------------
// Resolved-AST analysis
// ---------------------------------------------------------------------------

/// The Dart SDK the analyzer should resolve `dart:` libraries against. Under
/// `flutter test` the running executable is the Flutter tester, whose directory
/// is not an SDK, so the bundled `dart-sdk` is located explicitly.
String? _dartSdkPath() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (flutterRoot != null) p.join(flutterRoot, 'bin', 'cache', 'dart-sdk'),
    p.dirname(p.dirname(Platform.resolvedExecutable)),
  ];
  for (final candidate in candidates) {
    if (File(p.join(candidate, 'lib', 'core', 'core.dart')).existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// One provider-to-provider read edge, with the helper declarations the read
/// was found behind (empty when it is written in the provider's own body).
class ProviderRead {
  ProviderRead(this.target, this.via);

  final String target;
  final List<String> via;
}

/// A registered provider: its symbol, the repo-relative path of the library
/// declaring it, and the declarations supplying its build logic.
class ProviderInfo {
  ProviderInfo(this.key, this.name, this.path);

  final String key;
  final String name;
  final String path;
  final Set<String> bodies = <String>{};
  Expression? initializer;
}

/// The resolved provider read-graph over a set of source roots.
class ScopeGraph {
  ScopeGraph._();

  final Map<String, ProviderInfo> providers = <String, ProviderInfo>{};
  final List<String> unresolved = <String>[];

  /// Providers auto-scoped per tab via `@Riverpod(dependencies: [...])`.
  final Set<String> autoScoped = <String>{};

  final Map<String, _Decl> _decls = <String, _Decl>{};
  final Map<String, ResolvedUnitResult> _units = <String, ResolvedUnitResult>{};
  final Map<String, Map<String, String>> _generated =
      <String, Map<String, String>>{};
  final Map<String, _Scan> _scans = <String, _Scan>{};
  Map<String, List<ProviderRead>>? _reads;

  static Future<ScopeGraph> resolve(List<Directory> roots) async {
    final files = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final e in root.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) {
          files.add(p.normalize(e.absolute.path));
        }
      }
    }
    final graph = ScopeGraph._();
    if (files.isEmpty) return graph;
    final collection = AnalysisContextCollection(
      includedPaths: files,
      sdkPath: _dartSdkPath(),
    );
    for (final file in files) {
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedUnit(file);
      if (result is! ResolvedUnitResult) {
        graph.unresolved.add(p.relative(file));
        continue;
      }
      graph._units[p.normalize(result.path)] = result;
      result.unit.accept(_UnitVisitor(graph, result));
    }
    graph._linkGenerated();
    return graph;
  }

  String nameOf(String key) =>
      providers[key]?.name ?? key.substring(key.indexOf('::') + 2);

  String? keyOf(String name) {
    for (final e in providers.entries) {
      if (e.value.name == name) return e.key;
    }
    return null;
  }

  /// The helper chain recorded for the first hop of [reach], if the read was
  /// not written in that provider's own body.
  List<String> viaFor(List<String> reach) {
    if (reach.length < 2) return const <String>[];
    for (final r in reads()[reach[0]] ?? const <ProviderRead>[]) {
      if (r.target == reach[1]) return r.via;
    }
    return const <String>[];
  }

  /// Provider symbols appearing as `x.overrideWith(…)` targets in the library
  /// at [path], optionally restricted to the declaration of the top-level
  /// variable named [within].
  Set<String> overrideTargets(String path, String? within) {
    final unit = _units[p.normalize(File(path).absolute.path)];
    if (unit == null) return <String>{};
    AstNode scope = unit.unit;
    if (within != null) {
      for (final d in unit.unit.declarations) {
        if (d is TopLevelVariableDeclaration &&
            d.variables.variables.any((v) => v.name.lexeme == within)) {
          scope = d;
        }
      }
    }
    final out = <String>{};
    scope.accept(_OverrideVisitor(out));
    return out;
  }

  /// Every provider's read set, following the call graph out of its bodies.
  Map<String, List<ProviderRead>> reads() {
    final cached = _reads;
    if (cached != null) return cached;
    final out = <String, List<ProviderRead>>{};
    for (final info in providers.values) {
      final found = <String, List<String>>{};
      final own = _Scan();
      info.initializer?.accept(_ReadVisitor(this, own));
      for (final target in own.reads) {
        found.putIfAbsent(target, () => const <String>[]);
      }
      final seen = <String>{...info.bodies, ...own.callees};
      final queue = <_Frame>[
        // A body IS the provider's own code, so it adds no hop; a helper the
        // initializer calls is already one hop away.
        for (final k in info.bodies) _Frame(k, const <String>[]),
        for (final k in own.callees)
          if (!info.bodies.contains(k))
            _Frame(k, <String>[_decls[k]?.name ?? k]),
      ];
      while (queue.isNotEmpty) {
        final frame = queue.removeLast();
        final scan = _scan(frame.decl);
        for (final target in scan.reads) {
          found.putIfAbsent(target, () => frame.via);
        }
        for (final callee in scan.callees) {
          if (!seen.add(callee)) continue;
          queue.add(
            _Frame(callee, <String>[
              ...frame.via,
              _decls[callee]?.name ?? callee,
            ]),
          );
        }
      }
      out[info.key] = <ProviderRead>[
        for (final e in found.entries) ProviderRead(e.key, e.value),
      ];
    }
    return _reads = out;
  }

  _Scan _scan(String declKey) {
    final cached = _scans[declKey];
    if (cached != null) return cached;
    // Insert before walking so a recursive declaration terminates.
    final scan = _scans[declKey] = _Scan();
    _decls[declKey]?.node.accept(_ReadVisitor(this, scan));
    return scan;
  }

  void _linkGenerated() {
    for (final info in providers.values) {
      final library = info.key.substring(0, info.key.indexOf('::'));
      final decl = _generated[library]?[info.name];
      if (decl != null) info.bodies.add(decl);
    }
  }

  void _noteGenerated(String library, String provider, String declKey) {
    _generated.putIfAbsent(library, () => <String, String>{})[provider] =
        declKey;
  }
}

/// Fixed-point taint propagation. Returns, for every tainted provider, a
/// shortest reach path ending at the per-tab seed it depends on.
Map<String, List<String>> taintClosure(
  Map<String, List<ProviderRead>> reads,
  Set<String> perTab,
) {
  final reach = <String, List<String>>{};
  for (final entry in reads.entries) {
    for (final read in entry.value) {
      if (read.target == entry.key || !perTab.contains(read.target)) continue;
      reach[entry.key] = <String>[entry.key, read.target];
      break;
    }
  }
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in reads.entries) {
      if (reach.containsKey(entry.key)) continue;
      for (final read in entry.value) {
        if (read.target == entry.key) continue;
        final downstream = reach[read.target];
        if (downstream == null) continue;
        reach[entry.key] = <String>[entry.key, ...downstream];
        changed = true;
        break;
      }
    }
  }
  return reach;
}

class _Frame {
  _Frame(this.decl, this.via);
  final String decl;
  final List<String> via;
}

class _Decl {
  _Decl(this.name, this.node);
  final String name;
  final AstNode node;
}

class _Scan {
  final Set<String> reads = <String>{};
  final Set<String> callees = <String>{};
}

bool _isRiverpodLibrary(Uri? uri) =>
    uri != null && uri.toString().contains('riverpod');

/// True when [type] is, or inherits from, a type declared by riverpod — the
/// test that recognizes hand-written providers, generated providers and
/// families without depending on how the variable is named.
bool _isProviderType(DartType? type) {
  if (type is! InterfaceType) return false;
  if (_isRiverpodLibrary(type.element.library.uri)) return true;
  for (final supertype in type.element.allSupertypes) {
    if (_isRiverpodLibrary(supertype.element.library.uri)) return true;
  }
  return false;
}

/// True when [type] is riverpod's `Ref` or `WidgetRef`, however it was reached
/// — an inline parameter, a stored field, a captured local.
bool _isRefType(DartType? type) {
  if (type is! InterfaceType) return false;
  bool isRef(InterfaceElement element) {
    final name = element.name;
    return _isRiverpodLibrary(element.library.uri) &&
        (name == 'Ref' || name == 'WidgetRef');
  }

  if (isRef(type.element)) return true;
  for (final supertype in type.element.allSupertypes) {
    if (isRef(supertype.element)) return true;
  }
  return false;
}

/// True when [element] is a `Ref` member invoked without an explicit receiver
/// — the shape a `Ref` extension method takes, where `watch(x)` is an implicit
/// `this.watch(x)`.
bool _isImplicitRefReceiver(Element? element) {
  final enclosing = element?.enclosingElement;
  if (enclosing is InterfaceElement) return _isRefType(enclosing.thisType);
  if (enclosing is ExtensionElement) return _isRefType(enclosing.extendedType);
  return false;
}

const Set<String> _refMethods = <String>{
  'watch',
  'read',
  'listen',
  'listenManual',
  'refresh',
  'invalidate',
};

/// The registry key for a provider element, or null if [element] is not a
/// top-level provider variable.
String? _providerKey(Element? element) {
  var target = element;
  if (target is GetterElement) target = target.variable;
  if (target is SetterElement) target = target.variable;
  if (target is! TopLevelVariableElement) return null;
  if (!_isProviderType(target.type)) return null;
  final name = target.name;
  if (name == null) return null;
  return '${target.library.uri}::$name';
}

/// A stable key for a scannable declaration: its source file and name offset.
String? _declKey(Element? element) {
  if (element == null) return null;
  final fragment = element.firstFragment;
  final source = fragment.libraryFragment?.source.fullName;
  final offset = fragment.nameOffset;
  if (source == null || offset == null) return null;
  return '$source@$offset';
}

/// Registers provider definitions and every scannable declaration in one unit.
class _UnitVisitor extends RecursiveAstVisitor<void> {
  _UnitVisitor(this.graph, this.result);

  final ScopeGraph graph;
  final ResolvedUnitResult result;

  void _record(Element? element, String name, AstNode node) {
    final key = _declKey(element);
    if (key == null) return;
    graph._decls.putIfAbsent(key, () => _Decl(name, node));
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final element = variable.declaredFragment?.element;
      final key = _providerKey(element);
      if (key == null) continue;
      final info = graph.providers.putIfAbsent(
        key,
        () => ProviderInfo(
          key,
          element!.name!,
          p.relative(result.libraryElement.firstFragment.source.fullName),
        ),
      );
      final initializer = variable.initializer;
      if (initializer != null) {
        info.initializer = initializer;
        initializer.accept(_BodyReferenceVisitor(info));
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final element = node.declaredFragment?.element;
    final name = element?.name ?? '<function>';
    _record(element, name, node);
    _noteIfGenerated(node.metadata, name, element);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final element = node.declaredFragment?.element;
    _record(element, element?.name ?? '<method>', node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _record(node.declaredFragment?.element, '<constructor>', node);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    final name = element?.name ?? '<class>';
    _record(element, name, node);
    _noteIfGenerated(node.metadata, name, element);
    super.visitClassDeclaration(node);
  }

  /// A `@riverpod` function or class generates `<name>Provider` into the same
  /// library's `.g.dart` part; record the association so the generated variable
  /// picks up the annotated declaration as its body. When the annotation
  /// carries a `dependencies:` list the generated provider is also recorded as
  /// auto-scoped (Riverpod re-scopes it into any container overriding a listed
  /// seed).
  void _noteIfGenerated(
    NodeList<Annotation> metadata,
    String name,
    Element? element,
  ) {
    Annotation? riverpod;
    for (final a in metadata) {
      final n = a.name.name;
      if (n == 'riverpod' || n == 'Riverpod') {
        riverpod = a;
        break;
      }
    }
    if (riverpod == null || name.isEmpty) return;
    final key = _declKey(element);
    if (key == null) return;
    final generatedName =
        '${name[0].toLowerCase()}${name.substring(1)}Provider';
    final library = result.libraryElement.uri.toString();
    graph._noteGenerated(library, generatedName, key);
    final args = riverpod.arguments;
    final declaresDependencies =
        args != null &&
        args.arguments.any(
          (e) => e is NamedExpression && e.name.label.name == 'dependencies',
        );
    if (declaresDependencies) graph.autoScoped.add('$library::$generatedName');
  }
}

/// Attaches the declarations a provider's initializer names — `Foo.new` for a
/// notifier class, a bare identifier for a top-level build function — as that
/// provider's bodies.
class _BodyReferenceVisitor extends RecursiveAstVisitor<void> {
  _BodyReferenceVisitor(this.info);

  final ProviderInfo info;

  void _add(Element? element) {
    var target = element;
    if (target is ConstructorElement) target = target.enclosingElement;
    final key = _declKey(target);
    if (key != null) info.bodies.add(key);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is LocalFunctionElement ||
        element is TopLevelFunctionElement ||
        element is ConstructorElement) {
      _add(element);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    _add(node.constructorName.element);
    super.visitConstructorReference(node);
  }
}

/// Collects `ref.*` provider reads and outgoing call-graph edges from one
/// declaration.
class _ReadVisitor extends RecursiveAstVisitor<void> {
  _ReadVisitor(this.graph, this.scan);

  final ScopeGraph graph;
  final _Scan scan;

  void _addCallee(Element? element) {
    final key = _declKey(element);
    if (key != null && graph._decls.containsKey(key)) scan.callees.add(key);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final receiver = node.realTarget;
    final onRef = receiver != null
        ? _isRefType(receiver.staticType)
        : _isImplicitRefReceiver(node.methodName.element);
    if (_refMethods.contains(node.methodName.name) &&
        onRef &&
        node.argumentList.arguments.isNotEmpty) {
      node.argumentList.arguments.first.accept(
        _ProviderArgumentVisitor(graph, scan, <String>{}),
      );
    }
    _addCallee(node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    // An extension getter on `Ref` is a call site too.
    _addCallee(node.propertyName.element);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _addCallee(node.identifier.element);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _addCallee(node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _addCallee(node.element);
    super.visitFunctionExpressionInvocation(node);
  }
}

/// Resolves the provider(s) an argument expression denotes: a plain reference,
/// a family application, a conditional, or the result of a helper that returns
/// a provider.
class _ProviderArgumentVisitor extends RecursiveAstVisitor<void> {
  _ProviderArgumentVisitor(this.graph, this.scan, this.guard);

  final ScopeGraph graph;
  final _Scan scan;
  final Set<String> guard;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final key = _providerKey(node.element);
    if (key != null) scan.reads.add(key);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final key = _declKey(node.methodName.element);
    if (key != null && guard.add(key)) {
      graph._decls[key]?.node.accept(
        _ProviderArgumentVisitor(graph, scan, guard),
      );
    }
    super.visitMethodInvocation(node);
  }
}

/// Collects `x.overrideWith(…)` targets from an override list.
class _OverrideVisitor extends RecursiveAstVisitor<void> {
  _OverrideVisitor(this.out);

  final Set<String> out;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    const overrides = <String>{
      'overrideWith',
      'overrideWithValue',
      'overrideWithBuild',
    };
    if (overrides.contains(node.methodName.name)) {
      final receiver = node.realTarget;
      if (receiver is Identifier) {
        final key = _providerKey(receiver.element);
        if (key != null) out.add(key);
      }
    }
    super.visitMethodInvocation(node);
  }
}
