// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Web implementation of WebExamMonitor.
/// Listens to browser tab visibility changes, window blur (switching apps/tabs, minimizing),
/// focus return, and beforeunload events to monitor exam integrity in PC/laptop browsers.
class WebExamMonitor {
  final VoidCallback onLeft;
  final VoidCallback onReturned;

  StreamSubscription? _visibilitySub;
  StreamSubscription? _blurSub;
  StreamSubscription? _focusSub;
  StreamSubscription? _beforeUnloadSub;

  WebExamMonitor({
    required this.onLeft,
    required this.onReturned,
  });

  void start() {
    if (!kIsWeb) return;
    try {
      // 1. Visibility change (tab switch, minimize browser window)
      _visibilitySub = html.document.onVisibilityChange.listen((_) {
        if (html.document.hidden == true) {
          onLeft();
        } else {
          onReturned();
        }
      });

      // 2. Window Blur (user clicks outside browser, Alt+Tab, opening another window / split screen)
      _blurSub = html.window.onBlur.listen((_) {
        onLeft();
      });

      // 3. Window Focus (user returns focus to the exam window)
      _focusSub = html.window.onFocus.listen((_) {
        if (html.document.hidden != true) {
          onReturned();
        }
      });

      // 4. Before Unload (tab close or reload attempt)
      _beforeUnloadSub = html.window.onBeforeUnload.listen((event) {
        if (event is html.BeforeUnloadEvent) {
          event.returnValue = 'Ujian sedang berlangsung. Anda yakin ingin meninggalkan halaman?';
        }
        onLeft();
      });
    } catch (e) {
      debugPrint('⚠️ WebExamMonitor init error: $e');
    }
  }

  void stop() {
    try {
      _visibilitySub?.cancel();
      _blurSub?.cancel();
      _focusSub?.cancel();
      _beforeUnloadSub?.cancel();
    } catch (_) {}
  }
}
