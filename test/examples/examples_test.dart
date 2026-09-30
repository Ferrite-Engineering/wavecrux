// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guard for the shipped `examples/` sessions.
//
// **Existence is not loadability.** Nothing here calls `existsSync()` on a
// `.wavecrux` and declares victory. Every assertion below runs the real
// `SessionService.loadSession`, the real `WellenProvider`, the real
// `StageRegistry` and the real `DecoderRegistry` — the same four the desktop
// File → Open File path uses — and then re-derives every baked reference
// against the trace that is actually committed beside the session.
//
// That shape is not decorative. A `.wavecrux` stores each Stage and decoder
// binding as a **backend-local `signalRef`**, and session restore does not
// re-resolve those (only the composition-recipe path in
// `ActiveDecodersNotifier` does). The top-level signal list is re-resolved by
// path, and `SignalGroupsNotifier.reresolveSignalRefs` *silently drops* any
// entry whose path matches nothing. So both failure modes — a stale ref and a
// typo'd path — open to a window that is merely emptier than intended, with
// no error anywhere. A first-run user reads that as "this product does not
// work". These tests are the only place that failure is loud.
//
// MUTATION: change any "ref" in either session, rename a signal in either
// committed VCD, or delete a trace, and this file fails.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/stage/widgets/primitives/builtin_stage_widgets.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';
import 'package:wavecrux/services/decoders/axi4lite_decoder.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/uart_decoder.dart';
import 'package:wavecrux/services/session/session_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../helpers/wellen_ffi_library_gate.dart';

const String _examplesDir = 'examples';

/// The examples this file knows about. A `.wavecrux` under `examples/` that is
/// not in this map fails the coverage test below — an example nobody guards is
/// the defect this file exists to prevent.
const Map<String, String> _sessions = {
  'five-buses': 'five-buses/five-buses.wavecrux',
  'pipeline-diagram': 'pipeline-diagram/pipeline-diagram.wavecrux',
  'annotations': 'annotations/annotations-demo.wavecrux',
  'annotation-review': 'annotation-review/bus-review.wavecrux',
};

/// Each example's committed trace and the upstream fixture it was copied
/// from. The copy must stay byte-identical: the example is only meaningful
/// because the upstream corpus proves what the trace contains, and a drifted
/// copy would quietly stop meaning that. Same guarantee
/// `sample_waveform_service_test.dart` gives the bundled sample asset.
/// `annotations/` is intentionally absent: its trace is hand-authored for this
/// example rather than copied from an upstream corpus, so there is no origin to
/// stay byte-identical to. Its meaning is guarded instead by
/// `annotations_demo_session_test.dart`, which pins the witness value the
/// example's README instructs the reader to edit.
const Map<String, String> _traceOrigins = {
  'examples/five-buses/five-buses.vcd':
      'verification/fixtures/protocol/multi/all5_basic.vcd',
  'examples/pipeline-diagram/pipeline-diagram.vcd':
      'test/fixtures/protocol/riscv/generated/riscv_pipeline_5stage.vcd',
};

/// Flattens the session's signal list, descending into groups.
List<SignalEntry> _flatten(List<SignalEntry> entries) => [
  for (final e in entries) ...[
    e,
    if (e.kind == SignalEntryKind.group) ..._flatten(e.children),
  ],
];

/// Reads the raw JSON so the *authored* text can be asserted, not just the
/// decoded model — `SessionService` normalises a relative `sourceFilePath`
/// into an absolute one on load, which would hide a non-portable session.
Map<String, dynamic> _raw(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Same registrations `bootstrap()` performs, minus the ones no example
    // uses. Registering here rather than stubbing means an example that names
    // a decoder Open Core does not ship would fail on the real registry.
    final decoders = DecoderRegistry.instance;
    if (!decoders.isRegistered(SpiDecoder.decoderDefinition.id)) {
      decoders
        ..register(SpiDecoder.decoderDefinition, SpiDecoder.new)
        ..register(I2cDecoder.decoderDefinition, I2cDecoder.new)
        ..register(UartDecoder.decoderDefinition, UartDecoder.new)
        ..register(Axi4LiteDecoder.decoderDefinition, Axi4LiteDecoder.new)
        ..register(ApbDecoder.decoderDefinition, ApbDecoder.new);
    }
    registerBuiltinStageWidgets();
  });

  test('every .wavecrux under examples/ is covered by this file', () {
    final found = Directory(_examplesDir)
        .listSync(recursive: true)
        .whereType<File>()
        // `p.relative` yields host separators, but the `_sessions` keys are
        // written with `/` because they are stable identifiers rather than
        // paths anything opens. Normalise the discovered side to POSIX so the
        // comparison is platform-independent: on Windows this was comparing
        // `five-buses\five-buses.wavecrux` against
        // `five-buses/five-buses.wavecrux` and failing on the separator alone.
        .map((f) => p.split(p.relative(f.path, from: _examplesDir)).join('/'))
        .where((f) => f.endsWith(SessionService.fileExtension))
        .toSet();
    expect(
      found,
      _sessions.values.toSet(),
      reason:
          'a session was added to or removed from examples/ without updating '
          '_sessions — an unguarded example is exactly the defect this file '
          'exists to prevent',
    );
  });

  test('the copied traces are byte-identical to their upstream fixtures', () {
    _traceOrigins.forEach((copy, origin) {
      expect(
        File(copy).readAsBytesSync(),
        File(origin).readAsBytesSync(),
        reason:
            '$copy has drifted from $origin — regenerating the fixture without '
            'refreshing the example silently changes what the example shows',
      );
    });
  });

  test('the examples README documents every example directory', () {
    final readme = File('$_examplesDir/README.md').readAsStringSync();
    for (final relative in _sessions.values) {
      final dir = p.split(relative).first;
      expect(
        readme,
        contains(dir),
        reason: 'examples/README.md never mentions $dir/',
      );
    }
  });

  // Everything below opens the examples' traces.
  if (!requireWellenFfiLibrary('examples open and decode')) return;

  for (final entry in _sessions.entries) {
    group(entry.key, () {
      final sessionPath = p.join(_examplesDir, entry.value);
      late SessionState state;
      late WellenProvider provider;
      late Map<String, Variable> byPath;
      late Set<String> refs;

      setUpAll(() async {
        // The real load path, not a hand-rolled JSON read.
        state = await const SessionService().loadSession(sessionPath);
        provider = WellenProvider();
        await provider.openFile(state.sourceFilePath!);
        final variables = provider.findVariables(const SignalFilter());
        byPath = {for (final v in variables) v.fullPath: v};
        refs = {for (final v in variables) v.signalRef};
      });

      tearDownAll(() => provider.close());

      test('travels — the trace is named relatively and sits beside it', () {
        final authored = _raw(sessionPath)['sourceFilePath'] as String;
        expect(
          p.isAbsolute(authored),
          isFalse,
          reason:
              'sourceFilePath must be relative so the example opens from any '
              'checkout, on any machine',
        );
        expect(p.split(authored), hasLength(1));
        expect(
          File(p.join(p.dirname(sessionPath), authored)).existsSync(),
          isTrue,
          reason:
              '$sessionPath names "$authored", which is not committed — the '
              'example would open to an error dialog',
        );
        // SessionService resolves the relative path against the session's own
        // directory, so the loaded state points at the committed copy
        // regardless of the process working directory.
        expect(state.sourceFilePath, endsWith(authored));
      });

      test('the trace parses and is not empty', () {
        expect(provider.endTime, greaterThan(provider.startTime));
        expect(byPath, isNotEmpty);
      });

      // The two halves of the silent-drop failure: a path that resolves to
      // nothing is dropped by reresolveSignalRefs, and a ref that has gone
      // stale mis-binds every consumer that does not re-resolve.
      test('every baked signal entry resolves against the committed '
          'trace', () {
        final signals = _flatten(
          state.signalGroup.entries,
        ).where((e) => e.kind == SignalEntryKind.signal).toList();
        expect(
          signals,
          isNotEmpty,
          reason: 'an example that adds no signals shows an empty canvas',
        );
        for (final signal in signals) {
          final path = signal.signalPath;
          expect(
            path,
            isNotNull,
            reason:
                '"${signal.displayName}" has no path — it would survive only '
                'as a stale ref and silently mis-bind on another backend',
          );
          final variable = byPath[path];
          expect(
            variable,
            isNotNull,
            reason:
                '"$path" matches no signal in the trace; the viewer drops it '
                'without an error and the lane just never appears',
          );
          expect(
            signal.signalRef,
            variable!.signalRef,
            reason:
                'the baked ref for "$path" is stale — it is "${signal.signalRef}" '
                'but this trace resolves it to "${variable.signalRef}"',
          );
        }
      });

      test('every Stage instance mounts an Open Core widget with resolvable '
          'pins', () {
        for (final panel in state.stageWorkspace.panels) {
          for (final instance in panel.instances) {
            final widget = StageRegistry.instance.get(instance.widgetId);
            expect(
              widget,
              isNotNull,
              reason:
                  '"${instance.widgetId}" is not registered in an Open Core '
                  'build — this example would mount an empty tile',
            );
            final pins = {
              for (final b in widget!.requiredSignals) b.name,
              for (final b in widget.optionalSignals) b.name,
            };
            for (final binding in instance.signalBindings.entries) {
              expect(
                pins,
                contains(binding.key),
                reason:
                    '"${instance.widgetId}" declares no pin "${binding.key}"',
              );
              expect(
                refs,
                contains(binding.value.signalRef),
                reason:
                    'pin "${binding.key}" is bound to ref '
                    '"${binding.value.signalRef}", which this trace does not '
                    'produce',
              );
            }
          }
        }
      });

      test('every decoder is Open Core and every pin it binds is real', () {
        for (final decoder in state.decoders) {
          final definition = DecoderRegistry.instance.getDefinition(
            decoder.decoderId,
          );
          expect(
            definition,
            isNotNull,
            reason:
                '"${decoder.decoderId}" is not an Open Core decoder — restore '
                'drops it silently and the transaction table stays empty',
          );
          final pins = {
            for (final b in definition!.requiredSignals) b.name,
            for (final b in definition.optionalSignals) b.name,
          };
          for (final binding in decoder.config.signalBindings.entries) {
            expect(
              pins,
              contains(binding.key),
              reason: '"${decoder.decoderId}" declares no pin "${binding.key}"',
            );
            expect(
              refs,
              contains(binding.value),
              reason:
                  '"${decoder.decoderId}.${binding.key}" is bound to ref '
                  '"${binding.value}", which this trace does not produce',
            );
          }
        }
      });
    });
  }

  // The strongest claim the five-buses example makes is that the transaction
  // table is populated the moment it opens. Asserting the bindings resolve
  // proves only that the decoders would run — this runs them, through the
  // registry factories, with callbacks built exactly the way
  // `ActiveDecodersNotifier.decodeAll` builds them, and compares against the
  // committed expectations for the same trace.
  group('five-buses actually decodes', () {
    const sessionPath = 'examples/five-buses/five-buses.wavecrux';
    const expectedDir = 'verification/fixtures/protocol/multi';

    late SessionState state;
    late WellenProvider provider;

    setUpAll(() async {
      state = await const SessionService().loadSession(sessionPath);
      provider = WellenProvider();
      await provider.openFile(state.sourceFilePath!);
    });

    tearDownAll(() => provider.close());

    test('all five buses are bound', () {
      expect(
        state.decoders.map((d) => d.decoderId).toSet(),
        {'spi', 'i2c', 'uart', 'axi4_lite', 'apb'},
      );
    });

    test('each decoder produces the transactions the corpus expects', () async {
      for (final persisted in state.decoders) {
        final bindings = persisted.config.signalBindings;
        for (final ref in bindings.values) {
          if (ref.isNotEmpty && !provider.isSignalLoaded(ref)) {
            await provider.loadSignal(ref);
          }
        }
        String? query(String pin, int time) {
          final ref = bindings[pin];
          if (ref == null || ref.isEmpty) return null;
          return provider.valueAt(ref, time);
        }

        List<(int, String)> changes(String pin, int start, int end) {
          final ref = bindings[pin];
          if (ref == null || ref.isEmpty) return const [];
          return provider
              .changesInRange(ref, start, end)
              .map((c) => (c.time, c.value))
              .toList();
        }

        final factory = DecoderRegistry.instance.getFactory(
          persisted.decoderId,
        );
        final decoder = factory!(
          DecoderConfig(
            signalBindings: bindings,
            parameters: persisted.config.parameters,
          ),
        );
        final transactions = decoder.decode(
          provider.startTime,
          provider.endTime,
          query,
          changes,
          timescale: provider.timescale,
        );

        final expected =
            (jsonDecode(
                      File(
                        '$expectedDir/all5_basic.${persisted.decoderId}'
                        '.expected_transactions.json',
                      ).readAsStringSync(),
                    )
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();

        expect(
          transactions,
          isNotEmpty,
          reason:
              '${persisted.decoderId} decoded nothing — the example opens to '
              'an empty transaction table, which is worse than shipping no '
              'example at all',
        );
        expect(
          transactions.length,
          expected.length,
          reason:
              '${persisted.decoderId} decoded ${transactions.length} '
              'transactions but the corpus expects ${expected.length}; the '
              'baked bindings or parameters no longer match the trace',
        );
        _expectLabelsMatch(persisted.decoderId, transactions, expected);
      }
    });
  });
}

void _expectLabelsMatch(
  String decoderId,
  List<DecodedTransaction> actual,
  List<Map<String, dynamic>> expected,
) {
  final sorted = [...actual]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final expectedSorted = [...expected]
    ..sort((a, b) => (a['startTime'] as int).compareTo(b['startTime'] as int));
  for (var i = 0; i < expectedSorted.length; i++) {
    expect(
      sorted[i].label,
      expectedSorted[i]['label'],
      reason: '$decoderId tx[$i] label',
    );
    expect(
      sorted[i].startTime,
      expectedSorted[i]['startTime'],
      reason: '$decoderId tx[$i] startTime',
    );
  }
}
