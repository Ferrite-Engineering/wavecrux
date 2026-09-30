// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_name_resolver.dart';

void main() {
  const resolver = WaveCruxNameResolver();

  group('WaveCruxNameResolver.toCanonical', () {
    test('returns null for empty local string', () {
      expect(
        resolver.toCanonical(kind: ElementKind.signal, local: ''),
        isNull,
      );
    });

    test('signal: round-trips hierarchical path', () {
      final id = resolver.toCanonical(
        kind: ElementKind.signal,
        local: 'top.cpu.alu.sum',
      );
      expect(id, isNotNull);
      expect(id!.kind, ElementKind.signal);
      expect(id.path, 'top.cpu.alu.sum');
    });

    test('signal: preserves bit-extracted slice', () {
      final id = resolver.toCanonical(
        kind: ElementKind.signal,
        local: 'top.bus.data[31:24]',
      );
      expect(id!.path, 'top.bus.data[31:24]');
    });

    test('signal: preserves generate-block instance name', () {
      final id = resolver.toCanonical(
        kind: ElementKind.signal,
        local: 'top.genblk1[3].reg',
      );
      expect(id!.path, 'top.genblk1[3].reg');
    });

    test('signal: preserves VCD escape prefix verbatim', () {
      final id = resolver.toCanonical(
        kind: ElementKind.signal,
        local: r'top.\foo[3] ',
      );
      expect(id!.path, r'top.\foo[3] ');
    });

    test('signal: preserves Yosys-style synthetic names verbatim', () {
      final id = resolver.toCanonical(
        kind: ElementKind.signal,
        local: r'top.$0\out[31:0]',
      );
      expect(id!.path, r'top.$0\out[31:0]');
    });

    test('scope: round-trips hierarchical scope path', () {
      final id = resolver.toCanonical(
        kind: ElementKind.scope,
        local: 'top.cpu',
      );
      expect(id!.kind, ElementKind.scope);
      expect(id.path, 'top.cpu');
    });

    test('marker: accepts single lowercase letter', () {
      for (final letter in const ['a', 'm', 'z']) {
        final id = resolver.toCanonical(
          kind: ElementKind.marker,
          local: letter,
        );
        expect(id, isNotNull, reason: letter);
        expect(id!.kind, ElementKind.marker);
        expect(id.path, letter);
      }
    });

    test('marker: rejects uppercase letter', () {
      expect(
        resolver.toCanonical(kind: ElementKind.marker, local: 'A'),
        isNull,
      );
    });

    test('marker: rejects multi-character name', () {
      expect(
        resolver.toCanonical(kind: ElementKind.marker, local: 'ab'),
        isNull,
      );
    });

    test('marker: rejects digit', () {
      expect(
        resolver.toCanonical(kind: ElementKind.marker, local: '1'),
        isNull,
      );
    });

    test('source: round-trips file:line citation', () {
      final id = resolver.toCanonical(
        kind: ElementKind.source,
        local: 'rtl/cpu.v:142',
      );
      expect(id!.kind, ElementKind.source);
      expect(id.path, 'rtl/cpu.v:142');
    });

    test('source: round-trips file:line:column citation', () {
      final id = resolver.toCanonical(
        kind: ElementKind.source,
        local: 'rtl/cpu.v:142:7',
      );
      expect(id!.path, 'rtl/cpu.v:142:7');
    });

    test('returns null for non-native kinds (rule/test/breakpoint)', () {
      for (final kind in const [
        ElementKind.rule,
        ElementKind.test,
        ElementKind.breakpoint,
        ElementKind.instance,
        ElementKind.net,
        ElementKind.port,
      ]) {
        expect(
          resolver.toCanonical(kind: kind, local: 'whatever'),
          isNull,
          reason: kind.toString(),
        );
      }
    });
  });

  group('WaveCruxNameResolver.toLocal', () {
    test('returns null for empty path', () {
      expect(
        resolver.toLocal(const ElementId(kind: ElementKind.signal, path: '')),
        isNull,
      );
    });

    test('signal: round-trips canonical hierarchical path', () {
      final local = resolver.toLocal(
        const ElementId(
          kind: ElementKind.signal,
          path: 'top.cpu.alu.sum',
        ),
      );
      expect(local, 'top.cpu.alu.sum');
    });

    test('scope: round-trips canonical scope path', () {
      final local = resolver.toLocal(
        const ElementId(kind: ElementKind.scope, path: 'top.cpu'),
      );
      expect(local, 'top.cpu');
    });

    test('marker: accepts a lowercase letter', () {
      final local = resolver.toLocal(
        const ElementId(kind: ElementKind.marker, path: 'a'),
      );
      expect(local, 'a');
    });

    test('marker: rejects malformed paths', () {
      for (final path in const ['A', 'aa', '1']) {
        expect(
          resolver.toLocal(
            ElementId(kind: ElementKind.marker, path: path),
          ),
          isNull,
          reason: path,
        );
      }
    });

    test('source: round-trips file:line:column', () {
      final local = resolver.toLocal(
        const ElementId(
          kind: ElementKind.source,
          path: 'rtl/cpu.v:142:7',
        ),
      );
      expect(local, 'rtl/cpu.v:142:7');
    });

    test('instance/net/port: pass through as signal-like paths', () {
      for (final kind in const [
        ElementKind.instance,
        ElementKind.net,
        ElementKind.port,
      ]) {
        final local = resolver.toLocal(
          ElementId(kind: kind, path: 'top.cpu.something'),
        );
        expect(
          local,
          'top.cpu.something',
          reason: 'kind=$kind',
        );
      }
    });

    test('rule/test/breakpoint: return null', () {
      for (final kind in const [
        ElementKind.rule,
        ElementKind.test,
        ElementKind.breakpoint,
      ]) {
        expect(
          resolver.toLocal(
            ElementId(kind: kind, path: 'whatever'),
          ),
          isNull,
          reason: kind.toString(),
        );
      }
    });
  });

  group('round-trip property', () {
    test('every produced ElementId round-trips toCanonical → toLocal', () {
      final cases = <(ElementKind, String)>[
        (ElementKind.signal, 'top.cpu.alu.sum'),
        (ElementKind.signal, 'top.bus.data[31:24]'),
        (ElementKind.signal, 'top.genblk1[3].reg'),
        (ElementKind.scope, 'top.cpu'),
        (ElementKind.marker, 'a'),
        (ElementKind.marker, 'z'),
        (ElementKind.source, 'rtl/cpu.v:142'),
        (ElementKind.source, 'rtl/cpu.v:142:7'),
      ];
      for (final (kind, local) in cases) {
        final id = resolver.toCanonical(kind: kind, local: local);
        expect(id, isNotNull, reason: '$kind $local');
        final back = resolver.toLocal(id!);
        expect(back, local, reason: '$kind $local');
      }
    });
  });

  group('unknown element kinds (open wire type)', () {
    // `ElementKind` is open: a peer built against a later protocol revision —
    // or a third-party tool with its own vocabulary — can put a kind on the
    // wire that this build has never heard of. The ruling is that such a kind
    // is IGNORED GRACEFULLY: no throw, no crash, just "not ours".
    final unknown = ElementKind('quantum_gate');

    test('the fixture kind really is unknown to this build', () {
      expect(unknown.known, isNull);
      expect(unknown.isKnown, isFalse);
      expect(ElementKind.values, isNot(contains(unknown)));
    });

    test('toCanonical returns null instead of throwing', () {
      expect(
        resolver.toCanonical(kind: unknown, local: 'top.thing'),
        isNull,
      );
    });

    test('toLocal returns null instead of throwing', () {
      expect(
        resolver.toLocal(ElementId(kind: unknown, path: 'top.thing')),
        isNull,
      );
    });

    test('an unknown kind is not guessed to be signal-like', () {
      // The tempting shortcut — treat anything with a dotted path as a signal
      // — would silently highlight the wrong object for a kind whose path
      // grammar we do not know. Forward-compat means declining, not guessing.
      expect(
        resolver.toLocal(ElementId(kind: unknown, path: 'top.cpu.alu.sum')),
        isNull,
      );
    });
  });
}
