// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_requirement.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

ActionContext _ctx({
  bool fileLoaded = false,
  DeviceClass deviceClass = DeviceClass.desktop,
  bool diagnosticsEnabled = false,
  int paneCount = 1,
  bool inSession = false,
  bool isHost = false,
  bool isRecording = false,
  bool stageViewVisible = false,
  bool cursorPresent = false,
  bool markersPresent = false,
  bool diffActive = false,
  bool cocotbLogLoaded = false,
  bool patternMatchesPresent = false,
  bool canZoomOut = true,
  bool canZoomIn = true,
  bool isWeb = false,
}) => ActionContext(
  fileLoaded: fileLoaded,
  deviceClass: deviceClass,
  diagnosticsEnabled: diagnosticsEnabled,
  paneCount: paneCount,
  inSession: inSession,
  isHost: isHost,
  isRecording: isRecording,
  stageViewVisible: stageViewVisible,
  cursorPresent: cursorPresent,
  markersPresent: markersPresent,
  diffActive: diffActive,
  cocotbLogLoaded: cocotbLogLoaded,
  patternMatchesPresent: patternMatchesPresent,
  canZoomOut: canZoomOut,
  canZoomIn: canZoomIn,
  isWeb: isWeb,
);

void main() {
  group('descriptorFor', () {
    test('is total over ShortcutAction.values', () {
      for (final a in ShortcutAction.values) {
        expect(descriptorFor(a), isA<ActionDescriptor>());
      }
    });

    test('every action with a non-open-core tier stays discoverable', () {
      for (final a in ShortcutAction.values) {
        final d = descriptorFor(a);
        if (d.requiredTier != LicenseTier.openCore) {
          expect(
            d.surfaces,
            isNotEmpty,
            reason: '$a is a paid-tier action but appears in no surface',
          );
        }
      }
    });

    group('surface membership', () {
      test('keyboard-/context-only actions appear in no surface', () {
        const hidden = [
          ShortcutAction.waveformZoomIn,
          ShortcutAction.waveformZoomOut,
          ShortcutAction.panLeft,
          ShortcutAction.panRight,
          ShortcutAction.panLeftSmall,
          ShortcutAction.panRightSmall,
          ShortcutAction.clearSecondaryCursor,
          // nextTab / previousTab are NOT here: they have a home in the View
          // menu's tab group, as in every Crux app. The nine direct jump-to-tab-N actions stay surface-less.
          ShortcutAction.jumpToTab1,
          ShortcutAction.jumpToTab9,
          ShortcutAction.setFormatBinary,
          ShortcutAction.setFormatHexadecimal,
          ShortcutAction.setFormatNamedEnum,
        ];
        for (final a in hidden) {
          expect(descriptorFor(a).surfaces, isEmpty, reason: '$a');
        }
      });

      test('palette-only actions are palette-scoped', () {
        // moveTabToOtherPane left this list in the suite menu-consistency
        // pass — it now sits in the View menu's pane group next to Split /
        // Close / Focus Other Pane, as it does in the other three products.
        for (final a in [ShortcutAction.openPaneRenderStats]) {
          expect(descriptorFor(a).surfaces, {
            ActionSurface.palette,
          }, reason: '$a');
        }
      });

      test('toolbar actions also appear in menu/overflow/palette', () {
        for (final a in [
          ShortcutAction.openFile,
          ShortcutAction.zoomIn,
          ShortcutAction.addDecoder,
          ShortcutAction.openSettings,
        ]) {
          expect(
            descriptorFor(a).surfaces,
            contains(ActionSurface.toolbar),
            reason: '$a',
          );
        }
      });
    });

    group('file gating', () {
      test('file-required actions are disabled without a file', () {
        final noFile = _ctx();
        final withFile = _ctx(fileLoaded: true);
        for (final a in [
          ShortcutAction.zoomIn,
          ShortcutAction.exportWaveform,
          ShortcutAction.addDecoder,
          ShortcutAction.closeFile,
          ShortcutAction.saveSession,
          ShortcutAction.patternSearch,
        ]) {
          expect(descriptorFor(a).isEnabled(noFile), isFalse, reason: '$a');
          expect(descriptorFor(a).isEnabled(withFile), isTrue, reason: '$a');
        }
      });

      test('always-available actions ignore file state', () {
        for (final a in [
          ShortcutAction.openFile,
          ShortcutAction.openSearch,
          ShortcutAction.openSettings,
        ]) {
          expect(descriptorFor(a).isEnabled(_ctx()), isTrue, reason: '$a');
        }
      });
    });

    group('zoom gating', () {
      test('Zoom Out is disabled once the viewport shows the whole trace', () {
        // Not a cosmetic nicety. Zoom-out is clamped to fit-all, so past that
        // point the button responds and nothing moves — which reads as a
        // broken viewer rather than a limit that has been reached.
        final d = descriptorFor(ShortcutAction.zoomOut);
        expect(d.isEnabled(_ctx(fileLoaded: true)), isTrue);
        expect(d.isEnabled(_ctx(fileLoaded: true, canZoomOut: false)), isFalse);
        expect(
          d.unmetRequirement(_ctx(fileLoaded: true, canZoomOut: false)),
          ActionRequirement.canZoomOut,
          reason: 'the keyboard guard turns this into the localized hint',
        );
        // The file requirement still comes first, so a no-file press says
        // "load a waveform" rather than "already fully zoomed out".
        expect(
          d.unmetRequirement(_ctx(canZoomOut: false)),
          ActionRequirement.fileLoaded,
        );
      });

      test('Zoom In is disabled at the one-tick floor', () {
        final d = descriptorFor(ShortcutAction.zoomIn);
        expect(d.isEnabled(_ctx(fileLoaded: true)), isTrue);
        expect(d.isEnabled(_ctx(fileLoaded: true, canZoomIn: false)), isFalse);
        expect(
          d.unmetRequirement(_ctx(fileLoaded: true, canZoomIn: false)),
          ActionRequirement.canZoomIn,
        );
      });

      test('Fit All is never gated by the zoom bounds', () {
        // It is the escape hatch — and the affordance that proved the viewer
        // knew the trace's extent all along — so it stays live at both ends.
        final d = descriptorFor(ShortcutAction.fitAll);
        expect(
          d.isEnabled(
            _ctx(fileLoaded: true, canZoomOut: false, canZoomIn: false),
          ),
          isTrue,
        );
      });
    });

    group(
      'context gating (cursor / markers / diff / cocotb / stage / pattern)',
      () {
        test('cursor-gated actions need a file AND a cursor', () {
          for (final a in [
            ShortcutAction.jumpToStart,
            ShortcutAction.jumpToEnd,
            ShortcutAction.setMarker,
            ShortcutAction.clearCursors,
            ShortcutAction.nextTransition,
            ShortcutAction.prevTransition,
          ]) {
            final d = descriptorFor(a);
            expect(d.isEnabled(_ctx(fileLoaded: true)), isFalse, reason: '$a');
            expect(
              d.isEnabled(_ctx(cursorPresent: true)),
              isFalse,
              reason: '$a',
            );
            expect(
              d.isEnabled(_ctx(fileLoaded: true, cursorPresent: true)),
              isTrue,
              reason: '$a',
            );
          }
        });

        test('jump/remove marker need a file AND a marker (NOT a cursor)', () {
          for (final a in [
            ShortcutAction.jumpToMarker,
            ShortcutAction.removeMarker,
          ]) {
            final d = descriptorFor(a);
            expect(d.isEnabled(_ctx(fileLoaded: true)), isFalse, reason: '$a');
            // A cursor alone is not enough — these target an existing marker.
            expect(
              d.isEnabled(_ctx(fileLoaded: true, cursorPresent: true)),
              isFalse,
              reason: '$a',
            );
            expect(
              d.isEnabled(_ctx(fileLoaded: true, markersPresent: true)),
              isTrue,
              reason: '$a',
            );
          }
        });

        test('divergence nav needs a file AND an active diff', () {
          for (final a in [
            ShortcutAction.nextDivergence,
            ShortcutAction.prevDivergence,
          ]) {
            final d = descriptorFor(a);
            expect(d.isEnabled(_ctx(fileLoaded: true)), isFalse, reason: '$a');
            expect(
              d.isEnabled(_ctx(fileLoaded: true, diffActive: true)),
              isTrue,
              reason: '$a',
            );
          }
        });

        test('pattern-match nav needs a file AND a match', () {
          for (final a in [
            ShortcutAction.nextPatternMatch,
            ShortcutAction.prevPatternMatch,
          ]) {
            final d = descriptorFor(a);
            expect(d.isEnabled(_ctx(fileLoaded: true)), isFalse, reason: '$a');
            expect(
              d.isEnabled(_ctx(fileLoaded: true, patternMatchesPresent: true)),
              isTrue,
              reason: '$a',
            );
          }
        });

        test('clear cocotb log needs a loaded log', () {
          final d = descriptorFor(ShortcutAction.clearCocotbLog);
          expect(d.isEnabled(_ctx()), isFalse);
          expect(d.isEnabled(_ctx(cocotbLogLoaded: true)), isTrue);
        });

        test('stage undo/redo need the Stage panel open', () {
          for (final a in [
            ShortcutAction.stageUndo,
            ShortcutAction.stageRedo,
          ]) {
            final d = descriptorFor(a);
            expect(d.isEnabled(_ctx()), isFalse, reason: '$a');
            expect(
              d.isEnabled(_ctx(stageViewVisible: true)),
              isTrue,
              reason: '$a',
            );
          }
        });

        test('all context-gated actions stay discoverable in a surface', () {
          for (final a in [
            ShortcutAction.setMarker,
            ShortcutAction.jumpToMarker,
            ShortcutAction.removeMarker,
            ShortcutAction.nextDivergence,
            ShortcutAction.clearCocotbLog,
            ShortcutAction.stageUndo,
            ShortcutAction.nextPatternMatch,
          ]) {
            expect(descriptorFor(a).surfaces, isNotEmpty, reason: '$a');
          }
        });
      },
    );

    group('diagnostics gating', () {
      test('app diagnostics: visible on tablet/desktop, hidden on phone', () {
        final d = descriptorFor(ShortcutAction.openAppDiagnostics);
        expect(d.isVisible(_ctx()), isTrue);
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.tablet)), isTrue);
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.phone)), isFalse);
        expect(
          d.isVisible(_ctx(deviceClass: DeviceClass.phoneLandscape)),
          isFalse,
        );
      });

      test('app diagnostics: enabled only when diagnostics is on', () {
        final d = descriptorFor(ShortcutAction.openAppDiagnostics);
        expect(d.isEnabled(_ctx()), isFalse);
        expect(d.isEnabled(_ctx(diagnosticsEnabled: true)), isTrue);
      });

      test('tab diagnostics: needs diagnostics AND a file', () {
        final d = descriptorFor(ShortcutAction.openTabDiagnostics);
        expect(d.isEnabled(_ctx(diagnosticsEnabled: true)), isFalse);
        expect(d.isEnabled(_ctx(fileLoaded: true)), isFalse);
        expect(
          d.isEnabled(_ctx(diagnosticsEnabled: true, fileLoaded: true)),
          isTrue,
        );
      });
    });

    group('Stage Playback (togglePlayback)', () {
      test('appears in menu/overflow/palette (NOT the toolbar — the visible '
          "transport lives in the Stage dock tab's strip actions), "
          'tablet + desktop only', () {
        final d = descriptorFor(ShortcutAction.togglePlayback);
        expect(d.surfaces, isNot(contains(ActionSurface.toolbar)));
        expect(d.surfaces, contains(ActionSurface.menu));
        expect(d.surfaces, contains(ActionSurface.overflow));
        expect(d.surfaces, contains(ActionSurface.palette));
        expect(d.isVisible(_ctx()), isTrue); // desktop
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.tablet)), isTrue);
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.phone)), isFalse);
        expect(
          d.isVisible(_ctx(deviceClass: DeviceClass.phoneLandscape)),
          isFalse,
        );
      });

      test('enabled only when a file is loaded AND Stage is visible', () {
        final d = descriptorFor(ShortcutAction.togglePlayback);
        expect(d.isEnabled(_ctx()), isFalse);
        expect(d.isEnabled(_ctx(fileLoaded: true)), isFalse);
        expect(d.isEnabled(_ctx(stageViewVisible: true)), isFalse);
        expect(
          d.isEnabled(_ctx(fileLoaded: true, stageViewVisible: true)),
          isTrue,
        );
      });

      test('is Open Core (no tier badge)', () {
        expect(
          descriptorFor(ShortcutAction.togglePlayback).requiredTier,
          LicenseTier.openCore,
        );
      });
    });

    group('device-class visibility', () {
      test('stems generate/import are desktop only, browsable, '
          'file-independent, and Open Core (no tier badge)', () {
        for (final a in [
          ShortcutAction.generateRtlStems,
          ShortcutAction.importVerilatorAst,
        ]) {
          final d = descriptorFor(a);
          expect(d.isVisible(_ctx()), isTrue, reason: '$a'); // desktop
          expect(
            d.isVisible(_ctx(deviceClass: DeviceClass.tablet)),
            isFalse,
            reason: '$a',
          );
          expect(
            d.isVisible(_ctx(deviceClass: DeviceClass.phone)),
            isFalse,
            reason: '$a',
          );
          // Independent of a loaded file: you produce the stems first, then
          // load the result.
          expect(d.isEnabled(_ctx()), isTrue, reason: '$a');
          expect(d.surfaces, isNotEmpty, reason: '$a');
          expect(d.requiredTier, LicenseTier.openCore, reason: '$a');
        }
      });

      test('statistics strip is desktop only', () {
        final d = descriptorFor(ShortcutAction.toggleStatisticsStrip);
        expect(d.isVisible(_ctx()), isTrue);
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.tablet)), isFalse);
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.phone)), isFalse);
      });

      test('actions that save to a picked path are hidden in the browser; '
          'exports that download stay', () {
        const hiddenOnWeb = [
          ShortcutAction.saveSession,
          ShortcutAction.saveSessionAs,
          ShortcutAction.newWorkspace,
          ShortcutAction.saveWorkspaceAs,
          ShortcutAction.exportTabAsSession,
          ShortcutAction.generateTestVcd,
          ShortcutAction.generateRtlStems,
          ShortcutAction.importVerilatorAst,
        ];
        for (final a in hiddenOnWeb) {
          final d = descriptorFor(a);
          expect(d.isVisible(_ctx(fileLoaded: true)), isTrue, reason: '$a');
          expect(
            d.isVisible(_ctx(fileLoaded: true, isWeb: true)),
            isFalse,
            reason: '$a',
          );
        }
        for (final a in [
          ShortcutAction.exportWaveform,
          ShortcutAction.shareAnnotatedWaveform,
        ]) {
          expect(
            descriptorFor(a).isVisible(_ctx(fileLoaded: true, isWeb: true)),
            isTrue,
            reason: '$a',
          );
        }
      });

      test('cross-probe panel is hidden on phone', () {
        final d = descriptorFor(ShortcutAction.openCrossProbePanel);
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.tablet)), isTrue);
        expect(d.isVisible(_ctx(deviceClass: DeviceClass.phone)), isFalse);
      });
    });

    group('pane gating', () {
      test('split is enabled only with a single pane', () {
        final d = descriptorFor(ShortcutAction.splitPaneRight);
        expect(d.isEnabled(_ctx()), isTrue);
        expect(d.isEnabled(_ctx(paneCount: 2)), isFalse);
      });

      test('close/focus pane enabled only with multiple panes', () {
        for (final a in [
          ShortcutAction.closePane,
          ShortcutAction.focusOtherPane,
        ]) {
          expect(descriptorFor(a).isEnabled(_ctx()), isFalse, reason: '$a');
          expect(
            descriptorFor(a).isEnabled(_ctx(paneCount: 2)),
            isTrue,
            reason: '$a',
          );
        }
      });

      test('pane actions are hidden on phone', () {
        for (final a in [
          ShortcutAction.splitPaneRight,
          ShortcutAction.closePane,
          ShortcutAction.focusOtherPane,
          ShortcutAction.moveTabToOtherPane,
        ]) {
          expect(
            descriptorFor(a).isVisible(_ctx(deviceClass: DeviceClass.phone)),
            isFalse,
            reason: '$a',
          );
        }
      });
    });

    group('collaboration gating (hosting is Enterprise, joining is free)', () {
      test('share/join require not being in a session', () {
        for (final a in [
          ShortcutAction.shareSession,
          ShortcutAction.joinSession,
        ]) {
          final d = descriptorFor(a);
          expect(d.isEnabled(_ctx()), isTrue, reason: '$a');
          expect(d.isEnabled(_ctx(inSession: true)), isFalse, reason: '$a');
        }
      });

      test('only Share Session carries the Enterprise badge', () {
        expect(
          descriptorFor(ShortcutAction.shareSession).requiredTier,
          LicenseTier.enterprise,
        );
        expect(
          descriptorFor(ShortcutAction.joinSession).requiredTier,
          LicenseTier.openCore,
        );
      });

      test(
        'Join Session is hidden where no collaboration service is bound',
        () {
          const joinable = ActionContext(
            fileLoaded: false,
            deviceClass: DeviceClass.desktop,
          );
          const unavailable = ActionContext(
            fileLoaded: false,
            deviceClass: DeviceClass.desktop,
            collaborationAvailable: false,
          );
          for (final surface in [ActionSurface.menu, ActionSurface.palette]) {
            expect(
              isActionVisibleIn(ShortcutAction.joinSession, surface, joinable),
              isTrue,
            );
            expect(
              isActionVisibleIn(
                ShortcutAction.joinSession,
                surface,
                unavailable,
              ),
              isFalse,
            );
            // Share stays visible as the upsell.
            expect(
              isActionVisibleIn(
                ShortcutAction.shareSession,
                surface,
                unavailable,
              ),
              isTrue,
            );
          }
        },
      );

      test('stop sharing requires hosting', () {
        final d = descriptorFor(ShortcutAction.stopSharing);
        expect(d.isEnabled(_ctx(inSession: true, isHost: true)), isTrue);
        expect(d.isEnabled(_ctx(inSession: true)), isFalse);
        expect(d.isEnabled(_ctx()), isFalse);
      });

      test('leave session requires being a non-host participant', () {
        final d = descriptorFor(ShortcutAction.leaveSession);
        expect(d.isEnabled(_ctx(inSession: true)), isTrue);
        expect(d.isEnabled(_ctx(inSession: true, isHost: true)), isFalse);
        expect(d.isEnabled(_ctx()), isFalse);
      });

      test('export recording requires a session or a recording', () {
        final d = descriptorFor(ShortcutAction.exportSessionRecording);
        expect(d.isEnabled(_ctx(inSession: true)), isTrue);
        expect(d.isEnabled(_ctx(isRecording: true)), isTrue);
        expect(d.isEnabled(_ctx()), isFalse);
      });
    });

    group('Presenter Mode gating (free for every participant)', () {
      test('no presenter-mode action carries a tier', () {
        for (final a in [
          ShortcutAction.handoffPresenter,
          ShortcutAction.requestPresenter,
          ShortcutAction.resumeFollowing,
          ShortcutAction.dropPing,
          ShortcutAction.dropPin,
        ]) {
          expect(
            descriptorFor(a).requiredTier,
            LicenseTier.openCore,
            reason: '$a',
          );
        }
      });

      test(
        'all presenter-mode actions stay discoverable in a browsable surface',
        () {
          for (final a in [
            ShortcutAction.handoffPresenter,
            ShortcutAction.requestPresenter,
            ShortcutAction.resumeFollowing,
            ShortcutAction.dropPing,
            ShortcutAction.dropPin,
          ]) {
            expect(descriptorFor(a).surfaces, isNotEmpty, reason: '$a');
          }
        },
      );

      test(
        'handoff / resume / ping / pin are enabled only while in a session',
        () {
          for (final a in [
            ShortcutAction.handoffPresenter,
            ShortcutAction.resumeFollowing,
            ShortcutAction.dropPing,
            ShortcutAction.dropPin,
          ]) {
            final d = descriptorFor(a);
            expect(d.isEnabled(_ctx()), isFalse, reason: '$a');
            expect(d.isEnabled(_ctx(inSession: true)), isTrue, reason: '$a');
            // The host is in a session and may still hand off / resume / point.
            expect(
              d.isEnabled(_ctx(inSession: true, isHost: true)),
              isTrue,
              reason: '$a',
            );
          }
        },
      );

      test('request control requires being a non-host participant', () {
        final d = descriptorFor(ShortcutAction.requestPresenter);
        expect(d.isEnabled(_ctx(inSession: true)), isTrue);
        expect(d.isEnabled(_ctx(inSession: true, isHost: true)), isFalse);
        expect(d.isEnabled(_ctx()), isFalse);
      });
    });

    group('selectors', () {
      Set<ShortcutAction> menuSet(ActionContext c) => groupedActionsFor(
        ActionSurface.menu,
        c,
      ).values.expand((x) => x).toSet();
      Set<ShortcutAction> overflowSet(ActionContext c) => groupedActionsFor(
        ActionSurface.overflow,
        c,
      ).values.expand((x) => x).toSet();

      test(
        'palette omits hidden families and file-gated actions w/o a file',
        () {
          final listed = paletteActionsFor(_ctx()).toSet();
          expect(listed, isNot(contains(ShortcutAction.setFormatBinary)));
          expect(listed, isNot(contains(ShortcutAction.nextTab)));
          expect(listed, isNot(contains(ShortcutAction.jumpToTab1)));
          // openCommandPalette is reachable from menu/overflow but never listed
          // in the palette itself (self-referential) — issue #38.
          expect(listed, isNot(contains(ShortcutAction.openCommandPalette)));
          // file-required actions are omitted while no file is loaded.
          expect(listed, isNot(contains(ShortcutAction.zoomIn)));
          expect(listed, isNot(contains(ShortcutAction.exportWaveform)));
        },
      );

      test('palette includes file actions once a file is loaded', () {
        final listed = paletteActionsFor(_ctx(fileLoaded: true)).toSet();
        expect(listed, contains(ShortcutAction.zoomIn));
        expect(listed, contains(ShortcutAction.exportWaveform));
        // still never lists the per-row / keyboard-only families.
        expect(listed, isNot(contains(ShortcutAction.setFormatHexadecimal)));
      });

      test('palette lists palette-only actions when applicable', () {
        final listed = paletteActionsFor(
          _ctx(fileLoaded: true, diagnosticsEnabled: true, paneCount: 2),
        ).toSet();
        expect(listed, contains(ShortcutAction.openPaneRenderStats));
        expect(listed, contains(ShortcutAction.moveTabToOtherPane));
      });

      test(
        'menu/overflow include visible actions regardless of enablement',
        () {
          final menu = menuSet(_ctx());
          // file-required actions are visible (greyed) even without a file.
          expect(menu, contains(ShortcutAction.zoomIn));
          expect(menu, contains(ShortcutAction.closeFile));
          // hidden families never appear.
          expect(menu, isNot(contains(ShortcutAction.setFormatOctal)));
          expect(menu, isNot(contains(ShortcutAction.jumpToTab3)));
          // openCommandPalette IS reachable from the menu (recovery path if its
          // shortcut is unbound) even though it is excluded from the palette
          // itself — issue #38.
          expect(menu, contains(ShortcutAction.openCommandPalette));
          // palette-only entries never appear in the menu.
          expect(menu, isNot(contains(ShortcutAction.openPaneRenderStats)));
          // moveTabToOtherPane DOES appear — it is in the View menu's pane
          // group, as in every Crux app.
          expect(menu, contains(ShortcutAction.moveTabToOtherPane));
        },
      );

      test(
        'overflow exposes the command palette opener (mobile recovery path)',
        () {
          // On mobile the overflow menu is the recovery path to reopen the
          // palette if its shortcut is unbound — issue #38.
          expect(
            overflowSet(_ctx()),
            contains(ShortcutAction.openCommandPalette),
          );
        },
      );

      test('overflow on phone hides device-gated actions', () {
        final phone = overflowSet(_ctx(deviceClass: DeviceClass.phone));
        expect(phone, isNot(contains(ShortcutAction.openAppDiagnostics)));
        expect(phone, isNot(contains(ShortcutAction.openCrossProbePanel)));
        expect(phone, isNot(contains(ShortcutAction.toggleStatisticsStrip)));
        expect(phone, isNot(contains(ShortcutAction.splitPaneRight)));
        // but ordinary actions remain reachable on phone.
        expect(phone, contains(ShortcutAction.openFile));
        expect(phone, contains(ShortcutAction.zoomIn));
      });
    });

    group('tier metadata', () {
      test('Pro and Enterprise actions carry the right tier', () {
        expect(
          descriptorFor(ShortcutAction.debugAdvisorTogglePanel).requiredTier,
          LicenseTier.pro,
        );
        expect(
          descriptorFor(ShortcutAction.toggleSvaPanel).requiredTier,
          LicenseTier.pro,
        );
        expect(
          descriptorFor(ShortcutAction.convertPcapToVcd).requiredTier,
          LicenseTier.enterprise,
        );
        expect(
          descriptorFor(ShortcutAction.shareSession).requiredTier,
          LicenseTier.enterprise,
        );
        expect(
          descriptorFor(ShortcutAction.joinSession).requiredTier,
          LicenseTier.openCore,
        );
        expect(
          descriptorFor(ShortcutAction.leaveSession).requiredTier,
          LicenseTier.openCore,
        );
      });

      test('plain actions are open-core', () {
        expect(
          descriptorFor(ShortcutAction.openFile).requiredTier,
          LicenseTier.openCore,
        );
        expect(
          descriptorFor(ShortcutAction.zoomIn).requiredTier,
          LicenseTier.openCore,
        );
      });
    });

    group('checkForUpdates', () {
      test('is open-core (no tier badge) on menu / overflow / palette', () {
        final d = descriptorFor(ShortcutAction.checkForUpdates);
        expect(d.requiredTier, LicenseTier.openCore);
        expect(d.surfaces, {
          ActionSurface.menu,
          ActionSurface.overflow,
          ActionSurface.palette,
        });
        expect(d.surfaces, isNot(contains(ActionSurface.toolbar)));
      });

      test('appears in the command palette and the overflow Help group', () {
        final ctx = _ctx();
        expect(
          paletteActionsFor(ctx),
          contains(ShortcutAction.checkForUpdates),
        );
        expect(
          groupedActionsFor(ActionSurface.overflow, ctx)[ActionCategory.help],
          contains(ShortcutAction.checkForUpdates),
        );
      });
    });
  });
}
