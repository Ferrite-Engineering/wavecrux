// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The headless `wavecrux` binary: `info`, `search`, `values` and
// `transitions` with `--json`, and `mcp`, which serves them to an agent.
// Built by `tool/build_cli.sh`; its import closure holds no Flutter
// (`test/static/headless_cli_closure_test.dart`).

import 'dart:io';

import 'package:wavecrux/headless/wavecrux_cli.dart';

Future<void> main(List<String> args) async {
  final code = await WaveCruxCli().run(args, out: stdout, err: stderr);
  await stdout.flush();
  await stderr.flush();
  // The reader's worker isolates would keep the process alive otherwise.
  exit(code);
}
