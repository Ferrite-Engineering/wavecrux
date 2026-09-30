// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/decoders/decoder_value_helpers.dart';

/// Decodes Wishbone B3 (Classic + registered-feedback bursts) and B4
/// (Pipelined) bus transactions.
///
/// The Wishbone specification (OpenCores wbspec_b3 / wbspec_b4) defines two
/// handshake styles that share the same wire set:
///
/// - **B3 Classic standard cycle** — `cyc` envelopes `stb`; the slave returns
///   exactly one of `ack`/`err`/`rty` on the same rising-edge sample where
///   `stb` is high. One handshake = one transaction.
/// - **B3 registered-feedback bursts** (§4) — `cti` selects burst type
///   (`000` Classic, `001` Constant-address, `010` Incrementing, `111`
///   End-of-Burst); `bte` selects the wrap modulus for incrementing bursts
///   (`00` Linear, `01` 4-beat wrap, `10` 8-beat wrap, `11` 16-beat wrap).
///   Each beat is its own `stb`/`ack` handshake; the decoder emits one
///   transaction per beat plus a parent transaction summarising the burst.
/// - **B4 Pipelined** — adds `stall_o`. `stb` pulses once per requested
///   transaction (master holds outputs while `stall=1`); `ack`/`err`/`rty`
///   are decoupled from `stb` and may arrive multiple cycles later. The
///   decoder tracks an outstanding-request FIFO and emits one transaction
///   per request matched with its termination.
///
/// Per-instance configuration (`revision`, `addr_width`, `data_width`,
/// `granularity`, `endianness`, `check_alignment`) is read from the
/// [DecoderConfig.parameters] map every call to [decode] — sessions persist
/// the parameter map alongside the signal bindings.
///
/// Protocol violations detected:
///
/// 1. More than one of `ack`/`err`/`rty` asserted on the same edge
///    (RULE 3.45).
/// 2. Termination (`ack`/`err`/`rty`) asserted while `cyc` is deasserted
///    (RULE 3.30).
/// 3. `stb` asserted while `cyc` is deasserted (RULE 3.25).
/// 4. `we` changes during a cycle without `cyc` dropping (implied by
///    RULE 3.60 — `we` is `stb`-qualified and must remain stable across
///    a single cycle's beats unless paired with constant-address burst
///    rules).
/// 5. (B4 only) `adr`/`sel`/`dat_o`/`we` changes while `stb` is asserted
///    and `stall` is high — master must repeat its outputs across stalled
///    cycles (B4 §3.3).
/// 6. `adr` changes between beats of a constant-address burst (CTI=001;
///    RULE 4.35).
/// 7. `we` or `sel` change between beats of an incrementing burst, or
///    `adr` does not increment by data-port-byte-size (CTI=010;
///    RULE 4.40).
/// 8. Reserved CTI value (`011`/`100`/`101`/`110`) appears (Table 4-2).
/// 9. `bte` non-zero while `cti` is not the incrementing-burst code
///    (`010`) (B3 §4.2 — BTE only carries meaning for incrementing
///    bursts).
/// 10. Address misaligned to (data_width / granularity) — gated by the
///     `check_alignment` parameter (industry-standard sanity check).
class WishboneDecoder implements ProtocolDecoder {
  /// Creates a [WishboneDecoder] bound to [config].
  const WishboneDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  /// Static metadata registered with `DecoderRegistry` at app startup.
  static const decoderDefinition = DecoderDefinition(
    id: 'wishbone',
    displayName: 'Wishbone',
    description:
        'Decodes Wishbone B3 (Classic + registered-feedback bursts) and '
        'B4 (Pipelined) bus transactions. AMBA-adjacent open-bus protocol '
        'used by LiteX, picorv32, NEORV32, and the wider open-source HDL '
        'ecosystem.',
    category: DecoderCategory.amba,
    requiredSignals: [
      SignalBinding(
        name: 'clk',
        description: 'Bus clock (rising-edge sampled)',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'rst',
        description:
            'Synchronous reset (active high per Wishbone spec; '
            'bind an inverted net for active-low designs)',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'cyc',
        description: 'Cycle envelope; held across all phases of a transfer',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'stb',
        description: 'Strobe; qualifies adr/we/dat_o/sel for the current beat',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'we',
        description: 'Write enable (1 = write, 0 = read)',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'adr',
        description: 'Address bus; width comes from addr_width parameter',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'dat_o',
        description:
            'Master-to-slave data bus (write data); width = '
            'data_width parameter',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'dat_i',
        description:
            'Slave-to-master data bus (read data); width = '
            'data_width parameter',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'ack',
        description: 'Normal termination',
        bitWidth: 1,
      ),
    ],
    optionalSignals: [
      SignalBinding(
        name: 'sel',
        description:
            'Byte-lane select mask; width = data_width / granularity. '
            'When unbound the decoder treats every beat as full-width.',
      ),
      SignalBinding(
        name: 'err',
        description: 'Error termination',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'rty',
        description: 'Retry termination',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'lock',
        description: 'Indivisible-cycle hint',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'cti',
        description:
            'Cycle Type Identifier (3-bit). Binding enables burst '
            'decode; when unbound every cycle is treated as Classic.',
        bitWidth: 3,
      ),
      SignalBinding(
        name: 'bte',
        description:
            'Burst Type Extension (2-bit). Binding enables wrap-burst '
            'decode; ignored when cti is unbound.',
        bitWidth: 2,
      ),
      SignalBinding(
        name: 'stall',
        description:
            'Slave-not-ready (B4 pipelined only). Required at '
            'decode time when revision = B4; the decoder emits a warning '
            'transaction and falls back to classic decode when unbound.',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'tga',
        description:
            'User-defined address tag (passed through to the '
            'transaction record without semantic interpretation)',
      ),
      SignalBinding(
        name: 'tgd_o',
        description: 'User-defined data tag (master-to-slave)',
      ),
      SignalBinding(
        name: 'tgd_i',
        description: 'User-defined data tag (slave-to-master)',
      ),
      SignalBinding(
        name: 'tgc',
        description: 'User-defined cycle tag',
      ),
    ],
    parameters: [
      DecoderParameter(
        name: 'revision',
        displayName: 'Revision',
        labelKey: 'wishboneParamRevision',
        descriptionKey: 'wishboneParamRevisionDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: 'b3',
        enumValues: ['b3', 'b4'],
        enumLabels: {
          'b3': 'B3 (Classic + bursts)',
          'b4': 'B4 (Pipelined)',
        },
        enumLabelKeys: {
          'b3': 'wishboneChoiceRevisionB3',
          'b4': 'wishboneChoiceRevisionB4',
        },
        description:
            'Wishbone specification revision. B3 uses the held-stb '
            'classic handshake (with optional registered-feedback bursts via '
            'cti/bte); B4 uses pipelined stb pulses with stall-driven flow '
            'control.',
      ),
      DecoderParameter(
        name: 'addr_width',
        displayName: 'Address Width',
        labelKey: 'wishboneParamAddrWidth',
        descriptionKey: 'wishboneParamAddrWidthDescription',
        type: DecoderParameterType.integer,
        defaultValue: 32,
        description: 'Address bus width in bits (1..64).',
      ),
      DecoderParameter(
        name: 'data_width',
        displayName: 'Data Width',
        labelKey: 'wishboneParamDataWidth',
        descriptionKey: 'wishboneParamDataWidthDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '32',
        enumValues: ['8', '16', '32', '64'],
        description: 'Data bus port size in bits.',
      ),
      DecoderParameter(
        name: 'granularity',
        displayName: 'Granularity',
        labelKey: 'wishboneParamGranularity',
        descriptionKey: 'wishboneParamGranularityDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '8',
        enumValues: ['8', '16', '32', '64'],
        description:
            'Smallest addressable unit in bits. Combined with '
            'data_width, determines the byte-lane count for the optional sel '
            'signal and the natural address alignment.',
      ),
      DecoderParameter(
        name: 'endianness',
        displayName: 'Endianness',
        labelKey: 'wishboneParamEndianness',
        descriptionKey: 'wishboneParamEndiannessDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: 'little',
        enumValues: ['little', 'big'],
        enumLabels: {
          'little': 'Little-endian',
          'big': 'Big-endian',
        },
        enumLabelKeys: {
          'little': 'wishboneChoiceEndiannessLittle',
          'big': 'wishboneChoiceEndiannessBig',
        },
        description:
            'Byte ordering used when presenting partial-word bursts. '
            'Only affects the human-readable address sequence in burst '
            'transactions; the wire-level decode is endian-agnostic.',
      ),
      DecoderParameter(
        name: 'check_alignment',
        displayName: 'Check Address Alignment',
        labelKey: 'wishboneParamCheckAlignment',
        descriptionKey: 'wishboneParamCheckAlignmentDescription',
        type: DecoderParameterType.boolean,
        defaultValue: true,
        description:
            'Flag transactions whose address is not naturally aligned '
            'to (data_width / granularity). Industry-standard sanity check; '
            'disable for designs that intentionally drive misaligned access '
            'with explicit sel masks.',
      ),
    ],
  );

  @override
  DecoderDefinition get definition => WishboneDecoder.decoderDefinition;

  // ── decode entry point ─────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final clkChanges = changesQuery('clk', startTime, endTime);
    if (clkChanges.isEmpty) return [];

    // Sample only rising edges of clk; all Wishbone signals are sampled on
    // the rising edge of clk (B3 §3.2, B4 §3.1.3).
    final risingEdges = <int>[
      for (final (t, v) in clkChanges)
        if (isVcdHigh(v)) t,
    ];
    if (risingEdges.isEmpty) return [];

    final rev = stringParam(_config.parameters, 'revision', 'b3');
    if (rev == 'b4') {
      return _decodeB4Pipelined(risingEdges, query);
    }
    return _decodeB3(risingEdges, query);
  }

  // ── B3 Classic + Registered-Feedback Bursts ────────────────────────────────

  List<DecodedTransaction> _decodeB3(
    List<int> risingEdges,
    SignalValueQuery query,
  ) {
    final hasErr = _bound('err');
    final hasRty = _bound('rty');
    final hasSel = _bound('sel');
    final hasLock = _bound('lock');
    final hasCti = _bound('cti');
    final hasBte = _bound('bte');

    final transactions = <DecodedTransaction>[];

    // In-flight burst aggregation: when a burst is in progress we collect
    // child beats and emit a single parent transaction at burst termination.
    _BurstAccum? burst;

    int? prevWe;
    int? prevCyc;

    for (final edgeTime in risingEdges) {
      // Reset clears all in-flight state. Spec: rst is active-high.
      if (isVcdHigh(query('rst', edgeTime))) {
        if (burst != null) {
          transactions.add(burst.toParent());
          burst = null;
        }
        prevWe = prevCyc = null;
        continue;
      }

      final cyc = isVcdHigh(query('cyc', edgeTime)) ? 1 : 0;
      final stb = isVcdHigh(query('stb', edgeTime)) ? 1 : 0;
      final ackV = isVcdHigh(query('ack', edgeTime)) ? 1 : 0;
      final errV = hasErr && isVcdHigh(query('err', edgeTime)) ? 1 : 0;
      final rtyV = hasRty && isVcdHigh(query('rty', edgeTime)) ? 1 : 0;

      // Violation 3: stb asserted while cyc deasserted.
      if (stb == 1 && cyc == 0) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'STB asserted while CYC deasserted',
          ),
        );
      }

      // Violation 2: termination asserted while cyc deasserted.
      if (cyc == 0 && (ackV + errV + rtyV) > 0) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'Termination (ACK/ERR/RTY) asserted while CYC deasserted',
          ),
        );
      }

      // Violation 1: more than one termination asserted simultaneously.
      if (ackV + errV + rtyV > 1) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'Multiple terminations asserted simultaneously '
            '(ACK=$ackV ERR=$errV RTY=$rtyV)',
          ),
        );
      }

      // CYC drop ends an in-flight burst.
      if (cyc == 0) {
        if (burst != null) {
          transactions.add(burst.toParent());
          burst = null;
        }
        prevWe = null;
        prevCyc = cyc;
        continue;
      }

      // Sample addressing inputs once for this edge.
      final adr = parseVcdVectorInt(query('adr', edgeTime));
      final we = isVcdHigh(query('we', edgeTime)) ? 1 : 0;
      final selV = hasSel ? parseVcdVectorInt(query('sel', edgeTime)) : null;
      final datO = parseVcdVectorInt(query('dat_o', edgeTime));
      final cti = hasCti ? parseVcdVectorInt(query('cti', edgeTime)) : null;
      final bte = hasBte ? parseVcdVectorInt(query('bte', edgeTime)) : null;

      // Violation 4: WE changes while CYC remains asserted (across edges).
      if (prevCyc == 1 && prevWe != null && we != prevWe) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'WE changed mid-cycle (was $prevWe, now $we) without CYC dropping',
          ),
        );
      }

      // Violation 8: reserved CTI value (only meaningful when bound).
      if (cti != null && _isReservedCti(cti)) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'Reserved CTI value 0b${cti.toRadixString(2).padLeft(3, '0')} '
            '(allowed: 000 Classic, 001 Const, 010 Incr, 111 EOB)',
          ),
        );
      }

      // Violation 9: BTE non-zero with a CTI that doesn't accept BTE.
      // Allowed: CTI=010 (incrementing burst, BTE selects wrap modulus),
      // CTI=111 (end-of-burst — BTE is permissibly held over from the
      // matching CTI=010 beat). Flagged: CTI=000 Classic and CTI=001
      // constant-address burst, where BTE has no defined meaning.
      if (cti != null &&
          bte != null &&
          bte != 0 &&
          (cti == 0x0 || cti == 0x1)) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'BTE=0b${bte.toRadixString(2).padLeft(2, '0')} with CTI=0b'
            '${cti.toRadixString(2).padLeft(3, '0')} '
            '(BTE only meaningful for incrementing bursts)',
          ),
        );
      }

      // Beat completion: stb high & exactly one termination this edge.
      final terminated = (ackV + errV + rtyV) == 1;
      if (stb == 1 && terminated) {
        final term = ackV == 1
            ? _Term.ack
            : (errV == 1 ? _Term.err : _Term.rty);

        final isWrite = we == 1;
        final dataAtBeat = isWrite
            ? datO
            : parseVcdVectorInt(query('dat_i', edgeTime));

        // Determine cycle type for this beat.
        final cycleType = _b3CycleTypeFor(cti);

        // Violation 6: const-addr burst, address changed beat-to-beat.
        if (burst != null &&
            burst.cti == 0x1 &&
            adr != null &&
            burst.lastAdr != null &&
            adr != burst.lastAdr) {
          transactions.add(
            _violation(
              edgeTime,
              edgeTime,
              'Constant-address burst (CTI=001) but ADR changed '
              'from ${_fmtAddr(burst.lastAdr)} to ${_fmtAddr(adr)}',
            ),
          );
        }

        // Violation 7: incrementing burst rule violations.
        if (burst != null && burst.cti == 0x2) {
          if (we != burst.we) {
            transactions.add(
              _violation(
                edgeTime,
                edgeTime,
                'Incrementing burst (CTI=010) but WE changed beat-to-beat',
              ),
            );
          }
          if (hasSel && selV != burst.sel) {
            transactions.add(
              _violation(
                edgeTime,
                edgeTime,
                'Incrementing burst (CTI=010) but SEL changed beat-to-beat',
              ),
            );
          }
          if (adr != null && burst.lastAdr != null) {
            final stride = _bytesPerBeat();
            final expectedNext = _wrapBurstAdr(
              burst.firstAdr ?? burst.lastAdr!,
              burst.lastAdr! + stride,
              burst.bte ?? 0,
              stride,
            );
            if (adr != expectedNext) {
              transactions.add(
                _violation(
                  edgeTime,
                  edgeTime,
                  'Incrementing burst (CTI=010, BTE=${burst.bte}) but ADR '
                  'jumped from ${_fmtAddr(burst.lastAdr)} '
                  'to ${_fmtAddr(adr)} (expected ${_fmtAddr(expectedNext)})',
                ),
              );
            }
          }
        }

        // Open a new burst BEFORE building the beat, so the first beat
        // carries burst_id / beat_index in its fields. Violation checks 6/7
        // above already ran against the prior `burst` state, so this
        // reassignment doesn't disturb them.
        // The `cti!` is safe — the equality check guarantees non-null but
        // Dart's flow analysis doesn't promote on `==`.
        if ((cti == 0x1 || cti == 0x2) && burst == null) {
          burst = _BurstAccum(
            id: 'b3-$edgeTime',
            cti: cti!,
            bte: bte,
            we: we,
            sel: selV,
            firstAdr: adr,
          );
        }

        // Build the beat transaction with current burst metadata.
        final beat = _buildBeat(
          startTime: edgeTime,
          endTime: edgeTime,
          isWrite: isWrite,
          adr: adr,
          data: dataAtBeat,
          term: term,
          sel: hasSel ? selV : null,
          lock: hasLock ? (isVcdHigh(query('lock', edgeTime)) ? 1 : 0) : null,
          cycleType: cycleType,
          burstId: burst?.id,
          beatIndex: burst != null ? burst.beats.length + 1 : null,
          cti: cti,
          bte: bte,
          tags: _sampleTags(query, edgeTime),
        );
        transactions.add(beat);

        // Append this beat to its burst, and close the burst on EOB.
        if (burst != null && (cti == 0x1 || cti == 0x2 || cti == 0x7)) {
          burst.beats.add(beat);
          burst.lastAdr = adr;
          if (cti == 0x7) {
            transactions.add(burst.toParent());
            burst = null;
          }
        }
      }

      // Violation 10: address-misalignment (gated by check_alignment).
      if (terminated && adr != null && _checkAlignment) {
        final stride = _bytesPerBeat();
        if (stride > 1 && adr % stride != 0) {
          transactions.add(
            _violation(
              edgeTime,
              edgeTime,
              'Misaligned address ${_fmtAddr(adr)} for stride $stride bytes '
              '(data_width=$_dataWidth, granularity=$_granularity)',
            ),
          );
        }
      }

      prevWe = we;
      prevCyc = cyc;
    }

    // Cycle still in flight at end of trace: finalize burst if any.
    if (burst != null) {
      transactions.add(burst.toParent());
    }

    // Sort by start time, tie-breaking on endTime so burst-parent records
    // (which span the whole burst) sort after their child beats. This keeps
    // the emitted order deterministic and easy to read in the table view.
    transactions.sort((a, b) {
      final byStart = a.startTime.compareTo(b.startTime);
      if (byStart != 0) return byStart;
      return a.endTime.compareTo(b.endTime);
    });
    return transactions;
  }

  // ── B4 Pipelined ───────────────────────────────────────────────────────────

  List<DecodedTransaction> _decodeB4Pipelined(
    List<int> risingEdges,
    SignalValueQuery query,
  ) {
    final hasErr = _bound('err');
    final hasRty = _bound('rty');
    final hasSel = _bound('sel');
    final hasLock = _bound('lock');
    final hasStall = _bound('stall');

    final transactions = <DecodedTransaction>[];

    // If stall isn't bound, emit a single warning and fall back to classic
    // decode — pipelined-mode flow control is unobservable without it.
    if (!hasStall) {
      transactions
        ..add(
          _violation(
            risingEdges.first,
            risingEdges.first,
            'Wishbone B4 selected but `stall` signal not bound — bind it for '
            'accurate pipelined decode. Falling back to classic decode.',
          ),
        )
        ..addAll(_decodeB3(risingEdges, query));
      return transactions;
    }

    final outstanding = <_PipelinedRequest>[];

    int? prevAdr;
    int? prevSel;
    int? prevDatO;
    int? prevWe;
    var prevStb = 0;
    var prevStall = 0;

    for (final edgeTime in risingEdges) {
      if (isVcdHigh(query('rst', edgeTime))) {
        outstanding.clear();
        prevAdr = prevSel = prevDatO = prevWe = null;
        prevStb = prevStall = 0;
        continue;
      }

      final cyc = isVcdHigh(query('cyc', edgeTime)) ? 1 : 0;
      final stb = isVcdHigh(query('stb', edgeTime)) ? 1 : 0;
      final stallV = isVcdHigh(query('stall', edgeTime)) ? 1 : 0;
      final ackV = isVcdHigh(query('ack', edgeTime)) ? 1 : 0;
      final errV = hasErr && isVcdHigh(query('err', edgeTime)) ? 1 : 0;
      final rtyV = hasRty && isVcdHigh(query('rty', edgeTime)) ? 1 : 0;

      // Violation 1: mutex on terminations.
      if (ackV + errV + rtyV > 1) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'Multiple terminations asserted simultaneously '
            '(ACK=$ackV ERR=$errV RTY=$rtyV)',
          ),
        );
      }

      // Violation 2: termination without CYC.
      if (cyc == 0 && (ackV + errV + rtyV) > 0) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'Termination asserted while CYC deasserted',
          ),
        );
      }

      // Violation 3: STB without CYC.
      if (stb == 1 && cyc == 0) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'STB asserted while CYC deasserted',
          ),
        );
      }

      final adr = parseVcdVectorInt(query('adr', edgeTime));
      final we = isVcdHigh(query('we', edgeTime)) ? 1 : 0;
      final selV = hasSel ? parseVcdVectorInt(query('sel', edgeTime)) : null;
      final datO = parseVcdVectorInt(query('dat_o', edgeTime));

      // Violation 5: signal change while STB asserted and STALL high.
      // The master must repeat its outputs across stalled cycles.
      if (prevStb == 1 && prevStall == 1 && stb == 1) {
        final changes = <String>[];
        if (prevAdr != adr) changes.add('ADR');
        if (prevWe != we) changes.add('WE');
        if (hasSel && prevSel != selV) changes.add('SEL');
        if (we == 1 && prevDatO != datO) changes.add('DAT_O');
        if (changes.isNotEmpty) {
          transactions.add(
            _violation(
              edgeTime,
              edgeTime,
              'Signal(s) ${changes.join("/")} changed while STB asserted '
              'and STALL high (master must repeat outputs across stalled '
              'cycles)',
            ),
          );
        }
      }

      // Accept request: STB & CYC & ~STALL → enqueue.
      if (cyc == 1 && stb == 1 && stallV == 0) {
        outstanding.add(
          _PipelinedRequest(
            startTime: edgeTime,
            isWrite: we == 1,
            adr: adr,
            datOutAtIssue: datO,
            sel: hasSel ? selV : null,
            lock: hasLock ? (isVcdHigh(query('lock', edgeTime)) ? 1 : 0) : null,
            tags: _sampleTags(query, edgeTime),
          ),
        );
      }

      // Termination → match against head of FIFO.
      if (cyc == 1 && (ackV + errV + rtyV) == 1) {
        if (outstanding.isEmpty) {
          transactions.add(
            _violation(
              edgeTime,
              edgeTime,
              'Termination with no outstanding pipelined request '
              '(spurious ACK/ERR/RTY)',
            ),
          );
        } else {
          final req = outstanding.removeAt(0);
          final term = ackV == 1
              ? _Term.ack
              : (errV == 1 ? _Term.err : _Term.rty);
          final dataResult = req.isWrite
              ? req.datOutAtIssue
              : parseVcdVectorInt(query('dat_i', edgeTime));
          transactions.add(
            _buildBeat(
              startTime: req.startTime,
              endTime: edgeTime,
              isWrite: req.isWrite,
              adr: req.adr,
              data: dataResult,
              term: term,
              sel: req.sel,
              lock: req.lock,
              cycleType: 'Pipelined',
              burstId: null,
              beatIndex: null,
              cti: null,
              bte: null,
              tags: req.tags,
              latencyCycles: edgeTime - req.startTime,
            ),
          );
        }
      }

      // Violation 10: address misalignment at issue time.
      if (cyc == 1 &&
          stb == 1 &&
          stallV == 0 &&
          adr != null &&
          _checkAlignment) {
        final stride = _bytesPerBeat();
        if (stride > 1 && adr % stride != 0) {
          transactions.add(
            _violation(
              edgeTime,
              edgeTime,
              'Misaligned address ${_fmtAddr(adr)} for stride $stride bytes '
              '(data_width=$_dataWidth, granularity=$_granularity)',
            ),
          );
        }
      }

      // Cycle drop while still outstanding: spec says master must wait for
      // the last ack before negating CYC. Flag and discard pending.
      if (cyc == 0 && outstanding.isNotEmpty) {
        transactions.add(
          _violation(
            edgeTime,
            edgeTime,
            'CYC dropped with ${outstanding.length} outstanding pipelined '
            'request(s) — spec requires waiting for the final ACK',
          ),
        );
        outstanding.clear();
      }

      prevAdr = adr;
      prevSel = selV;
      prevDatO = datO;
      prevWe = we;
      prevStb = stb;
      prevStall = stallV;
    }

    // Sort by start time, tie-breaking on endTime so burst-parent records
    // (which span the whole burst) sort after their child beats. This keeps
    // the emitted order deterministic and easy to read in the table view.
    transactions.sort((a, b) {
      final byStart = a.startTime.compareTo(b.startTime);
      if (byStart != 0) return byStart;
      return a.endTime.compareTo(b.endTime);
    });
    return transactions;
  }

  // ── transaction emission ───────────────────────────────────────────────────

  DecodedTransaction _buildBeat({
    required int startTime,
    required int endTime,
    required bool isWrite,
    required int? adr,
    required int? data,
    required _Term term,
    required int? sel,
    required int? lock,
    required String cycleType,
    required String? burstId,
    required int? beatIndex,
    required int? cti,
    required int? bte,
    required Map<String, int?> tags,
    int? latencyCycles,
  }) {
    final addrStr = _fmtAddr(adr);
    final dataStr = _fmtData(data);
    final termStr = term.label;
    final isError = term != _Term.ack;

    final beatLabel = beatIndex != null
        ? ' [$cycleType $beatIndex]'
        : (cycleType == 'Classic' ? '' : ' [$cycleType]');

    final label = isWrite
        ? (isError
              ? 'W $addrStr = $dataStr [$termStr]$beatLabel'
              : 'W $addrStr = $dataStr$beatLabel')
        : (isError
              ? 'R $addrStr → $dataStr [$termStr]$beatLabel'
              : 'R $addrStr → $dataStr$beatLabel');

    final fields = <String, String>{
      'type': isWrite ? 'Write' : 'Read',
      'cycle': cycleType,
      'address': addrStr,
      'data': dataStr,
      'termination': termStr,
      if (latencyCycles != null) 'latency': latencyCycles.toString(),
      if (sel != null) 'sel': '0x${sel.toRadixString(16).toUpperCase()}',
      if (lock != null && lock == 1) 'lock': '1',
      'burst_id': ?burstId,
      if (beatIndex != null) 'beat_index': beatIndex.toString(),
      if (cti != null) 'cti': '0b${cti.toRadixString(2).padLeft(3, '0')}',
      if (bte != null) 'bte': '0b${bte.toRadixString(2).padLeft(2, '0')}',
      ...{
        for (final entry in tags.entries)
          if (entry.value != null)
            entry.key: '0x${entry.value!.toRadixString(16).toUpperCase()}',
      },
    };

    return DecodedTransaction(
      startTime: startTime,
      endTime: endTime,
      label: label,
      fields: fields,
      isError: isError,
      errorMessage: isError ? 'Termination = $termStr' : null,
    );
  }

  DecodedTransaction _violation(int startTime, int endTime, String msg) =>
      DecodedTransaction(
        startTime: startTime,
        endTime: endTime,
        label: 'Wishbone Violation',
        fields: {'error': msg},
        isError: true,
        errorMessage: msg,
      );

  Map<String, int?> _sampleTags(SignalValueQuery query, int t) => {
    if (_bound('tga')) 'tga': parseVcdVectorInt(query('tga', t)),
    if (_bound('tgd_o')) 'tgd_o': parseVcdVectorInt(query('tgd_o', t)),
    if (_bound('tgd_i')) 'tgd_i': parseVcdVectorInt(query('tgd_i', t)),
    if (_bound('tgc')) 'tgc': parseVcdVectorInt(query('tgc', t)),
  };

  // ── helpers: spec-derived semantics ────────────────────────────────────────

  static bool _isReservedCti(int cti) =>
      cti == 0x3 || cti == 0x4 || cti == 0x5 || cti == 0x6;

  static String _b3CycleTypeFor(int? cti) {
    if (cti == null) return 'Classic';
    switch (cti) {
      case 0x0:
        return 'Classic';
      case 0x1:
        return 'Burst-Const';
      case 0x2:
        return 'Burst-Incr';
      case 0x7:
        return 'Burst-EOB';
      default:
        return 'Classic'; // reserved values fall back; violation flagged.
    }
  }

  /// Computes the next address inside a registered-feedback burst.
  ///
  /// [firstAdr] is the address of the first beat of the burst — it
  /// determines the wrap window's high-bit base, which stays constant
  /// across the burst. [nextLinear] is the prospective next address if
  /// no wrap occurred ([prevAdr] + [stride]).
  ///
  /// BTE encoding (B3 §4.2 Table 4-3):
  ///   00 → linear (no wrap)
  ///   01 → 4-beat wrap
  ///   10 → 8-beat wrap
  ///   11 → 16-beat wrap
  ///
  /// Only the low `log2(beats * stride)` bits cycle within the burst
  /// window; higher bits are fixed by `firstAdr`.
  static int _wrapBurstAdr(int firstAdr, int nextLinear, int bte, int stride) {
    if (bte == 0) return nextLinear;
    final beats = bte == 1 ? 4 : (bte == 2 ? 8 : 16);
    final window = beats * stride;
    final base = firstAdr - (firstAdr % window);
    return base + ((nextLinear - base) % window);
  }

  // ── helpers: parameters and bindings ───────────────────────────────────────

  bool _bound(String name) => _config.signalBindings.containsKey(name);

  int get _addrWidth => intParam(_config.parameters, 'addr_width', 32);
  int get _dataWidth => intParam(_config.parameters, 'data_width', 32);
  int get _granularity => intParam(_config.parameters, 'granularity', 8);
  bool get _checkAlignment =>
      boolParam(_config.parameters, 'check_alignment', true);

  int _bytesPerBeat() => (_dataWidth + 7) ~/ 8;

  // ── helpers: VCD value formatting ──────────────────────────────────────────

  String _fmtAddr(int? val) {
    if (val == null) return '0x${'?' * ((_addrWidth + 3) >> 2)}';
    final nibbles = (_addrWidth + 3) >> 2;
    return '0x${val.toRadixString(16).toUpperCase().padLeft(nibbles, '0')}';
  }

  String _fmtData(int? val) {
    if (val == null) return '0x${'?' * ((_dataWidth + 3) >> 2)}';
    final nibbles = (_dataWidth + 3) >> 2;
    return '0x${val.toRadixString(16).toUpperCase().padLeft(nibbles, '0')}';
  }
}

// ── internal types ───────────────────────────────────────────────────────────

enum _Term {
  ack('ACK'),
  err('ERR'),
  rty('RTY');

  const _Term(this.label);
  final String label;
}

class _BurstAccum {
  _BurstAccum({
    required this.id,
    required this.cti,
    required this.bte,
    required this.we,
    required this.sel,
    required this.firstAdr,
  }) : lastAdr = firstAdr;

  final String id;
  final int cti;
  final int? bte;
  final int we;
  final int? sel;
  final int? firstAdr;
  int? lastAdr;
  final List<DecodedTransaction> beats = [];

  DecodedTransaction toParent() {
    final start = beats.isEmpty ? 0 : beats.first.startTime;
    final end = beats.isEmpty ? start : beats.last.endTime;
    final isWrite = we == 1;
    final ctiLabel = cti == 0x1 ? 'Burst-Const' : 'Burst-Incr';
    final bteLabel = (cti == 0x2 && bte != null && bte != 0)
        ? (bte == 1 ? '/Wrap-4' : (bte == 2 ? '/Wrap-8' : '/Wrap-16'))
        : '';
    final dirLabel = isWrite ? 'W' : 'R';
    final addrSpan = beats.isEmpty
        ? '?'
        : (cti == 0x1
              ? _hexOf(firstAdr)
              : '${_hexOf(firstAdr)}..${_hexOf(_extractAdr(beats.last))}');
    final hasErr = beats.any((b) => b.isError);

    return DecodedTransaction(
      startTime: start,
      endTime: end,
      label:
          '$ctiLabel$bteLabel ${beats.length}× $dirLabel $addrSpan'
          '${hasErr ? ' [contains-error]' : ''}',
      fields: {
        'type': 'Burst',
        'cycle': '$ctiLabel$bteLabel',
        'beats': beats.length.toString(),
        'first_address': _hexOf(firstAdr) ?? '0x?',
        'last_address': beats.isEmpty
            ? '?'
            : _hexOf(_extractAdr(beats.last)) ?? '0x?',
        'direction': isWrite ? 'Write' : 'Read',
        'burst_id': id,
        if (bte != null) 'bte': '0b${bte!.toRadixString(2).padLeft(2, '0')}',
      },
      isError: hasErr,
      errorMessage: hasErr ? 'Burst contains terminated beat(s)' : null,
    );
  }

  static String? _hexOf(int? v) =>
      v == null ? null : '0x${v.toRadixString(16).toUpperCase()}';

  static int? _extractAdr(DecodedTransaction beat) {
    final s = beat.fields['address'];
    if (s == null) return null;
    if (s.startsWith('0x')) {
      return int.tryParse(s.substring(2), radix: 16);
    }
    return int.tryParse(s);
  }
}

class _PipelinedRequest {
  _PipelinedRequest({
    required this.startTime,
    required this.isWrite,
    required this.adr,
    required this.datOutAtIssue,
    required this.sel,
    required this.lock,
    required this.tags,
  });

  final int startTime;
  final bool isWrite;
  final int? adr;
  final int? datOutAtIssue;
  final int? sel;
  final int? lock;
  final Map<String, int?> tags;
}
