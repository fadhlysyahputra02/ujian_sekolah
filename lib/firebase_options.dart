import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC5egeT8zanyEJe7YF442c5zUkG9nuqHVw',
    appId: '1:369910814359:web:ca058912be97dd00833bd2',
    messagingSenderId: '369910814359',
    projectId: 'sesicermat',
    authDomain: 'sesicermat.firebaseapp.com',
    storageBucket: 'sesicermat.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCc3HYVDjFCJ7iAqdiAzEkk6ApmWchk-c0',
    appId: '1:369910814359:android:a3278aa74e851694833bd2',
    messagingSenderId: '369910814359',
    projectId: 'sesicermat',
    storageBucket: 'sesicermat.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyATv7bEBXste84jCRLQyIWCKBL4xUMJ5YE',
    appId: '1:369910814359:ios:e809ca7a6475bdcb833bd2',
    messagingSenderId: '369910814359',
    projectId: 'sesicermat',
    storageBucket: 'sesicermat.firebasestorage.app',
    iosBundleId: 'com.sesicermat.sysExamSchool',
  );
}
