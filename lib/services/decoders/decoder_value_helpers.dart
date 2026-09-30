// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Pure-value helpers shared by every [ProtocolDecoder] implementation
/// (`lib/domain/interfaces/protocol_decoder.dart`), across both the open-core
/// decoder set here and the closed-source Pro decoders in the Pro overlay.
///
/// These were previously copy-pasted as private methods into ~15 decoders in
/// two repos; a bit-parsing fix (e.g. x/z handling) had to be applied N times.
/// Consolidating them here means one canonical implementation and one place to
/// test the edge cases.
///
/// Two families:
///
///  1. **VCD value predicates / parsers** ([isVcdHigh], [isVcdLow],
///     [parseVcdVectorInt]) — interpret the value strings returned by
///     `SignalValueQuery`. Each strips an optional `b`/`B` binary prefix and
///     surrounding whitespace, so both scalar (`'1'`) and vector-formatted
///     (`'b0101'`) values are handled uniformly.
///  1a. **Lenient parsers** ([parseVcdVectorIntLenient],
///     [parseVcdVectorIntLenientOrNull], [parseVcdVectorBigLenient],
///     [vcdVectorBytesLsbFirst], [vcdVectorWidth]) — the same parsing with
///     `x`/`z` coerced to `0` instead of rejecting the whole value. Streaming
///     decoders (Avalon-ST/MM, AXI-Stream, the Ethernet front-ends) need a
///     deterministic byte stream even when a capture has partial coverage, so
///     they take this family; decoders that must distinguish "unknown" from a
///     concrete value take [parseVcdVectorInt].
///  2. **Config-parameter readers** ([intParam], [stringParam], [boolParam]) —
///     coerce `DecoderConfig.parameters` entries (a `Map<String, dynamic>`
///     whose values may arrive as their natural type or as a String from a
///     round-tripped `.wavecrux` session) to `int` / `String` / `bool`, with a
///     fallback for missing or uncoercible entries.
///  3. **Field renderers** ([bytesToHex], [bytesToHexCapped], [joinCapped]) —
///     render recovered payloads into `DecodedTransaction.fields` entries. The
///     capped variants bound the retained string so a single multi-kilobyte
///     transaction cannot pin megabytes of payload text in the transaction
///     table; the caller records the true size in a separate numeric field.
///
/// Pure Dart — no Flutter imports, no decoder state.
library;

/// Default payload cap, in bytes, for [bytesToHexCapped].
///
/// Chosen to sit above the payload sizes engineers actually read off a bus —
/// a standard 1500-byte Ethernet MTU frame and any sub-2 KB stream packet
/// render in full — while still bounding the pathological cases the cap
/// exists for: a 1024-DW PCIe write, a 9 KB jumbo frame, a multi-megabyte
/// DMA burst. Capping below the common case would trade a real memory
/// problem for a real usability one.
const int kDecoderPayloadHexMaxBytes = 2048;

/// Default element cap for [joinCapped].
///
/// Sized on the same principle as [kDecoderPayloadHexMaxBytes]: 256 bus
/// beats covers ordinary burst lengths, and caps a 1024-beat burst.
const int kDecoderPayloadMaxParts = 256;

/// Strips an optional `b`/`B` binary prefix and surrounding whitespace,
/// returning the bare digit string (possibly empty).
String _bareVector(String value) {
  final s = (value.startsWith('b') || value.startsWith('B'))
      ? value.substring(1)
      : value;
  return s.trim();
}

/// Returns [digits] with every `x`/`X`/`z`/`Z` replaced by `0`.
///
/// A hand-rolled scan rather than `replaceAll(RegExp(...))`: these parsers run
/// once per signal per clock edge, and a per-call non-const `RegExp`
/// allocation there dominates the parse itself on multi-million-edge traces.
/// Returns [digits] unchanged (no copy) when there is nothing to replace,
/// which is the overwhelmingly common case.
String _zeroUnknownBits(String digits) {
  var firstUnknown = -1;
  for (var i = 0; i < digits.length; i++) {
    final c = digits.codeUnitAt(i);
    // x=120, X=88, z=122, Z=90
    if (c == 120 || c == 88 || c == 122 || c == 90) {
      firstUnknown = i;
      break;
    }
  }
  if (firstUnknown < 0) return digits;
  final out = StringBuffer(digits.substring(0, firstUnknown));
  for (var i = firstUnknown; i < digits.length; i++) {
    final c = digits.codeUnitAt(i);
    if (c == 120 || c == 88 || c == 122 || c == 90) {
      out.write('0');
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// Returns `true` when [value] is a logic-high 1-bit VCD value.
///
/// Strips an optional `b`/`B` binary prefix and surrounding whitespace, then
/// compares against `'1'`. `null`, low (`'0'`), and unknown (`x`/`z`) values
/// return `false`.
bool isVcdHigh(String? value) {
  if (value == null) return false;
  var s = value;
  if (s.startsWith('b') || s.startsWith('B')) s = s.substring(1);
  return s.trim() == '1';
}

/// Returns `true` when [value] is a *definite* logic-low 1-bit VCD value.
///
/// Symmetric with [isVcdHigh]: strips a `b`/`B` prefix and whitespace, then
/// compares against `'0'`. `null` and unknown (`x`/`z`) values return `false`
/// — callers that treat "low" as an active condition (e.g. an active-low reset)
/// therefore do not fire on indeterminate inputs.
bool isVcdLow(String? value) {
  if (value == null) return false;
  var s = value;
  if (s.startsWith('b') || s.startsWith('B')) s = s.substring(1);
  return s.trim() == '0';
}

/// Parses a VCD binary-encoded vector [value] to an integer.
///
/// Strips an optional `b`/`B` prefix and whitespace, then parses the remaining
/// digits as base-2. Returns `null` for a `null` input, an empty payload, any
/// value containing an unknown bit (`x`/`X`/`z`/`Z`), or a parse failure — so
/// callers can distinguish "no valid value" from a concrete integer.
int? parseVcdVectorInt(String? value) {
  if (value == null) return null;
  var s = value;
  if (s.startsWith('b') || s.startsWith('B')) s = s.substring(1).trim();
  if (s.isEmpty) return null;
  if (s.contains('x') ||
      s.contains('X') ||
      s.contains('z') ||
      s.contains('Z')) {
    return null;
  }
  return int.tryParse(s, radix: 2);
}

/// Number of binary digits in [value] after prefix/whitespace stripping.
///
/// This is the signal's observed bit width — VCD emits a vector's value at its
/// declared width, so a 1-bit `error` sideband reads back as `'1'` (width 1)
/// and an 8-bit one as `'b00000001'` (width 8). Callers that need to invert an
/// active-low bus (`~raw & mask`) must build the mask from this rather than
/// assuming a fixed width, or an idle-high 1-bit signal inverts to `0xFE`
/// instead of `0`.
///
/// Returns `0` for `null` or an empty payload.
int vcdVectorWidth(String? value) {
  if (value == null) return 0;
  return _bareVector(value).length;
}

/// Parses a VCD binary-encoded vector to an integer, coercing `x`/`z` to `0`.
///
/// Returns `null` only when there is no payload at all (`null` input or an
/// empty string after prefix stripping) or when the remaining digits are not
/// valid base-2. Contrast [parseVcdVectorInt], which rejects any value
/// containing an unknown bit.
int? parseVcdVectorIntLenientOrNull(String? value) {
  if (value == null) return null;
  final s = _bareVector(value);
  if (s.isEmpty) return null;
  return int.tryParse(_zeroUnknownBits(s), radix: 2);
}

/// [parseVcdVectorIntLenientOrNull] with a concrete [fallback] (default `0`).
int parseVcdVectorIntLenient(String? value, {int fallback = 0}) =>
    parseVcdVectorIntLenientOrNull(value) ?? fallback;

/// Parses a VCD binary-encoded vector to a [BigInt], coercing `x`/`z` to `0`.
///
/// Returns [BigInt.zero] for `null`, an empty payload, or a parse failure. Use
/// this only for buses wider than 63 bits; [vcdVectorBytesLsbFirst] is the
/// better choice when the caller just wants the bytes, since it avoids
/// materializing a [BigInt] per beat.
BigInt parseVcdVectorBigLenient(String? value) {
  if (value == null) return BigInt.zero;
  final s = _bareVector(value);
  if (s.isEmpty) return BigInt.zero;
  return BigInt.tryParse(_zeroUnknownBits(s), radix: 2) ?? BigInt.zero;
}

/// Slices [value] into [byteCount] bytes, least-significant byte first.
///
/// Equivalent to parsing the whole vector and extracting
/// `(v >> (8 * i)) & 0xFF` for each `i`, but works directly on the digit
/// string: no [BigInt] is allocated, which matters because the alternative
/// costs one big-integer allocation per shift per byte per beat — roughly a
/// dozen allocations per beat on a 32-bit bus, tens of millions on a
/// million-beat trace.
///
/// Bits beyond the vector's width read back as `0` (a short vector zero-fills
/// its high bytes); digits above `8 * byteCount` are dropped. `x`/`z` digits
/// count as `0`.
List<int> vcdVectorBytesLsbFirst(String? value, int byteCount) {
  final out = List<int>.filled(byteCount, 0);
  if (value == null || byteCount <= 0) return out;
  final s = _bareVector(value);
  if (s.isEmpty) return out;
  // The digit string is MSB-first, so byte i occupies the 8 characters ending
  // at `s.length - 8 * i`.
  for (var i = 0; i < byteCount; i++) {
    final end = s.length - 8 * i;
    if (end <= 0) break;
    final start = end - 8 < 0 ? 0 : end - 8;
    var b = 0;
    for (var j = start; j < end; j++) {
      final c = s.codeUnitAt(j);
      // '1' == 49; every other digit (0, x, X, z, Z) contributes a 0 bit.
      b = (b << 1) | (c == 49 ? 1 : 0);
    }
    out[i] = b & 0xFF;
  }
  return out;
}

/// Reads decoder-config parameter [name] from [parameters] as an `int`.
///
/// Accepts a native `int`, or a `String` parseable via [int.tryParse]. Any
/// other type, a missing key, or an unparseable string yields [fallback].
int intParam(Map<String, dynamic> parameters, String name, int fallback) {
  final v = parameters[name];
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// Reads decoder-config parameter [name] from [parameters] as a `String`.
///
/// Returns the value when it is already a `String`; otherwise [fallback].
String stringParam(
  Map<String, dynamic> parameters,
  String name,
  String fallback,
) {
  final v = parameters[name];
  return v is String ? v : fallback;
}

/// Reads decoder-config parameter [name] from [parameters] as a `bool`.
///
/// Accepts a native `bool`, or a `String` — case-insensitively `'true'`/`'1'`
/// → `true` and `'false'`/`'0'` → `false`. Any other type, a missing key, or
/// an unrecognised string yields [fallback].
//
// `fallback` reads naturally as the third positional argument, parallel to
// [intParam] / [stringParam] (`param(map, name, fallback)`); a named flag here
// would break that symmetry for no clarity gain.
// ignore: avoid_positional_boolean_parameters
bool boolParam(Map<String, dynamic> parameters, String name, bool fallback) {
  final v = parameters[name];
  if (v is bool) return v;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

/// Renders [bytes] as a contiguous lowercase hex string with no separators.
///
/// Every byte contributes exactly two characters, so the result length is
/// always even and callers can hex-decode it back to the original buffer.
String bytesToHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    final v = b & 0xFF;
    if (v < 16) buffer.write('0');
    buffer.write(v.toRadixString(16));
  }
  return buffer.toString();
}

/// [bytesToHex] over at most [maxBytes] bytes, with an elision suffix when the
/// buffer is longer.
///
/// A transaction field is a display surface: it is retained for the lifetime
/// of the decoded trace and rendered in the transaction table. An uncapped
/// payload means one 1024-DW PCIe write or one jumbo AXI-Stream packet
/// retains a multi-kilobyte string, times however many transactions the trace
/// holds. Callers record the true size in a separate numeric field
/// (`byte_count`, `length_dw`, …) so nothing is lost.
///
/// Fields that are a *data path* rather than a display surface — anything a
/// consumer hex-decodes back to bytes, such as the Ethernet `raw_frame_hex`
/// that feeds PCAP export — must use [bytesToHex] instead.
String bytesToHexCapped(
  List<int> bytes, {
  int maxBytes = kDecoderPayloadHexMaxBytes,
}) {
  if (maxBytes <= 0 || bytes.length <= maxBytes) return bytesToHex(bytes);
  final head = bytesToHex(bytes.sublist(0, maxBytes));
  return '$head… (+${bytes.length - maxBytes} more bytes)';
}

/// Joins at most [maxParts] of [parts] with [separator], appending an elision
/// suffix when there are more.
///
/// The list-of-beats counterpart to [bytesToHexCapped], for fields that render
/// one entry per bus beat (per-DW payload dumps, per-beat write data).
String joinCapped(
  List<String> parts, {
  String separator = ', ',
  int maxParts = kDecoderPayloadMaxParts,
}) {
  if (maxParts <= 0 || parts.length <= maxParts) return parts.join(separator);
  final head = parts.take(maxParts).join(separator);
  return '$head$separator… (+${parts.length - maxParts} more)';
}
