import 'package:cloud_firestore/cloud_firestore.dart';

class Student {
  final String id;
  final String? uid;
  final String displayName;
  final String? email;
  final String gender;
  final String nis;
  final String angkatan;
  final String schoolId;
  final bool disabled;
  final bool archived;
  final String? tempPassword;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Student({
    required this.id,
    this.uid,
    required this.displayName,
    this.email,
    required this.gender,
    required this.nis,
    required this.angkatan,
    required this.schoolId,
    required this.disabled,
    required this.archived,
    this.tempPassword,
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

    return Student(
      id: doc.id,
      uid: data['uid']?.toString(),
      displayName: (data['displayName'] ?? '').toString(),
      email: data['email']?.toString(),
      gender: (data['gender'] ?? 'M').toString(),
      nis: (data['nis'] ?? '').toString(),
      angkatan: (data['angkatan'] ?? '').toString(),
      schoolId: (data['schoolId'] ?? '').toString(),
      disabled: data['disabled'] == true,
      archived: data['archived'] == true,
      tempPassword: data['tempPassword']?.toString(),
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
