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

/// Decodes ARM AMBA AHB-Lite (Advanced High-performance Bus Lite) bus
/// transactions.
///
/// AHB-Lite is the single-master simplification of full AHB introduced in
/// AMBA 3 (Arm IHI 0033). It keeps the two-phase pipelined transfer model
/// (one-cycle address phase, one-or-more-cycle data phase, controlled by
/// `HREADY` from the slave) but drops bus arbitration and the four-state
/// `HRESP` encoding — `HRESP` becomes a single bit (OKAY / ERROR).
///
/// Pipeline summary (per IHI 0033 §3.1):
///
/// - Master drives `HADDR`/`HTRANS`/`HWRITE`/`HSIZE`/`HBURST` (and the
///   optional `HPROT`/`HMASTLOCK`) for transfer N during cycle [t-1, t].
///   At rising edge `t` the slave latches them and the transfer enters its
///   data phase.
/// - Data phase of transfer N occupies cycle [t, t+1]. `HWDATA` (writes) /
///   `HRDATA` (reads) and `HRESP` are sampled at edge `t+1` together with
///   `HREADY`. If `HREADY = 1` the data phase completes; if `HREADY = 0`
///   the slave inserts a wait state and both phases are extended.
///
/// `HTRANS` encoding (IHI 0033 §3.5):
///   00 IDLE — no transfer
///   01 BUSY — master is in a burst but cannot present the next beat
///   10 NONSEQ — first transfer of a burst (or a SINGLE)
///   11 SEQ — continuation of the current burst
///
/// `HBURST` encoding (IHI 0033 §3.7):
///   000 SINGLE — one transfer
///   001 INCR — incrementing burst of undefined length
///   010 WRAP4 / 011 INCR4 — 4-beat wrapping / incrementing
///   100 WRAP8 / 101 INCR8 — 8-beat wrapping / incrementing
///   110 WRAP16 / 111 INCR16 — 16-beat wrapping / incrementing
///
/// `HSIZE` encoding (IHI 0033 §3.6) — `1 << HSIZE` byte transfer width:
///   000 byte (8 bit), 001 halfword (16 bit), 010 word (32 bit),
///   011 doubleword (64 bit), 100 4-word (128 bit), 101 8-word (256 bit),
///   110 16-word (512 bit), 111 32-word (1024 bit).
///
/// `HRESP` (IHI 0033 §3.8): 0 = OKAY, 1 = ERROR. The two-cycle ERROR
/// response sequence is detected: cycle N has `HREADY=0,HRESP=1`; cycle
/// N+1 has `HREADY=1,HRESP=1` — the data phase completes at N+1 with
/// `response = ERROR`. An ERROR response that violates this two-cycle
/// pattern (e.g. HREADY=1 paired with HRESP=1 on the very first cycle of
/// the data phase, with no preceding HREADY=0,HRESP=1) is flagged as a
/// protocol violation.
///
/// `HPROT` (IHI 0033 §3.9, optional binding): 4-bit access attribute,
/// surfaced informationally on each transaction:
///   bit 0 = data (1) / instruction (0)
///   bit 1 = privileged (1) / user (0)
///   bit 2 = bufferable (1) / non-bufferable (0)
///   bit 3 = cacheable (1) / non-cacheable (0)
///
/// `HMASTLOCK` (IHI 0033 §3.10, optional binding): 1-bit indicator that
/// the current transfer is part of a locked sequence (read-modify-write,
/// atomic primitive). Surfaced on each transaction; bursts with
/// `HMASTLOCK = 1` carry the flag on every beat AND on the parent record.
///
/// Per-instance configuration (`addr_width`, `data_width`,
/// `check_alignment`, `wait_state_threshold`) is read from the
/// [DecoderConfig.parameters] map every call to [decode] — sessions
/// persist the parameter map alongside the signal bindings.
///
/// Bursts are emitted as one parent transaction spanning the full burst
/// plus one child beat per transfer; the `burst_id` field links them.
/// This matches the AXI4 and Wishbone parent-with-burst_id model.
///
/// Protocol violations detected (each fires a flagged DecodedTransaction
/// with `isError = true` and a human-readable `errorMessage`):
///
/// 1. `HTRANS = BUSY` while the active burst is `SINGLE`. BUSY is only
///    valid inside multi-beat bursts (IHI 0033 §3.5).
/// 2. `HTRANS = SEQ` without a preceding `NONSEQ` in the same burst. SEQ
///    requires an active burst already opened by NONSEQ (IHI 0033 §3.5).
/// 3. `HBURST` value changes between beats of an in-flight burst. The
///    burst type is fixed at the NONSEQ beat (IHI 0033 §3.7).
/// 4. `HADDR` does not follow the burst's address-increment rule for the
///    next beat (INCR* and WRAP* sequences). Computed as
///    `prev + (1 << HSIZE)` for INCR* and the wrap-modulus rule for
///    WRAP* (IHI 0033 §3.7).
/// 5. `HSIZE` encodes a transfer wider than the configured `data_width`
///    parameter. Slaves may drop the bus down to handle wider sizes, but
///    a master driving HSIZE > data port width is a configuration bug.
/// 6. `HADDR` not naturally aligned to `1 << HSIZE`. Gated by the
///    `check_alignment` parameter — disable for designs that intentionally
///    drive misaligned access. Also catches WRAP bursts whose first beat
///    is misaligned to the transfer size (the spec only requires
///    HSIZE-alignment of the start; the wrap window is implicitly
///    aligned to `beats * (1 << HSIZE)` and the burst wraps within it).
/// 7. `HRESP = ERROR` with `HREADY = 1` on the very first cycle of the
///    data phase (no preceding HREADY=0,HRESP=ERROR cycle). Spec requires
///    the two-cycle ERROR response (IHI 0033 §3.8.2).
/// 8. `HREADY` held low for more than `wait_state_threshold` consecutive
///    cycles. Soft warning surfaced as a flagged transaction with
///    `errorMessage` prefix `warn:` so users can filter them out.
///
/// Spec-derived address-phase-signal stability across wait states
/// (master must hold HADDR/HTRANS/HSIZE/HBURST/HPROT/HMASTLOCK stable
/// while HREADY=0, IHI 0033 §3.4) is **not** detected by this decoder.
/// The single-edge pipeline model captures the in-flight transfer at
/// the same edge that begins its data phase, so the address-phase
/// signals during a subsequent wait state are not directly comparable
/// to a held reference. A decoder operating on the strict two-phase
/// pipeline could detect this violation; the value of doing so on
/// observed waveforms (vs. the simulator's own assertion checks) is
/// marginal.
class AhbLiteDecoder implements ProtocolDecoder {
  /// Creates an [AhbLiteDecoder] bound to [config].
  const AhbLiteDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  /// Static metadata registered with `DecoderRegistry` at app startup.
  static const decoderDefinition = DecoderDefinition(
    id: 'ahb_lite',
    displayName: 'AHB-Lite',
    description:
        'Decodes ARM AMBA AHB-Lite (single-master) transactions. '
        'Two-phase pipelined transfers, all HBURST variants (SINGLE / INCR '
        '/ INCR4 / WRAP4 / INCR8 / WRAP8 / INCR16 / WRAP16), HSIZE up to '
        '1024-bit, single-bit HRESP with two-cycle ERROR handshake, '
        'optional HPROT / HMASTLOCK, configurable address and data widths.',
    category: DecoderCategory.amba,
    requiredSignals: [
      SignalBinding(
        name: 'hclk',
        description:
            'Bus clock (rising-edge sampled). All AHB-Lite signals '
            'are sampled on the rising edge of HCLK (IHI 0033 §3.1).',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'hresetn',
        description:
            'Active-low reset (IHI 0033 §3.2). The decoder treats '
            'HRESETn=0 as reset; bind an inverted net for active-high '
            'designs.',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'haddr',
        description:
            'Address bus; width comes from the addr_width '
            'parameter. Sampled at the rising edge that ends the address '
            'phase.',
      ),
      SignalBinding(
        name: 'htrans',
        description:
            'Transfer type (2-bit). 00 IDLE, 01 BUSY, '
            '10 NONSEQ, 11 SEQ (IHI 0033 §3.5).',
        bitWidth: 2,
      ),
      SignalBinding(
        name: 'hwrite',
        description: 'Write enable (1 = write, 0 = read).',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'hsize',
        description:
            'Transfer size (3-bit). 1 << HSIZE bytes per beat: '
            '000 byte, 001 halfword, 010 word, 011 doubleword, … '
            '111 32-word (IHI 0033 §3.6).',
        bitWidth: 3,
      ),
      SignalBinding(
        name: 'hburst',
        description:
            'Burst type (3-bit). 000 SINGLE, 001 INCR, '
            '010 WRAP4, 011 INCR4, 100 WRAP8, 101 INCR8, '
            '110 WRAP16, 111 INCR16 (IHI 0033 §3.7).',
        bitWidth: 3,
      ),
      SignalBinding(
        name: 'hwdata',
        description:
            'Master-to-slave write data; width comes from the '
            'data_width parameter. Sampled at the rising edge that '
            'completes the data phase (HREADY high).',
      ),
      SignalBinding(
        name: 'hrdata',
        description:
            'Slave-to-master read data; width comes from the '
            'data_width parameter. Sampled at the rising edge that '
            'completes the data phase (HREADY high).',
      ),
      SignalBinding(
        name: 'hready',
        description:
            'Slave-driven ready/wait signal. HREADY=1 ends the '
            'data phase that was active during the preceding cycle; '
            'HREADY=0 inserts a wait state (IHI 0033 §3.3).',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'hresp',
        description:
            'Response (1-bit, AHB-Lite simplification of full '
            'AHB). 0 = OKAY, 1 = ERROR. ERROR uses the two-cycle '
            'handshake (IHI 0033 §3.8).',
        bitWidth: 1,
      ),
    ],
    optionalSignals: [
      SignalBinding(
        name: 'hprot',
        description:
            'Protection control (4-bit, IHI 0033 §3.9). '
            'bit0=data/instr, bit1=privileged/user, bit2=bufferable, '
            'bit3=cacheable. Decoded informationally per beat.',
        bitWidth: 4,
      ),
      SignalBinding(
        name: 'hmastlock',
        description:
            'Locked transfer indicator (1-bit, IHI 0033 §3.10). '
            'Asserted high for the full duration of an atomic '
            'read-modify-write or other indivisible sequence.',
        bitWidth: 1,
      ),
    ],
    parameters: [
      DecoderParameter(
        name: 'addr_width',
        displayName: 'Address Width',
        labelKey: 'ahbLiteParamAddrWidth',
        descriptionKey: 'ahbLiteParamAddrWidthDescription',
        type: DecoderParameterType.integer,
        defaultValue: 32,
        description:
            'Address bus width in bits (1..64). Used for hex '
            'formatting of HADDR and for the misalignment check.',
      ),
      DecoderParameter(
        name: 'data_width',
        displayName: 'Data Width',
        labelKey: 'ahbLiteParamDataWidth',
        descriptionKey: 'ahbLiteParamDataWidthDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '32',
        enumValues: ['8', '16', '32', '64', '128', '256', '512', '1024'],
        description:
            'Data bus port width in bits. Caps the legal HSIZE '
            'encoding (HSIZE wider than this triggers violation 5) and '
            'sets the hex-nibble width of HWDATA / HRDATA.',
      ),
      DecoderParameter(
        name: 'check_alignment',
        displayName: 'Check Address Alignment',
        labelKey: 'ahbLiteParamCheckAlignment',
        descriptionKey: 'ahbLiteParamCheckAlignmentDescription',
        type: DecoderParameterType.boolean,
        defaultValue: true,
        description:
            'Flag transfers whose HADDR is not naturally aligned '
            'to (1 << HSIZE) bytes (violation 6). Disable for designs '
            'that intentionally drive misaligned access.',
      ),
      DecoderParameter(
        name: 'wait_state_threshold',
        displayName: 'Wait-state Warning Threshold',
        labelKey: 'ahbLiteParamWaitStateThreshold',
        descriptionKey: 'ahbLiteParamWaitStateThresholdDescription',
        type: DecoderParameterType.integer,
        defaultValue: 256,
        description:
            'Number of consecutive HREADY=0 cycles after which '
            'the decoder emits a soft warning (violation 8). Helpful '
            'for catching slaves that have stalled the bus indefinitely. '
            'Set to a large value to suppress warnings.',
      ),
    ],
  );

  @override
  DecoderDefinition get definition => AhbLiteDecoder.decoderDefinition;

  // ── decode entry point ─────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final clkChanges = changesQuery('hclk', startTime, endTime);
    if (clkChanges.isEmpty) return [];

    // Sample only rising edges of HCLK; AHB-Lite is synchronous to the
    // rising edge throughout (IHI 0033 §3.1).
    final risingEdges = <int>[
      for (final (t, v) in clkChanges)
        if (isVcdHigh(v)) t,
    ];
    if (risingEdges.isEmpty) return [];

    return _runPipeline(risingEdges, query);
  }

  // ── single-edge pipeline state machine ─────────────────────────────────────
  //
  // The decoder collapses the two-phase AHB-Lite pipeline into a single-edge
  // model: at each rising HCLK edge, an in-flight transfer (if any) is
  // completed using that edge's HREADY/HRESP/HWDATA/HRDATA values, and the
  // current edge's address-phase signals (HTRANS != IDLE) are immediately
  // captured as the new in-flight transfer. This effectively merges the
  // address-phase capture and the data-phase entry into one step.
  //
  // Why single-edge instead of a separate prevAddr buffer mirroring the
  // hardware pipeline: the simplification keeps the decoder readable, makes
  // back-to-back authoring tractable (each fixture frame neatly carries one
  // cycle's signals — the new transfer's address phase plus the previous
  // transfer's data values arriving at the same edge), and produces the
  // same transactions with the same field values. The cost is a 1-cycle
  // phase shift relative to absolute IHI 0033 timing, which is invisible
  // to the user — they still see correct addresses, data, responses, and
  // can correlate transactions to bus activity.

  List<DecodedTransaction> _runPipeline(
    List<int> risingEdges,
    SignalValueQuery query,
  ) {
    final hasHprot = _bound('hprot');
    final hasHmastlock = _bound('hmastlock');

    final transactions = <DecodedTransaction>[];

    // `inFlight` is the transfer currently in its data phase. Its
    // HWDATA / HRDATA / HRESP are sampled at the next edge with HREADY = 1.
    _AddressPhase? inFlight;
    var dataPhaseStart = 0;
    var waitStates = 0;

    // Burst accumulator: open when a NONSEQ beat is captured with
    // HBURST != SINGLE; closed when the burst's expected last beat
    // completes, or when HTRANS goes IDLE/NONSEQ-of-new-burst.
    _BurstAccum? burst;

    // Two-cycle ERROR response tracker: when the slave drives
    // (HREADY=0, HRESP=1) for the in-flight transfer, this records the
    // edge time so the next-cycle (HREADY=1, HRESP=1) is recognised as
    // the spec-mandated completion handshake rather than a violation.
    int? errorPhase1Edge;

    // Wait-state warning: number of consecutive HREADY=0 cycles seen
    // (regardless of in-flight identity). Reset on every HREADY=1 edge.
    var consecWaitLow = 0;
    var waitWarningFiredAt = -1;

    for (final edgeTime in risingEdges) {
      // ── reset ────────────────────────────────────────────────────────────
      if (!isVcdHigh(query('hresetn', edgeTime))) {
        if (burst != null) {
          transactions.add(burst.toParent());
          burst = null;
        }
        inFlight = null;
        dataPhaseStart = 0;
        waitStates = 0;
        errorPhase1Edge = null;
        consecWaitLow = 0;
        waitWarningFiredAt = -1;
        continue;
      }

      final hready = isVcdHigh(query('hready', edgeTime));
      final hresp = isVcdHigh(query('hresp', edgeTime));

      // ── wait-state warning (violation 8) ─────────────────────────────────
      if (!hready) {
        consecWaitLow++;
        if (consecWaitLow > _waitStateThreshold &&
            waitWarningFiredAt != edgeTime) {
          transactions.add(
            _warning(
              edgeTime,
              edgeTime,
              'HREADY held low for $consecWaitLow consecutive cycles '
              '(threshold $_waitStateThreshold). Slave may have '
              'stalled the bus indefinitely.',
            ),
          );
          waitWarningFiredAt = edgeTime;
        }
      } else {
        consecWaitLow = 0;
      }

      // ── complete in-flight data phase ────────────────────────────────────
      if (inFlight != null) {
        if (hready) {
          var twoCycleOk = true;
          if (hresp) {
            twoCycleOk = errorPhase1Edge != null;
          }

          final dataVal = inFlight.isWrite
              ? parseVcdVectorInt(query('hwdata', edgeTime))
              : parseVcdVectorInt(query('hrdata', edgeTime));

          final beat = _buildBeat(
            phase: inFlight,
            data: dataVal,
            isError: hresp,
            twoCycleErrorOk: twoCycleOk,
            waitStates: waitStates,
            dataPhaseStart: dataPhaseStart,
            dataPhaseEnd: edgeTime,
            burstId: burst?.id,
            beatIndex: burst != null ? burst.beats.length + 1 : null,
          );
          transactions.add(beat);

          if (burst != null) {
            burst.beats.add(beat);
            burst.lastAddr = inFlight.haddr;
            if (burst.expectedBeats != null &&
                burst.beats.length >= burst.expectedBeats!) {
              transactions.add(burst.toParent());
              burst = null;
            }
          }

          inFlight = null;
          waitStates = 0;
          errorPhase1Edge = null;
        } else {
          waitStates++;
          if (hresp) {
            errorPhase1Edge = edgeTime;
          }
          // Don't capture a new address phase while a wait state is in
          // progress — the master must hold its outputs stable.
          continue;
        }
      }

      // ── capture this edge's address phase ────────────────────────────────
      // After completing (or with no in-flight transfer), check this
      // edge's HTRANS. If NONSEQ/SEQ, immediately latch as the new
      // in-flight transfer.
      final htrans = parseVcdVectorInt(query('htrans', edgeTime)) ?? 0;
      if (htrans == _htransNonseq || htrans == _htransSeq) {
        final hwrite = isVcdHigh(query('hwrite', edgeTime));
        final hsize = parseVcdVectorInt(query('hsize', edgeTime)) ?? 0;
        final hburst = parseVcdVectorInt(query('hburst', edgeTime)) ?? 0;
        final haddr = parseVcdVectorInt(query('haddr', edgeTime));
        final hprot = hasHprot
            ? parseVcdVectorInt(query('hprot', edgeTime))
            : null;
        final hmastlock = hasHmastlock
            ? isVcdHigh(query('hmastlock', edgeTime))
            : null;

        if (htrans == _htransSeq) {
          // Violation 2: SEQ without an active burst opened by NONSEQ.
          if (burst == null) {
            transactions.add(
              _violation(
                edgeTime,
                edgeTime,
                'HTRANS=SEQ at ${_fmtAddr(haddr)} without a preceding '
                'NONSEQ — every burst must begin with NONSEQ',
              ),
            );
          } else if (hburst != burst.hburst) {
            // Violation 3: HBURST changes mid-burst.
            transactions.add(
              _violation(
                edgeTime,
                edgeTime,
                'HBURST changed mid-burst (was '
                '${_burstName(burst.hburst)}, now '
                '${_burstName(hburst)}) — burst type is fixed at NONSEQ',
              ),
            );
          } else {
            // Violation 4: address-increment rule.
            final prevAddr = burst.lastAddr;
            if (haddr != null && prevAddr != null) {
              final stride = 1 << hsize;
              final expected = _expectedNextAddr(
                burstFirstAddr: burst.firstAddr ?? prevAddr,
                prev: prevAddr,
                hburst: burst.hburst,
                stride: stride,
              );
              if (haddr != expected) {
                transactions.add(
                  _violation(
                    edgeTime,
                    edgeTime,
                    'HADDR ${_fmtAddr(haddr)} does not match expected next '
                    'beat ${_fmtAddr(expected)} for '
                    '${_burstName(burst.hburst)} (prev '
                    '${_fmtAddr(prevAddr)}, stride $stride)',
                  ),
                );
              }
            }
          }
        }

        // Violation 5: HSIZE wider than configured data_width.
        final hsizeBits = 1 << (hsize + 3);
        if (hsizeBits > _dataWidth) {
          transactions.add(
            _violation(
              edgeTime,
              edgeTime,
              'HSIZE encodes a $hsizeBits-bit transfer but data_width is '
              '$_dataWidth bits — master is requesting a transfer wider '
              'than the configured data port',
            ),
          );
        }

        // Violation 6: HADDR not aligned to (1 << HSIZE).
        if (_checkAlignment && haddr != null) {
          final stride = 1 << hsize;
          if (stride > 1 && haddr % stride != 0) {
            transactions.add(
              _violation(
                edgeTime,
                edgeTime,
                'Misaligned HADDR ${_fmtAddr(haddr)} for HSIZE=$hsize '
                '(stride $stride bytes)',
              ),
            );
          }
        }

        // Open / close burst tracking on NONSEQ.
        if (htrans == _htransNonseq) {
          if (burst != null) {
            transactions.add(burst.toParent());
            burst = null;
          }
          if (hburst != _hburstSingle) {
            burst = _BurstAccum(
              id: 'ahb-$edgeTime',
              hburst: hburst,
              hsize: hsize,
              isWrite: hwrite,
              hmastlock: hmastlock,
              firstAddr: haddr,
              expectedBeats: _burstBeatCount(hburst),
            );
          }
        }

        // Latch as the new in-flight transfer.
        inFlight = _AddressPhase(
          cycleStart: edgeTime,
          htrans: htrans,
          isWrite: hwrite,
          hsize: hsize,
          hburst: hburst,
          haddr: haddr,
          hprot: hprot,
          hmastlock: hmastlock,
        );
        dataPhaseStart = edgeTime;
      } else if (htrans == _htransBusy) {
        // Violation 1: BUSY in a SINGLE (no active multi-beat burst).
        if (burst == null) {
          transactions.add(
            _violation(
              edgeTime,
              edgeTime,
              'HTRANS=BUSY without an active multi-beat burst — BUSY is '
              'only valid inside INCR / INCR4 / WRAP4 / INCR8 / WRAP8 '
              '/ INCR16 / WRAP16 sequences',
            ),
          );
        }
      } else {
        // HTRANS = IDLE. Closes an in-flight INCR-undefined burst.
        if (burst != null && burst.hburst == _hburstIncr) {
          transactions.add(burst.toParent());
          burst = null;
        }
      }
    }

    if (burst != null) {
      transactions.add(burst.toParent());
    }

    transactions.sort((a, b) {
      final byStart = a.startTime.compareTo(b.startTime);
      if (byStart != 0) return byStart;
      return a.endTime.compareTo(b.endTime);
    });
    return transactions;
  }

  // ── transaction emission ───────────────────────────────────────────────────

  DecodedTransaction _buildBeat({
    required _AddressPhase phase,
    required int? data,
    required bool isError,
    required bool twoCycleErrorOk,
    required int waitStates,
    required int dataPhaseStart,
    required int dataPhaseEnd,
    required String? burstId,
    required int? beatIndex,
  }) {
    final addrStr = _fmtAddr(phase.haddr);
    final dataStr = _fmtData(data);
    final respStr = isError ? 'ERROR' : 'OKAY';
    final sizeBits = 1 << (phase.hsize + 3);
    final burstName = _burstName(phase.hburst);

    final beatLabel = beatIndex != null
        ? ' [$burstName $beatIndex]'
        : (phase.hburst == _hburstSingle ? '' : ' [$burstName]');

    final label = phase.isWrite
        ? (isError
              ? 'W $addrStr = $dataStr [$respStr]$beatLabel'
              : 'W $addrStr = $dataStr$beatLabel')
        : (isError
              ? 'R $addrStr → $dataStr [$respStr]$beatLabel'
              : 'R $addrStr → $dataStr$beatLabel');

    final fields = <String, String>{
      'type': phase.isWrite ? 'Write' : 'Read',
      'address': addrStr,
      'data': dataStr,
      'size_bits': sizeBits.toString(),
      'burst': burstName,
      'response': respStr,
      'wait_states': waitStates.toString(),
      'addr_phase_start': phase.cycleStart.toString(),
      'data_phase_start': dataPhaseStart.toString(),
      if (phase.hmastlock != null) 'locked': phase.hmastlock! ? '1' : '0',
      if (phase.hprot != null)
        'hprot': '0x${phase.hprot!.toRadixString(16).toUpperCase()}',
      if (phase.hprot != null) ..._hprotFlags(phase.hprot!),
      'burst_id': ?burstId,
      if (beatIndex != null) 'beat_index': beatIndex.toString(),
    };

    // Surface violation 7 (single-cycle ERROR) on the same beat that
    // carries the bad response — the user-facing error is the same
    // event, just annotated.
    final violations = <String>[];
    if (isError && !twoCycleErrorOk) {
      violations.add(
        'ERROR response without two-cycle handshake (HREADY=1 with '
        'HRESP=ERROR on first cycle of data phase, no preceding '
        'HREADY=0,HRESP=ERROR cycle — IHI 0033 §3.8.2 violated)',
      );
    }
    final hasViolation = isError || violations.isNotEmpty;
    final errorMsg = violations.isEmpty
        ? (isError ? 'Response = $respStr' : null)
        : violations.join('; ');

    return DecodedTransaction(
      startTime: phase.cycleStart,
      endTime: dataPhaseEnd,
      label: label,
      fields: fields,
      isError: hasViolation,
      errorMessage: errorMsg,
    );
  }

  static Map<String, String> _hprotFlags(int hprot) {
    return {
      'hprot_data_or_instr': (hprot & 0x1) == 0x1 ? 'data' : 'instr',
      'hprot_privileged': (hprot & 0x2) == 0x2 ? '1' : '0',
      'hprot_bufferable': (hprot & 0x4) == 0x4 ? '1' : '0',
      'hprot_cacheable': (hprot & 0x8) == 0x8 ? '1' : '0',
    };
  }

  DecodedTransaction _violation(int startTime, int endTime, String msg) =>
      DecodedTransaction(
        startTime: startTime,
        endTime: endTime,
        label: 'AHB-Lite Violation',
        fields: {'error': msg},
        isError: true,
        errorMessage: msg,
      );

  DecodedTransaction _warning(int startTime, int endTime, String msg) =>
      DecodedTransaction(
        startTime: startTime,
        endTime: endTime,
        label: 'AHB-Lite Warning',
        fields: {'warning': msg},
        isError: true,
        errorMessage: 'warn: $msg',
      );

  // ── helpers: spec-derived semantics ────────────────────────────────────────

  // HTRANS encoding (IHI 0033 §3.5). IDLE (0b00) is treated as "no
  // transfer" — the decoder branches on NONSEQ / SEQ / BUSY explicitly
  // and falls through to IDLE in the else branch, so no constant is
  // needed for it.
  static const int _htransBusy = 0x1;
  static const int _htransNonseq = 0x2;
  static const int _htransSeq = 0x3;

  static const int _hburstSingle = 0x0;
  static const int _hburstIncr = 0x1;
  static const int _hburstWrap4 = 0x2;
  static const int _hburstIncr4 = 0x3;
  static const int _hburstWrap8 = 0x4;
  static const int _hburstIncr8 = 0x5;
  static const int _hburstWrap16 = 0x6;
  static const int _hburstIncr16 = 0x7;

  static String _burstName(int hburst) {
    switch (hburst) {
      case _hburstSingle:
        return 'SINGLE';
      case _hburstIncr:
        return 'INCR';
      case _hburstWrap4:
        return 'WRAP4';
      case _hburstIncr4:
        return 'INCR4';
      case _hburstWrap8:
        return 'WRAP8';
      case _hburstIncr8:
        return 'INCR8';
      case _hburstWrap16:
        return 'WRAP16';
      case _hburstIncr16:
        return 'INCR16';
      default:
        return 'UNK($hburst)';
    }
  }

  static bool _isWrapBurst(int hburst) =>
      hburst == _hburstWrap4 ||
      hburst == _hburstWrap8 ||
      hburst == _hburstWrap16;

  /// Returns the fixed beat count for INCR4/8/16 and WRAP4/8/16. Returns
  /// `null` for SINGLE (1 beat — but no burst tracker is opened) and INCR
  /// (undefined length — burst is closed by HTRANS != SEQ).
  static int? _burstBeatCount(int hburst) {
    switch (hburst) {
      case _hburstWrap4:
      case _hburstIncr4:
        return 4;
      case _hburstWrap8:
      case _hburstIncr8:
        return 8;
      case _hburstWrap16:
      case _hburstIncr16:
        return 16;
      default:
        return null;
    }
  }

  /// Computes the expected next address inside an in-flight burst, given
  /// the burst's first address (for wrap), the previous beat's address,
  /// the burst type, and the byte stride per beat.
  static int _expectedNextAddr({
    required int burstFirstAddr,
    required int prev,
    required int hburst,
    required int stride,
  }) {
    final linear = prev + stride;
    if (!_isWrapBurst(hburst)) {
      return linear;
    }
    final beats = _burstBeatCount(hburst);
    if (beats == null) return linear;
    final window = beats * stride;
    final base = burstFirstAddr - (burstFirstAddr % window);
    return base + ((linear - base) % window);
  }

  // ── helpers: parameters and bindings ───────────────────────────────────────

  bool _bound(String name) => _config.signalBindings.containsKey(name);

  int get _addrWidth => intParam(_config.parameters, 'addr_width', 32);
  int get _dataWidth => intParam(_config.parameters, 'data_width', 32);
  bool get _checkAlignment =>
      boolParam(_config.parameters, 'check_alignment', true);
  int get _waitStateThreshold =>
      intParam(_config.parameters, 'wait_state_threshold', 256);

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

class _AddressPhase {
  const _AddressPhase({
    required this.cycleStart,
    required this.htrans,
    required this.isWrite,
    required this.hsize,
    required this.hburst,
    required this.haddr,
    required this.hprot,
    required this.hmastlock,
  });

  /// Edge time at which this address phase was sampled (start of the
  /// address-phase cycle).
  final int cycleStart;
  final int htrans;
  final bool isWrite;
  final int hsize;
  final int hburst;
  final int? haddr;
  final int? hprot;
  final bool? hmastlock;
}

class _BurstAccum {
  _BurstAccum({
    required this.id,
    required this.hburst,
    required this.hsize,
    required this.isWrite,
    required this.hmastlock,
    required this.firstAddr,
    required this.expectedBeats,
  }) : lastAddr = firstAddr;

  final String id;
  final int hburst;
  final int hsize;
  final bool isWrite;
  final bool? hmastlock;
  final int? firstAddr;
  int? lastAddr;
  final int? expectedBeats;
  final List<DecodedTransaction> beats = [];

  DecodedTransaction toParent() {
    final start = beats.isEmpty ? 0 : beats.first.startTime;
    final end = beats.isEmpty ? start : beats.last.endTime;
    final dirLabel = isWrite ? 'W' : 'R';
    final hasErr = beats.any((b) => b.isError);
    final burstName = AhbLiteDecoder._burstName(hburst);

    final firstAddrStr = firstAddr != null
        ? '0x${firstAddr!.toRadixString(16).toUpperCase()}'
        : '0x?';
    final lastAddrStr = lastAddr != null
        ? '0x${lastAddr!.toRadixString(16).toUpperCase()}'
        : '0x?';
    final addrSpan = beats.isEmpty
        ? '?'
        : (firstAddr == lastAddr
              ? firstAddrStr
              : '$firstAddrStr..$lastAddrStr');

    return DecodedTransaction(
      startTime: start,
      endTime: end,
      label:
          '$burstName ${beats.length}× $dirLabel $addrSpan'
          '${hasErr ? ' [contains-error]' : ''}',
      fields: {
        'type': 'Burst',
        'burst': burstName,
        'beats': beats.length.toString(),
        'first_address': firstAddrStr,
        'last_address': lastAddrStr,
        'direction': isWrite ? 'Write' : 'Read',
        'burst_id': id,
        if (hmastlock != null) 'locked': hmastlock! ? '1' : '0',
      },
      isError: hasErr,
      errorMessage: hasErr ? 'Burst contains error beat(s)' : null,
    );
  }
}
