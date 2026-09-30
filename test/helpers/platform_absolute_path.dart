// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Spells a POSIX-looking fixture path as an absolute path on the host.
//
// The CXP containment floor refuses a path unless it is absolute and not
// merely rooted. On Windows `/rtl/cpu.v` names no drive, so the floor
// refuses it as relative, which is correct: a receiver cannot know which
// drive the sender meant. A test that means "an absolute path" writes
// `platformAbsolute('/rtl/cpu.v')` and gets `/rtl/cpu.v` on macOS and
// Linux, and `D:\rtl\cpu.v` on Windows, on the drive the test runs from.
// Roots and expected values must go through the same call so every side
// of a comparison is spelled one way.

import 'package:path/path.dart' as p;

/// [posixPath], which must begin with `/`, as an absolute path under
/// [context]: unchanged on POSIX, drive-qualified with `\` separators on
/// Windows.
String platformAbsolute(String posixPath, {p.Context? context}) {
  if (!posixPath.startsWith('/')) {
    throw ArgumentError.value(posixPath, 'posixPath', 'must begin with /');
  }
  final ctx = context ?? p.context;
  if (ctx.style != p.Style.windows) return posixPath;
  final segments = p.posix.split(posixPath).skip(1);
  return ctx.joinAll(<String>[ctx.rootPrefix(ctx.current), ...segments]);
}
