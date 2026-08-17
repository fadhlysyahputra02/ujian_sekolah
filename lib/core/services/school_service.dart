import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class SchoolService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Stream of all school documents in the system
  Stream<QuerySnapshot<Map<String, dynamic>>> getSchoolsStream() {
    return _firestore
        .collection('schools')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Triggers the createSchool Cloud Function to create a school and school admin user.
  Future<void> createSchool({
    required String name,
    required String code,
    required String adminEmail,
    required String adminPassword,
    required String adminName,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('createSchool');
      await callable.call({
        'name': name,
        'code': code,
        'adminEmail': adminEmail,
        'adminPassword': adminPassword,
        'adminName': adminName,
      });
    } catch (e) {
      debugPrint("Error in createSchool: $e");
      rethrow;
    }
  }

  /// Triggers the toggleSchoolStatus Cloud Function to enable/disable a school's subscription.
  Future<void> toggleSchoolStatus({
    required String schoolId,
    required bool disabled,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('toggleSchoolStatus');
      await callable.call({
        'schoolId': schoolId,
        'disabled': disabled,
      });
    } catch (e) {
      debugPrint("Error in toggleSchoolStatus: $e");
      rethrow;
    }
  }

  /// Triggers the deleteSchool Cloud Function to delete a school and its associated users.
  Future<void> deleteSchool({
    required String schoolId,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('deleteSchool');
      await callable.call({
        'schoolId': schoolId,
      });
    } catch (e) {
      debugPrint("Error in deleteSchool: $e");
      rethrow;
    }
  }

  /// Runs the initial seeding script to register the sadmin@sesicermat.com / 11081987 account
  Future<void> seedSuperAdmin() async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('seedSuperAdmin');
      await callable.call();
    } catch (e) {
      debugPrint("Error in seedSuperAdmin: $e");
      rethrow;
    }
  }

  /// Mereset password admin sekolah via Cloud Function
  Future<void> resetSchoolAdminPassword({
    required String schoolId,
    required String newPassword,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('resetSchoolAdminPassword');
      await callable.call({
        'schoolId': schoolId,
        'newPassword': newPassword,
      });
    } catch (e) {
      debugPrint("Error in resetSchoolAdminPassword: $e");
      rethrow;
    }
  }
}
