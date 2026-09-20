import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_update_model.dart';
import '../widgets/app_update_dialog.dart';

class AppUpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final int currentBuildNumber;
  final AppUpdateInfo? updateInfo;
  final String? errorMessage;

  AppUpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.currentBuildNumber,
    this.updateInfo,
    this.errorMessage,
  });
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Memeriksa apakah ada versi baru di Firestore (khusus mobile Android/iOS)
  Future<AppUpdateCheckResult> checkForUpdate() async {
    // Pada platform Web / browser, jangan periksa atau tampilkan pembaruan APK
    if (kIsWeb) {
      return AppUpdateCheckResult(
        hasUpdate: false,
        currentVersion: 'Web',
        currentBuildNumber: 0,
      );
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final doc = await _firestore.collection('system_config').doc('app_version').get();

      if (!doc.exists || doc.data() == null) {
        return AppUpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
          currentBuildNumber: currentBuildNumber,
        );
      }

      final updateInfo = AppUpdateInfo.fromMap(doc.data()!);

      // Bandingkan build number ATAU semantic version (misal 1.1.37 > 1.0.2)
      final bool isBuildNewer = updateInfo.latestBuildNumber > currentBuildNumber;
      final bool isVersionNewer = _isVersionNewer(updateInfo.latestVersion, currentVersion);
      final bool hasUpdate = isBuildNewer || isVersionNewer;

      return AppUpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        updateInfo: updateInfo,
      );
    } catch (e, stack) {
      developer.log('AppUpdateService error checking update: $e', error: e, stackTrace: stack);
      return AppUpdateCheckResult(
        hasUpdate: false,
        currentVersion: '1.0.0',
        currentBuildNumber: 0,
        errorMessage: e.toString(),
      );
    }
  }

  /// Membandingkan semantic version (misal: "1.1.37" vs "1.0.2")
  bool _isVersionNewer(String latest, String current) {
    try {
      final latestParts = latest.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Memeriksa dan menampilkan dialog jika ada update baru (khusus mobile Android/iOS)
  Future<void> checkAndShowUpdateDialog(
    BuildContext context, {
    bool silentIfLatest = true,
  }) async {
    // Pada web/browser, jangan tampilkan dialog update
    if (kIsWeb) return;

    final result = await checkForUpdate();

    if (!context.mounted) return;

    if (result.hasUpdate && result.updateInfo != null) {
      await AppUpdateDialog.show(
        context,
        updateInfo: result.updateInfo!,
        currentVersion: result.currentVersion,
      );
    } else if (!silentIfLatest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aplikasi Anda sudah menggunakan versi terbaru (v${result.currentVersion}).',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
