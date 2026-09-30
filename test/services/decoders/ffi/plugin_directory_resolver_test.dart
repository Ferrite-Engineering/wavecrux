// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';

void main() {
  group('PluginDirectoryResolver', () {
    group('default-path resolution', () {
      test('Linux uses <appSupport>/wavecrux/decoders', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/user/.config',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths();
        expect(paths, ['/home/user/.config/wavecrux/decoders']);
      });

      test('macOS uses <appSupport>/wavecrux/decoders', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.macos,
          appSupportPath: '/Users/dev/Library/Application Support',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths();
        expect(paths, [
          '/Users/dev/Library/Application Support/wavecrux/decoders',
        ]);
      });

      test('Windows uses <appSupport>/WaveCrux/decoders', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.windows,
          appSupportPath: r'C:\Users\dev\AppData\Roaming',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths();
        expect(paths.length, 1);
        // path package normalizes — just confirm the salient parts.
        expect(
          paths.first.endsWith(r'WaveCrux\decoders'),
          isTrue,
          reason: 'paths.first = ${paths.first}',
        );
      });
    });

    group('environment variable parsing', () {
      test('Unix splits on colon', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/user/.config',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          envVarRaw: '/opt/wc/plugins:/srv/team/decoders',
        );
        expect(paths, [
          '/opt/wc/plugins',
          '/srv/team/decoders',
          '/home/user/.config/wavecrux/decoders',
        ]);
      });

      test('Windows splits on semicolon', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.windows,
          appSupportPath: r'C:\Users\dev\AppData\Roaming',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          envVarRaw: r'C:\Plugins\one;D:\Plugins\two',
        );
        expect(paths.length, 3);
        expect(paths[0], r'C:\Plugins\one');
        expect(paths[1], r'D:\Plugins\two');
      });

      test('empty entries are ignored', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(envVarRaw: '/a::/b:');
        expect(paths.where((p) => p.startsWith('/')).toList(), [
          '/a',
          '/b',
          '/home/u/wavecrux/decoders',
        ]);
      });

      test('whitespace-only entries are ignored', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(envVarRaw: '   :  ');
        expect(paths, ['/home/u/wavecrux/decoders']);
      });

      test('relative paths in env var are rejected', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          envVarRaw: './relative:/abs/path',
        );
        expect(paths, ['/abs/path', '/home/u/wavecrux/decoders']);
      });

      test('null env var means none', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths();
        expect(paths, ['/home/u/wavecrux/decoders']);
      });
    });

    group('user-configured paths', () {
      test('appended in priority order between env var and default', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          userConfigured: ['/usr/local/wc'],
          envVarRaw: '/etc/wc',
        );
        expect(paths, [
          '/etc/wc',
          '/usr/local/wc',
          '/home/u/wavecrux/decoders',
        ]);
      });

      test('relative user-configured paths are rejected', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          userConfigured: ['plugins/local', '/abs/wc'],
        );
        expect(paths, ['/abs/wc', '/home/u/wavecrux/decoders']);
      });

      test('empty user-configured strings ignored', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          userConfigured: ['', '   '],
        );
        expect(paths, ['/home/u/wavecrux/decoders']);
      });
    });

    group('deduplication', () {
      test('duplicate paths across sources collapse, first wins (Linux, '
          'case-sensitive)', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          userConfigured: ['/etc/wc'],
          envVarRaw: '/etc/wc',
        );
        expect(paths, ['/etc/wc', '/home/u/wavecrux/decoders']);
      });

      test('case differences kept distinct on Linux', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          envVarRaw: '/etc/wc:/etc/WC',
        );
        expect(paths, [
          '/etc/wc',
          '/etc/WC',
          '/home/u/wavecrux/decoders',
        ]);
      });

      test('case-insensitive collapse on macOS', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.macos,
          appSupportPath: '/Users/dev/Library/Application Support',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          envVarRaw: '/Plugins:/PLUGINS',
        );
        expect(paths, [
          '/Plugins',
          '/Users/dev/Library/Application Support/wavecrux/decoders',
        ]);
      });

      test('case-insensitive collapse on Windows', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.windows,
          appSupportPath: r'C:\Users\dev\AppData\Roaming',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          envVarRaw: r'C:\plugins;c:\PLUGINS',
        );
        // Both env entries collapse; only the default remains alongside.
        expect(paths.length, 2);
        expect(paths.first, r'C:\plugins');
      });

      test('default path collapses if user-configured matches it', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final paths = resolver.resolveCandidatePaths(
          userConfigured: ['/home/u/wavecrux/decoders'],
        );
        expect(paths, ['/home/u/wavecrux/decoders']);
      });
    });

    group('resolveDirectories existence filtering', () {
      test('skips nonexistent paths', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final dirs = resolver.resolveDirectories(
          envVarRaw: '/exists:/missing',
          exists: (p) => p == '/exists',
        );
        expect(dirs.map((d) => d.path).toList(), ['/exists']);
      });

      test('returns Directory objects in priority order', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final dirs = resolver.resolveDirectories(
          userConfigured: ['/srv/wc'],
          envVarRaw: '/etc/wc',
          exists: (_) => true,
        );
        expect(dirs.map((d) => d.path).toList(), [
          '/etc/wc',
          '/srv/wc',
          '/home/u/wavecrux/decoders',
        ]);
      });

      test('returns empty when nothing exists', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/home/u',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        final dirs = resolver.resolveDirectories(exists: (_) => false);
        expect(dirs, isEmpty);
      });

      test('default existence check returns Directory objects that may or may '
          'not exist (smoke)', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/__definitely_not_a_real_path__',
        );
        const resolver = PluginDirectoryResolver(context: ctx);
        // No injected `exists` callback — the resolver uses
        // Directory.existsSync. The default path doesn't exist, so we
        // expect zero directories.
        final dirs = resolver.resolveDirectories();
        expect(dirs, isEmpty);
      });
    });

    group('PluginPlatformContext', () {
      test('environment defaults to empty', () {
        const ctx = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/x',
        );
        expect(ctx.environment, isEmpty);
      });

      test('pathListSeparator is colon on Unix', () {
        const linux = PluginPlatformContext(
          platform: PluginHostPlatform.linux,
          appSupportPath: '/x',
        );
        const macos = PluginPlatformContext(
          platform: PluginHostPlatform.macos,
          appSupportPath: '/x',
        );
        expect(linux.pathListSeparator, ':');
        expect(macos.pathListSeparator, ':');
      });

      test('pathListSeparator is semicolon on Windows', () {
        const win = PluginPlatformContext(
          platform: PluginHostPlatform.windows,
          appSupportPath: r'C:\x',
        );
        expect(win.pathListSeparator, ';');
      });
    });

    test('resolved Directory objects use the resolved path', () {
      const ctx = PluginPlatformContext(
        platform: PluginHostPlatform.linux,
        appSupportPath: '/home/u',
      );
      const resolver = PluginDirectoryResolver(context: ctx);
      final dirs = resolver.resolveDirectories(
        envVarRaw: '/some/dir',
        exists: (_) => true,
      );
      expect(dirs.first, isA<Directory>());
      expect(dirs.first.path, '/some/dir');
    });
  });
}
