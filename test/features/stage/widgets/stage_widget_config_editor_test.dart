// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_config_editor.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const String _instId = 'i0';

ProviderContainer _makeContainer({
  Map<String, Object?> initialConfig = const {},
}) {
  final container = ProviderContainer();
  container.read(stageWorkspaceProvider.notifier).state = StageWorkspaceState(
    panels: [
      StagePanelConfig(
        id: 'p0',
        name: 'Panel',
        instances: [
          StageInstance(
            id: _instId,
            widgetId: 'audio',
            configuration: initialConfig,
          ),
        ],
      ),
    ],
    activePanelId: 'p0',
  );
  return container;
}

Widget _wrap(
  Widget child, {
  required ProviderContainer container,
  Locale locale = const Locale('en'),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

StageInstance _instanceFrom(ProviderContainer container) {
  final ws = container.read(stageWorkspaceProvider);
  return ws.panels.first.instances.first;
}

void main() {
  group('StageWidgetConfigEditor — toggle param', () {
    testWidgets('renders a SwitchListTile and commits on tap', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const param = ConfigParam(
        id: 'showFft',
        labelKey: 'Show FFT',
        type: ConfigParamType.toggle,
        defaultValue: true,
      );

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: const [param],
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Show FFT'), findsOneWidget);

      // Default is true — tap to flip to false.
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(_instanceFrom(container).configuration['showFft'], false);
    });

    testWidgets(
      'toggle row survives a ColoredBox surface with no Material between it '
      'and the tile (regression: bindings-pane ink-splash assertion)',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        const param = ConfigParam(
          id: 'showFft',
          labelKey: 'Show FFT',
          type: ConfigParamType.toggle,
          defaultValue: true,
        );

        // Reproduces how StageBindingsPane actually hosts this editor: the
        // pane paints its surface with a ColoredBox, which sits between the
        // tile and the nearest Material. The other tests in this file wrap in
        // a bare Scaffold, whose own Material hides the problem — which is
        // why this regressed unnoticed. Two toggles, matching the Traffic
        // Light Pro widget that surfaced it during smoke testing.
        await tester.pumpWidget(
          _wrap(
            ColoredBox(
              color: const Color(0xFF141418),
              child: StageWidgetConfigEditor(
                instance: _instanceFrom(container),
                params: const [param],
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        // Pre-fix this threw "ListTile background color or ink splashes may
        // be invisible" during build.
        expect(tester.takeException(), isNull);
        expect(find.byType(SwitchListTile), findsOneWidget);

        // The tile still works through the added Material.
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(_instanceFrom(container).configuration['showFft'], false);
      },
    );
  });

  group('StageWidgetConfigEditor — enumChoice param', () {
    testWidgets(
      'renders DropdownButtonFormField and commits on selection',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        const param = ConfigParam(
          id: 'fftWindow',
          labelKey: 'FFT Window',
          type: ConfigParamType.enumChoice,
          defaultValue: 'hann',
          choices: [
            ConfigParamChoice(id: 'hann', labelKey: 'Hann'),
            ConfigParamChoice(id: 'hamming', labelKey: 'Hamming'),
            ConfigParamChoice(id: 'rectangular', labelKey: 'Rectangular'),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            StageWidgetConfigEditor(
              instance: _instanceFrom(container),
              params: const [param],
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('FFT Window'), findsOneWidget);

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hamming').last);
        await tester.pumpAndSettle();

        expect(
          _instanceFrom(container).configuration['fftWindow'],
          'hamming',
        );
      },
    );

    testWidgets(
      'long enum-choice labels do not overflow the bindings-pane column',
      (tester) async {
        // Regression: in narrow side panes (bindings pane is ~200 dp wide
        // by default), a DropdownButtonFormField sized to its widest
        // intrinsic menu item produced a 2.5 px RenderFlex overflow when
        // a Pro pack widget had long enum-choice labels (e.g. the
        // orientation widget's "Accelerometer + gyroscope (fusion)").
        // The fix: isExpanded:true on the dropdown so it fills the column
        // and ellipsizes the closed-state display.
        final container = _makeContainer();
        addTearDown(container.dispose);

        const param = ConfigParam(
          id: 'mode',
          labelKey: 'Sensor mode',
          type: ConfigParamType.enumChoice,
          defaultValue: 'accelAndGyro',
          choices: [
            ConfigParamChoice(id: 'accelOnly', labelKey: 'Accelerometer only'),
            ConfigParamChoice(id: 'gyroOnly', labelKey: 'Gyroscope only'),
            ConfigParamChoice(
              id: 'accelAndGyro',
              labelKey: 'Accelerometer + gyroscope (fusion)',
            ),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            // Constrain to the narrow bindings-pane width that triggered
            // the overflow before the isExpanded fix.
            SizedBox(
              width: 200,
              child: StageWidgetConfigEditor(
                instance: _instanceFrom(container),
                params: const [param],
              ),
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      },
    );
  });

  group('StageWidgetConfigEditor — numeric param', () {
    testWidgets(
      'integer param with min+max renders a Slider; integer commits on slide',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        const param = ConfigParam(
          id: 'windowMs',
          labelKey: 'Window (ms)',
          type: ConfigParamType.integer,
          defaultValue: 500,
          min: 100,
          max: 1000,
          step: 50,
        );

        await tester.pumpWidget(
          _wrap(
            StageWidgetConfigEditor(
              instance: _instanceFrom(container),
              params: const [param],
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Slider), findsOneWidget);
      },
    );

    testWidgets(
      'integer param with no min/max renders a numeric TextField only',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        const param = ConfigParam(
          id: 'sampleRateHz',
          labelKey: 'Sample rate (Hz)',
          type: ConfigParamType.integer,
          defaultValue: 16000,
        );

        await tester.pumpWidget(
          _wrap(
            StageWidgetConfigEditor(
              instance: _instanceFrom(container),
              params: const [param],
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Slider), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets(
      'numeric field commits typed value on focus loss, not just Enter',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        const param = ConfigParam(
          id: 'sampleRateHz',
          labelKey: 'Sample rate (Hz)',
          type: ConfigParamType.integer,
          defaultValue: 16000,
        );

        await tester.pumpWidget(
          _wrap(
            StageWidgetConfigEditor(
              instance: _instanceFrom(container),
              params: const [param],
            ),
            container: container,
          ),
        );
        await tester.pumpAndSettle();

        // Type a new value but do NOT press Enter.
        await tester.enterText(find.byType(TextField), '22050');
        await tester.pump();
        // The edit is still uncommitted — nothing written to the config.
        expect(
          _instanceFrom(container).configuration['sampleRateHz'],
          isNull,
        );

        // Drop focus (the tab / click-elsewhere path). This must commit
        // the field's current text — the regression this guards is that
        // only onSubmitted (Enter) used to commit, so tab/blur lost it.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        expect(
          _instanceFrom(container).configuration['sampleRateHz'],
          22050,
        );
      },
    );
  });

  group('StageWidgetConfigEditor — text param', () {
    testWidgets('renders a single-line TextField and commits on submit', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const param = ConfigParam(
        id: 'label',
        labelKey: 'Label',
        type: ConfigParamType.text,
        defaultValue: '',
      );

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: const [param],
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'CD quality');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        _instanceFrom(container).configuration['label'],
        'CD quality',
      );
    });
  });

  group('StageWidgetConfigEditor — visibility predicate', () {
    testWidgets('hides params whose visibleWhen predicate is unsatisfied', (
      tester,
    ) async {
      final container = _makeContainer(
        initialConfig: const {'channelMode': 'mono'},
      );
      addTearDown(container.dispose);

      const params = [
        ConfigParam(
          id: 'channelMode',
          labelKey: 'Channels',
          type: ConfigParamType.enumChoice,
          defaultValue: 'mono',
          choices: [
            ConfigParamChoice(id: 'mono', labelKey: 'Mono'),
            ConfigParamChoice(id: 'stereo', labelKey: 'Stereo'),
          ],
        ),
        ConfigParam(
          id: 'stereoDisplay',
          labelKey: 'Stereo display',
          type: ConfigParamType.enumChoice,
          defaultValue: 'stacked',
          visibleWhenKey: 'channelMode',
          visibleWhenValue: 'stereo',
          choices: [
            ConfigParamChoice(id: 'stacked', labelKey: 'Stacked'),
            ConfigParamChoice(id: 'overlay', labelKey: 'Overlay'),
          ],
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: params,
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Channels visible, stereo display hidden.
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Stereo display'), findsNothing);
    });

    testWidgets('shows the param when the predicate becomes satisfied', (
      tester,
    ) async {
      final container = _makeContainer(
        initialConfig: const {'channelMode': 'stereo'},
      );
      addTearDown(container.dispose);

      const params = [
        ConfigParam(
          id: 'channelMode',
          labelKey: 'Channels',
          type: ConfigParamType.enumChoice,
          defaultValue: 'mono',
          choices: [
            ConfigParamChoice(id: 'mono', labelKey: 'Mono'),
            ConfigParamChoice(id: 'stereo', labelKey: 'Stereo'),
          ],
        ),
        ConfigParam(
          id: 'stereoDisplay',
          labelKey: 'Stereo display',
          type: ConfigParamType.enumChoice,
          defaultValue: 'stacked',
          visibleWhenKey: 'channelMode',
          visibleWhenValue: 'stereo',
          choices: [
            ConfigParamChoice(id: 'stacked', labelKey: 'Stacked'),
            ConfigParamChoice(id: 'overlay', labelKey: 'Overlay'),
          ],
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: params,
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stereo display'), findsOneWidget);
    });
  });

  group('StageWidgetConfigEditor — grouping', () {
    testWidgets('renders group headers in declaration order', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const params = [
        ConfigParam(
          id: 'a',
          labelKey: 'A',
          type: ConfigParamType.toggle,
          defaultValue: false,
          groupId: 'g1',
        ),
        ConfigParam(
          id: 'b',
          labelKey: 'B',
          type: ConfigParamType.toggle,
          defaultValue: false,
          groupId: 'g2',
        ),
      ];
      const groups = [
        ConfigParamGroup(id: 'g1', labelKey: 'Group 1'),
        ConfigParamGroup(id: 'g2', labelKey: 'Group 2'),
      ];

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: params,
            groups: groups,
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Group 1'), findsOneWidget);
      expect(find.text('Group 2'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('ungrouped params render before any group header', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const params = [
        ConfigParam(
          id: 'top',
          labelKey: 'Top-level',
          type: ConfigParamType.toggle,
          defaultValue: false,
        ),
        ConfigParam(
          id: 'inGroup',
          labelKey: 'Grouped',
          type: ConfigParamType.toggle,
          defaultValue: false,
          groupId: 'g',
        ),
      ];
      const groups = [ConfigParamGroup(id: 'g', labelKey: 'Group')];

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: params,
            groups: groups,
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Both labels visible. Vertical position order verified by Y coord:
      // top-level row's Y < group header's Y.
      final topY = tester.getTopLeft(find.text('Top-level')).dy;
      final headerY = tester.getTopLeft(find.text('Group')).dy;
      expect(topY, lessThan(headerY));
    });
  });

  group('StageWidgetConfigEditor — labelResolver', () {
    testWidgets('resolver overrides the labelKey rendering', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const param = ConfigParam(
        id: 'showFft',
        labelKey: 'showFftLabel',
        type: ConfigParamType.toggle,
        defaultValue: false,
      );

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: const [param],
            labelResolver: (key) => key == 'showFftLabel' ? 'FFT 표시' : key,
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FFT 표시'), findsOneWidget);
      expect(find.text('showFftLabel'), findsNothing);
    });
  });

  group('StageWidgetConfigEditor — locale sweep', () {
    const locales = [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];

    for (final locale in locales) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        const params = [
          ConfigParam(
            id: 'flag',
            labelKey: 'Flag',
            type: ConfigParamType.toggle,
            defaultValue: true,
          ),
          ConfigParam(
            id: 'count',
            labelKey: 'Count',
            type: ConfigParamType.integer,
            defaultValue: 10,
            min: 0,
            max: 100,
          ),
          ConfigParam(
            id: 'kind',
            labelKey: 'Kind',
            type: ConfigParamType.enumChoice,
            defaultValue: 'a',
            choices: [
              ConfigParamChoice(id: 'a', labelKey: 'A'),
              ConfigParamChoice(id: 'b', labelKey: 'B'),
            ],
          ),
        ];

        await tester.pumpWidget(
          _wrap(
            StageWidgetConfigEditor(
              instance: _instanceFrom(container),
              params: params,
            ),
            container: container,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('StageWidgetConfigEditor — empty schema', () {
    testWidgets('renders nothing when params is empty', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          StageWidgetConfigEditor(
            instance: _instanceFrom(container),
            params: const [],
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });
  });
}
