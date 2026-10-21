// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';

/// The link parser is the first thing a link from anywhere (a chat, a CI log,
/// a web page) reaches. These hold it to its grammar: one action, three known
/// keys, each once, bounded, percent-decoded with `+` left alone, and no
/// character that could disguise a file name. The fuzz group feeds it mutated
/// and random input and asserts only what must hold for every input: it never
/// throws, and whatever it accepts satisfies the invariants a caller relies
/// on.

WaveCruxLink _ok(String raw) {
  final result = parseWaveCruxLink(raw);
  return switch (result) {
    WaveCruxLinkParsed(:final link) => link,
    WaveCruxLinkRejected(:final refusal) => fail(
      'expected $raw to parse, got $refusal',
    ),
  };
}

WaveCruxLinkRefusal _refused(String raw) {
  final result = parseWaveCruxLink(raw);
  return switch (result) {
    WaveCruxLinkRejected(:final refusal) => refusal,
    WaveCruxLinkParsed(:final link) => fail(
      'expected $raw to be refused, got file=${link.file}',
    ),
  };
}

void main() {
  group('accepted links', () {
    test('file only', () {
      final link = _ok('wavecrux://open?file=/home/me/sim/dump.vcd');
      expect(link.file, '/home/me/sim/dump.vcd');
      expect(link.signal, isNull);
      expect(link.time, isNull);
    });

    test('all three keys, in any order', () {
      final link = _ok(
        'wavecrux://open?t=1.5us&signal=tb.dut.tx_busy&file=/w/a.fst',
      );
      expect(link.file, '/w/a.fst');
      expect(link.signal, 'tb.dut.tx_busy');
      expect(link.time, WaveCruxLinkTime.seconds(BigInt.from(15), -7));
    });

    test('percent-escapes decode; + stays a plus', () {
      final link = _ok(
        'wavecrux://open?file=/work/c++/my%20sim/d%C3%A9j%C3%A0.vcd',
      );
      expect(link.file, '/work/c++/my sim/déjà.vcd');
    });

    test('scheme and action ignore case; one trailing slash is allowed', () {
      expect(_ok('WaveCrux://OPEN?file=/a.vcd').file, '/a.vcd');
      expect(_ok('wavecrux://open/?file=/a.vcd').file, '/a.vcd');
    });

    test('a Windows path survives, encoded or not', () {
      expect(_ok(r'wavecrux://open?file=C:\work\a.vcd').file, r'C:\work\a.vcd');
      expect(
        _ok('wavecrux://open?file=C%3A%5Cwork%5Ca.vcd').file,
        r'C:\work\a.vcd',
      );
      expect(_ok('wavecrux://open?file=C:/work/a.vcd').file, 'C:/work/a.vcd');
    });

    test('a signal with a bit range is kept whole', () {
      expect(
        _ok('wavecrux://open?file=/a.vcd&signal=top.data%5B7%3A0%5D').signal,
        'top.data[7:0]',
      );
    });
  });

  group('refused links', () {
    test('another scheme is not a WaveCrux link', () {
      expect(
        _refused('https://open?file=/a.vcd'),
        WaveCruxLinkRefusal.notAWaveCruxLink,
      );
      expect(
        _refused('wavecruxx://open?file=/a.vcd'),
        WaveCruxLinkRefusal.notAWaveCruxLink,
      );
      expect(_refused(''), WaveCruxLinkRefusal.notAWaveCruxLink);
    });

    test('anything but //open is malformed', () {
      for (final raw in [
        'wavecrux:open?file=/a.vcd',
        'wavecrux:/open?file=/a.vcd',
        'wavecrux://close?file=/a.vcd',
        'wavecrux://run?file=/a.vcd',
        'wavecrux://user@open?file=/a.vcd',
        'wavecrux://open:80?file=/a.vcd',
        'wavecrux://open/x?file=/a.vcd',
        'wavecrux://open//?file=/a.vcd',
        'wavecrux://open?file=/a.vcd#frag',
        'wavecrux://open?file=/a.vcd&',
        'wavecrux://open?&file=/a.vcd',
        'wavecrux://open?file',
        'wavecrux://open?=x&file=/a.vcd',
      ]) {
        expect(_refused(raw), WaveCruxLinkRefusal.malformed, reason: raw);
      }
    });

    test('no query, an empty query or no file is a missing value', () {
      expect(_refused('wavecrux://open'), WaveCruxLinkRefusal.missingValue);
      expect(_refused('wavecrux://open?'), WaveCruxLinkRefusal.missingValue);
      expect(
        _refused('wavecrux://open?signal=top.clk'),
        WaveCruxLinkRefusal.missingValue,
      );
      expect(
        _refused('wavecrux://open?file='),
        WaveCruxLinkRefusal.missingValue,
      );
      expect(
        _refused('wavecrux://open?file=/a.vcd&signal='),
        WaveCruxLinkRefusal.missingValue,
      );
    });

    test('unknown keys are refused, not ignored', () {
      for (final key in ['File', 'path', 'url', 'cmd', 'exec', 'session']) {
        expect(
          _refused('wavecrux://open?file=/a.vcd&$key=x'),
          WaveCruxLinkRefusal.unknownKey,
          reason: key,
        );
      }
    });

    test('one file per link: a repeated key is refused', () {
      expect(
        _refused('wavecrux://open?file=/a.vcd&file=/b.vcd'),
        WaveCruxLinkRefusal.duplicateKey,
      );
      expect(
        _refused('wavecrux://open?file=/a.vcd&t=1ns&t=2ns'),
        WaveCruxLinkRefusal.duplicateKey,
      );
    });

    test('broken escapes and invalid UTF-8 are refused', () {
      expect(
        _refused('wavecrux://open?file=/a%ZZ.vcd'),
        WaveCruxLinkRefusal.badEncoding,
      );
      expect(
        _refused('wavecrux://open?file=/a%.vcd'),
        WaveCruxLinkRefusal.badEncoding,
      );
      expect(
        _refused('wavecrux://open?file=/a%C3.vcd'),
        WaveCruxLinkRefusal.badEncoding,
      );
      expect(
        _refused('wavecrux://open?file=/a%EF%BF%BD.vcd'),
        WaveCruxLinkRefusal.badEncoding,
      );
    });

    test('controls, raw white space and bidi controls are refused', () {
      for (final raw in [
        'wavecrux://open?file=/a.vcd ',
        'wavecrux://open?file=/a b.vcd',
        'wavecrux://open?file=/a.vcd\n',
        'wavecrux://open?file=/a%00.vcd',
        'wavecrux://open?file=/a%0A.vcd',
        'wavecrux://open?file=/a%7F.vcd',
        'wavecrux://open?file=/evil%E2%80%AEdcv.vcd',
        'wavecrux://open?file=/x%E2%81%A6.vcd',
        'wavecrux://open?file=/a.vcd&signal=top.%20clk',
        'wavecrux://open?file=/a%C2%A0b.vcd',
      ]) {
        expect(
          _refused(raw),
          WaveCruxLinkRefusal.forbiddenCharacter,
          reason: raw,
        );
      }
    });

    test('lengths are bounded', () {
      final longLink = 'wavecrux://open?file=/${'a' * kWaveCruxLinkMaxLength}';
      expect(_refused(longLink), WaveCruxLinkRefusal.tooLong);
      final longFile =
          'wavecrux://open?file=/${'a' * kWaveCruxLinkMaxFileLength}.vcd';
      expect(_refused(longFile), WaveCruxLinkRefusal.tooLong);
      final longSignal =
          'wavecrux://open?file=/a.vcd&signal=${'s' * (kWaveCruxLinkMaxSignalLength + 1)}';
      expect(_refused(longSignal), WaveCruxLinkRefusal.tooLong);
    });

    test('a bad time is refused', () {
      for (final t in [
        '-5ns',
        '1.5',
        '5 ns',
        '5NS',
        '5min',
        'ns',
        '1e9ns',
        '0x10',
        '.5ns',
        '5.ns',
        '1' * 25,
      ]) {
        expect(
          _refused('wavecrux://open?file=/a.vcd&t=${Uri.encodeComponent(t)}'),
          anyOf(
            WaveCruxLinkRefusal.badTime,
            WaveCruxLinkRefusal.forbiddenCharacter,
          ),
          reason: t,
        );
      }
    });
  });

  group('time', () {
    test('units and fractions parse exactly', () {
      expect(
        parseWaveCruxLinkTime('1500ns'),
        WaveCruxLinkTime.seconds(BigInt.from(1500), -9),
      );
      expect(
        parseWaveCruxLinkTime('1.5us'),
        WaveCruxLinkTime.seconds(BigInt.from(15), -7),
      );
      expect(
        parseWaveCruxLinkTime('2µs'),
        WaveCruxLinkTime.seconds(BigInt.two, -6),
      );
      expect(
        parseWaveCruxLinkTime('2μs'),
        WaveCruxLinkTime.seconds(BigInt.two, -6),
      );
      expect(
        parseWaveCruxLinkTime('3s'),
        WaveCruxLinkTime.seconds(BigInt.from(3), 0),
      );
      expect(
        parseWaveCruxLinkTime('42'),
        WaveCruxLinkTime.ticks(BigInt.from(42)),
      );
    });

    test('converts to ticks of the file timescale, rounding to nearest', () {
      const ns1 = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
      const ps10 = Timescale(factor: 10, unit: TimescaleUnit.picoSeconds);
      BigInt? ticks(String t, Timescale? ts) =>
          parseWaveCruxLinkTime(t)!.toTicks(ts);
      expect(ticks('1.5us', ns1), BigInt.from(1500));
      expect(ticks('20ns', ns1), BigInt.from(20));
      expect(ticks('1500ps', ns1), BigInt.from(2)); // 1.5 rounds up
      expect(ticks('1499ps', ns1), BigInt.one);
      expect(ticks('20ns', ps10), BigInt.from(2000));
      expect(ticks('5ps', ps10), BigInt.one); // 0.5 rounds up
      expect(ticks('1s', ns1), BigInt.from(1000000000));
      expect(ticks('42', ns1), BigInt.from(42));
      expect(ticks('42', null), BigInt.from(42), reason: 'ticks need no scale');
    });

    test('a time with a unit cannot be placed without a known timescale', () {
      const unknown = Timescale(factor: 1, unit: TimescaleUnit.unknown);
      expect(parseWaveCruxLinkTime('5ns')!.toTicks(null), isNull);
      expect(parseWaveCruxLinkTime('5ns')!.toTicks(unknown), isNull);
      expect(
        parseWaveCruxLinkTime('5ns')!.toTicks(
          const Timescale(factor: 0, unit: TimescaleUnit.nanoSeconds),
        ),
        isNull,
      );
    });
  });

  group('launch arguments', () {
    test('an ordinary command line passes through untouched', () {
      final split = WaveCruxLaunchArgs.split(const ['--reset', 'a.vcd']);
      expect(split.args, ['--reset', 'a.vcd']);
      expect(split.links, isEmpty);
    });

    test('a link drops every other argument, whatever its position', () {
      // The Windows quoting break-out: "%1" closed early by a quote in the
      // link, so the rest arrives as extra arguments.
      final split = WaveCruxLaunchArgs.split(const [
        'wavecrux://open?file=C:/a.vcd',
        '--reset',
        '--reset-eula',
        r'C:\other.vcd',
      ]);
      expect(split.args, isEmpty);
      expect(split.links, ['wavecrux://open?file=C:/a.vcd']);
      final before = WaveCruxLaunchArgs.split(const [
        '--no-restore',
        'WAVECRUX://open?file=/a.vcd',
      ]);
      expect(before.args, isEmpty);
      expect(before.links, ['WAVECRUX://open?file=/a.vcd']);
    });

    test('two links are both kept so the launch can refuse them', () {
      final split = WaveCruxLaunchArgs.split(const [
        'wavecrux://open?file=/a.vcd',
        'wavecrux://open?file=/b.vcd',
      ]);
      expect(split.args, isEmpty);
      expect(split.links, hasLength(2));
    });
  });

  group('fuzz', () {
    const seed = 0x5EED1;
    const valid =
        'wavecrux://open?file=/home/me/sim/dump.vcd'
        '&signal=tb.dut.tx_busy&t=1.5us';
    const letters =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const punctuation = r'%&=?#/:\.+-_ ~@!$*()[];,';
    const awkward =
        '\u0000\u0009\u000A\u007F\u00A0\u00E9\u202E\u2066\uFEFF\u{1F600}';
    const alphabet = '$letters$punctuation$awkward';

    void checkInvariants(String raw) {
      final WaveCruxLinkParseResult result;
      try {
        result = parseWaveCruxLink(raw);
      } on Object catch (e) {
        fail('parseWaveCruxLink threw $e on ${Uri.encodeFull(raw)}');
      }
      if (result case WaveCruxLinkParsed(:final link)) {
        expect(raw.length, lessThanOrEqualTo(kWaveCruxLinkMaxLength));
        expect(looksLikeWaveCruxLink(raw), isTrue);
        expect(link.file, isNotEmpty);
        expect(link.file.length, lessThanOrEqualTo(kWaveCruxLinkMaxFileLength));
        expect(link.file.contains('\u0000'), isFalse);
        expect(
          RegExp(
            r'[\u0000-\u001F\u007F\u202A-\u202E\u2066-\u2069]',
          ).hasMatch(link.file),
          isFalse,
        );
        final signal = link.signal;
        if (signal != null) {
          expect(signal, isNotEmpty);
          expect(signal.contains(' '), isFalse);
          expect(
            signal.length,
            lessThanOrEqualTo(kWaveCruxLinkMaxSignalLength),
          );
        }
        final time = link.time;
        if (time != null) {
          expect(time.mantissa.isNegative, isFalse);
        }
      }
    }

    test('mutations of a valid link never throw and keep the invariants', () {
      final random = Random(seed);
      for (var i = 0; i < 5000; i++) {
        final chars = valid.split('');
        final edits = 1 + random.nextInt(6);
        for (var e = 0; e < edits; e++) {
          final op = random.nextInt(3);
          final at = random.nextInt(chars.length + 1);
          final ch = alphabet[random.nextInt(alphabet.length)];
          if (op == 0 && at < chars.length) {
            chars[at] = ch;
          } else if (op == 1) {
            chars.insert(at, ch);
          } else if (at < chars.length) {
            chars.removeAt(at);
          }
        }
        checkInvariants(chars.join());
      }
    });

    test('random query strings never throw', () {
      final random = Random(seed + 1);
      for (var i = 0; i < 5000; i++) {
        final length = random.nextInt(80);
        final query = List.generate(
          length,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
        checkInvariants('wavecrux://open?$query');
        checkInvariants('wavecrux://open?file=$query');
      }
    });

    test('random percent-escapes never throw', () {
      final random = Random(seed + 2);
      const hex = '0123456789ABCDEFabcdefXZ';
      for (var i = 0; i < 3000; i++) {
        final buffer = StringBuffer('wavecrux://open?file=/');
        for (var j = random.nextInt(12); j >= 0; j--) {
          buffer
            ..write('%')
            ..write(hex[random.nextInt(hex.length)])
            ..write(hex[random.nextInt(hex.length)]);
        }
        buffer.write('.vcd');
        checkInvariants(buffer.toString());
      }
    });
  });
}
