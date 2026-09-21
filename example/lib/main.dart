import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging_handler/firebase_messaging_handler.dart';

import 'screens/home_screen.dart';
import 'screens/firebase_setup_screen.dart';
import 'screens/ios_apns_setup_screen.dart';
import 'providers/notification_provider.dart';
import 'router/app_router.dart';
import 'services/firebase_setup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessagingHandler.instance.setInAppNavigatorKey(rootNavigatorKey);
  await FirebaseMessagingHandler.instance.configureBackgroundMessageHandler(
    exampleBackgroundHandler,
  );

  runApp(const MyApp());
}

@pragma('vm:entry-point')
Future<void> exampleBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseMessagingHandler.handleBackgroundMessage(message);
  debugPrint(
    '[BackgroundHandler] Message received: '
    '${message.messageId} | data=${message.data}',
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        title: 'Firebase Messaging Handler Showcase',
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        navigatorKey: rootNavigatorKey,
        home: const FirebaseInitializationWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class FirebaseInitializationWrapper extends StatefulWidget {
  const FirebaseInitializationWrapper({super.key});

  @override
  State<FirebaseInitializationWrapper> createState() =>
      _FirebaseInitializationWrapperState();
}

class _FirebaseInitializationWrapperState
    extends State<FirebaseInitializationWrapper> {
  bool _isLoading = true;
  bool _firebaseConfigured = false;
  bool _continueWithoutApns = false;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    try {
      final isConfigured = await FirebaseSetupService.initializeAndCheck();

      if (mounted) {
        setState(() {
          _firebaseConfigured = isConfigured;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _firebaseConfigured = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _retryInitialization() async {
    setState(() {
      _isLoading = true;
    });

    FirebaseSetupService.reset();
    await _initializeFirebase();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing Firebase...'),
            ],
          ),
        ),
      );
    }

    if (!_firebaseConfigured && !_continueWithoutApns) {
      // Show iOS-specific setup if APNs error detected
      if (FirebaseSetupService.isIOSApnsError) {
        return IOSApnsSetupScreen(
          onRetry: _retryInitialization,
          onContinueWithoutApns: () {
            setState(() {
              _continueWithoutApns = true;
            });
          },
        );
      }

      // Show general Firebase setup for other errors
      return FirebaseSetupScreen(onRetry: _retryInitialization);
    }

    return const HomeScreen();
  }
}
