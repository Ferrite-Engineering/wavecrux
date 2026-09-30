// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

/// `request_open_artifact`: a peer asks WaveCrux to open a design's
/// waveform, named by `design_id`, with an optional `path` hint. WaveCrux
/// resolves the file through the shared workspace store, falls back to the
/// hint, and opens the result in a new tab — so every path that reaches a
/// tab here was chosen, directly or through a record, by another process.
///
/// The route is held to the floor — absolute, well-formed, the exact string
/// opened — and not to the directories the user has opened: it exists to
/// open a waveform WaveCrux has never seen, which is what "Open in WaveCrux
/// Desktop" in VS Code sends (`kCxpOpenArtifactContainment` says why). The
/// `crux.design_id` fallback a cross-probe takes keeps the roots, and the
/// last group proves that it still does.
///
/// Most tests call [dispatchCxpOpenArtifact] directly, so the handler sees
/// exactly what a peer sent; two go through a real socket and the server the
/// app's own provider builds, whose wire screen runs first.
void main() {
  // An honoured open nudges the window's attention through a platform
  // channel, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory open;
  late Directory outside;
  late Directory storeDir;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'WaveCrux',
      packageName: 'com.ferriteengineering.wavecrux',
      version: '0.0.0-test',
      buildNumber: '0',
      buildSignature: '',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    open = Directory.systemTemp.createTempSync('cxp_artifact_open_');
    outside = Directory.systemTemp.createTempSync('cxp_artifact_outside_');
    storeDir = Directory.systemTemp.createTempSync('cxp_artifact_store_');
  });

  tearDown(() => <Directory>[open, outside, storeDir].forEach(_deleteQuietly));

  File waveform(Directory dir, String name) =>
      File(p.join(dir.path, name))
        ..writeAsStringSync(r'$date $end $enddefinitions $end');

  Future<void> record(String designId, String path) =>
      CxpWorkspaceStore(workspaceDirectory: storeDir.path).upsertArtifact(
        designId: designId,
        kind: 'waveform',
        path: path,
        producer: 'peer',
      );

  /// A root container whose rooted rule has [open] as its only root, over a
  /// workspace store that carries that rule — as the production store does.
  /// Nothing on the `request_open_artifact` route should consult either.
  ({ProviderContainer root, TabContainerManager tcm}) boot({
    List<Override> extra = const <Override>[],
  }) {
    final containment = CxpPathContainment(roots: () => <String>[open.path]);
    final tcm = TabContainerManager(
      extraTabOverrides: [
        waveformSourceProvider.overrideWith(_OpenableSourceNotifier.new),
      ],
    );
    final root = ProviderContainer(
      overrides: <Override>[
        productTelemetryConfig,
        ...testWorkspaceOverrides(),
        tabContainerManagerProvider.overrideWithValue(tcm),
        cxpPathContainmentProvider.overrideWithValue(containment),
        cxpWorkspaceStoreProvider.overrideWithValue(
          CxpWorkspaceStore(
            workspaceDirectory: storeDir.path,
            containment: containment,
          ),
        ),
        ...extra,
      ],
    );
    tcm.init(root);
    addTearDown(() {
      tcm.dispose();
      root.dispose();
    });
    return (root: root, tcm: tcm);
  }

  Future<CxpHandlerResult> ask(
    ProviderContainer root, {
    String designId = 'unrecorded',
    String kind = 'waveform',
    String? hint,
  }) => dispatchCxpOpenArtifact(root.read(_refProvider), designId, kind, hint);

  /// The files open in a tab, in tab order.
  List<String?> opened(ProviderContainer root) => <String?>[
    for (final tab in root.read(tabListProvider)) tab.filePath,
  ];

  /// The file the active tab's waveform source was opened from.
  String? activeSource(
    ({ProviderContainer root, TabContainerManager tcm}) env,
  ) => env.tcm
      .containerFor(env.root.read(activeTabIdProvider))
      .read(waveformSourceProvider.notifier)
      .currentFilePath;

  group('request_open_artifact', () {
    test('a recorded waveform inside the open directories is opened in a new '
        'tab', () async {
      final file = waveform(open, 'fsm.vcd');
      await record('d1', file.path);
      final env = boot();
      final result = await ask(env.root, designId: 'd1');
      expect(result.honored, isTrue, reason: result.reason);
      expect(result.reason, isNull);
      expect(opened(env.root), <String>[file.path]);
      expect(activeSource(env), file.path);
    });

    test(
      'a kind other than waveform is declined, and nothing is opened',
      () async {
        final file = waveform(open, 'fsm.vcd');
        await record('d1', file.path);
        final env = boot();
        final result = await ask(
          env.root,
          designId: 'd1',
          kind: 'source',
          hint: file.path,
        );
        expect(result.honored, isFalse);
        expect(result.reason, contains('only waveform artifacts'));
        expect(opened(env.root), isEmpty);
      },
    );

    test('no record and no hint is declined', () async {
      final env = boot();
      final result = await ask(env.root, designId: 'unknown');
      expect(result.honored, isFalse);
      expect(result.reason, contains('no waveform artifact recorded'));
      expect(opened(env.root), isEmpty);
    });

    test('with no record, the peer hint inside the open directories is '
        'opened', () async {
      final file = waveform(open, 'hinted.vcd');
      final env = boot();
      final result = await ask(env.root, hint: file.path);
      expect(result.honored, isTrue, reason: result.reason);
      expect(opened(env.root), <String>[file.path]);
    });

    // The waveform the VS Code extension hands over is, as often as not, one
    // WaveCrux has never opened. MUTATION: checking the path with
    // `cxpPathContainmentProvider` in `dispatchCxpOpenArtifact` instead of
    // `kCxpOpenArtifactContainment` makes this red.
    test('with no record, a peer hint outside the open directories is '
        'opened: the floor applies, not the roots', () async {
      final file = waveform(outside, 'never_opened.vcd');
      final env = boot();
      final result = await ask(env.root, hint: file.path);
      expect(result.honored, isTrue, reason: result.reason);
      expect(opened(env.root), <String>[file.path]);
      expect(activeSource(env), file.path);
    });

    // The extension publishes the waveform into the shared workspace before
    // it sends, so this is the path its hand-off normally takes. The store
    // the app provides is rooted and would drop the record; the route reads
    // the same directory under the floor. MUTATION: resolving through
    // `resolveWaveformArtifactPath` (the rooted store) in
    // `dispatchCxpOpenArtifact` makes this red.
    test('a record outside the open directories is opened, though the rooted '
        'store drops it', () async {
      final file = waveform(outside, 'published.vcd');
      await record('d-published', file.path);
      final env = boot();
      expect(
        resolveWaveformArtifactPath(env.root.read(_refProvider), 'd-published'),
        isNull,
        reason: 'the premise: the rooted store drops this record',
      );
      final result = await ask(env.root, designId: 'd-published');
      expect(result.honored, isTrue, reason: result.reason);
      expect(opened(env.root), <String>[file.path]);
    });

    test('a record inside the open directories wins over a hint outside '
        'them', () async {
      final recorded = waveform(open, 'recorded.vcd');
      final hinted = waveform(outside, 'hinted.vcd');
      await record('d2', recorded.path);
      final env = boot();
      final result = await ask(env.root, designId: 'd2', hint: hinted.path);
      expect(result.honored, isTrue, reason: result.reason);
      expect(opened(env.root), <String>[recorded.path]);
    });

    // The receiver's own resolution comes first (CXP §9.10), wherever the
    // record points. MUTATION: resolving through the rooted store makes this
    // fall back to the hint, and it goes red.
    test('a record outside the open directories still wins over a hint '
        'inside them', () async {
      final recorded = waveform(outside, 'recorded.vcd');
      final hinted = waveform(open, 'hinted.vcd');
      await record('d3', recorded.path);
      final env = boot();
      final result = await ask(env.root, designId: 'd3', hint: hinted.path);
      expect(result.honored, isTrue, reason: result.reason);
      expect(opened(env.root), <String>[recorded.path]);
    });

    test('a malformed hint is refused before anything is opened, and the '
        'reason never repeats it', () async {
      final inside = waveform(open, 'real.vcd').path;
      final hints = <String>[
        '',
        '   ',
        'relative/dump.vcd',
        './dump.vcd',
        '../${p.basename(open.path)}/real.vcd',
        '-rf',
        '+:!curl x|sh',
        'file://$inside',
        ' $inside',
        '$inside\n',
      ];
      final env = boot();
      for (final hint in hints) {
        final result = await ask(env.root, hint: hint);
        expect(result.honored, isFalse, reason: 'hint ${hint.codeUnits}');
        if (hint.trim().isNotEmpty) {
          expect(result.reason, isNot(contains(hint.trim())));
        }
        expect(opened(env.root), isEmpty, reason: 'hint ${hint.codeUnits}');
      }
    });

    // The floor is what stands between a peer and an open now, so each of
    // its refusals is pinned by a case only it can refuse.
    group('the floor refuses', () {
      // Relative to where WaveCrux runs, this names a real waveform, so
      // nothing after the floor would stop it. MUTATION: deleting the
      // `kCxpOpenArtifactContainment.refuse(path)` check opens it, and this
      // goes red.
      test('a relative path, even one naming a file from where WaveCrux '
          'runs', () async {
        // WaveCrux runs from the open directory for this case. Relativising
        // the temp file against the test's own working directory instead
        // cannot work everywhere: on Windows the two can sit on different
        // drives, and no relative path crosses a drive.
        final previous = Directory.current;
        Directory.current = open;
        addTearDown(() => Directory.current = previous);
        final relative = p.basename(waveform(open, 'relative.vcd').path);
        expect(p.isRelative(relative), isTrue);
        expect(
          FileSystemEntity.typeSync(relative),
          FileSystemEntityType.file,
          reason: 'the case must name a real file, or it proves nothing',
        );
        final env = boot();
        final result = await ask(env.root, hint: relative);
        expect(result.honored, isFalse);
        expect(result.reason, 'file_path must be an absolute path');
        expect(opened(env.root), isEmpty);
      });

      // A NUL ends the name where the operating system reads it, so what was
      // checked is not what would be opened.
      test('a path carrying a NUL', () async {
        final file = waveform(open, 'nul.vcd');
        final env = boot();
        for (final hint in <String>[
          '${file.path} ',
          '${file.path} .txt',
          '${open.path} /nul.vcd',
        ]) {
          final result = await ask(env.root, hint: hint);
          expect(result.honored, isFalse, reason: 'hint ${hint.codeUnits}');
          expect(result.reason, 'file_path contains a NUL character');
          expect(opened(env.root), isEmpty, reason: 'hint ${hint.codeUnits}');
        }
      });

      // The string checked is the string opened. A trailing space is part of
      // a POSIX file name, so `padded.vcd ` is a real file here and a
      // different one from `padded.vcd`; a check that trimmed first would
      // pass the one name and open the other. `crux_cxp`'s floor judges the
      // string as spelled and refuses a padded one in its own words, so this
      // pins that rule as the route applies it. MUTATION: deleting the
      // `kCxpOpenArtifactContainment.refuse(path)` check in
      // `dispatchCxpOpenArtifact` opens `padded.vcd `, and this goes red.
      test('a path padded with white space, though the padded name is a real '
          'file', () async {
        waveform(open, 'padded.vcd');
        final trailing = waveform(open, 'padded.vcd ').path;
        expect(
          FileSystemEntity.typeSync(trailing),
          FileSystemEntityType.file,
          reason: 'the case must name a real file, or it proves nothing',
        );
        final plain = p.join(open.path, 'padded.vcd');
        final env = boot();
        for (final hint in <String>[trailing, ' $plain', '$plain\t']) {
          final result = await ask(env.root, hint: hint);
          expect(result.honored, isFalse, reason: 'hint ${hint.codeUnits}');
          expect(result.reason, 'file_path begins or ends with white space');
          expect(opened(env.root), isEmpty, reason: 'hint ${hint.codeUnits}');
        }

        // The same name arriving as a record rather than a hint. The store
        // reads its records under the same floor and drops this one, so the
        // design resolves to nothing rather than to the padded name.
        await record('d-padded', trailing);
        final result = await ask(env.root, designId: 'd-padded');
        expect(result.honored, isFalse);
        expect(
          result.reason,
          'no waveform artifact recorded for design '
          '"d-padded"',
        );
        expect(opened(env.root), isEmpty);
      });
    });

    // Opening a missing file would leave a tab holding nothing but an error.
    // MUTATION: deleting the `FileSystemEntity.typeSync` check in
    // `dispatchCxpOpenArtifact` creates the tab, and this goes red.
    test('a hint naming no file here is declined, and no tab is '
        'created', () async {
      final env = boot();
      for (final missing in <String>[
        p.join(outside.path, 'deleted.vcd'),
        p.join(outside.path, 'no', 'such', 'dir.vcd'),
        outside.path, // a directory, not a file
      ]) {
        final result = await ask(env.root, hint: missing);
        expect(result.honored, isFalse, reason: missing);
        expect(result.reason, 'the artifact is not a file here');
        expect(opened(env.root), isEmpty, reason: missing);
      }
    });

    group('over a socket, through the server the app builds', () {
      /// The server [CxpServerNotifier.startServer] builds, bound to an
      /// ephemeral port, and a client connected to it.
      Future<
        ({
          ProviderContainer root,
          TabContainerManager tcm,
          LocalCxpClient client,
        })
      >
      serve() async {
        final peers = Directory.systemTemp.createTempSync(
          'cxp_artifact_peers_',
        );
        addTearDown(() => _deleteQuietly(peers));
        final env = boot(
          extra: <Override>[
            cxpManifestDirectoryProvider.overrideWith(
              (ref) async => peers.path,
            ),
          ],
        );
        final notifier = env.root.read(cxpServerProvider.notifier);
        expect(await notifier.startServer(0), isNull);
        addTearDown(notifier.stopServer);
        final client = LocalCxpClient(
          selfIdentity: const PeerIdentity(
            peerId: 'open-artifact-test',
            productName: 'vscode',
            productVersion: '0.0.0-test',
          ),
        );
        await client.connect(
          host: '127.0.0.1',
          port: env.root.read(cxpServerProvider).port,
          token: cxpProcessAuthToken,
        );
        addTearDown(client.dispose);
        return (root: env.root, tcm: env.tcm, client: client);
      }

      Future<RequestOpenArtifactAck> send(
        LocalCxpClient client,
        RequestOpenArtifact request,
      ) async {
        final reply = client.inbound.firstWhere(
          (m) => m.message is RequestOpenArtifactAck,
        );
        client.send(request);
        return (await reply.timeout(const Duration(seconds: 5))).message
            as RequestOpenArtifactAck;
      }

      // `LocalCxpServer` screens the hint on the wire before the handler sees
      // it, and a rooted screen there strips the hint for a waveform never
      // opened. No record is written, so the hint is all the handler has.
      // MUTATION: handing `WaveCruxCxpServer` the rooted
      // `cxpPathContainmentProvider` in `CxpServerNotifier.startServer` makes
      // this red.
      test('the hint for a waveform never opened crosses the wire, and it is '
          'opened', () async {
        final file = waveform(outside, 'never_opened.vcd');
        final env = await serve();
        final ack = await send(
          env.client,
          RequestOpenArtifact(
            designId: 'unrecorded',
            artifactKind: 'waveform',
            path: file.path,
          ),
        );
        expect(ack.honored, isTrue, reason: ack.reason);
        expect(opened(env.root), <String>[file.path]);
      });

      // The wire screen is `crux_cxp`'s floor too, and it judges the string
      // as spelled, so a padded hint never crosses the wire: the server
      // strips a hint that fails the rule (a refused hint is no fallback),
      // and the handler, with no record and no hint, has nothing to open.
      // The reason says where it stopped: a hint that reached the handler
      // would be refused there, in the floor's words about white space.
      test('a padded hint is stripped on the wire, and nothing is '
          'opened', () async {
        waveform(open, 'padded.vcd');
        final trailing = waveform(open, 'padded.vcd ').path;
        final env = await serve();
        final ack = await send(
          env.client,
          RequestOpenArtifact(
            designId: 'unrecorded',
            artifactKind: 'waveform',
            path: trailing,
          ),
        );
        expect(ack.honored, isFalse);
        expect(
          ack.reason,
          'no waveform artifact recorded for design "unrecorded"',
        );
        expect(opened(env.root), isEmpty);
      });
    });
  });

  // Everything above fixes the roots. These run the production provider —
  // `cxpPathContainmentProvider` as the app builds it — over a workspace with
  // one open tab and a recent-files list, so the roots under test are the
  // ones WaveCrux actually uses.
  group('with the production roots', () {
    late Directory tabDir;
    late Directory recentDir;
    late Directory neverDir;

    setUp(() {
      tabDir = Directory.systemTemp.createTempSync('cxp_roots_tab_');
      recentDir = Directory.systemTemp.createTempSync('cxp_roots_recent_');
      neverDir = Directory.systemTemp.createTempSync('cxp_roots_never_');
      addTearDown(
        () => <Directory>[tabDir, recentDir, neverDir].forEach(_deleteQuietly),
      );
    });

    Future<({ProviderContainer root, TabContainerManager tcm})>
    bootApp() async {
      final recent = waveform(recentDir, 'closed.vcd');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'recent_files': <String>[recent.path],
      });
      final tcm = TabContainerManager(
        extraTabOverrides: [
          waveformSourceProvider.overrideWith(_OpenableSourceNotifier.new),
        ],
      );
      final root = ProviderContainer(
        overrides: <Override>[
          productTelemetryConfig,
          ...testWorkspaceOverrides(),
          tabContainerManagerProvider.overrideWithValue(tcm),
          // The production store, pointed at a temp directory and carrying
          // the production rule.
          cxpWorkspaceStoreProvider.overrideWith(
            (ref) => CxpWorkspaceStore(
              workspaceDirectory: storeDir.path,
              containment: ref.watch(cxpPathContainmentProvider),
            ),
          ),
        ],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });
      await root.read(recentFilesProvider.future);
      // The user has a waveform open in a tab; it has not been loaded, so a
      // cross-probe's signal cannot resolve in it.
      await root.wavecruxWorkspace.openFile(p.join(tabDir.path, 'open.vcd'));
      await root.wavecruxWorkspace.flushPendingSave();
      return (root: root, tcm: tcm);
    }

    group('request_open_artifact', () {
      test('a waveform in an open tab directory is opened', () async {
        final env = await bootApp();
        final file = waveform(tabDir, 'sibling.vcd');
        await record('d-tab', file.path);
        final result = await ask(env.root, designId: 'd-tab');
        expect(result.honored, isTrue, reason: result.reason);
        expect(activeSource(env), file.path);
      });

      test(
        'a waveform whose tab was closed — in the recent files — is opened',
        () async {
          final env = await bootApp();
          final file = File(p.join(recentDir.path, 'closed.vcd'));
          await record('d-closed', file.path);
          final result = await ask(env.root, designId: 'd-closed');
          expect(result.honored, isTrue, reason: result.reason);
          expect(activeSource(env), file.path);
        },
      );

      // The case the route exists for: "Open in WaveCrux Desktop" on a
      // waveform this installation has never seen. It was refused while the
      // route was rooted. The extension publishes the record before it
      // sends, and no hint is sent here, so the record alone has to carry
      // it. MUTATION: restoring the rooted resolution, or the rooted check,
      // in `dispatchCxpOpenArtifact` makes this red.
      test(
        'a waveform never opened in this installation is honoured under the '
        'floor',
        () async {
          final env = await bootApp();
          final file = waveform(neverDir, 'never.vcd');
          await record('d-never', file.path);
          final result = await ask(env.root, designId: 'd-never');
          expect(result.honored, isTrue, reason: result.reason);
          expect(activeSource(env), file.path);
        },
      );
    });

    // The `crux.design_id` fallback keeps the roots: a peer attaches the id
    // to a cross-probe, and the record it selects would be opened without the
    // user asking for that waveform. MUTATION, each measured: replacing the
    // rooted rule with the floor (`const CxpPathContainment()`) in
    // `cxpPathContainment` turns 'never opened' red; dropping the recent-files
    // loop from `cxpOpenDirectories` turns 'closed tab' red.
    group('the crux.design_id fallback', () {
      Future<CxpHandlerResult> probe(ProviderContainer root, String id) =>
          dispatchCxpHighlight(
            root.read(_refProvider),
            const ElementId(kind: ElementKind.signal, path: 'top.clk'),
            <String, Object?>{cxpDesignIdMetadataKey: id},
          );

      test('opens a waveform in an open tab directory', () async {
        final env = await bootApp();
        final file = waveform(tabDir, 'sibling.vcd');
        await record('d-tab', file.path);
        final result = await probe(env.root, 'd-tab');
        expect(result.honored, isTrue, reason: result.reason);
        expect(activeSource(env), file.path);
      });

      test(
        'opens a waveform whose tab was closed — in the recent files',
        () async {
          final env = await bootApp();
          final file = File(p.join(recentDir.path, 'closed.vcd'));
          await record('d-closed', file.path);
          final result = await probe(env.root, 'd-closed');
          expect(result.honored, isTrue, reason: result.reason);
          expect(activeSource(env), file.path);
        },
      );

      test('refuses a waveform never opened in this installation', () async {
        final env = await bootApp();
        final file = waveform(neverDir, 'never.vcd');
        await record('d-never', file.path);
        final tabsBefore = opened(env.root);
        final result = await probe(env.root, 'd-never');
        expect(result.honored, isFalse);
        expect(result.reason, isNot(contains(file.path)));
        expect(opened(env.root), tabsBefore);
      });
    });
  });
}

/// Deletes [dir], tolerating a server that is still removing its manifest
/// from it.
void _deleteQuietly(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // Best effort.
  }
}

/// Provider exposing the container's [Ref] so tests can pass it to the
/// dispatch functions without subclassing a notifier.
final _refProvider = Provider<Ref>((ref) => ref);

/// A per-tab [WaveformSourceNotifier] that starts empty and "opens" any path
/// into a fixed fake source with `top.clk` — a stand-in for a real parse, so
/// what is under test is which path reaches the open, not the parser.
class _OpenableSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<FakeWaveformDataSource?> build() =>
      const AsyncData<FakeWaveformDataSource?>(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    currentFilePath = path;
    state = AsyncData(
      FakeWaveformDataSource(
        scopes: const [
          Scope(
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
            ],
          ),
        ],
      ),
    );
  }
}
