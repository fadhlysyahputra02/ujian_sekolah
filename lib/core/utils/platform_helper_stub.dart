import 'package:flutter/foundation.dart';

/// Non-web fallback implementation
bool isWebMobile() {
  if (!kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Mendapatkan deskripsi perangkat yang ramah pengguna untuk non-web (Aplikasi)
String getClientDeviceLabel() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Aplikasi Android';
    case TargetPlatform.iOS:
      return 'Aplikasi iOS';
    case TargetPlatform.macOS:
      return 'Aplikasi Desktop (macOS)';
    case TargetPlatform.windows:
      return 'Aplikasi Desktop (Windows)';
    case TargetPlatform.linux:
      return 'Aplikasi Desktop (Linux)';
    default:
      return 'Aplikasi SesiCermat';
  }
}
