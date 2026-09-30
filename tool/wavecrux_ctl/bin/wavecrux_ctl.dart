// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:wavecrux_ctl/src/client.dart';
import 'package:wavecrux_ctl/src/runner.dart';

Future<void> main(List<String> args) async {
  final runner = WavecruxCtlRunner();
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  } on CliException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
}
