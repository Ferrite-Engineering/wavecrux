// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/policy/org_decoder_settings.dart';
import 'package:wavecrux/services/policy/org_object_policy_key.dart';

OrgDecoderSettings settings(Object? raw, {bool locked = false}) =>
    OrgDecoderSettings.fromPolicyEntry(
      raw == null ? null : OrgPolicyEntry(value: raw, locked: locked),
    );

void main() {
  group('parsing', () {
    test('an absent key configures nothing', () {
      expect(settings(null).isEmpty, isTrue);
    });

    test('values parse per decoder and per parameter', () {
      final org = settings(<String, Object?>{
        'spi': <String, Object?>{'cpol': 1, 'bitOrder': 'msb'},
        'uart': <String, Object?>{'baud': 115200},
      });
      expect(org.valueFor('spi', 'cpol'), 1);
      expect(org.valueFor('spi', 'bitOrder'), 'msb');
      expect(org.valueFor('uart', 'baud'), 115200);
      expect(org.valueFor('i2c', 'addressBits'), isNull);
    });

    test('one malformed decoder entry does not cost the others', () {
      final org = settings(<String, Object?>{
        'spi': 'not an object',
        'uart': <String, Object?>{'baud': 9600},
      });
      expect(
        org.valueFor('uart', 'baud'),
        9600,
        reason:
            'a typo in one entry must not cost an administrator the other '
            'nine',
      );
      expect(org.valueFor('spi', 'cpol'), isNull);
    });

    test('an empty decoder object is dropped rather than counted', () {
      expect(
        settings(<String, Object?>{'spi': <String, Object?>{}}).isEmpty,
        isTrue,
      );
    });
  });

  group('precedence — locked > user setting > policy default > built-in', () {
    const decoder = 'spi';
    const param = 'cpol';

    test('with no organization value, the built-in wins', () {
      expect(
        settings(null).resolve(decoder, param, userValue: null, builtIn: 0),
        0,
      );
    });

    test('an UNLOCKED organization value replaces the built-in', () {
      final org = settings(<String, Object?>{
        decoder: <String, Object?>{param: 1},
      });
      expect(
        org.resolve(decoder, param, userValue: null, builtIn: 0),
        1,
        reason: 'so a fresh decoder starts right rather than starting wrong',
      );
    });

    test('an UNLOCKED organization value yields to what the user set', () {
      final org = settings(<String, Object?>{
        decoder: <String, Object?>{param: 1},
      });
      expect(
        org.resolve(decoder, param, userValue: 0, builtIn: 0),
        0,
        reason:
            'a policy DEFAULT the user cannot depart from is a lock whose '
            'control forgot to grey itself — the incoherence locking corrects',
      );
    });

    test('a LOCKED organization value wins over the user’s own', () {
      final org = settings(
        <String, Object?>{
          decoder: <String, Object?>{param: 1},
        },
        locked: true,
      );
      expect(
        org.resolve(decoder, param, userValue: 0, builtIn: 0),
        1,
        reason:
            'a lock that yielded to a saved session would be a lock in name '
            'only',
      );
      expect(org.isLocked(decoder, param), isTrue);
    });

    test('locking the key does not lock parameters it never mentions', () {
      final org = settings(
        <String, Object?>{
          decoder: <String, Object?>{param: 1},
        },
        locked: true,
      );
      expect(
        org.isLocked(decoder, 'bitOrder'),
        isFalse,
        reason:
            'locking decoderSettings fixes the values written in it, not '
            'every parameter of every decoder',
      );
      expect(
        org.resolve(decoder, 'bitOrder', userValue: 'lsb', builtIn: 'msb'),
        'lsb',
      );
    });
  });

  group('the wrapper ambiguity', () {
    test('the bare object form works — the natural spelling', () {
      final entry = readOrgPolicyEntry(
        <String, Map<String, Object?>>{
          'wavecrux': <String, Object?>{
            'decoderSettings': <String, Object?>{
              'spi': <String, Object?>{'cpol': 1},
            },
          },
        },
        productId: 'wavecrux',
        key: 'decoderSettings',
      );
      final org = OrgDecoderSettings.fromPolicyEntry(entry);
      expect(org.valueFor('spi', 'cpol'), 1);
      expect(org.locked, isFalse);
    });

    test('the wrapper form works, and its lock is honoured', () {
      final entry = readOrgPolicyEntry(
        <String, Map<String, Object?>>{
          'wavecrux': <String, Object?>{
            'decoderSettings': <String, Object?>{
              'value': <String, Object?>{
                'spi': <String, Object?>{'cpol': 1},
              },
              'locked': true,
            },
          },
        },
        productId: 'wavecrux',
        key: 'decoderSettings',
      );
      final org = OrgDecoderSettings.fromPolicyEntry(entry);
      expect(org.valueFor('spi', 'cpol'), 1);
      expect(org.locked, isTrue);
    });

    test('a scalar under an object-valued key is refused, not coerced', () {
      expect(
        readOrgPolicyEntry(
          <String, Map<String, Object?>>{
            'wavecrux': <String, Object?>{'decoderSettings': 42},
          },
          productId: 'wavecrux',
          key: 'decoderSettings',
        ),
        isNull,
      );
    });

    test('a non-boolean lock flag degrades to unlocked, keeping the value', () {
      final entry = readOrgPolicyEntry(
        <String, Map<String, Object?>>{
          'wavecrux': <String, Object?>{
            'decoderSettings': <String, Object?>{
              'value': <String, Object?>{
                'spi': <String, Object?>{'cpol': 1},
              },
              'locked': 'yes',
            },
          },
        },
        productId: 'wavecrux',
        key: 'decoderSettings',
      );
      expect(entry, isNotNull);
      expect(
        entry!.locked,
        isFalse,
        reason: 'a typo in the lock flag must not take the value with it',
      );
    });
  });
}
