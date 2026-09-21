import 'package:firebase_messaging_handler/src/core/utils/bridging_payload_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BridgingPayloadValidator', () {
    test('accepts minimal payload with title', () {
      bool failed = false;
      final ok = BridgingPayloadValidator.validate(<String, dynamic>{
        'title': 'Hello',
      }, onError: (_) => failed = true);

      expect(ok, isTrue);
      expect(failed, isFalse);
    });

    test('rejects missing title/body', () {
      String? error;
      final ok = BridgingPayloadValidator.validate(<String, dynamic>{
        'foo': 'bar',
      }, onError: (String e) => error = e);

      expect(ok, isFalse);
      expect(error?.toLowerCase().contains('title') ?? false, isTrue);
    });

    test('rejects non-string title/body and invalid actions', () {
      final errors = <String>[];
      final ok = BridgingPayloadValidator.validate(<String, dynamic>{
        'title': 123,
        'actions': <dynamic>[
          <String, dynamic>{'id': 'ok'}, // missing title
        ],
        'analytics': 'should-be-map',
      }, onError: errors.add);

      expect(ok, isFalse);
      expect(errors, isNotEmpty);
      expect(errors, isNotEmpty);
    });

    test('accepts valid actions and analytics map', () {
      bool failed = false;
      final ok = BridgingPayloadValidator.validate(<String, dynamic>{
        'title': 'Sale',
        'actions': <dynamic>[
          <String, dynamic>{'id': 'open', 'title': 'Open'},
        ],
        'analytics': <String, dynamic>{'campaign': 'promo'},
      }, onError: (_) => failed = true);

      expect(ok, isTrue);
      expect(failed, isFalse);
    });

    test('decodes JSON action and analytics values sent by FCM', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'title': 'Sale',
        'actions': '[{"id":"open","title":"Open"}]',
        'analytics': '{"campaign":"promo"}',
      };

      expect(BridgingPayloadValidator.validate(payload), isTrue);
      expect(payload['actions'], isA<List<dynamic>>());
      expect(payload['analytics'], <String, dynamic>{'campaign': 'promo'});
    });

    test('validates v2 cancel envelopes without display content', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'schemaVersion': '2',
        'id': 'message-1',
        'command': 'cancel',
      };

      expect(BridgingPayloadValidator.validate(payload), isTrue);
    });
  });
}
