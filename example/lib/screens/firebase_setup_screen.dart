import 'package:flutter/material.dart';
import '../services/firebase_setup_service.dart';

class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Setup Required'),
        backgroundColor: Colors.orange.shade50,
        foregroundColor: Colors.orange.shade800,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildStepSection(
              context,
              stepNumber: 1,
              title: 'Create Firebase Project',
              description:
                  'Set up a new Firebase project or use an existing one',
              children: [
                _buildStepItem(
                  'Go to Firebase Console',
                  'https://console.firebase.google.com/',
                  Icons.open_in_new,
                ),
                _buildStepItem(
                  'Click "Create a project" or select existing',
                  'Follow the setup wizard',
                  Icons.add_circle_outline,
                ),
                _buildStepItem(
                  'Enable Google Analytics (optional)',
                  'Recommended for better insights',
                  Icons.analytics_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStepSection(
              context,
              stepNumber: 2,
              title: 'Add Flutter App to Firebase',
              description: 'Register your Flutter app with Firebase',
              children: [
                _buildStepItem(
                  'Click "Add app" → Flutter icon',
                  'Select Flutter platform',
                  Icons.phone_android,
                ),
                _buildStepItem(
                  'Enter package name',
                  'com.afewgoodcoders.fmhexample',
                  Icons.label_outline,
                ),
                _buildStepItem(
                  'Download configuration files',
                  'google-services.json (Android) & GoogleService-Info.plist (iOS)',
                  Icons.download,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStepSection(
              context,
              stepNumber: 3,
              title: 'Configure Android',
              description: 'Set up Android configuration',
              children: [
                _buildStepItem(
                  'Place google-services.json',
                  'android/app/google-services.json',
                  Icons.folder_open,
                ),
                _buildStepItem(
                  'Update android/app/build.gradle',
                  'Add Google Services plugin',
                  Icons.code,
                ),
                _buildCodeBlock('''
// android/app/build.gradle
apply plugin: 'com.google.gms.google-services'

dependencies {
    implementation 'com.google.firebase:firebase-bom:32.7.0'
    implementation 'com.google.firebase:firebase-messaging'
}'''),
              ],
            ),
            const SizedBox(height: 20),
            _buildStepSection(
              context,
              stepNumber: 4,
              title: 'Configure Web (VAPID Key)',
              description: 'Required for browser push notifications',
              children: [
                _buildStepItem(
                  'Open Firebase Console → Project Settings',
                  'Select the Cloud Messaging tab',
                  Icons.settings,
                ),
                _buildStepItem(
                  'Scroll to "Web Push certificates"',
                  'Under "Web configuration" section',
                  Icons.web,
                ),
                _buildStepItem(
                  'Generate or copy your Web Push key pair',
                  'Click "Generate key pair" if none exists',
                  Icons.key,
                ),
                _buildCodeBlock(
                  '// Pass the Key Pair value as webVapidKey\n'
                  'await FirebaseMessagingHandler.instance.init(\n'
                  '  senderId: \'your_sender_id\',\n'
                  '  webVapidKey: \'your_vapid_key_here\',\n'
                  '  androidChannelList: [...],\n'
                  '  androidNotificationIconPath: \'@drawable/ic_notification\',\n'
                  ');',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStepSection(
              context,
              stepNumber: 5,
              title: 'Configure iOS',
              description: 'Set up iOS configuration and APNS',
              children: [
                _buildStepItem(
                  'Place GoogleService-Info.plist',
                  'ios/Runner/GoogleService-Info.plist',
                  Icons.folder_open,
                ),
                _buildStepItem(
                  'Add APNS Key to Firebase Console',
                  'Project Settings → Cloud Messaging → iOS app configuration',
                  Icons.key,
                ),
                _buildStepItem(
                  'Upload your APNs Authentication Key',
                  'Download from Apple Developer Portal',
                  Icons.upload_file,
                ),
                _buildStepItem(
                  'Note your Messaging Sender ID',
                  'Found in GoogleService-Info.plist',
                  Icons.info_outline,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStepSection(
              context,
              stepNumber: 6,
              title: 'Enable Cloud Messaging',
              description: 'Activate Firebase Cloud Messaging',
              children: [
                _buildStepItem(
                  'Go to Cloud Messaging section',
                  'Firebase Console → Cloud Messaging',
                  Icons.message,
                ),
                _buildStepItem(
                  'Send test message (optional)',
                  'Verify your setup works',
                  Icons.send,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildNextSteps(context),
            const SizedBox(height: 20),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Firebase Not Configured',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This example app requires Firebase Cloud Messaging to be properly configured. '
              'Follow the steps below to set up Firebase for your Flutter app.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.orange.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepSection(
    BuildContext context, {
    required int stepNumber,
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      stepNumber.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(String code) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SelectableText(
        code,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _buildNextSteps(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Colors.green.shade700,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pro Tips',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTipItem(
              'Test on both platforms',
              'iOS requires APNS key, Android works with default settings',
            ),
            _buildTipItem(
              'Use Firebase Console for testing',
              'Send test messages to verify your setup',
            ),
            _buildTipItem(
              'Check your bundle ID',
              'Must match exactly in Firebase Console and your app',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: Colors.green.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final requiresRecompile = FirebaseSetupService.requiresRecompile;

    return Column(
      children: [
        if (requiresRecompile) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showRecompileInstructions(context),
              icon: const Icon(Icons.build),
              label: const Text('Recompile App Required'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange.shade600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Major configuration changes require app recompilation.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _retryFirebaseSetup(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Firebase Setup'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Minor configuration changes can be retried.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  void _retryFirebaseSetup(BuildContext context) {
    if (onRetry != null) {
      onRetry!();
    } else {
      // Fallback: restart the app
      Navigator.of(context).pop(true);
    }
  }

  void _showRecompileInstructions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recompile Required'),
        content: const Text(
          'Major configuration changes require app recompilation:\n\n'
          '1. Stop the current app\n'
          '2. Run "flutter clean"\n'
          '3. Run "flutter pub get"\n'
          '4. Run "flutter run" again\n\n'
          'This is required when changing:\n'
          '• Package name/bundle ID\n'
          '• Firebase configuration files\n'
          '• App signing certificates',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
