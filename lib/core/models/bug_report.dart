import 'package:cloud_firestore/cloud_firestore.dart';

class BugReport {
  final String id;
  final String schoolId;
  final String schoolName;
  final String schoolCode;
  final String senderEmail;
  final String title;
  final String description;
  final String screenshotUrl;
  final String status;
  final String? adminResponse;
  final DateTime createdAt;
  final DateTime? updatedAt;

  BugReport({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.schoolCode,
    required this.senderEmail,
    required this.title,
    required this.description,
    required this.screenshotUrl,
    this.status = 'terbuka',
    this.adminResponse,
    required this.createdAt,
    this.updatedAt,
  });

  factory BugReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final parentSchoolId = doc.reference.parent.parent?.id;

    return BugReport(
      id: doc.id,
      schoolId: (data['schoolId'] != null && data['schoolId'].toString().isNotEmpty)
          ? data['schoolId'].toString()
          : (parentSchoolId ?? ''),
      schoolName: data['schoolName'] ?? 'Sekolah Tidak Diketahui',
      schoolCode: data['schoolCode'] ?? '-',
      senderEmail: data['senderEmail'] ?? '-',
      title: data['title'] ?? 'Laporan Bug',
      description: data['description'] ?? '',
      screenshotUrl: data['screenshotUrl'] ?? '',
      status: data['status'] ?? 'terbuka',
      adminResponse: data['adminResponse'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schoolId': schoolId,
      'schoolName': schoolName,
      'schoolCode': schoolCode,
      'senderEmail': senderEmail,
      'title': title,
      'description': description,
      'screenshotUrl': screenshotUrl,
      'status': status,
      'adminResponse': adminResponse,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
    };
  }
}
