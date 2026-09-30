// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'import_graph.dart';

/// Every file under `lib/` is loaded by the program, or says why it is not.
///
/// ## The defect class this closes
///
/// A widget can be written, localized in five locales, covered by a dozen
/// tests, named in the architecture manual as one of four action surfaces —
/// and mounted nowhere. Its tests import it directly, so they stay green; its
/// doc comment says where it is used, so a reader believes it; the guard that
/// checks action reachability credits it with ninety-odd actions. This suite
/// once carried such a widget, a custom Stage widget renderer that had been
/// superseded by another, a sparkline whose own documentation named the strip
/// it was not in, and a pair of re-export shims kept "so existing imports keep
/// resolving" long after the last import had gone.
///
/// Per-feature tripwires cannot see this. They assert a file's *text*, and a
/// file that lost its last importer keeps its text. The only question that
/// catches it is the one the compiler asks: starting from `main`, which files
/// does the program load?
///
/// ## How
///
/// [ImportGraph] follows `import`, `export` and `part` from the entry points,
/// taking every branch of a conditional import. The entry points are the
/// program's real ones: `lib/main.dart` is the only `main` in `lib/`, it is
/// also the web entry, there is no `bin/`, and no isolate is started from a
/// URI or a `vm:entry-point` pragma — the worker isolates are spawned from
/// functions in files the walk already reaches. The last test below keeps that
/// claim honest.
///
/// ## Why an allowlist
///
/// A few files are correct and unreached: seams the Pro overlay consumes, a
/// bundle writer the repository's own tools run, a catalog the telemetry tests
/// of both repositories pin. Each entry carries its reason, and an entry whose
/// file is now reached — or gone — fails, so the list cannot outlive its facts.
const _exemptions = <_Exemption>[
  // ── Seams the Pro overlay consumes ────────────────────────────────────────
  // The open core declares the extension point and its inert default; only
  // the Pro overlay reads or overrides it. The overlay's own reachability
  // guard checks that each of these is still loaded by the overlay.
  _Exemption.proOverlay(
    'lib/core/license/license_tier_change_audit_listener.dart',
    'the licence-tier audit listener; only the Pro overlay has a tier that '
        'can change',
  ),
  _Exemption.proOverlay(
    'lib/core/providers/debug_advisor_service_provider.dart',
    'Debug Advisor extension point; the rule engine and its panel are Pro',
  ),
  _Exemption.proOverlay(
    'lib/domain/interfaces/debug_advisor_service.dart',
    'Debug Advisor interface the Pro rule engine implements',
  ),
  _Exemption.proOverlay(
    'lib/services/debug_advisor/noop_debug_advisor_service.dart',
    'default binding of the Debug Advisor extension point',
  ),
  _Exemption.proOverlay(
    'lib/features/collaboration/providers/host_auto_approve_lan_provider.dart',
    'collaboration host policy seam; the session UI is Enterprise',
  ),
  _Exemption.proOverlay(
    'lib/features/collaboration/providers/host_control_policy_provider.dart',
    'Presenter Mode host policy seam; the session UI is Enterprise',
  ),
  _Exemption.proOverlay(
    'lib/shared/widgets/wavecrux_edition_badge.dart',
    'the edition badge renders nothing at open core; the Pro overlay mounts '
        'it in the shared chrome',
  ),

  // ── Tooling and test data ─────────────────────────────────────────────────
  _Exemption(
    'lib/features/stage/bundle/widget_bundle_writer.dart',
    'the authoring side of the `.wcrux-widget` format. The app only reads '
        'bundles; tool/generate_tachometer_bundle.dart and '
        'tool/generate_community_widget_fixture.dart write the committed '
        'ones, and the Pro overlay integration test builds bundles with it, '
        'so it has to stay importable by package URI',
  ),
  _Exemption(
    'lib/services/telemetry/telemetry_event_catalog.dart',
    'the pinned event catalog. Nothing records from it — call sites spell '
        'event names as literals so the conformance scan can read them — but '
        'the conformance tests of this repository and of the Pro overlay both '
        'import it, and only a lib/ file is importable from both',
  ),
];

void main() {
  late ImportGraph graph;
  late List<String> libFiles;

  setUpAll(() {
    graph = ImportGraph.walk(
      root: '.',
      packageName: 'wavecrux',
      entryPoints: const ['lib/main.dart'],
    );
    libFiles = graph.libraryFiles();
  });

  test(
    'every lib/ file is reached from main, or is exempted with a reason',
    () {
      final exempt = {for (final e in _exemptions) e.file};
      final orphans = [
        for (final file in libFiles)
          if (!graph.reached.contains(file) && !exempt.contains(file)) file,
      ];
      expect(
        orphans,
        isEmpty,
        reason:
            'These files are not imported, exported or included as a part by '
            'anything lib/main.dart loads, so the app never runs them. A test '
            'that imports one directly keeps passing; that is how dead code '
            'stays green.\n'
            'Delete the file (and any test that only tested it), wire it in, '
            'or add an _Exemption with the reason it is legitimately '
            'unreached:\n  ${orphans.join('\n  ')}',
      );
    },
  );

  test('every exemption is still needed', () {
    final stale = <String>[];
    for (final e in _exemptions) {
      if (!libFiles.contains(e.file)) {
        stale.add('${e.file}: no longer exists — delete the exemption');
      } else if (graph.reached.contains(e.file)) {
        stale.add(
          '${e.file}: now reached from lib/main.dart — delete the exemption',
        );
      }
    }
    expect(stale, isEmpty, reason: stale.join('\n'));
  });

  test('each exemption is listed once', () {
    final seen = <String>{};
    final duplicates = [
      for (final e in _exemptions)
        if (!seen.add(e.file)) e.file,
    ];
    expect(duplicates, isEmpty);
  });

  test('the walk is not vacuous', () {
    // A broken directive parser or a moved entry point reaches almost
    // nothing, and every file then looks like an orphan — or, if the
    // enumeration broke too, nothing does.
    expect(graph.reached.length, greaterThan(700));
    expect(libFiles.length, greaterThan(700));
    expect(graph.reached, contains('lib/app.dart'));
    // Every branch of a conditional export is reached, the default included.
    expect(
      graph.reached,
      containsAll(<String>[
        'lib/services/waveform/lxt2fst_converter_stub.dart',
        'lib/services/waveform/lxt2fst_converter_web.dart',
        'lib/services/waveform/lxt2fst_converter_io.dart',
      ]),
    );
  });

  test('lib/main.dart is the only entry point', () {
    // The walk trusts that nothing else in lib/ starts a program. A second
    // `main`, an isolate spawned from a URI, or a pragma'd entry point would
    // each be a root the walk does not know about.
    final extraRoots = <String>[];
    for (final file in libFiles) {
      final code = stripComments(File(file).readAsStringSync());
      if (file != 'lib/main.dart' && _topLevelMain.hasMatch(code)) {
        extraRoots.add('$file: declares a top-level main()');
      }
      if (code.contains('spawnUri(')) {
        extraRoots.add('$file: spawns an isolate from a URI');
      }
      if (code.contains('vm:entry-point')) {
        extraRoots.add('$file: declares a vm:entry-point');
      }
    }
    expect(
      extraRoots,
      isEmpty,
      reason:
          'Add these as entry points of the walk above:\n'
          '${extraRoots.join('\n')}',
    );
  });
}

/// A `main` declared at column 0 — top level, as `dart format` lays it out.
final _topLevelMain = RegExp(r'^(?:[\w<>?]+\s+)?main\s*\(', multiLine: true);

/// One unreached `lib/` file and why that is correct.
class _Exemption {
  const _Exemption(this.file, this.reason);

  /// A seam the Pro overlay consumes. The overlay's reachability guard reads
  /// these entries back and fails if the overlay stops loading one, which is
  /// the half of the check this repository cannot run.
  const _Exemption.proOverlay(this.file, this.reason);

  final String file;
  final String reason;
}
