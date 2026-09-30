// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart'
    show
        kTelemetryUncaughtErrorKinds,
        kTelemetryUncaughtErrorLibraries,
        kTelemetryUncaughtErrorSources;
import 'package:meta/meta.dart';

/// One entry of the WaveCrux event catalog: an event name and the closed
/// vocabulary of each property it may carry.
///
/// [enumeratedValues] lists the string values a property key is allowed to
/// take. A key mapped to an empty list carries something that is not a closed
/// string set — a bool, or a bounded integer — and is checked by the
/// conformance test's per-key rules instead.
@immutable
class TelemetryCatalogEvent {
  /// Pins one catalog event and its property vocabulary.
  const TelemetryCatalogEvent(
    this.name, {
    this.enumeratedValues = const <String, List<String>>{},
    this.boolProperties = const <String>[],
    this.intProperties = const <String>[],
  });

  /// The catalog event name, as recorded.
  final String name;

  /// String-valued properties → every value the call site may emit.
  final Map<String, List<String>> enumeratedValues;

  /// Properties whose value is a `bool`.
  final List<String> boolProperties;

  /// Properties whose value is a bounded integer.
  final List<String> intProperties;

  /// Every property key this event may carry.
  Iterable<String> get propertyKeys => <String>[
    ...enumeratedValues.keys,
    ...boolProperties,
    ...intProperties,
  ];
}

/// **The** WaveCrux event catalog — every telemetry event either repository
/// may record, with the closed vocabulary of every property.
///
/// This list is the pinned event catalog; the user-facing account of what is
/// collected is `https://edacrux.app/telemetry`. Two tests hold it to that
/// role: one scans both source trees and fails on an
/// event name that is recorded but not listed here, and one checks every name,
/// key and value in this list against the ingestion Worker's grammar.
///
/// The second check is the load-bearing one. The Worker drops a malformed
/// event name *silently* — the batch still returns 202, the row is counted
/// only in the response's `dropped` field, and the client is not told. A
/// property whose key or value fails its class is dropped while the event is
/// kept, which is worse: the counter looks healthy and its dimension is
/// simply, permanently empty. Neither failure is visible from the app, from
/// the queue, or from a dashboard that has never seen the missing rows. The
/// conformance test is the only place either one can be caught.
const List<TelemetryCatalogEvent>
kWavecruxEventCatalog = <TelemetryCatalogEvent>[
  // ── workspace, tabs, panes (open core) ─────────────────────────────────
  TelemetryCatalogEvent(
    'workspace.restored',
    intProperties: <String>['tabs', 'panes'],
  ),
  TelemetryCatalogEvent('workspace.created'),
  TelemetryCatalogEvent('workspace.reset'),
  TelemetryCatalogEvent('workspace.named.saved'),
  TelemetryCatalogEvent(
    'workspace.named.opened',
    intProperties: <String>['tabs', 'panes'],
  ),
  TelemetryCatalogEvent(
    'tab.opened',
    intProperties: <String>['tabs', 'panes'],
  ),
  TelemetryCatalogEvent('tab.exported'),
  TelemetryCatalogEvent('tab.dragged_to_pane'),
  TelemetryCatalogEvent('pane.split'),
  TelemetryCatalogEvent('pane.closed'),

  // ── the launch set (open core) ─────────────────────────────────────────
  TelemetryCatalogEvent(
    'file.opened',
    enumeratedValues: <String, List<String>>{
      // `WaveformFormat.values` plus the streaming transport, which has no
      // container format to resolve. The conformance test asserts the enum
      // half against `WaveformFormat` so a new reader cannot be added
      // without appearing here.
      'format': <String>[
        'vcd',
        'fst',
        'ghw',
        'lxt',
        'lxt2',
        'unknown',
        'streaming',
      ],
    },
  ),
  TelemetryCatalogEvent(
    'decoder.opened',
    enumeratedValues: <String, List<String>>{
      // Open-core built-ins, the Pro pack's protocols, and `plugin` — the
      // one token every runtime-loaded FFI decoder reports, whatever its
      // manifest calls it.
      'decoder': <String>[
        'spi',
        'i2c',
        'uart',
        'axi4_lite',
        'apb',
        'ahb_lite',
        'wishbone',
        'spi_flash',
        'riscv',
        'can',
        'axi4_full',
        'mdio',
        'pcie_tlp',
        'usb2',
        'jtag',
        'axi_stream',
        'avalon_mm',
        'avalon_st',
        'ethernet_mii',
        'ethernet_rmii',
        'ethernet_gmii',
        'ethernet_rgmii',
        'ethernet_axis',
        'plugin',
      ],
    },
  ),
  TelemetryCatalogEvent(
    'export.completed',
    enumeratedValues: <String, List<String>>{
      'kind': <String>['vcd', 'saif', 'png', 'svg'],
    },
  ),
  TelemetryCatalogEvent(
    'search.used',
    enumeratedValues: <String, List<String>>{
      'mode': <String>['signal_substring', 'signal_glob', 'pattern'],
    },
  ),
  TelemetryCatalogEvent('session.gtkw_imported'),

  // ── the share bundle (open core) ────────────────────────────────────────
  // The instrument for the distribution thesis: "an annotated waveform is
  // a thing people send, and a pack is what makes the recipient install
  // WaveCrux". Two counters, no properties — deliberately. The interesting
  // ratio is packs opened against packs exported, and every dimension that
  // would make it more interesting (which signals, whose annotations, how
  // big) is design data we do not collect. If the loop is real these two
  // numbers say so within a beta cycle; if it is not, that is worth
  // knowing before Enterprise layers are built on top of it.
  TelemetryCatalogEvent('pack.exported'),
  TelemetryCatalogEvent('pack.opened'),
  TelemetryCatalogEvent(
    'tool.opened',
    enumeratedValues: <String, List<String>>{
      'tool': <String>[
        'comparison',
        'activity',
        'fsm',
        'x_trace',
        'statistics',
      ],
    },
  ),
  TelemetryCatalogEvent(
    'format.set',
    enumeratedValues: <String, List<String>>{
      // `DisplayFormat.values` snake_cased by `telemetryEnumToken`; the
      // conformance test derives the same list from the enum so the two
      // cannot drift.
      'format': <String>[
        'binary',
        'hexadecimal',
        'octal',
        'unsigned_decimal',
        'signed_decimal',
        'ascii',
        'ieee754_single',
        'ieee754_double',
        'fixed_point_q',
        'signed_magnitude',
        'gray_code',
        'named_enum',
      ],
    },
  ),
  TelemetryCatalogEvent(
    'cxp.crossprobe',
    enumeratedValues: <String, List<String>>{
      'direction': <String>['inbound', 'outbound'],
    },
    boolProperties: <String>['honored'],
  ),
  TelemetryCatalogEvent('ai.explain_used'),
  TelemetryCatalogEvent(
    'stage.widget_added',
    enumeratedValues: <String, List<String>>{
      // Open-core families, the Pro pack's, and `custom` for a community
      // `.wcrux-widget` bundle. `nexysa7` / `artya7` are the two open-core
      // board ids whose declared form is camelCase; the Pro pack's ids are
      // `wavecrux.pro.<token>` and contribute their last segment. The Pro
      // repo's conformance test walks its own registry and fails if a
      // family it ships is missing from this list.
      'widget': <String>[
        // open core
        'led',
        'toggle_switch',
        'seven_segment',
        'level_bar',
        'state_indicator',
        'bus_readout',
        'signal_graph',
        'basys3',
        'de10_lite',
        'nexysa7',
        'artya7',
        'tachometer',
        'riscv_commit',
        'pipeline',
        // Pro pack
        'audio_waveform',
        'bldc_motor',
        'bus_dashboard',
        'character_lcd',
        'cycle_accounting',
        'de10_nano',
        'dsp_eye',
        'dsp_spectrum',
        'dsp_xy',
        'elevator',
        'framebuffer',
        'gauge_cluster',
        'memory_map',
        'nexys_video',
        'oled_graphic',
        'orientation_3axis',
        'ps2_visualizer',
        'pwm_analyzer',
        'register_file',
        'rgb_led',
        'riscv_branch',
        'riscv_csr',
        'riscv_pipeline_adv',
        'traffic_light',
        'uart_terminal',
        'zybo_z7',
        // community bundle
        'custom',
      ],
    },
  ),

  TelemetryCatalogEvent(
    'translator.preset_bound',
    enumeratedValues: <String, List<String>>{
      // The *family* a contributed preset binds — the last dot segment of
      // the registry id its `configBuilder` writes (`pro.amba` → `amba`),
      // lowercased, the same derivation `stage.widget_added` uses. Family
      // rather than preset id on purpose: the decision is which pack to
      // extend, and the 15 individual Pro presets would answer "which AXI
      // control word" instead. Open core contributes no presets today, so
      // every value here comes from the Pro pack; the Pro repo's
      // conformance test walks `proTranslatorPresets()` and fails if a
      // family it ships is missing from this list.
      'family': <String>['amba', 'mlfloat', 'pixel'],
    },
  ),

  // ── recorded by the shared telemetry package ───────────────────────────
  // `crux_telemetry`'s `TelemetryUncaughtErrorCounter` records this from the
  // global error handlers `captureFlutterErrors` installs, so no call site in
  // either repository spells it. At most once per (source, kind, library) per
  // session and ten per session; never the message, the stack or a file
  // name. `kind` is the error's class bucketed by `is` checks, never its
  // runtime type name, and `library` is the Flutter framework library that
  // reported it. The value lists are the package's own
  // `kTelemetryUncaughtError*` constants, referenced rather than copied: the
  // ingestion Worker enforces them value by value for this one event, and
  // the package holds them to the Worker's copy, so a copy here could only
  // drift from both.
  TelemetryCatalogEvent(
    'app.uncaught_error',
    enumeratedValues: <String, List<String>>{
      'source': kTelemetryUncaughtErrorSources,
      'kind': kTelemetryUncaughtErrorKinds,
      'library': kTelemetryUncaughtErrorLibraries,
    },
    boolProperties: <String>['silent'],
  ),

  // ── the commercial group ───────────────────────────────────────────────
  TelemetryCatalogEvent(
    // Recorded inside `WaveCruxUpgradeDialog.show` for every gate denial in
    // both repositories — the suite's single gate-denial convention — with
    // the call site's own `feature` id, and only when the dialog opens, so
    // a repeated shortcut counts once. It cannot fire during the beta,
    // because `FeatureGate` short-circuits to allow and the dialog is
    // unreachable; that matches telemetry's own dark launch rather than
    // working around it.
    'tier.gate_hit',
    enumeratedValues: <String, List<String>>{
      'feature': kWavecruxGateFeatureIds,
      // `LicenseTier.name` for the two tiers a gate can demand. A gate
      // never requires `edu` — EDU is Pro-equivalent for gating — and
      // `openCore` is never gated, so neither can appear.
      'required': <String>['pro', 'enterprise'],
    },
  ),

  // The badge funnel, shared verbatim with host-core's catalog
  // (`crux-vscode/packages/host-core/src/telemetry/events.ts`,
  // `badgeImpression` / `badgeClick`). Same two
  // names on both sides deliberately: under a VSCode host these events
  // are relayed through the bridge and land in the *host's* envelope, so
  // a name that differed by side would split one funnel across two
  // series that no query could rejoin.
  //
  // ### Why this is not a duplicate of `tier.gate_hit`
  //
  // They answer different questions and neither can answer the other's.
  // `tier.gate_hit` carries `feature` — *which* locked thing drives
  // upgrade intent — and has no impression counterpart, so it can only
  // ever produce a count. `badge.click` carries `tier` and shares its
  // dimension with `badge.impression`, which makes the ratio the funnel
  // actually needs computable: of the people who **saw** a Pro badge,
  // how many acted on one. Both fire for the same tap; that is the cost
  // of two honest denominators, and coalescing keeps it to two rows.
  TelemetryCatalogEvent(
    // Recorded at most **once per tier per session**, on a badge's first
    // mount — see `TierBadgeImpressionNotifier`. Not once per badge: a
    // decoder picker listing forty Pro decoders is one person seeing that
    // Pro exists, and forty rows would make the impression side of the
    // ratio a function of catalogue size rather than of readership.
    'badge.impression',
    enumeratedValues: <String, List<String>>{
      // The tier the badge *names*, not the viewer's own. `FeatureTierBadge`
      // renders nothing for `openCore`/`edu`, so neither can appear.
      'tier': <String>['pro', 'enterprise'],
    },
  ),
  TelemetryCatalogEvent(
    // Recorded inside `WaveCruxUpgradeDialog.show` — the one place every
    // badged-item activation in both repositories passes through — and
    // only when the dialog opens.
    'badge.click',
    enumeratedValues: <String, List<String>>{
      'tier': <String>['pro', 'enterprise'],
    },
  ),

  // ── Pro overlay ────────────────────────────────────────────────────────
  TelemetryCatalogEvent(
    'debug_advisor.suggestion.accepted',
    enumeratedValues: <String, List<String>>{
      'rule_id': kDebugAdvisorRuleIdTokens,
      'severity': <String>['info', 'warning', 'error'],
    },
    intProperties: <String>['confidence'],
  ),
  TelemetryCatalogEvent(
    'debug_advisor.suggestion.dismissed',
    enumeratedValues: <String, List<String>>{
      'rule_id': kDebugAdvisorRuleIdTokens,
      'severity': <String>['info', 'warning', 'error'],
    },
    intProperties: <String>['confidence'],
  ),
  TelemetryCatalogEvent(
    'sva.results_loaded',
    enumeratedValues: <String, List<String>>{
      // `SvaSimulatorFormat.values` — the dispatcher's own detection
      // result, not anything read out of the log. `unknown` is a real
      // value: a log that parsed to nothing still loaded, and "how often
      // do we fail to recognise a simulator" is the question that decides
      // whether a fourth parser is worth writing.
      'simulator': <String>['verilator', 'vcs', 'questa', 'unknown'],
    },
  ),
  TelemetryCatalogEvent(
    'ai_advisor.answered',
    enumeratedValues: <String, List<String>>{
      // `AiAdvisorSurface.values` under `telemetryEnumToken` — which of
      // the three capability surfaces the run came from.
      'surface': <String>['ask', 'explain_region', 'why_hang'],
      // `AiProvider.values`; already lowercase, so the call site emits
      // `.name`. The user's endpoint override and key are never sent —
      // only which of the four codecs we maintain was exercised.
      'provider': <String>['anthropic', 'openai', 'google', 'ollama'],
    },
  ),
  TelemetryCatalogEvent('collab.session_shared'),
  TelemetryCatalogEvent('collab.session_joined'),
  TelemetryCatalogEvent('ethernet.pcap_exported'),
  TelemetryCatalogEvent(
    'ethernet.vcd_synthesized',
    enumeratedValues: <String, List<String>>{
      // `SynthTargetPhy.values`, all already lowercase. The link speed is
      // deliberately absent: it is implied by the PHY for every shipping
      // combination, and a free integer would not survive coalescing.
      'phy': <String>['mii', 'rmii', 'gmii', 'rgmii', 'axis'],
    },
  ),
];

/// The closed `feature` vocabulary of [kWavecruxEventCatalog]'s `tier.gate_hit`
/// — one id per gate-denial call site across both repositories, passed as
/// `WaveCruxUpgradeDialog.show`'s `gateFeatureId`, in WaveCrux's own
/// vocabulary.
///
/// These are **not** the dialog's `featureName`. That argument is a localized
/// display string: it differs per locale and fails the ingestion Worker's
/// `[a-z0-9_]{1,64}` value class outright, so the property would be dropped
/// while the event was kept and the dimension would be permanently empty.
/// Every call site passes an id from this list instead.
const List<String> kWavecruxGateFeatureIds = <String>[
  // open core — the three tier-badged pickers
  'translator_preset',
  'decoder_pack',
  'stage_widget_pack',
  // open core — the cross-probe panel's per-peer send button
  // (`crossProbeOriginateGateProvider`). Origination is priced as Pro; the
  // panel it lives on ships in open core, so the gate and its deny surface
  // do too — see the suite ruling "the gate lives beside the code that has
  // the capability".
  'cross_probe',
  // Pro overlay — the five gated activations
  'sva_panel',
  'pcap_export',
  'debug_advisor',
  'ai_advisor',
  // The only Enterprise-tier gate in WaveCrux, and therefore the only
  // possible source of `required: enterprise`. Its deny path was once a red
  // error snackbar, left over from before the upgrade dialog existed, which
  // both broke the suite rule (an insufficient-tier activation always
  // surfaces the dialog; error toasts are for failures, not for not having
  // bought something) and made this the one gate denial no counter could see.
  'pcap_to_vcd',
];

/// `DebugAdvisorRuleId.values` after [telemetryEnumToken]. Named because both
/// Debug Advisor events carry it.
const List<String> kDebugAdvisorRuleIdTokens = <String>[
  'x_propagation_chain',
  'clock_domain_crossing',
  'stuck_at',
  'timing_violation',
];

/// Every catalog event name, for the source-scanning conformance test.
Set<String> get kWavecruxEventNames => <String>{
  for (final event in kWavecruxEventCatalog) event.name,
};
