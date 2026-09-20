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

/// Mendapatkan deskripsi browser dan OS untuk Web
String getClientDeviceLabel() {
  try {
    final ua = html.window.navigator.userAgent;
    String browser = 'Web Browser';
    if (ua.contains('Edg/')) {
      browser = 'Edge';
    } else if (ua.contains('Chrome/') || ua.contains('CriOS/')) {
      browser = 'Chrome';
    } else if (ua.contains('Safari/') && !ua.contains('Chrome/')) {
      browser = 'Safari';
    } else if (ua.contains('Firefox/') || ua.contains('FxiOS/')) {
      browser = 'Firefox';
    } else if (ua.contains('OPR/') || ua.contains('Opera/')) {
      browser = 'Opera';
    }

    String os = 'Web';
    if (ua.contains('Macintosh') || ua.contains('Mac OS X')) {
      os = 'macOS';
    } else if (ua.contains('Windows')) {
      os = 'Windows';
    } else if (ua.contains('Android')) {
      os = 'Android';
    } else if (ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod')) {
      os = 'iOS';
    } else if (ua.contains('Linux')) {
      os = 'Linux';
    } else if (ua.contains('CrOS')) {
      os = 'ChromeOS';
    }

    return 'Browser $browser ($os)';
  } catch (_) {
    return 'Browser Web';
  }
}
