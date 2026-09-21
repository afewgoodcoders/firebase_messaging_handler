import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

/// How to provide credentials (choose one):
///
/// **Option A — dart-define (recommended for device/CI):**
/// Base64-encode your service account JSON on the host:
/// ```
///   base64 -i test/firebase_config/service_account.json | tr -d '\n'
/// ```
/// Then pass at test time:
/// ```
///   --dart-define=FCM_SERVICE_ACCOUNT_B64=BASE64_STRING_HERE
/// ```
///
/// **Option B — manual send (no credentials in test):**
/// Skip credential passing; tests that require a sender will mark themselves
/// skipped. Use terminated_state_manual.sh or the Firebase Console to send
/// notifications manually while the test waits.
///
/// The device app authenticates with Google OAuth2 and POSTs to FCM HTTP v1,
/// which routes the notification back to the same device via Firebase servers.
// ignore_for_file: unintended_html_in_doc_comment
class FcmTestSender {
  static const _scope = 'https://www.googleapis.com/auth/firebase.messaging';

  /// Embedded at compile time via --dart-define=FCM_SERVICE_ACCOUNT_B64=<base64>
  static const _encodedSa = String.fromEnvironment(
    'FCM_SERVICE_ACCOUNT_B64',
    defaultValue: '',
  );

  final String projectId;
  final Map<String, dynamic> _serviceAccount;

  FcmTestSender._({required this.projectId, required Map<String, dynamic> sa})
    : _serviceAccount = sa;

  /// Returns null when no credentials are available — tests self-skip.
  static FcmTestSender? fromEnv() {
    if (_encodedSa.isEmpty) return null;
    try {
      final json = utf8.decode(base64Decode(_encodedSa));
      final sa = jsonDecode(json) as Map<String, dynamic>;
      return FcmTestSender._(projectId: sa['project_id'] as String, sa: sa);
    } catch (_) {
      return null;
    }
  }

  /// Sends an FCM message to [deviceToken] via FCM HTTP v1.
  ///
  /// Supply [title] + [body] for a visible notification, [data] for a
  /// data-only (silent) payload, or both.
  Future<void> send({
    required String deviceToken,
    String? title,
    String? body,
    Map<String, String> data = const {},
  }) async {
    final creds = ServiceAccountCredentials.fromJson(_serviceAccount);
    final client = await clientViaServiceAccount(creds, [
      _scope,
    ], baseClient: http.Client());
    try {
      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      );
      final payload = {
        'message': {
          'token': deviceToken,
          if (title != null || body != null)
            'notification': {'title': ?title, 'body': ?body},
          if (data.isNotEmpty) 'data': data,
        },
      };
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode != 200) {
        throw Exception(
          'FCM send failed ${response.statusCode}: ${response.body}',
        );
      }
    } finally {
      client.close();
    }
  }
}
