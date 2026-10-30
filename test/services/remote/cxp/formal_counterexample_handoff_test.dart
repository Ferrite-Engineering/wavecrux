// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' show CruxCxpHandlerResult;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

/// **The SimCrux → WaveCrux formal hand-off, end to end, from real traces.**
///
/// What SimCrux sends for a counterexample or a cover (CXP §9.9.3): one
/// `request_highlight` whose element is the trace as a `source`, with a
/// `formal.trace_step` coordinate naming the solver's step, and for an
/// equivalence trace the `formal.eqy.*` scope keys in the metadata. This
/// drives the production entry point, [dispatchCxpHighlight], over the real
/// workspace, tab container manager and the native reader the app opens files
/// with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final captured = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'formal',
    'captured',
  );
  final handshake = p.join(
    captured,
    'sby/handshake_imm/captured/prove_bug/engine_0/trace.vcd',
  );
  final eqy = p.join(
    captured,
    'eqy/captured/alu_fail/strategies/alu.z/sby/trace.vcd',
  );

  CxpStreamCoordinate formalStep(int k, {String? mode}) => CxpStreamCoordinate(
    streamId: CxpStreamCoordinate.formalTraceStepStreamId,
    sequenceIndex: k,
    attributes: <String, String>{
      CxpStreamCoordinate.formalVerdictAttribute: 'FAIL',
      CxpStreamCoordinate.formalPropertyKindAttribute: 'assert',
      CxpStreamCoordinate.formalModeAttribute: ?mode,
    },
  );

  testWidgets('a counterexample lands the cursor on the reported step and '
      'says so', (tester) async {
    final announced = _captureAnnouncements(tester);
    await _pumpMessenger(tester);
    final harness = await _handOff(
      tester,
      handshake,
      coordinate: formalStep(6),
    );
    expect(harness.result.honored, isTrue);
    expect(harness.result.reason, isNull);
    // Step 6 is the sample at time 60 (smt_step 6 in the file).
    expect(harness.cursorTime, 60);
    await tester.pump();
    expect(announced, ['Formal trace opened. Cursor at step 6.']);
  });

  testWidgets('a replayed fixture is labelled as one', (tester) async {
    final announced = _captureAnnouncements(tester);
    await _pumpMessenger(tester);
    await _handOff(tester, handshake, coordinate: formalStep(6, mode: 'demo'));
    await tester.pump();
    expect(announced, [
      'Formal trace opened from a replayed demo fixture. Cursor at step 6.',
    ]);
  });

  testWidgets('a step the trace cannot place is declined with a reason, the '
      'element still honoured', (tester) async {
    final announced = _captureAnnouncements(tester);
    await _pumpMessenger(tester);
    final dir = Directory.systemTemp.createTempSync('formal_handoff_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final uneven = File(p.join(dir.path, 'uneven.vcd'))
      ..writeAsStringSync(_unevenTrace);
    final harness = await _handOff(
      tester,
      uneven.path,
      coordinate: formalStep(1),
    );
    expect(harness.result.honored, isTrue, reason: 'the trace opened');
    expect(harness.result.reason, contains('not evenly spaced'));
    expect(harness.cursorTime, isNull);
    await tester.pump();
    const declined =
        'Formal trace opened. The step could not be placed on this trace, so '
        'the cursor did not move.';
    expect(announced, [declined]);
  });

  testWidgets('no coordinate (a multi-clock trace, whose producer omits it) '
      'opens the trace and moves nothing', (tester) async {
    final announced = _captureAnnouncements(tester);
    await _pumpMessenger(tester);
    final harness = await _handOff(tester, handshake);
    expect(harness.result, CruxCxpHandlerResult.ok);
    expect(harness.cursorTime, isNull);
    await tester.pump();
    expect(announced, isEmpty);
  });

  testWidgets('an EQY trace opens with the miter outputs first and gold and '
      'gate as a pair, at the failing step', (tester) async {
    final harness = await _handOff(
      tester,
      eqy,
      coordinate: formalStep(1),
      metadata: const <String, Object?>{
        cxpFormalEqyGoldScopeMetadataKey: 'gold',
        cxpFormalEqyGateScopeMetadataKey: 'gate',
        cxpFormalPropertyKindMetadataKey: 'assert',
      },
    );
    expect(harness.result.honored, isTrue);
    expect(harness.result.reason, isNull);
    expect(harness.cursorTime, 10);

    final entries = harness.tab.read(signalGroupsProvider).entries;
    final groups = [
      for (final e in entries)
        if (e.kind == SignalEntryKind.group) e.groupName,
    ];
    expect(groups, ['miter.gold', 'miter.gate']);
    final firstGroup = entries.indexWhere(
      (e) => e.kind == SignalEntryKind.group,
    );
    expect(firstGroup, 10, reason: 'the ten miter outputs come first');
    expect(
      entries.take(firstGroup).every((e) => e.signalPath!.contains('__po_z')),
      isTrue,
    );
  });

  testWidgets('without the EQY keys the same trace opens unarranged', (
    tester,
  ) async {
    final harness = await _handOff(tester, eqy, coordinate: formalStep(1));
    expect(harness.result.honored, isTrue);
    expect(
      harness.tab
          .read(signalGroupsProvider)
          .entries
          .where((e) => e.kind == SignalEntryKind.group),
      isEmpty,
    );
  });

  // CXP §9.3.2: a signal highlight may carry `crux.time_ps`, and when it also
  // carries a coordinate the coordinate is the more specific request and wins
  // the cursor.
  const req = ElementId(kind: ElementKind.signal, path: 'handshake_imm.req');

  testWidgets('a signal highlight with a time moves the cursor to it in the '
      'real trace', (tester) async {
    await _pumpMessenger(tester);
    final harness = await _handOff(
      tester,
      handshake,
      follow: const _FollowUp(req, <String, Object?>{'crux.time_ps': 20000}),
    );
    expect(harness.result.honored, isTrue);
    expect(harness.result.reason, isNull);
    // The trace declares a 1 ns timescale: 20000 ps is the sample at 20.
    expect(harness.cursorTime, 20);
  });

  testWidgets('when a coordinate rides with the time, the coordinate wins the '
      'cursor', (tester) async {
    await _pumpMessenger(tester);
    final harness = await _handOff(
      tester,
      handshake,
      follow: _FollowUp(
        req,
        const <String, Object?>{'crux.time_ps': 20000},
        formalStep(6),
      ),
    );
    expect(harness.result.honored, isTrue);
    expect(harness.cursorTime, 60, reason: 'step 6 is the sample at time 60');
  });

  testWidgets('a coordinate that cannot be placed leaves the time where it '
      'put the cursor', (tester) async {
    await _pumpMessenger(tester);
    final dir = Directory.systemTemp.createTempSync('formal_time_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final uneven = File(p.join(dir.path, 'uneven.vcd'))
      ..writeAsStringSync(_unevenTrace);
    final harness = await _handOff(
      tester,
      uneven.path,
      follow: _FollowUp(
        const ElementId(kind: ElementKind.signal, path: 'top.data'),
        const <String, Object?>{'crux.time_ps': 25000},
        formalStep(1),
      ),
    );
    expect(harness.result.honored, isTrue);
    expect(harness.result.reason, contains('not evenly spaced'));
    expect(harness.cursorTime, 25);
  });

  testWidgets('a property element is still declined: WaveCrux receives the '
      'trace, not the property', (tester) async {
    final harness = await _handOff(
      tester,
      handshake,
      element: const ElementId(
        kind: ElementKind.property,
        path: 'handshake_imm.sv:45',
      ),
      coordinate: formalStep(6),
    );
    expect(harness.result.honored, isFalse);
    expect(harness.result.reason, contains('does not handle'));
    expect(harness.result.reason, isNot(contains('handshake_imm')));
  });
}

/// What one hand-off produced.
class _Harness {
  _Harness(this.result, this.tab);

  final CruxCxpHandlerResult result;

  /// The active tab's container after the hand-off.
  final ProviderContainer tab;

  /// The primary cursor in [tab]. Read through a subscription kept until the
  /// container goes, so the read schedules no disposal in the fake zone.
  int? get cursorTime =>
      tab.listen(cursorStateProvider, (_, _) {}).read().primaryCursorTime;
}

/// A second `request_highlight`, sent after the trace is open, whose reply
/// becomes the hand-off's result.
class _FollowUp {
  const _FollowUp(this.element, this.metadata, [this.coordinate]);

  final ElementId element;
  final Map<String, Object?> metadata;
  final CxpStreamCoordinate? coordinate;
}

/// Runs [dispatchCxpHighlight] for [element] (by default the trace at [path]
/// as a `source`), the request SimCrux sends. With [follow], then sends that
/// second request into the tab the first one opened.
Future<_Harness> _handOff(
  WidgetTester tester,
  String path, {
  ElementId? element,
  CxpStreamCoordinate? coordinate,
  Map<String, Object?> metadata = const <String, Object?>{},
  _FollowUp? follow,
}) async {
  final tcm = TabContainerManager(
    extraTabOverrides: [
      waveformSourceProvider.overrideWith(_NativeTraceSourceNotifier.new),
    ],
  );
  final root = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      ...testWorkspaceOverrides(),
      tabContainerManagerProvider.overrideWithValue(tcm),
    ],
  );
  tcm.init(root);
  addTearDown(() {
    tcm.dispose();
    root.dispose();
  });
  final result = await tester.runAsync(() async {
    var result = await dispatchCxpHighlight(
      root.read(_refProvider),
      element ?? ElementId(kind: ElementKind.source, path: path),
      metadata,
      coordinate,
    );
    if (follow != null) {
      result = await dispatchCxpHighlight(
        root.read(_refProvider),
        follow.element,
        follow.metadata,
        follow.coordinate,
      );
    }
    await root.wavecruxWorkspace.flushPendingSave();
    return result;
  });
  return _Harness(result!, tcm.containerFor(root.read(activeTabIdProvider)));
}

/// Mounts the root messenger the inbound path localizes and announces
/// through. A plain Material theme has no Crux Desktop toast host, so the
/// message is announced directly, which is what the test listens for.
Future<void> _pumpMessenger(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: const Scaffold(),
  ),
);

/// Every screen-reader announcement sent while the test runs.
List<String> _captureAnnouncements(WidgetTester tester) {
  final announced = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (message) async {
      if (message is Map && message['type'] == 'announce') {
        final data = message['data'];
        if (data is Map && data['message'] is String) {
          announced.add(data['message'] as String);
        }
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return announced;
}

final Provider<Ref> _refProvider = Provider<Ref>((ref) => ref);

/// A per-tab source notifier that opens the trace with the native reader the
/// app uses.
class _NativeTraceSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      const AsyncData<WaveformDataSource?>(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    currentFilePath = path;
    final source = WellenProvider();
    await source.openFile(path);
    addTearDown(source.close);
    state = AsyncData(source);
  }
}

const String _unevenTrace = r'''
$timescale 1ns $end
$scope module top $end
$var wire 4 a data $end
$upscope $end
$enddefinitions $end
#0
b0000 a
#10
b0001 a
#25
b0010 a
#40
b0011 a
''';
