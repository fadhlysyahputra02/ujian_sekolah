// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Web implementation of isWebMobile.
/// Detects if the browser is running on a mobile / tablet device (smartphone/tablet browser)
/// while returning false for desktop PC/laptop browsers (Chrome, Edge, Safari, Firefox on Windows/macOS/Linux).
bool isWebMobile() {
  if (!kIsWeb) return false;
  final ua = (html.window.navigator.userAgent).toLowerCase();
  final isMobileUA = ua.contains('android') ||
      ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod') ||
      ua.contains('mobile') ||
      ua.contains('silk/') ||
      ua.contains('blackberry') ||
      ua.contains('opera mini');

  final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  return isMobileUA || isMobilePlatform;
}
