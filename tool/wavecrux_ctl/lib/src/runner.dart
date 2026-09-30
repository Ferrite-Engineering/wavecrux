// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:args/command_runner.dart';

import 'client.dart';
import 'commands.dart';

/// Command runner for `wavecrux-ctl`.
///
/// Registers all subcommands and global options (`--host`, `--port`, `--json`).
class WavecruxCtlRunner extends CommandRunner<void> {
  WavecruxCtlRunner({IOSink? output, WcpClientFactory? clientFactory})
    : super(
        'wavecrux-ctl',
        'Control a running WaveCrux instance via its remote control API.',
      ) {
    final out = output ?? stdout;
    final factory = clientFactory ?? (h, p) => WcpClient(host: h, port: p);

    argParser
      ..addOption(
        'host',
        abbr: 'H',
        defaultsTo: 'localhost',
        help: 'WaveCrux host address.',
      )
      ..addOption(
        'port',
        abbr: 'p',
        defaultsTo: '${WcpClient.defaultPort}',
        help: 'WaveCrux remote control port.',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output raw JSON instead of formatted text.',
      );

    addCommand(LoadCommand(output: out, factory: factory));
    addCommand(AddCommand(output: out, factory: factory));
    addCommand(RemoveCommand(output: out, factory: factory));
    addCommand(CursorCommand(output: out, factory: factory));
    addCommand(MarkerCommand(output: out, factory: factory));
    addCommand(ZoomCommand(output: out, factory: factory));
    addCommand(FitCommand(output: out, factory: factory));
    addCommand(SignalsCommand(output: out, factory: factory));
    addCommand(ValueCommand(output: out, factory: factory));
    addCommand(HierarchyCommand(output: out, factory: factory));
    addCommand(StatusCommand(output: out, factory: factory));
  }
}
