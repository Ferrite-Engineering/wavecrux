// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';

void main() {
  group('DecodedTransaction', () {
    const tx = DecodedTransaction(
      startTime: 100,
      endTime: 500,
      label: 'Write 0xFF',
      fields: {'address': '0x50', 'rw': 'W', 'data': '0xFF'},
    );

    const txError = DecodedTransaction(
      startTime: 200,
      endTime: 300,
      label: 'NACK',
      isError: true,
      errorMessage: 'No acknowledgement received',
    );

    const txMinimal = DecodedTransaction(
      startTime: 0,
      endTime: 10,
      label: 'Read',
    );

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 500,
        label: 'Write 0xFF',
        fields: {'address': '0x50', 'rw': 'W', 'data': '0xFF'},
      );
      expect(tx, equals(other));
    });

    test('identical instances are equal', () {
      expect(tx, equals(tx));
    });

    test('equal with empty fields default', () {
      const other = DecodedTransaction(
        startTime: 0,
        endTime: 10,
        label: 'Read',
      );
      expect(txMinimal, equals(other));
    });

    test('not equal when startTime differs', () {
      const other = DecodedTransaction(
        startTime: 99,
        endTime: 500,
        label: 'Write 0xFF',
      );
      expect(tx, isNot(equals(other)));
    });

    test('not equal when endTime differs', () {
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 501,
        label: 'Write 0xFF',
      );
      expect(tx, isNot(equals(other)));
    });

    test('not equal when label differs', () {
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 500,
        label: 'Read 0xFF',
      );
      expect(tx, isNot(equals(other)));
    });

    test('not equal when isError differs', () {
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 500,
        label: 'Write 0xFF',
        fields: {'address': '0x50', 'rw': 'W', 'data': '0xFF'},
        isError: true,
      );
      expect(tx, isNot(equals(other)));
    });

    test('not equal when errorMessage differs', () {
      const other = DecodedTransaction(
        startTime: 200,
        endTime: 300,
        label: 'NACK',
        isError: true,
        errorMessage: 'Different error',
      );
      expect(txError, isNot(equals(other)));
    });

    test('not equal when fields differ in value', () {
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 500,
        label: 'Write 0xFF',
        fields: {'address': '0x51', 'rw': 'W', 'data': '0xFF'},
      );
      expect(tx, isNot(equals(other)));
    });

    test('not equal when fields have different keys', () {
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 500,
        label: 'Write 0xFF',
        fields: {'address': '0x50'},
      );
      expect(tx, isNot(equals(other)));
    });

    test('hashCode consistent with equality', () {
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 500,
        label: 'Write 0xFF',
        fields: {'address': '0x50', 'rw': 'W', 'data': '0xFF'},
      );
      expect(tx.hashCode, equals(other.hashCode));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith returns equal when no args', () {
      expect(tx.copyWith(), equals(tx));
    });

    test('copyWith updates startTime', () {
      expect(tx.copyWith(startTime: 50).startTime, 50);
    });

    test('copyWith updates endTime', () {
      expect(tx.copyWith(endTime: 600).endTime, 600);
    });

    test('copyWith updates label', () {
      expect(tx.copyWith(label: 'Read').label, 'Read');
    });

    test('copyWith updates fields', () {
      final updated = tx.copyWith(fields: {'x': 'y'});
      expect(updated.fields, {'x': 'y'});
    });

    test('copyWith updates isError', () {
      expect(tx.copyWith(isError: true).isError, isTrue);
    });

    test('copyWith updates errorMessage', () {
      expect(tx.copyWith(errorMessage: 'oops').errorMessage, 'oops');
    });

    test('clearErrorMessage sets errorMessage to null', () {
      expect(txError.copyWith(clearErrorMessage: true).errorMessage, isNull);
    });

    test('clearErrorMessage takes precedence over new errorMessage', () {
      expect(
        txError
            .copyWith(errorMessage: 'new', clearErrorMessage: true)
            .errorMessage,
        isNull,
      );
    });

    // ── defaults ──────────────────────────────────────────────────────────────

    test('default fields is empty map', () {
      expect(txMinimal.fields, isEmpty);
    });

    test('default isError is false', () {
      expect(txMinimal.isError, isFalse);
    });

    test('default errorMessage is null', () {
      expect(txMinimal.errorMessage, isNull);
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains start, end, label, and isError', () {
      final s = tx.toString();
      expect(s, contains('100'));
      expect(s, contains('500'));
      expect(s, contains('Write 0xFF'));
      expect(s, contains('false'));
    });
  });
}
