// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

/// How register indices are labelled in the Commit Inspector.
enum RiscvCommitRegisterNaming {
  /// RISC-V ABI mnemonics — `a0`, `sp`, `ra`. What a core designer reads.
  abi('abi'),

  /// Numeric `x`-indices — `x10`, `x2`, `x1`. What the encoding names.
  numeric('numeric');

  const RiscvCommitRegisterNaming(this.id);

  /// Stable id persisted in `.wavecrux` session files.
  final String id;

  /// Parses a stored config value, defaulting to [abi].
  static RiscvCommitRegisterNaming parse(Object? raw) {
    for (final v in RiscvCommitRegisterNaming.values) {
      if (v.id == raw) return v;
    }
    return RiscvCommitRegisterNaming.abi;
  }
}

/// **RVFI Commit Inspector** — the open-core RISC-V correctness widget.
///
/// Turns a VCD/FST of an RVFI-instrumented core into the four views a core
/// designer works from — the retired-instruction log with real operand
/// values, the reconstructed architectural register file at the cursor, the
/// memory access log and the trap log — and then runs the **consistency
/// checker** over the whole retire stream (see
/// `services/riscv/riscv_consistency_checker.dart`).
///
/// **Open core, and not crippled.** The RISC-V family draws the
/// tier line at *correctness is free, productivity is paid*: this widget
/// answers "is my core correct?" end to end with no license, no row cap, no
/// watermark and no in-view upsell. The checker in particular stays free —
/// it is the reason the widget is more than a log viewer, and gating it
/// would invert the doctrine. Microarchitectural performance analysis is
/// what the Pro pack sells; this is not that.
///
/// **Pins.** All 21 riscv-formal `rvfi_*` channels are declared, named
/// exactly as the ports are, so [RvfiDetectionService] can map a whole
/// bundle onto them by name in one action. Three are required — without
/// `rvfi_valid` there is no retirement strobe, without `rvfi_insn` nothing
/// to disassemble, without `rvfi_pc_rdata` nothing to locate in the program.
/// The other eighteen are optional and their absence **degrades a view
/// rather than blocking the widget**: a core instrumented with only the
/// reduced set (valid + pc + insn + rd) still gets a commit log, a register
/// file and two of the six checks, and the UI says exactly which channels
/// are missing and which checks did not run.
///
/// Twenty-one pins is more than anyone will bind by hand, which is why the
/// widget declares an [autoBindService]; see `StageWidget.supportsAutoBind`.
///
/// **Single-issue.** The declared pins cover retirement channel 0. A
/// superscalar core exposing `rvfi_valid[1]`, `rvfi_valid[2]`, … retires on
/// several channels per cycle; the substrate models that, but multi-issue
/// *presentation* belongs to the Pro pipeline widget, and declaring 21 pins
/// per channel here would be unusable.
class RiscvCommitStageWidget extends StageWidget {
  const RiscvCommitStageWidget();

  /// Stable id used by the Stage registry, the picker, session files, and
  /// the renderer factory.
  ///
  /// Bare, per the open-core widget-id convention (`led`, `bus_readout`).
  /// The Tachometer's `wavecrux.pro.tachometer` is legacy from its tier flip
  /// and is not the pattern to copy.
  static const String widgetId = 'riscv_commit';

  /// Config key: [RiscvCommitRegisterNaming].
  static const String paramRegisterNaming = 'registerNaming';

  /// Config key: number of architectural integer registers.
  static const String paramRegisterCount = 'registerCount';

  /// Config key: how many recent memory accesses the log retains.
  static const String paramMemoryLogDepth = 'memoryLogDepth';

  static const String _displayGroup = 'riscvCommit.display';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'RVFI Commit Inspector';

  @override
  String? get displayNameKey => 'stageRiscvCommitDisplayName';

  @override
  String get description =>
      'Retired-instruction log, reconstructed architectural register file, '
      'memory and trap logs, and the RVFI consistency checker, for a core '
      'instrumented with the riscv-formal interface.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;

  @override
  StageAutoBindService? get autoBindService => const RvfiDetectionService();

  @override
  String? get autoBindTitleKey => 'stageRvfiAutoBindTitle';

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'rvfi_valid',
      description:
          'Retirement strobe. Asserted for the cycle an instruction retires; '
          'every other channel is sampled against it.',
      bitWidth: 1,
    ),
    SignalBinding(
      name: 'rvfi_insn',
      description:
          'The retired instruction word, in its expanded 32-bit '
          'form.',
    ),
    SignalBinding(
      name: 'rvfi_pc_rdata',
      description: 'The address the retired instruction was fetched from.',
    ),
  ];

  @override
  List<SignalBinding> get optionalSignals => const [
    SignalBinding(
      name: 'rvfi_order',
      description:
          'Monotonic retirement counter. Without it, back-to-back '
          'retirements held under one valid pulse collapse into one, and the '
          'retirement-order check cannot run.',
    ),
    SignalBinding(
      name: 'rvfi_pc_wdata',
      description:
          'Address the next instruction should retire from. Drives the '
          'control-flow continuity check.',
    ),
    SignalBinding(
      name: 'rvfi_trap',
      description: 'Set when the retired instruction raised a trap.',
      bitWidth: 1,
    ),
    SignalBinding(
      name: 'rvfi_halt',
      description: 'Set on the last retirement before the core halts.',
      bitWidth: 1,
    ),
    SignalBinding(
      name: 'rvfi_intr',
      description:
          'Set when the retirement is the first instruction of a trap '
          'handler.',
      bitWidth: 1,
    ),
    SignalBinding(
      name: 'rvfi_mode',
      description: 'Privilege level at retirement (0 = U, 1 = S, 3 = M).',
    ),
    SignalBinding(
      name: 'rvfi_ixl',
      description: 'Effective XLEN encoding at retirement (1 = 32, 2 = 64).',
    ),
    SignalBinding(
      name: 'rvfi_rs1_addr',
      description: 'Register index read on port 1 (0 when unused).',
    ),
    SignalBinding(
      name: 'rvfi_rs1_rdata',
      description: 'Value read on port 1.',
    ),
    SignalBinding(
      name: 'rvfi_rs2_addr',
      description: 'Register index read on port 2 (0 when unused).',
    ),
    SignalBinding(
      name: 'rvfi_rs2_rdata',
      description: 'Value read on port 2.',
    ),
    SignalBinding(
      name: 'rvfi_rd_addr',
      description:
          'Destination register index; 0 means the instruction writes no '
          'register.',
    ),
    SignalBinding(
      name: 'rvfi_rd_wdata',
      description: 'Value written to the destination register.',
    ),
    SignalBinding(
      name: 'rvfi_mem_addr',
      description: 'Address of the memory access, if any.',
    ),
    SignalBinding(
      name: 'rvfi_mem_rmask',
      description: 'Byte-enable mask of the read half of the access.',
    ),
    SignalBinding(
      name: 'rvfi_mem_wmask',
      description: 'Byte-enable mask of the write half of the access.',
    ),
    SignalBinding(
      name: 'rvfi_mem_rdata',
      description: 'Data read by the access.',
    ),
    SignalBinding(
      name: 'rvfi_mem_wdata',
      description: 'Data written by the access.',
    ),
  ];

  @override
  (double, double) get defaultSize => (560, 380);

  @override
  (double, double) get minSize => (320, 220);

  @override
  List<ConfigParamGroup> get configGroups => const [
    ConfigParamGroup(id: _displayGroup, labelKey: 'riscvCommitGroupDisplay'),
  ];

  @override
  List<ConfigParam> get configParams => const [
    ConfigParam(
      id: paramRegisterNaming,
      labelKey: 'riscvCommitParamRegisterNaming',
      type: ConfigParamType.enumChoice,
      defaultValue: 'abi',
      choices: [
        ConfigParamChoice(id: 'abi', labelKey: 'riscvCommitChoiceAbi'),
        ConfigParamChoice(id: 'numeric', labelKey: 'riscvCommitChoiceNumeric'),
      ],
      groupId: _displayGroup,
    ),
    // 32 for RV32I / RV64I, 16 for the RV32E embedded profile. There is no
    // third legal value, so this is a two-stop slider rather than free text.
    ConfigParam(
      id: paramRegisterCount,
      labelKey: 'riscvCommitParamRegisterCount',
      type: ConfigParamType.integer,
      defaultValue: 32,
      min: 16,
      max: 32,
      step: 16,
      groupId: _displayGroup,
    ),
    ConfigParam(
      id: paramMemoryLogDepth,
      labelKey: 'riscvCommitParamMemoryLogDepth',
      type: ConfigParamType.integer,
      defaultValue: 32,
      min: 4,
      max: 256,
      step: 4,
      groupId: _displayGroup,
    ),
  ];
}
