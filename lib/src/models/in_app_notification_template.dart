import 'dart:async';

import 'in_app_notification_data.dart';

/// Callback invoked when a template should render a received in-app payload.
typedef InAppNotificationDisplayCallback =
    FutureOr<void> Function(InAppNotificationData data);

/// Describes a registered in-app template and how it should be displayed.
class InAppNotificationTemplate {
  /// Stable template identifier referenced by incoming payloads.
  final String id;

  /// Human-readable template description used in docs and debugging.
  final String description;

  /// Rendering callback invoked when the template is triggered.
  final InAppNotificationDisplayCallback onDisplay;

  /// Optional duration after which the template should dismiss automatically.
  final Duration? autoDismissDuration;

  /// Whether the user may dismiss modal-style presentation by tapping outside.
  final bool barrierDismissible;

  /// Creates a template definition for registration with the handler.
  const InAppNotificationTemplate({
    required this.id,
    required this.description,
    required this.onDisplay,
    this.autoDismissDuration,
    this.barrierDismissible = true,
  });
}
