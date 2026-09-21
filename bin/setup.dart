import 'dart:io';

void main(List<String> args) async {
  print('\n🔥 Firebase Messaging Handler: Setup Doctor 🔥\n');
  print(
    'Running diagnostics to ensure your project is ready for "Epic" notifications...\n',
  );

  final projectRoot = Directory.current.path;
  bool allGood = true;

  // 1. Check Android Config
  print('🤖 Checking Android Configuration...');
  final googleServicesJson = File(
    '$projectRoot/android/app/google-services.json',
  );
  if (await googleServicesJson.exists()) {
    print('  ✅ google-services.json found.');
  } else {
    print('  ❌ google-services.json MISSING in android/app/');
    print(
      '     -> Action: Download it from Firebase Console and place it in android/app/',
    );
    allGood = false;
  }

  final androidManifest = File(
    '$projectRoot/android/app/src/main/AndroidManifest.xml',
  );
  if (await androidManifest.exists()) {
    final content = await androidManifest.readAsString();

    if (content.contains('android.permission.INTERNET')) {
      print('  ✅ INTERNET permission found.');
    } else {
      print('  ⚠️ INTERNET permission missing in AndroidManifest.xml');
      print(
        '     -> Action: Add <uses-permission android:name="android.permission.INTERNET"/>',
      );
      // We could auto-fix this, but for now let's warn.
      allGood = false;
    }

    if (content.contains('android.permission.POST_NOTIFICATIONS')) {
      print('  ✅ POST_NOTIFICATIONS permission found (Android 13+).');
    } else {
      print(
        '  ⚠️ POST_NOTIFICATIONS permission missing (Required for Android 13+)',
      );
      print(
        '     -> Action: Add <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
      );
      allGood = false;
    }

    if (!allGood) {
      print('\n🔧 Attempting to auto-patch AndroidManifest.xml...');
      bool patched = false;

      // Re-read content to ensure we work with the latest version if we do multiple patches
      String currentContent = await androidManifest.readAsString();

      if (!currentContent.contains('android.permission.INTERNET')) {
        // Simple injection before <application
        if (currentContent.contains('<application')) {
          currentContent = currentContent.replaceFirst(
            '<application',
            '    <uses-permission android:name="android.permission.INTERNET"/>\n    <application',
          );
          print('  ✅ Auto-patched: Added INTERNET permission.');
          patched = true;
        }
      }

      if (!currentContent.contains('android.permission.POST_NOTIFICATIONS')) {
        if (currentContent.contains('<application')) {
          currentContent = currentContent.replaceFirst(
            '<application',
            '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application',
          );
          print('  ✅ Auto-patched: Added POST_NOTIFICATIONS permission.');
          patched = true;
        }
      }

      if (patched) {
        await androidManifest.writeAsString(currentContent);
        print('✨ AndroidManifest.xml patched successfully!');
        allGood = true; // Re-evaluate as good if patched
      } else {
        print(
          '❌ Could not auto-patch AndroidManifest.xml. Please add permissions manually.',
        );
      }
    }
  } else {
    print('  ❌ AndroidManifest.xml not found at expected path.');
    allGood = false;
  }

  print('');

  // 2. Check iOS Config
  print('🍎 Checking iOS Configuration...');
  final googleServicePlist = File(
    '$projectRoot/ios/Runner/GoogleService-Info.plist',
  );
  if (await googleServicePlist.exists()) {
    print('  ✅ GoogleService-Info.plist found.');
  } else {
    print('  ❌ GoogleService-Info.plist MISSING in ios/Runner/');
    print(
      '     -> Action: Download it from Firebase Console and place it in ios/Runner/',
    );
    print(
      '     -> Note: Don\'t forget to add it to the Runner target in Xcode!',
    );
    allGood = false;
  }

  print('');

  // 3. Summary
  if (allGood) {
    print('🎉 SUCCESS! Your project configuration looks solid.');
    print('   You are ready to handle notifications like a pro.');
  } else {
    print(
      '🛑 ISSUES FOUND. Please resolve the items above to ensure reliable notifications.',
    );
  }

  print('');
}
