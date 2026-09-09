// Web implementation using dart:html
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void reloadPage() => html.window.location.reload();
String? getSessionItem(String key) => html.window.sessionStorage[key];
void setSessionItem(String key, String value) =>
    html.window.sessionStorage[key] = value;
void removeSessionItem(String key) =>
    html.window.sessionStorage.remove(key);
