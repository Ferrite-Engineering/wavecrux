// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_io/crux_io.dart' show canonicalPathKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_lists.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';
import 'package:wavecrux/services/links/wavecrux_link_target.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// The links found on this launch's command line (Windows and Linux open a
/// link by starting the application with it as an argument).
///
/// Empty when the launch was an ordinary one. `bootstrap` overrides it with
/// [WaveCruxLaunchArgs.links]; the app hands them to the link inbox once the
/// startup restore has settled.
final Provider<List<String>> initialWaveCruxLinksProvider =
    Provider<List<String>>((ref) => const <String>[]);

/// Asks the user whether to open a file a link named. Resolves true only when
/// they chose to open it.
typedef WaveCruxLinkConsent = Future<bool> Function(String path);

/// Why a link opened nothing.
enum WaveCruxLinkFailure {
  /// The link did not parse. See [WaveCruxLinkOutcome.parseRefusal].
  malformed,

  /// The path is not an absolute, well-formed local path.
  pathRefused,

  /// The file is not a waveform format a link may open.
  notAWaveform,

  /// The file is not there.
  fileNotFound,

  /// The file opened in a tab, and the tab shows why it could not be read.
  loadFailed,
}

/// What handling a link did, for the caller to tell the user.
@immutable
class WaveCruxLinkOutcome {
  /// A link that opened nothing.
  const WaveCruxLinkOutcome.failed(
    WaveCruxLinkFailure this.failure, {
    this.fileName,
    this.parseRefusal,
  }) : declined = false,
       path = null,
       openedTab = false,
       signal = null,
       signalNotFound = false,
       timeNotPlaced = false,
       timeClamped = false;

  /// A link the user chose not to open.
  const WaveCruxLinkOutcome.declined({required String this.path})
    : failure = null,
      declined = true,
      fileName = null,
      parseRefusal = null,
      openedTab = false,
      signal = null,
      signalNotFound = false,
      timeNotPlaced = false,
      timeClamped = false;

  /// A link whose file is now the active tab.
  const WaveCruxLinkOutcome.opened({
    required String this.path,
    required this.openedTab,
    this.signal,
    this.signalNotFound = false,
    this.timeNotPlaced = false,
    this.timeClamped = false,
  }) : failure = null,
       declined = false,
       fileName = null,
       parseRefusal = null;

  /// Why nothing opened, or null when something did or the user declined.
  final WaveCruxLinkFailure? failure;

  /// The parser's reason, for [WaveCruxLinkFailure.malformed].
  final WaveCruxLinkRefusal? parseRefusal;

  /// The file's base name, for a failure that names it.
  final String? fileName;

  /// Whether the user cancelled the confirmation.
  final bool declined;

  /// The resolved file, once the link got that far.
  final String? path;

  /// Whether a new tab was created, as opposed to an open one focused.
  final bool openedTab;

  /// The signal the link asked for.
  final String? signal;

  /// The link named a signal the file does not have.
  final bool signalNotFound;

  /// The link named a time with a unit, and the file declares no timescale.
  final bool timeNotPlaced;

  /// The link's time lay outside the file and the cursor went to the nearest
  /// end.
  final bool timeClamped;

  /// Whether the file is now open.
  bool get opened => failure == null && !declined;
}

/// Opens what a link names: parses it, vets the file, asks the user when the
/// file is not one they have opened before, then opens the file in a new tab
/// (or focuses the tab that already has it), adds and selects the signal, and
/// puts the primary cursor at the time.
///
/// Never throws, never runs anything, never fetches anything. The file must
/// exist, be a waveform format ([kWaveCruxLinkExtensions]) both as named and
/// once symbolic links resolve, and pass the CXP receive floor
/// ([kWaveCruxLinkContainment]). The resolved path is what is shown in the
/// confirmation, re-checked after the user answers, and opened.
///
/// [confirm] is asked only for a file that is neither open in a tab nor in
/// the recent-files list ([wasOpenedBefore]). A file opened from a link is not
/// added to recent files, so the answer is not remembered.
///
/// An unknown signal or a time that cannot be placed still opens the file;
/// the outcome says what was not done.
Future<WaveCruxLinkOutcome> openWaveCruxLink(
  ProviderContainer root,
  String raw, {
  required WaveCruxLinkConsent confirm,
}) async {
  final WaveCruxLink link;
  switch (parseWaveCruxLink(raw)) {
    case WaveCruxLinkRejected(:final refusal):
      return WaveCruxLinkOutcome.failed(
        WaveCruxLinkFailure.malformed,
        parseRefusal: refusal,
      );
    case WaveCruxLinkParsed(link: final parsed):
      link = parsed;
  }

  final fileName = _displayName(link.file);
  var target = vetWaveCruxLinkTarget(link.file);
  final String path;
  switch (target) {
    case WaveCruxLinkTargetRefused(:final refusal):
      return _refused(refusal, fileName);
    case WaveCruxLinkTargetAccepted(path: final resolved):
      path = resolved;
  }

  final openedBefore = wasOpenedBefore(
    path,
    openTabPaths: root.read(tabListProvider).map((t) => t.filePath),
    recentPaths: root.read(recentFiles.provider),
  );
  if (!openedBefore) {
    final bool agreed;
    try {
      agreed = await confirm(path);
    } on Object {
      return WaveCruxLinkOutcome.declined(path: path);
    }
    if (!agreed) return WaveCruxLinkOutcome.declined(path: path);
    // The question may have been on screen for a while. Check again, and
    // open only if the same file is still what the link resolves to.
    target = vetWaveCruxLinkTarget(path);
    switch (target) {
      case WaveCruxLinkTargetRefused(:final refusal):
        return _refused(refusal, fileName);
      case WaveCruxLinkTargetAccepted(path: final again) when again != path:
        return WaveCruxLinkOutcome.failed(
          WaveCruxLinkFailure.fileNotFound,
          fileName: fileName,
        );
      case WaveCruxLinkTargetAccepted():
        break;
    }
  }

  final ({ProviderContainer tab, bool openedTab}) opened;
  try {
    opened = await _openOrFocus(root, path);
  } on Object {
    return WaveCruxLinkOutcome.failed(
      WaveCruxLinkFailure.loadFailed,
      fileName: fileName,
    );
  }
  final loaded = opened.tab.read(waveformSourceProvider);
  final source = loaded.value;
  if (loaded is AsyncError || source == null) {
    return WaveCruxLinkOutcome.failed(
      WaveCruxLinkFailure.loadFailed,
      fileName: fileName,
    );
  }

  var signalNotFound = false;
  final signal = link.signal;
  if (signal != null) {
    final match = resolveWaveCruxLinkSignal(
      signal,
      source.findVariables(const SignalFilter()),
    );
    if (match == null) {
      signalNotFound = true;
    } else {
      _addAndSelect(root, opened.tab, match);
    }
  }

  var timeNotPlaced = false;
  var timeClamped = false;
  final time = link.time;
  if (time != null) {
    final ticks = time.toTicks(source.timescale);
    if (ticks == null) {
      timeNotPlaced = true;
    } else {
      final start = BigInt.from(source.startTime);
      final end = BigInt.from(source.endTime);
      var at = ticks;
      if (at < start) {
        at = start;
        timeClamped = true;
      } else if (at > end) {
        at = end;
        timeClamped = true;
      }
      final tick = at.toInt();
      opened.tab.read(cursorStateProvider.notifier).placePrimary(tick);
      opened.tab.read(navigationProvider.notifier).jumpToTime(tick);
    }
  }

  return WaveCruxLinkOutcome.opened(
    path: path,
    openedTab: opened.openedTab,
    signal: signal,
    signalNotFound: signalNotFound,
    timeNotPlaced: timeNotPlaced,
    timeClamped: timeClamped,
  );
}

/// Finds the variable a link's `signal` names in [variables].
///
/// An exact hierarchical name wins. Otherwise the name may be the tail of one,
/// matched on whole segments (`dut.alu.carry` finds `tb.dut.alu.carry`, never
/// `tb.dut.alu.xcarry`), and only when exactly one variable has that tail: a
/// link that could mean two signals selects neither, rather than the wrong
/// one.
Variable? resolveWaveCruxLinkSignal(String name, List<Variable> variables) {
  for (final v in variables) {
    if (v.fullPath == name) return v;
  }
  final suffix = '.$name';
  Variable? only;
  for (final v in variables) {
    if (!v.fullPath.endsWith(suffix)) continue;
    if (only != null) return null;
    only = v;
  }
  return only;
}

/// Adds [match] to the tab's signal list unless it is there, and selects and
/// reveals it: the same three moves a CXP cross-probe makes.
void _addAndSelect(
  ProviderContainer root,
  ProviderContainer tab,
  Variable match,
) {
  final entries = tab.read(signalGroupsProvider).entries;
  if (!entries.any((e) => e.signalRef == match.signalRef)) {
    tab.read(signalGroupsProvider.notifier).addSignals([match]);
  }
  root.read(selectedSignalProvider.notifier).select(match.signalRef);
  tab.read(selectedVariablesProvider.notifier).selectOnly(match.fullPath);
  tab.read(revealSignalRequestProvider.notifier).request(match.fullPath);
}

/// Focuses the tab that already holds [path], by file identity, or opens a new
/// tab for it, and loads it when it is not loaded.
Future<({ProviderContainer tab, bool openedTab})> _openOrFocus(
  ProviderContainer root,
  String path,
) async {
  final key = canonicalPathKey(path);
  final tcm = root.read(tabContainerManagerProvider);
  for (final tab in root.read(tabListProvider)) {
    final existing = tab.filePath;
    if (existing == null || existing.isEmpty) continue;
    if (canonicalPathKey(existing) != key) continue;
    await root.wavecruxWorkspace.setActiveTab(tab.id);
    final container = tcm.containerFor(tab.id);
    if (container.read(waveformSourceProvider).value == null) {
      await container.read(waveformSourceProvider.notifier).openFile(existing);
    }
    return (tab: container, openedTab: false);
  }
  final tabId = await root.wavecruxWorkspace.openFile(path);
  final container = tcm.containerFor(tabId);
  await container.read(waveformSourceProvider.notifier).openFile(path);
  return (tab: container, openedTab: true);
}

WaveCruxLinkOutcome _refused(
  WaveCruxLinkTargetRefusal refusal,
  String fileName,
) => switch (refusal) {
  WaveCruxLinkTargetRefusal.pathRefused => const WaveCruxLinkOutcome.failed(
    WaveCruxLinkFailure.pathRefused,
  ),
  WaveCruxLinkTargetRefusal.notAWaveform => WaveCruxLinkOutcome.failed(
    WaveCruxLinkFailure.notAWaveform,
    fileName: fileName,
  ),
  WaveCruxLinkTargetRefusal.fileNotFound => WaveCruxLinkOutcome.failed(
    WaveCruxLinkFailure.fileNotFound,
    fileName: fileName,
  ),
  WaveCruxLinkTargetRefusal.unsupportedPlatform =>
    const WaveCruxLinkOutcome.failed(WaveCruxLinkFailure.malformed),
};

/// The base name of a link's path, shortened for a message. A link chooses
/// this text, so it is bounded before it reaches the screen.
String _displayName(String path) {
  final base = p.basename(path.replaceAll(r'\', '/'));
  return base.length <= 80 ? base : '${base.substring(0, 77)}...';
}

/// Holds links until the app can act on them, and handles them one at a time.
///
/// Nothing is handled before [markReady]: a link that launched the app waits
/// for the startup restore, so a tab it asks for is matched against the
/// restored tabs and its activation is the last word on focus. While one link
/// is being handled (its confirmation may be on screen), only the newest link
/// to arrive is kept; the ones in between are dropped, so a page that fires a
/// burst of links raises at most one more question.
class WaveCruxLinkInbox {
  /// Creates an inbox that hands each link to [handle].
  WaveCruxLinkInbox(this._handle);

  final Future<void> Function(String raw) _handle;
  bool _ready = false;
  bool _busy = false;
  String? _pending;

  /// Queues [raw], replacing any link still waiting.
  void add(String raw) {
    _pending = raw;
    unawaited(_drain());
  }

  /// Starts handling links.
  void markReady() {
    _ready = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (!_ready || _busy) return;
    _busy = true;
    try {
      while (_pending != null) {
        final raw = _pending!;
        _pending = null;
        try {
          await _handle(raw);
        } on Object {
          // One bad link never stops the next one.
        }
      }
    } finally {
      _busy = false;
    }
  }
}
