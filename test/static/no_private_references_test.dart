// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: this public repository points at nothing a reader cannot
/// open.
///
/// The suite is built from public repositories (this one, `crux-shared`,
/// `crux-vscode`, `edacrux-edu-packs`, the sibling open-core products) and
/// private ones (the Pro overlays, the planning repository, the websites and
/// the backend services). A reference to the private side — a repository
/// path, a plan section, a work-stream or audit id — reads as an explanation
/// to its author and as a dead end to everyone else. So the reasoning is
/// stated where it is needed, the Pro overlay is called "the Pro overlay",
/// public specifications are cited by their published URL (the CXP
/// specification is `https://edacrux.app/cxp`), and nothing is cited by a
/// private id.
///
/// Scope: every file `git ls-files` reports, except binaries, files over
/// [_maxBytes] (fixture data), generated code, the `crux-shared` submodule
/// (it runs its own copy of this guard) and vendored third-party trees.
///
/// A file may be exempted from specific rules only through [_allowlist],
/// with the reason recorded beside it.
void main() {
  test('tracked files name no private repository, plan or tracking id', () {
    final findings = <String>[];
    for (final path in _trackedTextFiles()) {
      final text = _readText(path);
      if (text == null) continue;
      for (final finding in _scan(text)) {
        final exempt = _allowlist[path]?.rules.contains(finding.rule) ?? false;
        if (exempt) continue;
        findings.add('$path:${finding.line} [${finding.rule}] ${finding.text}');
      }
    }
    expect(
      findings,
      isEmpty,
      reason:
          'A public file references something only the private side of the '
          'suite can open. Name the Pro overlay as "the Pro overlay", link a '
          'public specification by its URL, and state the reason inline '
          'instead of pointing at a plan section, a phase, or a work-stream, '
          'prompt or audit id:\n${findings.join('\n')}',
    );
  });

  test('every allowlist entry still exempts a real finding', () {
    final stale = <String>[];
    for (final entry in _allowlist.entries) {
      final text = File(entry.key).existsSync() ? _readText(entry.key) : null;
      final hits = text == null
          ? const <_Finding>[]
          : _scan(text).where((f) => entry.value.rules.contains(f.rule));
      if (hits.isEmpty) stale.add('${entry.key} (${entry.value.reason})');
    }
    expect(
      stale,
      isEmpty,
      reason:
          'These allowlist entries exempt nothing any more — delete them:\n'
          '${stale.join('\n')}',
    );
  });

  group('the rules', () {
    // Planted references. This file is excluded from the scan above, so the
    // samples can be written out in full.
    const planted = <String, String>{
      'private-repo': 'see `edacrux/docs/strategy/x.md` for why',
      'private-repo overlay': 'the `wavecrux-pro` overlay registers these',
      'private-plan': 'rationale in the WaveCrux project plan §4.2',
      'plan-phase': 'shipped in Phase 4.15',
      'plan-phase suffix': 'board drops (Phase 3c) win',
      'plan-phase hyphen': 'documents written before post-Phase-4.16',
      'tracking-id': 'the cross-probe panel (WS-B)',
      'architecture-gap': 'see ARCHITECTURE.md §4.11.7',
    };

    for (final entry in planted.entries) {
      test('catch a planted ${entry.key} reference', () {
        expect(_scan(entry.value), isNotEmpty, reason: entry.value);
      });
    }

    test('leave public references alone', () {
      const clean = [
        'CXP §9.9 (https://edacrux.app/cxp#sec-9-9)',
        'published at https://docs.wavecrux.app and https://edacrux.app/terms',
        'the closed-source Pro overlay overrides this provider',
        'the public `crux-shared` and `edacrux-edu-packs` repositories',
        'per ARCHITECTURE.md §3.1.8.5 and §6.4',
        'Wishbone B4 §3.1.3 and GitHub issue #44',
      ];
      for (final line in clean) {
        expect(_scan(line), isEmpty, reason: line);
      }
    });
  });
}

/// Files above this size are fixture data (multi-megabyte VCDs), not prose.
const int _maxBytes = 1024 * 1024;

/// Path prefixes that are not this repository's own text.
const _skippedPrefixes = [
  // The shared-packages submodule; it carries its own copy of this guard.
  'crux-shared/',
  // Vendored third-party crates, kept byte-identical to upstream.
  'native/vendor/',
];

/// This guard's own source, whose rule table necessarily spells every
/// pattern out.
const _self = 'test/static/no_private_references_test.dart';

/// Exact file → the rules it is exempt from, and why.
///
/// Empty on purpose. An entry is for a public name that happens to match a
/// rule — the shipped `lintcrux-pro` / `simcrux-pro` command-line tools, say,
/// named in a file that documents invoking them — never for a reference that
/// could be restated. Shape:
///
///     'docs/cli.md': _Allowance({'private-repo'},
///         'Names the shipped `lintcrux-pro` executable a user runs.'),
const _allowlist = <String, _Allowance>{};

class _Allowance {
  const _Allowance(this.rules, this.reason);

  final Set<String> rules;
  final String reason;
}

class _Rule {
  const _Rule(this.name, this.pattern);

  final String name;
  final RegExp pattern;
}

class _Finding {
  const _Finding(this.rule, this.line, this.text);

  final String rule;
  final int line;
  final String text;
}

final _rules = <_Rule>[
  // Private repositories, by path or by name. `edacrux/` is the planning
  // repository; `edacrux.app/` and `edacrux-edu-packs` are public and do not
  // match.
  _Rule('private-repo', RegExp(r'(?<![\w.:/@-])edacrux/')),
  _Rule('private-repo', RegExp(r'Ferrite-Engineering/edacrux(?![\w-])')),
  _Rule(
    'private-repo',
    RegExp(
      r'\b(?:wavecrux|netcrux|lintcrux|simcrux)-pro\b',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'private-repo',
    RegExp(
      r'\b(?:wavecrux|netcrux|lintcrux|simcrux|edacrux|ferrite)-website\b|'
      r'\*-website\b',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'private-repo',
    RegExp(
      r'\b(?:crux-updates|crux-commerce|wavecrux-updates|pulsecrux|anneal|'
      r'vcd_parser)\b',
      caseSensitive: false,
    ),
  ),
  // The beta repos close at the open-core flip (L4): they are the beta
  // cohort's public record, and archived-then-private is a 404 to anyone
  // who follows a link into one.
  _Rule(
    'private-repo',
    RegExp(
      r'\b(?:wavecrux|netcrux|lintcrux|simcrux)-beta\b',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'private-repo',
    RegExp(
      r'\b(?:private|separate) (?:planning|docs|documentation) repo',
      caseSensitive: false,
    ),
  ),
  // Private plans and their section, phase and charter citations.
  _Rule(
    'private-plan',
    RegExp(
      r'\b(?:project|suite|strategic|ecosystem|business|product|'
      'commercial[-_ ]launch|editor-integration|VSCode pack|ISA pack|launch)'
      r'[-_ ]plan\b|ECOSYSTEM_PLAN|development_plan\b|\bdev plan\b|\bplan §',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'private-plan',
    RegExp(
      r'\bconsistency[-_ ]charter\b|\bcharter §|\bexecution[- ]prompts?\b',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'plan-phase',
    RegExp(r'\bPhase[ -](?:\d+[a-z]?(?:\.\d+)*|[A-C]\d?)\b'),
  ),
  // ARCHITECTURE.md has no §1, §4, §7 or §11; those numbers were the roadmap's.
  _Rule(
    'architecture-gap',
    RegExp(r'ARCHITECTURE(?:\.md)?`?\s*§\s?(?:1|4|7|11)(?:\.\d+)*\b'),
  ),
  // Work-stream, prompt, ruling, campaign and audit identifiers.
  _Rule(
    'tracking-id',
    RegExp(
      r'\bWS-[A-H]\b|\bWS\d\b|\b[Pp]rompt [A-Z]?\d+(?:\.\d+)?\b|'
      r'\bR-CS\d+\b|\bCS\d{1,2}\b|§[A-Z]\d\b|\bIssue-\d+\b|'
      r'\bbeta bug [A-Z]?\d+\b|\bF-\d{2,3}\b|\(P\d{1,3}\)|'
      r'\b(?:adoption|migration), Session \d+\b',
    ),
  ),
  _Rule(
    'tracking-id',
    RegExp(
      r'\bCross-Probe Increment\b|\b(?:lift|motion|quality) campaign\b|'
      r'\bcampaign item\b|\bruling [A-Z]\d+\b|\bconsistency (?:pass|ruling)\b',
      caseSensitive: false,
    ),
  ),
];

List<_Finding> _scan(String text) {
  final findings = <_Finding>[];
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }
  int lineOf(int offset) {
    var lo = 0;
    var hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  for (final rule in _rules) {
    for (final match in rule.pattern.allMatches(text)) {
      findings.add(
        _Finding(rule.name, lineOf(match.start), match.group(0)!.trim()),
      );
    }
  }
  findings.sort((a, b) => a.line.compareTo(b.line));
  return findings;
}

Iterable<String> _trackedTextFiles() {
  final result = Process.runSync('git', ['ls-files', '-z']);
  if (result.exitCode != 0) {
    fail('git ls-files failed (${result.exitCode}): ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\x00')
      .where((path) => path.isNotEmpty)
      .where((path) => path != _self)
      .where((path) => !_skippedPrefixes.any(path.startsWith))
      .where((path) => !path.endsWith('.g.dart'))
      .where((path) => !path.startsWith('lib/l10n/generated/'))
      .where(FileSystemEntity.isFileSync);
}

/// The file's text, or null for a binary or an oversized data file.
String? _readText(String path) {
  final file = File(path);
  if (file.lengthSync() > _maxBytes) return null;
  final bytes = file.readAsBytesSync();
  final probe = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < probe; i++) {
    if (bytes[i] == 0) return null;
  }
  return utf8.decode(bytes, allowMalformed: true);
}
