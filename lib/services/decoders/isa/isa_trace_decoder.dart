// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';

/// Instruction-word width. RV32 and RV64 both fetch 32 bits, and so do
/// MicroBlaze and LM32; the 16-bit compressed encodings are handled by tables
/// that place them in the low half of a 32-bit container.
const int kIsaInstructionBitWidth = 32;

/// Post-processes a decoded instruction before it becomes a transaction label.
///
/// The seam the Pro alias packs plug into. Open core leaves the disassembly as
/// the encoding tables produced it — correct, complete, and harder to read than
/// it needs to be, because `mv`, `ret`, `nop` and the branch-against-zero forms
/// are conventions layered on the encoding rather than properties of it.
typedef IsaDisassemblyRenderer =
    DisassembledInstruction Function(
      DisassembledInstruction decoded,
      InstructionDisassembler disassembler,
    );

/// The renderer the app installs into every instruction-trace decoder.
///
/// A plain static seam rather than a Riverpod override, matching
/// `RiscvIdentityTrackerRegistry`: the decoder registry builds decoders from a
/// closure that has no container, and every consumer of a decoded trace should
/// see the same disassembly rather than only the widgets that watch a provider.
///
/// **The seam itself carries no tier; the renderer the Pro build installs
/// does.** An earlier note here argued the opposite — that a lapsed licence
/// should stop updates, not rendering — but that is not how the suite's
/// licences behave: grace keeps the tier, and past grace every other Pro gate
/// closes. Gating on the Pro build's *presence* alone meant every downloader
/// of that build rendered pseudo-instructions at Open Core. So the open-core
/// build leaves this null and renders exactly what the tables say, and the
/// Pro build installs a renderer that asks the live tier on every call.
IsaDisassemblyRenderer? isaDisassemblyRenderer;

/// Walks an instruction-fetch trace and disassembles it.
///
/// **Architecture-neutral by construction.** Everything here — sampling the
/// fetch clock, honouring an optional valid strobe, reading the instruction and
/// PC words, formatting a transaction — is the same work whatever ISA the core
/// implements. The only architecture-specific decision is *which encoding
/// tables to consult*, and that is the one method a subclass supplies.
///
/// That split is what lets the Pro ISA pack ship MicroBlaze and LM32 without a
/// second copy of the trace walk. Before it existed, the RISC-V decoder was the
/// only instruction-trace decoder in the app, and a curated table for any other
/// core would have been an asset nothing could select.
abstract class IsaTraceDecoder implements ProtocolDecoder {
  /// Creates a decoder over [assets].
  IsaTraceDecoder(this.config, this.assets, {IsaDisassemblyRenderer? renderer})
    : _renderer = renderer;

  /// The user's binding and parameter choices.
  @protected
  final DecoderConfig config;

  /// The encoding tables discovered for this architecture.
  @protected
  final IsaDecoderAssets assets;

  final IsaDisassemblyRenderer? _renderer;

  /// Built lazily rather than in the constructor, deliberately: the
  /// constructor cannot call [resolveInstructionSets] because a subclass's
  /// fields are not initialised until after the base constructor returns, so
  /// an override reading them would see nulls.
  late final InstructionDisassembler disassembler = InstructionDisassembler(
    resolveInstructionSets(),
  );

  /// Which tables this decoder consults, in composition order.
  ///
  /// Order matters: the disassembler resolves by last-match-wins, so a table
  /// meant to override another must come after it.
  @protected
  List<InstructionSet> resolveInstructionSets();

  /// Hex width for the rendered PC. 8 nibbles unless a subclass says otherwise.
  @protected
  int get pcHexNibbles => 8;

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final clkChanges = changesQuery('clk', startTime, endTime);
    if (clkChanges.isEmpty) return const [];

    final hasValid = config.signalBindings.containsKey('valid');
    final hasPc = config.signalBindings.containsKey('pc');

    final transactions = <DecodedTransaction>[];

    for (final (edgeTime, edgeVal) in clkChanges) {
      if (!isHigh(edgeVal)) continue;
      if (hasValid && !isHigh(query('valid', edgeTime))) continue;

      final instrRaw = query('instruction', edgeTime);
      final instr = parseVectorInt(instrRaw);
      if (instr == null) continue; // x/z or unparseable; skip cycle

      final pc = hasPc ? parseVectorInt(query('pc', edgeTime)) : null;
      final rawDisasm = disassembler.decode(instr, kIsaInstructionBitWidth);
      final disasm = rawDisasm == null
          ? null
          : (_renderer?.call(rawDisasm, disassembler) ?? rawDisasm);

      final pcStr = pc != null ? fmtHex(pc, pcHexNibbles) : null;
      final rawStr = fmtHex(instr, 8);

      if (disasm == null) {
        final label = pcStr != null
            ? '[$pcStr] UNKNOWN INSN ($rawStr)'
            : 'UNKNOWN INSN ($rawStr)';
        transactions.add(
          DecodedTransaction(
            startTime: edgeTime,
            endTime: edgeTime,
            label: label,
            fields: {'raw': rawStr, 'pc': ?pcStr},
            isError: true,
            errorMessage: 'No matching instruction in loaded ISA TOMLs',
          ),
        );
        continue;
      }

      final label = pcStr != null ? '[$pcStr] ${disasm.text}' : disasm.text;
      transactions.add(
        DecodedTransaction(
          startTime: edgeTime,
          endTime: edgeTime,
          label: label,
          fields: {
            'mnemonic': disasm.mnemonic,
            'disasm': disasm.text,
            'raw': rawStr,
            'isa': disasm.setName,
            'pc': ?pcStr,
          },
        ),
      );
    }
    return transactions;
  }

  // ── parameter and value helpers, shared by every ISA ─────────────────────

  /// String parameter, or [fallback].
  @protected
  String strParam(String name, String fallback) {
    final v = config.parameters[name];
    if (v is String) return v;
    if (v != null) return v.toString();
    return fallback;
  }

  /// Integer parameter, or [fallback].
  @protected
  int intParam(String name, int fallback) {
    final v = config.parameters[name];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// Boolean parameter, tolerating the string spellings a config file carries.
  @protected
  bool boolParam(String name, {required bool defaultValue}) {
    final v = config.parameters[name];
    if (v is bool) return v;
    if (v is String) {
      final lower = v.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return defaultValue;
  }

  /// Whether a 1-bit VCD value reads as high.
  @protected
  bool isHigh(String? value) {
    if (value == null) return false;
    var s = value;
    if (s.startsWith('b') || s.startsWith('B')) s = s.substring(1);
    return s.trim() == '1';
  }

  /// Parses a VCD vector, returning null for x/z — an unresolved fetch is not
  /// an instruction and must not be decoded as one.
  @protected
  int? parseVectorInt(String? value) {
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

  /// `0xDEADBEEF`-style rendering, zero-padded to [nibbles].
  @protected
  String fmtHex(int value, int nibbles) {
    final hex = value.toUnsigned(nibbles * 4).toRadixString(16);
    return '0x${hex.padLeft(nibbles, '0').toUpperCase()}';
  }
}
