// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void stopWebCameraStreams() {
  try {
    final videoElements = html.document.querySelectorAll('video');
    for (final el in videoElements) {
      if (el is html.VideoElement) {
        if (el.srcObject != null) {
          final stream = el.srcObject;
          if (stream is html.MediaStream) {
            final tracks = stream.getTracks();
            for (final track in tracks) {
              try {
                track.stop();
              } catch (_) {}
            }
          }
          el.srcObject = null;
        }
        try {
          el.pause();
        } catch (_) {}
      }
    }
  } catch (_) {}
}
