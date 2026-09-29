import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bug_report.dart';

class BugReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createBugReport(BugReport report) async {
    final data = report.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();

    await _firestore
        .collection('schools')
        .doc(report.schoolId)
        .collection('bug_reports')
        .add(data);
  }

  Stream<List<BugReport>> streamAllBugReports() {
    late StreamController<List<BugReport>> controller;
    StreamSubscription? schoolsListSub;
    final Map<String, StreamSubscription> schoolSubs = {};
    final Map<String, List<BugReport>> schoolReports = {};
    bool isDisposed = false;

    void emitCombined() {
      if (isDisposed || controller.isClosed) return;
      final List<BugReport> combined = [];
      for (var list in schoolReports.values) {
        combined.addAll(list);
      }
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(combined);
    }

    controller = StreamController<List<BugReport>>(
      onListen: () {
        schoolsListSub = _firestore
            .collection('schools')
            .snapshots()
            .listen(
          (schoolsSnap) {
            if (isDisposed) return;
            final activeIds = schoolsSnap.docs.map((d) => d.id).toSet();

            final toRemove = schoolSubs.keys
                .where((id) => !activeIds.contains(id))
                .toList();
            for (final id in toRemove) {
              schoolSubs[id]?.cancel();
              schoolSubs.remove(id);
              schoolReports.remove(id);
            }

            if (schoolsSnap.docs.isEmpty) {
              emitCombined();
              return;
            }

            for (final schoolDoc in schoolsSnap.docs) {
              final schoolId = schoolDoc.id;
              if (!schoolSubs.containsKey(schoolId)) {
                schoolSubs[schoolId] = _firestore
                    .collection('schools')
                    .doc(schoolId)
                    .collection('bug_reports')
                    .orderBy('createdAt', descending: true)
                    .snapshots()
                    .listen(
                  (reportsSnap) {
                    if (isDisposed) return;
                    schoolReports[schoolId] = reportsSnap.docs
                        .map((doc) => BugReport.fromFirestore(doc))
                        .toList();
                    emitCombined();
                  },
                  onError: (e) {
                    debugPrint('[BugReportService] bug_reports for $schoolId: $e');
                    if (!schoolReports.containsKey(schoolId)) {
                      schoolReports[schoolId] = [];
                      emitCombined();
                    }
                  },
                );
              }
            }
          },
          onError: (e) {
            if (!isDisposed && !controller.isClosed) {
              debugPrint('[BugReportService] streamAllBugReports schools error: $e');
              controller.addError(e);
            }
          },
        );
      },
      onCancel: () {
        isDisposed = true;
        schoolsListSub?.cancel();
        for (final sub in schoolSubs.values) {
          sub.cancel();
        }
        schoolSubs.clear();
        schoolReports.clear();
      },
    );

    return controller.stream;
  }

  Stream<List<BugReport>> streamBugReportsBySchool(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('bug_reports')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => BugReport.fromFirestore(doc))
            .toList());
  }

  Future<void> updateReportStatus({
    required String schoolId,
    required String reportId,
    required String status,
    String? adminResponse,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (adminResponse != null) {
      updates['adminResponse'] = adminResponse;
    }

    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('bug_reports')
        .doc(reportId)
        .update(updates);
  }

  Future<void> deleteBugReport({
    required String schoolId,
    required String reportId,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('bug_reports')
        .doc(reportId)
        .delete();
  }
}
