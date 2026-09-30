// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/analog_interpolation.dart';
import 'package:wavecrux/domain/enums/display_format.dart';

// ── GtkwFile ──────────────────────────────────────────────────────────────────

/// Parsed representation of a GTKWave `.gtkw` save file.
///
/// The `.gtkw` format is a line-oriented ASCII text format that GTKWave writes
/// when the user saves a waveform view session. This class captures all
/// information needed to reconstruct that session inside WaveCrux.
@immutable
class GtkwFile {
  const GtkwFile({
    this.dumpFilePath,
    this.timeStart,
    this.zoomFactor,
    this.primaryMarker,
    this.namedMarkers = const {},
    this.openScopes = const [],
    this.entries = const [],
    this.canvasBackgroundHex,
  });

  /// Path to the referenced waveform file (from `[dumpfile]` directive), or null.
  final String? dumpFilePath;

  /// Simulation tick at the left edge of the viewport (`[timestart]`), or null.
  final int? timeStart;

  /// GTKWave zoom factor from the `*` marker line, or null if absent.
  ///
  /// Stored as-is from the file. Conversion to WaveCrux [ticksPerPixel]
  /// requires the timescale from the loaded waveform — handled by
  /// [GtkwImportService].
  final double? zoomFactor;

  /// GTKWave's primary marker (its cursor) from the `*` line, or null when it
  /// is unset (GTKWave writes -1) or the line is absent.
  ///
  /// This is the field straight after the zoom factor. It is not a named
  /// marker; [GtkwImportService] imports it as the primary cursor position.
  final int? primaryMarker;

  /// Named markers a–z parsed from the `*` line.
  ///
  /// GTKWave writes them after the zoom factor and the primary marker, so the
  /// third field is marker `a`. Only markers with non-negative tick values are
  /// included (GTKWave writes -1 for unset markers).
  final Map<String, int> namedMarkers;

  /// Scope paths that were expanded in the GTKWave signal tree (`[treeopen]`).
  final List<String> openScopes;

  /// Ordered signal entries (signals, groups, separators, comments).
  final List<GtkwEntry> entries;

  /// Canvas background color from a `[bgcolor]` directive, as a CSS hex string
  /// (`#RRGGBB`), or null if absent. Callers apply this as the
  /// `canvas.background` theme override during GTKWave session import.
  final String? canvasBackgroundHex;

  @override
  String toString() =>
      'GtkwFile('
      'dumpFile: $dumpFilePath, '
      'entries: ${entries.length}, '
      'markers: ${namedMarkers.length})';
}

// ── Entry sealed hierarchy ────────────────────────────────────────────────────

/// A single parsed row from a GTKWave `.gtkw` file.
sealed class GtkwEntry {
  const GtkwEntry();
}

/// A signal trace row.
@immutable
final class GtkwSignalEntry extends GtkwEntry {
  const GtkwSignalEntry({
    required this.path,
    required this.format,
    this.colorArgb,
    this.translateFilterPath,
    this.renderAsAnalog = false,
    this.analogInterpolation = AnalogInterpolation.linear,
  });

  /// Full hierarchical path as it appears in the .gtkw file (e.g. `top.clk`).
  ///
  /// May include a bit-range suffix such as `top.data[7:0]`; the import
  /// service strips this before path matching.
  final String path;

  /// Display format derived from the GTKWave flag word.
  final DisplayFormat format;

  /// Packed ARGB color derived from a `[color]` directive, or null for auto.
  final int? colorArgb;

  /// Path to a GTKWave translate filter file, or null if absent.
  final String? translateFilterPath;

  /// True when the save file asked for this trace to be drawn as an analog
  /// curve (`TR_ANALOG_STEP` or `TR_ANALOG_INTERPOLATED`).
  final bool renderAsAnalog;

  /// Which analog shape the save file asked for. Meaningful only when
  /// [renderAsAnalog] is true; defaults to linear so the field is never null.
  final AnalogInterpolation analogInterpolation;

  @override
  String toString() =>
      'GtkwSignalEntry($path, $format'
      '${renderAsAnalog ? ', analog ${analogInterpolation.name}' : ''})';
}

/// A named group begin marker.
@immutable
final class GtkwGroupBeginEntry extends GtkwEntry {
  const GtkwGroupBeginEntry(this.name);

  final String name;

  @override
  String toString() => 'GtkwGroupBeginEntry($name)';
}

/// A named group end marker.
@immutable
final class GtkwGroupEndEntry extends GtkwEntry {
  const GtkwGroupEndEntry(this.name);

  final String name;

  @override
  String toString() => 'GtkwGroupEndEntry($name)';
}

/// A blank separator row.
final class GtkwSeparatorEntry extends GtkwEntry {
  const GtkwSeparatorEntry();

  @override
  String toString() => 'GtkwSeparatorEntry';
}

/// A comment / label row.
@immutable
final class GtkwCommentEntry extends GtkwEntry {
  const GtkwCommentEntry(this.text);

  final String text;

  @override
  String toString() => 'GtkwCommentEntry($text)';
}

// ── GtkwParser ────────────────────────────────────────────────────────────────

/// Parses GTKWave `.gtkw` save files into a [GtkwFile] data structure.
///
/// The parser is line-oriented and tolerant of unknown directives — lines that
/// don't match any known pattern are silently skipped, matching GTKWave's own
/// approach to forward compatibility.
///
/// ### Format overview
/// | Line prefix | Meaning |
/// |-------------|---------|
/// | `[key]`     | Metadata directive (dumpfile, timestart, color, …) |
/// | `*`         | Zoom factor, primary marker, then named markers a–z |
/// | `@XXXXXXXX` | Display-format / attribute flags for the next entry |
/// | `^`         | Translate-filter reference for the next trace (skipped) |
/// | `-`         | Comment, blank separator, or group label |
/// | *(other)*   | Signal hierarchical path |
///
/// ### The `*` line
///
/// GTKWave's writer (`savefile.c`, `write_save_helper`) emits
/// `*<zoom> <primary marker> <named A> … <named Z>` — 28 fields — and its
/// reader assigns field 1 to the primary marker and fields 2 onwards to
/// `named_markers[which-2]`. A real save looks like `*-17.277769 -1 -1 …` with
/// 27 `-1`s after the zoom. Reading field 1 as marker `a` shifts every named
/// marker one letter late and invents a marker from the cursor position.
///
/// ### `^` translate-filter lines
///
/// GTKWave writes `^<n> <path>` (file filter), `^><n> <path>` (process filter)
/// and `^<<n> <path>` (transaction filter) before a trace that uses one. They
/// are not signal paths, so they are skipped; importing the filters they name
/// is not implemented.
///
/// ### The `@` flag word is a bit set, not an enumeration
///
/// Every attribute is an independent bit; `TR_RJUSTIFY` (`0x20`) is set on
/// nearly every trace a real GTKWave writes, so the radix bit is always seen in
/// combination. Values are `1 << <bit>` over `enum TraceEntFlagBits` in
/// GTKWave's `src/analyzer.h`.
///
/// | Bit mask | Flag | Meaning |
/// |----------|------|---------|
/// | `0x00000002` | `TR_HEX` | hexadecimal |
/// | `0x00000004` | `TR_DEC` | decimal (signed when `TR_SIGNED` is also set) |
/// | `0x00000008` | `TR_BIN` | binary |
/// | `0x00000010` | `TR_OCT` | octal |
/// | `0x00000020` | `TR_RJUSTIFY` | right-justify (display only; ignored here) |
/// | `0x00000200` | `TR_BLANK` | blank / separator row |
/// | `0x00000400` | `TR_SIGNED` | signed; alone (no radix bit) means signed decimal |
/// | `0x00000800` | `TR_ASCII` | ASCII |
/// | `0x00008000` | `TR_ANALOG_STEP` | draw as an analog curve, step-held |
/// | `0x00010000` | `TR_ANALOG_INTERPOLATED` | draw as an analog curve, interpolated |
/// | `0x00800000` | `TR_GRP_BEGIN` | group begin |
/// | `0x01000000` | `TR_GRP_END` | group end |
/// | `0x02000000` | `TR_BINGRAY` | Gray-coded |
/// | `0x04000000` | `TR_GRAYBIN` | Gray-coded |
///
/// **Do not reintroduce a low-byte lookup table here.** An earlier one read
/// `0x22` as octal and `0x28` as hex; per the header they are hex and binary
/// respectively, and the `fpxx_adder` capture agrees — `@22` sits on a 23-bit
/// mantissa and `@28` on `clk`/`reset`. That mapping is invisibly wrong on the
/// 1-bit signals which carry `@28`, where hex and binary render identically,
/// which is how it survived.
class GtkwParser {
  const GtkwParser();

  // ── Flag constants ──────────────────────────────────────────────────────────

  // Bit positions come from `enum TraceEntFlagBits` in GTKWave's
  // `src/analyzer.h` (each flag is `1 << <bit>`), read from the GTKWave source
  // this repo's fixtures were captured against. The two group bits below were
  // already correct and cross-check the derivation: TR_GRP_BEGIN_B is bit 23
  // (0x800000) and TR_GRP_END_B is bit 24 (0x1000000).
  static const int _kFlagHex = 0x02; // TR_HEX
  static const int _kFlagDec = 0x04; // TR_DEC
  static const int _kFlagBin = 0x08; // TR_BIN
  static const int _kFlagOct = 0x10; // TR_OCT
  static const int _kFlagSigned = 0x400; // TR_SIGNED
  static const int _kFlagAscii = 0x800; // TR_ASCII
  static const int _kFlagAnalogStep = 0x8000; // TR_ANALOG_STEP
  static const int _kFlagAnalogInterpolated = 0x10000; // TR_ANALOG_INTERPOLATED
  static const int _kFlagGroupBegin = 0x800000; // TR_GRP_BEGIN
  static const int _kFlagGroupEnd = 0x1000000; // TR_GRP_END
  static const int _kFlagBinGray = 0x2000000; // TR_BINGRAY
  static const int _kFlagGrayBin = 0x4000000; // TR_GRAYBIN
  static const int _kFlagGrayMask = _kFlagBinGray | _kFlagGrayBin;

  /// GTKWave's own default for a trace with no explicit radix bit: hex, with
  /// TR_RJUSTIFY set the way every real save file has it.
  static const int _kDefaultFlags = _kFlagHex | 0x20;

  // ── GTKWave color palette (index → packed ARGB) ─────────────────────────────
  // GTKWave color indices 1–8; index 0 means "no override" (auto palette).
  static const List<int?> _kColorPalette = [
    null,
    0xFFFF5555, // 1 red
    0xFFFF9500, // 2 orange
    0xFFFFFF00, // 3 yellow
    0xFF00FF00, // 4 green
    0xFF6699FF, // 5 blue
    0xFF8800FF, // 6 indigo/purple
    0xFFFF00FF, // 7 magenta
    0xFF00FFFF, // 8 cyan
  ];

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Parses [content] (the full text of a `.gtkw` file) into a [GtkwFile].
  ///
  /// Unknown directives are silently skipped. The parser never throws — even
  /// a completely malformed file produces an empty [GtkwFile].
  GtkwFile parse(String content) {
    String? dumpFilePath;
    int? timeStart;
    double? zoomFactor;
    int? primaryMarker;
    String? canvasBackgroundHex;
    final namedMarkers = <String, int>{};
    final openScopes = <String>[];
    final entries = <GtkwEntry>[];

    // Per-entry pending state (reset after each signal entry is emitted).
    var currentFlags = _kDefaultFlags;
    int? pendingColorIndex;
    String? pendingTranslateFilter;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;

      // ── [key] metadata directives ─────────────────────────────────────────
      if (line.startsWith('[')) {
        final bracket = line.indexOf(']');
        if (bracket == -1) continue;
        final key = line.substring(1, bracket).trim().toLowerCase();
        final value = _stripQuotes(line.substring(bracket + 1).trim());

        switch (key) {
          case 'dumpfile':
            dumpFilePath = value.isEmpty ? null : value;
          case 'timestart':
            timeStart = int.tryParse(value);
          case 'treeopen':
            if (value.isNotEmpty) openScopes.add(value);
          case 'color':
            pendingColorIndex = int.tryParse(value);
          case 'translate_filter_file':
            pendingTranslateFilter = value.isEmpty ? null : value;
          case 'bgcolor':
            canvasBackgroundHex = _parseBgcolor(value);
          case 'signal_comment':
            entries.add(GtkwCommentEntry(value));
            pendingColorIndex = null;
            pendingTranslateFilter = null;
          default:
            break; // unknown — skip for forward compatibility
        }
        continue;
      }

      // ── * zoom / primary-marker / named-marker line ───────────────────────
      if (line.startsWith('*')) {
        final parts = line.substring(1).trim().split(RegExp(r'\s+'));
        if (parts.isEmpty) continue;
        zoomFactor = double.tryParse(parts[0]);
        // Field 1 is the primary marker, not a named one.
        if (parts.length > 1) {
          final time = int.tryParse(parts[1]);
          primaryMarker = time != null && time >= 0 ? time : null;
        }
        // Named markers follow: field 2 → 'a', field 3 → 'b', …
        for (var i = 2; i < parts.length && (i - 2) < 26; i++) {
          final time = int.tryParse(parts[i]);
          if (time != null && time >= 0) {
            final letter = String.fromCharCode('a'.codeUnitAt(0) + (i - 2));
            namedMarkers[letter] = time;
          }
        }
        continue;
      }

      // ── ^ translate-filter references (^n, ^>n, ^<n) ───────────────────────
      // Not signal paths. Skipped without touching the pending per-trace state,
      // because GTKWave writes them between a trace's attributes and its path.
      if (line.startsWith('^')) continue;

      // ── @XXXXXXXX display-format / attribute flags ────────────────────────
      if (line.startsWith('@')) {
        final flagStr = line.substring(1).trim();
        final flags = int.tryParse(flagStr, radix: 16);
        if (flags != null) currentFlags = flags;
        continue;
      }

      // ── - dash lines: group labels, separators, comments ──────────────────
      if (line.startsWith('-')) {
        final text = line.substring(1);
        final trimmed = text.trim();

        final isBegin = (currentFlags & _kFlagGroupBegin) != 0;
        final isEnd = (currentFlags & _kFlagGroupEnd) != 0;

        if (isBegin) {
          entries.add(
            GtkwGroupBeginEntry(
              _stripGroupBraces(trimmed.isEmpty ? 'Group' : trimmed),
            ),
          );
        } else if (isEnd) {
          entries.add(
            GtkwGroupEndEntry(
              _stripGroupBraces(trimmed.isEmpty ? 'Group' : trimmed),
            ),
          );
        } else if (trimmed.isEmpty) {
          entries.add(const GtkwSeparatorEntry());
        } else {
          entries.add(GtkwCommentEntry(trimmed));
        }
        // Per-signal attributes reset regardless of entry kind.
        pendingColorIndex = null;
        pendingTranslateFilter = null;
        continue;
      }

      // ── Signal path (any other non-empty line) ────────────────────────────
      final path = line.trim();
      if (path.isNotEmpty) {
        entries.add(
          GtkwSignalEntry(
            path: path,
            format: _flagsToFormat(currentFlags),
            colorArgb: _colorIndexToArgb(pendingColorIndex),
            translateFilterPath: pendingTranslateFilter,
            renderAsAnalog: _flagsToAnalog(currentFlags),
            analogInterpolation: _flagsToInterpolation(currentFlags),
          ),
        );
        pendingColorIndex = null;
        pendingTranslateFilter = null;
      }
    }

    return GtkwFile(
      dumpFilePath: dumpFilePath,
      timeStart: timeStart,
      zoomFactor: zoomFactor,
      primaryMarker: primaryMarker,
      namedMarkers: Map.unmodifiable(namedMarkers),
      openScopes: List.unmodifiable(openScopes),
      entries: List.unmodifiable(entries),
      canvasBackgroundHex: canvasBackgroundHex,
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Maps a GTKWave flag word to a [DisplayFormat].
  ///
  /// Each radix is a single bit, not a value in a low-byte enumeration, and the
  /// bits combine freely with the attribute bits (`TR_RJUSTIFY` in particular is
  /// set on almost every real trace). So the decode has to test bits in GTKWave's
  /// own precedence order rather than switch on a masked byte.
  ///
  /// Precedence follows `TR_NUMMASK`'s ordering in `analyzer.h`: ASCII wins over
  /// any radix, then hex, decimal, binary, octal. `TR_SIGNED` upgrades decimal
  /// to signed decimal, and on its own (no radix bit at all, e.g. the `@420` seen
  /// in the fpxx_adder capture) means signed decimal too — GTKWave's default
  /// numeric rendering. The Gray bits are a separate mask and take precedence
  /// over the radix, matching how GTKWave applies them.
  static DisplayFormat _flagsToFormat(int flags) {
    if ((flags & _kFlagGrayMask) != 0) return DisplayFormat.grayCode;
    if ((flags & _kFlagAscii) != 0) return DisplayFormat.ascii;

    final signed = (flags & _kFlagSigned) != 0;
    if ((flags & _kFlagHex) != 0) return DisplayFormat.hexadecimal;
    if ((flags & _kFlagDec) != 0) {
      return signed
          ? DisplayFormat.signedDecimal
          : DisplayFormat.unsignedDecimal;
    }
    if ((flags & _kFlagBin) != 0) return DisplayFormat.binary;
    if ((flags & _kFlagOct) != 0) return DisplayFormat.octal;
    if (signed) return DisplayFormat.signedDecimal;

    return DisplayFormat.hexadecimal; // GTKWave's own default
  }

  /// True when [flags] asks for the trace to be drawn as an analog curve.
  ///
  /// GTKWave has three analog bits: `TR_ANALOG_STEP` and
  /// `TR_ANALOG_INTERPOLATED` choose the shape, and `TR_ANALOG_BLANK_STRETCH`
  /// only affects how blanked rows below the trace are used for height. Either
  /// of the first two means "this is an analog trace"; the third alone does not.
  static bool _flagsToAnalog(int flags) =>
      (flags & (_kFlagAnalogStep | _kFlagAnalogInterpolated)) != 0;

  /// The interpolation implied by [flags].
  ///
  /// GTKWave treats interpolated as the richer mode: when both bits are set it
  /// draws interpolated segments (`gw-wave-view-traces.c` tests
  /// `TR_ANALOG_INTERPOLATED` first), so that is the mapping here.
  static AnalogInterpolation _flagsToInterpolation(int flags) =>
      (flags & _kFlagAnalogInterpolated) != 0
      ? AnalogInterpolation.linear
      : AnalogInterpolation.stepHold;

  /// Maps a GTKWave color index to a packed ARGB integer, or null for auto.
  static int? _colorIndexToArgb(int? index) {
    if (index == null || index <= 0) return null;
    if (index < _kColorPalette.length) return _kColorPalette[index];
    return null;
  }

  /// Strips surrounding double-quotes: `"value"` → `value`.
  static String _stripQuotes(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Strips `{...}` braces used by some GTKWave versions for group names.
  static String _stripGroupBraces(String text) {
    if (text.length >= 2 && text.startsWith('{') && text.endsWith('}')) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  /// Parses a GTKWave `[bgcolor]` value to a `#RRGGBB` hex string, or null
  /// if the value is empty or not a valid 6-digit hex color.
  ///
  /// Accepts both `#RRGGBB` and bare `RRGGBB` forms. The returned string
  /// always starts with `#` for direct use as a `canvas.background` override.
  static String? _parseBgcolor(String value) {
    final stripped = value.startsWith('#') ? value.substring(1) : value;
    if (stripped.length != 6) return null;
    final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(stripped);
    return valid ? '#$stripped' : null;
  }
}
