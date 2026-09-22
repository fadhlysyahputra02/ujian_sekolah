import 'package:flutter/foundation.dart';

/// Non-web fallback implementation
bool isWebMobile() {
  if (!kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Helper untuk memeriksa apakah perangkat saat ini adalah mobile (aplikasi mobile atau web mobile)
bool isMobileDevice() {
  if (!kIsWeb) {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
  return isWebMobile();
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
