// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void updateWebUrlHistory(String url) {
  try {
    html.window.history.replaceState(null, '', url);
  } catch (_) {}
}
