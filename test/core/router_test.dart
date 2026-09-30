// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wavecrux/core/router.dart';

void main() {
  group('routerProvider', () {
    test('creates a GoRouter instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      expect(router, isA<GoRouter>());
    });

    test('keeps the router alive across reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(routerProvider);
      final second = container.read(routerProvider);
      expect(identical(first, second), isTrue);
    });
  });

  // Regression for "GoException: no routes for location: file:///…" when the
  // engine forwards a dropped/opened file URL to go_router as a deep link in
  // parallel with IncomingFilePlugin. The redirect catches the file:// URL —
  // but what it does with it is platform-dependent (see fileUrlRedirect docs).
  group('fileUrlRedirect', () {
    // Desktop: the file:// path is directly readable, so open it via ?file=.
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      test('desktop ($platform) rewrites file:// to /viewer?file=<path>', () {
        final out = fileUrlRedirect(
          Uri.parse('file:///Users/jane/traces/test.vcd'),
          platform: platform,
        );
        expect(out, isNotNull);
        final rewritten = Uri.parse(out!);
        expect(rewritten.path, '/viewer');
        expect(
          rewritten.queryParameters['file'],
          '/Users/jane/traces/test.vcd',
        );
      });
    }

    // Mobile: the raw file:// path is a security-scoped / non-materialized
    // location the app cannot read; IncomingFilePlugin delivers the sandbox
    // copy instead. So the deep-link must be absorbed WITHOUT the raw path,
    // otherwise the raw path is opened and fails (errno 1 / 2). Regression for
    // the iOS/Android share-sheet open.
    for (final platform in const [
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      test('mobile ($platform) absorbs file:// to /viewer (no raw ?file=)', () {
        final out = fileUrlRedirect(
          Uri.parse(
            'file:///private/var/mobile/Library/Mail/AttachmentData/1/test.vcd',
          ),
          platform: platform,
        );
        expect(out, '/viewer');
      });
    }

    // Desktop repeat-open: macOS delivers a Finder double-click / `open -a` of
    // an already-open path as the IDENTICAL file:// deep-link. go_router
    // no-ops an unchanged location, so the rewrite must stamp a fresh `req`
    // token each time or the second open of the same path is silently dropped
    // (the "open-of-already-seen-path" defect).
    test('desktop rewrite stamps a monotonic req token for repeat opens', () {
      debugResetFileUrlOpenSeq();
      addTearDown(debugResetFileUrlOpenSeq);
      const path = 'file:///Users/jane/traces/dump.vcd';
      final first = Uri.parse(
        fileUrlRedirect(Uri.parse(path), platform: TargetPlatform.macOS)!,
      );
      final second = Uri.parse(
        fileUrlRedirect(Uri.parse(path), platform: TargetPlatform.macOS)!,
      );
      // Same file both times…
      expect(first.queryParameters['file'], '/Users/jane/traces/dump.vcd');
      expect(second.queryParameters['file'], '/Users/jane/traces/dump.vcd');
      // …but a strictly increasing req token, so the locations differ and the
      // second open actually reaches ViewerScreen.didUpdateWidget.
      final r1 = int.parse(first.queryParameters['req']!);
      final r2 = int.parse(second.queryParameters['req']!);
      expect(r2, greaterThan(r1));
      expect(first.toString(), isNot(second.toString()));
    });

    // The absorbed mobile path carries neither the raw file nor a req token.
    test('mobile absorb path never stamps a req token', () {
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        final out = fileUrlRedirect(
          Uri.parse('file:///x/dump.vcd'),
          platform: platform,
        );
        expect(Uri.parse(out!).queryParameters, isEmpty);
      }
    });

    test('returns null for non-file schemes on every platform', () {
      for (final platform in TargetPlatform.values) {
        expect(
          fileUrlRedirect(Uri.parse('/viewer?file=/x.vcd'), platform: platform),
          isNull,
        );
        expect(
          fileUrlRedirect(Uri.parse('/settings'), platform: platform),
          isNull,
        );
        expect(
          fileUrlRedirect(
            Uri.parse('https://example.com/x'),
            platform: platform,
          ),
          isNull,
        );
      }
    });
  });

  // The full redirect decision, including the legacy `/` → `/viewer` rewrite.
  // Regression for the bug where a bare-root `/?file=<url>` deep link (a web
  // browser address-bar URL, or any older `/`-rooted deep link carrying query
  // params) lost its query string: `path == '/'` unconditionally rewrote to a
  // bare `/viewer`, dropping `?file=`/`?session=`, so the file never opened.
  group('rootRedirect', () {
    test('bare `/` (no query) rewrites to `/viewer`', () {
      expect(rootRedirect(Uri.parse('/')), '/viewer');
    });

    test('`/?file=<url>` preserves the file query param', () {
      final out = rootRedirect(
        Uri.parse('/?file=https://example.com/dump.vcd'),
      );
      expect(out, isNotNull);
      final rewritten = Uri.parse(out!);
      expect(rewritten.path, '/viewer');
      expect(
        rewritten.queryParameters['file'],
        'https://example.com/dump.vcd',
      );
    });

    test('`/?session=<path>` preserves the session query param', () {
      final out = rootRedirect(Uri.parse('/?session=/Users/jane/x.wavecrux'));
      expect(out, isNotNull);
      final rewritten = Uri.parse(out!);
      expect(rewritten.path, '/viewer');
      expect(
        rewritten.queryParameters['session'],
        '/Users/jane/x.wavecrux',
      );
    });

    test('`/` with multiple query params preserves all of them', () {
      final out = rootRedirect(Uri.parse('/?file=/x.vcd&req=7'));
      final rewritten = Uri.parse(out!);
      expect(rewritten.path, '/viewer');
      expect(rewritten.queryParameters['file'], '/x.vcd');
      expect(rewritten.queryParameters['req'], '7');
    });

    test('the rewritten `/viewer?file=` location does not redirect again '
        '(no loop)', () {
      // Feeding the first redirect's output back in must be a no-op — a
      // `/viewer` path is not `/`, and the query carries no `file://` scheme,
      // so rootRedirect returns null (go_router stops redirecting).
      final first = rootRedirect(Uri.parse('/?file=/x.vcd'))!;
      expect(rootRedirect(Uri.parse(first)), isNull);
    });

    test('non-root paths defer to fileUrlRedirect (file:// still caught)', () {
      // A desktop file:// deep link on a non-`/` path is still rewritten.
      final out = rootRedirect(
        Uri.parse('file:///Users/jane/traces/test.vcd'),
        platform: TargetPlatform.macOS,
      );
      expect(out, isNotNull);
      expect(
        Uri.parse(out!).queryParameters['file'],
        '/Users/jane/traces/test.vcd',
      );
    });

    test('a plain `/viewer` (no query) is left alone', () {
      expect(rootRedirect(Uri.parse('/viewer')), isNull);
    });
  });
}
