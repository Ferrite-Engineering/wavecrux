// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Linux runner's fallback to the software renderer.
///
/// Flutter's GTK embedder draws through a GDK OpenGL context. On a display
/// that cannot give it one (VNC without GLX, X forwarding, ETX or NX sessions,
/// a virtual machine without 3D acceleration) it logs "Failed to create OpenGL
/// context" and draws nothing: the window never appears. The engine switches
/// to its software renderer only when `FLUTTER_LINUX_RENDERER=software` is
/// set, and with Impeller on (the default) the software renderer aborts at
/// the first line of text. The runner therefore probes for a context before
/// creating the engine, sets the variable when the probe fails, and turns
/// Impeller off whenever the software renderer is selected (wavecrux#73).
///
/// Every piece is needed, and losing any one of them is silent on a desktop
/// with a GPU, which is where the app is developed. Hence a static check.
void main() {
  const path = 'linux/runner/my_application.cc';

  late String code;
  setUpAll(() {
    code = File(path)
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  });

  test('the runner probes the display for an OpenGL context', () {
    expect(code, contains('gdk_window_create_gl_context('));
    expect(code, contains('gdk_gl_context_realize('));
  });

  test('a failed probe selects the software renderer and says so', () {
    expect(
      code,
      contains('g_setenv("FLUTTER_LINUX_RENDERER", "software", FALSE)'),
      reason: 'FALSE keeps a value the user set, "opengl" included.',
    );
    expect(code, contains('falling back'));
  });

  test('the software renderer runs with Impeller off', () {
    expect(
      code,
      contains('fl_dart_project_set_enable_impeller(project, FALSE)'),
    );
  });

  test('the probe runs before the engine is created', () {
    final probe = code.indexOf('select_renderer_for_display();');
    final engine = code.indexOf('fl_view_new(');
    expect(probe, isNonNegative, reason: 'activate() never calls the probe.');
    expect(engine, isNonNegative);
    expect(
      probe,
      lessThan(engine),
      reason:
          'The engine reads FLUTTER_LINUX_RENDERER when fl_view_new creates '
          'it; setting the variable afterwards has no effect.',
    );
  });
}
