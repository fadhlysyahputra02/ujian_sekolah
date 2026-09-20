import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/platform_helper.dart';

class StudentSessionService {
  static const String _prefKeySessionId = 'student_session_id';

  /// Mendapatkan atau membuat ID sesi unik untuk perangkat / browser saat ini.
  static Future<String> getOrCreateSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? sessionId = prefs.getString(_prefKeySessionId);
      if (sessionId == null || sessionId.trim().isEmpty) {
        final rand = Random().nextInt(900000) + 100000;
        sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}_$rand';
        await prefs.setString(_prefKeySessionId, sessionId);
      }
      return sessionId;
    } catch (e) {
      debugPrint('[SESSION] Error accessing SharedPreferences: $e');
      final rand = Random().nextInt(900000) + 100000;
      return 'sess_${DateTime.now().millisecondsSinceEpoch}_$rand';
    }
  }

  /// Mendapatkan ID sesi lokal jika ada, tanpa membuat yang baru.
  static Future<String?> getCurrentSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKeySessionId);
    } catch (_) {
      return null;
    }
  }

  /// Menghapus ID sesi lokal dari penyimpanan perangkat.
  static Future<void> clearLocalSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeySessionId);
    } catch (_) {}
  }

  /// Mendapatkan nama perangkat / browser yang deskriptif untuk ditampilkan ke pengguna / pengawas.
  static String getDeviceLabel() {
    return getClientDeviceLabel();
  }

  /// Mendaftarkan sesi aktif untuk siswa saat berhasil login.
  static Future<void> registerSession({
    required String schoolId,
    String? studentId,
    String? uid,
  }) async {
    final sessionId = await getOrCreateSessionId();
    final deviceLabel = getDeviceLabel();

    // 1. Jalankan via Cloud Function untuk jaminan pembaruan dengan Admin SDK
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('registerStudentSession');
      await callable.call({
        'schoolId': schoolId,
        'studentId': studentId,
        'sessionId': sessionId,
        'deviceInfo': deviceLabel,
      });
      debugPrint('[SESSION] Registered active session via CF: $sessionId ($deviceLabel)');
    } catch (e) {
      debugPrint('[SESSION] CF registerStudentSession error (fallback to Firestore): $e');
    }

    // 2. Direct Firestore update (Fast path & realtime propagation)
    try {
      if (studentId != null && studentId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(studentId)
            .update({
          'activeSession': {
            'sessionId': sessionId,
            'deviceInfo': deviceLabel,
            'loginAt': FieldValue.serverTimestamp(),
            'lastActiveAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (uid != null && uid.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .where('uid', isEqualTo: uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          await snap.docs.first.reference.update({
            'activeSession': {
              'sessionId': sessionId,
              'deviceInfo': deviceLabel,
              'loginAt': FieldValue.serverTimestamp(),
              'lastActiveAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('[SESSION] Direct Firestore update error: $e');
    }
  }

  /// Menghapus sesi aktif siswa (dipanggil saat siswa menekan Logout).
  static Future<void> clearSession({
    required String schoolId,
    String? studentId,
    String? uid,
  }) async {
    final currentSessionId = await getCurrentSessionId();

    // 1. Direct Firestore update
    try {
      if (studentId != null && studentId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(studentId)
            .update({
          'activeSession': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (uid != null && uid.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .where('uid', isEqualTo: uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          await snap.docs.first.reference.update({
            'activeSession': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('[SESSION] Direct Firestore clear session error: $e');
    }

    // 2. Cloud Function fallback
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('clearStudentSession');
      await callable.call({
        'schoolId': schoolId,
        'studentId': studentId,
        'sessionId': currentSessionId,
      });
    } catch (e) {
      debugPrint('[SESSION] CF clearStudentSession error: $e');
    }

    await clearLocalSessionId();
  }

  /// Mereset sesi aktif siswa (dipanggil oleh Admin Sekolah atau Guru Pengawas).
  static Future<bool> resetSession({
    required String schoolId,
    String? studentId,
    String? studentNis,
  }) async {
    bool success = false;

    // 1. Direct Firestore update jika studentId tersedia
    try {
      if (studentId != null && studentId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(studentId)
            .update({
          'activeSession': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        success = true;
      } else if (studentNis != null && studentNis.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .where('nis', isEqualTo: studentNis)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          await snap.docs.first.reference.update({
            'activeSession': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
        }
      }
    } catch (e) {
      debugPrint('[SESSION] Direct Firestore reset error: $e');
    }

    // 2. Cloud Function resetStudentSession (jaminan izin Admin/Pengawas)
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('resetStudentSession');
      final res = await callable.call({
        'schoolId': schoolId,
        'studentId': studentId,
        'studentNis': studentNis,
      });
      if (res.data?['success'] == true) {
        success = true;
      }
    } catch (e) {
      debugPrint('[SESSION] CF resetStudentSession error: $e');
    }

    return success;
  }

  /// Mereset seluruh sesi murid di sekolah dari 0
  static Future<bool> resetAllStudentSessions({String? schoolId}) async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('resetAllStudentSessions');
      final res = await callable.call({'schoolId': schoolId});
      return res.data?['success'] == true;
    } catch (e) {
      debugPrint('[SESSION] Error resetAllStudentSessions: $e');
      return false;
    }
  }
}
