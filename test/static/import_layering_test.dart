// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail for the layer dependency flow (ARCHITECTURE.md §6.2).
//
// THE PROBLEM THIS SOLVES:
// §6.2 documents `features → services → domain`, `core → nothing app-level`,
// `plugins → domain` — but for a long time nothing enforced it, and ~20 files
// had grown feature imports from below the feature layer. Auditing them
// showed nearly all were *composition/orchestration code misfiled by the
// simple four-arrow diagram* rather than true layering rot: per-tab/pane
// container composition roots, wire-protocol → provider translators
// (WCP/CXP/collab), diagnostics snapshot reporters, the route table, plugin
// registries. Rather than a big-bang move to a new directory, these are
// blessed as an explicit ORCHESTRATION TIER — named per-file in the
// allowlists below with a one-line justification each. The prose lives in
// ARCHITECTURE.md §6.2; this test is the enforcement.
//
// THE RULES ENFORCED (each rule names its allowlist):
//
//  1. domain/ imports nothing app-level (features/services/core/plugins/
//     shared). NO exceptions — a pure-Dart value type a domain file needs
//     moves into domain/ instead.
//  2. services/, plugins/, shared/ do not import features/ — except the
//     orchestration-tier files in [_orchestrationTier].
//  3. core/ does not import features/ — except orchestration-tier files —
//     and does not import services/ — except files under `core/providers/`,
//     the extension-point registry, whose job is to declare a cross-repo
//     extension point and bind its open-core default implementation (a
//     no-op service or a registry type).
//  4. Lateral feature isolation: a feature may import a SIBLING feature's
//     providers/commands/constants/root files freely (that is the sanctioned
//     time-bus / state-seam pattern; ~170 such imports exist), but NOT the
//     sibling's `widgets/` or `screens/` — except:
//       (a) `features/viewer/` — the sanctioned feature SHELL. The viewer
//           screen hosts every panel, dialog, menu surface, and toolbar;
//           importing sibling UI is its composition job.
//       (b) the (feature → imported path) pairs in [_lateralUiAllowlist].
//
// WHAT IS DELIBERATELY NOT REGULATED: features → {services, domain, core,
// shared, plugins} (the documented downward flow), services → services,
// services → {domain, core, shared}, lateral feature PROVIDER imports, and
// the app-level composition roots `lib/app.dart` / `lib/main.dart` (the
// bootstrap is by definition allowed to see everything).
//
// STALE-ENTRY HYGIENE: every allowlist entry must still be exercising its
// exemption (the file exists and still holds a violating import of the kind
// the entry grants). An entry that stops being needed FAILS the test until
// it is removed, so the lists cannot silently rot into blanket permission.
//
// When this test fails on new code, the fix is almost never "add my file to
// the allowlist": first ask whether the feature state you need should be
// read through a provider seam (rule 4), whether the code is actually
// orchestration that belongs in an existing orchestration file, or whether
// an open-core extension point is missing. Add an allowlist entry ONLY for
// genuine composition/orchestration responsibilities, with a justification.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Orchestration-tier files: composition
/// roots and cross-feature bridges whose *job* is to wire features together,
/// and which may therefore import from `features/`. Path → justification.
const Map<String, String> _orchestrationTier = <String, String>{
  // ── per-tab / per-pane container composition ──────────────────────────────
  'lib/services/tabs/wavecrux_tab_overrides.dart':
      'THE per-tab composition root — assembles every per-tab feature '
      'provider override (the registry per_tab_provider_scope_leak_test '
      'derives its truth from).',
  'lib/services/tabs/tab_container_manager.dart':
      'Creates/disposes per-tab ProviderContainers from the override '
      'registry.',
  'lib/services/tabs/active_tab_container.dart':
      "Resolves the active tab's container so app-level code can reach "
      'per-tab feature state.',
  'lib/services/panes/pane_container_manager.dart':
      'Pane hosting — mounts per-pane feature UI (incl. the viewer '
      'render-stats collector) into IdeLayout panes.',
  // ── wire-protocol → feature-provider translators ──────────────────────────
  'lib/services/remote/remote_control_notifier.dart':
      'WCP remote-control server — translates wire commands into feature '
      'provider mutations (cursor, viewer, session).',
  'lib/services/remote/cxp/cxp_inbound_handlers.dart':
      'CXP cross-probe inbound gossip — applies peer messages to feature '
      'providers.',
  'lib/services/remote/cxp/cxp_selection_emitter.dart':
      'CXP outbound — mirrors feature selection state to suite peers.',
  'lib/services/host_bridge/editor_host_bridge.dart':
      'Editor-host bridge — the third front door onto the same providers WCP '
      "and CXP already drive; applies an extension host's messages to feature "
      'providers (the waveform source) and mirrors selection back to it.',
  'lib/services/host_bridge/host_annotation_value_service.dart':
      'Editor-host RTL annotation — answers the extension '
      "host's standing value query by reading the active tab's waveform, "
      'cursor, signal-format and hierarchy feature providers, and re-answers '
      'it as the cursor moves. The outbound counterpart to the inbound '
      'branches in editor_host_bridge.dart, split out because it owns a '
      'lifetime (a re-bound per-tab cursor listen) rather than one dispatch.',
  'lib/services/remote/cxp/cxp_workspace_link.dart':
      'Shared-workspace link: gates the produced-artifact upsert on CXP '
      'server-running state and resolves design→waveform for inbound '
      'open-on-miss — a cross-cutting orchestration seam consumed from both '
      'services/ (inbound handler) and features/ (waveform source).',
  'lib/services/collaboration/collab_viewer_bridge.dart':
      'Collaboration bridge — mirrors per-tab viewer/cursor/marker feature '
      'state into the collab session and back.',
  'lib/services/ai/tools/viewer_navigation_tools.dart':
      'AI tool registry — exposes viewer navigation feature actions as '
      'callable AI tools.',
  // ── state-snapshot reporters ──────────────────────────────────────────────
  'lib/services/diagnostics/app_diagnostics_report_service.dart':
      'App-wide "copy diagnostics report" — snapshots feature provider '
      'state into the report text.',
  'lib/services/diagnostics/tab_diagnostics_report_service.dart':
      "Per-tab \"copy report\" — snapshots the tab's feature provider state.",
  // ── session / workspace plumbing ──────────────────────────────────────────
  'lib/services/session/session_reset.dart':
      'Resets per-tab feature state when a session/tab closes.',
  'lib/services/workspace/last_session_migration.dart':
      'Migrates the legacy last-session format into feature session state.',
  'lib/services/decoders/ffi/ffi_decoder_loader_provider.dart':
      "Binds runtime-loaded FFI decoders into the decoder feature's "
      'provider graph.',
  // ── core composition roots ────────────────────────────────────────────────
  'lib/core/router.dart':
      'The route table — a router mounts feature screens by definition.',
  'lib/core/shortcuts/action_context_provider.dart':
      'The action-surface gating seam (ARCHITECTURE §3.1.6) — aggregates '
      'feature providers into the single ActionContext every surface '
      'consumes.',
  'lib/core/theme/wavecrux_color_theme_bootstrap.dart':
      "Theme bootstrap — reads the settings feature's persisted color "
      'theme at startup.',
  // ── plugin registries ─────────────────────────────────────────────────────
  'lib/plugins/extra_stage_widgets_provider.dart':
      'Registry binding the built-in Stage widgets, whose implementations '
      'live in features/stage.',
  'lib/plugins/custom_stage_widget_registry_provider.dart':
      'Live custom-widget registry bridging the Stage runtime.',
  'lib/plugins/timeline_overlay_layers_provider.dart':
      'Registry binding the cocotb timeline overlay layer implementation.',
};

/// Sanctioned lateral feature→feature UI imports (rule 4b): importing
/// feature → sibling `widgets/`/`screens/` path → justification.
/// `features/viewer/` needs no entries — it is the sanctioned shell (4a).
const Map<String, Map<String, String>>
_lateralUiAllowlist = <String, Map<String, String>>{
  // The About dialog and the viewer open the beta issue reporter via the
  // shared `crux_issue_reporter` package (`CruxIssueReporterDialog`), not a
  // sibling feature widget, so no lateral feature→feature entry is needed.
  'signal_tree': {
    'package:wavecrux/features/decoders/widgets/decoder_picker_dialog.dart':
        'The signal-tree context menu opens the decoder picker.',
    'package:wavecrux/features/viewer/widgets/signal_removal_feedback.dart':
        "Remove All in Scope reports through the viewer's one bulk-removal "
        'Undo snackbar, so every bulk removal reads and reverses the same '
        'way.',
  },
  'panes': {
    'package:wavecrux/features/diagnostics/widgets/pane_render_stats_popover.dart':
        "Each pane's tab bar anchors the per-pane render-stats popover.",
    'package:wavecrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart':
        'The pane host mounts the per-tab diagnostics drawer.',
  },
  'diagnostics': {
    'package:wavecrux/features/viewer/widgets/render_stats_collector.dart':
        "Diagnostics reads the viewer's paint-stats collector widget "
        'to source render metrics.',
  },
};

/// One scanned import edge.
typedef _Edge = ({String file, String import});

void main() {
  // ── scan lib/ once, shared by every rule ──────────────────────────────────
  final edges = <_Edge>[];
  final scannedFiles = <String>{};

  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    // Plain throw: this runs at test-registration time, outside any test
    // body, where `expect` is not usable.
    throw StateError('run from the package root (flutter test)');
  }

  final importRe = RegExp(
    r"^\s*(?:import|export)\s+'([^']+)'",
    multiLine: true,
  );

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    // Generated code is exempt: codegen output and localization.
    if (path.endsWith('.g.dart') || path.startsWith('lib/l10n/')) continue;
    scannedFiles.add(path);
    final src = entity.readAsStringSync();
    for (final m in importRe.allMatches(src)) {
      final target = m.group(1)!;
      String? normalized;
      if (target.startsWith('package:wavecrux/')) {
        normalized = target;
      } else if (!target.contains(':')) {
        // Relative import — resolve against the file's directory so a
        // `../features/...` cannot slip past the package-prefix match.
        final baseSegments = path
            .split('/')
            .sublist(0, path.split('/').length - 1);
        final segments = [...baseSegments, ...target.split('/')];
        final resolved = <String>[];
        for (final s in segments) {
          if (s == '.') continue;
          if (s == '..') {
            if (resolved.isNotEmpty) resolved.removeLast();
            continue;
          }
          resolved.add(s);
        }
        final joined = resolved.join('/');
        if (joined.startsWith('lib/')) {
          normalized = 'package:wavecrux/${joined.substring(4)}';
        }
      }
      if (normalized == null) continue; // dart:/flutter/3rd-party import.
      edges.add((file: path, import: normalized));
    }
  }

  String tierOf(String libPath) {
    // `lib/<tier>/...` → tier name; `lib/features/<f>/...` handled separately.
    final parts = libPath.split('/');
    return parts.length > 1 ? parts[1] : '';
  }

  String importedTier(String pkgImport) {
    // `package:wavecrux/<tier>/...`
    final rest = pkgImport.substring('package:wavecrux/'.length);
    return rest.split('/').first;
  }

  String? featureOf(String libPath) {
    final parts = libPath.split('/');
    if (parts.length > 2 && parts[1] == 'features') return parts[2];
    return null;
  }

  String? importedFeature(String pkgImport) {
    final rest = pkgImport.substring('package:wavecrux/'.length).split('/');
    if (rest.length > 1 && rest.first == 'features') return rest[1];
    return null;
  }

  test('domain/ imports nothing app-level (no exceptions)', () {
    const forbidden = {'features', 'services', 'core', 'plugins', 'shared'};
    final violations = [
      for (final e in edges)
        if (tierOf(e.file) == 'domain' &&
            forbidden.contains(importedTier(e.import)))
          '${e.file} imports ${e.import}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'domain/ is pure Dart models/enums/interfaces — it may not import '
          'app layers. Move the imported code into domain/ if it is a pure '
          'value type, or move the '
          'domain file out of domain/ if it is not domain-shaped:\n'
          '${violations.join('\n')}',
    );
  });

  test(
    'services/, core/, plugins/, shared/ import features/ only from the '
    'orchestration tier',
    () {
      const lowerTiers = {'services', 'core', 'plugins', 'shared'};
      final violations = [
        for (final e in edges)
          if (lowerTiers.contains(tierOf(e.file)) &&
              importedTier(e.import) == 'features' &&
              !_orchestrationTier.containsKey(e.file))
            '${e.file} imports ${e.import}',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'Below the feature layer, only the sanctioned orchestration-tier '
            'files (ARCHITECTURE §6.2) may import features/. Either the '
            'feature state you need should be exposed through a '
            'service/domain seam, or your file is genuinely a composition '
            'root — '
            'in that case add it to _orchestrationTier in this test WITH a '
            'justification:\n${violations.join('\n')}',
      );
    },
  );

  test(
    'core/ imports services/ only from the core/providers/ extension-point '
    'registry',
    () {
      final violations = [
        for (final e in edges)
          if (tierOf(e.file) == 'core' &&
              importedTier(e.import) == 'services' &&
              !e.file.startsWith('lib/core/providers/'))
            '${e.file} imports ${e.import}',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'core/ has no app-level dependencies (§6.1). The one carve-out '
            'is lib/core/providers/ — the extension-point registry, which '
            'declares cross-repo seams and binds their open-core default '
            'implementations:\n${violations.join('\n')}',
      );
    },
  );

  test(
    'lateral feature imports stay out of sibling widgets/ and screens/ '
    '(viewer is the sanctioned shell)',
    () {
      final violations = <String>[];
      for (final e in edges) {
        final from = featureOf(e.file);
        final to = importedFeature(e.import);
        if (from == null || to == null || from == to) continue;
        // Rule 4a: the viewer feature is the shell — it hosts every panel,
        // dialog, and menu surface, so its sibling-UI imports are its job.
        if (from == 'viewer') continue;
        final rest = e.import.substring(
          'package:wavecrux/features/$to/'.length,
        );
        final isUi = rest.startsWith('widgets/') || rest.startsWith('screens/');
        if (!isUi) continue; // providers/commands/constants/root: sanctioned.
        if (_lateralUiAllowlist[from]?.containsKey(e.import) ?? false) {
          continue;
        }
        violations.add('features/$from (${e.file}) imports ${e.import}');
      }
      expect(
        violations,
        isEmpty,
        reason:
            "A feature may read a sibling's providers/commands/constants "
            '(the state-seam pattern) but not compose its widgets/screens — '
            'that couples UI trees across features. Host the widget from '
            'the viewer shell, expose the state through a provider, or (for '
            'a genuine cross-feature surface like a shared dialog) add a '
            'justified entry to _lateralUiAllowlist:\n'
            '${violations.join('\n')}',
      );
    },
  );

  test('allowlist entries are all still exercised (no stale exemptions)', () {
    final stale = <String>[];

    for (final path in _orchestrationTier.keys) {
      if (!scannedFiles.contains(path)) {
        stale.add('_orchestrationTier: $path no longer exists');
        continue;
      }
      final stillImportsFeatures = edges.any(
        (e) => e.file == path && importedTier(e.import) == 'features',
      );
      if (!stillImportsFeatures) {
        stale.add(
          '_orchestrationTier: $path no longer imports features/ — remove '
          'its entry',
        );
      }
    }

    _lateralUiAllowlist.forEach((feature, imports) {
      for (final imported in imports.keys) {
        final stillImported = edges.any(
          (e) => featureOf(e.file) == feature && e.import == imported,
        );
        if (!stillImported) {
          stale.add(
            '_lateralUiAllowlist: features/$feature no longer imports '
            '$imported — remove its entry',
          );
        }
      }
    });

    expect(
      stale,
      isEmpty,
      reason:
          'Every allowlist entry must still be needed; stale entries rot '
          'into blanket permission. Remove these:\n${stale.join('\n')}',
    );
  });
}
