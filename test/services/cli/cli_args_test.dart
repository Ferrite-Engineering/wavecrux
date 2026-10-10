// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/cli/cli_args.dart';

void main() {
  group('parseCliArgs', () {
    test('empty args produces an empty CliArgs', () {
      final cli = parseCliArgs(const []);
      expect(cli.initialFiles, isEmpty);
      expect(cli.initialSession, isNull);
      expect(cli.initialWorkspace, isNull);
      expect(cli.stdinMode, isFalse);
      expect(cli.pipePath, isNull);
    });

    test('bare positional .fst routes to initialFiles', () {
      final cli = parseCliArgs(const ['dump.fst']);
      expect(cli.initialFiles, equals(['dump.fst']));
      expect(cli.initialWorkspace, isNull);
      expect(cli.initialSession, isNull);
    });

    test('multiple bare positionals open as multiple tabs', () {
      final cli = parseCliArgs(const ['a.fst', 'b.vcd', 'c.ghw']);
      expect(cli.initialFiles, equals(['a.fst', 'b.vcd', 'c.ghw']));
    });

    test('bare positional .wavecrux routes to initialSession', () {
      final cli = parseCliArgs(const ['debug.wavecrux']);
      expect(cli.initialSession, equals('debug.wavecrux'));
      expect(cli.initialFiles, isEmpty);
      expect(cli.initialWorkspace, isNull);
    });

    test('bare positional .wavecruxpack routes to initialSession', () {
      // A share bundle restores a whole view, so it takes the session route
      // rather than the waveform one. Routed to `initialFiles` it would be
      // handed to the waveform parser as a zip and fail with a format error.
      final cli = parseCliArgs(const ['review.wavecruxpack']);
      expect(cli.initialSession, equals('review.wavecruxpack'));
      expect(cli.initialFiles, isEmpty);
      expect(cli.initialWorkspace, isNull);
    });

    test('a named design manifest opens as a tab, resolved when it opens', () {
      // The manifest is swapped for its waveform by the viewer's open flow,
      // which every positional file passes through.
      final cli = parseCliArgs(const ['uart_tx.crux-project']);
      expect(cli.initialFiles, equals(['uart_tx.crux-project']));
      expect(cli.initialSession, isNull);
      expect(cli.initialWorkspace, isNull);
    });

    test('bare positional .wavecrux-workspace routes to initialWorkspace', () {
      final cli = parseCliArgs(const ['team.wavecrux-workspace']);
      expect(cli.initialWorkspace, equals('team.wavecrux-workspace'));
      expect(cli.initialFiles, isEmpty);
      expect(cli.initialSession, isNull);
    });

    test('--workspace <path> sets initialWorkspace', () {
      final cli = parseCliArgs(const [
        '--workspace',
        'team.wavecrux-workspace',
      ]);
      expect(cli.initialWorkspace, equals('team.wavecrux-workspace'));
    });

    test('--session <path> sets initialSession', () {
      final cli = parseCliArgs(const ['--session', 'debug.wavecrux']);
      expect(cli.initialSession, equals('debug.wavecrux'));
    });

    test('--session and bare files can coexist', () {
      final cli = parseCliArgs(
        const ['dump.fst', '--session', 'debug.wavecrux'],
      );
      expect(cli.initialFiles, equals(['dump.fst']));
      expect(cli.initialSession, equals('debug.wavecrux'));
    });

    test('--workspace overrides bare positional ordering', () {
      // First the workspace flag, then a stray file — both honored.
      final cli = parseCliArgs(
        const ['--workspace', 'a.wavecrux-workspace', 'b.fst'],
      );
      expect(cli.initialWorkspace, equals('a.wavecrux-workspace'));
      expect(cli.initialFiles, equals(['b.fst']));
    });

    test('--interactive / --stdin set stdinMode', () {
      expect(parseCliArgs(const ['--interactive']).stdinMode, isTrue);
      expect(parseCliArgs(const ['--stdin']).stdinMode, isTrue);
    });

    test('--pipe <path> sets pipePath', () {
      final cli = parseCliArgs(const ['--pipe', '/tmp/wave.pipe']);
      expect(cli.pipePath, equals('/tmp/wave.pipe'));
    });

    test('unknown flags are silently ignored', () {
      final cli = parseCliArgs(const ['--foo', '--bar=baz', 'dump.fst']);
      expect(cli.initialFiles, equals(['dump.fst']));
    });

    test('trailing flag without value is ignored', () {
      // No path after --workspace — guarded by `i + 1 < args.length`.
      final cli = parseCliArgs(const ['--workspace']);
      expect(cli.initialWorkspace, isNull);
    });

    test('case-insensitive extension routing', () {
      final cli = parseCliArgs(const ['TEAM.WAVECRUX-WORKSPACE']);
      expect(cli.initialWorkspace, equals('TEAM.WAVECRUX-WORKSPACE'));
    });

    test('defaults: reset and noRestore are false', () {
      final cli = parseCliArgs(const []);
      expect(cli.reset, isFalse);
      expect(cli.noRestore, isFalse);
    });

    test('--reset sets reset', () {
      final cli = parseCliArgs(const ['--reset']);
      expect(cli.reset, isTrue);
      expect(cli.noRestore, isFalse);
    });

    test('--no-restore sets noRestore', () {
      final cli = parseCliArgs(const ['--no-restore']);
      expect(cli.noRestore, isTrue);
      expect(cli.reset, isFalse);
    });

    test('--reset and --no-restore compose with a positional file', () {
      final cli = parseCliArgs(const ['--reset', '--no-restore', 'dump.fst']);
      expect(cli.reset, isTrue);
      expect(cli.noRestore, isTrue);
      expect(cli.initialFiles, equals(['dump.fst']));
    });
  });

  group('isWorkspaceFilePath', () {
    test('matches .wavecrux-workspace extension case-insensitively', () {
      expect(isWorkspaceFilePath('a.wavecrux-workspace'), isTrue);
      expect(isWorkspaceFilePath('A.WAVECRUX-WORKSPACE'), isTrue);
      expect(isWorkspaceFilePath('/path/to/team.wavecrux-workspace'), isTrue);
    });

    test('rejects other extensions', () {
      expect(isWorkspaceFilePath('a.wavecrux'), isFalse);
      expect(isWorkspaceFilePath('a.fst'), isFalse);
      expect(isWorkspaceFilePath('a.wavecrux-workspace.bak'), isFalse);
    });
  });

  group('cliHelpText', () {
    test('mentions every supported flag', () {
      final help = cliHelpText();
      expect(help, contains('--session'));
      expect(help, contains('--workspace'));
      expect(help, contains('--interactive'));
      expect(help, contains('--stdin'));
      expect(help, contains('--pipe'));
      expect(help, contains('--no-restore'));
      expect(help, contains('--reset'));
      expect(help, contains('--reset-eula'));
      expect(help, contains('--reset-telemetry-consent'));
      expect(help, contains('--help'));
      expect(help, contains('.wavecrux-workspace'));
      expect(help, contains('.wavecrux'));
      expect(help, contains('.crux-project'));
    });

    test('--wcp-port takes the next argument as the port', () {
      expect(parseCliArgs(const ['--wcp-port', '9000']).wcpPort, 9000);
      expect(parseCliArgs(const ['--wcp-port=0', 'dump.fst']).wcpPort, 0);
      expect(
        parseCliArgs(const ['--wcp-port', '0', 'dump.fst']).initialFiles,
        ['dump.fst'],
      );
    });

    test('a --wcp-port value that is not a port is ignored', () {
      expect(parseCliArgs(const ['--wcp-port', 'abc']).wcpPort, isNull);
      expect(parseCliArgs(const ['--wcp-port=70000']).wcpPort, isNull);
      expect(parseCliArgs(const ['--wcp-port=-1']).wcpPort, isNull);
      expect(parseCliArgs(const ['--wcp-port']).wcpPort, isNull);
      expect(parseCliArgs(const []).wcpPort, isNull);
    });
  });

  group('resolveWcpPortOverride', () {
    test('the flag wins over the environment', () {
      final cli = parseCliArgs(const ['--wcp-port', '9000']);
      expect(resolveWcpPortOverride(cli, {kWcpPortEnvVar: '9001'}), 9000);
    });

    test('the environment applies when the flag is absent', () {
      final cli = parseCliArgs(const []);
      expect(resolveWcpPortOverride(cli, {kWcpPortEnvVar: ' 0 '}), 0);
      expect(resolveWcpPortOverride(cli, {kWcpPortEnvVar: 'x'}), isNull);
      expect(resolveWcpPortOverride(cli, const {}), isNull);
    });

    test('the help text documents the flag', () {
      expect(cliHelpText(), contains('--wcp-port <n>'));
      expect(cliHelpText(), contains(kWcpPortEnvVar));
    });
  });
}
