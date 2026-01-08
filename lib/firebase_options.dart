import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default Firebase configuration for the app.
///
/// To get your config values:
/// 1. Go to Firebase Console (console.firebase.google.com)
/// 2. Select your project
/// 3. Click the gear icon (Project Settings)
/// 4. Scroll down to "Your apps" and select your web app
/// 5. Copy the values from the firebaseConfig object
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS is not configured yet.');
      case TargetPlatform.macOS:
        throw UnsupportedError('macOS is not configured yet.');
      case TargetPlatform.windows:
        throw UnsupportedError('Windows is not configured yet.');
      case TargetPlatform.linux:
        throw UnsupportedError('Linux is not configured yet.');
      default:
        throw UnsupportedError('This platform is not supported.');
    }
  }

  // TODO: Replace these placeholder values with your Firebase config
  // You can find these in Firebase Console > Project Settings > Your apps > Web app
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCr4YgyA6xQ1ztph3AZN7-1i-w9Iak1A-c',
    appId: '1:1061807776510:web:4aaf4b21a3b1819abafbaf',
    messagingSenderId: '1061807776510',
    projectId: 'simple-calorie-tracker-7a1c7',
    authDomain: 'simple-calorie-tracker-7a1c7.firebaseapp.com',
    storageBucket: 'simple-calorie-tracker-7a1c7.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC4o20wkWTBrNBTV7zMouw_CXq_fYUe64c',
    appId: '1:1061807776510:android:ab61bf40ee404181bafbaf',
    messagingSenderId: '1061807776510',
    projectId: 'simple-calorie-tracker-7a1c7',
    storageBucket: 'simple-calorie-tracker-7a1c7.firebasestorage.app',
  );
}
