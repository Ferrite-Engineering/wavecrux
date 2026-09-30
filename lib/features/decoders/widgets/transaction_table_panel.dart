// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_license/crux_license.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/constants.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/core/utils/focus_opening_menu.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_body.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/selected_transaction_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/plugins/transaction_table_exporters_provider.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

/// Maximum transaction rows rendered into the table at once.
///
/// Sized from measurement, not taste: the `DataTable` costs roughly 3–4 ms
/// per row to lay out, so a couple of thousand rows is the most that keeps
/// the pane's first frame inside a second or so. The filtered set is sorted
/// before it is capped, so the rows shown are the top of whatever order the
/// user chose.
const int kTransactionTableRenderLimit = 2000;

/// Spreadsheet-style table showing all decoded transactions from all active
/// decoders.
///
/// Columns: #, Decoder, Start, End, Label, plus one dynamic column per unique
/// field key found across the current transaction set.  Every column is
/// sortable by clicking its header.  A decoder-filter dropdown and a text
/// search field appear above the table.
///
/// Clicking a row places the primary cursor at that transaction's start time
/// and sets the selected transaction so the canvas overlay highlights it. The
/// rows, their keyboard control and what a screen reader hears for them are
/// [TransactionTableBody]; the decoder filter is a named button whose menu
/// opens on its first item from the keyboard.
///
/// An "Export CSV" button at the top-right writes all visible rows to a
/// user-chosen CSV file — every filtered row, not just the rendered ones.
///
/// **Rendered rows are capped at [kTransactionTableRenderLimit].** Decoders
/// run over the whole trace, so a UART at 115 200 baud over a one-second
/// capture is already ~11 500 transactions and a bus capture is far more.
/// [TransactionTableBody] is a `DataTable`, which materializes a row per
/// transaction and sizes its columns intrinsically — i.e. it walks every row,
/// per column, per layout pass. Measured on this machine: ~1.8 s to first
/// frame at 100 rows, 8.5 s at 2 000, and 20 000 rows had not finished its
/// first layout after fifteen minutes. The cap keeps the pane responsive;
/// sort and search are how the user reaches the rest, and export still writes
/// everything. Lifting it properly means virtualizing the table body, which
/// carries its own keyboard-navigation and screen-reader contract.
class TransactionTablePanel extends ConsumerStatefulWidget {
  const TransactionTablePanel({
    super.key,
    this.renderLimit = kTransactionTableRenderLimit,
  });

  /// Maximum rows handed to [TransactionTableBody]. Defaults to
  /// [kTransactionTableRenderLimit]; a test lowers it so the capped path can
  /// be exercised without laying out two thousand rows.
  final int renderLimit;

  @override
  ConsumerState<TransactionTablePanel> createState() =>
      _TransactionTablePanelState();

  /// Builds the CSV string for [rows] with [fieldKeys] as dynamic columns.
  ///
  /// All values are always quoted so that spreadsheet applications (Numbers,
  /// Excel) treat hex literals (0x...) as text rather than converting them
  /// to decimal.
  static String buildCsvContent(
    List<TableTransaction> rows,
    List<String> fieldKeys,
  ) {
    final buffer = StringBuffer()..write('#,Decoder,Start,End,Label,Error');
    for (final k in fieldKeys) {
      buffer.write(',${_csvEscape(k)}');
    }
    buffer.writeln();

    for (final row in rows) {
      final tx = row.transaction;
      buffer
        ..write('${row.rowIndex},')
        ..write('${_csvEscape(row.decoderDisplayName)},')
        ..write('${tx.startTime},')
        ..write('${tx.endTime},')
        ..write('${_csvEscape(tx.label)},')
        ..write('${tx.isError}');
      for (final k in fieldKeys) {
        buffer.write(',${_csvEscape(tx.fields[k] ?? '')}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  // Always quote every value so spreadsheet applications (Numbers, Excel)
  // treat hex literals (0x...) as text rather than converting them to decimal.
  static String _csvEscape(String value) => '"${value.replaceAll('"', '""')}"';
}

class _TransactionTablePanelState extends ConsumerState<TransactionTablePanel> {
  final _searchController = TextEditingController();
  final _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  // ── row interaction ───────────────────────────────────────────────────────

  void _onRowTap(TableTransaction row) {
    ref
      ..read(
        selectedTransactionProvider.notifier,
      ).select(row.transaction, row.decoderInstanceId)
      ..read(
        cursorStateProvider.notifier,
      ).placePrimary(row.transaction.startTime)
      ..read(navigationProvider.notifier).jumpToTime(row.transaction.startTime);
  }

  // ── CSV export ────────────────────────────────────────────────────────────

  Future<void> _exportCsv(
    List<TableTransaction> rows,
    List<String> fieldKeys,
    L10N l10n,
  ) async {
    final csv = TransactionTablePanel.buildCsvContent(rows, fieldKeys);

    // In the browser the CSV downloads; there is no save dialog that returns
    // a path to write to.
    final download = ref.read(browserDownloadProvider);
    if (download != null) {
      const fileName = 'transactions.csv';
      await download(fileName: fileName, bytes: utf8.encode(csv));
      if (mounted) {
        showCruxInfoSnack(
          context,
          l10n.transactionTableExportCsvSaved(fileName),
        );
      }
      return;
    }

    if (ref.read(systemDialogInFlightProvider)) return;
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final String? path;
    try {
      path = await FilePicker.saveFile(
        // file_picker 12 requires bytes & writes the file; pass empty so it
        // only returns the chosen path and we write via our own service below.
        bytes: Uint8List(0),
        fileName: 'transactions.csv',
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );
    } finally {
      inFlight.end();
    }
    if (path == null || !mounted) return;
    try {
      await File(path).writeAsString(csv);
      if (mounted) {
        showCruxInfoSnack(
          context,
          l10n.transactionTableExportCsvSaved(path.split('/').last),
        );
      }
    } on Exception {
      // Ignore: file save is best-effort; errors are surfaced by the OS.
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final decoders = ref.watch(activeDecodersProvider);
    final filter = ref.watch(transactionTableFilterProvider);
    final rows = ref.watch(filteredTransactionsProvider);
    // What the table renders. `rows` — the whole filtered, sorted set — is
    // what export writes and what the empty-state check reads.
    final rendered = rows.length > widget.renderLimit
        ? rows.sublist(0, widget.renderLimit)
        : rows;
    final filterNotifier = ref.read(transactionTableFilterProvider.notifier);
    final selected = ref.watch(selectedTransactionProvider);
    final extraExporters = ref.watch(transactionTableExportersProvider);

    // Collect field keys from ALL active decoder transactions (not just
    // filtered rows) so columns stay stable while the user types a query.
    final fieldKeys = _collectFieldKeys(decoders)..sort();

    // Build extra-exporter menu entries: one per (exporter, applicable
    // currently-visible decoder) pair. "Currently visible" honors the active
    // decoder filter so the menu doesn't offer to export decoders the user
    // has filtered out.
    final visibleDecoders = filter.decoderIdFilter == null
        ? decoders
        : decoders.where((d) => d.id == filter.decoderIdFilter).toList();
    final exporterEntries = <_ExporterMenuEntry>[];
    for (final decoder in visibleDecoders) {
      for (final exporter in extraExporters) {
        if (exporter.isApplicable(decoder)) {
          exporterEntries.add(
            _ExporterMenuEntry(exporter: exporter, decoder: decoder),
          );
        }
      }
    }

    // The filter bar's separator is a bottom BORDER, not a 1 px Divider
    // child: at the dock's minimum pane height the content region is exactly
    // the bar's height, and bar + divider + Expanded(0) overflowed the
    // column by that 1 px on every open/close (the pane animation passes
    // through the minimum). A border paints inside the bar's own bounds and
    // adds no layout height.
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: _FilterBar(
            decoders: decoders,
            filter: filter,
            searchController: _searchController,
            onDecoderChanged: filterNotifier.setDecoderFilter,
            onRemoveDecoder: (id) {
              // If the removed decoder is the active filter, reset to "all".
              if (filter.decoderIdFilter == id) {
                filterNotifier.setDecoderFilter(null);
              }
              ref.read(activeDecodersProvider.notifier).removeDecoder(id);
            },
            onConfigureDecoder: (id) {
              final target = decoders.where((d) => d.id == id).firstOrNull;
              if (target == null) return;
              final definition = DecoderRegistry.instance.getDefinition(
                target.decoderId,
              );
              if (definition == null) return;
              unawaited(
                DecoderConfigDialog.showEdit(
                  context,
                  definition: definition,
                  instanceId: id,
                  instanceNumber: target.instanceNumber,
                  initialConfig: target.config,
                  // Pre-read from THIS panel's per-tab ref. A dialog route is a
                  // child of the Navigator, which sits above the per-tab
                  // UncontrolledProviderScope, so the dialog's own `ref` would
                  // resolve the root container — where no file is loaded. The
                  // edit would then be written to the root notifier and the
                  // active tab would silently keep its old config. The sibling
                  // call sites (decoder_picker_dialog, decoder_list_entry)
                  // already pass these; this one did not.
                  signalMap: ref.read(signalVariablesMapProvider),
                  decodersNotifier: ref.read(activeDecodersProvider.notifier),
                ),
              );
            },
            onSearchChanged: filterNotifier.setSearchQuery,
            onExport: rows.isEmpty
                ? null
                : () => _exportCsv(rows, fieldKeys, l10n),
            extraExporters: exporterEntries,
            onExtraExport: (entry) => entry.exporter.export(
              context: context,
              ref: ref,
              decoder: entry.decoder,
            ),
            l10n: l10n,
          ),
        ),
        Expanded(
          // The dock sweeps this pane through tiny heights on open/close;
          // CruxPanelEmptyState's inner Column would RenderFlex-overflow
          // below ~90 px. Scroll + minHeight keeps the message centered at
          // normal sizes and clips gracefully when squeezed.
          child: rows.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: CruxPanelEmptyState(
                        message: decoders.isNotEmpty
                            ? l10n.transactionTableEmptyNoTransactions
                            : l10n.transactionTableEmptyNoDecoders,
                      ),
                    ),
                  ),
                )
              : TransactionTableBody(
                  rows: rendered,
                  fieldKeys: fieldKeys,
                  filter: filter,
                  selectedRow: selected,
                  horizontalScrollController: _horizontalScrollController,
                  onSort: filterNotifier.setSortColumnAndDirection,
                  onRowTap: _onRowTap,
                ),
        ),
        // Says so when the table is not showing everything the filter
        // matched. Below the table, where the rows run out.
        if (rendered.length < rows.length)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Text(
              l10n.transactionTableTruncated(rendered.length, rows.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static List<String> _collectFieldKeys(List<ActiveDecoder> decoders) {
    final keys = <String>{};
    for (final d in decoders) {
      for (final tx in d.transactions) {
        keys.addAll(tx.fields.keys);
      }
    }
    return keys.toList();
  }
}

// ── _ExporterMenuEntry ────────────────────────────────────────────────────────

/// One row in the extra-exporters overflow menu: pairs an exporter with the
/// specific decoder instance it is being applied to. Constructed by the panel
/// at build time from the cross-product of `transactionTableExportersProvider`
/// and the currently visible decoder list.
@immutable
class _ExporterMenuEntry {
  const _ExporterMenuEntry({required this.exporter, required this.decoder});

  final TransactionTableExporter exporter;
  final ActiveDecoder decoder;
}

// ── _FilterBar ────────────────────────────────────────────────────────────────

/// Sealed result type returned by the decoder filter popup menu.
sealed class _DecoderMenuAction {
  const _DecoderMenuAction();
}

class _DecoderMenuSelect extends _DecoderMenuAction {
  const _DecoderMenuSelect(this.id);
  final String? id;
}

class _DecoderMenuRemove extends _DecoderMenuAction {
  const _DecoderMenuRemove(this.id);
  final String id;
}

class _DecoderMenuConfigure extends _DecoderMenuAction {
  const _DecoderMenuConfigure(this.id);
  final String id;
}

class _FilterBar extends StatefulWidget {
  const _FilterBar({
    required this.decoders,
    required this.filter,
    required this.searchController,
    required this.onDecoderChanged,
    required this.onRemoveDecoder,
    required this.onConfigureDecoder,
    required this.onSearchChanged,
    required this.onExport,
    required this.extraExporters,
    required this.onExtraExport,
    required this.l10n,
  });

  final List<ActiveDecoder> decoders;
  final TransactionTableFilter filter;
  final TextEditingController searchController;
  final ValueChanged<String?> onDecoderChanged;
  final ValueChanged<String> onRemoveDecoder;
  final ValueChanged<String> onConfigureDecoder;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onExport;
  final List<_ExporterMenuEntry> extraExporters;
  final ValueChanged<_ExporterMenuEntry> onExtraExport;
  final L10N l10n;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  String _instanceLabel(ActiveDecoder d) {
    final baseName =
        DecoderRegistry.instance.getDefinition(d.decoderId)?.displayName ??
        d.decoderId;
    return d.instanceLabel(baseName);
  }

  String get _currentFilterLabel {
    final id = widget.filter.decoderIdFilter;
    if (id == null) return widget.l10n.transactionTableFilterAllDecoders;
    final match = widget.decoders.where((d) => d.id == id).firstOrNull;
    return match != null
        ? _instanceLabel(match)
        : widget.l10n.transactionTableFilterAllDecoders;
  }

  final GlobalKey _filterButtonKey = GlobalKey();

  /// Opens the decoder menu below the filter button, whether it was clicked
  /// or activated from the keyboard, with focus on its first item.
  Future<void> _showDecoderMenu(BuildContext context) async {
    final l10n = widget.l10n;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final button = _filterButtonKey.currentContext?.findRenderObject();
    if (button is! RenderBox || !button.hasSize) return;
    final anchor = Rect.fromPoints(
      button.localToGlobal(
        button.size.bottomLeft(Offset.zero),
        ancestor: overlay,
      ),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );

    final items = <PopupMenuEntry<_DecoderMenuAction>>[
      PopupMenuItem<_DecoderMenuAction>(
        value: const _DecoderMenuSelect(null),
        child: Semantics(
          selected: widget.filter.decoderIdFilter == null,
          child: Text(l10n.transactionTableFilterAllDecoders),
        ),
      ),
      if (widget.decoders.isNotEmpty) const PopupMenuDivider(),
      for (final d in widget.decoders)
        _DecoderMenuEntry(
          child: Builder(
            builder: (ctx) => _DecoderMenuItem(
              label: _instanceLabel(d),
              isSelected: widget.filter.decoderIdFilter == d.id,
              onSelect: () => Navigator.of(ctx).pop(_DecoderMenuSelect(d.id)),
              onConfigure: () =>
                  Navigator.of(ctx).pop(_DecoderMenuConfigure(d.id)),
              onRemove: () => Navigator.of(ctx).pop(_DecoderMenuRemove(d.id)),
              l10n: l10n,
            ),
          ),
        ),
    ];

    final shown = showMenu<_DecoderMenuAction>(
      context: context,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      items: items,
    );
    focusFirstItemOfOpeningMenu();
    final action = await shown;
    if (!mounted || action == null) return;

    switch (action) {
      case _DecoderMenuSelect(:final id):
        widget.onDecoderChanged(id);
      case _DecoderMenuRemove(:final id):
        widget.onRemoveDecoder(id);
      case _DecoderMenuConfigure(:final id):
        widget.onConfigureDecoder(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Decoder filter button — opens custom menu with remove/configure.
          // A focusable button named for what it filters, with the current
          // filter as its value: it was a bare gesture detector, so the
          // keyboard could not filter, configure or remove a decoder.
          Semantics(
            container: true,
            button: true,
            label: l10n.transactionTableDecoderFilterLabel,
            value: _currentFilterLabel,
            child: InkWell(
              key: _filterButtonKey,
              borderRadius: BorderRadius.circular(4),
              onTap: () => _showDecoderMenu(context),
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentFilterLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Search field.
          SizedBox(
            width: 220,
            height: 32,
            child: TextField(
              controller: widget.searchController,
              decoration: InputDecoration(
                hintText: l10n.transactionTableSearchHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: widget.searchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: l10n.transactionTableClearSearchTooltip,
                        icon: const Icon(Icons.clear, size: 16),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          widget.searchController.clear();
                          widget.onSearchChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: widget.onSearchChanged,
            ),
          ),
          const SizedBox(width: 8),
          // Export CSV button.
          TextButton.icon(
            onPressed: widget.onExport,
            icon: const Icon(Icons.download, size: 16),
            label: Text(l10n.transactionTableExportCsv),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
          // Overflow menu — extra exporters contributed by the Pro overlay
          // (e.g. Ethernet PCAP). Hidden when no exporter applies to any
          // currently visible decoder.
          if (widget.extraExporters.isNotEmpty) ...[
            const SizedBox(width: 4),
            PopupMenuButton<_ExporterMenuEntry>(
              tooltip: l10n.transactionTableExportMoreTooltip,
              icon: const Icon(Icons.more_vert, size: 18),
              padding: EdgeInsets.zero,
              onSelected: widget.onExtraExport,
              itemBuilder: (context) => [
                for (final entry in widget.extraExporters)
                  PopupMenuItem<_ExporterMenuEntry>(
                    value: entry,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            entry.exporter.labelFor(context, entry.decoder),
                          ),
                        ),
                        if (entry.exporter.requiredTier !=
                            LicenseTier.openCore) ...[
                          const SizedBox(width: 8),
                          WaveCruxFeatureTierBadge(
                            requiredTier: entry.exporter.requiredTier,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ],
          // Pop-out affordance: present but disabled until kMultiWindowAvailable.
          const SizedBox(width: 4),
          Opacity(
            opacity: kMultiWindowAvailable ? 1.0 : 0.38,
            child: AbsorbPointer(
              child: IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: l10n.panelPopOutDisabledTooltip,
                // null renders the button visually disabled; AbsorbPointer
                // additionally blocks touch while kMultiWindowAvailable is false.
                onPressed: null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _DecoderMenuEntry ─────────────────────────────────────────────────────────

/// A decoder row in the filter menu, as a plain menu entry.
///
/// It used to sit inside a `PopupMenuItem`, whose own ink well wrapped the
/// row's three controls: a keyboard landed on that outer well first, and
/// Enter there closed the menu with no action.
class _DecoderMenuEntry extends PopupMenuEntry<_DecoderMenuAction> {
  const _DecoderMenuEntry({required this.child});

  final Widget child;

  @override
  double get height => 40;

  @override
  bool represents(_DecoderMenuAction? value) => false;

  @override
  State<_DecoderMenuEntry> createState() => _DecoderMenuEntryState();
}

class _DecoderMenuEntryState extends State<_DecoderMenuEntry> {
  @override
  Widget build(BuildContext context) => widget.child;
}

// ── _DecoderMenuItem ──────────────────────────────────────────────────────────

/// One row in the decoder filter popup menu: label + configure icon + remove icon.
///
/// Tapping the label area calls [onSelect]; each icon pops the menu with its
/// own action via [Navigator.of(context).pop].
class _DecoderMenuItem extends StatelessWidget {
  const _DecoderMenuItem({
    required this.label,
    required this.isSelected,
    required this.onSelect,
    required this.onConfigure,
    required this.onRemove,
    required this.l10n,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onConfigure;
  final VoidCallback onRemove;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          // Name area — tapping selects/filters.
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              selected: isSelected,
              label: label,
              child: InkWell(
                onTap: onSelect,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (isSelected)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Configure icon. Named for its decoder: with several decoders a
          // screen reader otherwise hears a row of identical "Configure"s.
          IconButton(
            tooltip: l10n.transactionTableConfigureDecoder(label),
            icon: const Icon(Icons.settings_outlined, size: 15),
            onPressed: onConfigure,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Remove icon.
          IconButton(
            tooltip: l10n.transactionTableRemoveDecoder(label),
            icon: const Icon(Icons.close, size: 15),
            onPressed: onRemove,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
