import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/student.dart';
import '../models/teacher.dart';

class AdminUserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Stream active teachers of a school
  Stream<List<Teacher>> streamTeachers(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .where('archived', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Teacher.fromFirestore(doc)).toList();
      list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return list;
    });
  }

  /// Stream active students of a school
  Stream<List<Student>> streamStudents(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .where('archived', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Student.fromFirestore(doc)).toList();
      list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return list;
    });
  }

  /// Get active teachers once
  Future<List<Teacher>> getTeachersOnce(String schoolId) async {
    final snapshot = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .where('archived', isEqualTo: false)
        .get();
    final list = snapshot.docs.map((doc) => Teacher.fromFirestore(doc)).toList();
    list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  }

  /// Get active students once
  Future<List<Student>> getStudentsOnce(String schoolId) async {
    final snapshot = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .where('archived', isEqualTo: false)
        .get();
    final list = snapshot.docs.map((doc) => Student.fromFirestore(doc)).toList();
    list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  }

  /// Stream archived users (both teachers and students) of a school
  Stream<List<Map<String, dynamic>>> streamArchive(String schoolId) {
    return _firestore
        .collection('archives')
        .doc(schoolId)
        .collection('users')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Create a new teacher
  Future<Map<String, dynamic>> createTeacher({
    required String schoolId,
    required String displayName,
    required String gender,
    required String nip,
    String? email,
    required List<String> subjects,
    required bool createAuth,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('createTeacher');
    final response = await callable.call({
      'schoolId': schoolId,
      'displayName': displayName,
      'gender': gender,
      'nip': nip,
      'email': email,
      'subjects': subjects,
      'createAuth': createAuth,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Create a new student
  Future<Map<String, dynamic>> createStudent({
    required String schoolId,
    required String displayName,
    required String gender,
    required String nis,
    required String angkatan,
    String? email,
    required bool createAuth,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('createStudent');
    final response = await callable.call({
      'schoolId': schoolId,
      'displayName': displayName,
      'gender': gender,
      'nis': nis,
      'angkatan': angkatan,
      'email': email,
      'createAuth': createAuth,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Update an existing teacher
  Future<void> updateTeacher({
    required String schoolId,
    required String docId,
    required String displayName,
    required String gender,
    required String nip,
    String? email,
    required List<String> subjects,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('updateTeacher');
    await callable.call({
      'schoolId': schoolId,
      'docId': docId,
      'displayName': displayName,
      'gender': gender,
      'nip': nip,
      'email': email,
      'subjects': subjects,
    });
  }

  /// Update an existing student
  Future<void> updateStudent({
    required String schoolId,
    required String docId,
    required String displayName,
    required String gender,
    required String nis,
    required String angkatan,
    String? email,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('updateStudent');
    await callable.call({
      'schoolId': schoolId,
      'docId': docId,
      'displayName': displayName,
      'gender': gender,
      'nis': nis,
      'angkatan': angkatan,
      'email': email,
    });
  }

  /// Generate or reset temporary password
  Future<String> generateTempPassword({
    required String schoolId,
    required String collectionType,
    required String docId,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('generateTempPassword');
    final response = await callable.call({
      'schoolId': schoolId,
      'collectionType': collectionType,
      'docId': docId,
    });
    return response.data['tempPassword'] as String;
  }

  /// Soft delete user
  Future<void> softDeleteUser({
    required String schoolId,
    required String collectionType,
    required String docId,
    String? reason,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('softDeleteUser');
    await callable.call({
      'schoolId': schoolId,
      'collectionType': collectionType,
      'docId': docId,
      'reason': reason,
    });
  }

  /// Restore user from archive
  Future<void> restoreUser({
    required String schoolId,
    required String collectionType,
    required String docId,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('restoreUser');
    await callable.call({
      'schoolId': schoolId,
      'collectionType': collectionType,
      'docId': docId,
    });
  }

  /// Permanently delete user
  Future<void> permanentDeleteUser({
    required String schoolId,
    required String collectionType,
    required String docId,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('permanentDeleteUser');
    await callable.call({
      'schoolId': schoolId,
      'collectionType': collectionType,
      'docId': docId,
    });
  }

  /// Import students bulk
  Future<List<Map<String, dynamic>>> importStudentsBulk({
    required String schoolId,
    required List<Map<String, dynamic>> rows,
    required bool createAuth,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('importStudentsBulk');
    final response = await callable.call({
      'schoolId': schoolId,
      'rows': rows,
      'createAuth': createAuth,
    });
    final list = List.from(response.data['results'] as List);
    return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  /// Import teachers bulk
  Future<List<Map<String, dynamic>>> importTeachersBulk({
    required String schoolId,
    required List<Map<String, dynamic>> rows,
    required bool createAuth,
  }) async {
    final HttpsCallable callable = _functions.httpsCallable('importTeachersBulk');
    final response = await callable.call({
      'schoolId': schoolId,
      'rows': rows,
      'createAuth': createAuth,
    });
    final list = List.from(response.data['results'] as List);
    return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  /// Stream subjects of a school
  Stream<List<Map<String, dynamic>>> streamSubjects(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('subjects')
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Add a subject
  Future<void> addSubject({
    required String schoolId,
    required String name,
    required String code,
  }) async {
    final check = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('subjects')
        .where('name', isEqualTo: name.trim())
        .get();
    if (check.docs.isNotEmpty) {
      throw 'Mata pelajaran "$name" sudah terdaftar.';
    }

    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('subjects')
        .add({
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update a subject
  Future<void> updateSubject({
    required String schoolId,
    required String docId,
    required String name,
    required String code,
  }) async {
    final check = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('subjects')
        .where('name', isEqualTo: name.trim())
        .get();
    if (check.docs.any((doc) => doc.id != docId)) {
      throw 'Mata pelajaran "$name" sudah terdaftar.';
    }

    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('subjects')
        .doc(docId)
        .update({
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
    });
  }

  /// Delete a subject
  Future<void> deleteSubject({
    required String schoolId,
    required String docId,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('subjects')
        .doc(docId)
        .delete();
  }

  // ─────────────────── CLASS MANAGEMENT ───────────────────

  /// Stream active classes of a school
  Stream<List<Map<String, dynamic>>> streamClasses(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Add a new class
  Future<void> addClass({
    required String schoolId,
    required String name,
  }) async {
    final check = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .where('name', isEqualTo: name.trim())
        .get();
    if (check.docs.isNotEmpty) {
      throw 'Kelas "$name" sudah terdaftar.';
    }
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .add({
      'name': name.trim(),
      'studentIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update a class
  Future<void> updateClass({
    required String schoolId,
    required String classId,
    required String name,
  }) async {
    final check = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .where('name', isEqualTo: name.trim())
        .get();
    if (check.docs.any((doc) => doc.id != classId)) {
      throw 'Kelas "$name" sudah terdaftar.';
    }
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .update({
      'name': name.trim(),
    });
  }

  /// Delete a class
  Future<void> deleteClass({
    required String schoolId,
    required String classId,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .delete();
  }

  /// Add a student to a class
  Future<void> addStudentToClass({
    required String schoolId,
    required String classId,
    required String studentId,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .update({
      'studentIds': FieldValue.arrayUnion([studentId]),
    });
  }

  /// Add multiple students to a class
  Future<void> addStudentsToClass({
    required String schoolId,
    required String classId,
    required List<String> studentIds,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .update({
      'studentIds': FieldValue.arrayUnion(studentIds),
    });
  }

  /// Remove a student from a class
  Future<void> removeStudentFromClass({
    required String schoolId,
    required String classId,
    required String studentId,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .update({
      'studentIds': FieldValue.arrayRemove([studentId]),
    });
  }
}
