// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_telemetry/crux_telemetry.dart' show TelemetryEvent;
import 'package:crux_theme/crux_theme.dart' show cruxColorThemeProvider;
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/editor_host_theme_synthesizer.dart'
    show kEditorHostThemeId;
import 'package:wavecrux/core/theme/wavecrux_color_theme_bootstrap.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_bridge.dart';
import 'package:wavecrux/services/host_bridge/editor_host_session_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../../helpers/fake_waveform_data_source.dart';
import '../../helpers/product_telemetry_config.dart';
import '../../support/fake_host_bridge_transport.dart';

/// The third front door onto the same hallway.
///
/// The claim under test is not "the bridge can highlight a signal" — that would
/// be a second highlight implementation, and having one is the failure mode.
/// The claim is that a frame from the extension host reaches *the very
/// providers* WCP's `add_items` / `set_cursor` / `focus_item` and CXP's inbound
/// `request_highlight` already reach: `signalGroupsProvider.addSignals`,
/// `selectedSignalProvider.select`, `cursorStateProvider.placePrimary`, and
/// `WaveformSourceNotifier.openFromBytes`. Every assertion below reads one of
/// those, never anything the bridge owns.
///
/// The rest is refusal. Frames are untrusted `window.postMessage` input, so the
/// bridge is also pinned to ignore what it cannot decode, answer what it cannot
/// act on, and never throw out of either.
void main() {
  // `dispatchCxpHighlight` ends in `requestUserAttention()`, a platform
  // channel. Unhandled channels answer null under the test binding, which is
  // the right shape for a best-effort OS nudge.
  TestWidgetsFlutterBinding.ensureInitialized();

  Scope buildScope() => const Scope(
    name: 'top',
    path: 'top',
    type: ScopeType.module,
    variables: [
      Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'top.clk',
        scopePath: 'top',
        bitWidth: 1,
      ),
      Variable(
        name: 'data',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'top.data',
        scopePath: 'top',
        bitWidth: 8,
      ),
    ],
  );

  ProviderContainer makeContainer({
    FakeWaveformDataSource? source,
    _RecordingSourceNotifier Function()? sourceNotifier,
  }) {
    final container = ProviderContainer(
      overrides: <Override>[
        productTelemetryConfig,
        appSettingsProvider.overrideWith(_FakeAppSettings.new),
        if (sourceNotifier != null)
          waveformSourceProvider.overrideWith(sourceNotifier)
        else if (source != null)
          waveformSourceProvider.overrideWith(
            () => _PreloadedSourceNotifier(source),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Map<String, Object?> frameOf(
    String kind,
    Map<String, Object?> payload, {
    String messageId = 'm1',
  }) => <String, Object?>{
    'type': kHostBridgeCxpFrameType,
    'envelope': <String, Object?>{
      'cxp_version': cxpProtocolVersion,
      'message_id': messageId,
      'from': 'vscode.host',
      'kind': kind,
      'payload': payload,
    },
  };

  /// Every CXP message the bridge posted, decoded, in order.
  ///
  /// Selected by type rather than by index because a highlight that lands also
  /// moves the selection, and the emitter's `notify_selection` shares the
  /// channel with the acknowledgement — which is the design working, not an
  /// ordering to pin.
  List<T> postedOfType<T extends CxpMessage>(
    FakeHostBridgeTransport transport,
  ) => <T>[
    for (final frame in transport.posted)
      if (frame['type'] == kHostBridgeCxpFrameType)
        if (decodeHostBridgePayload(
              CxpEnvelope.fromJson(
                frame['envelope']! as Map<String, Object?>,
              ).kind,
              CxpEnvelope.fromJson(
                frame['envelope']! as Map<String, Object?>,
              ).payload,
            )
            case final T message)
          message,
  ];

  /// The envelope of the frame carrying the first [T].
  CxpEnvelope envelopeOfType<T extends CxpMessage>(
    FakeHostBridgeTransport transport,
  ) => transport.posted
      .map((f) => CxpEnvelope.fromJson(f['envelope']! as Map<String, Object?>))
      .firstWhere(
        (e) => decodeHostBridgePayload(e.kind, e.payload) is T,
      );

  group('inbound request_highlight reaches the existing providers', () {
    test('adds the signal, focuses it, and acknowledges', () async {
      final container = makeContainer(
        source: FakeWaveformDataSource(scopes: [buildScope()]),
      );
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(CxpMessageKind.requestHighlight, <String, Object?>{
          'element': <String, Object?>{'kind': 'signal', 'path': 'top.clk'},
        }),
      );

      // `signalGroupsProvider.addSignals` — the same call WCP's `add_items`
      // makes.
      expect(
        container.read(signalGroupsProvider).entries.map((e) => e.signalRef),
        contains('top.clk'),
      );
      // `selectedSignalProvider.select` — the same call `focus_item` makes.
      expect(container.read(selectedSignalProvider), 'top.clk');

      final ack = postedOfType<RequestHighlightAck>(transport).single;
      expect(
        envelopeOfType<RequestHighlightAck>(transport).kind,
        CxpMessageKind.requestHighlightAck,
      );
      expect(ack.inReplyTo, 'm1');
      expect(ack.honored, isTrue);
    });

    test("acknowledges honored:false with the handler's own reason", () async {
      // No waveform loaded. The reason is produced by `dispatchCxpHighlight`,
      // not by the bridge — which is the point: a cross-probe the app could not
      // act on must read identically whichever door it came through.
      final container = makeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(CxpMessageKind.requestHighlight, <String, Object?>{
          'element': <String, Object?>{'kind': 'signal', 'path': 'top.clk'},
        }),
      );

      final ack = postedOfType<RequestHighlightAck>(transport).single;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('no waveform file loaded'));
    });

    test('a marker element places the primary cursor', () async {
      final container = makeContainer(
        source: FakeWaveformDataSource(scopes: [buildScope()]),
      );
      container.read(markerStateProvider.notifier).setMarker('a', 250);
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(CxpMessageKind.requestHighlight, <String, Object?>{
          'element': <String, Object?>{'kind': 'marker', 'path': 'a'},
        }),
      );

      // `cursorStateProvider.placePrimary` — the same call `set_cursor` makes.
      expect(container.read(cursorStateProvider).primaryCursorTime, 250);
    });
  });

  group('inbound theme tokens', () {
    // Settles `appSettingsProvider` before returning: `cruxColorThemeProvider`
    // (via `WaveCruxCruxColorThemeNotifier.build`) watches it, so a frame
    // handled while it is still pending would have its `applyEphemeral`
    // effect overwritten the moment settings resolve and the notifier
    // rebuilds — exactly the ordering hazard `applyEphemeral` itself does not
    // create (it never touches settings), but `build()` re-running for an
    // unrelated reason still would.
    Future<ProviderContainer> makeThemeContainer() async {
      final container = ProviderContainer(
        overrides: <Override>[
          productTelemetryConfig,
          appSettingsProvider.overrideWith(_FakeAppSettings.new),
          cruxColorThemeProvider.overrideWith(
            WaveCruxCruxColorThemeNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);
      return container;
    }

    test('synthesizes and applies the theme, unacknowledged', () async {
      final container = await makeThemeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(kHostBridgeThemeKind, <String, Object?>{
          'appearance': 'dark',
          'tokens': <String, Object?>{
            'editor.background': '#101010',
            'editor.foreground': '#F0F0F0',
          },
        }),
      );

      final theme = container.read(cruxColorThemeProvider);
      expect(theme.id, kEditorHostThemeId);
      expect(theme.brightness, Brightness.dark);
      expect(theme.color('canvas', 'background')?.toARGB32(), 0xFF101010);
      // Fire-and-forget: nothing is posted back for a theme frame.
      expect(transport.posted, isEmpty);
    });

    test('a live toggle updates the rendered theme again, no reload', () async {
      final container = await makeThemeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(kHostBridgeThemeKind, <String, Object?>{
          'appearance': 'dark',
          'tokens': <String, Object?>{'editor.background': '#101010'},
        }),
      );
      expect(
        container.read(cruxColorThemeProvider).brightness,
        Brightness.dark,
      );

      await bridge.handleFrame(
        frameOf(kHostBridgeThemeKind, <String, Object?>{
          'appearance': 'light',
          'tokens': <String, Object?>{'editor.background': '#FAFAFA'},
        }),
      );
      final theme = container.read(cruxColorThemeProvider);
      expect(theme.brightness, Brightness.light);
      expect(theme.color('canvas', 'background')?.toARGB32(), 0xFFFAFAFA);
    });

    test('does not persist the host theme to on-disk settings', () async {
      final container = await makeThemeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);
      final before = container.read(appSettingsProvider).value?.activeThemeName;

      await bridge.handleFrame(
        frameOf(kHostBridgeThemeKind, <String, Object?>{
          'appearance': 'dark',
          'tokens': <String, Object?>{'editor.background': '#101010'},
        }),
      );

      expect(
        container.read(appSettingsProvider).value?.activeThemeName,
        before,
      );
    });
  });

  // The nudge policy's not-on-the-first-file rule needs state that
  // outlives the window, and only the extension host has any. The bridge
  // records what it is told and nothing more — the policy built on top of it
  // is `capability_nudge_provider.dart`'s.
  group('inbound host session', () {
    test('records what the host said, unacknowledged', () async {
      final container = makeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(kHostBridgeHostSessionKind, <String, Object?>{
          'opened_file_before': true,
        }),
      );

      expect(
        container.read(editorHostSessionProvider).openedFileBefore,
        isTrue,
      );
      // A push, like the theme frame: nothing to correlate a reply to.
      expect(transport.posted, isEmpty);
    });

    test('the first open of an installation reports false', () async {
      final container = makeContainer();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: FakeHostBridgeTransport(),
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(kHostBridgeHostSessionKind, <String, Object?>{
          'opened_file_before': false,
        }),
      );

      expect(
        container.read(editorHostSessionProvider).openedFileBefore,
        isFalse,
      );
    });

    test('a malformed frame changes nothing and is silently ignored', () async {
      // Untrusted input. Coercing a truthy value would invent the one value
      // that *enables* a nudge out of a broken frame.
      final container = makeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(kHostBridgeHostSessionKind, <String, Object?>{
          'opened_file_before': 'yes',
        }),
      );

      expect(
        container.read(editorHostSessionProvider),
        EditorHostSession.unknown,
      );
      // A payload that does not decode for its kind fails at
      // `decodeHostBridgeFrame`, before dispatch — and an undecoded frame is
      // *not* answered: there is nothing honest to correlate a reply to. That
      // is the same rejection every other malformed frame gets, and the
      // failure mode it produces is silence rather than a misfired nudge.
      expect(transport.posted, isEmpty);
    });

    test('the kind literal matches the host side', () {
      // Renaming one side only is silent: the app answers `unknown_kind`, the
      // provider keeps its default, and the nudge simply never appears.
      // crux-vscode's `packages/wavecrux/src/webview/host-session.ts` pins the
      // same literal from the other direction.
      expect(kHostBridgeHostSessionKind, 'crux.host_session');
    });
  });

  group('inbound value query (RTL annotation)', () {
    test('answers with a value response rather than an ack', () async {
      final container = makeContainer(
        source: FakeWaveformDataSource(scopes: [buildScope()]),
      );
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(kHostBridgeValueQueryKind, <String, Object?>{
          'query_id': 'q1',
          'paths': <Object?>['top.clk'],
        }),
      );

      // Read off the raw frame rather than through `decodeHostBridgePayload`:
      // the response is an *outbound* kind, so this build deliberately has no
      // decoder for it — inventing one so a test could be tidier would put a
      // second definition of the shape in the repo that produces it.
      final envelope = CxpEnvelope.fromJson(
        transport.posted.single['envelope']! as Map<String, Object?>,
      );
      expect(envelope.kind, kHostBridgeValueResponseKind);
      // Correlated by `query_id`, not `in_reply_to`: the query stands, so one
      // message id could not name the responses it produces.
      expect(envelope.payload['query_id'], 'q1');
      expect(envelope.payload['values'], isA<Map<String, Object?>>());
      // No `unknown_kind` — the branch exists and claimed the frame.
      expect(postedOfType<ErrorResponse>(transport), isEmpty);
    });

    test('a malformed query is ignored, not answered', () async {
      final container = makeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(
        frameOf(kHostBridgeValueQueryKind, <String, Object?>{
          'paths': <Object?>['top.clk'],
        }),
      );

      expect(transport.posted, isEmpty);
    });

    test('the kind literals match the host side', () {
      // crux-vscode's `packages/wavecrux/src/webview/value-query.ts` pins the
      // same two literals from the other direction. A rename on one side only
      // is silent: this build answers `unknown_kind` and the extension's
      // decorations simply never appear.
      expect(kHostBridgeValueQueryKind, 'crux.value_query');
      expect(kHostBridgeValueResponseKind, 'crux.value_response');
    });
  });

  group('inbound open-waveform', () {
    test('routes bytes into WaveformSourceNotifier.openFromBytes', () async {
      // `openFromBytes` asserts `kIsWeb`, so the notifier is subclassed to
      // record the call rather than perform it. What is under test is the
      // routing — that the bridge reaches the app's one byte-open entry point
      // and does not grow a second.
      late _RecordingSourceNotifier recorder;
      final container = makeContainer(
        sourceNotifier: () => recorder = _RecordingSourceNotifier(),
      );
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);
      // Force the notifier to build so `recorder` is assigned.
      container.read(waveformSourceProvider);

      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      await bridge.handleFrame(
        frameOf(kHostBridgeOpenWaveformKind, <String, Object?>{
          'display_name': 'dump.vcd',
          'bytes_base64': base64Encode(bytes),
        }),
      );

      expect(recorder.openedBytes, bytes);
      expect(recorder.openedName, 'dump.vcd');
      final ack = postedOfType<RequestOpenArtifactAck>(transport).single;
      expect(ack.honored, isTrue);
      expect(ack.inReplyTo, 'm1');
    });

    test(
      'an open that throws becomes an unhonoured ack, not a crash',
      () async {
        late _RecordingSourceNotifier recorder;
        final container = makeContainer(
          sourceNotifier: () =>
              recorder = _RecordingSourceNotifier(throwOnOpen: true),
        );
        final transport = FakeHostBridgeTransport();
        final bridge = EditorHostBridge(
          ref: container.read(_refProvider),
          channel: transport,
        )..start();
        addTearDown(bridge.dispose);
        container.read(waveformSourceProvider);

        await bridge.handleFrame(
          frameOf(kHostBridgeOpenWaveformKind, <String, Object?>{
            'display_name': 'bad.vcd',
            'bytes_base64': base64Encode(<int>[1]),
          }),
        );

        expect(recorder.openedName, 'bad.vcd');
        final ack = postedOfType<RequestOpenArtifactAck>(transport).single;
        expect(ack.honored, isFalse);
        expect(ack.reason, contains('bad.vcd'));
      },
    );
  });

  group('inbound chunked open-waveform', () {
    Map<String, Object?> chunkFrame({
      required int index,
      required int count,
      required int totalBytes,
      required List<int> bytes,
      String transferId = 't1',
      String displayName = 'big.fst',
      String messageId = 'm1',
    }) => frameOf(
      kHostBridgeOpenWaveformChunkKind,
      <String, Object?>{
        'transfer_id': transferId,
        'index': index,
        'count': count,
        'display_name': displayName,
        'total_bytes': totalBytes,
        'bytes_base64': base64Encode(bytes),
      },
      messageId: messageId,
    );

    test('opens once, when the last chunk lands', () async {
      // The host slices a large waveform because a structured clone of the
      // whole thing is one allocation that size on each side. What arrives at
      // `openFromBytes` must still be the file, whole and in order.
      late _RecordingSourceNotifier recorder;
      final container = makeContainer(
        sourceNotifier: () => recorder = _RecordingSourceNotifier(),
      );
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);
      container.read(waveformSourceProvider);

      await bridge.handleFrame(
        chunkFrame(index: 0, count: 3, totalBytes: 6, bytes: <int>[1, 2]),
      );
      expect(recorder.openedBytes, isNull);
      expect(postedOfType<RequestOpenArtifactAck>(transport), isEmpty);

      await bridge.handleFrame(
        chunkFrame(index: 1, count: 3, totalBytes: 6, bytes: <int>[3, 4]),
      );
      expect(recorder.openedBytes, isNull);

      await bridge.handleFrame(
        chunkFrame(
          index: 2,
          count: 3,
          totalBytes: 6,
          bytes: <int>[5, 6],
          messageId: 'm-last',
        ),
      );
      expect(recorder.openedBytes, Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]));
      expect(recorder.openedName, 'big.fst');
      final ack = postedOfType<RequestOpenArtifactAck>(transport).single;
      expect(ack.honored, isTrue);
      expect(ack.inReplyTo, 'm-last');
    });

    test('answers a refused transfer instead of going quiet', () async {
      // A dropped transfer with no answer is indistinguishable from a webview
      // that never booted.
      late _RecordingSourceNotifier recorder;
      final container = makeContainer(
        sourceNotifier: () => recorder = _RecordingSourceNotifier(),
      );
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);
      container.read(waveformSourceProvider);

      await bridge.handleFrame(
        chunkFrame(
          index: 1,
          count: 2,
          totalBytes: 4,
          bytes: <int>[3, 4],
          messageId: 'm-orphan',
        ),
      );
      expect(recorder.openedBytes, isNull);
      final error = postedOfType<ErrorResponse>(transport).single;
      expect(error.code, CxpErrorCode.malformedPayload);
      expect(error.inReplyTo, 'm-orphan');
      expect(error.message, contains('transfer refused'));
    });

    test(
      'a chunk over the receiver cap never decodes, so nothing answers it',
      () async {
        // Rejected in `decodeHostBridgeFrame`, before an envelope exists to
        // reply to — the same silence every undecodable frame gets.
        final container = makeContainer();
        final transport = FakeHostBridgeTransport();
        final bridge = EditorHostBridge(
          ref: container.read(_refProvider),
          channel: transport,
        )..start();
        addTearDown(bridge.dispose);

        await bridge.handleFrame(
          chunkFrame(
            index: 0,
            count: 1,
            totalBytes: kHostBridgeMaxOpenBytes + 1,
            bytes: <int>[1],
          ),
        );
        expect(transport.posted, isEmpty);
      },
    );
  });

  group('untrusted input', () {
    test('a frame that does not decode is ignored, not answered', () async {
      // Not answered on purpose: with no valid envelope there is no message id
      // to correlate a reply to, and inventing one would put a reply on the
      // wire that answers nothing.
      final container = makeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      await bridge.handleFrame(<String, Object?>{'type': 'crux.nonsense'});
      await bridge.handleFrame(<String, Object?>{
        'type': kHostBridgeCxpFrameType,
        'envelope': <String, Object?>{'kind': 'request_highlight'},
      });
      await bridge.handleFrame(
        frameOf(CxpMessageKind.requestHighlight, <String, Object?>{}),
      );

      expect(transport.posted, isEmpty);
    });

    test('an oversize open-waveform payload is refused whole', () async {
      late _RecordingSourceNotifier recorder;
      final container = makeContainer(
        sourceNotifier: () => recorder = _RecordingSourceNotifier(),
      );
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);
      container.read(waveformSourceProvider);

      // Base64 of a buffer larger than `kHostBridgeMaxOpenBytes` cannot decode,
      // so the frame never becomes a message and nothing is opened. Proven with
      // a payload that fails the *shape* check for the same reason a huge one
      // fails the bound: the message is null either way, and the app must never
      // see a partially-applied open.
      await bridge.handleFrame(
        frameOf(kHostBridgeOpenWaveformKind, <String, Object?>{
          'display_name': 'x.vcd',
          'bytes_base64': 'not base64 at all!!',
        }),
      );

      expect(recorder.openedName, isNull);
      expect(transport.posted, isEmpty);
    });

    test(
      'a kind this build does not act on gets unknown_kind, not a throw',
      () async {
        final container = makeContainer();
        final transport = FakeHostBridgeTransport();
        final bridge = EditorHostBridge(
          ref: container.read(_refProvider),
          channel: transport,
        )..start();
        addTearDown(bridge.dispose);

        // `goodbye` decodes cleanly — it is a real CXP kind — and this build
        // has nothing to do with one over the bridge. That is the forward-
        // compatibility case: a kind a newer host sends must be answered, not
        // dropped and not thrown on.
        await bridge.handleFrame(
          frameOf(CxpMessageKind.goodbye, <String, Object?>{
            'reason': 'window closing',
          }),
        );

        final error = postedOfType<ErrorResponse>(transport).single;
        expect(error.code, CxpErrorCode.unknownKind);
        expect(error.inReplyTo, 'm1');
      },
    );
  });

  group('outbound', () {
    test('a selection change is posted as a CXP notify_selection', () async {
      final container = makeContainer(
        source: FakeWaveformDataSource(scopes: [buildScope()]),
      );
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      container.read(selectedSignalProvider.notifier).select('top.data');
      await Future<void>.delayed(Duration.zero);

      final selection = postedOfType<NotifySelection>(transport).single;
      expect(selection.elements.single.kind, ElementKind.signal);
      expect(selection.elements.single.path, 'top.data');
      // The same `CxpSelectionEmitter` the CXP server drives — so the editor
      // and the peer apps cannot come to see different selections.
      expect(selection.displayName, 'top.data');
    });

    test(
      'the envelope names this build and stamps a fresh id per message',
      () async {
        final container = makeContainer(
          source: FakeWaveformDataSource(scopes: [buildScope()]),
        );
        final transport = FakeHostBridgeTransport();
        final bridge = EditorHostBridge(
          ref: container.read(_refProvider),
          channel: transport,
        )..start();
        addTearDown(bridge.dispose);

        container.read(selectedSignalProvider.notifier).select('top.data');
        container.read(selectedSignalProvider.notifier).select('top.clk');
        await Future<void>.delayed(Duration.zero);

        final ids = transport.posted
            .map(
              (f) => (f['envelope']! as Map<String, Object?>)['message_id'],
            )
            .toList();
        expect(ids, hasLength(2));
        expect(ids.toSet(), hasLength(2));
        for (final frame in transport.posted) {
          expect(
            (frame['envelope']! as Map<String, Object?>)['from'],
            kHostBridgePeerId,
          );
        }
      },
    );

    test('telemetry is posted as the descriptor frame the host reads', () {
      final container = makeContainer();
      final transport = FakeHostBridgeTransport();
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      bridge.postTelemetry(
        TelemetryEvent(
          'cxp.crossprobe',
          properties: const <String, Object?>{'direction': 'inbound'},
        ),
      );

      expect(transport.posted.single['type'], kHostBridgeTelemetryFrameType);
    });
  });

  group('lifecycle', () {
    test('start is inert when nothing is hosting this build', () async {
      // The desktop and browser case. Reading the bridge provider at bootstrap
      // must not install a selection listener whose broadcasts nobody receives.
      final container = makeContainer(
        source: FakeWaveformDataSource(scopes: [buildScope()]),
      );
      final transport = FakeHostBridgeTransport(
        hostKind: EditorHostKind.none,
      );
      final bridge = EditorHostBridge(
        ref: container.read(_refProvider),
        channel: transport,
      )..start();
      addTearDown(bridge.dispose);

      container.read(selectedSignalProvider.notifier).select('top.data');
      await Future<void>.delayed(Duration.zero);

      expect(bridge.hostKind, EditorHostKind.none);
      expect(transport.posted, isEmpty);
    });

    test('a disposed bridge stops posting and stops acting', () async {
      final container = makeContainer(
        source: FakeWaveformDataSource(scopes: [buildScope()]),
      );
      final transport = FakeHostBridgeTransport();
      final bridge =
          EditorHostBridge(
              ref: container.read(_refProvider),
              channel: transport,
            )
            ..start()
            ..dispose();

      container.read(selectedSignalProvider.notifier).select('top.data');
      await bridge.handleFrame(
        frameOf(CxpMessageKind.requestHighlight, <String, Object?>{
          'element': <String, Object?>{'kind': 'signal', 'path': 'top.clk'},
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(transport.posted, isEmpty);
      expect(
        container.read(signalGroupsProvider).entries,
        isEmpty,
        reason: 'a disposed bridge must not still mutate the viewer',
      );
      // Idempotent.
      expect(bridge.dispose, returnsNormally);
    });
  });
}

final _refProvider = Provider<Ref>((ref) => ref);

class _FakeAppSettings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// Records the `openFromBytes` call instead of performing it.
///
/// The real method asserts `kIsWeb` and drives the WASM parser; neither is
/// available on the VM runner, and neither is what this file is about.
class _RecordingSourceNotifier extends WaveformSourceNotifier {
  _RecordingSourceNotifier({this.throwOnOpen = false});

  final bool throwOnOpen;
  Uint8List? openedBytes;
  String? openedName;

  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncData(null);

  @override
  Future<void> openFromBytes(Uint8List bytes, String displayName) async {
    openedBytes = bytes;
    openedName = displayName;
    if (throwOnOpen) throw StateError('WebAssembly unavailable');
  }
}
