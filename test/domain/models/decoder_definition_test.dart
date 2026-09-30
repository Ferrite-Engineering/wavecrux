// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';

void main() {
  group('DecoderDefinition', () {
    const sclk = SignalBinding(name: 'sclk', description: 'Clock', bitWidth: 1);
    const mosi = SignalBinding(
      name: 'mosi',
      description: 'Master Out',
      bitWidth: 1,
    );
    const miso = SignalBinding(
      name: 'miso',
      description: 'Master In',
      bitWidth: 1,
    );
    const cpolParam = DecoderParameter(
      name: 'cpol',
      type: DecoderParameterType.boolean,
      defaultValue: false,
      description: 'Clock polarity',
    );

    const def = DecoderDefinition(
      id: 'spi',
      displayName: 'SPI',
      description: 'Serial Peripheral Interface decoder',
      requiredSignals: [sclk, mosi],
      optionalSignals: [miso],
      parameters: [cpolParam],
    );

    const defMinimal = DecoderDefinition(
      id: 'uart',
      displayName: 'UART',
      description: 'Universal Asynchronous Receiver-Transmitter',
      requiredSignals: [mosi],
    );

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when all fields match', () {
      const other = DecoderDefinition(
        id: 'spi',
        displayName: 'SPI',
        description: 'Serial Peripheral Interface decoder',
        requiredSignals: [sclk, mosi],
        optionalSignals: [miso],
        parameters: [cpolParam],
      );
      expect(def, equals(other));
    });

    test('equal with default empty optionalSignals and parameters', () {
      const other = DecoderDefinition(
        id: 'uart',
        displayName: 'UART',
        description: 'Universal Asynchronous Receiver-Transmitter',
        requiredSignals: [mosi],
      );
      expect(defMinimal, equals(other));
    });

    test('not equal when id differs', () {
      const other = DecoderDefinition(
        id: 'i2c',
        displayName: 'SPI',
        description: 'Serial Peripheral Interface decoder',
        requiredSignals: [sclk, mosi],
      );
      expect(def, isNot(equals(other)));
    });

    test('not equal when displayName differs', () {
      const other = DecoderDefinition(
        id: 'spi',
        displayName: 'SPI v2',
        description: 'Serial Peripheral Interface decoder',
        requiredSignals: [sclk, mosi],
      );
      expect(def, isNot(equals(other)));
    });

    test('not equal when requiredSignals differ', () {
      const other = DecoderDefinition(
        id: 'spi',
        displayName: 'SPI',
        description: 'Serial Peripheral Interface decoder',
        requiredSignals: [sclk],
      );
      expect(def, isNot(equals(other)));
    });

    test('not equal when optionalSignals differ', () {
      const other = DecoderDefinition(
        id: 'spi',
        displayName: 'SPI',
        description: 'Serial Peripheral Interface decoder',
        requiredSignals: [sclk, mosi],
      );
      expect(def, isNot(equals(other)));
    });

    test('not equal when parameters differ', () {
      const other = DecoderDefinition(
        id: 'spi',
        displayName: 'SPI',
        description: 'Serial Peripheral Interface decoder',
        requiredSignals: [sclk, mosi],
        optionalSignals: [miso],
      );
      expect(def, isNot(equals(other)));
    });

    test('hashCode consistent with equality', () {
      const other = DecoderDefinition(
        id: 'spi',
        displayName: 'SPI',
        description: 'Serial Peripheral Interface decoder',
        requiredSignals: [sclk, mosi],
        optionalSignals: [miso],
        parameters: [cpolParam],
      );
      expect(def.hashCode, equals(other.hashCode));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith returns equal when no args', () {
      expect(def.copyWith(), equals(def));
    });

    test('copyWith updates id', () {
      expect(def.copyWith(id: 'spi2').id, 'spi2');
    });

    test('copyWith updates displayName', () {
      expect(def.copyWith(displayName: 'SPI v2').displayName, 'SPI v2');
    });

    test('copyWith updates requiredSignals', () {
      final updated = def.copyWith(requiredSignals: [sclk]);
      expect(updated.requiredSignals, [sclk]);
    });

    test('copyWith updates optionalSignals', () {
      final updated = def.copyWith(optionalSignals: []);
      expect(updated.optionalSignals, isEmpty);
    });

    test('copyWith updates parameters', () {
      final updated = def.copyWith(parameters: []);
      expect(updated.parameters, isEmpty);
    });

    // ── requiredTier ──────────────────────────────────────────────────────────

    test('requiredTier defaults to openCore when omitted', () {
      expect(def.requiredTier, LicenseTier.openCore);
      expect(defMinimal.requiredTier, LicenseTier.openCore);
    });

    test('requiredTier captured when supplied', () {
      const proDef = DecoderDefinition(
        id: 'usb',
        displayName: 'USB 2.0',
        description: 'Pro decoder',
        requiredSignals: [mosi],
        requiredTier: LicenseTier.pro,
      );
      expect(proDef.requiredTier, LicenseTier.pro);
    });

    test('not equal when requiredTier differs', () {
      final pro = def.copyWith(requiredTier: LicenseTier.pro);
      expect(pro, isNot(equals(def)));
    });

    test('hashCode differs when requiredTier differs', () {
      final pro = def.copyWith(requiredTier: LicenseTier.pro);
      expect(pro.hashCode, isNot(equals(def.hashCode)));
    });

    test('copyWith updates requiredTier', () {
      final pro = def.copyWith(requiredTier: LicenseTier.enterprise);
      expect(pro.requiredTier, LicenseTier.enterprise);
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains id and displayName', () {
      final s = def.toString();
      expect(s, contains('spi'));
      expect(s, contains('SPI'));
    });

    // ── category ──────────────────────────────────────────────────────────────

    test('category defaults to custom when omitted', () {
      expect(def.category, DecoderCategory.custom);
      expect(defMinimal.category, DecoderCategory.custom);
    });

    test('category captured when supplied', () {
      const ambaDef = DecoderDefinition(
        id: 'apb',
        displayName: 'APB',
        description: 'AMBA APB decoder',
        requiredSignals: [mosi],
        category: DecoderCategory.amba,
      );
      expect(ambaDef.category, DecoderCategory.amba);
    });

    test('not equal when category differs', () {
      final amba = def.copyWith(category: DecoderCategory.amba);
      expect(amba, isNot(equals(def)));
    });

    test('hashCode differs when category differs', () {
      final amba = def.copyWith(category: DecoderCategory.amba);
      expect(amba.hashCode, isNot(equals(def.hashCode)));
    });

    test('copyWith updates category', () {
      final ethernet = def.copyWith(category: DecoderCategory.ethernet);
      expect(ethernet.category, DecoderCategory.ethernet);
    });
  });
}
