// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/timescale.dart';

/// The URL scheme WaveCrux registers with the operating system.
///
/// A link is `wavecrux://open?file=<path>&signal=<name>&t=<time>`. It can
/// arrive from anywhere: a chat message, a CI log, a web page, a review
/// comment. Everything in this file treats it as hostile input, and nothing
/// here touches the filesystem. Whether the file it names may be opened is
/// decided afterwards by `vetWaveCruxLinkTarget`, and whether the user agrees
/// by the handler.
const String kWaveCruxLinkScheme = 'wavecrux';

/// The longest link accepted, in UTF-16 code units, before any decoding.
const int kWaveCruxLinkMaxLength = 8192;

/// The longest decoded `file` value accepted.
const int kWaveCruxLinkMaxFileLength = 4096;

/// The longest decoded `signal` value accepted.
const int kWaveCruxLinkMaxSignalLength = 1024;

/// The longest decoded `t` value accepted.
const int kWaveCruxLinkMaxTimeLength = 48;

/// Why a link was refused before anything was opened.
///
/// Every value is reported to the user the same way ("not a valid WaveCrux
/// link"): the distinctions are for tests and diagnostics, not for the sender.
enum WaveCruxLinkRefusal {
  /// Longer than [kWaveCruxLinkMaxLength], or a value longer than its bound.
  tooLong,

  /// The scheme is not `wavecrux`.
  notAWaveCruxLink,

  /// Not of the form `wavecrux://open?…`: another action, a user name, a
  /// port, a path, a fragment, or no query at all.
  malformed,

  /// A query key this build does not know. Unknown keys are refused rather
  /// than ignored, so a link written for a later build fails visibly instead
  /// of half-working.
  unknownKey,

  /// The same key twice. One link names one file.
  duplicateKey,

  /// No `file`, or an empty value for any key.
  missingValue,

  /// A broken percent-escape, or bytes that are not UTF-8.
  badEncoding,

  /// White space, a control character or a bidirectional-text control in the
  /// link or in a decoded value.
  forbiddenCharacter,

  /// A `t` value that is not a non-negative number with a known unit, or a
  /// unit-less value that is not a whole number of ticks.
  badTime,

  /// More than one link on the command line. Only one is honoured per launch.
  tooManyLinks,
}

/// A time in a link, kept exact: [mantissa] × 10^[exponent] seconds, or
/// [mantissa] ticks of the file's own timescale when [isTicks] is true.
@immutable
class WaveCruxLinkTime {
  /// A time in seconds: [mantissa] × 10^[exponent].
  const WaveCruxLinkTime.seconds(this.mantissa, this.exponent)
    : isTicks = false;

  /// A raw tick count in the file's timescale.
  const WaveCruxLinkTime.ticks(this.mantissa) : exponent = 0, isTicks = true;

  /// The digits of the value, with any decimal point removed.
  final BigInt mantissa;

  /// The power of ten [mantissa] is scaled by, in seconds. Zero for ticks.
  final int exponent;

  /// Whether the link gave a bare tick count rather than a time with a unit.
  final bool isTicks;

  /// This time as a tick count in [timescale], rounded to the nearest tick,
  /// or null when it cannot be converted: a time with a unit in a file whose
  /// timescale is absent or unknown.
  ///
  /// Not clamped to the file's range; the caller does that, so it can say so.
  /// Saturates at the largest tick a 64-bit time can hold.
  BigInt? toTicks(Timescale? timescale) {
    if (isTicks) return mantissa;
    final unitExponent = timescale?.unit.exponent;
    final factor = timescale?.factor ?? 0;
    if (unitExponent == null || factor <= 0) return null;
    final shift = exponent - unitExponent;
    var numerator = mantissa;
    var denominator = BigInt.from(factor);
    if (shift >= 0) {
      numerator *= BigInt.from(10).pow(shift);
    } else {
      denominator *= BigInt.from(10).pow(-shift);
    }
    // Round half up: (2n + d) / 2d.
    return (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  }

  @override
  bool operator ==(Object other) =>
      other is WaveCruxLinkTime &&
      other.mantissa == mantissa &&
      other.exponent == exponent &&
      other.isTicks == isTicks;

  @override
  int get hashCode => Object.hash(mantissa, exponent, isTicks);

  @override
  String toString() => isTicks
      ? 'WaveCruxLinkTime.ticks($mantissa)'
      : 'WaveCruxLinkTime.seconds(${mantissa}e$exponent)';
}

/// A link that parsed: the file it names, and optionally a signal and a time.
@immutable
class WaveCruxLink {
  /// Creates a parsed link.
  const WaveCruxLink({required this.file, this.signal, this.time});

  /// The local path, exactly as decoded from the link. Not yet checked
  /// against the filesystem.
  final String file;

  /// The hierarchical signal name to add or select, if any.
  final String? signal;

  /// Where to put the primary cursor, if anywhere.
  final WaveCruxLinkTime? time;
}

/// The result of [parseWaveCruxLink].
sealed class WaveCruxLinkParseResult {
  const WaveCruxLinkParseResult();
}

/// The link parsed.
final class WaveCruxLinkParsed extends WaveCruxLinkParseResult {
  /// Wraps the parsed [link].
  const WaveCruxLinkParsed(this.link);

  /// The parsed link.
  final WaveCruxLink link;
}

/// The link was refused.
final class WaveCruxLinkRejected extends WaveCruxLinkParseResult {
  /// Wraps the [refusal].
  const WaveCruxLinkRejected(this.refusal);

  /// Why it was refused.
  final WaveCruxLinkRefusal refusal;
}

const String _keyFile = 'file';
const String _keySignal = 'signal';
const String _keyTime = 't';
const Set<String> _knownKeys = {_keyFile, _keySignal, _keyTime};

/// Whether [raw] is spelled as a WaveCrux link: it begins with the scheme and
/// a colon, in any case. Says nothing about whether it is a valid one.
bool looksLikeWaveCruxLink(String raw) =>
    raw.length > kWaveCruxLinkScheme.length &&
    raw.substring(0, kWaveCruxLinkScheme.length + 1).toLowerCase() ==
        '$kWaveCruxLinkScheme:';

/// Parses [raw] strictly. Never throws, never touches the filesystem.
///
/// Accepted: `wavecrux://open?file=…` with an optional `signal` and `t`, in
/// any order, each at most once, each percent-encoded. The authority is
/// exactly `open` (any case), optionally followed by a single `/`. Nothing
/// else is accepted: no user name, port, other path, fragment or other key.
///
/// `+` is a literal plus, not a space: a path such as `/work/c++/dump.vcd`
/// must survive, and a space is written `%20`.
WaveCruxLinkParseResult parseWaveCruxLink(String raw) {
  if (raw.length > kWaveCruxLinkMaxLength) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.tooLong);
  }
  if (!looksLikeWaveCruxLink(raw)) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.notAWaveCruxLink);
  }
  if (_hasForbiddenCharacter(raw)) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.forbiddenCharacter);
  }
  if (raw.contains('#')) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.malformed);
  }
  final rest = raw.substring(kWaveCruxLinkScheme.length + 1);
  if (!rest.startsWith('//')) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.malformed);
  }
  final afterSlashes = rest.substring(2);
  final queryAt = afterSlashes.indexOf('?');
  final head = queryAt == -1
      ? afterSlashes
      : afterSlashes.substring(0, queryAt);
  if (head.toLowerCase() != 'open' && head.toLowerCase() != 'open/') {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.malformed);
  }
  if (queryAt == -1) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.missingValue);
  }
  final query = afterSlashes.substring(queryAt + 1);
  if (query.isEmpty) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.missingValue);
  }

  final values = <String, String>{};
  for (final pair in query.split('&')) {
    final eq = pair.indexOf('=');
    if (eq <= 0) {
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.malformed);
    }
    final key = pair.substring(0, eq);
    if (!_knownKeys.contains(key)) {
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.unknownKey);
    }
    if (values.containsKey(key)) {
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.duplicateKey);
    }
    final String decoded;
    try {
      decoded = Uri.decodeComponent(pair.substring(eq + 1));
    } on Object {
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.badEncoding);
    }
    if (decoded.isEmpty) {
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.missingValue);
    }
    if (decoded.contains('�')) {
      // A malformed UTF-8 sequence decodes to the replacement character,
      // which would name a different file than the sender's bytes did.
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.badEncoding);
    }
    final limit = switch (key) {
      _keyFile => kWaveCruxLinkMaxFileLength,
      _keySignal => kWaveCruxLinkMaxSignalLength,
      _ => kWaveCruxLinkMaxTimeLength,
    };
    if (decoded.length > limit) {
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.tooLong);
    }
    if (_hasForbiddenCharacter(decoded, allowSpace: key == _keyFile)) {
      return const WaveCruxLinkRejected(
        WaveCruxLinkRefusal.forbiddenCharacter,
      );
    }
    values[key] = decoded;
  }

  final file = values[_keyFile];
  if (file == null) {
    return const WaveCruxLinkRejected(WaveCruxLinkRefusal.missingValue);
  }
  WaveCruxLinkTime? time;
  final rawTime = values[_keyTime];
  if (rawTime != null) {
    time = parseWaveCruxLinkTime(rawTime);
    if (time == null) {
      return const WaveCruxLinkRejected(WaveCruxLinkRefusal.badTime);
    }
  }
  return WaveCruxLinkParsed(
    WaveCruxLink(file: file, signal: values[_keySignal], time: time),
  );
}

/// The `t` grammar: digits, an optional fraction, an optional unit.
final RegExp _timePattern = RegExp(
  r'^([0-9]{1,24})(?:\.([0-9]{1,24}))?(fs|ps|ns|us|µs|μs|ms|s)?$',
);

/// Parses a link's `t` value, or returns null when it is not one.
///
/// `1500ns`, `1.5us` and `2s` are times; `µs` and `μs` are accepted beside
/// `us`. A value with no unit is a whole number of ticks in the file's own
/// timescale (`t=42`); a fraction with no unit is refused, because a fraction
/// of a tick names no instant. Negative values are refused.
WaveCruxLinkTime? parseWaveCruxLinkTime(String value) {
  if (value.length > kWaveCruxLinkMaxTimeLength) return null;
  final match = _timePattern.firstMatch(value);
  if (match == null) return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  final unit = match.group(3);
  if (unit == null) {
    if (fraction.isNotEmpty) return null;
    return WaveCruxLinkTime.ticks(BigInt.parse(whole));
  }
  final unitExponent = switch (unit) {
    'fs' => -15,
    'ps' => -12,
    'ns' => -9,
    'us' || 'µs' || 'μs' => -6,
    'ms' => -3,
    _ => 0,
  };
  return WaveCruxLinkTime.seconds(
    BigInt.parse('$whole$fraction'),
    unitExponent - fraction.length,
  );
}

/// Whether [value] holds a character no link or link value may carry: a C0 or
/// C1 control, DEL, a bidirectional-text control (which can make a file name
/// read differently from the file it is), a line or paragraph separator, or
/// white space (allowed only as a plain U+0020 inside a decoded path when
/// [allowSpace]).
bool _hasForbiddenCharacter(String value, {bool allowSpace = false}) {
  for (final unit in value.runes) {
    if (unit == 0x20) {
      if (allowSpace) continue;
      return true;
    }
    if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F)) return true;
    if (unit == 0x200E || unit == 0x200F) return true;
    if (unit >= 0x202A && unit <= 0x202E) return true;
    if (unit >= 0x2066 && unit <= 0x2069) return true;
    if (unit == 0x061C || unit == 0x2028 || unit == 0x2029) return true;
    if (unit == 0x00A0 || unit == 0x1680 || unit == 0x3000) return true;
    if (unit >= 0x2000 && unit <= 0x200B) return true;
    if (unit == 0x202F || unit == 0x205F || unit == 0xFEFF) return true;
  }
  return false;
}

/// The command line a launch received, with any WaveCrux link taken out.
///
/// On Windows and Linux the operating system opens a link by starting the
/// application with the link as an argument. A link that carries a quote can
/// break out of the registered command's quoting on Windows and smuggle
/// further arguments in after it (`--reset` among them), so when any argument
/// is a link **every other argument is dropped**: a launch is either a link or
/// an ordinary command line, never both.
@immutable
class WaveCruxLaunchArgs {
  const WaveCruxLaunchArgs._(this.args, this.links);

  /// Splits [argv]. An argument is a link when it begins with `wavecrux:` in
  /// any case.
  factory WaveCruxLaunchArgs.split(List<String> argv) {
    final links = <String>[
      for (final a in argv)
        if (looksLikeWaveCruxLink(a)) a,
    ];
    if (links.isEmpty) return WaveCruxLaunchArgs._(argv, const <String>[]);
    return WaveCruxLaunchArgs._(const <String>[], links);
  }

  /// The arguments to parse as a command line. Empty when [links] is not.
  final List<String> args;

  /// Every argument that looked like a link. More than one is refused as a
  /// whole ([WaveCruxLinkRefusal.tooManyLinks]).
  final List<String> links;
}
