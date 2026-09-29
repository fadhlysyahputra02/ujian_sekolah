import 'package:cloud_firestore/cloud_firestore.dart';

class Teacher {
  final String id;
  final String? uid;
  final String displayName;
  final String? email;
  final String gender;
  final String nip;
  final List<String> subjects;
  final String schoolId;
  final bool disabled;
  final bool archived;
  final String? tempPassword;
  final Map<String, dynamic>? activeSession;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get hasActiveSession => activeSession != null && activeSession!['sessionId'] != null;
  String? get activeDeviceName => activeSession?['deviceInfo'] as String?;

  Teacher({
    required this.id,
    this.uid,
    required this.displayName,
    this.email,
    required this.gender,
    required this.nip,
    required this.subjects,
    required this.schoolId,
    required this.disabled,
    required this.archived,
    this.tempPassword,
    this.activeSession,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Teacher.fromFirestore(DocumentSnapshot doc) {
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

    return Teacher(
      id: doc.id,
      uid: data['uid']?.toString(),
      displayName: (data['displayName'] ?? '').toString(),
      email: data['email']?.toString(),
      gender: (data['gender'] ?? 'M').toString(),
      nip: (data['nip'] ?? '').toString(),
      subjects: List<String>.from((data['subjects'] as Iterable?)?.map((e) => e.toString()) ?? []),
      schoolId: (data['schoolId'] ?? '').toString(),
      disabled: data['disabled'] == true,
      archived: data['archived'] == true,
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
      'nip': nip,
      'subjects': subjects,
      'schoolId': schoolId,
      'disabled': disabled,
      'archived': archived,
      'tempPassword': tempPassword,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
    };
  }
}
