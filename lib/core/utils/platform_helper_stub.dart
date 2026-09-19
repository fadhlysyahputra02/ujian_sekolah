import 'package:flutter/foundation.dart';

/// Non-web fallback implementation
bool isWebMobile() {
  if (!kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
