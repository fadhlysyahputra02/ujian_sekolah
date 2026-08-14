// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> saveAndDownloadFile(List<int> bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute("download", filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

Future<void> openUrl(String url) async {
  html.window.open(url, '_blank');
}
