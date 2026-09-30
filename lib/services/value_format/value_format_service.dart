// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';

/// Formats raw signal value strings (from the waveform data source) into
/// human-readable display strings for each [DisplayFormat].
///
/// Raw values use the VCD/wellen bit-string encoding:
/// - Scalar (1-bit): `"0"`, `"1"`, `"x"`, `"z"`
/// - Vector: `"0101xxzz"` (already normalized, no prefix) or `"b0101xxzz"` (VCD prefix)
/// - Real/analog: `"3.14"`, `"-1.5e-3"` (floating-point, no x/z)
///
/// x/z propagation rules follow GTKWave conventions:
/// - Hex/octal: any `x` in a digit group → `x`; any `z` (no `x`) → `z`
/// - Decimal: any `x` or `z` anywhere → `X` or `Z` (indeterminate)
/// - ASCII: any `x` or `z` in a byte → `?`
class ValueFormatService {
  const ValueFormatService();

  /// Returns the conventional default [DisplayFormat] for a given [bitWidth]:
  /// binary for 1-bit signals, hexadecimal for everything wider.
  static DisplayFormat defaultFormat(int bitWidth) =>
      bitWidth == 1 ? DisplayFormat.binary : DisplayFormat.hexadecimal;

  /// Formats [rawValue] for the given [format] and [bitWidth].
  ///
  /// [bitWidth] is the signal's declared bit width; used for padding in binary
  /// mode and for two's-complement sign interpretation in signed-decimal mode.
  /// Pass `0` only for real/analog signals where width is not meaningful.
  ///
  /// [config] is the per-signal translator configuration map from
  /// [SignalEntry.translatorConfig]. Required for [DisplayFormat.fixedPointQ]
  /// and [DisplayFormat.namedEnum]; ignored for all other formats.
  String format(
    String rawValue,
    int bitWidth,
    DisplayFormat fmt, [
    Map<String, Object?>? config,
  ]) {
    if (rawValue.isEmpty) return rawValue;
    final bits = _normalizeBits(rawValue, bitWidth);
    if (_isNonBitString(bits)) return bits; // real/analog — pass through

    return switch (fmt) {
      DisplayFormat.binary => _formatBinary(bits, bitWidth),
      DisplayFormat.hexadecimal => _formatHex(bits),
      DisplayFormat.octal => _formatOctal(bits),
      DisplayFormat.unsignedDecimal => _formatUnsignedDecimal(bits),
      DisplayFormat.signedDecimal => _formatSignedDecimal(bits, bitWidth),
      DisplayFormat.ascii => _formatAscii(bits),
      DisplayFormat.ieee754Single => _formatIeee754Single(bits),
      DisplayFormat.ieee754Double => _formatIeee754Double(bits),
      DisplayFormat.fixedPointQ => _formatFixedPointQ(bits, config),
      DisplayFormat.signedMagnitude => _formatSignedMagnitude(bits),
      DisplayFormat.grayCode => _formatGrayCode(bits),
      DisplayFormat.namedEnum => _formatNamedEnum(bits, config),
    };
  }

  /// Interprets [rawValue] as a **number** under [fmt], for callers that need
  /// a magnitude rather than a label — today that is the analog renderer.
  ///
  /// Returns [double.nan] whenever the value has no defined magnitude: `x`/`z`
  /// bits, an empty value, or an unparseable real literal. The analog painter
  /// renders NaN as a gap, so "unknown" stays visible rather than being drawn
  /// as zero.
  ///
  /// **This is not `double.parse(format(...))`.** For the radix formats the
  /// rendered text is not a decimal number at all — `format` returns `"ff"` for
  /// hex, and `"1e5"` for another hex value happens to parse as `100000.0`,
  /// which would plot a bus 200× too high. The radix is a display choice; the
  /// magnitude is the same either way, so binary / hex / octal all interpret
  /// the raw bits as an unsigned integer. ASCII and named-enum likewise carry
  /// no magnitude of their own and fall back to the unsigned bit value, which
  /// is what GTKWave plots for a bus in those formats.
  ///
  /// The formats that *do* define a distinct numeric reading — signed decimal,
  /// sign-magnitude, Gray code, IEEE 754, fixed-point Q — get it here, using
  /// the same bit arithmetic their formatter uses.
  double numericValue(
    String rawValue,
    int bitWidth,
    DisplayFormat fmt, [
    Map<String, Object?>? config,
  ]) {
    if (rawValue.isEmpty) return double.nan;
    final bits = _normalizeBits(rawValue, bitWidth);

    // A real/analog literal ("3.14", "-1.5e-3") — the value is already a
    // number and no format applies to it.
    if (_isNonBitString(bits)) {
      final s = bits.trim();
      if (s == 'x' || s == 'z' || s == 'nan') return double.nan;
      return double.tryParse(s) ?? double.nan;
    }

    // Unknown or high-impedance bits have no magnitude.
    if (bits.contains('x') || bits.contains('z')) return double.nan;
    if (bits.isEmpty) return double.nan;

    return switch (fmt) {
      // Radix and text formats: magnitude is the raw unsigned bit value.
      DisplayFormat.binary ||
      DisplayFormat.hexadecimal ||
      DisplayFormat.octal ||
      DisplayFormat.ascii ||
      DisplayFormat.namedEnum ||
      DisplayFormat.unsignedDecimal => BigInt.parse(bits, radix: 2).toDouble(),

      DisplayFormat.signedDecimal => _signedValue(bits, bitWidth).toDouble(),
      DisplayFormat.signedMagnitude => _signedMagnitudeValue(bits),
      DisplayFormat.grayCode => _grayValue(bits).toDouble(),
      DisplayFormat.ieee754Single => _ieee754SingleValue(bits),
      DisplayFormat.ieee754Double => _ieee754DoubleValue(bits),
      DisplayFormat.fixedPointQ => _fixedPointQValue(bits, config),
    };
  }

  // ── numeric readings (shared with the formatters above) ────────────────────

  BigInt _signedValue(String bits, int bitWidth) {
    final unsigned = BigInt.parse(bits, radix: 2);
    // Width 0 means "not declared" — read it as unsigned rather than guessing
    // a sign bit that may not exist.
    if (bitWidth <= 0) return unsigned;
    final halfMax = BigInt.one << (bitWidth - 1);
    final maxVal = BigInt.one << bitWidth;
    return unsigned >= halfMax ? unsigned - maxVal : unsigned;
  }

  double _signedMagnitudeValue(String bits) {
    final signBit = bits[0];
    final magnitude = bits.length > 1 ? bits.substring(1) : '0';
    final magValue = BigInt.parse(magnitude, radix: 2).toDouble();
    // Negative zero is representable here and is deliberately preserved: the
    // formatter renders it "−0", and plotting it as +0 would hide the encoding.
    return signBit == '1' ? -magValue : magValue;
  }

  BigInt _grayValue(String bits) {
    final gray = BigInt.parse(bits, radix: 2);
    var binary = gray;
    var mask = gray >> 1;
    while (mask > BigInt.zero) {
      binary = binary ^ mask;
      mask = mask >> 1;
    }
    return binary;
  }

  double _ieee754SingleValue(String bits) {
    final padded = bits.padLeft(32, '0');
    if (padded.length != 32) return double.nan;
    return _ByteData32(int.parse(padded, radix: 2)).asFloat32();
  }

  double _ieee754DoubleValue(String bits) {
    final padded = bits.padLeft(64, '0');
    if (padded.length != 64) return double.nan;
    final high = int.parse(padded.substring(0, 32), radix: 2);
    final low = int.parse(padded.substring(32, 64), radix: 2);
    return _ByteData64(high, low).asFloat64();
  }

  double _fixedPointQValue(String bits, Map<String, Object?>? config) {
    final cfg = config != null
        ? QFormatConfig.fromMap(config)
        : const QFormatConfig();
    final intVal = cfg.signed
        ? _signedValue(bits, bits.length)
        : BigInt.parse(bits, radix: 2);
    if (cfg.n == 0) return intVal.toDouble();
    // Divide as doubles rather than scaling BigInts: the fractional result is
    // the whole point, and `>> n` would floor it away.
    return intVal.toDouble() / (BigInt.one << cfg.n).toDouble();
  }

  // ── normalization ──────────────────────────────────────────────────────────

  String _normalizeBits(String rawValue, int bitWidth) {
    var s = rawValue.toLowerCase();
    // Strip VCD vector prefix ('b' for binary, 'r' for real).
    if (s.startsWith('b')) s = s.substring(1);
    if (s.startsWith('r')) s = s.substring(1);
    // Zero-extend bit strings shorter than the declared width.
    if (!_isNonBitString(s) && s.length < bitWidth && bitWidth > 0) {
      s = s.padLeft(bitWidth, '0');
    }
    return s;
  }

  /// Returns true if [s] contains characters other than 0, 1, x, z —
  /// indicating a real/floating-point value rather than a bit string.
  static bool _isNonBitString(String s) {
    for (final c in s.runes) {
      if (c != 0x30 && c != 0x31 && c != 0x78 && c != 0x7a) return true;
      // 0x30='0'  0x31='1'  0x78='x'  0x7a='z'
    }
    return false;
  }

  // ── binary ─────────────────────────────────────────────────────────────────

  String _formatBinary(String bits, int bitWidth) {
    if (bitWidth > 0 && bits.length < bitWidth) {
      return bits.padLeft(bitWidth, '0');
    }
    return bits;
  }

  // ── hexadecimal ────────────────────────────────────────────────────────────

  String _formatHex(String bits) {
    final padLen = ((bits.length + 3) ~/ 4) * 4;
    final padded = bits.padLeft(padLen, '0');

    final buf = StringBuffer();
    for (var i = 0; i < padded.length; i += 4) {
      final nibble = padded.substring(i, i + 4);
      if (nibble.contains('x')) {
        buf.write('x');
      } else if (nibble.contains('z')) {
        buf.write('z');
      } else {
        buf.write(int.parse(nibble, radix: 2).toRadixString(16));
      }
    }
    return buf.toString();
  }

  // ── octal ──────────────────────────────────────────────────────────────────

  String _formatOctal(String bits) {
    final padLen = ((bits.length + 2) ~/ 3) * 3;
    final padded = bits.padLeft(padLen, '0');

    final buf = StringBuffer();
    for (var i = 0; i < padded.length; i += 3) {
      final group = padded.substring(i, i + 3);
      if (group.contains('x')) {
        buf.write('x');
      } else if (group.contains('z')) {
        buf.write('z');
      } else {
        buf.write(int.parse(group, radix: 2).toRadixString(8));
      }
    }
    return buf.toString();
  }

  // ── unsigned decimal ───────────────────────────────────────────────────────

  String _formatUnsignedDecimal(String bits) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';
    return BigInt.parse(bits, radix: 2).toString();
  }

  // ── signed decimal ─────────────────────────────────────────────────────────

  String _formatSignedDecimal(String bits, int bitWidth) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';
    if (bitWidth <= 0) return BigInt.parse(bits, radix: 2).toString();

    final unsigned = BigInt.parse(bits, radix: 2);
    final halfMax = BigInt.one << (bitWidth - 1);
    final maxVal = BigInt.one << bitWidth;
    final signed = unsigned >= halfMax ? unsigned - maxVal : unsigned;
    return signed.toString();
  }

  // ── ascii ──────────────────────────────────────────────────────────────────

  String _formatAscii(String bits) {
    // Pad to a multiple of 8 so we process complete bytes.
    final padLen = ((bits.length + 7) ~/ 8) * 8;
    final padded = bits.padLeft(padLen, '0');

    final buf = StringBuffer();
    for (var i = 0; i < padded.length; i += 8) {
      final byte = padded.substring(i, i + 8);
      if (byte.contains('x') || byte.contains('z')) {
        buf.write('?');
      } else {
        final code = int.parse(byte, radix: 2);
        if (code >= 0x20 && code <= 0x7e) {
          buf.writeCharCode(code);
        } else {
          buf
            ..write(r'\x')
            ..write(code.toRadixString(16).padLeft(2, '0'));
        }
      }
    }
    return buf.toString();
  }

  // ── IEEE 754 single precision (32-bit) ────────────────────────────────────

  String _formatIeee754Single(String bits) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';
    // Require exactly 32 bits; pad or signal width-mismatch gracefully.
    final padded = bits.padLeft(32, '0');
    if (padded.length != 32) return _formatHex(bits);

    final raw = int.parse(padded, radix: 2);
    // Reconstruct via ByteData to get proper IEEE 754 single interpretation.
    final bd = _ByteData32(raw);
    final f = bd.asFloat32();
    return _formatFloat(f);
  }

  // ── IEEE 754 double precision (64-bit) ────────────────────────────────────

  String _formatIeee754Double(String bits) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';
    final padded = bits.padLeft(64, '0');
    if (padded.length != 64) return _formatHex(bits);

    final high = int.parse(padded.substring(0, 32), radix: 2);
    final low = int.parse(padded.substring(32, 64), radix: 2);
    final bd = _ByteData64(high, low);
    final d = bd.asFloat64();
    return _formatFloat(d);
  }

  static String _formatFloat(double f) {
    if (f.isNaN) return 'NaN';
    if (f.isInfinite) return f.isNegative ? '-Inf' : '+Inf';
    // Use up to 7 significant digits (IEEE 754 single) — double gets more
    // digits automatically via Dart's default toString which is shortest.
    final s = f.toString();
    // Dart already emits the shortest round-trippable representation.
    return s;
  }

  // ── fixed-point Q-format ──────────────────────────────────────────────────

  String _formatFixedPointQ(String bits, Map<String, Object?>? config) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';

    final cfg = config != null
        ? QFormatConfig.fromMap(config)
        : const QFormatConfig();
    final n = cfg.n;

    // Interpret raw bit pattern as an integer.
    final raw = BigInt.parse(bits, radix: 2);
    BigInt intVal;
    if (cfg.signed) {
      final width = bits.length;
      final halfMax = BigInt.one << (width - 1);
      final maxVal = BigInt.one << width;
      intVal = raw >= halfMax ? raw - maxVal : raw;
    } else {
      intVal = raw;
    }

    // Scale: value = intVal / 2^n
    if (n == 0) return intVal.toString();

    final scale = BigInt.one << n; // 2^n
    final wholePart = intVal ~/ scale;
    final fracPart = (intVal - wholePart * scale).abs();

    // Convert fractional part to decimal digits.
    // Multiply fracPart by 10^digits / scale and format.
    const digits = 6;
    final fracScaled = (fracPart * BigInt.from(1000000)) ~/ scale;
    final fracStr = fracScaled.toString().padLeft(digits, '0').trimRight();
    // Trim trailing zeros but keep at least one digit for readability.
    var trimmed = fracStr.isEmpty ? '0' : fracStr;
    while (trimmed.length > 1 && trimmed.endsWith('0')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    final sign = intVal.isNegative && wholePart == BigInt.zero ? '-' : '';
    return '$sign$wholePart.$trimmed';
  }

  // ── signed magnitude ──────────────────────────────────────────────────────

  String _formatSignedMagnitude(String bits) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';
    if (bits.isEmpty) return '0';

    final signBit = bits[0];
    final magnitude = bits.length > 1 ? bits.substring(1) : '0';
    final magValue = BigInt.parse(magnitude, radix: 2);

    if (signBit == '1') {
      // Negative — distinct −0 renders as "−0"
      return '−$magValue';
    }
    return magValue.toString();
  }

  // ── Gray code ─────────────────────────────────────────────────────────────

  String _formatGrayCode(String bits) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';
    if (bits.isEmpty) return '0';

    // Binary-reflected Gray → binary decode.
    // binary[0] = gray[0]; binary[i] = binary[i-1] XOR gray[i]
    final gray = BigInt.parse(bits, radix: 2);
    var binary = gray;
    var mask = gray >> 1;
    while (mask > BigInt.zero) {
      binary = binary ^ mask;
      mask = mask >> 1;
    }
    return binary.toString();
  }

  // ── named enum ────────────────────────────────────────────────────────────

  String _formatNamedEnum(String bits, Map<String, Object?>? config) {
    if (bits.contains('x')) return 'X';
    if (bits.contains('z')) return 'Z';

    if (config == null) return _formatHex(bits);

    final cfg = NamedEnumConfig.fromMap(config);
    final value = BigInt.parse(bits, radix: 2);
    return cfg.translate(value) ?? _formatHex(bits);
  }
}

// ── IEEE 754 bit-cast helpers (pure Dart, no dart:typed_data import needed
//    in domain but services layer can use it) ─────────────────────────────────

class _ByteData32 {
  _ByteData32(int raw) : _raw = raw & 0xFFFFFFFF;
  final int _raw;

  double asFloat32() {
    final sign = (_raw >> 31) & 1;
    final exp = (_raw >> 23) & 0xFF;
    final frac = _raw & 0x7FFFFF;

    if (exp == 0xFF) {
      // Infinity or NaN
      if (frac == 0) {
        return sign == 0 ? double.infinity : double.negativeInfinity;
      }
      return double.nan;
    }
    if (exp == 0) {
      // Subnormal
      final value = frac / 8388608.0 * 1.1754943508222875e-38; // 2^-126
      return sign == 0 ? value : -value;
    }
    final value = (1.0 + frac / 8388608.0) * _pow2(exp - 127);
    return sign == 0 ? value : -value;
  }
}

class _ByteData64 {
  _ByteData64(int high, int low) : _high = high, _low = low;
  final int _high;
  final int _low;

  double asFloat64() {
    final sign = (_high >> 31) & 1;
    final exp = (_high >> 20) & 0x7FF;
    final fracHigh = _high & 0xFFFFF;
    final fracLow = _low;

    if (exp == 0x7FF) {
      if (fracHigh == 0 && fracLow == 0) {
        return sign == 0 ? double.infinity : double.negativeInfinity;
      }
      return double.nan;
    }
    if (exp == 0) {
      // Subnormal — very small; return zero as a fallback.
      return 0;
    }
    // Reconstruct via Dart's double arithmetic (Dart is IEEE 754 64-bit).
    // Combine 52-bit mantissa: high 20 bits from fracHigh, low 32 from fracLow.
    // Mask _low to unsigned 32-bit to avoid Dart signed-int confusion.
    final fracLowU = _low & 0xFFFFFFFF;
    final mantissa =
        (fracHigh * 4294967296 + fracLowU) / 4503599627370496; // 2^52
    final value = (1.0 + mantissa) * _pow2(exp - 1023);
    return sign == 0 ? value : -value;
  }
}

double _pow2(int exp) {
  if (exp >= 0) {
    var r = 1.0;
    for (var i = 0; i < exp; i++) {
      r *= 2.0;
    }
    return r;
  } else {
    var r = 1.0;
    for (var i = 0; i < -exp; i++) {
      r /= 2.0;
    }
    return r;
  }
}
