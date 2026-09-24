import 'package:cloud_firestore/cloud_firestore.dart';

class Student {
  final String id;
  final String? uid;
  final String displayName;
  final String? email;
  final String gender;
  final String nis;
  final String angkatan;
  final String religion;
  final String schoolId;
  final String status;
  final bool disabled;
  final bool archived;
  final bool graduated;
  final String? tempPassword;
  final Map<String, dynamic>? activeSession;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isInactive => status == 'inactive';
  bool get isGraduated => graduated || status == 'graduated' || status == 'lulus';
  bool get hasActiveSession => activeSession != null && activeSession!['sessionId'] != null;
  String? get activeDeviceName => activeSession?['deviceInfo'] as String?;

  Student({
    required this.id,
    this.uid,
    required this.displayName,
    this.email,
    required this.gender,
    required this.nis,
    required this.angkatan,
    this.religion = 'Islam',
    required this.schoolId,
    this.status = 'active',
    required this.disabled,
    required this.archived,
    this.graduated = false,
    this.tempPassword,
    this.activeSession,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }
    
    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawReligion = data['religion'] ?? data['agama'];

    return Student(
      id: doc.id,
      uid: data['uid']?.toString(),
      displayName: (data['displayName'] ?? '').toString(),
      email: data['email']?.toString(),
      gender: (data['gender'] ?? 'M').toString(),
      nis: (data['nis'] ?? '').toString(),
      angkatan: (data['angkatan'] ?? '').toString(),
      religion: (rawReligion == null || rawReligion.toString().trim().isEmpty) ? 'Islam' : rawReligion.toString().trim(),
      schoolId: (data['schoolId'] ?? '').toString(),
      status: (data['status'] ?? 'active').toString(),
      disabled: data['disabled'] == true,
      archived: data['archived'] == true,
      graduated: data['graduated'] == true || data['status'] == 'graduated' || data['status'] == 'lulus',
      tempPassword: data['tempPassword']?.toString(),
      activeSession: data['activeSession'] as Map<String, dynamic>?,
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      deletedAt: parseNullableDate(data['deletedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'gender': gender,
      'nis': nis,
      'angkatan': angkatan,
      'religion': religion,
      'agama': religion,
      'schoolId': schoolId,
      'status': status,
      'disabled': disabled,
      'archived': archived,
      'graduated': graduated,
      'tempPassword': tempPassword,
      'activeSession': activeSession,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
    };
  }
}
