class ErrorFormatter {
  /// Cleans raw error strings by stripping Firebase internal tags, exception prefixes, etc.
  static String format(dynamic error) {
    if (error == null) return 'Terjadi kesalahan tidak diketahui.';
    String msg = error.toString();

    // Remove bracket tags like [firebase_functions/internal], [firebase_auth/email-already-in-use]
    msg = msg.replaceAll(RegExp(r'\[.*?\]\s*'), '');

    // Remove prefixes like "Exception:", "FirebaseException:", "FirebaseFunctionsException:"
    msg = msg.replaceAll(
      RegExp(r'^(FirebaseFunctionsException|FirebaseException|PlatformException|Exception):\s*', caseSensitive: false),
      '',
    );

    msg = msg.trim();

    if (msg.isEmpty) {
      return 'Terjadi kesalahan pada sistem.';
    }

    return msg;
  }
}
