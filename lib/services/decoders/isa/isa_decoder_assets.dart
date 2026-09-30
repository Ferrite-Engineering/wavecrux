// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Loads and caches the bundled instruction-set TOML files at app startup so
// the synchronous ProtocolDecoder.decode() path has all instruction-set data
// available without async I/O.
//
// Per the JKU instruction-decoder design, "extension set + XLEN" is
// expressed as "which TOML files you bundle" — the schema has no runtime
// extension toggles. This class is responsible for discovering and loading
// every TOML bundled for one architecture at startup; the [RiscvDecoder]
// composes the relevant subset per-instance based on its DecoderConfig.
//
// The architecture is a parameter rather than a hardcoded path segment
// ([kDefaultIsaArchitecture], `riscv`). RISC-V is the only architecture
// WaveCrux bundles; the parameter exists so the namespace is not welded to
// one ISA, not as an invitation to add more.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:meta/meta.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/user_isa_tables.dart';

/// Root asset directory holding one subdirectory per bundled architecture.
const String kIsaDecoderAssetRoot = 'assets/decoders/isa';

/// The only architecture WaveCrux bundles, and the default for
/// [IsaDecoderAssets.loadFromBundle].
const String kDefaultIsaArchitecture = 'riscv';

/// Environment variable naming extra ISA table directories, path-list
/// separated (`:` on Unix, `;` on Windows).
///
/// Mirrors `WAVECRUX_DECODER_PATH` for decoder plugins, so a CI job or a shared
/// team setup can point at a checked-in table directory without every engineer
/// configuring the same path by hand.
///
/// Declared here rather than in the `dart:io` half so both sides of the
/// conditional export present the same surface and the name cannot drift.
const String kIsaTablePathEnvVar = 'WAVECRUX_ISA_PATH';

/// Canonical load order for discovered instruction-set assets.
///
/// **Load order is semantics, not cosmetics.** `InstructionDisassembler`
/// resolves an encoding matched by more than one set by "last match wins",
/// so a set loaded later overrides an earlier one. `AssetManifest` makes no
/// ordering guarantee, so discovery must impose one explicitly.
///
/// The rule:
///
/// 1. Ascending by the first run of digits in the asset base name — the
///    register width the set is named for. A narrower base set therefore
///    always loads *before* its wider sibling, so the wider sibling wins any
///    overlap. That is precisely the RV32I-before-RV64I relationship the
///    RISC-V corpus depends on: `RV64I.toml` re-declares `slli`/`srli`/`srai`
///    with a 6-bit shamt and must override `RV32I.toml`'s 5-bit form.
/// 2. Ties broken by case-sensitive lexicographic order on the base name, so
///    the result is a *total* order with no residual dependence on the
///    manifest's iteration order.
///
/// `test/services/decoders/isa/isa_set_load_order_test.dart` proves
/// mechanically — by intersecting every cross-set (mask, match) pair — that
/// RV32I-vs-RV64I `slli`/`srli`/`srai` are the *only* cross-set encoding
/// ambiguities in the bundled corpus, so this comparator fully determines
/// decode behavior. If a future TOML introduces another ambiguity that guard
/// fails rather than letting the ordering silently decide it.
int compareIsaSetNames(String a, String b) {
  final wa = _leadingWidth(a);
  final wb = _leadingWidth(b);
  if (wa != wb) return wa.compareTo(wb);
  return a.compareTo(b);
}

/// First run of digits in [name] as an int, or -1 when the name carries no
/// digits (such a set sorts before every width-tagged one).
int _leadingWidth(String name) {
  final match = RegExp(r'\d+').firstMatch(name);
  if (match == null) return -1;
  return int.tryParse(match.group(0)!) ?? -1;
}

/// Cache of loaded instruction sets keyed by canonical asset name
/// (e.g. `"RV32I"`, `"RV64I"`, `"RV32C-lower"`).
///
/// Iteration order of [availableSets] is the canonical load order defined by
/// [compareIsaSetNames] — callers that build an `InstructionDisassembler`
/// from the whole corpus inherit correct last-match-wins behavior.
/// One table that failed to load, kept so the UI can say which file and why.
///
/// The bundled corpus is ours and under test, so in practice this is empty —
/// its reason for existing is user-supplied tables, where a silently-skipped
/// file is indistinguishable from one that loaded and decoded nothing.
@immutable
class IsaTableLoadIssue {
  /// Creates an issue record.
  const IsaTableLoadIssue({
    required this.name,
    required this.source,
    required this.message,
  });

  /// The set name the file would have provided.
  final String name;

  /// Asset key or filesystem path the table came from.
  final String source;

  /// The parser's own message, which names the offending key path.
  final String message;

  @override
  String toString() => '$source: $message';
}

/// What a scan of the user's ISA table directories produced.
///
/// [scannedDirectories] is reported even when it yields nothing, because
/// "WaveCrux looked in these places" is the first thing an author whose table
/// did not appear needs to know — more often than not the answer is that the
/// file is somewhere else.
@immutable
class UserIsaTableLoadResult {
  /// Creates a result.
  const UserIsaTableLoadResult({
    required this.sets,
    required this.issues,
    required this.scannedDirectories,
  });

  /// Successfully parsed tables, keyed by set name.
  final Map<String, InstructionSet> sets;

  /// Tables that failed to parse, each naming its file and the reason.
  final List<IsaTableLoadIssue> issues;

  /// Directories actually scanned, in priority order.
  final List<String> scannedDirectories;
}

class IsaDecoderAssets {
  IsaDecoderAssets(
    this._sets, {
    this.architecture = kDefaultIsaArchitecture,
    this.issues = const <IsaTableLoadIssue>[],
    this.scannedUserDirectories = const <String>[],
    this.userSuppliedSets = const <String>{},
  });

  /// Test helper: build assets directly from in-memory InstructionSets.
  ///
  /// The map is re-sorted into [compareIsaSetNames] order so a test built
  /// from a literal map has the same ordering contract as a bundle load.
  factory IsaDecoderAssets.fromMap(
    Map<String, InstructionSet> sets, {
    String architecture = kDefaultIsaArchitecture,
  }) {
    final ordered = sets.keys.toList()..sort(compareIsaSetNames);
    return IsaDecoderAssets(<String, InstructionSet>{
      for (final name in ordered) name: sets[name]!,
    }, architecture: architecture);
  }

  /// The architecture these sets were loaded for.
  final String architecture;

  /// Tables that failed to load, in discovery order. Empty on a clean load.
  final List<IsaTableLoadIssue> issues;

  /// Directories scanned for user tables, in priority order. Empty when none
  /// were configured, and always empty on web.
  final List<String> scannedUserDirectories;

  /// Set names that came from a user directory rather than the bundle, so the
  /// UI can mark them and a diagnostics surface can say where a decode came
  /// from.
  final Set<String> userSuppliedSets;

  final Map<String, InstructionSet> _sets;

  /// Returns the [InstructionSet] for [assetName] or null if not loaded.
  InstructionSet? get(String assetName) => _sets[assetName];

  /// Set names successfully loaded, in canonical load order.
  Iterable<String> get availableSets => _sets.keys;

  /// Discovers and loads every `<root>/<architecture>/*.toml` file declared
  /// in the asset manifest. Per-file failures are isolated — a malformed
  /// file won't prevent siblings from loading. The caller is expected to
  /// surface a status to the user when a previously-available file fails to
  /// load.
  static Future<IsaDecoderAssets> loadFromBundle({
    String architecture = kDefaultIsaArchitecture,
    List<String> userTableDirectories = const <String>[],
  }) async {
    // The TOMLs are declared in wavecrux's own pubspec. They resolve at the
    // root key (`assets/decoders/isa/riscv/X.toml`) when wavecrux is the
    // running app, but under `packages/wavecrux/assets/decoders/isa/riscv/
    // X.toml` when wavecrux is consumed as a path dependency (e.g. by
    // the Pro overlay). Discover the actual keys via the asset manifest and only
    // ever `loadString` a key that exists: a *failed* rootBundle.loadString
    // surfaces an uncaught async asset error that flakily fails whichever
    // integration test it lands in (the cause of the intermittent Pro mobile-
    // decoder "did not load" reds).
    Set<String> available;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      available = manifest.listAssets().toSet();
    } on Object {
      available = const <String>{};
    }

    // Dual-path resolution: take whichever prefix actually carries the
    // architecture's TOMLs. The bare prefix wins when both are present.
    var discovered = const <String, String>{};
    for (final prefix in [
      '$kIsaDecoderAssetRoot/$architecture',
      'packages/wavecrux/$kIsaDecoderAssetRoot/$architecture',
    ]) {
      final hits = <String, String>{};
      for (final key in available) {
        if (!key.startsWith('$prefix/') || !key.endsWith('.toml')) continue;
        final tail = key.substring(prefix.length + 1);
        // Direct children only — the corpus has no nested directories.
        if (tail.contains('/')) continue;
        hits[tail.substring(0, tail.length - '.toml'.length)] = key;
      }
      if (hits.isNotEmpty) {
        discovered = hits;
        break;
      }
    }

    // Discovery order is undefined; the canonical comparator makes it a
    // total order before anything is loaded (see [compareIsaSetNames]).
    final names = discovered.keys.toList()..sort(compareIsaSetNames);

    final loaded = <String, InstructionSet>{};
    final issues = <IsaTableLoadIssue>[];
    for (final name in names) {
      try {
        final text = await rootBundle.loadString(discovered[name]!);
        loaded[name] = parseInstructionSetToml(text, sourceLabel: '$name.toml');
      } on Object catch (e) {
        // Isolated per file so a malformed sibling still loads — but
        // **recorded, not swallowed.** While every table in the tree was ours
        // and under test, silence was harmless; the moment a user drops in
        // their own table, a silently-skipped file looks identical to a table
        // that loaded and simply decoded nothing.
        issues.add(
          IsaTableLoadIssue(
            name: name,
            source: discovered[name]!,
            message: '$e',
          ),
        );
      }
    }
    // User tables are overlaid last and win a name collision.
    //
    // Winning is the point, not a side effect: someone who authors a table
    // named after a bundled set is replacing our version of it on purpose,
    // and the alternative — silently preferring ours — would look exactly like
    // the file never loaded. Their table is also appended after every bundled
    // one, which matters because the disassembler resolves last-match-wins, so
    // a table describing a custom instruction that overlaps a base encoding
    // takes precedence. That overlap is usually why the table exists.
    final user = await loadUserIsaTables(directories: userTableDirectories);
    loaded.addAll(user.sets);
    issues.addAll(user.issues);

    return IsaDecoderAssets(
      loaded,
      architecture: architecture,
      issues: issues,
      scannedUserDirectories: user.scannedDirectories,
      userSuppliedSets: user.sets.keys.toSet(),
    );
  }
}
