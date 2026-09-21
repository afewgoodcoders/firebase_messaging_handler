/// Stub implementations for non-web platforms.
/// All functions return safe defaults since web APIs are unavailable.
library;

String getWebNotificationPermission() => 'unavailable';

Future<bool> requestWebNotificationPermission() async => false;

Map<String, dynamic> getWebRuntimeDiagnostics() => {
  'supported': false,
  'reason': 'unavailable',
};

Future<bool> showWebNotification({
  required String title,
  required String body,
  required String icon,
  required Map<String, dynamic> data,
  String? badge,
  String? image,
  String? tag,
  bool renotify = false,
  bool requireInteraction = false,
  bool silent = false,
  List<Map<String, dynamic>> actions = const <Map<String, dynamic>>[],
}) async => false;

void setWebNotificationEventHandler(
  void Function(Map<String, dynamic> event)? handler,
) {}
