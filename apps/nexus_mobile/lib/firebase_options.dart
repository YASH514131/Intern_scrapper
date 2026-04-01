import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase options are not configured for web in this app.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase options are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC_iaLU8Q0ZFh7TVL3CRzlPLhRUpCDq1MM',
    appId: '1:943101881292:android:9d70abb556f75652d78b69',
    messagingSenderId: '943101881292',
    projectId: 'nexus-2fa13',
    storageBucket: 'nexus-2fa13.firebasestorage.app',
  );

  // Replace these placeholders by running: flutterfire configure

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBE221nkK0VjE_ir5_cKnu2SX-W2_elwAo',
    appId: '1:943101881292:ios:415703398717ace1d78b69',
    messagingSenderId: '943101881292',
    projectId: 'nexus-2fa13',
    storageBucket: 'nexus-2fa13.firebasestorage.app',
    iosBundleId: 'com.example.nexusMobile',
  );
}
