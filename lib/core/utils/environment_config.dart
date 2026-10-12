import 'package:flutter/foundation.dart';

/// Class utility untuk membedakan environment (Dev vs Production)
/// secara otomatis berdasarkan domain URL saat ini di Flutter Web.
class EnvironmentConfig {
  /// Memeriksa apakah aplikasi diakses via domain Production (`sesicermat.web.id`).
  static bool get isProduction {
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      return host.contains('sesicermat.web.id');
    }
    return kReleaseMode;
  }

  /// Memeriksa apakah aplikasi diakses via domain Dev (`dev-sesicermat-exam.web.app`, `sesicermat.web.app`, `localhost`, dll).
  static bool get isDevelopment => !isProduction;

  /// Memeriksa apakah aplikasi berjalan di local machine (localhost).
  static bool get isLocalhost {
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      return host.contains('localhost') || host.contains('127.0.0.1');
    }
    return kDebugMode;
  }

  /// Mendapatkan nama domain yang sedang dibuka (contoh: `sesicermat.web.app` atau `sesicermat.web.id`).
  static String get currentDomain => kIsWeb ? Uri.base.host : 'Native Mobile/Desktop';

  /// Label Environment ('PRODUCTION' atau 'DEV')
  static String get environmentLabel => isProduction ? 'PRODUCTION' : 'DEV';

  /// Debug info singkat
  static String get debugInfo {
    return 'Domain: $currentDomain | Env: $environmentLabel';
  }
}
