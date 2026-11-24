// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crux_mcp/crux_mcp.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/headless/cli_version.dart';
import 'package:wavecrux/headless/wave_file_cache.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';
import 'package:wavecrux/services/wave_session/wave_queries.dart';

/// The program every document names, and the MCP server's `serverInfo`.
const McpProgram kWaveCruxProgram = McpProgram(
  name: 'wavecrux',
  version: kWaveCruxCliVersion,
);

/// The engine a document names once a file was handed to the reader.
const McpEngine kWellenEngine = McpEngine(
  name: 'wellen',
  version: kWellenEngineVersion,
);

/// `search --limit`: the default.
const int kSearchLimitDefault = 50;

/// `search --limit`: the most.
const int kSearchLimitMax = 500;

/// `values --limit` (clock edges): the default.
const int kValuesLimitDefault = 200;

/// `values --limit` (clock edges): the most.
const int kValuesLimitMax = 5000;

/// `transitions --limit` (changes per signal): the default.
const int kTransitionsLimitDefault = 200;

/// `transitions --limit` (changes per signal): the most.
const int kTransitionsLimitMax = 10000;

/// The most `--signal`s one call names.
const int kMaxSignalsPerCall = 32;

/// The most scopes `info` lists.
const int kInfoScopeLimit = 50;

/// What a failure of the waveform reader means for a command: its outcome
/// and the error diagnostic that says why.
@immutable
class ReaderFailure {
  /// A failure ending in [outcome], said by [diagnostic].
  const ReaderFailure(this.outcome, this.diagnostic);

  /// How the command ends.
  final McpOutcome outcome;

  /// Why.
  final McpDiagnostic diagnostic;
}

/// Maps what the reader threw while reading [file] to how the command ends.
///
/// A file wellen parsed and refused, or one that could not be read, is an
/// `input_error`; a reader that hung, could not start (its native library
/// missing) or failed in any other way is an `engine_error`. Never an
/// answer: a reader that failed has produced none. The mutation proof in
/// `test/headless/reader_failure_test.dart` holds this to that.
ReaderFailure classifyReaderFailure(Object error, {required String file}) {
  if (error is WaveformOpenException) {
    return ReaderFailure(
      McpOutcome.inputError,
      McpDiagnostic.error(
        'input.unreadable',
        'wellen could not read `$file`: ${error.reason}',
      ),
    );
  }
  if (error is FileSystemException) {
    return ReaderFailure(
      McpOutcome.inputError,
      McpDiagnostic.error(
        'input.unreadable',
        '`$file` could not be read: ${error.message}',
      ),
    );
  }
  if (error is TimeoutException) {
    return ReaderFailure(
      McpOutcome.engineError,
      McpDiagnostic.error(
        'engine.timeout',
        'wellen did not finish reading `$file` in time',
      ),
    );
  }
  return ReaderFailure(
    McpOutcome.engineError,
    McpDiagnostic.error('engine.failed', 'the waveform reader failed: $error'),
  );
}

/// Maps a reader failure to how a command ends; [classifyReaderFailure]
/// unless a test proves that a broken mapping is caught.
typedef ReaderFailureMap =
    ReaderFailure Function(Object error, {required String file});

/// A refused argument: the command writes a `usage_error` and runs nothing
/// more.
class WaveUsageException implements Exception {
  /// A refusal saying [message].
  const WaveUsageException(this.message);

  /// One sentence naming the argument and what is wrong.
  final String message;

  @override
  String toString() => message;
}

/// What every command shares: where files are opened, and how a reader
/// failure is mapped.
class WaveCommandContext {
  /// A context opening files through [cache].
  WaveCommandContext({
    required this.cache,
    this.program = kWaveCruxProgram,
    this.mapFailure = classifyReaderFailure,
  });

  /// The open files.
  final WaveFileCache cache;

  /// The program the documents name.
  final McpProgram program;

  /// How a reader failure ends a command.
  final ReaderFailureMap mapFailure;

  /// The `--license-file` the `mcp` server was started with, for a command
  /// that reads a licence; null on the command line, where each command
  /// takes its own flag. The four commands of this library read none.
  String? licenseFile;
}

/// One subcommand: its MCP tool, its flags, and the document it writes.
abstract class WaveCommand {
  /// The subcommand's name, which is its tool's.
  String get name;

  /// One line for `--help`.
  String get summary;

  /// How it is called, for `--help`.
  String get invocation;

  /// Its tool: the definition `tools/list` sends, and how a call's fields
  /// become this command's arguments.
  McpTool get tool;

  /// Adds the command's own flags (not `--json` or `--help`) to [parser].
  void addFlags(ArgParser parser);

  /// Runs the command and returns its document. Throws a
  /// [WaveUsageException] for a refused argument.
  Future<McpDocument> run(WaveCommandContext context, ArgResults args);

  /// The document's answer as lines for a person, without `--json`.
  List<String> describe(Map<String, Object?> body);
}

/// The four open-core commands, in listing order.
List<WaveCommand> openCoreWaveCommands() => <WaveCommand>[
  InfoCommand(),
  SearchCommand(),
  ValuesCommand(),
  TransitionsCommand(),
];

// ── shared helpers ──────────────────────────────────────────────────────────

final BigInt _maxTick = BigInt.parse('9223372036854775807');

/// [text] (a whole tick count, or a time with a unit in a link's `t`
/// grammar) as ticks of [timescale]. Throws a [WaveUsageException] when it
/// is neither, has a unit on a file with no known timescale, or does not
/// fall on a whole tick.
int parseTicks(String text, Timescale? timescale, {required String flag}) {
  final time = parseWaveCruxLinkTime(text);
  if (time == null) {
    throw WaveUsageException(
      '`$flag $text` is not a tick count or a time such as 1500ns',
    );
  }
  BigInt ticks;
  if (time.isTicks) {
    ticks = time.mantissa;
  } else {
    final unitExponent = timescale?.unit.exponent;
    final factor = timescale?.factor ?? 0;
    if (unitExponent == null || factor <= 0) {
      throw WaveUsageException(
        '`$flag $text` has a unit, and this file declares no timescale; '
        'give a tick count',
      );
    }
    final shift = time.exponent - unitExponent;
    final numerator =
        time.mantissa * BigInt.from(10).pow(shift > 0 ? shift : 0);
    final denominator =
        BigInt.from(factor) * BigInt.from(10).pow(shift < 0 ? -shift : 0);
    if (numerator % denominator != BigInt.zero) {
      throw WaveUsageException(
        "`$flag $text` is not a whole number of ticks of this file's "
        '${timescale!.displayString} timescale',
      );
    }
    ticks = numerator ~/ denominator;
  }
  if (ticks > _maxTick) {
    throw WaveUsageException('`$flag $text` is past the last possible tick');
  }
  return ticks.toInt();
}

int _limit(ArgResults args, {required int fallback, required int max}) {
  final raw = args.option('limit');
  if (raw == null) return fallback;
  final value = int.tryParse(raw);
  if (value == null || value < 1 || value > max) {
    throw WaveUsageException('`--limit $raw` is a whole number from 1 to $max');
  }
  return value;
}

List<String> _signals(ArgResults args) {
  final signals = args.multiOption('signal');
  if (signals.isEmpty) {
    throw const WaveUsageException('give at least one --signal');
  }
  if (signals.length > kMaxSignalsPerCall) {
    throw const WaveUsageException(
      'at most $kMaxSignalsPerCall --signal values in one call',
    );
  }
  return signals;
}

String _onePositional(ArgResults args, String what) {
  if (args.rest.length != 1) {
    throw WaveUsageException('give one $what');
  }
  return p.absolute(args.rest.single);
}

void _addSignalFlags(ArgParser parser) => parser.addMultiOption(
  'signal',
  help: 'A signal by full path (or signal reference). Repeat for more.',
  valueHelp: 'path',
  splitCommas: false,
);

void _addLimit(ArgParser parser, String help) =>
    parser.addOption('limit', help: help, valueHelp: 'n');

/// The file at [file] opened, or the document that says why it is not.
///
/// Public so that a command defined outside this library opens, refuses and
/// maps a reader failure exactly as these four do.
Future<(WaveFile?, McpDocument?)> openWaveForCommand(
  WaveCommandContext context,
  String command,
  String file,
) async {
  McpDocument fail(
    McpOutcome outcome,
    McpDiagnostic diagnostic, {
    bool engineRan = false,
  }) => McpDocument(
    tool: context.program,
    command: command,
    outcome: outcome,
    engines: engineRan ? const <McpEngine>[kWellenEngine] : const <McpEngine>[],
    diagnostics: <McpDiagnostic>[diagnostic],
  );

  if (FileSystemEntity.typeSync(file) != FileSystemEntityType.file) {
    return (
      null,
      fail(
        McpOutcome.inputError,
        McpDiagnostic.error('input.not_found', '`$file` is not a file'),
      ),
    );
  }
  try {
    waveCruxLink(file);
  } on McpLocationException catch (e) {
    return (
      null,
      fail(
        McpOutcome.inputError,
        McpDiagnostic.error(
          'input.path_unlinkable',
          '`$file` cannot be cited by a link: ${e.message}',
        ),
      ),
    );
  }
  try {
    return (await context.cache.open(file), null);
  } on Object catch (error) {
    final failure = context.mapFailure(error, file: file);
    return (null, fail(failure.outcome, failure.diagnostic, engineRan: true));
  }
}

/// The location of [signal] at [tick] in [file], with its link; a place
/// location and a warning when the name cannot travel in a link.
(McpLocation, McpDiagnostic?) waveSignalLocation(
  String file,
  String signal,
  int tick,
) {
  try {
    return (
      McpSignalLocation(file: file, signal: signal, time: McpTime.ticks(tick)),
      null,
    );
  } on McpLocationException catch (e) {
    final place = McpPlaceLocation(file: file, time: McpTime.ticks(tick));
    return (
      place,
      McpDiagnostic.warning(
        'link.unavailable',
        'no link can name `$signal`: ${e.message}; its location gives the '
            'file and time only',
        location: place,
      ),
    );
  }
}

/// Resolves [names] in [file]; each one not found becomes a warning.
(List<Variable>, List<McpDiagnostic>) _resolve(
  WaveFile wave,
  String file,
  List<String> names,
  int tick,
) {
  final found = <Variable>[];
  final missing = <McpDiagnostic>[];
  for (final name in names) {
    final variable = wave.index.resolve(name);
    if (variable != null) {
      found.add(variable);
    } else {
      missing.add(
        McpDiagnostic.warning(
          'signal.not_found',
          'no signal `$name` in `$file`',
          fix: 'find its full path with `wavecrux search`',
          location: McpPlaceLocation(file: file, time: McpTime.ticks(tick)),
        ),
      );
    }
  }
  return (found, missing);
}

/// The warnings as errors: the outcome when no signal named was found.
List<McpDiagnostic> _asErrors(List<McpDiagnostic> warnings) => <McpDiagnostic>[
  for (final w in warnings)
    McpDiagnostic.error(w.code, w.message, fix: w.fix, location: w.location),
];

/// Runs [body], and maps anything the reader throws while it runs to the
/// document [context.mapFailure] gives; a [WaveUsageException] passes
/// through.
Future<McpDocument> guardWaveCommand(
  WaveCommandContext context,
  String command,
  String file,
  Future<McpDocument> Function() body,
) async {
  try {
    return await body();
  } on WaveUsageException {
    rethrow;
  } on Object catch (error) {
    final failure = context.mapFailure(error, file: file);
    return McpDocument(
      tool: context.program,
      command: command,
      outcome: failure.outcome,
      engines: const <McpEngine>[kWellenEngine],
      diagnostics: <McpDiagnostic>[failure.diagnostic],
    );
  }
}

// ── info ────────────────────────────────────────────────────────────────────

/// `wavecrux info <file>`: the timescale, time range, top scopes and signal
/// count of a waveform.
class InfoCommand extends WaveCommand {
  @override
  String get name => 'info';

  @override
  String get summary =>
      'Timescale, time range, top scopes and signal count of a waveform.';

  @override
  String get invocation => 'wavecrux info <file> [--json]';

  @override
  late final McpTool tool = McpTool(
    name: 'info',
    description:
        'Open a waveform file (VCD, FST, GHW and others) and return its '
        'timescale, time range, top scopes and signal count. Every WaveCrux '
        'tool gives times in ticks of this timescale.',
    fields: const <McpField>[McpField('file', kind: McpFieldKind.path)],
    required: const <String>['file'],
  );

  @override
  void addFlags(ArgParser parser) {}

  @override
  Future<McpDocument> run(WaveCommandContext context, ArgResults args) async {
    final file = _onePositional(args, 'waveform file');
    final (wave, failed) = await openWaveForCommand(context, name, file);
    if (failed != null) return failed;
    return await guardWaveCommand(context, name, file, () async {
      final source = wave!.source;
      final roots = source.rootScopes;
      final listed = <Scope>[
        for (final root in roots) ...<Scope>[root, ...root.childScopes],
      ];
      var scopeCount = 0;
      void count(Scope s) {
        scopeCount++;
        s.childScopes.forEach(count);
      }

      roots.forEach(count);
      final timescale = source.timescale;
      final exponent = timescale?.unit.exponent;
      return McpDocument(
        tool: context.program,
        command: name,
        outcome: McpOutcome.completed,
        engines: const <McpEngine>[kWellenEngine],
        body: <String, Object?>{
          'file': file,
          'format': wave.format,
          'timescale': timescale == null || exponent == null
              ? null
              : <String, Object?>{
                  'display': timescale.displayString,
                  'seconds_per_tick': double.parse(
                    '${timescale.factor}e$exponent',
                  ),
                },
          'start': source.startTime,
          'end': source.endTime,
          'signal_count': roots.fold<int>(
            0,
            (sum, s) => sum + s.totalVariableCount,
          ),
          'scope_count': scopeCount,
          'scopes': <Map<String, Object?>>[
            for (final s in listed.take(kInfoScopeLimit))
              <String, Object?>{
                'path': s.path,
                'signal_count': s.totalVariableCount,
              },
          ],
          'truncated': listed.length > kInfoScopeLimit,
          'location': McpPlaceLocation(
            file: file,
            time: McpTime.ticks(source.startTime),
          ),
        },
      );
    });
  }

  @override
  List<String> describe(Map<String, Object?> body) {
    final timescale = body['timescale'] as Map<String, Object?>?;
    return <String>[
      '${body['file']} (${body['format']})',
      'timescale: ${timescale?['display'] ?? 'none declared'}',
      'time: ${body['start']} to ${body['end']} ticks',
      '${body['signal_count']} signals in ${body['scope_count']} scopes',
      for (final s
          in (body['scopes']! as List<Object?>).cast<Map<String, Object?>>())
        '  ${s['path']} (${s['signal_count']} signals)',
      if (body['truncated'] == true) '  ...',
    ];
  }
}

// ── search ──────────────────────────────────────────────────────────────────

/// `wavecrux search <file> <query>`: signals by name.
class SearchCommand extends WaveCommand {
  @override
  String get name => 'search';

  @override
  String get summary => 'Find signals by name; full paths, widths and types.';

  @override
  String get invocation =>
      'wavecrux search <file> <query> [--glob] [--limit <n>] [--json]';

  @override
  late final McpTool tool = McpTool(
    name: 'search',
    description:
        'Find signals in a waveform by name. Returns full hierarchical '
        'paths, widths and types.',
    fields: const <McpField>[
      McpField('file', kind: McpFieldKind.path),
      McpField('query', kind: McpFieldKind.text),
      McpField(
        'glob',
        kind: McpFieldKind.boolean,
        flag: '--glob',
        description: 'Match * and ? as a glob, not a substring.',
      ),
      McpField(
        'limit',
        kind: McpFieldKind.integer,
        flag: '--limit',
        description: 'Default 50, at most 500.',
        minimum: 1,
      ),
    ],
    required: const <String>['file', 'query'],
  );

  @override
  void addFlags(ArgParser parser) {
    parser.addFlag(
      'glob',
      negatable: false,
      help: 'Match * and ? as a glob, not a substring.',
    );
    _addLimit(parser, 'Signals returned: default 50, at most 500.');
  }

  @override
  Future<McpDocument> run(WaveCommandContext context, ArgResults args) async {
    if (args.rest.length != 2) {
      throw const WaveUsageException('give a waveform file and a query');
    }
    final file = p.absolute(args.rest[0]);
    final query = args.rest[1];
    final limit = _limit(
      args,
      fallback: kSearchLimitDefault,
      max: kSearchLimitMax,
    );
    final (wave, failed) = await openWaveForCommand(context, name, file);
    if (failed != null) return failed;
    return await guardWaveCommand(context, name, file, () async {
      final answer = SignalSearchAnswer.search(
        rootScopes: wave!.source.rootScopes,
        query: query,
        mode: args.flag('glob') ? SearchMode.glob : SearchMode.substring,
        limit: limit,
      );
      return McpDocument(
        tool: context.program,
        command: name,
        outcome: McpOutcome.completed,
        engines: const <McpEngine>[kWellenEngine],
        body: answer.toJson(),
      );
    });
  }

  @override
  List<String> describe(Map<String, Object?> body) => <String>[
    for (final s
        in (body['signals']! as List<Object?>).cast<Map<String, Object?>>())
      '${s['path']}  [${s['bitWidth'] ?? '?'}] ${s['varType']} ${s['direction']}',
    '${body['returned']} of ${body['matchCount']} matches',
  ];
}

// ── values ──────────────────────────────────────────────────────────────────

/// `wavecrux values`: values of signals at one time (`--at`), or at each
/// rising edge of a clock (`--clock` with `--from` and `--to`).
class ValuesCommand extends WaveCommand {
  @override
  String get name => 'values';

  @override
  String get summary =>
      'Values of signals at one time, or at each rising edge of a clock.';

  @override
  String get invocation =>
      'wavecrux values <file> --signal <path>... (--at <t> | --clock <path> '
      '--from <t> --to <t>) [--limit <n>] [--json]';

  @override
  late final McpTool tool = McpTool(
    name: 'values',
    description:
        'Values of signals at one time, or at each rising edge of a clock '
        'between two times. Each signal carries a link that opens it in '
        'WaveCrux.',
    fields: const <McpField>[
      McpField('file', kind: McpFieldKind.path),
      McpField(
        'signals',
        kind: McpFieldKind.text,
        flag: '--signal',
        many: true,
        description: 'Full paths, at most 32.',
      ),
      McpField(
        'at',
        kind: McpFieldKind.time,
        flag: '--at',
        description: 'A tick, or a time such as 1500ns.',
      ),
      McpField('clock', kind: McpFieldKind.text, flag: '--clock'),
      McpField('from', kind: McpFieldKind.time, flag: '--from'),
      McpField('to', kind: McpFieldKind.time, flag: '--to'),
      McpField(
        'limit',
        kind: McpFieldKind.integer,
        flag: '--limit',
        description: 'Clock edges, default 200, at most 5000.',
        minimum: 1,
      ),
    ],
    required: const <String>['file', 'signals'],
  );

  @override
  void addFlags(ArgParser parser) {
    _addSignalFlags(parser);
    parser
      ..addOption(
        'at',
        help: 'A tick, or a time such as 1500ns.',
        valueHelp: 't',
      )
      ..addOption(
        'clock',
        help: 'Sample at its rising edges.',
        valueHelp: 'path',
      )
      ..addOption(
        'from',
        help: 'First tick of the clock window.',
        valueHelp: 't',
      )
      ..addOption(
        'to',
        help: 'End of the clock window, not included.',
        valueHelp: 't',
      );
    _addLimit(parser, 'Clock edges: default 200, at most 5000.');
  }

  @override
  Future<McpDocument> run(WaveCommandContext context, ArgResults args) async {
    final file = _onePositional(args, 'waveform file');
    final names = _signals(args);
    final at = args.option('at');
    final clockName = args.option('clock');
    final fromText = args.option('from');
    final toText = args.option('to');
    final atMode =
        at != null && clockName == null && fromText == null && toText == null;
    final clockMode =
        at == null && clockName != null && fromText != null && toText != null;
    if (!atMode && !clockMode) {
      throw const WaveUsageException(
        'give --at, or --clock with --from and --to',
      );
    }
    final limit = _limit(
      args,
      fallback: kValuesLimitDefault,
      max: kValuesLimitMax,
    );
    final (wave, failed) = await openWaveForCommand(context, name, file);
    if (failed != null) return failed;
    final source = wave!.source;
    final timescale = source.timescale;
    final atTick = atMode ? parseTicks(at, timescale, flag: '--at') : null;
    final from = clockMode
        ? parseTicks(fromText, timescale, flag: '--from')
        : null;
    final to = clockMode ? parseTicks(toText, timescale, flag: '--to') : null;
    if (from != null && to != null && from > to) {
      throw WaveUsageException('`--from $fromText` is after `--to $toText`');
    }
    final queryTick = atTick ?? from!;

    return await guardWaveCommand(context, name, file, () async {
      final (variables, warnings) = _resolve(wave, file, names, queryTick);
      if (variables.isEmpty) {
        return McpDocument(
          tool: context.program,
          command: name,
          outcome: McpOutcome.inputError,
          engines: const <McpEngine>[kWellenEngine],
          diagnostics: _asErrors(warnings),
        );
      }
      final diagnostics = <McpDiagnostic>[...warnings];
      List<int> times;
      var truncated = false;
      int? nextFrom;
      String? clockPath;
      if (clockMode) {
        final clock = wave.index.resolve(clockName);
        if (clock == null) {
          return McpDocument(
            tool: context.program,
            command: name,
            outcome: McpOutcome.inputError,
            engines: const <McpEngine>[kWellenEngine],
            diagnostics: <McpDiagnostic>[
              McpDiagnostic.error(
                'signal.not_found',
                'no clock `$clockName` in `$file`',
                fix: 'find its full path with `wavecrux search`',
                location: McpPlaceLocation(
                  file: file,
                  time: McpTime.ticks(queryTick),
                ),
              ),
            ],
          );
        }
        if (clock.bitWidth != null && clock.bitWidth != 1) {
          return McpDocument(
            tool: context.program,
            command: name,
            outcome: McpOutcome.inputError,
            engines: const <McpEngine>[kWellenEngine],
            diagnostics: <McpDiagnostic>[
              McpDiagnostic.error(
                'values.clock_width',
                'the clock `${clock.fullPath}` is ${clock.bitWidth} bits '
                    'wide; a clock is one bit',
              ),
            ],
          );
        }
        clockPath = clock.fullPath;
        await source.loadSignal(clock.signalRef);
        final edges = risingEdges(source, clock, from: from!, to: to!);
        truncated = edges.length > limit;
        times = edges.take(limit).toList();
        if (truncated) nextFrom = times.last + 1;
      } else {
        times = <int>[atTick!];
      }
      final locationTick = times.isEmpty ? queryTick : times.first;
      final signals = <Map<String, Object?>>[];
      for (final v in variables) {
        await source.loadSignal(v.signalRef);
        final (location, linkWarning) = waveSignalLocation(
          file,
          v.fullPath,
          locationTick,
        );
        if (linkWarning != null) diagnostics.add(linkWarning);
        signals.add(<String, Object?>{
          'path': v.fullPath,
          'bitWidth': v.bitWidth,
          'values': <String?>[
            for (final t in times) source.valueAt(v.signalRef, t),
          ],
          'location': location,
        });
      }
      return McpDocument(
        tool: context.program,
        command: name,
        outcome: McpOutcome.completed,
        engines: const <McpEngine>[kWellenEngine],
        body: <String, Object?>{
          'times': times,
          'clock': clockPath,
          'truncated': truncated,
          'next_from': nextFrom,
          'signals': signals,
        },
        diagnostics: diagnostics,
      );
    });
  }

  @override
  List<String> describe(Map<String, Object?> body) {
    final times = (body['times']! as List<Object?>).cast<int>();
    return <String>[
      'times: ${times.join(' ')}',
      for (final s
          in (body['signals']! as List<Object?>).cast<Map<String, Object?>>())
        '${s['path']}: ${(s['values']! as List<Object?>).map((v) => v ?? '-').join(' ')}',
      if (body['truncated'] == true)
        'more clock edges from tick ${body['next_from']}',
    ];
  }
}

// ── transitions ─────────────────────────────────────────────────────────────

/// `wavecrux transitions <file> --signal <path>... --from <t> --to <t>`:
/// every value change in a window.
class TransitionsCommand extends WaveCommand {
  @override
  String get name => 'transitions';

  @override
  String get summary =>
      'Every value change of signals between two times, as recorded.';

  @override
  String get invocation =>
      'wavecrux transitions <file> --signal <path>... --from <t> --to <t> '
      '[--limit <n>] [--json]';

  @override
  late final McpTool tool = McpTool(
    name: 'transitions',
    description:
        'Every value change of signals between two times, exactly as '
        "recorded, with each signal's value at the start. Use instead of "
        'sampling. A truncated signal gives next_from to continue.',
    fields: const <McpField>[
      McpField('file', kind: McpFieldKind.path),
      McpField(
        'signals',
        kind: McpFieldKind.text,
        flag: '--signal',
        many: true,
        description: 'Full paths, at most 32.',
      ),
      McpField('from', kind: McpFieldKind.time, flag: '--from'),
      McpField('to', kind: McpFieldKind.time, flag: '--to'),
      McpField(
        'limit',
        kind: McpFieldKind.integer,
        flag: '--limit',
        description: 'Changes per signal, default 200, at most 10000.',
        minimum: 1,
      ),
    ],
    required: const <String>['file', 'signals', 'from', 'to'],
  );

  @override
  void addFlags(ArgParser parser) {
    _addSignalFlags(parser);
    parser
      ..addOption('from', help: 'First tick of the window.', valueHelp: 't')
      ..addOption(
        'to',
        help: 'End of the window, not included.',
        valueHelp: 't',
      );
    _addLimit(parser, 'Changes per signal: default 200, at most 10000.');
  }

  @override
  Future<McpDocument> run(WaveCommandContext context, ArgResults args) async {
    final file = _onePositional(args, 'waveform file');
    final names = _signals(args);
    final fromText = args.option('from');
    final toText = args.option('to');
    if (fromText == null || toText == null) {
      throw const WaveUsageException('give --from and --to');
    }
    final limit = _limit(
      args,
      fallback: kTransitionsLimitDefault,
      max: kTransitionsLimitMax,
    );
    final (wave, failed) = await openWaveForCommand(context, name, file);
    if (failed != null) return failed;
    final source = wave!.source;
    final from = parseTicks(fromText, source.timescale, flag: '--from');
    final to = parseTicks(toText, source.timescale, flag: '--to');
    if (from > to) {
      throw WaveUsageException('`--from $fromText` is after `--to $toText`');
    }

    return await guardWaveCommand(context, name, file, () async {
      final (variables, warnings) = _resolve(wave, file, names, from);
      if (variables.isEmpty) {
        return McpDocument(
          tool: context.program,
          command: name,
          outcome: McpOutcome.inputError,
          engines: const <McpEngine>[kWellenEngine],
          diagnostics: _asErrors(warnings),
        );
      }
      final diagnostics = <McpDiagnostic>[...warnings];
      final signals = <Map<String, Object?>>[];
      for (final v in variables) {
        final answer = await transitionsInWindow(
          source,
          v,
          start: from,
          end: to,
          limit: limit,
        );
        if (answer.splitsLastTick) {
          diagnostics.add(
            McpDiagnostic.warning(
              'transitions.same_tick_split',
              '`${v.fullPath}` changes more than once at tick '
                  '${answer.returned.last.time} and the limit fell among '
                  'them; next_from starts after that tick, so ask again '
                  'with a higher limit to see every change at it',
            ),
          );
        }
        final (location, linkWarning) = waveSignalLocation(
          file,
          v.fullPath,
          from,
        );
        if (linkWarning != null) diagnostics.add(linkWarning);
        signals.add(<String, Object?>{
          ...answer.toPagedJson(),
          'location': location,
        });
      }
      return McpDocument(
        tool: context.program,
        command: name,
        outcome: McpOutcome.completed,
        engines: const <McpEngine>[kWellenEngine],
        body: <String, Object?>{
          'window': <String, Object?>{'start': from, 'end': to},
          'signals': signals,
        },
        diagnostics: diagnostics,
      );
    });
  }

  @override
  List<String> describe(Map<String, Object?> body) => <String>[
    for (final s
        in (body['signals']! as List<Object?>)
            .cast<Map<String, Object?>>()) ...<String>[
      '${s['signal']} (at start: ${s['valueAtStart'] ?? '-'})',
      for (final t
          in (s['transitions']! as List<Object?>).cast<Map<String, Object?>>())
        '  ${t['time']}  ${t['value']}',
      if (s['truncated'] == true)
        '  ${s['returned']} of ${s['transitionCount']}; more from tick ${s['next_from']}',
    ],
  ];
}
