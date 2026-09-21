import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';
import 'package:firebase_messaging_handler_example/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _backgroundMarkerKey = 'fmh_lifecycle_probe_background_marker';

@pragma('vm:entry-point')
Future<void> lifecycleProbeBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseMessagingHandler.handleBackgroundMessage(
    message,
    bootstrap: () async {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    },
  );
  final marker = message.data['marker']?.toString();
  if (marker != null && marker.isNotEmpty) {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_backgroundMarkerKey, marker);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseMessagingHandler.instance.configureBackgroundMessageHandler(
    lifecycleProbeBackgroundHandler,
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LifecycleProbeApp());
}

class LifecycleProbeApp extends StatelessWidget {
  const LifecycleProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LifecycleProbeScreen(),
    );
  }
}

class LifecycleProbeScreen extends StatefulWidget {
  const LifecycleProbeScreen({super.key});

  @override
  State<LifecycleProbeScreen> createState() => _LifecycleProbeScreenState();
}

class _LifecycleProbeScreenState extends State<LifecycleProbeScreen> {
  StreamSubscription<NotificationData?>? _clickSubscription;
  Timer? _preferencePoll;
  String _status = 'starting';
  String _token = 'pending';
  String _event = 'none';
  String _initial = 'none';
  String _background = 'none';
  String _actionMarker = 'pending';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final clickStream = await FirebaseMessagingHandler.instance.initialize(
        FCMConfiguration(
          senderId: DefaultFirebaseOptions.currentPlatform.messagingSenderId,
          androidChannels: <NotificationChannelData>[
            NotificationChannelData(
              id: 'lifecycle_probe',
              name: 'Lifecycle probe',
              description: 'Physical-device lifecycle integration tests',
              importance: NotificationImportanceEnum.max,
              priority: NotificationPriorityEnum.max,
            ),
          ],
          androidNotificationIconPath: '@drawable/ic_notification',
          requestPermissionOnInitialize: true,
          enableDefaultDataOnlyBridge: true,
          dataOnlyBridgeChannelId: 'lifecycle_probe',
          enableDebugLogging: true,
        ),
      );

      _clickSubscription = clickStream?.listen(_recordEvent);
      final initial = await FirebaseMessagingHandler.checkInitial();
      if (initial != null) {
        _recordEvent(initial, initial: true);
      }

      final token = await FirebaseMessagingHandler.instance.getFcmToken();
      if (token == null || token.isEmpty) {
        throw StateError(
          FirebaseMessagingHandler.instance.lastTokenError ??
              'FCM token was unavailable.',
        );
      }
      await FirebaseMessagingHandler.instance.synchronizeToken(force: true);

      final actionMarker =
          'action-${DateTime.now().microsecondsSinceEpoch.toString()}';
      final actionShown = await FirebaseMessagingHandler.instance
          .showNotificationWithActions(
            title: 'FMH Action Probe',
            body: 'Tap ACK to verify background action routing',
            actions: const <NotificationAction>[
              NotificationAction(id: 'ack', title: 'ACK'),
            ],
            payload: <String, dynamic>{'marker': actionMarker},
            channelId: 'lifecycle_probe',
          );
      if (!actionShown) {
        throw StateError('Could not display the action probe notification.');
      }

      await _refreshBackgroundMarker();
      _preferencePoll = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(_refreshBackgroundMarker()),
      );

      if (!mounted) return;
      setState(() {
        _token = token;
        _actionMarker = actionMarker;
        _status = 'ready';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'error:$error');
    }
  }

  void _recordEvent(NotificationData? data, {bool initial = false}) {
    if (data == null || !mounted) return;
    final marker = data.payload['marker']?.toString() ?? 'no-marker';
    final lifecycle = data.isFromTerminated ? 'terminated' : data.type.name;
    final actionId = data.payload['actionId']?.toString() ?? 'none';
    final value = '$marker|$lifecycle|$actionId';
    setState(() {
      _event = value;
      if (initial || data.isFromTerminated) {
        _initial = value;
      }
    });
  }

  Future<void> _refreshBackgroundMarker() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final marker = preferences.getString(_backgroundMarkerKey) ?? 'none';
    if (mounted && marker != _background) {
      setState(() => _background = marker);
    }
  }

  @override
  void dispose() {
    _preferencePoll?.cancel();
    unawaited(_clickSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FMH lifecycle probe')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _ProbeValue(label: 'probe_status=$_status'),
          _ProbeValue(label: 'probe_token=$_token'),
          _ProbeValue(label: 'probe_event=$_event'),
          _ProbeValue(label: 'probe_initial=$_initial'),
          _ProbeValue(label: 'probe_background=$_background'),
          _ProbeValue(label: 'probe_action=$_actionMarker'),
        ],
      ),
    );
  }
}

class _ProbeValue extends StatelessWidget {
  const _ProbeValue({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: label,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Probe value available'),
      ),
    );
  }
}
