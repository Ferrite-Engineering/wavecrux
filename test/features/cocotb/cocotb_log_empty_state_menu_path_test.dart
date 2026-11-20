// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Cocotb Log panel's empty state tells the user which menu command loads a
// log. The command lives in the Tools menu (menu_layout.dart), so the string
// must name that menu and that command's own label in every locale, and move
// with the menu if the command ever moves.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/menu_layout.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];

Map<String, dynamic> _load(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('Load Cocotb Log is a Tools menu command', () {
    final inTools = [
      for (final group in kMenuLayout[ActionCategory.tools]!) ...group,
    ];
    expect(inTools, contains(ShortcutAction.loadCocotbLog));
    final inFile = [
      for (final group in kMenuLayout[ActionCategory.file]!) ...group,
    ];
    expect(inFile, isNot(contains(ShortcutAction.loadCocotbLog)));
  });

  for (final locale in _locales) {
    test('$locale: the empty state names the Tools menu and the command', () {
      final arb = _load(locale);
      final empty = arb['cocotbLogEmpty'] as String;
      final menu = arb['actionCategoryTools'] as String;
      final command = arb['shortcutActionLoadCocotbLog'] as String;
      expect(
        empty,
        contains('$menu > $command'),
        reason: 'cocotbLogEmpty in app_$locale.arb is "$empty"',
      );
    });
  }
}
