import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'onboarding_guide.dart';

/// "Show once" plumbing for the first-run capture walkthrough. The seen flag
/// lives in localStorage (the app is a web-only PWA — see DEPLOY.md), so it
/// persists per-device with no extra dependency. The walkthrough widget itself
/// is pure Flutter in onboarding_guide.dart (so it's widget-testable).

const String _seenKey = 'plo_capture_guide_seen_v1';

bool _guideSeen() => web.window.localStorage.getItem(_seenKey) != null;
void _markGuideSeen() => web.window.localStorage.setItem(_seenKey, '1');

/// Show the walkthrough the first time only. Call from the capture screen after
/// the first frame; a no-op once the user has seen (or skipped) it.
Future<void> maybeShowFirstRunGuide(BuildContext context) async {
  if (_guideSeen()) return;
  await showCaptureGuide(context);
}

/// Show the walkthrough on demand (the "?" button). Always marks it seen so the
/// first-run prompt won't reappear afterwards.
Future<void> showCaptureGuide(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (_) => buildFirstRunGuide(),
  );
  _markGuideSeen();
}
