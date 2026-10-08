// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/services/collaboration/noop_collaboration_service.dart';

/// Whether this build can actually take part in a collaborative session.
///
/// True only when [collaborationServiceProvider] is bound to a real service
/// (the open-source build binds [NoopCollaborationService]) on a desktop host
/// (the web and mobile builds do not offer collaboration).
///
/// Join Session is free in every edition, so unlike Share Session it carries
/// no tier badge, and the rule that hides inert tier-badged actions does not
/// cover it. This is the capability test that keeps a Join action from being
/// offered where it would do nothing.
final collaborationAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(collaborationServiceProvider) is! NoopCollaborationService &&
      !kIsWeb &&
      !isMobileHostPlatform,
  name: 'collaborationAvailableProvider',
);
