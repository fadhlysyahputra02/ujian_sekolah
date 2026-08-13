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
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

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
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Teacher.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Teacher(
      id: doc.id,
      uid: data['uid'] as String?,
      displayName: data['displayName'] ?? '',
      email: data['email'] as String?,
      gender: data['gender'] ?? 'M',
      nip: data['nip'] ?? '',
      subjects: List<String>.from(data['subjects'] ?? []),
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
