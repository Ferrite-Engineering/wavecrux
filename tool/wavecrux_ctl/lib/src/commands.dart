// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'client.dart';
import 'formatter.dart';

// ── Base ──────────────────────────────────────────────────────────────────────

/// Base class for all wavecrux-ctl commands.
///
/// Handles connection lifecycle, global option access, and consistent
/// error reporting. Throws [CliException] on failure so that [main] can
/// decide whether to call exit().
abstract class WavecruxCommand extends Command<void> {
  WavecruxCommand({required IOSink output, required WcpClientFactory factory})
    : _output = output,
      _factory = factory;

  final IOSink _output;
  final WcpClientFactory _factory;

  String get _host => (globalResults?['host'] as String?) ?? 'localhost';
  int get _port =>
      int.tryParse(
        (globalResults?['port'] as String?) ?? '${WcpClient.defaultPort}',
      ) ??
      WcpClient.defaultPort;
  bool get _jsonFlag => (globalResults?['json'] as bool?) ?? false;

  Future<void> withClient(Future<void> Function(WcpClient client) body) async {
    final client = _factory(_host, _port);
    try {
      await body(client);
    } on WcpException catch (e) {
      throw CliException(e.toString());
    } finally {
      await client.close();
    }
  }

  void emit(String text) => _output.writeln(text);

  void emitResult(
    Map<String, dynamic> result,
    String Function(Map<String, dynamic> r) formatter,
  ) {
    if (_jsonFlag) {
      emit(Formatter.rawJson(result));
    } else {
      emit(formatter(result));
    }
  }
}

// ── load ──────────────────────────────────────────────────────────────────────

/// Loads a waveform file into WaveCrux.
class LoadCommand extends WavecruxCommand {
  LoadCommand({required super.output, required super.factory});

  @override
  String get name => 'load';

  @override
  String get description => 'Load a waveform file.';

  @override
  String get invocation => 'wavecrux-ctl [options] load <file>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Expected a file path argument.');

    await withClient((client) async {
      final result = await client.call('load', {'source': rest.first});
      emitResult(result, (_) => 'Loaded: ${rest.first}');
    });
  }
}

// ── add ───────────────────────────────────────────────────────────────────────

/// Adds one or more signals to the waveform viewer.
class AddCommand extends WavecruxCommand {
  AddCommand({required super.output, required super.factory});

  @override
  String get name => 'add';

  @override
  String get description => 'Add signal(s) to the viewer by full path.';

  @override
  String get invocation => 'wavecrux-ctl [options] add <signal_path> [...]';

  @override
  Future<void> run() async {
    final paths = argResults!.rest;
    if (paths.isEmpty) usageException('Expected at least one signal path.');

    await withClient((client) async {
      final result = await client.call('add_items', {'paths': paths});
      emitResult(result, (r) {
        final items = r['items'] as List<dynamic>? ?? [];
        if (items.length == 1) {
          return 'Added: ${(items.first as Map)['path']}';
        }
        return 'Added ${items.length} signal(s).';
      });
    });
  }
}

// ── remove ────────────────────────────────────────────────────────────────────

/// Removes a signal from the waveform viewer.
class RemoveCommand extends WavecruxCommand {
  RemoveCommand({required super.output, required super.factory});

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a signal from the viewer.';

  @override
  String get invocation => 'wavecrux-ctl [options] remove <signal_path>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Expected a signal path argument.');

    await withClient((client) async {
      final listResult = await client.call('get_item_list');
      final items = listResult['items'] as List<dynamic>? ?? [];
      final item = items
          .cast<Map<String, dynamic>>()
          .where((i) => i['path'] == rest.first)
          .firstOrNull;

      if (item == null) {
        throw CliException('Signal not found in viewer: ${rest.first}');
      }

      await client.call('remove_items', {
        'ids': [item['id']],
      });
      emitResult({'path': rest.first}, (_) => 'Removed: ${rest.first}');
    });
  }
}

// ── cursor ────────────────────────────────────────────────────────────────────

/// Places the primary cursor at a simulation tick.
class CursorCommand extends WavecruxCommand {
  CursorCommand({required super.output, required super.factory});

  @override
  String get name => 'cursor';

  @override
  String get description => 'Place the primary cursor at a simulation tick.';

  @override
  String get invocation => 'wavecrux-ctl [options] cursor <time>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('Expected a time (integer tick) argument.');
    }

    final time = int.tryParse(rest.first);
    if (time == null) {
      usageException('Time must be an integer (simulation ticks).');
    }

    await withClient((client) async {
      final result = await client.call('set_cursor', {'timestamp': time});
      emitResult(result, (_) => 'Cursor set to tick $time.');
    });
  }
}

// ── marker ────────────────────────────────────────────────────────────────────

/// Sets a named marker (a–z) at a simulation tick.
class MarkerCommand extends WavecruxCommand {
  MarkerCommand({required super.output, required super.factory});

  @override
  String get name => 'marker';

  @override
  String get description => 'Set a named marker (a–z) at a simulation tick.';

  @override
  String get invocation => 'wavecrux-ctl [options] marker <name> <time>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      usageException('Expected: marker <name> <time>');
    }

    final markerName = rest[0];
    if (markerName.length != 1 || !RegExp(r'^[a-z]$').hasMatch(markerName)) {
      usageException('Marker name must be a single lowercase letter (a–z).');
    }

    final time = int.tryParse(rest[1]);
    if (time == null) {
      usageException('Time must be an integer (simulation ticks).');
    }

    await withClient((client) async {
      final result = await client.call('add_markers', {
        'markers': [
          {'name': markerName, 'time': time},
        ],
      });
      emitResult(result, (r) {
        final item = ((r['items'] as List).first) as Map;
        return "Marker '${item['name']}' set to tick ${item['time']}.";
      });
    });
  }
}

// ── zoom ──────────────────────────────────────────────────────────────────────

/// Centers the viewport on a simulation timestamp.
class ZoomCommand extends WavecruxCommand {
  ZoomCommand({required super.output, required super.factory});

  @override
  String get name => 'zoom';

  @override
  String get description => 'Center viewport on a simulation timestamp.';

  @override
  String get invocation => 'wavecrux-ctl [options] zoom <timestamp>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Expected a timestamp (positive number).');

    final level = num.tryParse(rest.first);
    if (level == null || level <= 0) {
      usageException('Zoom level must be a positive number.');
    }

    await withClient((client) async {
      final result = await client.call('set_viewport_to', {
        'timestamp': level.toInt(),
      });
      emitResult(result, (_) => 'Viewport centered on tick ${level.toInt()}.');
    });
  }
}

// ── fit ───────────────────────────────────────────────────────────────────────

/// Fits the entire simulation in the viewport.
class FitCommand extends WavecruxCommand {
  FitCommand({required super.output, required super.factory});

  @override
  String get name => 'fit';

  @override
  String get description => 'Zoom to fit the entire simulation in view.';

  @override
  Future<void> run() async {
    await withClient((client) async {
      final result = await client.call('zoom_to_fit');
      emitResult(result, (_) => 'Fit all.');
    });
  }
}

// ── signals ───────────────────────────────────────────────────────────────────

/// Lists all signals currently displayed in the viewer.
class SignalsCommand extends WavecruxCommand {
  SignalsCommand({required super.output, required super.factory});

  @override
  String get name => 'signals';

  @override
  String get description => 'List signals currently displayed in the viewer.';

  @override
  Future<void> run() async {
    await withClient((client) async {
      final result = await client.call('get_item_list');
      emitResult(result, Formatter.formatItems);
    });
  }
}

// ── value ─────────────────────────────────────────────────────────────────────

/// Gets the value of a signal at the cursor or a specified time.
class ValueCommand extends WavecruxCommand {
  ValueCommand({required super.output, required super.factory});

  @override
  String get name => 'value';

  @override
  String get description =>
      'Get signal value at the cursor position or a specified tick.';

  @override
  String get invocation => 'wavecrux-ctl [options] value <signal_path> [time]';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Expected a signal path argument.');

    final signalPath = rest.first;
    int? explicitTime;
    if (rest.length >= 2) {
      explicitTime = int.tryParse(rest[1]);
      if (explicitTime == null) {
        usageException('Time must be an integer (simulation ticks).');
      }
    }

    await withClient((client) async {
      int time;
      if (explicitTime != null) {
        time = explicitTime;
      } else {
        final state = await client.call('wavecrux.getState');
        time = (state['cursor'] as int?) ?? 0;
      }

      final result = await client.call('wavecrux.getValueAt', {
        'signal_path': signalPath,
        'time': time,
      });
      emitResult(result, Formatter.formatValue);
    });
  }
}

// ── hierarchy ─────────────────────────────────────────────────────────────────

/// Prints the design hierarchy as a tree.
class HierarchyCommand extends WavecruxCommand {
  HierarchyCommand({required super.output, required super.factory});

  @override
  String get name => 'hierarchy';

  @override
  String get description => 'Print the design scope/signal hierarchy.';

  @override
  Future<void> run() async {
    await withClient((client) async {
      final result = await client.call('wavecrux.getHierarchy');
      emitResult(result, Formatter.formatHierarchy);
    });
  }
}

// ── status ────────────────────────────────────────────────────────────────────

/// Prints the current viewer state.
class StatusCommand extends WavecruxCommand {
  StatusCommand({required super.output, required super.factory});

  @override
  String get name => 'status';

  @override
  String get description => 'Print the current WaveCrux viewer state.';

  @override
  Future<void> run() async {
    await withClient((client) async {
      final result = await client.call('wavecrux.getState');
      emitResult(result, Formatter.formatState);
    });
  }
}
