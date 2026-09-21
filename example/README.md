# Firebase Messaging Handler Example App

A comprehensive showcase application demonstrating all the features of the **Firebase Messaging Handler** plugin with the **new modular architecture**.

## 🚨 **First Time Setup**

**This example app requires Firebase to be properly configured before it can run.**

When you first run the app, you'll see a **Firebase Setup Screen** with step-by-step instructions. This prevents crashes and guides you through the complete setup process.

### **Quick Start (5 minutes)**

1. **Run the app** - You'll see the Firebase setup screen
2. **Follow the on-screen instructions** - Complete setup in the app
3. **Test notifications** - Use the built-in test features

### **What You'll Need**

- Firebase project (create at [Firebase Console](https://console.firebase.google.com/))
- Android: `google-services.json` file
- iOS: `GoogleService-Info.plist` file + APNs key
- 5 minutes of setup time

### **🔧 Important: Configure Your Own App**

**Before testing, you should configure this example with your own Firebase project:**

1. **Change Package Name** (recommended):
   ```bash
   # Update package name in pubspec.yaml
   name: your_app_name_example
   
   # Update Android package name
   # android/app/build.gradle
   applicationId "com.yourcompany.yourapp"
   
   # Update iOS bundle identifier
   # ios/Runner/Info.plist
   CFBundleIdentifier: com.yourcompany.yourapp
   ```

2. **Set Up Your Firebase Project**:
   - Create project at [Firebase Console](https://console.firebase.google.com/)
   - Add Android app with your package name
   - Add iOS app with your bundle ID
   - Download configuration files

3. **Replace Configuration Files**:
   - Place `google-services.json` in `android/app/`
   - Place `GoogleService-Info.plist` in `ios/Runner/`

4. **Update Firebase Options**:
   - Run `flutterfire configure` or manually copy `lib/firebase_options.dart.example` → `lib/firebase_options.dart` and fill in your credentials

5. **Web only — set up the service worker**:
   - Copy `web/firebase-messaging-sw.js.example` → `web/firebase-messaging-sw.js`
   - Fill in your Firebase project credentials inside that file
   - Get your VAPID key from Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
   - Pass it through `FCMConfiguration.webVapidKey` when calling `initialize()`
     (see `lib/services/firebase_messaging_handler_example_service.dart`)

> **Note:** `firebase_options.dart` and `firebase-messaging-sw.js` are gitignored — they contain credentials and must never be committed. The `.example` versions are safe templates with placeholder values.

**The app will guide you through everything step-by-step!** 🎯

## 🏗️ **New Architecture Features**

This example now showcases the **refactored plugin architecture** with:

- **🔧 Modular Design** - Clear separation of concerns with interfaces, services, and managers
- **🧪 Better Testability** - Interface-based design enables easy mocking and testing
- **📈 Enhanced Scalability** - Modular structure supports future feature additions
- **🛡️ Robust Error Handling** - Comprehensive error handling and logging system
- **⚙️ Configuration Management** - Centralized configuration with validation
- **🔄 Backward Compatibility** - Existing APIs work unchanged with new architecture

## 🚀 **What This Example Demonstrates**

This example app showcases every feature of our Firebase messaging handler plugin:

### ✅ **Core Features**
- **Unified notification stream** handling all notification types
- **Flexible initial notification control** (stream or separate handling)
- **Smart token management** with single backend call optimization
- **Capability-aware support** across Android, iOS, Web, macOS, Windows, and Linux

### ✅ **Advanced Features**
- **Interactive notification actions** with custom payloads
- **Notification scheduling** (where reported by runtime capabilities)
- **Direct app-icon badge management** (iOS)
- **Notification grouping** and threading
- **Custom sound support**
- **Built-in analytics** tracking
- **Testing utilities** with mock data

## 📋 **How to Use This Example**

### **1. Setup Firebase Project**

1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Add your Android and iOS apps to the project
3. Download and place `google-services.json` in `android/app/`
4. Download and place `GoogleService-Info.plist` in `ios/Runner/`

### **2. Confirm Firebase Project Metadata**

The example reads the messaging sender ID from generated Firebase options. You
can find it in:
- Firebase Console > Project Settings > Cloud Messaging
- Look for "Sender ID" (usually a 12-digit number)

You do not need to duplicate this value in normal v2 initialization. Web token
creation may additionally require the public VAPID key from Web Push
certificates.

### **3. Update Configuration**

The sender ID is read automatically from `DefaultFirebaseOptions.currentPlatform.messagingSenderId` — no manual update needed once you have `firebase_options.dart` in place.

### **4. Run the Example**

```bash
# Install dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Or run on specific platform
flutter run -d android
flutter run -d ios
```

## 🎮 **Using the Example App**

### **Main Screen Features:**

#### **📊 Status Dashboard**
- Shows initialization status
- Displays FCM token
- Capability-aware badge status
- **Copy FCM Token** button in app bar

#### **🚀 Feature Showcase**
- **Send Test Notification**: Interactive notification with action buttons
- **Schedule Notification**: Schedule a notification for 1 minute from now
- **Schedule Recurring**: Daily recurring notifications
- **Create Notification Group**: Group multiple notifications together
- **Update Badge**: Update the app-icon badge when the runtime supports it
- **Custom Sounds**: Create notification channels with custom sounds

#### **📨 Notification History**
- View recent notifications with rich metadata
- See notification types (foreground, background, terminated)
- Check notification actions and payloads

#### **🚀 Initial Notification**
- Shows the notification that launched the app (if any)
- Demonstrates separate handling approach

### **🧪 Testing Scenarios**

#### **Test Interactive Actions**
1. Tap "Send Test Notification"
2. You'll see a notification with "Reply", "View Details", and "Dismiss" buttons
3. Tap any button to see the action handling in action

#### **Test Notification Scheduling**
1. Tap "Schedule Notification" - notification will appear in 1 minute
2. Tap "Schedule Recurring" - daily notifications at 9:00 AM
3. Check "Recent Notifications" to see scheduled notifications

#### **Test Badge Management**
1. On iOS, tap "Update Badges" to set the app-icon badge to 5.
2. On unsupported platforms, confirm the activity feed reports that limitation.

#### **Test Notification Grouping**
1. Tap "Create Notification Group" - creates a group of 3 notifications
2. See how notifications are organized together

## 📱 **Platform-Specific Testing**

### **Android**
- Test notification channels and custom sounds
- Confirm direct badge mutation is reported unsupported
- Check notification grouping behavior
- Test scheduled notifications

### **iOS**
- Test badge management (requires proper APNs setup)
- Verify notification threading
- Check sound customization
- Test scheduled notifications

**🔑 iOS APNs Setup Required:**

For iOS notifications to work properly, you **MUST** configure APNs:

1. **Generate APNs Key:**
   - Go to [Apple Developer Console](https://developer.apple.com/)
   - Navigate to Certificates, Identifiers & Profiles
   - Go to Keys section
   - Create a new key with "Apple Push Notifications service (APNs)" enabled
   - Download the `.p8` key file

2. **Upload to Firebase:**
   - Go to Firebase Console > Project Settings > Cloud Messaging
   - Scroll to "Apple app configuration"
   - Upload your APNs key (`.p8` file)
   - Enter your Key ID and Team ID
   - Choose environment: Sandbox (development) or Production

3. **Without APNs setup:**
   - iOS notifications will NOT work
   - FCM tokens will show "APNs token not set" error
   - This is normal behavior until APNs is configured

**⚠️ This is a Firebase requirement, not our plugin limitation!**

### **Web**
- Test browser notification permissions
- Verify notification display in browser
- Check service worker integration

### **Windows / Linux**
- Remote FCM is not available on these platforms
- Use the example to validate desktop local mode instead
- Open Notification Doctor and confirm it reports `FCM unavailable` with local desktop mode active
- Test supported local presentation, inbox flows, and in-app templates
- Query runtime capabilities before testing scheduling; Linux scheduling is not
  guaranteed and recurring Windows scheduling is upstream-dependent

## 🔧 **Configuration Options**

The example demonstrates various configuration options:

```dart
// Different notification channels
final channel = NotificationChannelData(
  id: 'default_channel',
  name: 'Default Notifications',
  description: 'Default notification channel',
  importance: NotificationImportanceEnum.high,
  priority: NotificationPriorityEnum.high,
  playSound: true,
  enableVibration: true,
  enableLights: true,
);

// Interactive actions
final action = NotificationAction(
  id: 'reply',
  title: 'Reply',
  payload: {'action': 'reply', 'user_id': 'user123'},
);

// Scheduling options
await FirebaseMessagingHandler.instance.scheduleNotification(
  id: 1,
  title: 'Meeting Reminder',
  body: 'Team meeting in 30 minutes',
  scheduledDate: DateTime.now().add(Duration(minutes: 30)),
);

// Analytics tracking
messagingHandler.setAnalyticsCallback((event, data) {
  print('Analytics: $event - $data');
});
```

## 🐛 **Troubleshooting**

### **Common Issues**

**Notifications not showing:**
- Check Firebase configuration files are in place
- Run Notification Doctor and verify token, permission, and channel status
- Check AndroidManifest.xml permissions

**Scheduled notifications not working:**
- Ensure broadcast receivers are added to AndroidManifest.xml
- Check scheduled time is in the future

**iOS badges not updating:**
- Requires proper APNs certificate configuration
- May not work in simulator
- **Must upload APNs key to Firebase Console**

**APNs token not set error:**
- This is **NORMAL** until APNs is configured
- Generate APNs key in Apple Developer Console
- Upload `.p8` key file to Firebase Console
- Choose correct environment (Sandbox/Production)
- **This is a Firebase requirement, not a plugin issue**

**Custom sounds not playing:**
- Add sound files to correct platform directories
- Create notification channels before using sounds

## 📊 **Analytics Events**

The example logs all analytics events to the console:

- `notification_received` - When notifications arrive
- `notification_clicked` - When notifications are tapped
- `notification_action` - When action buttons are pressed
- `notification_scheduled` - When notifications are scheduled
- `fcm_token` - Token events (fetched, updated, error)

## 🎯 **What This Proves**

This example app is a validation harness for the package. It demonstrates:

1. Lifecycle, click, token, inbox, in-app, policy, and local-presentation APIs.
2. Runtime capability checks and explicit unsupported results.
3. Synthetic, compiled device, and credential-gated real-FCM test paths.
4. Platform setup failures surfaced through diagnostics.

It cannot prove carrier/OS delivery guarantees. Validate background delivery,
terminated launches, actions, rich media, and permission behavior on each
physical-device/OS combination you ship.

## 🚀 **Next Steps**

After testing this example:

1. **Customize for your app** - Modify the notification channels and handlers
2. **Add your Firebase config** - Replace placeholder values with real Firebase project
3. **Implement your logic** - Add your app's specific notification handling
4. **Test thoroughly** - Use the testing utilities to ensure reliability
5. **Run the release matrix** - Include physical-device and real-FCM scenarios

## 📝 **Integration Guide**

To integrate into your app:

1. **Copy the notification service** structure
2. **Customize notification channels** for your use case
3. **Implement your handlers** for different notification types
4. **Add analytics tracking** for your metrics
5. **Test with your Firebase project**

**The example serves as both a showcase and a starting point for your own implementation!** 🎉
