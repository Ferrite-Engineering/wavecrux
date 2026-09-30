// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The telemetry catalog's conformance guard.
//
// WHY THIS TEST EXISTS, AND WHY IT IS WORTH ITS LENGTH:
//
// The ingestion Worker validates every
// event it receives, and every one of its rejections is SILENT.
//
//   * An event NAME that fails `^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$` is skipped.
//     The batch still returns 202; the row is counted only in the response's
//     `dropped` field, which the client does not read and no dashboard shows.
//   * A property KEY that fails `^[a-z][a-z0-9_]{0,31}$`, or a VALUE that is
//     neither `[a-z0-9_]{1,64}`, nor a bool, nor an integer with |v| <= 100000,
//     is dropped while the event is KEPT. That is the worse failure: the
//     counter looks healthy and one of its dimensions is permanently empty.
//
// Nothing in the app, the queue, the response, or the SQL API can distinguish
// "nobody used this feature" from "every row was discarded at the edge". A
// capital letter in an event name — `debugAdvisor.suggestion.accepted`, which
// is what shipped before this test — costs the whole event, forever, with no
// error anywhere. So the grammar is asserted HERE, client-side, where a
// violation is a failing build instead of a quiet hole in the data.
//
// The rules enforced:
//
//  1. Every event name recorded anywhere in `lib/` appears in the pinned
//     `kWavecruxEventCatalog`. An undocumented event cannot ship.
//  2. Conversely, every catalog entry is still recorded somewhere (Pro-only
//     entries excepted, since they live in the other repo, and the shared
//     `app.uncaught_error`, which `crux_telemetry` records) — a catalog that
//     accumulates dead names stops being a description of the product.
//  3. Every catalog name matches the Worker's event-name class.
//  4. Every property key matches the Worker's property-key class.
//  5. Every enumerated property value matches the Worker's value class.
//  6. The catalog's enum-derived value sets equal what `telemetryEnumToken`
//     produces from the Dart enums they came from, so adding a camelCase
//     constant to `DisplayFormat` (or a new `WaveformFormat`) fails here
//     rather than losing a property at the edge.
//  7. No duplicate names; no event over the Worker's six-property cap.
//
// The scanner reads string literals passed to `TelemetryEvent(...)`, which is
// why instrumentation call sites spell their event names as literals rather
// than referencing constants: a constant would make rule 1 vacuous.

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/interfaces/debug_advisor_service.dart';
import 'package:wavecrux/features/viewer/widgets/export_dialog.dart';
import 'package:wavecrux/services/telemetry/telemetry_event_catalog.dart';

/// The ingestion Worker's `EVENT_NAME`.
final _eventName = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$');

/// The ingestion Worker's `PROPERTY_KEY`.
final _propertyKey = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

/// The ingestion Worker's `PROPERTY_VALUE`.
final _propertyValue = RegExp(r'^[a-z0-9_]{1,64}$');

/// The Worker's `MAX_PROPERTIES`.
const int _maxProperties = 6;

/// Matches the event-name argument of a `TelemetryEvent('…')` construction, or
/// of the workspace notifier's `_emit('…')` wrapper around one.
///
/// Single-quoted only — the house style throughout `lib/`, and a double-quoted
/// literal would be caught by the analyzer's quote lint first.
final _recordedEvent = RegExp(r"(?:TelemetryEvent|_emit)\(\s*'([^']+)'");

/// Every `TelemetryEvent(` construction, whether or not its first argument is
/// a literal. Used to prove the scanner above sees all of them.
final _anyConstruction = RegExp(r'TelemetryEvent\(');

/// The one place a `TelemetryEvent` is constructed from a variable rather than
/// a literal: the workspace notifier's `_emit` helper, whose callers pass the
/// literal instead and are matched by [_recordedEvent].
const String _indirectConstructionSite =
    'lib/features/workspace/providers/workspace_provider.dart';

/// Pipeline files that construct a [TelemetryEvent] from stored data rather
/// than recording one: the model's own declaration and the queue's decoder,
/// which rebuilds whatever a previous build wrote to disk. Neither is an
/// instrumentation call site, so neither is a name the catalog can pin.
const Set<String> _pipelineFiles = <String>{
  'lib/domain/models/telemetry_event.dart',
  'lib/services/telemetry/telemetry_event_queue.dart',
};

/// Catalog entries that live in the Pro overlay and so cannot be found by a
/// scan of this repository. The Pro repo runs the same rule-2 check over its
/// own tree against the same catalog.
const Set<String> _proOnlyEvents = <String>{
  'debug_advisor.suggestion.accepted',
  'debug_advisor.suggestion.dismissed',
  'sva.results_loaded',
  'ai_advisor.answered',
  'collab.session_shared',
  'collab.session_joined',
  'ethernet.pcap_exported',
  'ethernet.vcd_synthesized',
};

/// Catalog entries recorded by a shared package rather than by a call site in
/// either repository. `crux_telemetry` records `app.uncaught_error` from the
/// global error handlers, so no scan of this repository's `lib/` can find it,
/// and it is excused from the "still recorded" rule.
const Set<String> _sharedEvents = <String>{'app.uncaught_error'};

void main() {
  const catalog = kWavecruxEventCatalog;

  test('no duplicate catalog entries', () {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final event in catalog) {
      if (!seen.add(event.name)) duplicates.add(event.name);
    }
    expect(duplicates, isEmpty, reason: 'each event is listed once');
  });

  test('every catalog name matches the Worker event-name class', () {
    final bad = [
      for (final event in catalog)
        if (!_eventName.hasMatch(event.name)) event.name,
    ];
    expect(
      bad,
      isEmpty,
      reason:
          'The ingestion Worker drops these names without reporting anything, '
          'so the events would never arrive. Names are lowercase, '
          'dot-separated, two or three segments:\n'
          '${bad.join('\n')}',
    );
  });

  test('every property key matches the Worker property-key class', () {
    final bad = <String>[];
    for (final event in catalog) {
      for (final key in event.propertyKeys) {
        if (!_propertyKey.hasMatch(key)) bad.add('${event.name}.$key');
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          'A key outside the Worker property-key class is dropped while its '
          'event is kept — the counter survives and the dimension is silently '
          'empty:\n${bad.join('\n')}',
    );
  });

  test('every enumerated property value matches the Worker value class', () {
    final bad = <String>[];
    for (final event in catalog) {
      event.enumeratedValues.forEach((key, values) {
        for (final value in values) {
          if (!_propertyValue.hasMatch(value)) {
            bad.add('${event.name}.$key = $value');
          }
        }
      });
    }
    expect(
      bad,
      isEmpty,
      reason:
          'Values are identifiers from our own vocabulary — no capitals, no '
          'dots, no spaces — never a user-chosen string:\n${bad.join('\n')}',
    );
  });

  test('no event exceeds the Worker property cap', () {
    final over = [
      for (final event in catalog)
        if (event.propertyKeys.length > _maxProperties)
          '${event.name} (${event.propertyKeys.length})',
    ];
    expect(
      over,
      isEmpty,
      reason:
          'The Worker encodes at most $_maxProperties properties per event; '
          'the rest are dropped in key order:\n${over.join('\n')}',
    );
  });

  group('enum-derived vocabularies match their Dart enums', () {
    // Each of these pins a catalog value list to the enum it is derived from,
    // so a new constant cannot be added to the enum without the catalog being
    // updated in the same change.

    List<String> valuesFor(String event, String key) =>
        catalog.firstWhere((e) => e.name == event).enumeratedValues[key]!;

    test('file.opened.format covers every WaveformFormat', () {
      final fromEnum = WaveformFormat.values.map((v) => v.name).toSet();
      final fromCatalog = valuesFor('file.opened', 'format').toSet();
      expect(
        fromCatalog,
        containsAll(fromEnum),
        reason: 'a new reader format must be added to the catalog',
      );
      // The catalog carries exactly one token the enum does not: the streaming
      // transport, which resolves no container format at all.
      expect(fromCatalog.difference(fromEnum), <String>{'streaming'});
      // `WaveformFormat` constants are already lowercase, so the call site
      // emits `.name` directly. This asserts that remains true.
      expect(
        WaveformFormat.values.every((v) => _propertyValue.hasMatch(v.name)),
        isTrue,
        reason:
            'a camelCase WaveformFormat constant would be dropped by the '
            'Worker; route it through telemetryEnumToken if one is added',
      );
    });

    test('format.set.format is DisplayFormat under telemetryEnumToken', () {
      expect(
        valuesFor('format.set', 'format').toSet(),
        DisplayFormat.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('export.completed.kind covers every ExportFormat', () {
      expect(
        valuesFor('export.completed', 'kind').toSet(),
        ExportFormat.values.map((v) => v.name).toSet(),
      );
      expect(
        ExportFormat.values.every((v) => _propertyValue.hasMatch(v.name)),
        isTrue,
      );
    });

    test('search.used.mode covers every SearchMode, plus pattern', () {
      final signalModes = SearchMode.values
          .map((v) => 'signal_${telemetryEnumToken(v)}')
          .toSet();
      final fromCatalog = valuesFor('search.used', 'mode').toSet();
      expect(fromCatalog, containsAll(signalModes));
      expect(fromCatalog.difference(signalModes), <String>{'pattern'});
    });

    test('ai_advisor.answered.provider covers every AiProvider', () {
      expect(
        valuesFor('ai_advisor.answered', 'provider').toSet(),
        AiProvider.values.map((v) => v.name).toSet(),
      );
      // The constants are already lowercase, so the Pro call site emits
      // `.name`. A camelCase provider added later must go through
      // `telemetryEnumToken` instead — this is where that is caught.
      expect(
        AiProvider.values.every((v) => _propertyValue.hasMatch(v.name)),
        isTrue,
      );
    });

    test('tier.gate_hit.required is exactly the gateable tiers', () {
      // A gate can only ever demand a paid tier: `openCore` is never gated and
      // `edu` is Pro-equivalent for gating (`LicenseTierFeatures`), so no call
      // site can pass either. Deriving the expectation from `LicenseTier`
      // means a fifth tier fails here rather than reaching the Worker as a
      // value the catalog never declared.
      expect(
        valuesFor('tier.gate_hit', 'required').toSet(),
        LicenseTier.values
            .where((t) => t != LicenseTier.openCore && t != LicenseTier.edu)
            .map((t) => t.name)
            .toSet(),
      );
    });

    test('tier.gate_hit.feature is the pinned call-site vocabulary', () {
      // The list is shared with the call sites through one const, so this
      // guards the wiring rather than the spelling: an event whose `feature`
      // list drifted from `kWavecruxGateFeatureIds` would be a catalog that no
      // longer describes what the dialogs send.
      expect(
        valuesFor('tier.gate_hit', 'feature'),
        kWavecruxGateFeatureIds,
      );
      expect(
        kWavecruxGateFeatureIds.toSet(),
        hasLength(
          kWavecruxGateFeatureIds.length,
        ),
      );
    });

    test('debug_advisor rule_id and severity match their enums', () {
      expect(
        kDebugAdvisorRuleIdTokens.toSet(),
        DebugAdvisorRuleId.values.map(telemetryEnumToken).toSet(),
      );
      expect(
        valuesFor('debug_advisor.suggestion.accepted', 'severity').toSet(),
        DebugAdvisorSeverity.values.map(telemetryEnumToken).toSet(),
      );
      // Accepted and dismissed are the same measurement with opposite answers,
      // so their vocabularies must not diverge.
      expect(
        valuesFor('debug_advisor.suggestion.dismissed', 'rule_id'),
        valuesFor('debug_advisor.suggestion.accepted', 'rule_id'),
      );
    });
  });

  test('app.uncaught_error carries the shared counter vocabulary', () {
    // Recorded by `crux_telemetry`, not by this repository, so the lists are
    // the package's, exactly: the catalog references its constants, and this
    // holds it there, so a hand copy that drifted from what the counter
    // records (and the Worker admits) fails here. Four properties, no free
    // text, a catch-all in each open-ended dimension, and `none` for an error
    // with no framework library.
    final entry = catalog.firstWhere(
      (e) => e.name == kTelemetryUncaughtErrorEvent,
    );
    expect(entry.propertyKeys.toSet(), <String>{
      'source',
      'kind',
      'library',
      'silent',
    });
    expect(entry.boolProperties, <String>['silent']);
    expect(entry.intProperties, isEmpty);
    expect(entry.enumeratedValues['source'], kTelemetryUncaughtErrorSources);
    expect(entry.enumeratedValues['kind'], kTelemetryUncaughtErrorKinds);
    expect(
      entry.enumeratedValues['library'],
      kTelemetryUncaughtErrorLibraries,
    );
    expect(entry.enumeratedValues['kind'], contains('other'));
    expect(
      entry.enumeratedValues['library'],
      containsAll(<String>['none', 'other']),
    );
  });

  group('source scan', () {
    final recorded = <String, Set<String>>{};
    // Files holding a `TelemetryEvent(` the name scanner could not read a
    // literal out of. Exactly one is expected, and it is the `_emit` wrapper.
    final opaqueConstructions = <String>[];

    final libDir = Directory('lib');
    if (!libDir.existsSync()) {
      throw StateError('run from the package root (flutter test)');
    }
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('.g.dart')) continue;
      if (_pipelineFiles.contains(path)) continue;
      final source = entity.readAsStringSync();
      var literalConstructions = 0;
      for (final match in _recordedEvent.allMatches(source)) {
        recorded.putIfAbsent(match.group(1)!, () => <String>{}).add(path);
        if (match.group(0)!.startsWith('TelemetryEvent')) {
          literalConstructions++;
        }
      }
      final total = _anyConstruction.allMatches(source).length;
      for (var i = literalConstructions; i < total; i++) {
        opaqueConstructions.add(path);
      }
    }

    test('the scan found the instrumentation at all', () {
      // A regex that silently stops matching would turn the rules below into
      // tests that assert nothing, so assert the scanner is alive.
      expect(
        recorded.length,
        greaterThan(10),
        reason:
            'the TelemetryEvent scan matched almost nothing — the call-site '
            'idiom probably changed and this guard has gone blind',
      );
    });

    test('no event name is hidden from the scanner behind an indirection', () {
      // The closure property that makes "every recorded name is in the
      // catalog" mean something: an event constructed from a variable is an
      // event this file cannot see, and so an event that could ship
      // undocumented. One such indirection exists by design.
      expect(
        opaqueConstructions,
        <String>[_indirectConstructionSite],
        reason:
            'A TelemetryEvent built from a non-literal name is invisible to '
            'the catalog check. Spell the name as a literal at the call site, '
            'or — if a new thin wrapper is genuinely warranted — teach '
            '_recordedEvent to read its callers and list it here.',
      );
    });

    test('every recorded event name is in the catalog', () {
      final names = kWavecruxEventNames;
      final undocumented = [
        for (final entry in recorded.entries)
          if (!names.contains(entry.key))
            '${entry.key}  (${entry.value.join(', ')})',
      ];
      expect(
        undocumented,
        isEmpty,
        reason:
            'An event that is not in kWavecruxEventCatalog is an event nobody '
            'vetted against the never-collect list '
            '(https://edacrux.app/telemetry). Add it to the catalog or '
            'remove the call site:\n${undocumented.join('\n')}',
      );
    });

    test('every open-core catalog entry is still recorded', () {
      final dead = [
        for (final event in catalog)
          if (!_proOnlyEvents.contains(event.name) &&
              !_sharedEvents.contains(event.name) &&
              !recorded.containsKey(event.name))
            event.name,
      ];
      expect(
        dead,
        isEmpty,
        reason:
            'These catalog entries have no call site in this repository. If '
            'the feature was removed, remove the entry; if the event moved to '
            'the Pro overlay, add it to _proOnlyEvents:\n${dead.join('\n')}',
      );
    });
  });
}
