// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_io/crux_io.dart' show revealInFileManager;
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/diagnostics/providers/dev_tools_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/dev_tools/vcd_generator_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Type signature for the OS save-file picker. Tests inject a stub so the
/// flow can be exercised without touching `FilePicker.platform`.
typedef SaveVcdPicker =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
    });

/// Type signature for the platform-specific reveal-in-file-manager launcher.
/// Tests inject a stub so we can assert it was invoked with the expected
/// path without spawning a real subprocess.
typedef RevealLauncher = Future<void> Function(String filePath);

Future<String?> _defaultSaveVcdPicker({
  required String dialogTitle,
  required String fileName,
}) => FilePicker.saveFile(
  // file_picker 12 requires bytes & writes the file; pass empty so it
  // only returns the chosen path and we write via our own service below.
  bytes: Uint8List(0),
  dialogTitle: dialogTitle,
  fileName: fileName,
  allowedExtensions: const ['vcd'],
  type: FileType.custom,
);

/// The reveal the dialog uses when none is injected: `crux_io`'s
/// [revealInFileManager], which every product's "Reveal in Finder /
/// Explorer / Files" shares. It selects the file on macOS and Windows,
/// resolves each file-manager command to an absolute path before spawning
/// it, and does nothing on the web.
@visibleForTesting
const RevealLauncher defaultRevealLauncher = revealInFileManager;

/// Standalone dialog for generating a synthetic VCD and either opening it in
/// a new tab or revealing it in the platform file manager.
///
/// Replaces the legacy Generator tab inside the diagnostics dialog. The
/// dialog reuses
/// [devToolsProvider] for slider / toggle / seed state so settings
/// persist across opens within the same session.
class GenerateTestVcdDialog extends ConsumerStatefulWidget {
  const GenerateTestVcdDialog({
    super.key,
    VcdGeneratorService? generatorService,
    SaveVcdPicker? savePicker,
    RevealLauncher? revealLauncher,
  }) : _generatorService = generatorService,
       _savePicker = savePicker,
       _revealLauncher = revealLauncher;

  final VcdGeneratorService? _generatorService;
  final SaveVcdPicker? _savePicker;
  final RevealLauncher? _revealLauncher;

  /// Opens the dialog as a modal on the current navigator.
  static Future<void> show(BuildContext context) async {
    await showCruxDialog<void>(
      context: context,
      // Editor dialogs hold in-progress user input: closing must be a
      // deliberate act (Close, Escape), never a stray scrim click — the
      // suite-wide dialog rule.
      barrierDismissible: false,
      builder: (_) => const GenerateTestVcdDialog(),
    );
  }

  @override
  ConsumerState<GenerateTestVcdDialog> createState() =>
      _GenerateTestVcdDialogState();
}

class _GenerateTestVcdDialogState extends ConsumerState<GenerateTestVcdDialog> {
  late TextEditingController _seedController;
  String? _destinationPath;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    final seed = ref.read(devToolsProvider).seed;
    _seedController = TextEditingController(text: '$seed');
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  // Maps a linear [0, 1] slider value to log-scaled duration [100, 1,000,000].
  static int _sliderToDuration(double v) =>
      pow(10, 2 + v * 4).round().clamp(100, 1000000);

  static double _durationToSlider(int duration) =>
      ((log(duration) / log(10)) - 2) / 4;

  String _suggestedFileName() {
    final s = ref.read(devToolsProvider);
    return 'wavecrux_sample_s${s.signalCount}_d${s.duration}_seed${s.seed}.vcd';
  }

  VcdGeneratorConfig _currentConfig() {
    final s = ref.read(devToolsProvider);
    return VcdGeneratorConfig(
      signalCount: s.signalCount,
      duration: s.duration,
      includeAnalog: s.includeAnalog,
      includeXz: s.includeXz,
      seed: s.seed,
    );
  }

  Future<void> _chooseDestination() async {
    final l10n = L10N.of(context);
    final picker = widget._savePicker ?? _defaultSaveVcdPicker;
    final path = await picker(
      dialogTitle: l10n.toolsGenerateTestVcdSavePickerTitle,
      fileName: _suggestedFileName(),
    );
    // The picker is its own window; where the app stays live behind it, the
    // dialog may have closed before the answer arrives.
    if (path == null || !mounted) return;
    setState(() => _destinationPath = path);
  }

  /// Returns the absolute path the file was written to, or null if writing
  /// failed (in which case a snackbar has already been shown).
  Future<String?> _writeFile() async {
    final dest = _destinationPath;
    if (dest == null) return null;
    final l10n = L10N.of(context);
    try {
      final service = widget._generatorService ?? VcdGeneratorService();
      final content = service.generate(_currentConfig());
      // Read before the write: the dialog can close while it is pending.
      final devTools = ref.read(devToolsProvider.notifier);
      await File(dest).writeAsString(content);
      devTools.setLastGeneratedPath(dest);
      return dest;
    } on Object catch (e) {
      if (mounted) {
        showCruxErrorSnack(
          context,
          l10n.toolsGenerateTestVcdGenerateError(
            e.toString(),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _generateAndOpenInNewTab() async {
    if (_isGenerating || _destinationPath == null) return;
    setState(() => _isGenerating = true);
    try {
      final path = await _writeFile();
      if (path == null || !mounted) return;
      // Append the new file as a tab in the active pane. Uses the same
      // canonical openFile pattern as File→Open in [ViewerScreen]; openFile
      // returns the new tab's id directly.
      final tabId = await ref.wavecruxWorkspace.openFile(path);
      if (!mounted) return;
      final container = ref
          .read(tabContainerManagerProvider)
          .containerFor(tabId);
      unawaited(
        container.read(waveformSourceProvider.notifier).openFile(path),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateAndReveal() async {
    if (_isGenerating || _destinationPath == null) return;
    setState(() => _isGenerating = true);
    try {
      final path = await _writeFile();
      if (path == null || !mounted) return;
      final launcher = widget._revealLauncher ?? defaultRevealLauncher;
      await launcher(path);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(devToolsProvider);
    final notifier = ref.read(devToolsProvider.notifier);
    final hasDestination = _destinationPath != null;

    return CruxDialog(
      title: l10n.toolsGenerateTestVcdTitle,
      width: 680,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledControl(
            label: l10n.toolsGenerateTestVcdSignalCount,
            value: '${state.signalCount}',
            child: CruxSlider(
              min: 1,
              max: 500,
              value: state.signalCount.toDouble(),
              onChanged: (v) => notifier.setSignalCount(v.round()),
            ),
          ),
          const SizedBox(height: 8),
          _LabeledControl(
            label: l10n.toolsGenerateTestVcdDuration,
            value: _formatDuration(state.duration),
            child: CruxSlider(
              value: _durationToSlider(state.duration),
              onChanged: (v) => notifier.setDuration(_sliderToDuration(v)),
            ),
          ),
          const SizedBox(height: 8),
          // Options of a form that applies on its own buttons: checkboxes.
          CruxFormRow.checkbox(
            label: l10n.toolsGenerateTestVcdIncludeAnalog,
            value: state.includeAnalog,
            onChanged: (v) => notifier.setIncludeAnalog(value: v),
          ),
          const SizedBox(height: 4),
          CruxFormRow.checkbox(
            label: l10n.toolsGenerateTestVcdIncludeXz,
            value: state.includeXz,
            onChanged: (v) => notifier.setIncludeXz(value: v),
          ),
          const SizedBox(height: 8),
          CruxFormRow(
            label: l10n.toolsGenerateTestVcdSeed,
            child: SizedBox(
              width: 120,
              child: TextField(
                controller: _seedController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) notifier.setSeed(n);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Destination row.
          Text(
            l10n.toolsGenerateTestVcdDestinationLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _destinationPath ?? l10n.toolsGenerateTestVcdNoDestination,
                  key: const Key('generate_test_vcd_destination_text'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: hasDestination
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('generate_test_vcd_choose_destination'),
                onPressed: _isGenerating ? null : _chooseDestination,
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(l10n.toolsGenerateTestVcdChooseDestination),
              ),
            ],
          ),
          if (_isGenerating) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        CruxDialogAction(
          label: l10n.toolsGenerateTestVcdClose,
          onPressed: _isGenerating ? null : () => Navigator.of(context).pop(),
        ),
        CruxDialogAction(
          key: const Key('generate_test_vcd_generate_and_reveal'),
          label: l10n.toolsGenerateTestVcdGenerateAndReveal,
          onPressed: (_isGenerating || !hasDestination)
              ? null
              : _generateAndReveal,
        ),
        CruxDialogAction(
          key: const Key('generate_test_vcd_generate_and_open'),
          label: l10n.toolsGenerateTestVcdGenerateAndOpen,
          role: CruxDialogActionRole.primary,
          onPressed: (_isGenerating || !hasDestination)
              ? null
              : _generateAndOpenInNewTab,
        ),
      ],
    );
  }

  String _formatDuration(int duration) {
    if (duration >= 1000000) {
      return '${(duration / 1000000).toStringAsFixed(1)}M';
    }
    if (duration >= 1000) return '${(duration / 1000).toStringAsFixed(1)}k';
    return '$duration';
  }
}

// ── Private helpers ──────────────────────────────────────────────────────────

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.label,
    required this.value,
    required this.child,
  });

  final String label;
  final String value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        child,
      ],
    );
  }
}
