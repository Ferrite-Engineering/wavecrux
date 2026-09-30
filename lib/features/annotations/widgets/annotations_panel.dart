// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart'
    show kCruxInfoSnackDuration, showCruxInfoSnack;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/core/theme/annotation_colors.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/providers/annotation_walkthrough_provider.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// How the list is ordered.
enum AnnotationSort { time, author, created }

/// Lists every annotation in the tab, including the ones the canvas cannot
/// draw.
///
/// The canvas deliberately renders nothing for an annotation whose signal is
/// hidden or absent — piling orphans onto the top edge would be worse than
/// omitting them. This panel is where those go, so "not drawn" never means
/// "silently lost". It is also the only surface that reaches an annotation
/// scrolled or panned out of view.
class AnnotationsPanel extends ConsumerStatefulWidget {
  const AnnotationsPanel({super.key});

  @override
  ConsumerState<AnnotationsPanel> createState() => _AnnotationsPanelState();
}

class _AnnotationsPanelState extends ConsumerState<AnnotationsPanel> {
  final TextEditingController _search = TextEditingController();
  AnnotationSort _sort = AnnotationSort.time;
  bool _driftedOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Centres [time] in the viewport, keeping the current zoom.
  void _jumpTo(int time) {
    final mapper = ref.read(timeMapperProvider);
    final width = mapper.visibleRange;
    if (width <= 0) return;
    final start = time - width ~/ 2;
    ref.read(timeMapperProvider.notifier).zoomToRange(start, start + width);
  }

  /// Adds an orphaned annotation's signal back to the displayed list, which
  /// makes the note drawable again.
  void _showSignal(String rowId) {
    final variable = ref.read(signalVariablesByPathProvider)[rowId];
    if (variable == null) return;
    ref.read(signalGroupsProvider.notifier).addSignal(variable);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    // The COMPOSED set — local notes plus any authored in the live session.
    //
    // The panel read the local-only list, so during a session the canvas and
    // the list disagreed about what existed: a note from another participant
    // was drawn on the waveform and absent from the panel entirely. Every row
    // action the panel owns — set anchor time, collapse, delete, "show signal"
    // for an orphan — was therefore unreachable for exactly the notes somebody
    // else had just written, and the panel's promise that nothing is silently
    // lost held only for your own.
    final annotations = ref.watch(composedAnnotationsInTimeOrderProvider);
    final layers = ref.watch(annotationLayersProvider);
    final readOnly = ref.watch(readOnlyAnnotationIdsProvider);
    final statuses = ref.watch(annotationStatusesProvider);
    final timescale = ref.watch(currentTimescaleProvider);
    final scheme = Theme.of(context).colorScheme;

    if (annotations.isEmpty) {
      return _Centred(text: l10n.annotationsPanelEmpty);
    }

    // Numbering is assigned over the FULL time-ordered set, before any
    // filtering or grouping, so a row's badge always matches the dot the
    // canvas draws for the same note.
    final numbers = <String, int>{
      for (var i = 0; i < annotations.length; i++) annotations[i].id: i + 1,
    };

    final query = _search.text.trim().toLowerCase();
    bool matches(Annotation a) {
      if (_driftedOnly && statuses[a.id] != AnnotationStatus.drifted) {
        return false;
      }
      if (query.isEmpty) return true;
      return a.text.toLowerCase().contains(query) ||
          a.authorName.toLowerCase().contains(query) ||
          (a.rowId ?? '').toLowerCase().contains(query);
    }

    final visible = <Annotation>[];
    final orphaned = <Annotation>[];
    final unresolved = <Annotation>[];
    for (final a in annotations.where(matches)) {
      switch (statuses[a.id]) {
        case AnnotationStatus.orphaned:
          orphaned.add(a);
        case AnnotationStatus.unresolved:
          unresolved.add(a);
        case _:
          visible.add(a);
      }
    }

    switch (_sort) {
      case AnnotationSort.time:
        break; // already in time order
      case AnnotationSort.author:
        visible.sort((a, b) => a.authorName.compareTo(b.authorName));
      case AnnotationSort.created:
        visible.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final formatter = TimeFormatService(timescale: timescale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          controller: _search,
          hint: l10n.annotationsPanelSearchHint,
          driftedOnly: _driftedOnly,
          driftedLabel: l10n.annotationsPanelDriftedOnly,
          driftedExplanation: l10n.annotationsPanelDriftedExplanation,
          sort: _sort,
          onSearchChanged: (_) => setState(() {}),
          onDriftedChanged: (v) => setState(() => _driftedOnly = v),
          onSortChanged: (v) => setState(() => _sort = v),
        ),
        Expanded(
          child: visible.isEmpty && orphaned.isEmpty && unresolved.isEmpty
              ? _Centred(text: l10n.annotationsPanelNoMatches)
              : ListView(
                  primary: false,
                  children: [
                    // Ungrouped notes first — the user's own, which is what
                    // the panel is mostly about — then one group per adopted
                    // layer. Grouping is what makes "keep all" safe a week
                    // later: twelve loose notes by three people are twelve
                    // notes nobody will confidently delete.
                    for (final a in visible.where((a) => a.layerId == null))
                      _rowFor(
                        a,
                        numbers,
                        statuses,
                        formatter,
                        scheme,
                        l10n,
                        readOnly: readOnly,
                      ),
                    for (final layer in layers)
                      if (visible.any((a) => a.layerId == layer.id))
                        _Group(
                          label: layer.label,
                          trailing: _LayerControls(
                            layer: layer,
                            onToggle: () => ref
                                .read(annotationLayersProvider.notifier)
                                .setVisible(
                                  layer.id,
                                  visible: !layer.visible,
                                ),
                            onDelete: () => _deleteLayer(layer.id, l10n),
                            hideTooltip: l10n.annotationLayerHideTooltip,
                            showTooltip: l10n.annotationLayerShowTooltip,
                            deleteTooltip: l10n.annotationLayerDeleteTooltip,
                          ),
                          children: [
                            for (final a in visible.where(
                              (a) => a.layerId == layer.id,
                            ))
                              _rowFor(
                                a,
                                numbers,
                                statuses,
                                formatter,
                                scheme,
                                l10n,
                                readOnly: readOnly,
                              ),
                          ],
                        ),
                    if (orphaned.isNotEmpty)
                      _Group(
                        label: l10n.annotationsPanelNotDisplayed(
                          orphaned.length,
                        ),
                        children: [
                          for (final a in orphaned)
                            _rowFor(
                              a,
                              numbers,
                              statuses,
                              formatter,
                              scheme,
                              l10n,
                              readOnly: readOnly,
                              actionLabel: l10n.annotationsPanelShowSignal,
                              onAction: () {
                                final rowId = a.rowId;
                                if (rowId != null) _showSignal(rowId);
                              },
                            ),
                        ],
                      ),
                    if (unresolved.isNotEmpty)
                      _Group(
                        label: l10n.annotationsPanelNotInFile(
                          unresolved.length,
                        ),
                        children: [
                          for (final a in unresolved)
                            _rowFor(
                              a,
                              numbers,
                              statuses,
                              formatter,
                              scheme,
                              l10n,
                              readOnly: readOnly,
                            ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// One list row, with the edit affordance decided by attribution.
  ///
  /// An adopted note is read-only by attribution: hide it, delete it or
  /// duplicate it as yours, but do not rewrite somebody else's words while
  /// their name is on them. So the double-tap-to-edit is replaced by a
  /// **Duplicate as mine** action rather than left to fail silently.
  Widget _rowFor(
    Annotation a,
    Map<String, int> numbers,
    Map<String, AnnotationStatus> statuses,
    TimeFormatService formatter,
    ColorScheme scheme,
    L10N l10n, {
    required Set<String> readOnly,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final locked = readOnly.contains(a.id);
    // Not in the local store: somebody else's live-session note. Every mutation
    // path in the app writes to the local store, so these actions cannot work
    // on it — and an action that silently fails is worse than one that is not
    // offered. Each verb gets its own answer rather than one blanket rule.
    final remote = ref.watch(sessionOnlyAnnotationIdsProvider).contains(a.id);
    return _Row(
      key: ValueKey('annotation-row-${a.id}'),
      annotation: a,
      number: numbers[a.id] ?? 0,
      status: statuses[a.id],
      timeLabel: _timeLabel(a, formatter),
      scheme: scheme,
      driftedLabel: l10n.annotationsPanelDrifted,
      unattributed: l10n.annotationsPanelUnattributed,
      lockedTooltip: locked ? l10n.annotationReadOnlyAttribution : null,
      actionLabel: actionLabel,
      onAction: onAction,
      selected: ref.watch(annotationSelectedProvider) == a.id,
      // Selecting on tap, not only jumping. The row and the canvas then agree
      // about which note is under discussion, and it is the same selection the
      // ⌥-arrow nudge acts on.
      onTap: () {
        ref.read(annotationSelectedProvider.notifier).selected = a.id;
        _jumpTo(a.sortTime);
      },
      onEdit: locked ? null : () => _edit(a, statuses[a.id], l10n),
      // The row overflow. Delete used to be reachable only from the balloon's
      // own ✕ on the canvas, which meant an annotation whose signal is hidden
      // — the whole reason this panel exists — could be listed and not
      // removed.
      menu: [
        if (!locked)
          _RowAction(
            key: 'edit',
            label: l10n.annotationsPanelEditAction,
            onSelected: () => _edit(a, statuses[a.id], l10n),
          ),
        if (locked)
          _RowAction(
            key: 'duplicate',
            label: l10n.annotationDuplicateAsMine,
            onSelected: () => ref
                .read(annotationAuthoringProvider.notifier)
                .duplicateAsMine(a.id),
          ),
        // Fold / unfold on the canvas. Until now `collapsed: true` could only
        // be set by the walkthrough folding the note it had just left, so a
        // user could expand a dot but never fold a balloon back.
        //
        // Absent for a remote note. Collapsing is presentation and arguably
        // ought to be per-viewer, but `collapsed` lives on the shared model —
        // folding somebody else's note would need local presentation state that
        // does not exist, so the honest thing is not to offer it yet.
        if (!remote)
          _RowAction(
            key: a.collapsed ? 'expand' : 'collapse',
            label: a.collapsed
                ? l10n.annotationsPanelExpandAction
                : l10n.annotationsPanelCollapseAction,
            onSelected: () => ref
                .read(annotationsProvider.notifier)
                .setCollapsed(a.id, collapsed: !a.collapsed),
          ),
        // Moving an anchor is a content change, so author-only — the same rule
        // as the text. Offered on a remote note it opened its dialog, took a
        // tick, and did nothing.
        if (!remote)
          _RowAction(
            key: 'set-time',
            label: l10n.annotationsPanelSetTimeAction,
            onSelected: () => _editAnchorTime(a, formatter, l10n),
          ),
        // Delete is the one verb the host may use on somebody else's note
        // — the service already accepts a removal from the
        // author or the host and drops every other. A non-host sees no Delete
        // on a remote note rather than a control that cannot work.
        if (!remote || ref.watch(canModerateAnnotationsProvider))
          _RowAction(
            key: 'delete',
            label: l10n.annotationsPanelDeleteAction,
            destructive: true,
            onSelected: () => _delete(a.id, l10n, remote: remote),
          ),
      ],
    );
  }

  /// Opens a note's inline editor on the canvas — or explains why it cannot.
  ///
  /// **The editor lives on the balloon, and the canvas deliberately draws no
  /// balloon for a note whose signal is hidden or absent from the file.** So
  /// asking to edit one of those set the provider and produced nothing
  /// visible, which is indistinguishable from a dead menu item — and the panel
  /// is exactly where those notes are listed, so it is the surface from which
  /// somebody is most likely to try.
  ///
  /// The orphan case offers a way out rather than only an apology: its signal
  /// can be put back on the canvas, and then the note is editable.
  void _edit(Annotation a, AnnotationStatus? status, L10N l10n) {
    final rowId = a.rowId;
    if (status == AnnotationStatus.orphaned && rowId != null) {
      _showSignal(rowId);
    } else if (status == AnnotationStatus.unresolved) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.annotationsPanelNotInFileEdit)),
        );
      return;
    }
    _jumpTo(a.sortTime);
    ref.read(annotationBeingEditedProvider.notifier).editing = a.id;
  }

  /// Deletes one annotation, with the same undo toast the canvas balloon
  /// offers.
  ///
  /// Reachable from the panel because the panel is the only surface that lists
  /// an annotation whose signal is hidden or absent — exactly the notes whose
  /// balloon, and therefore whose ✕, the canvas deliberately does not draw.
  void _delete(String id, L10N l10n, {bool remote = false}) {
    // A remote note is not in the local store, so the local delete is a no-op.
    // Moderation goes over the wire, where the host is the documented exception
    // to author-only removal.
    if (remote) {
      ref.read(collaborationServiceProvider).removeAnnotation(id);
      // No undo offered, deliberately. The authoritative copy is gone and the
      // note was never ours to restore — a button that cannot work is a worse
      // promise than no button.
      showCruxInfoSnack(context, l10n.annotationDeletedToast);
      return;
    }
    final notifier = ref.read(annotationsProvider.notifier);
    if (!ref.read(annotationAuthoringProvider.notifier).delete(id)) return;
    showUndoSnack(
      context,
      message: l10n.annotationDeletedToast,
      undoLabel: l10n.annotationUndo,
      onUndo: notifier.undo,
    );
  }

  /// Asks for an exact anchor tick and applies it.
  ///
  /// A number, not a formatted time: the field takes ticks because that is the
  /// unit the model stores and the only one that round-trips without a
  /// timescale parser. The current value is shown formatted beside it so the
  /// user can see which unit they are in.
  Future<void> _editAnchorTime(
    Annotation annotation,
    TimeFormatService formatter,
    L10N l10n,
  ) async {
    final tick = await showDialog<int>(
      context: context,
      builder: (ctx) => _AnchorTimeDialog(
        initialTick: annotation.sortTime,
        title: l10n.annotationsPanelSetTimeAction,
        fieldLabel: l10n.annotationsPanelSetTimeHint,
        helperText: _timeLabel(annotation, formatter),
      ),
    );
    if (tick == null || !mounted) return;

    // Goes through the authoring notifier, never `reanchor`, because this must
    // re-capture the witness — see `setAnchorTime`. A note that reported
    // drifted the moment you corrected its tick would make the drift badge
    // mean "somebody touched this".
    // Jump to where the anchor LANDED, not to what was typed. A tick past the
    // end of the trace clamps the anchor to the last tick, and jumping to the
    // typed number instead parks the viewport in empty space with the note
    // nowhere in it — the note moved correctly and simply could not be seen,
    // which reads as the note having been destroyed.
    final landed = ref
        .read(annotationAuthoringProvider.notifier)
        .setAnchorTime(annotation.id, tick);
    if (landed == null) return;

    // Select it. Row numbers are positional — assigned over the full
    // time-ordered set — so a move that reorders the list renumbers every row
    // under the user: the badge they were following now belongs to a different
    // note, which may sit in "Not in this file". Marking the moved note is what
    // makes a correct move readable as a move rather than as a substitution.
    ref.read(annotationSelectedProvider.notifier).selected = annotation.id;
    _jumpTo(landed);

    // Say so when the value was clamped. Otherwise typing 10000 into a 1000-tick
    // trace silently becomes 1000, and the only evidence is a row that moved
    // somewhere the user did not ask for.
    if (landed != tick && mounted) {
      showCruxInfoSnack(
        context,
        l10n.annotationsPanelSetTimeClamped(landed),
      );
    }
  }

  /// Removes a layer's notes in one undo step and drops its registry entry.
  ///
  /// The notes are undoable; the name is not, and it is re-created by the undo
  /// path only in the sense that it never mattered — an annotation naming a
  /// layer with no entry degrades to an unnamed group, which is exactly what a
  /// build predating the registry sees.
  void _deleteLayer(String layerId, L10N l10n) {
    final notifier = ref.read(annotationsProvider.notifier)
      ..removeLayer(layerId);
    ref.read(annotationLayersProvider.notifier).remove(layerId);
    showUndoSnack(
      context,
      message: l10n.annotationLayerDeletedToast,
      undoLabel: l10n.annotationUndo,
      onUndo: notifier.undo,
    );
  }

  String _timeLabel(Annotation a, TimeFormatService formatter) =>
      switch (a.anchor) {
        PointAnchor(:final time) => formatter.format(time),
        RangeAnchor(:final earliest, :final latest) =>
          '${formatter.format(earliest)} – '
              '${formatter.format(latest)}',
      };
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.hint,
    required this.driftedOnly,
    required this.driftedLabel,
    required this.driftedExplanation,
    required this.sort,
    required this.onSearchChanged,
    required this.onDriftedChanged,
    required this.onSortChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool driftedOnly;
  final String driftedLabel;

  /// What amber means, on the one control that is about drift. Without it the
  /// colour is a mystery: drift is the feature's whole differentiator over a
  /// screenshot, and it is signalled by a colour nothing explains.
  final String driftedExplanation;

  final AnnotationSort sort;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onDriftedChanged;
  final ValueChanged<AnnotationSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: controller,
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 16),
                  hintText: hint,
                  hintStyle: const TextStyle(fontSize: 12),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // The chip carries the legend. Amber is the only colour variation a
          // single user ever sees on their notes, and nothing else in the app
          // says what it means — so the control that filters *by* drift is where
          // the word and the swatch belong together.
          Tooltip(
            message: driftedExplanation,
            child: FilterChip(
              avatar: const CircleAvatar(
                radius: 5,
                backgroundColor: kAnnotationDriftedColor,
              ),
              label: Text(driftedLabel, style: const TextStyle(fontSize: 11)),
              selected: driftedOnly,
              onSelected: onDriftedChanged,
            ),
          ),
          const SizedBox(width: 4),
          const _WalkthroughControls(),
          const SizedBox(width: 4),
          PopupMenuButton<AnnotationSort>(
            tooltip: l10n.annotationsPanelSortTooltip,
            initialValue: sort,
            onSelected: onSortChanged,
            icon: const Icon(Icons.sort, size: 18),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AnnotationSort.time,
                child: Text(l10n.annotationSortByTime),
              ),
              PopupMenuItem(
                value: AnnotationSort.author,
                child: Text(l10n.annotationSortByAuthor),
              ),
              PopupMenuItem(
                value: AnnotationSort.created,
                child: Text(l10n.annotationSortByCreated),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Play / pause / stop for the automatic walkthrough, plus its dwell.
///
/// Lives in the panel rather than on the canvas because the panel is where
/// somebody *reading* an annotated waveform already is — the list, the
/// numbering and the tour are one surface.
class _WalkthroughControls extends ConsumerWidget {
  const _WalkthroughControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(annotationWalkthroughProvider);
    final walkthrough = ref.read(annotationWalkthroughProvider.notifier);
    final metrics = MobileMetrics.of(context, ref.watch(deviceClassProvider));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: state.playing
              ? l10n.annotationWalkthroughPauseTooltip
              : l10n.annotationWalkthroughPlayTooltip,
          icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
          onPressed: () =>
              walkthrough.toggle(minLaneHeight: metrics.minLaneHeight),
        ),
        if (state.playing || state.focusedId != null)
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: l10n.annotationWalkthroughStopTooltip,
            icon: const Icon(Icons.stop),
            onPressed: walkthrough.stop,
          ),
        Tooltip(
          message: l10n.annotationWalkthroughDwellTooltip,
          child: DropdownButton<int>(
            value: state.dwell.inSeconds,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 11),
            items: const [2, 4, 6, 10]
                .map(
                  (seconds) => DropdownMenuItem(
                    value: seconds,
                    child: Text('${seconds}s'),
                  ),
                )
                .toList(),
            onChanged: (seconds) => seconds == null
                ? null
                : walkthrough.setDwell(Duration(seconds: seconds)),
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children, this.trailing});

  final String label;
  final List<Widget> children;

  /// Controls that act on the group as a unit — present for an adopted layer,
  /// absent for the orphan/unresolved groups, which are classifications rather
  /// than things a user can hide or delete wholesale.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
      ...children,
    ],
  );
}

/// Hide / show and delete, acting on a whole adopted layer.
///
/// Both are what a *named* group buys over loose notes: one control takes a
/// meeting's worth of somebody else's commentary off the canvas, and one more
/// removes it for good.
class _LayerControls extends StatelessWidget {
  const _LayerControls({
    required this.layer,
    required this.onToggle,
    required this.onDelete,
    required this.hideTooltip,
    required this.showTooltip,
    required this.deleteTooltip,
  });

  final AnnotationLayer layer;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final String hideTooltip;
  final String showTooltip;
  final String deleteTooltip;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: ValueKey('annotation-layer-toggle-${layer.id}'),
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        tooltip: layer.visible ? hideTooltip : showTooltip,
        icon: Icon(
          layer.visible ? Icons.visibility : Icons.visibility_off,
        ),
        onPressed: onToggle,
      ),
      IconButton(
        key: ValueKey('annotation-layer-delete-${layer.id}'),
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        tooltip: deleteTooltip,
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    ],
  );
}

/// One entry in a row's overflow menu.
@immutable
class _RowAction {
  const _RowAction({
    required this.key,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  /// Stable id, used for the menu item's widget key so a test can name an
  /// action without matching its localized label.
  final String key;
  final String label;
  final VoidCallback onSelected;

  /// Rendered in the error colour. Delete is the only one, and it sits under
  /// a pointer that was a moment ago hovering "collapse".
  final bool destructive;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.annotation,
    required this.number,
    required this.status,
    required this.timeLabel,
    required this.scheme,
    required this.driftedLabel,
    required this.unattributed,
    this.lockedTooltip,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.onEdit,
    this.menu = const [],
    this.selected = false,
    super.key,
  });

  final Annotation annotation;
  final int number;
  final AnnotationStatus? status;
  final String timeLabel;
  final ColorScheme scheme;
  final String driftedLabel;
  final String unattributed;

  /// Why this row's text cannot be edited, or null when it can. Rendered as a
  /// small lock beside the author, so the missing double-tap has a visible
  /// reason rather than reading as a bug.
  final String? lockedTooltip;

  final String? actionLabel;

  /// Whether this is the annotation the canvas has selected.
  ///
  /// **The panel had no notion of selection at all**, and row numbers are
  /// positional — assigned over the full time-ordered set so a badge matches
  /// the canvas dot. Move an anchor and the list reorders under the user: the
  /// row wearing "#2" is now a different note, and the one they were tracking
  /// is somewhere else entirely. With nothing marking it, a correct move reads
  /// as the note having turned into another note, or vanished.
  final bool selected;

  /// Overflow actions for this row. Empty renders no button.
  final List<_RowAction> menu;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final drifted = status == AnnotationStatus.drifted;
    final rgb = annotation.colorRgb;
    final color = drifted
        ? kAnnotationDriftedColor
        : (rgb != null ? Color(rgb) : scheme.primary);
    final firstLine = annotation.text.split('\n').first;

    // The InkWell wraps the row's **body only**, with the trailing controls as
    // siblings rather than descendants.
    //
    // Not cosmetic: `onDoubleTap` puts a `DoubleTapGestureRecognizer` in the
    // arena, and a tap on a button underneath it does not resolve until that
    // recognizer's ~300 ms timeout expires. Nesting the ⋮ inside meant every
    // press of it hung for a third of a second before the menu appeared. Same
    // family as the 5.9.1 defect where a tap recognizer beside a pan one cost
    // every drag its first slop-distance of travel.
    return Container(
      // A tinted ground plus a colour-bearing left edge, in the annotation's
      // own colour, so the row can be found by the same cue that identifies it
      // on the canvas. Deliberately not a colour *change* to the badge or the
      // text: a note can be selected and drifted at once, and those two facts
      // have to stay separately legible — the same rule the canvas ring
      // follows.
      decoration: selected
          ? BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border(left: BorderSide(color: color, width: 3)),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              onDoubleTap: onEdit,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                    child: Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.surface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          firstLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              timeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (annotation.rowId != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  annotation.rowId!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Text(
                              annotation.authorName.isEmpty
                                  ? unattributed
                                  : annotation.authorName,
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (lockedTooltip != null) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: lockedTooltip,
                                child: Icon(
                                  Icons.lock_outline,
                                  size: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (drifted) ...[
                              const SizedBox(width: 6),
                              Text(
                                driftedLabel,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: kAnnotationDriftedColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          if (menu.isNotEmpty)
            PopupMenuButton<_RowAction>(
              key: ValueKey('annotation-row-menu-${annotation.id}'),
              tooltip: l10n.annotationsPanelRowMenuTooltip,
              iconSize: 16,
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: (action) => action.onSelected(),
              itemBuilder: (context) => [
                for (final action in menu)
                  PopupMenuItem(
                    key: ValueKey(
                      'annotation-row-action-${action.key}-'
                      '${annotation.id}',
                    ),
                    value: action,
                    child: Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: action.destructive ? scheme.error : null,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Centred extends StatelessWidget {
  const _Centred({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// Asks for an exact anchor tick.
///
/// **Stateful so it owns its controller.** The caller used to build one, hand
/// it to a `TextField` inside `showDialog`, and dispose it the line after the
/// `await` returned — but the route's exit transition is still playing then,
/// with the field still mounted, and a `TextField` re-attaching to a disposed
/// `TextEditingController` throws. Nothing surfaced it until a test drove the
/// dialog to completion; by hand the exception lands in the console after the
/// dialog has visibly closed and the anchor has visibly moved, which is a long
/// way from where anyone would look.
class _AnchorTimeDialog extends StatefulWidget {
  const _AnchorTimeDialog({
    required this.initialTick,
    required this.title,
    required this.fieldLabel,
    required this.helperText,
  });

  final int initialTick;
  final String title;
  final String fieldLabel;

  /// The current position, formatted in the file's timescale — the field takes
  /// ticks, so this is what says which unit the number beside it is in.
  final String helperText;

  @override
  State<_AnchorTimeDialog> createState() => _AnchorTimeDialogState();
}

class _AnchorTimeDialogState extends State<_AnchorTimeDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.initialTick}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop(int.tryParse(_controller.text.trim()));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('annotation-set-time-field'),
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.fieldLabel,
        helperText: widget.helperText,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      TextButton(
        key: const ValueKey('annotation-set-time-ok'),
        onPressed: _submit,
        child: Text(MaterialLocalizations.of(context).okButtonLabel),
      ),
    ],
  );
}

/// Shows an undo snackbar **after the route that triggered it has closed**.
///
/// **Why the deferral.** `ScaffoldMessengerState.build` arms the auto-dismiss
/// timer only when its own route is current:
///
/// ```dart
/// final ModalRoute<dynamic>? route = ModalRoute.of(context);
/// if (route == null || route.isCurrent) {
///   if (_snackBarController!.isCompleted && _snackBarTimer == null) {
///     _snackBarTimer = Timer(snackBar.duration, ...);
/// ```
///
/// Every one of these is raised from inside the panel's ⋮ menu, which is a
/// route sitting on top. Show the snackbar there and `isCurrent` is false, so
/// **no timer is ever created** — the snackbar has nothing that will ever
/// expire it. It then sits over the status bar indefinitely, which is how a
/// host came to miss a join request that timed out underneath it.
///
/// Pressing Escape appeared to "fix" it only by closing the stale route and
/// forcing the rebuild that finally armed the timer.
///
/// One frame is enough: the menu pops before the callback runs, so the
/// messenger builds with its own route current and arms the timer normally.
/// Deliberately not a longer delay — a snackbar that lags a visible beat behind
/// the action it reports reads as lag.
void showUndoSnack(
  BuildContext context, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: undoLabel, onPressed: onUndo),
        // Explicit, and pinned to the suite constant rather than left to the
        // framework default they currently coincide on: the timer below is
        // armed from the same value, and the two must not be able to drift.
        // ignore: avoid_redundant_argument_values
        duration: kCruxInfoSnackDuration,
      ),
    );
    // **We close it ourselves.** Deferring the show past the menu's route was
    // not enough — the messenger arms its timer from `build`, and only while
    // its own route is current, so whether one is ever created depends on what
    // else happens to be on the navigator at that instant. A snack that may or
    // may not expire depending on route timing is not a snack with a duration.
    //
    // Owning the timer makes the dismissal unconditional. `close` is a no-op if
    // the user already dismissed it or tapped Undo.
    final timer = Timer(kCruxInfoSnackDuration, controller.close);
    // Cancelled the moment the snack goes, however it goes — Undo tapped, a
    // later snack replacing it, the messenger torn down. A timer that outlives
    // its snack would fire into nothing in production and trip
    // flutter_test's "a Timer is still pending" invariant in every test that
    // deletes something.
    unawaited(controller.closed.then((_) => timer.cancel()));
  });
}
