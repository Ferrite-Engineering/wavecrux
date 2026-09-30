// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/host_bridge/editor_host_cross_probe_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_event_log_entry.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../support/fake_host_bridge_transport.dart';
import '../../../support/fake_waveform_source.dart';

/// The cross-probe panel under a VSCode extension host.
///
/// The bug these pin: inside a webview this build has no CXP server and
/// cannot have one, so the panel showed a red banner telling the user to
/// enable a setting that was already on, an empty peer list, and a Send
/// button that returned without a sound — while the extension host it was
/// running inside was a healthy CXP peer the whole time.
///
/// Every assertion below therefore reads what the *host* said, never
/// `cxpServerProvider`. The desktop path is asserted in
/// `cross_probe_panel_test.dart` and must be untouched by all of this: the
/// editor-host source is an alternative, not a replacement.
void main() {
  const peer = PeerIdentity(
    peerId: 'wavecrux-4242-1700000000000',
    productName: 'WaveCrux',
    productVersion: '0.9.0',
  );

  Widget wrap({
    List<Override> overrides = const [],
    Locale locale = const Locale('en'),
  }) => ProviderScope(
    overrides: [
      productTelemetryConfig,
      // What makes this an editor host at all. Set by the host bridge during
      // bootstrap in production, from a marker the extension's shim freezes
      // into `window` before `main.dart.js` runs.
      editorHostKindProvider.overrideWith(
        () => _StaticHostKind(EditorHostKind.vscode),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: const Scaffold(
        body: SizedBox(
          width: 800,
          height: 800,
          child: WaveCruxCrossProbePanel(),
        ),
      ),
    ),
  );

  Override hostState(EditorHostCrossProbeState state) =>
      editorHostCrossProbeProvider.overrideWith(() => _StaticState(state));

  group('the offline banner', () {
    testWidgets('never shows under an editor host, even with nothing live', (
      tester,
    ) async {
      // `cxpServerProvider.isRunning` is false here and always will be — the
      // lifecycle bridge is desktop-only by construction. Reading it as "the
      // server is offline, enable it in Settings" was advice about a setting
      // that could not have helped.
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cross_probe_offline_banner')),
        findsNothing,
      );
    });

    testWidgets('still shows on desktop when the server is stopped', (
      tester,
    ) async {
      // The control for the test above: the same widget, the same stopped
      // server, and `EditorHostKind.none`.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [productTelemetryConfig],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 800,
                child: WaveCruxCrossProbePanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cross_probe_offline_banner')),
        findsOneWidget,
      );
    });
  });

  group('the host feeds the panel', () {
    testWidgets('renders peer rows the host discovered', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            hostState(
              const EditorHostCrossProbeState(
                online: true,
                peers: <PeerIdentity>[peer],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('WaveCrux 0.9.0'), findsOneWidget);
      expect(find.text('No peers connected'), findsNothing);
      expect(
        find.byKey(const Key('cross_probe_send_wavecrux-4242-1700000000000')),
        findsOneWidget,
      );
    });

    testWidgets('renders the host event log through the shared mapping', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            hostState(
              EditorHostCrossProbeState(
                online: true,
                events: <CxpEventLogEntry>[
                  CxpEventLogEntry(
                    timestamp: DateTime(2026, 5, 24, 10, 30),
                    direction: CxpEventDirection.outbound,
                    messageKind: CxpMessageKind.notifySelection,
                    peerLabel: 'WaveCrux',
                    summary: 'top.data',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // The same semantic labels the desktop log produces — one mapping, two
      // sources.
      expect(find.text('Selection sent'), findsOneWidget);
      expect(find.textContaining('WaveCrux · top.data'), findsOneWidget);
    });

    testWidgets('renders the host unreachable-peer records', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            hostState(
              const EditorHostCrossProbeState(
                online: true,
                unreachable: <CxpDialFailure>[
                  CxpDialFailure(
                    peerId: 'netcrux-1-2',
                    host: '127.0.0.1',
                    port: 54399,
                    error: 'Connection refused',
                    consecutiveFailures: 1,
                    nextRetryAfterTicks: 0,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('netcrux-1-2'), findsOneWidget);
    });

    testWidgets('clear events hides what is shown without asking the host', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            hostState(
              EditorHostCrossProbeState(
                online: true,
                events: <CxpEventLogEntry>[
                  CxpEventLogEntry(
                    timestamp: DateTime(2026),
                    direction: CxpEventDirection.inbound,
                    messageKind: CxpMessageKind.notifySelection,
                    peerLabel: 'WaveCrux',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_clear_events')));
      await tester.pumpAndSettle();
      expect(find.text('No events yet'), findsOneWidget);
    });

    testWidgets('surfaces a refused send as a toast, exactly once', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            hostState(
              const EditorHostCrossProbeState(
                online: true,
                peers: <PeerIdentity>[peer],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WaveCruxCrossProbePanel)),
      );
      const refused = EditorHostCrossProbeState(
        online: true,
        peers: <PeerIdentity>[peer],
        sendFailure: HostBridgeCrossProbeSendFailure(
          inReplyTo: 'wc-0',
          peerLabel: 'WaveCrux',
          reason: 'This window has no live connection to that app right now.',
        ),
      );
      container.read(editorHostCrossProbeProvider.notifier).set(refused);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cross_probe_send_failure')),
        findsOneWidget,
      );
      expect(find.textContaining('no live connection'), findsOneWidget);

      // The host re-pushes its whole snapshot on every peer change, and the
      // refusal rides along until it is replaced. Correlating on
      // `in_reply_to` is what stops the same toast re-firing on each push.
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.byKey(const Key('cross_probe_send_failure')), findsNothing);
      container
          .read(editorHostCrossProbeProvider.notifier)
          .set(
            const EditorHostCrossProbeState(
              online: true,
              sendFailure: HostBridgeCrossProbeSendFailure(
                inReplyTo: 'wc-0',
                peerLabel: 'WaveCrux',
                reason:
                    'This window has no live connection to that app right now.',
              ),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cross_probe_send_failure')), findsNothing);
    });

    testWidgets('a refusal of a later send, worded the same, raises its own '
        'toast', (tester) async {
      await tester.pumpWidget(
        wrap(
          overrides: [
            hostState(
              const EditorHostCrossProbeState(
                online: true,
                peers: <PeerIdentity>[peer],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WaveCruxCrossProbePanel)),
      );
      final toast = find.byKey(const Key('cross_probe_send_failure'));
      EditorHostCrossProbeState refusalOf(String messageId) =>
          EditorHostCrossProbeState(
            online: true,
            peers: const <PeerIdentity>[peer],
            sendFailure: HostBridgeCrossProbeSendFailure(
              inReplyTo: messageId,
              peerLabel: 'WaveCrux',
              reason:
                  'This window has no live connection to that app right now.',
            ),
          );

      container
          .read(editorHostCrossProbeProvider.notifier)
          .set(refusalOf('wc-0'));
      await tester.pumpAndSettle();
      expect(toast, findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(toast, findsNothing);

      // A different send, refused for the same reason. Its failure equals the
      // last one, so published as-is it would not notify the panel.
      container
          .read(editorHostCrossProbeProvider.notifier)
          .set(refusalOf('wc-1'));
      await tester.pumpAndSettle();
      expect(toast, findsOneWidget, reason: 'every refused send is answered');
    });
  });

  group('the panel sends through the host', () {
    // Originating a cross-probe is Pro, through the host as on the desktop,
    // so these run at a Pro seat.
    final proSeat = licenseTierProvider.overrideWithValue(
      LicenseTier.pro,
    );

    testWidgets('posts a crux.cross_probe_send naming the peer and the path', (
      tester,
    ) async {
      final transport = FakeHostBridgeTransport();
      await tester.pumpWidget(
        wrap(
          overrides: [
            proSeat,
            hostBridgeChannelProvider.overrideWithValue(transport),
            waveformSourceProvider.overrideWith(
              () => _PreloadedSourceNotifier(FakeWaveformSource.reference()),
            ),
            // The focus stores the backend-local ref `s_data`, not a path.
            selectedSignalProvider.overrideWith(
              () => _StaticSelection('s_data'),
            ),
            hostState(
              const EditorHostCrossProbeState(
                online: true,
                peers: <PeerIdentity>[peer],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('cross_probe_send_wavecrux-4242-1700000000000')),
      );
      await tester.pumpAndSettle();

      final frame = transport.posted.singleWhere(
        (f) =>
            (f['envelope']! as Map<String, Object?>)['kind'] ==
            kHostBridgeCrossProbeSendKind,
      );
      final envelope = CxpEnvelope.fromJson(
        frame['envelope']! as Map<String, Object?>,
      );
      expect(envelope.payload['peer_id'], 'wavecrux-4242-1700000000000');
      final selection = envelope.payload['selection']! as Map<String, Object?>;
      final elements = selection['elements']! as List<Object?>;
      // The canonical fullPath, never the opaque per-process `s_data` that
      // no peer can resolve — the same rule the desktop send follows.
      expect(
        (elements.single! as Map<String, Object?>)['path'],
        'top.data',
      );
      expect(
        (elements.single! as Map<String, Object?>)['kind'],
        ElementKind.signal.name,
      );
    });

    testWidgets('says so instead of sending when nothing is selected', (
      tester,
    ) async {
      final transport = FakeHostBridgeTransport();
      await tester.pumpWidget(
        wrap(
          overrides: [
            proSeat,
            hostBridgeChannelProvider.overrideWithValue(transport),
            hostState(
              const EditorHostCrossProbeState(
                online: true,
                peers: <PeerIdentity>[peer],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('cross_probe_send_wavecrux-4242-1700000000000')),
      );
      await tester.pumpAndSettle();

      expect(
        transport.posted.where(
          (f) =>
              (f['envelope']! as Map<String, Object?>)['kind'] ==
              kHostBridgeCrossProbeSendKind,
        ),
        isEmpty,
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  testWidgets('locale sweep — en/zh_CN/ja/ko render without exception', (
    tester,
  ) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await tester.pumpWidget(
        wrap(
          locale: locale,
          overrides: [
            hostState(
              EditorHostCrossProbeState(
                online: true,
                peers: const <PeerIdentity>[peer],
                unreachable: const <CxpDialFailure>[
                  CxpDialFailure(
                    peerId: 'netcrux-1-2',
                    host: '127.0.0.1',
                    port: 54399,
                    error: 'Connection refused',
                    consecutiveFailures: 1,
                    nextRetryAfterTicks: 0,
                  ),
                ],
                events: <CxpEventLogEntry>[
                  CxpEventLogEntry(
                    timestamp: DateTime(2026, 5, 24, 10, 30),
                    direction: CxpEventDirection.outbound,
                    messageKind: CxpMessageKind.notifySelection,
                    peerLabel: 'WaveCrux',
                    summary: 'top.data',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$locale');
    }
  });
}

class _StaticHostKind extends EditorHostKindNotifier {
  _StaticHostKind(this._kind);
  final EditorHostKind _kind;
  @override
  EditorHostKind build() => _kind;
}

class _StaticState extends EditorHostCrossProbeNotifier {
  _StaticState(this._state);
  final EditorHostCrossProbeState _state;
  @override
  EditorHostCrossProbeState build() => _state;
}

class _StaticSelection extends SelectedSignalNotifier {
  _StaticSelection(this._selection);
  final String? _selection;
  @override
  String? build() => _selection;
}

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource> build() => AsyncData(_source);
}
