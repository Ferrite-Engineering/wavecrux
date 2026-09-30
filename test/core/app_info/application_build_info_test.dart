// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/app_info/application_build_info.dart';

void main() {
  const a = ApplicationBuildInfo(
    version: '1.2.3',
    buildNumber: '42',
    gitSha: 'abc1234',
    os: 'macOS 15.0',
    architecture: 'arm64',
    flutterVersion: '3.29.0',
    dartVersion: '3.7.0',
  );

  const b = ApplicationBuildInfo(
    version: '1.2.3',
    buildNumber: '42',
    gitSha: 'abc1234',
    os: 'macOS 15.0',
    architecture: 'arm64',
    flutterVersion: '3.29.0',
    dartVersion: '3.7.0',
  );

  const c = ApplicationBuildInfo(
    version: '9.9.9',
    buildNumber: '99',
    gitSha: 'deadbeef',
    os: 'Linux',
    architecture: 'x86_64',
    flutterVersion: '4.0.0',
    dartVersion: '4.0.0',
  );

  group('ApplicationBuildInfo', () {
    group('equality', () {
      test('identical objects are equal', () {
        expect(a, equals(a));
      });

      test('objects with same fields are equal', () {
        expect(a, equals(b));
      });

      test('objects with different fields are not equal', () {
        expect(a, isNot(equals(c)));
      });

      test('different version yields inequality', () {
        const d = ApplicationBuildInfo(
          version: '0.0.1',
          buildNumber: '42',
          gitSha: 'abc1234',
          os: 'macOS 15.0',
          architecture: 'arm64',
          flutterVersion: '3.29.0',
          dartVersion: '3.7.0',
        );
        expect(a, isNot(equals(d)));
      });

      test('different gitSha yields inequality', () {
        const d = ApplicationBuildInfo(
          version: '1.2.3',
          buildNumber: '42',
          gitSha: 'different',
          os: 'macOS 15.0',
          architecture: 'arm64',
          flutterVersion: '3.29.0',
          dartVersion: '3.7.0',
        );
        expect(a, isNot(equals(d)));
      });
    });

    group('hashCode', () {
      test('equal objects have the same hashCode', () {
        expect(a.hashCode, equals(b.hashCode));
      });

      test('unequal objects have different hashCode (very likely)', () {
        expect(a.hashCode, isNot(equals(c.hashCode)));
      });
    });

    group('fields', () {
      test('version field is accessible', () {
        expect(a.version, equals('1.2.3'));
      });

      test('buildNumber field is accessible', () {
        expect(a.buildNumber, equals('42'));
      });

      test('gitSha field is accessible', () {
        expect(a.gitSha, equals('abc1234'));
      });

      test('os field is accessible', () {
        expect(a.os, equals('macOS 15.0'));
      });

      test('architecture field is accessible', () {
        expect(a.architecture, equals('arm64'));
      });

      test('flutterVersion field is accessible', () {
        expect(a.flutterVersion, equals('3.29.0'));
      });

      test('dartVersion field is accessible', () {
        expect(a.dartVersion, equals('3.7.0'));
      });
    });
  });
}
