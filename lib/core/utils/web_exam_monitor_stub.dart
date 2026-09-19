import 'package:flutter/foundation.dart';

/// Stub implementation for non-web platforms.
class WebExamMonitor {
  final VoidCallback onLeft;
  final VoidCallback onReturned;

  WebExamMonitor({
    required this.onLeft,
    required this.onReturned,
  });

  void start() {
    // No-op on mobile/native (native lifecycle is handled by WidgetsBindingObserver)
  }

  void stop() {
    // No-op
  }
}
