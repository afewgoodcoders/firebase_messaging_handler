import 'package:flutter/material.dart';
import '../services/firebase_setup_service.dart';

class IOSApnsSetupScreen extends StatelessWidget {
  const IOSApnsSetupScreen({
    super.key,
    this.onRetry,
    this.onContinueWithoutApns,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onContinueWithoutApns;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iOS APNs Setup Required'),
        backgroundColor: Colors.blue.shade50,
        foregroundColor: Colors.blue.shade800,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildApnsSection(context),
            const SizedBox(height: 20),
            _buildFirebaseSection(context),
            const SizedBox(height: 20),
            _buildAppleDeveloperSection(context),
            const SizedBox(height: 24),
            _buildImportantNotes(context),
            const SizedBox(height: 20),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_iphone, color: Colors.blue.shade700, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'iOS APNs Configuration Required',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Your Firebase project is configured, but iOS requires Apple Push Notification service (APNs) to be set up in Firebase Console. This is a requirement for iOS notifications to work.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.blue.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApnsSection(BuildContext context) {
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
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '1',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
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
                        'Generate APNs Key',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Create an APNs authentication key in Apple Developer Console',
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
            _buildStepItem(
              'Go to Apple Developer Console',
              'https://developer.apple.com/account/resources/authkeys/list',
              Icons.open_in_new,
            ),
            _buildStepItem(
              'Sign in with your Apple Developer account',
              'You need a paid Apple Developer account',
              Icons.account_circle,
            ),
            _buildStepItem(
              'Click the "+" button to create a new key',
              'Select "Apple Push Notifications service (APNs)"',
              Icons.add_circle_outline,
            ),
            _buildStepItem(
              'Download the .p8 key file',
              'Keep this file secure - you can only download it once',
              Icons.download,
            ),
            _buildStepItem(
              'Note your Key ID and Team ID',
              'You\'ll need these when uploading to Firebase',
              Icons.info_outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirebaseSection(BuildContext context) {
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
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '2',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
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
                        'Upload APNs Key to Firebase',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Configure your iOS app in Firebase Console',
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
            _buildStepItem(
              'Go to Firebase Console',
              'https://console.firebase.google.com/',
              Icons.open_in_new,
            ),
            _buildStepItem(
              'Select your project',
              'The same project you\'re using for this app',
              Icons.folder_open,
            ),
            _buildStepItem(
              'Go to Project Settings → Cloud Messaging',
              'Scroll down to "Apple app configuration"',
              Icons.settings,
            ),
            _buildStepItem(
              'Upload your APNs key (.p8 file)',
              'Click "Upload" and select your key file',
              Icons.upload_file,
            ),
            _buildStepItem(
              'Enter Key ID and Team ID',
              'From your Apple Developer Console',
              Icons.key,
            ),
            _buildStepItem(
              'Choose environment',
              'Sandbox for development, Production for release',
              Icons.settings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppleDeveloperSection(BuildContext context) {
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
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '3',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade800,
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
                        'Apple Developer Account Requirements',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'What you need to generate APNs keys',
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
            _buildStepItem(
              'Paid Apple Developer Account',
              'Required to generate APNs keys (\$99/year)',
              Icons.payment,
            ),
            _buildStepItem(
              'App registered in Apple Developer Console',
              'Your app bundle ID must be registered',
              Icons.app_registration,
            ),
            _buildStepItem(
              'Valid Apple Developer Program membership',
              'Active membership required for APNs',
              Icons.verified_user,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportantNotes(BuildContext context) {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade700,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Important Notes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildNoteItem(
              'APNs keys are required for iOS notifications',
              'Without APNs, iOS notifications will not work',
            ),
            _buildNoteItem(
              'This is a Firebase requirement, not our plugin limitation',
              'Even the official Firebase package requires APNs setup',
            ),
            _buildNoteItem(
              'You can test Android without APNs',
              'Android notifications work without iOS APNs setup',
            ),
            _buildNoteItem(
              'APNs keys are secure and reusable',
              'One key can be used for multiple apps',
            ),
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

  Widget _buildNoteItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.amber.shade600),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _continueWithoutApns(context),
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Continue Without APNs (Limited)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can test Android features and see the app structure, but iOS notifications will not work.',
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

  void _continueWithoutApns(BuildContext context) {
    if (onContinueWithoutApns != null) {
      onContinueWithoutApns!();
    } else {
      // Fallback: close the screen
      Navigator.of(context).pop(false);
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
