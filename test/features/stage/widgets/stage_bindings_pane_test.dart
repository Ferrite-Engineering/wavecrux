// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_config_label_resolver_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/board_auto_bind_preview_dialog.dart';
import 'package:wavecrux/features/stage/widgets/stage_bindings_pane.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';

class _BoardLikeStub extends StageWidget {
  const _BoardLikeStub();
  @override
  String get id => 'board';
  @override
  String get displayName => 'Board';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.board;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'clk', description: 'Clock'),
    SignalBinding(name: 'rst', description: 'Reset'),
  ];
  @override
  List<SignalBinding> get optionalSignals => const [
    SignalBinding(name: 'dbg', description: 'Debug'),
  ];
}

class _NoPinsStub extends StageWidget {
  const _NoPinsStub();
  @override
  String get id => 'no_pins';
  @override
  String get displayName => 'No Pins';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [];
}

/// Stub used by the resolver-wiring test. Declares one config param so
/// the bindings pane renders the configuration section and its
/// [ConfigParam.labelKey] is fed through the resolver factory.
class _ConfigStub extends StageWidget {
  const _ConfigStub();
  @override
  String get id => 'cfg';
  @override
  String get displayName => 'Configurable';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [];
  @override
  List<ConfigParam> get configParams => const [
    ConfigParam(
      id: 'theme',
      labelKey: 'stub.param.theme',
      type: ConfigParamType.text,
      defaultValue: 'dark',
    ),
  ];
}

/// Stub for the per-pin visibility seam: two unconditional pins that must
/// behave exactly as they always have, plus two that are gated on a config
/// key — the "2–8 configurable stages" shape.
class _VisibilityStub extends StageWidget {
  const _VisibilityStub();
  @override
  String get id => 'vis';
  @override
  String get displayName => 'Visibility';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'always_req', description: 'Always required'),
    SignalBinding(
      name: 'stage2_valid',
      description: 'Stage 2 valid',
      visibleWhenKey: 'stageCount',
      visibleWhenValues: {2, 3},
    ),
  ];
  @override
  List<SignalBinding> get optionalSignals => const [
    SignalBinding(name: 'always_opt', description: 'Always optional'),
    SignalBinding(
      name: 'stage3_valid',
      description: 'Stage 3 valid',
      visibleWhenKey: 'stageCount',
      visibleWhenValue: 3,
    ),
  ];
}

/// Stub for the non-compound auto-bind seam: a plain [StageWidget] that
/// declares its own matcher and therefore earns the affordance that used to
/// be hard-gated on `CompoundStageWidget`.
class _AutoBindStub extends StageWidget {
  const _AutoBindStub();
  @override
  String get id => 'autobind';
  @override
  String get displayName => 'Auto-bindable';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'rvfi_valid', description: 'valid'),
  ];
  @override
  StageAutoBindService? get autoBindService => const RvfiDetectionService();

  // A non-board subject names itself. Leaving the key null would open the
  // dialog under "Auto-bind board signals", which is wrong for an RVFI
  // channel bundle.
  @override
  String? get autoBindTitleKey => 'stageRvfiAutoBindTitle';
}

/// Minimal compound widget — the pre-seam case. It declares no matcher and
/// no title key, so it must resolve to the shared board matcher and keep the
/// board dialog heading, exactly as before the seam existed.
class _CompoundStub extends CompoundStageWidget {
  const _CompoundStub();
  @override
  String get id => 'compound';
  @override
  String get displayName => 'Compound';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.board;
  @override
  List<StageWidgetSlot> get slots => const [
    StageWidgetSlot(
      name: 'led0',
      childWidgetId: 'led',
      x: 0,
      y: 0,
      width: 0.1,
      height: 0.1,
    ),
  ];
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required StageWorkspaceState seed,
  String? selectedInstanceId,
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: StageBindingsPane.width,
            height: 600,
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const StageBindingsPane();
              },
            ),
          ),
        ),
      ),
    ),
  );
  // Seed via post-frame so the providers are alive.
  WidgetsBinding.instance.scheduleFrame();
  await tester.pumpAndSettle();
  container.read(stageWorkspaceProvider.notifier).restoreFromSession(seed);
  if (selectedInstanceId != null) {
    container
        .read(stageSelectedInstanceProvider.notifier)
        .select(selectedInstanceId);
  }
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    StageRegistry.instance
      ..clear()
      ..register(const _BoardLikeStub())
      ..register(const _NoPinsStub())
      ..register(const _ConfigStub())
      ..register(const _VisibilityStub())
      ..register(const _AutoBindStub())
      ..register(const _CompoundStub());
  });
  tearDown(StageRegistry.instance.clear);

  group('StageBindingsPane — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await _pump(
          tester,
          locale: Locale(locale),
          seed: const StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'P',
                instances: [StageInstance(id: 'i0', widgetId: 'board')],
              ),
            ],
            activePanelId: 'p0',
          ),
          selectedInstanceId: 'i0',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('StageBindingsPane — visibility', () {
    testWidgets('renders nothing when no instance is selected', (tester) async {
      await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [StageInstance(id: 'i0', widgetId: 'board')],
            ),
          ],
          activePanelId: 'p0',
        ),
      );
      // No header, no rows.
      expect(find.text('Signal Bindings'), findsNothing);
    });

    testWidgets('renders pane and binding rows when instance selected', (
      tester,
    ) async {
      await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [
                StageInstance(
                  id: 'i0',
                  widgetId: 'board',
                  signalBindings: {
                    'clk': StageSignalBinding(signalRef: 'top.clk'),
                  },
                ),
              ],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );
      // Title (instance label fallback to widget displayName).
      expect(find.text('Board'), findsOneWidget);
      // Section heading.
      expect(find.text('Signal Bindings'), findsOneWidget);
      // Required + optional pin rows.
      expect(
        find.byKey(const ValueKey('stageBindingRow:i0:clk')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('stageBindingRow:i0:rst')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('stageBindingRow:i0:dbg')),
        findsOneWidget,
      );
      // Bound row shows the signal ref.
      expect(find.text('top.clk'), findsOneWidget);
    });
  });

  group('StageBindingRow — signalRef resolves to a human path', () {
    testWidgets(
      'shows the variable fullPath, not the opaque signalRef handle',
      (tester) async {
        // wellen's signalRef is an opaque handle (a bare number like
        // "10"), not a path. The row must resolve it back to the
        // variable's fullPath for display — the regression this guards
        // is the row printing the raw "10".
        const variable = Variable(
          name: 'level_ramp',
          varType: VarType.wire,
          direction: VarDirection.unknown,
          signalRef: '10',
          scopePath: 'top',
          bitWidth: 8,
        );
        await _pump(
          tester,
          overrides: [
            signalVariablesMapProvider.overrideWith(
              (ref) => const {'10': variable},
            ),
          ],
          seed: const StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'P',
                instances: [
                  StageInstance(
                    id: 'i0',
                    widgetId: 'board',
                    signalBindings: {
                      'clk': StageSignalBinding(signalRef: '10'),
                    },
                  ),
                ],
              ),
            ],
            activePanelId: 'p0',
          ),
          selectedInstanceId: 'i0',
        );

        expect(find.text('top.level_ramp'), findsOneWidget);
        expect(find.text('10'), findsNothing);
      },
    );

    testWidgets('falls back to the raw ref when the signal is not loaded', (
      tester,
    ) async {
      // A session bound against a signal absent from the current file:
      // no variable resolves, so we surface the raw ref rather than an
      // empty cell.
      await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [
                StageInstance(
                  id: 'i0',
                  widgetId: 'board',
                  signalBindings: {
                    'clk': StageSignalBinding(signalRef: '99'),
                  },
                ),
              ],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );

      expect(find.text('99'), findsOneWidget);
    });
  });

  group('StageBindingsPane — close action', () {
    testWidgets('close button clears the selection', (tester) async {
      final container = await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [StageInstance(id: 'i0', widgetId: 'board')],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );
      expect(container.read(stageSelectedInstanceProvider), 'i0');
      await tester.tap(find.byTooltip('Close bindings pane'));
      await tester.pumpAndSettle();
      expect(container.read(stageSelectedInstanceProvider), isNull);
    });
  });

  group('StageBindingsPane — clear binding', () {
    testWidgets('the per-row clear button removes the binding', (tester) async {
      final container = await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [
                StageInstance(
                  id: 'i0',
                  widgetId: 'board',
                  signalBindings: {
                    'clk': StageSignalBinding(signalRef: 'top.clk'),
                  },
                ),
              ],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );

      // The clear-binding IconButton is inside the bound row.
      final clearButton = find.descendant(
        of: find.byKey(const ValueKey('stageBindingRow:i0:clk')),
        matching: find.byTooltip('Clear binding'),
      );
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      final updated = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(updated.signalBindings.containsKey('clk'), isFalse);
    });
  });

  group('StageBindingsPane — empty pin set', () {
    testWidgets('shows the no-bindings placeholder for widgets with no pins', (
      tester,
    ) async {
      await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [StageInstance(id: 'i0', widgetId: 'no_pins')],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );
      expect(find.text('Signal Bindings'), findsOneWidget);
      expect(find.text('This widget has no signal inputs.'), findsOneWidget);
    });
  });

  group('StageBindingRow — drag-and-drop signal binding', () {
    testWidgets('accepts a dropped signal ref and binds the pin', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [StageInstance(id: 'i0', widgetId: 'board')],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );

      // Initially the rst pin is unbound.
      var instance = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(instance.signalBindings['rst'], isNull);

      // Find the DragTarget<String> inside the rst row and dispatch
      // onAcceptWithDetails directly. Going through the DragTarget's
      // public surface is more reliable in a widget test than simulating
      // a long-press + drag from a far-away source widget.
      final rowFinder = find.byKey(const ValueKey('stageBindingRow:i0:rst'));
      expect(rowFinder, findsOneWidget);
      final target = tester
          .widget<DragTarget<String>>(
            find.ancestor(
              of: rowFinder,
              matching: find.byType(DragTarget<String>),
            ),
          )
          .onAcceptWithDetails!;
      target(
        DragTargetDetails<String>(
          data: 'top.dut.rst',
          offset: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      instance = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(instance.signalBindings['rst']?.signalRef, 'top.dut.rst');
    });

    testWidgets('drop onto an already-bound row replaces the binding', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [
                StageInstance(
                  id: 'i0',
                  widgetId: 'board',
                  signalBindings: {
                    'clk': StageSignalBinding(signalRef: 'top.clk'),
                  },
                ),
              ],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );

      final rowFinder = find.byKey(const ValueKey('stageBindingRow:i0:clk'));
      final target = tester
          .widget<DragTarget<String>>(
            find.ancestor(
              of: rowFinder,
              matching: find.byType(DragTarget<String>),
            ),
          )
          .onAcceptWithDetails!;
      target(
        DragTargetDetails<String>(
          data: 'top.dut.clk_alt',
          offset: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      final instance = container
          .read(stageWorkspaceProvider)
          .activePanel!
          .instances
          .first;
      expect(instance.signalBindings['clk']?.signalRef, 'top.dut.clk_alt');
    });
  });

  group('StageBindingsPane — config-label resolver factory', () {
    testWidgets(
      'configuration section runs labelKeys through the resolver factory',
      (tester) async {
        // Override the resolver factory to return a resolver that maps
        // 'stub.param.theme' to a recognisable label. The default identity
        // resolver would render the raw ARB key — that's the bug this test
        // guards against. The Pro overlay overrides this provider with a
        // factory backed by L10NPro.
        await _pump(
          tester,
          seed: const StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'P',
                instances: [StageInstance(id: 'i0', widgetId: 'cfg')],
              ),
            ],
            activePanelId: 'p0',
          ),
          selectedInstanceId: 'i0',
          overrides: [
            stageConfigLabelResolverFactoryProvider.overrideWithValue(
              (_) =>
                  (key) => key == 'stub.param.theme' ? 'Theme (resolved)' : key,
            ),
          ],
        );

        expect(find.text('Theme (resolved)'), findsOneWidget);
        expect(find.text('stub.param.theme'), findsNothing);
      },
    );

    testWidgets('default factory passes raw labelKeys through unchanged', (
      tester,
    ) async {
      await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [StageInstance(id: 'i0', widgetId: 'cfg')],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );

      // No override → identity resolver → raw ARB key is rendered. This
      // documents the open-core fallback and proves Pro builds need the
      // override to render localized labels.
      expect(find.text('stub.param.theme'), findsOneWidget);
    });
  });

  group('StageBindingsPane — trackpad scroll', () {
    testWidgets('inspector body re-enables trackpad two-finger scroll', (
      tester,
    ) async {
      // Regression: the app-wide ScrollConfiguration restricts dragDevices
      // to {touch}, which drops macOS/iPad trackpad pan-zoom. With a tall
      // configuration section the inspector overflows, and without this
      // the user can't trackpad-scroll down to reach lower config knobs
      // (e.g. the Tachometer's maxRpm slider).
      await _pump(
        tester,
        seed: const StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [StageInstance(id: 'i0', widgetId: 'cfg')],
            ),
          ],
          activePanelId: 'p0',
        ),
        selectedInstanceId: 'i0',
      );

      final scrollView = find.byType(SingleChildScrollView);
      expect(scrollView, findsOneWidget);
      final config = tester.widget<ScrollConfiguration>(
        find
            .ancestor(
              of: scrollView,
              matching: find.byType(ScrollConfiguration),
            )
            .first,
      );
      final devices = config.behavior.dragDevices;
      expect(devices, contains(PointerDeviceKind.trackpad));
      expect(devices, contains(PointerDeviceKind.touch));
    });
  });

  // ── per-pin visibility (SignalBinding.visibleWhen*) ──────────────────────

  group('StageBindingsPane — per-pin visibility', () {
    Future<void> pumpVisibility(
      WidgetTester tester, {
      required Map<String, Object?> configuration,
    }) => _pump(
      tester,
      seed: StageWorkspaceState(
        panels: [
          StagePanelConfig(
            id: 'p0',
            name: 'P',
            instances: [
              StageInstance(
                id: 'i0',
                widgetId: 'vis',
                configuration: configuration,
              ),
            ],
          ),
        ],
        activePanelId: 'p0',
      ),
      selectedInstanceId: 'i0',
    );

    Finder rowFor(String pin) =>
        find.byKey(ValueKey('stageBindingRow:i0:$pin'));

    testWidgets(
      'pins without a predicate render exactly as they did before the seam',
      (tester) async {
        // The whole additive-change claim: an empty configuration is the
        // pre-seam state, and the unconditional pins must still be listed.
        await pumpVisibility(tester, configuration: const {});
        expect(rowFor('always_req'), findsOneWidget);
        expect(rowFor('always_opt'), findsOneWidget);
      },
    );

    testWidgets('a gated pin is hidden while its predicate is unsatisfied', (
      tester,
    ) async {
      await pumpVisibility(tester, configuration: const {});
      expect(rowFor('stage2_valid'), findsNothing);
      expect(rowFor('stage3_valid'), findsNothing);
    });

    testWidgets('a set-membership predicate reveals the pin', (tester) async {
      await pumpVisibility(tester, configuration: const {'stageCount': 2});
      expect(rowFor('stage2_valid'), findsOneWidget);
      expect(rowFor('stage3_valid'), findsNothing);
      expect(rowFor('always_req'), findsOneWidget);
    });

    testWidgets('a single-value predicate reveals the pin', (tester) async {
      await pumpVisibility(tester, configuration: const {'stageCount': 3});
      expect(rowFor('stage2_valid'), findsOneWidget);
      expect(rowFor('stage3_valid'), findsOneWidget);
    });

    testWidgets('an out-of-range value hides both gated pins', (tester) async {
      await pumpVisibility(tester, configuration: const {'stageCount': 8});
      expect(rowFor('stage2_valid'), findsNothing);
      expect(rowFor('stage3_valid'), findsNothing);
      expect(rowFor('always_req'), findsOneWidget);
      expect(rowFor('always_opt'), findsOneWidget);
    });
  });

  // ── non-compound auto-bind seam ──────────────────────────────────────────

  group('StageBindingsPane — auto-bind affordance', () {
    Future<void> pumpWidgetId(WidgetTester tester, String widgetId) => _pump(
      tester,
      seed: StageWorkspaceState(
        panels: [
          StagePanelConfig(
            id: 'p0',
            name: 'P',
            instances: [StageInstance(id: 'i0', widgetId: widgetId)],
          ),
        ],
        activePanelId: 'p0',
      ),
      selectedInstanceId: 'i0',
    );

    testWidgets('is offered for a non-compound widget with a matcher', (
      tester,
    ) async {
      await pumpWidgetId(tester, 'autobind');
      expect(find.byIcon(Icons.auto_fix_high), findsOneWidget);
    });

    testWidgets('is not offered for a widget with no matcher', (tester) async {
      // `_BoardLikeStub` is board-*categorized* but not compound, and
      // declares no service — it never had the affordance and must not
      // gain one from the seam.
      await pumpWidgetId(tester, 'board');
      expect(find.byIcon(Icons.auto_fix_high), findsNothing);
    });

    testWidgets('opens the preview dialog with the detected candidates', (
      tester,
    ) async {
      await pumpWidgetId(tester, 'autobind');
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pumpAndSettle();
      expect(find.byType(BoardAutoBindPreviewDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a widget with an autoBindTitleKey titles the dialog itself', (
      tester,
    ) async {
      await pumpWidgetId(tester, 'autobind');
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pumpAndSettle();
      expect(find.text('Auto-bind RVFI channels'), findsOneWidget);
      expect(find.text('Auto-bind board signals'), findsNothing);
    });

    testWidgets('the board dialog keeps its own heading', (tester) async {
      // The seam must not change what boards do: `_CompoundStub` declares no
      // title key, so the dialog stays on the board heading.
      await pumpWidgetId(tester, 'compound');
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pumpAndSettle();
      expect(find.text('Auto-bind board signals'), findsOneWidget);
    });
  });
}
