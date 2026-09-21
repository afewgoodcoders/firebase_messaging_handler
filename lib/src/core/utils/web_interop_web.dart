/// WASM-compatible web interop using dart:js_interop.
/// This file is only compiled on web targets.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Notification')
external JSObject? get _notificationCtor;

@JS('navigator')
external JSObject get _navigator;

@JS('isSecureContext')
external bool get _isSecureContext;

@JS('location')
external JSObject get _location;

@JS('window')
external JSObject get _window;

JSFunction? _serviceWorkerMessageListener;

String getWebNotificationPermission() {
  try {
    final ctor = _notificationCtor;
    if (ctor == null) return 'unavailable';
    final perm = ctor.getProperty<JSString?>('permission'.toJS);
    return perm?.toDart ?? 'unknown';
  } catch (_) {
    return 'error';
  }
}

Future<bool> requestWebNotificationPermission() async {
  try {
    final ctor = _notificationCtor;
    if (ctor == null) return false;
    final perm = ctor.getProperty<JSString?>('permission'.toJS)?.toDart;
    if (perm == 'granted') return true;
    if (perm == 'default') {
      final result = await ctor
          .callMethod<JSPromise<JSString>>('requestPermission'.toJS)
          .toDart;
      return result.toDart == 'granted';
    }
    return false;
  } catch (_) {
    return false;
  }
}

Map<String, dynamic> getWebRuntimeDiagnostics() {
  try {
    final notifAvailable = _notificationCtor != null;
    final nav = _navigator;
    final sw = nav.getProperty<JSObject?>('serviceWorker'.toJS);
    final swController = sw?.getProperty<JSObject?>('controller'.toJS);
    final ua = nav.getProperty<JSString?>('userAgent'.toJS)?.toDart;
    final proto = _location.getProperty<JSString?>('protocol'.toJS)?.toDart;
    final host = _location.getProperty<JSString?>('host'.toJS)?.toDart;
    return {
      'supported': notifAvailable,
      'notificationApiAvailable': notifAvailable,
      'serviceWorkerApiAvailable': sw != null,
      'serviceWorkerControllerPresent': swController != null,
      'pushManagerLikelyAvailable':
          sw?.getProperty<JSAny?>('ready'.toJS) != null,
      'isSecureContext': _isSecureContext,
      'locationProtocol': proto,
      'locationHost': host,
      'userAgent': ua,
    };
  } catch (e) {
    return {'supported': false, 'error': e.toString()};
  }
}

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
}) async {
  try {
    if (getWebNotificationPermission() != 'granted') return false;
    final ctor = _notificationCtor;
    if (ctor == null) return false;
    final opts = {
      'body': body,
      'icon': icon,
      'badge': badge,
      'image': image,
      'tag': tag ?? 'firebase-notification',
      'renotify': renotify,
      'requireInteraction': requireInteraction,
      'silent': silent,
      if (actions.isNotEmpty) 'actions': actions,
      'data': data,
    }.jsify();
    if (actions.isNotEmpty) {
      final JSObject? serviceWorker = _navigator.getProperty<JSObject?>(
        'serviceWorker'.toJS,
      );
      final JSPromise<JSObject>? ready = serviceWorker
          ?.getProperty<JSPromise<JSObject>?>('ready'.toJS);
      if (ready == null) return false;
      final JSObject registration = await ready.toDart;
      await registration
          .callMethod<JSPromise<JSAny?>>(
            'showNotification'.toJS,
            title.toJS,
            opts!,
          )
          .toDart;
    } else {
      ctor.callMethod<JSObject>('new'.toJS, title.toJS, opts!);
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Registers a single listener for service-worker notification click/close
/// messages emitted by the package's v2 worker template.
void setWebNotificationEventHandler(
  void Function(Map<String, dynamic> event)? handler,
) {
  final JSFunction? previous = _serviceWorkerMessageListener;
  if (previous != null) {
    _window.callMethod<JSAny?>(
      'removeEventListener'.toJS,
      'message'.toJS,
      previous,
    );
    _serviceWorkerMessageListener = null;
  }
  if (handler == null) return;

  _serviceWorkerMessageListener = ((JSObject messageEvent) {
    try {
      final Object? value = messageEvent
          .getProperty<JSAny?>('data'.toJS)
          ?.dartify();
      if (value is Map) {
        handler(Map<String, dynamic>.from(value));
      }
    } catch (_) {
      // Ignore unrelated or non-cloneable window messages.
    }
  }).toJS;
  _window.callMethod<JSAny?>(
    'addEventListener'.toJS,
    'message'.toJS,
    _serviceWorkerMessageListener!,
  );
}
