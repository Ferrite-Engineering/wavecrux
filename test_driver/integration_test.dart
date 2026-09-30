// test_driver/integration_test.dart
//
// Entry point for `flutter drive` integration test runs. Required by
// the `integration_test` package on web (and as the default driver on
// every platform). Each `integration_test/<phase>/<name>_test.dart`
// file is exercised with:
//
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/<phase>/<name>_test.dart \
//     -d chrome
//
// The web tests in `integration_test/web/` are run through this driver.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
