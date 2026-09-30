// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guard for the one semantic that asset *discovery* could silently break.
//
// `InstructionDisassembler` resolves an encoding matched by more than one
// instruction set by "last match wins", so set load order is behavior, not
// presentation. Before A2b the order was frozen by a hardcoded 10-filename
// list; now it comes from discovery over `AssetManifest` + the total order
// imposed by `compareIsaSetNames`. This file proves the replacement is
// behavior-preserving in the only way that actually counts:
//
//  1. `compareIsaSetNames` is a total order, and it puts RV32I before RV64I.
//  2. Across the whole bundled corpus, the *only* cross-set encoding
//     ambiguities are RV32I-vs-RV64I `slli` / `srli` / `srai`. That is
//     computed exhaustively from the (mask, match) pairs — two instructions
//     can both match some word iff
//     `(matchA ^ matchB) & maskA & maskB == 0` — not asserted from memory.
//
// Together those mean the ordering of every *other* pair is irrelevant to
// decode output, so any comparator satisfying (1) reproduces the old
// behavior exactly. If a future TOML introduces a new ambiguity, (2) fails
// here rather than letting the sort quietly pick a winner.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';

/// The ambiguities the RISC-V corpus is *known and intended* to contain.
/// RV64I re-declares the shift-immediates with a 6-bit shamt; it must load
/// after RV32I so its wider form wins.
const _expectedAmbiguities = <String>{
  'RV32I:slli <-> RV64I:slli',
  'RV32I:srai <-> RV64I:srai',
  'RV32I:srli <-> RV64I:srli',
};

void main() {
  final dir = Directory(
    '$kIsaDecoderAssetRoot/$kDefaultIsaArchitecture',
  );

  final names =
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.toml'))
          .map((n) => n.substring(0, n.length - '.toml'.length))
          .toList()
        ..sort(compareIsaSetNames);

  final sets = <String, InstructionSet>{
    for (final n in names)
      n: parseInstructionSetToml(
        File('${dir.path}/$n.toml').readAsStringSync(),
        sourceLabel: '$n.toml',
      ),
  };

  group('compareIsaSetNames', () {
    test('is a total order — no two distinct names compare equal', () {
      for (var i = 0; i < names.length; i++) {
        for (var j = 0; j < names.length; j++) {
          final c = compareIsaSetNames(names[i], names[j]);
          if (i == j) {
            expect(c, 0, reason: '${names[i]} vs itself');
          } else {
            expect(
              c,
              isNot(0),
              reason:
                  'ambiguous ordering between ${names[i]} and ${names[j]} — '
                  'discovery order would leak into decode behavior',
            );
            expect(
              c.sign,
              -compareIsaSetNames(names[j], names[i]).sign,
              reason: 'antisymmetry broken for ${names[i]}/${names[j]}',
            );
          }
        }
      }
    });

    test('is independent of the order discovery hands it back', () {
      final shuffled = names.reversed.toList()..sort(compareIsaSetNames);
      expect(shuffled, names);
    });

    test('orders narrower base sets before wider siblings', () {
      expect(names.indexOf('RV32I'), lessThan(names.indexOf('RV64I')));
      expect(names.indexOf('RV32M'), lessThan(names.indexOf('RV64M')));
      expect(names.indexOf('RV32A'), lessThan(names.indexOf('RV64A')));
      expect(
        names.indexOf('RV32C-lower'),
        lessThan(names.indexOf('RV64C-lower')),
      );
    });
  });

  group('bundled corpus ambiguity', () {
    test('discovery finds the full corpus', () {
      expect(names, hasLength(10));
      expect(names, contains('RV32I'));
      expect(names, contains('RV64I'));
    });

    test(
      'the only cross-set encoding ambiguities are the RV32I/RV64I shifts',
      () {
        final found = <String>{};
        for (var i = 0; i < names.length; i++) {
          for (var j = i + 1; j < names.length; j++) {
            final a = sets[names[i]]!;
            final b = sets[names[j]]!;
            // Only sets of equal encoding width ever compete: the
            // disassembler skips sets whose bitWidth differs from the query.
            if (a.bitWidth != b.bitWidth) continue;
            for (final fa in a.formats) {
              for (final ia in fa.instructions) {
                for (final fb in b.formats) {
                  for (final ib in fb.instructions) {
                    if (((ia.match ^ ib.match) & ia.mask & ib.mask) != 0) {
                      continue;
                    }
                    found.add(
                      '${names[i]}:${ia.name} <-> ${names[j]}:${ib.name}',
                    );
                  }
                }
              }
            }
          }
        }
        expect(
          found,
          _expectedAmbiguities,
          reason:
              'Set load order only affects decode output for encodings that '
              'more than one set matches. A change here means discovery order '
              'now decides an outcome it did not decide before — resolve it '
              'explicitly (see compareIsaSetNames) rather than updating this '
              'expectation blindly.',
        );
      },
    );
  });
}
