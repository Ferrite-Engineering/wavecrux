// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/rtl_source/rtl_syntax_highlighter.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';
import 'package:wavecrux/shared/widgets/editor_host_boundary.dart';

/// Source-annotation panel that shows RTL source files inline with live signal
/// values at the current cursor time.
///
/// Activated by loading a GTKWave-compatible stems file (xml2stems / vermin
/// output). When the user selects a signal in the signal tree the panel
/// navigates to the file and line number recorded in the stems file. The
/// signal value at the primary cursor is rendered as an inline annotation
/// next to the highlighted line.
///
/// Bidirectional navigation:
/// - Click an identifier in the source view → resolves it to a stems entry
///   and adds the matching variable to the waveform viewer
/// - Selecting a signal in the viewer → navigates the panel to that signal's
///   source location (handled by [RtlSourceController.bindToSelection] in
///   [ViewerScreen])
///
/// Desktop only. The hosting [IdeLayout] gates this panel behind
/// `deviceClassProvider` upstream.
class RtlSourcePanel extends ConsumerWidget {
  const RtlSourcePanel({this.onLoadStems, this.onClose, super.key});

  /// Invoked when the user taps the "Load Stems File…" button. Caller
  /// typically opens a file picker and calls
  /// [RtlSourceNotifier.loadStemsFile] on the result.
  final VoidCallback? onLoadStems;

  /// Invoked when the user dismisses the panel from the header close button.
  /// The hosting layout decides what "close" means (toggle visibility, hide
  /// pane, etc.).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(rtlSourceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Inside a VSCode editor panel the panel keeps its header — title, close
    // button, its place in the layout — and states the boundary in the body
    // — present and explained, never omitted.
    //
    // The stems-load action is withheld with it: a stems file names HDL
    // *paths*, and `_SourceView` renders those files' contents, which a
    // webview has no filesystem to read. Offering a picker that can only
    // ever end in an empty source view would be a worse answer than the
    // sentence.
    final hosted = isEditorHosted(ref);

    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            l10n: l10n,
            stemsCount: state.stems?.length ?? 0,
            onLoadStems: hosted ? null : onLoadStems,
            onClose: onClose,
          ),
          Expanded(
            child: hosted
                ? const EditorHostBoundary(
                    capability: EditorHostCapability.rtlAnnotation,
                  )
                : _Body(state: state, l10n: l10n, onLoadStems: onLoadStems),
          ),
        ],
      ),
    );
  }
}

// ── header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.l10n,
    required this.stemsCount,
    required this.onLoadStems,
    required this.onClose,
  });

  final L10N l10n;
  final int stemsCount;
  final VoidCallback? onLoadStems;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          // The right pane this header lives in can be as narrow as 150 dp, so
          // the title/count area scrolls horizontally (per the open-core
          // "chrome rows are horizontally scrollable" rule) while the action
          // buttons stay pinned and always reachable.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(Icons.code, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    l10n.rtlSourcePanelTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (stemsCount > 0)
                    Text(
                      l10n.rtlSourceStemsLoadedCount(stemsCount),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Compact, always-pinned so it can't overflow the narrow right pane.
          // The prominent labelled call-to-action lives in the empty-state body
          // (where the "no stems loaded" guidance is); this header button is the
          // secondary "load a different stems file" affordance.
          if (onLoadStems != null)
            IconButton(
              tooltip: l10n.rtlSourceLoadStemsButton,
              icon: const Icon(Icons.folder_open, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
              onPressed: onLoadStems,
            ),
          if (onClose != null)
            IconButton(
              tooltip: l10n.rtlSourcePanelClose,
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

// ── body ──────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.l10n, this.onLoadStems});

  final RtlSourceState state;
  final L10N l10n;
  final VoidCallback? onLoadStems;

  @override
  Widget build(BuildContext context) {
    if (state.status == RtlStemsStatus.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (!state.hasStems) {
      // Primary call-to-action: no stems loaded → offer the load button here,
      // where the guidance text is, since the header action is icon-only.
      return _empty(
        context,
        body: l10n.rtlSourceNoStemsLoaded,
        error: state.error,
        onLoadStems: onLoadStems,
      );
    }

    final source = state.currentSourceFile;
    if (source == null) {
      return _empty(
        context,
        body: l10n.rtlSourceNoSelection,
        error: state.error,
      );
    }

    return _SourceView(state: state);
  }

  Widget _empty(
    BuildContext context, {
    required String body,
    String? error,
    VoidCallback? onLoadStems,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (onLoadStems != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onLoadStems,
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(l10n.rtlSourceLoadStemsButton),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── source view ───────────────────────────────────────────────────────────────

class _SourceView extends ConsumerStatefulWidget {
  const _SourceView({required this.state});

  final RtlSourceState state;

  @override
  ConsumerState<_SourceView> createState() => _SourceViewState();
}

class _SourceViewState extends ConsumerState<_SourceView> {
  static const _highlighter = RtlSyntaxHighlighter();
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(_SourceView old) {
    super.didUpdateWidget(old);
    if (widget.state.currentLine != old.state.currentLine ||
        widget.state.currentSourceFile?.path !=
            old.state.currentSourceFile?.path) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlight();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToHighlight();
    });
  }

  void _scrollToHighlight() {
    if (!_scrollController.hasClients) return;
    final line = widget.state.currentLine;
    if (line == null) return;
    const lineHeight = 18.0;
    final position = (line - 1) * lineHeight;
    final viewport = _scrollController.position.viewportDimension;
    final target = (position - viewport / 2).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final source = widget.state.currentSourceFile!;
    final dialect = _highlighter.dialectFor(source.path);

    final cursor = ref.watch(cursorStateProvider).primaryCursorTime;
    final dataSource = ref.watch(waveformSourceProvider).value;
    final variablesMap = ref.watch(signalVariablesMapProvider);

    final formattedValue = _formatValueAtCursor(
      ref: ref,
      signalRef: widget.state.currentSignalRef,
      cursor: cursor,
      variablesMap: variablesMap,
    );

    final lines = source.lines;
    final highlightLine = widget.state.currentLine ?? -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colorScheme.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  source.path,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.state.currentLine != null) ...[
                const SizedBox(width: 8),
                Text(
                  l10n.rtlSourceLineNumberLabel(widget.state.currentLine!),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          color: colorScheme.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.rtlSourceClickHint,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              if (formattedValue != null)
                Text(
                  l10n.rtlSourceCurrentValue(formattedValue),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: lines.length,
            itemExtent: 18,
            itemBuilder: (context, index) {
              final inBlockComment = _inBlockCommentAt(
                lines: lines,
                upTo: index,
                dialect: dialect,
              );
              return _SourceLine(
                lineNumber: index + 1,
                text: lines[index],
                spans: _highlighter.tokenize(
                  lines[index],
                  dialect,
                  inBlockComment: inBlockComment,
                ),
                isHighlighted: index + 1 == highlightLine,
                onIdentifierTap: (name) =>
                    _handleIdentifierTap(name, dataSource, variablesMap),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _inBlockCommentAt({
    required List<String> lines,
    required int upTo,
    required RtlSourceDialect dialect,
  }) {
    if (dialect != RtlSourceDialect.verilog) return false;
    var open = false;
    for (var i = 0; i < upTo; i++) {
      open = _highlighter.carryBlockComment(
        lines[i],
        dialect,
        inBlockComment: open,
      );
    }
    return open;
  }

  String? _formatValueAtCursor({
    required WidgetRef ref,
    required String? signalRef,
    required int? cursor,
    required Map<String, Variable> variablesMap,
  }) {
    if (signalRef == null) return null;
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return null;
    final time = cursor ?? source.startTime;
    final raw = source.valueAt(signalRef, time);
    if (raw == null) return null;
    final variable = variablesMap[signalRef];
    final width = variable?.bitWidth ?? raw.length;
    final format =
        _findFormat(ref, signalRef) ?? ValueFormatService.defaultFormat(width);
    return ref
        .read(translatorRegistryProvider)
        .translate(
          TranslationRequest(
            rawValue: raw,
            bitWidth: width,
            format: format,
          ),
        )
        .text;
  }

  DisplayFormat? _findFormat(WidgetRef ref, String signalRef) {
    DisplayFormat? scan(List<SignalEntry> entries) {
      for (final entry in entries) {
        if (entry.kind == SignalEntryKind.signal &&
            entry.signalRef == signalRef) {
          return entry.format;
        }
        if (entry.kind == SignalEntryKind.group) {
          final nested = scan(entry.children);
          if (nested != null) return nested;
        }
      }
      return null;
    }

    return scan(ref.read(signalGroupsProvider).entries);
  }

  Future<void> _handleIdentifierTap(
    String name,
    Object? dataSource,
    Map<String, Variable> variablesMap,
  ) async {
    final notifier = ref.read(rtlSourceProvider.notifier);
    final navigated = await notifier.showByName(name);
    if (!navigated || !mounted) return;
    // Try to add the corresponding variable to the viewer.
    final state = ref.read(rtlSourceProvider);
    final path = state.currentSignalPath;
    if (path == null) return;
    final variable = _findVariableByPath(variablesMap, path);
    if (variable == null) return;
    ref.read(signalGroupsProvider.notifier).addSignal(variable);
  }

  Variable? _findVariableByPath(
    Map<String, Variable> variablesMap,
    String fullPath,
  ) {
    for (final v in variablesMap.values) {
      if (v.fullPath == fullPath) return v;
    }
    final lower = fullPath.toLowerCase();
    for (final v in variablesMap.values) {
      if (v.fullPath.toLowerCase() == lower) return v;
    }
    // Suffix match (local name).
    final dot = fullPath.lastIndexOf('.');
    final localLower = (dot < 0 ? fullPath : fullPath.substring(dot + 1))
        .toLowerCase();
    for (final v in variablesMap.values) {
      if (v.name.toLowerCase() == localLower) return v;
    }
    return null;
  }
}

// ── single source line ────────────────────────────────────────────────────────

class _SourceLine extends StatelessWidget {
  const _SourceLine({
    required this.lineNumber,
    required this.text,
    required this.spans,
    required this.isHighlighted,
    required this.onIdentifierTap,
  });

  final int lineNumber;
  final String text;
  final List<RtlTokenSpan> spans;
  final bool isHighlighted;
  final ValueChanged<String> onIdentifierTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final children = <InlineSpan>[];
    for (final span in spans) {
      final style = _styleFor(span.kind, colorScheme);
      if (span.kind == RtlTokenKind.plain && _isLikelyIdentifier(span.text)) {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: InkWell(
              hoverColor: colorScheme.primary.withValues(alpha: 0.08),
              onTap: () => onIdentifierTap(span.text),
              child: Text(span.text, style: style),
            ),
          ),
        );
      } else {
        children.add(TextSpan(text: span.text, style: style));
      }
    }

    return Container(
      color: isHighlighted ? colorScheme.primary.withValues(alpha: 0.18) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: children),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _styleFor(RtlTokenKind kind, ColorScheme cs) {
    final base = TextStyle(
      fontSize: 12,
      fontFamily: 'monospace',
      height: 1.3,
      color: cs.onSurface,
    );
    switch (kind) {
      case RtlTokenKind.plain:
        return base;
      case RtlTokenKind.keyword:
        return base.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w600,
        );
      case RtlTokenKind.typeKeyword:
        return base.copyWith(color: cs.tertiary);
      case RtlTokenKind.comment:
        return base.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        );
      case RtlTokenKind.number:
        return base.copyWith(color: cs.secondary);
      case RtlTokenKind.string:
        return base.copyWith(color: cs.error);
    }
  }

  /// Heuristic: spans tagged `plain` that look like a single identifier word
  /// (start with [A-Za-z_] and contain only identifier chars) are eligible
  /// for click-to-navigate.
  static bool _isLikelyIdentifier(String s) {
    if (s.isEmpty) return false;
    final first = s.codeUnitAt(0);
    final isStart =
        (first >= 0x41 && first <= 0x5A) ||
        (first >= 0x61 && first <= 0x7A) ||
        first == 0x5F;
    if (!isStart) return false;
    for (var i = 1; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final ok =
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A) ||
          c == 0x5F;
      if (!ok) return false;
    }
    return true;
  }
}
