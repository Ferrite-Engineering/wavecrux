// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The headless `wavecrux` command line and its MCP server.
///
/// `wavecrux info|search|values|transitions ... --json` writes one document
/// (`crux_mcp`'s envelope) and exits with the suite's code for its outcome;
/// `wavecrux mcp` serves the same four commands as tools over stdio, each
/// call running the command's own code, so a tool's text is byte for byte
/// what the command writes. No Flutter anywhere below this file:
/// `test/static/headless_cli_closure_test.dart` walks the imports.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crux_mcp/crux_mcp.dart';
import 'package:wavecrux/headless/cli_version.dart';
import 'package:wavecrux/headless/wave_commands.dart';
import 'package:wavecrux/headless/wave_file_cache.dart';

/// The `instructions` paragraph `initialize` returns: when to call the
/// server, and to cite with links. The full text is `docs/agent/WAVECRUX.md`.
const String kWaveCruxMcpInstructions =
    'WaveCrux reads simulation waveforms (VCD, FST, GHW and others) without '
    're-running the simulation. Call info first for the timescale and time '
    'range, search to find full signal paths, transitions for every value '
    'change of a signal between two times, and values for values at one time '
    "or at rising clock edges. Times are ticks of the file's timescale. "
    'Cite each finding with the link in its location, which opens the '
    'signal at that time in WaveCrux for a person to check.';

/// The `--license-file` help: the open-core tools need no licence.
const String _licenseHelp =
    'A licence file for the tools that need one. The four tools of this '
    'binary are free and read none.';

/// The headless command line: `wavecrux <command> ...`.
class WaveCruxCli {
  /// A command line serving [commands], opening files through [cache].
  ///
  /// [telemetry] makes the `mcp` server's counter; by default the one that
  /// sends under the consent the desktop app recorded (never when `CI` is
  /// set). [mapFailure] exists for the mutation proof only.
  WaveCruxCli({
    List<WaveCommand>? commands,
    WaveFileCache? cache,
    this.program = kWaveCruxProgram,
    McpExitCodes? exitCodes,
    McpTelemetry? Function()? telemetry,
    ReaderFailureMap mapFailure = classifyReaderFailure,
  }) : commands = List<WaveCommand>.unmodifiable(
         commands ?? openCoreWaveCommands(),
       ),
       exitCodes = exitCodes ?? McpExitCodes.suite,
       _telemetry = telemetry ?? waveCruxMcpTelemetry,
       commandContext = WaveCommandContext(
         cache: cache ?? WaveFileCache(),
         program: program,
         mapFailure: mapFailure,
       );

  /// The subcommands, which are also the server's tools, in listing order.
  final List<WaveCommand> commands;

  /// The program the documents name.
  final McpProgram program;

  /// The exit code of each outcome.
  final McpExitCodes exitCodes;

  /// Where files are opened.
  final WaveCommandContext commandContext;

  final McpTelemetry? Function() _telemetry;

  WaveCommand? _command(String name) {
    for (final c in commands) {
      if (c.name == name) return c;
    }
    return null;
  }

  ArgParser _parserFor(WaveCommand command) {
    final parser = ArgParser()
      ..addFlag('json', negatable: false, help: 'Write the JSON document.')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'This text.');
    command.addFlags(parser);
    return parser;
  }

  /// The document [command] writes for [args] (everything after the command
  /// name). The `--json` door and every tool call come through here.
  Future<McpDocument> document(String command, List<String> args) async {
    final c = _command(command);
    if (c == null) {
      return McpDocument.usage(
        tool: program,
        command: null,
        message: 'unknown command `$command`',
      );
    }
    try {
      final parsed = _parserFor(c).parse(args);
      return await c.run(commandContext, parsed);
    } on FormatException catch (e) {
      return McpDocument.usage(
        tool: program,
        command: c.name,
        message: e.message,
      );
    } on WaveUsageException catch (e) {
      return McpDocument.usage(
        tool: program,
        command: c.name,
        message: e.message,
      );
    }
  }

  /// Runs [argv] as the binary would: writes to [out] and [err], serves
  /// `mcp` on [input] and [output], and returns the exit code.
  Future<int> run(
    List<String> argv, {
    required StringSink out,
    required StringSink err,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
  }) async {
    if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
      (argv.isEmpty ? err : out).write(usage());
      return argv.isEmpty ? exitCodes.usageError : 0;
    }
    if (argv.first == '--version') {
      out.writeln('${program.name} ${program.version}');
      return 0;
    }
    final name = argv.first;
    final rest = argv.sublist(1);
    if (name == 'mcp') {
      return await _serve(
        rest,
        out: out,
        err: err,
        input: input,
        output: output,
      );
    }
    final command = _command(name);
    if (command == null) {
      err
        ..writeln('${program.name}: unknown command `$name`')
        ..write(usage());
      return exitCodes.usageError;
    }
    if (rest.contains('--help') || rest.contains('-h')) {
      out
        ..writeln(command.summary)
        ..writeln()
        ..writeln('Usage: ${command.invocation}')
        ..writeln(_parserFor(command).usage);
      return 0;
    }
    final McpDocument doc;
    try {
      doc = await document(name, rest);
    } finally {
      await commandContext.cache.closeAll();
    }
    if (rest.contains('--json')) {
      out.write(doc.render());
    } else {
      final body = doc.body;
      if (body != null) {
        command.describe(body).forEach(out.writeln);
      }
      for (final d in doc.diagnostics) {
        err.writeln('${d.severity.name}: ${d.message}');
        if (d.fix != null) err.writeln('  fix: ${d.fix}');
      }
      if (doc.outcome == McpOutcome.usageError) {
        err.writeln('Usage: ${command.invocation}');
      }
    }
    return exitCodes.exitCodeFor(doc.outcome);
  }

  /// The top-level help.
  String usage() {
    final b = StringBuffer()
      ..writeln(
        '${program.name} ${program.version}: read waveforms from the '
        'command line, or serve them to an agent over MCP.',
      )
      ..writeln()
      ..writeln('Commands:');
    for (final c in commands) {
      b.writeln('  ${c.name.padRight(12)} ${c.summary}');
    }
    b
      ..writeln(
        '  ${'mcp'.padRight(12)} Serve these commands as MCP tools on stdio.',
      )
      ..writeln()
      ..writeln(
        'Add --json for the JSON document; `${program.name} <command> '
        "--help` for a command's flags.",
      );
    return b.toString();
  }

  /// The MCP server over these commands, its paths held inside [root].
  McpServer server({required String root, McpTelemetry? telemetry}) =>
      McpServer(
        program: program,
        instructions: kWaveCruxMcpInstructions,
        tools: <McpTool>[for (final c in commands) c.tool],
        confinement: Confinement(root),
        telemetry: telemetry,
        runner: (call) async => McpCommandOutput.document(
          await document(call.tool.command, <String>[
            ...call.arguments.argv,
            '--json',
          ]),
        ),
      );

  Future<int> _serve(
    List<String> args, {
    required StringSink out,
    required StringSink err,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
  }) async {
    final parser = ArgParser()
      ..addOption(
        'root',
        help: 'Every path a tool receives must be inside it.',
        valueHelp: 'dir',
        defaultsTo: Directory.current.path,
      )
      ..addOption('license-file', help: _licenseHelp, valueHelp: 'path')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'This text.');
    final ArgResults parsed;
    try {
      parsed = parser.parse(args);
    } on FormatException catch (e) {
      err
        ..writeln('${program.name} mcp: ${e.message}')
        ..writeln(parser.usage);
      return exitCodes.usageError;
    }
    if (parsed.flag('help')) {
      out
        ..writeln(
          'Serve ${commands.map((c) => c.name).join(', ')} as MCP tools: '
          'newline-delimited JSON-RPC on stdin and stdout.',
        )
        ..writeln()
        ..writeln(
          'Usage: ${program.name} mcp [--root <dir>] '
          '[--license-file <path>]',
        )
        ..writeln(parser.usage);
      return 0;
    }
    if (parsed.rest.isNotEmpty) {
      err.writeln('${program.name} mcp: unexpected `${parsed.rest.first}`');
      return exitCodes.usageError;
    }
    final root = parsed.option('root')!;
    final server = this.server(root: root, telemetry: _telemetry());
    final problem = server.confinement.rootProblem();
    if (problem != null) {
      err.writeln('${program.name} mcp: $problem');
      return exitCodes.usageError;
    }
    try {
      await server.serve(input ?? stdin, output ?? stdout);
    } finally {
      await commandContext.cache.closeAll();
    }
    return 0;
  }
}

/// The `mcp.tool_call` counter of the open-core binary: sent only under the
/// consent the WaveCrux desktop app recorded on this machine, and never when
/// the `CI` environment variable is set.
McpTelemetry waveCruxMcpTelemetry() =>
    McpTelemetry.desktop(waveCruxHeadlessTelemetry());

/// The headless sender behind [waveCruxMcpTelemetry].
HeadlessTelemetry waveCruxHeadlessTelemetry() => HeadlessTelemetry(
  product: CruxTelemetryProduct.wavecrux,
  pro: false,
  appVersion: kWaveCruxCliVersion,
);
