// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A decoder plugin that fails is reported where a release build can see it.
//
// The loader and the directory resolver used to report through
// `developer.log`, which emits nothing from an AOT build: a plugin author, or
// a user filing a report, had no trace of why a plugin was missing. Faults now
// go to the `wavecrux.decoders.plugins` Logger, which reaches the issue
// reporter's buffer and, at SEVERE, stderr. Routine tracing stays off it.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader_io.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';

const _channel = 'wavecrux.decoders.plugins';

PluginHostPlatform _host() => Platform.isWindows
    ? PluginHostPlatform.windows
    : Platform.isMacOS
    ? PluginHostPlatform.macos
    : PluginHostPlatform.linux;

/// Scans exactly [directory].
class _OneDirectoryResolver extends PluginDirectoryResolver {
  _OneDirectoryResolver(this.directory)
    : super(
        context: PluginPlatformContext(
          platform: _host(),
          appSupportPath: directory.path,
        ),
      );

  final Directory directory;

  @override
  List<Directory> resolveDirectories({
    List<String> userConfigured = const <String>[],
    String? envVarRaw,
    bool Function(String path)? exists,
  }) => [directory];
}

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> subscription;
  setUp(() {
    records = [];
    subscription = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => subscription.cancel());

  List<LogRecord> onChannel() =>
      records.where((r) => r.loggerName == _channel).toList();

  group('FfiDecoderLoader', () {
    test('a plugin that will not open is reported at SEVERE', () async {
      final dir = await Directory.systemTemp.createTemp('wcx_plugin_log_');
      addTearDown(() => dir.delete(recursive: true));
      File(p.join(dir.path, 'broken.so')).writeAsStringSync('not a library');
      final loader = FfiDecoderLoader(
        resolver: _OneDirectoryResolver(dir),
        registry: DecoderRegistry.forTesting(),
        opener: (_) => throw ArgumentError('dlopen failed'),
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos.single.loadStatus, DecoderPluginLoadStatus.loadError);
      final record = onChannel().single;
      expect(record.level, Level.SEVERE);
      expect(record.message, contains('cannot open shared library'));
      expect(record.message, contains('broken.so'));
    });

    test('loading turned off in Settings is a trace, not a fault', () async {
      final dir = await Directory.systemTemp.createTemp('wcx_plugin_log_');
      addTearDown(() => dir.delete(recursive: true));
      final loader = FfiDecoderLoader(
        resolver: _OneDirectoryResolver(dir),
        registry: DecoderRegistry.forTesting(),
        pluginLoadingDisabled: true,
      );
      addTearDown(loader.dispose);

      await loader.scan();

      expect(onChannel(), isEmpty);
    });
  });

  group('PluginDirectoryResolver', () {
    const resolver = PluginDirectoryResolver(
      context: PluginPlatformContext(
        platform: PluginHostPlatform.linux,
        appSupportPath: '/home/u',
      ),
    );

    test('a configured directory that is missing is a WARNING', () {
      resolver.resolveDirectories(
        userConfigured: ['/srv/plugins'],
        exists: (_) => false,
      );

      final record = onChannel().single;
      expect(record.level, Level.WARNING);
      expect(record.message, contains('/srv/plugins'));
    });

    test('a relative path is a WARNING', () {
      resolver.resolveCandidatePaths(envVarRaw: 'plugins');

      final record = onChannel().single;
      expect(record.level, Level.WARNING);
      expect(record.message, contains('WAVECRUX_DECODER_PATH'));
    });

    test('the platform default missing is a trace, not a fault', () {
      resolver.resolveDirectories(exists: (_) => false);

      expect(onChannel(), isEmpty);
    });
  });
}
