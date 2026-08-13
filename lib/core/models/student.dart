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
    final data = doc.data() as Map<String, dynamic>;
    return Student(
      id: doc.id,
      uid: data['uid'] as String?,
      displayName: data['displayName'] ?? '',
      email: data['email'] as String?,
      gender: data['gender'] ?? 'M',
      nis: data['nis'] ?? '',
      angkatan: data['angkatan'] ?? '',
      schoolId: data['schoolId'] ?? '',
      disabled: data['disabled'] ?? false,
      archived: data['archived'] ?? false,
      tempPassword: data['tempPassword'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
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
