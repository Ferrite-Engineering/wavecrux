// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/remote/providers/cxp_server_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';

part 'cxp_workspace_link.g.dart';

/// The shared-workspace artifact kind WaveCrux both produces and consumes.
///
/// WaveCrux is the suite's waveform viewer: it *produces* `waveform` records
/// (producer, see [publishWaveformWorkspaceArtifact]) and *consumes* them
/// when a cross-probe it cannot satisfy locally names a design whose waveform
/// it can open (consumer, in `cxp_inbound_handlers.dart`).
const String kCxpWaveformArtifactKind = 'waveform';

/// WaveCrux's producer short-name stamped into workspace records.
const String kWavecruxProducer = 'wavecrux';

/// The directories the user has opened, as CXP §11's containment rule
/// consumes them.
///
/// Two sources, both "the user opened this":
///
/// * the containing directory of every file open in a tab, and
/// * the containing directory of every entry in the recent-files list — a
///   file the user picked in this installation, which is what makes a
///   cross-probe into a design whose tab was closed still land.
///
/// These roots guard the `crux.design_id` fallback a cross-probe takes when
/// its signal is not in an open waveform, and every path handed to an editor
/// command. `request_open_artifact` is not rooted at all: see
/// [kCxpOpenArtifactContainment] for why it is held to the floor.
///
/// Read on every containment check rather than snapshotted when the server
/// starts: a design opened after CXP came up is one the user opened, and a
/// snapshot would report otherwise for the rest of the process's life.
/// Recent files is an [AsyncValue]; before it resolves this yields the open
/// tabs alone rather than blocking the check.
Iterable<String> cxpOpenDirectories(Ref ref) {
  final roots = <String>{};
  for (final tab in ref.read(tabListProvider)) {
    final path = tab.filePath;
    if (path != null && path.isNotEmpty) roots.add(p.dirname(path));
  }
  for (final path in ref.read(recentFilesProvider).value ?? const <String>[]) {
    if (path.isNotEmpty) roots.add(p.dirname(path));
  }
  return roots;
}

/// The rooted [CxpPathContainment]: a peer-supplied path must lie inside
/// [cxpOpenDirectories].
///
/// One instance, so the routes that keep the roots apply the *same* rule,
/// which is what CXP §11 requires of an artifact resolved through our own
/// records: [cxpWorkspaceStore] screens what it resolves for the
/// `crux.design_id` fallback, and the inbound handlers check once more on
/// the value they are about to open from that fallback or hand to an editor
/// command (`request_open_source`).
///
/// `request_open_artifact` is held to [kCxpOpenArtifactContainment] instead,
/// and so is `LocalCxpServer`'s screen of the wire, because that one rule
/// covers the artifact request's hint as well as `request_open_source`.
@Riverpod(keepAlive: true)
CxpPathContainment cxpPathContainment(Ref ref) =>
    CxpPathContainment(roots: () => cxpOpenDirectories(ref));

/// The rule a `request_open_artifact` is held to: CXP §11.3's floor, and
/// not the directories the user has opened.
///
/// The floor refuses what a path must never be on its way into an open:
/// empty, relative (resolved against whatever directory WaveCrux was
/// launched from), carrying a NUL, or padded with white space. It judges the
/// string exactly as spelled, so the string checked is the string opened: a
/// padded path is refused rather than trimmed into a different file.
///
/// It is not rooted, because on this route a rooted rule is secure and
/// useless at once. `request_open_artifact` exists to open a waveform
/// WaveCrux does not have open: the VS Code extension's "Open in WaveCrux
/// Desktop" sends it for the waveform in the active tab, which is, as often
/// as not, a dump in a simulation run folder this installation has never
/// seen. Rooted on the open tabs and the recent files, the rule refused
/// exactly the request the route serves, and the roots bought nothing to pay
/// for that:
///
/// * the sender is already a same-user process. Since CXP 1.2 a peer must
///   present the per-process token WaveCrux publishes in its manifest, which
///   only a process that can read this user's application data can do, and
///   such a process can already read any file WaveCrux could be asked to
///   open;
/// * WaveCrux only parses what this route opens. The file is read as a
///   waveform and drawn in a new tab of the user's own window; nothing in it
///   is executed.
///
/// The "Debug in WaveCrux" hand-off, a `request_highlight` naming a waveform
/// (`_kSourceHandoffFloor` in `cxp_inbound_handlers.dart`), took the same
/// decision first.
///
/// The roots stay where they still buy something ([cxpPathContainment]): the
/// `crux.design_id` fallback resolves an id a peer attached to a cross-probe
/// through store records nobody asked WaveCrux to open, and
/// `request_open_source` hands its path to an editor command line.
const CxpPathContainment kCxpOpenArtifactContainment = CxpPathContainment();

/// The shared design→artifact link store.
///
/// A single keep-alive instance rooted at the suite-shared workspace directory
/// (`sharedCxpWorkspaceDirectory()`). Overridable in tests to redirect the
/// store at a temp directory so no test touches the real per-user workspace.
///
/// Carries [cxpPathContainmentProvider] so a record written by a peer — the
/// workspace directory is user-writable, and the sender chose the `design_id`
/// that selects the record — cannot name a file outside the directories this
/// session has open (CXP §11). `request_open_artifact` reads the same records
/// under its own rule instead: see [resolveOpenArtifactWaveformPath].
@Riverpod(keepAlive: true)
CxpWorkspaceStore cxpWorkspaceStore(Ref ref) =>
    CxpWorkspaceStore(containment: ref.watch(cxpPathContainmentProvider));

/// Records the just-opened [source] at [path] in the shared workspace so a peer
/// that receives a cross-probe it cannot satisfy locally can resolve and open
/// this waveform (producer).
///
/// The record is keyed by the design's `design_id` — derived from the
/// waveform's containing directory via the one shared [cxpDesignIdForPath]
/// helper, so it byte-matches the id SimCrux/NetCrux compute for the same
/// design folder. The wave's internal top scope (`tb_cdc_capture` vs the DUT
/// `cdc_capture`) never enters the key; it rides along only as the resolver
/// hint [WorkspaceArtifact.topModule].
///
/// Gated on the CXP server running: with CXP off there is no peer to serve and
/// no reason to write into the shared workspace directory — which also keeps
/// the wide swath of waveform-open tests from writing into the real per-user
/// workspace. Best-effort throughout: a failed upsert must never break opening
/// a file, so every error is swallowed.
Future<void> publishWaveformWorkspaceArtifact(
  Ref ref,
  String path,
  WaveformDataSource source,
) async {
  if (!ref.read(cxpServerProvider).isRunning) return;
  final topModule = source.rootScopes.isEmpty
      ? null
      : source.rootScopes.first.name;
  try {
    await ref
        .read(cxpWorkspaceStoreProvider)
        .upsertArtifact(
          designId: cxpDesignIdForPath(path),
          kind: kCxpWaveformArtifactKind,
          path: path,
          producer: kWavecruxProducer,
          topModule: topModule,
          basename: p.basename(path),
        );
  } on Object {
    // The workspace link is a courtesy; never let a workspace write surface as an error
    // on the file-open path.
  }
}

/// Resolves the shared-workspace `waveform` artifact for the design named by
/// [designId], preferring an exact `design_id`+kind match and falling back to
/// the descriptive [topModule]/[basename] hints (consumer resolution).
///
/// Returns the absolute path to open, or null when the design has no waveform
/// artifact recorded. The caller opens it through the ordinary
/// [WaveformSourceNotifier.openFile] path (a new tab), exactly as the SimCrux
/// "Debug in WaveCrux" source handoff does.
///
/// Reads through [cxpWorkspaceStoreProvider], so a record outside the
/// directories the user has opened resolves to null: this is the
/// `crux.design_id` fallback's resolution. `request_open_artifact` uses
/// [resolveOpenArtifactWaveformPath].
String? resolveWaveformArtifactPath(
  Ref ref,
  String designId, {
  String? topModule,
  String? basename,
}) {
  if (designId.isEmpty) return null;
  final artifact = ref
      .read(cxpWorkspaceStoreProvider)
      .resolveArtifact(
        designId,
        kCxpWaveformArtifactKind,
        topModule: topModule,
        basename: basename,
      );
  return artifact?.path;
}

/// Resolves the `waveform` artifact recorded for [designId] the way
/// `request_open_artifact` needs it: the records [cxpWorkspaceStoreProvider]
/// reads, from the same directory, admitted by [kCxpOpenArtifactContainment]
/// rather than by the rooted rule that store carries.
///
/// Reading them through the rooted store would drop the record for a
/// waveform WaveCrux has never opened, and the request would be refused as
/// though nothing were recorded — the failure [kCxpOpenArtifactContainment]
/// explains. The store keeps no state between reads, so a second view of the
/// directory costs nothing.
///
/// Returns the absolute path WaveCrux should open, or null when the design
/// has no waveform artifact recorded.
String? resolveOpenArtifactWaveformPath(Ref ref, String designId) {
  if (designId.isEmpty) return null;
  final store = ref.read(cxpWorkspaceStoreProvider);
  return CxpWorkspaceStore(
    workspaceDirectory: store.workspaceDirectory,
    ttl: store.ttl,
    containment: kCxpOpenArtifactContainment,
  ).resolveArtifact(designId, kCxpWaveformArtifactKind)?.path;
}
