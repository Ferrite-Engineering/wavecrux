// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';
import 'package:wavecrux/services/session/session_service.dart';

/// File extension for named workspace documents. Mirrored from
/// `Workspace`-related serialization (see ARCHITECTURE.md §6.4).
const String _kWorkspaceFileExtension = '.wavecrux-workspace';

/// Parsed result of CLI argument parsing.
///
/// Pure-data structure consumed by `bootstrap()` to override the relevant
/// startup providers. Tests build a [CliArgs] directly to exercise startup
/// behavior without touching `Platform.executableArguments`.
class CliArgs {
  const CliArgs({
    this.initialFiles = const <String>[],
    this.initialSession,
    this.initialWorkspace,
    this.stdinMode = false,
    this.pipePath,
    this.reset = false,
    this.noRestore = false,
    this.wcpPort,
  });

  /// Bare positional waveform paths (`wavecrux a.fst b.vcd`).
  final List<String> initialFiles;

  /// A path that restores a whole view: a per-tab session export from
  /// `--session <path>` or a bare positional `.wavecrux`, or a
  /// `.wavecruxpack` share bundle.
  ///
  /// One field for both because they are the same startup intent — "open this
  /// arrangement, not this dump" — and the viewer dispatches on the extension
  /// when it loads. Splitting them would give startup two barriers to
  /// sequence for no behavioural difference.
  final String? initialSession;

  /// Named-workspace path picked from `--workspace <path>` or a bare
  /// positional `.wavecrux-workspace` argument. Triggers the
  /// "Open Workspace…" replace-with-confirmation flow at startup.
  final String? initialWorkspace;

  /// `--interactive` / `--stdin` flag.
  final bool stdinMode;

  /// `--pipe <path>` argument.
  final String? pipePath;

  /// `--reset` flag — clear all persisted restore state (the auto-managed
  /// `workspace.json`, every per-tab session sidecar, and the legacy
  /// `last_session.json` manifest) before launching into a fresh, empty
  /// workspace. The recovery escape hatch for a session so corrupt it wedges
  /// startup. Destructive but scoped: it does NOT touch app settings, the
  /// keymap, or recent-files history.
  final bool reset;

  /// `--no-restore` flag — skip restoring the previous session's waveforms for
  /// this launch only, without deleting anything. Restored tab chips still
  /// appear (so nothing is lost), but their waveforms are not auto-opened. The
  /// non-destructive first thing to try when the app hangs on startup: if it
  /// launches cleanly, the previous session was the culprit and `--reset`
  /// clears it permanently.
  final bool noRestore;

  /// `--wcp-port <n>` (or `--wcp-port=<n>`): run the WCP remote-control
  /// server for this process on port `n`, whatever Settings say, without
  /// writing the setting. `0` asks the OS for a free port, which is printed
  /// on stdout once bound. Null when the flag is absent or its value is not
  /// a port number; see [resolveWcpPortOverride] for the environment
  /// fallback.
  final int? wcpPort;
}

/// Environment variable that enables WCP for one process the way
/// `--wcp-port` does. The flag wins when both are given.
const String kWcpPortEnvVar = 'WAVECRUX_WCP_PORT';

/// Parses a WCP port value: an integer from 0 to 65535, else null.
int? parseWcpPort(String? raw) {
  final port = int.tryParse(raw?.trim() ?? '');
  if (port == null || port < 0 || port > 65535) return null;
  return port;
}

/// The per-process WCP port: `--wcp-port` from [cli] if given, else
/// [kWcpPortEnvVar] from [environment], else null (Settings decide).
int? resolveWcpPortOverride(CliArgs cli, Map<String, String> environment) =>
    cli.wcpPort ?? parseWcpPort(environment[kWcpPortEnvVar]);

/// Returns true if [path] ends with `.wavecrux-workspace` (case-insensitive).
bool isWorkspaceFilePath(String path) =>
    path.toLowerCase().endsWith(_kWorkspaceFileExtension);

/// Parses [args] into a [CliArgs] structure.
///
/// Argument grammar:
///
/// * `--session <path>` → per-tab session export (`.wavecrux`).
/// * `--workspace <path>` → named workspace (`.wavecrux-workspace`).
/// * `--interactive` / `--stdin` → read VCD from stdin.
/// * `--pipe <path>` → read VCD from named pipe.
/// * `--wcp-port <n>` / `--wcp-port=<n>` → per-process WCP port.
/// * Bare positional arguments are auto-routed:
///   - `.wavecrux-workspace` → [CliArgs.initialWorkspace]
///   - `.wavecrux` / `.wavecruxpack` → [CliArgs.initialSession]
///   - anything else → [CliArgs.initialFiles] (each becomes a tab); a
///     `<design>.crux-project` manifest or a design directory is resolved to
///     the waveform it names when the tab opens
///
/// Unknown flags are silently ignored — startup must never fail because a
/// user typed `--foo` they read about in an out-of-date blog post. The
/// first-run testing flags (`--reset-eula`, `--reset-telemetry-consent`) are
/// not modelled here either: `bootstrap()` acts on them through
/// `applyFirstRunResetFlags` before any of this state exists.
CliArgs parseCliArgs(List<String> args) {
  final initialFiles = <String>[];
  String? initialSession;
  String? initialWorkspace;
  var stdinMode = false;
  String? pipePath;
  var reset = false;
  var noRestore = false;
  int? wcpPort;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--session' && i + 1 < args.length) {
      i++;
      initialSession = args[i];
    } else if (a == '--workspace' && i + 1 < args.length) {
      i++;
      initialWorkspace = args[i];
    } else if (a == '--interactive' || a == '--stdin') {
      stdinMode = true;
    } else if (a == '--pipe' && i + 1 < args.length) {
      i++;
      pipePath = args[i];
    } else if (a == '--reset') {
      reset = true;
    } else if (a == '--no-restore') {
      noRestore = true;
    } else if (a == '--wcp-port' && i + 1 < args.length) {
      i++;
      wcpPort = parseWcpPort(args[i]);
    } else if (a.startsWith('--wcp-port=')) {
      wcpPort = parseWcpPort(a.substring('--wcp-port='.length));
    } else if (!a.startsWith('--')) {
      if (isWorkspaceFilePath(a)) {
        initialWorkspace = a;
      } else if (SessionService.isSessionFilePath(a) ||
          WaveCruxPackSpec.isPackFilePath(a)) {
        initialSession = a;
      } else {
        initialFiles.add(a);
      }
    }
  }

  return CliArgs(
    initialFiles: initialFiles,
    initialSession: initialSession,
    initialWorkspace: initialWorkspace,
    stdinMode: stdinMode,
    pipePath: pipePath,
    reset: reset,
    noRestore: noRestore,
    wcpPort: wcpPort,
  );
}

/// One-line `--help` blurb listing every supported CLI flag and bare
/// positional argument. Surfaced by `wavecrux --help` and embedded in user
/// guide reference material.
String cliHelpText() => '''
WaveCrux — modern waveform viewer

Usage:
  wavecrux [options] [files...]

Options:
  --session <path>    Open a .wavecrux per-tab session export at startup.
  --workspace <path>  Open a .wavecrux-workspace named workspace at startup
                      (replaces the current workspace after confirmation).
  --interactive       Read VCD from stdin (alias: --stdin).
  --stdin             Read VCD from stdin.
  --pipe <path>       Read VCD from the named pipe at <path>.
  --no-restore        Launch without reopening the previous session's
                      waveforms (nothing is deleted). Try this first if the
                      app hangs on startup.
  --wcp-port <n>      Run the WCP remote-control server on port <n> for this
                      launch only; the Remote Control setting is not
                      changed. 0 picks a free port and prints it. The
                      WAVECRUX_WCP_PORT environment variable does the same.
  --reset             Clear all saved session/workspace state (workspace,
                      per-tab sessions, legacy manifest) and launch empty.
                      Settings, keymap, and recent files are kept.
  --reset-eula        Testing aid. Forget this installation's acceptance of
                      the licence agreement so it is presented again on this
                      launch.
  --reset-telemetry-consent
                      Testing aid. Forget this installation's telemetry
                      answer so the one-time first-launch disclosure appears
                      again. The installation ID is kept. The dialog is only
                      shown at all on a build where telemetry is live --
                      --dart-define=TELEMETRY_DEV=true, or BETA_PERIOD=false.
  -h, --help          Show this help and exit.

Bare positional arguments are auto-routed by extension:
  *.wavecrux-workspace -> named workspace
  *.wavecrux           -> per-tab session export
  *.crux-project       -> design manifest; opens the waveform it names
  *                    -> waveform file (each opens as a new tab)

Examples:
  wavecrux dump.fst
  wavecrux a.fst b.vcd c.ghw
  wavecrux --workspace team-debug.wavecrux-workspace
  wavecrux dump.fst --session debug.wavecrux
''';
