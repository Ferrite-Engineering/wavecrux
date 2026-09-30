// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

/// Mounts an **RVFI Commit Inspector** into a tab a cross-probe just opened,
/// pre-bound to the RVFI channels the trace actually carries.
///
/// ## Why this exists
///
/// A CXP §9.9 (https://edacrux.app/cxp#sec-9-9) `riscv.formal.trace_step`
/// coordinate lands the primary cursor on
/// the retirement a bounded proof failed at. That is exactly the right instant
/// — and on a freshly-opened tab it is invisible: a new tab has no Stage
/// panel, so the Commit Inspector that renders the retirement (and the landing
/// banner that explains it, which lives inside that widget) is not on screen at
/// all. The hand-off's promise is *jump from a failing proof to the offending
/// retirement and see it*; without this the user gets a cursor on an empty
/// canvas.
///
/// ## The three rules this obeys
///
/// 1. **Only for a resolved RVFI coordinate.** The caller invokes this only
///    after a coordinate has actually resolved against an RVFI stream — an
///    unknown `stream_id`, an unresolvable step, or a trace with no RVFI bundle
///    never reaches here, and changes nothing about the layout.
/// 2. **Only into a tab the cross-probe itself opened.** A trace that was
///    *already* open is a tab the user has arranged. Moving its cursor is the
///    hand-off's job; rearranging its panels is not. The caller passes that
///    distinction in; this function is only ever called for a fresh tab.
/// 3. **Bound through the existing detection service.** [RvfiDetectionService]
///    is the same [`StageAutoBindService`] the Commit Inspector's own Auto-bind
///    affordance uses. There is no second binding path to keep in sync, and a
///    trace carrying only the reduced channel set produces a reduced binding
///    map — which the widget already degrades gracefully around, saying which
///    channels are missing.
///
/// ## What it does, as one undoable step
///
/// Adds a Stage panel named [panelName], puts one [RiscvCommitStageWidget]
/// instance on it at [kRiscvCrossProbeMountSize], applies the auto-bound
/// channel map, reveals the panel's bottom-dock tab and raises the dock to
/// [kRiscvCrossProbeDockHeight] if it was shorter. The whole thing is
/// bracketed in a [StageWorkspaceNotifier] transaction so a user who did not
/// want it undoes it with one Ctrl/Cmd+Z rather than three.
///
/// Returns the new instance's id, or **null** when nothing was mounted:
///
/// * the tab already holds a Commit Inspector (a repeat cross-probe onto the
///   same tab must not stack a second one), or
/// * the detection service bound no channel at all (nothing to show — and a
///   panel that appears unbidden only to report that it is empty is worse
///   than no panel).
/// The size the cross-probe mounts its Commit Inspector at — **not** the
/// widget's declared `defaultSize`.
///
/// `defaultSize` (560 × 380) is tuned for a user dragging the inspector onto a
/// Stage panel they have already sized and will size again; this mount is a
/// panel the user never asked for, appearing in a dock they are not looking
/// at, whose single job is to show one particular retirement. At 380 tall the
/// inspector's chrome — landing banner, bound-channel count, the five-way view
/// selector, the column header — eats ~170 px and leaves room for four 44 px
/// commit rows. A six-retirement counterexample therefore lands below the
/// fold, which is exactly what a user hit on the SimCrux hand-off.
///
/// **420 × 720**: five to six rows of log, which is the landed retirement plus
/// enough of its history to read it in context, and it pairs with
/// [kRiscvCrossProbeDockHeight] so the whole instance is on screen at once. It
/// is deliberately not larger — the dock is a strip beside the waveform
/// canvas, not the point of the window, and the row is *scrolled* into view
/// (see `RiscvCommitLogView`) rather than sized into view, so growing this
/// further buys context, never correctness. 720 wide keeps the disassembly and
/// the architectural-effect columns off the ellipsis next to the fixed 40 px
/// order and 96 px PC columns.
const (double, double) kRiscvCrossProbeMountSize = (720, 420);

/// The least bottom-dock height the cross-probe leaves behind.
///
/// Sizing the *instance* is only half of "visible": the Stage canvas is an
/// unconstrained [InteractiveViewer], so an instance taller than the dock is
/// panned into view rather than scrolled, and a 420 px inspector in the
/// default 200 px dock shows its banner and nothing else. 480 clears
/// [kRiscvCrossProbeMountSize]'s height plus the panel's own chrome.
///
/// Sized against the small window rather than the large one: 480 px is 44 % of
/// a 1080 px-tall display and still leaves the waveform canvas the majority of
/// a 900 px one. Raise-only ([PanelLayoutNotifier.growBottomPaneTo]), so a user
/// who keeps a tall dock keeps it.
const double kRiscvCrossProbeDockHeight = 480;

String? mountRiscvCommitInspector({
  required StageWorkspaceNotifier workspace,
  required StageWorkspaceState current,
  required PanelLayoutNotifier layout,
  required Map<String, Variable> availableSignals,
  required String panelName,
}) {
  // Idempotent: one inspector per tab. A second cross-probe onto a tab that
  // already has one moves the cursor and re-captions the existing panel.
  final alreadyMounted = current.panels.any(
    (p) => p.instances.any(
      (i) => i.widgetId == RiscvCommitStageWidget.widgetId,
    ),
  );
  if (alreadyMounted) return null;

  final bindings = riscvCommitAutoBindings(availableSignals);
  if (bindings.isEmpty) return null;

  final (width, height) = kRiscvCrossProbeMountSize;

  workspace.beginTransaction();
  final panelId = workspace.addPanel(panelName);
  final instanceId = workspace.addInstanceAt(
    RiscvCommitStageWidget.widgetId,
    x: 0,
    y: 0,
    width: width,
    height: height,
  );
  if (instanceId != null) workspace.setBindings(instanceId, bindings);
  workspace.endTransaction();
  if (instanceId == null) return null;

  // Reveal, VS Code style: activate the new panel's tab AND open the bottom
  // region, so the panel that was just created is the one on screen — and give
  // the region enough height to show the instance rather than a strip of its
  // banner, which is what the default 200 px dock reduced it to.
  layout
    ..setStageViewVisible(visible: true)
    ..revealBottomDockTab('$kBottomDockStagePrefix$panelId')
    ..growBottomPaneTo(kRiscvCrossProbeDockHeight);
  return instanceId;
}

/// The Commit Inspector pin → signal map [RvfiDetectionService] proposes for
/// [availableSignals], with the `noMatch` pins dropped.
///
/// Exposed separately from [mountRiscvCommitInspector] so the binding decision
/// can be asserted without a workspace, and so the auto-mount and the manual
/// Auto-bind affordance provably share one implementation: both call
/// [`StageAutoBindService.autoBind`] on the same `const RvfiDetectionService()`
/// with the same widget definition.
Map<String, StageSignalBinding> riscvCommitAutoBindings(
  Map<String, Variable> availableSignals,
) {
  final proposal = const RvfiDetectionService().autoBind(
    widget: const RiscvCommitStageWidget(),
    availableSignals: availableSignals,
  );
  return <String, StageSignalBinding>{
    for (final entry in proposal.candidates.entries)
      entry.key: ?entry.value.binding,
  };
}
