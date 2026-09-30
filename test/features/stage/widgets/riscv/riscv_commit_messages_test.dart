// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_messages.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

const List<Locale> _locales = [
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// A violation of [kind] with placeholder-shaped args, for formatting only.
RiscvConsistencyViolation _synthetic(RiscvViolationKind kind) =>
    RiscvConsistencyViolation(
      kind: kind,
      severity: RiscvViolationSeverity.error,
      retireIndex: 0,
      time: 0,
      detail: 'synthetic',
      args: [
        for (var i = 0; i < kind.argCount; i++) 'ARG$i',
      ],
    );

void main() {
  for (final locale in _locales) {
    group('$locale', () {
      late L10N l10n;

      setUp(() async {
        l10n = await L10N.delegate.load(locale);
      });

      // The formatter indexes `violation.args` positionally. An off-by-one
      // there would throw in front of a user on a trace that fired that one
      // rule — so every kind is formatted here, in every locale.
      test('every violation kind formats without throwing', () {
        for (final kind in RiscvViolationKind.values) {
          final message = riscvViolationMessage(l10n, _synthetic(kind));
          expect(message, isNotEmpty, reason: '$kind');
        }
      });

      test('every violation message interpolates all of its args', () {
        for (final kind in RiscvViolationKind.values) {
          final message = riscvViolationMessage(l10n, _synthetic(kind));
          for (var i = 0; i < kind.argCount; i++) {
            expect(
              message,
              contains('ARG$i'),
              reason: '$kind dropped arg $i in $locale',
            );
          }
        }
      });

      test('every message is localized, not left as the raw ARB key', () {
        for (final kind in RiscvViolationKind.values) {
          final message = riscvViolationMessage(l10n, _synthetic(kind));
          expect(message, isNot(contains('riscvCommitViolation')));
          expect(message, isNot(contains('{')));
        }
      });

      test('every rule has a name and every severity a label', () {
        for (final rule in RiscvCheckRule.values) {
          expect(riscvRuleName(l10n, rule), isNotEmpty, reason: '$rule');
        }
        for (final severity in RiscvViolationSeverity.values) {
          expect(
            riscvSeverityLabel(l10n, severity),
            isNotEmpty,
            reason: '$severity',
          );
        }
      });

      test('rule names are distinct — a shared name would be useless in the '
          '"not checked" line', () {
        final names = [
          for (final rule in RiscvCheckRule.values) riscvRuleName(l10n, rule),
        ];
        expect(names.toSet(), hasLength(names.length));
      });

      // The Checks tab's headline counts are all ICU plurals, so the singular
      // has to be exercised: a count of one is the *first* value that makes
      // the summary render at all, and the flat interpolation this replaced
      // put "1 errors" at the top of the RVFI Commit Inspector.
      test('the checker headlines survive a count of one', () {
        for (final message in [
          l10n.riscvCommitChecksSummary(1, 1, 1),
          l10n.riscvCommitChecksClean(1),
          l10n.riscvCommitMemoryBytes(1),
          l10n.pipelineLowConfidenceBanner(1, 'positional'),
          l10n.pipelineDegradedBanner(1, 'positional'),
        ]) {
          expect(message, isNotEmpty);
          expect(message, isNot(contains('{')));
        }
      });
    });
  }

  group('English plural agreement in the Checks tab', () {
    late L10N l10n;

    setUp(() async {
      l10n = await L10N.delegate.load(const Locale('en'));
    });

    test('one error and one warning over one retirement is singular '
        'throughout', () {
      // The headline of the RVFI Commit Inspector's Checks tab, and the
      // widget that goes into the RISC-V International demo — "1 errors" was
      // visible there.
      expect(
        l10n.riscvCommitChecksSummary(1, 1, 1),
        '1 error, 1 warning over 1 retirement',
      );
    });

    test('every other combination stays plural', () {
      expect(
        l10n.riscvCommitChecksSummary(0, 2, 8),
        '0 errors, 2 warnings over 8 retirements',
      );
      expect(
        l10n.riscvCommitChecksSummary(3, 0, 12),
        '3 errors, 0 warnings over 12 retirements',
      );
    });

    test('the clean line, the byte count and the pipeline banners agree '
        'too', () {
      expect(
        l10n.riscvCommitChecksClean(1),
        '1 retirement checked, no inconsistency found.',
      );
      expect(
        l10n.riscvCommitChecksClean(8),
        '8 retirements checked, no inconsistency found.',
      );
      // `lb` / `sb` cover exactly one byte, so this is a routine value, not an
      // edge case.
      expect(l10n.riscvCommitMemoryBytes(1), '1 byte');
      expect(l10n.riscvCommitMemoryBytes(4), '4 bytes');
      expect(
        l10n.pipelineLowConfidenceBanner(1, 'positional'),
        contains('in 1 cell.'),
      );
      expect(
        l10n.pipelineLowConfidenceBanner(2, 'positional'),
        contains('in 2 cells.'),
      );
      expect(
        l10n.pipelineDegradedBanner(1, 'positional'),
        contains('resolved 1 ambiguity by convention'),
      );
      expect(
        l10n.pipelineDegradedBanner(3, 'positional'),
        contains('resolved 3 ambiguities by convention'),
      );
    });
  });

  group('riscvChannelList', () {
    test('renders the canonical port names, sorted', () {
      expect(
        riscvChannelList({
          RvfiChannel.memWmask,
          RvfiChannel.trap,
          RvfiChannel.memAddr,
        }),
        'rvfi_mem_addr, rvfi_mem_wmask, rvfi_trap',
      );
    });

    test('is empty for an empty set', () {
      expect(riscvChannelList(const <RvfiChannel>{}), isEmpty);
    });

    test("is deliberately not localized — these are the user's own port "
        'names', () async {
      final ja = await L10N.delegate.load(const Locale('ja'));
      expect(ja, isNotNull);
      expect(
        riscvChannelList({RvfiChannel.valid}),
        'rvfi_valid',
      );
    });
  });
}
