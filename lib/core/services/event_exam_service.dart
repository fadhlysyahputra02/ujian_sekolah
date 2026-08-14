import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class EventExamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Stream daftar event ujian di sekolah
  Stream<List<Map<String, dynamic>>> streamEvents(String schoolId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Stream sesi ujian per event
  Stream<List<Map<String, dynamic>>> streamSessions(String schoolId, String eventId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .collection('sessions')
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Stream jadwal pelajaran per event
  Stream<List<Map<String, dynamic>>> streamTimetable(String schoolId, String eventId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .collection('timetable')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Stream alokasi tempat duduk per event
  Stream<List<Map<String, dynamic>>> streamAllocations(String schoolId, String eventId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .collection('allocations')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Stream kursi (seating) teralokasi dari runId tertentu
  Stream<List<Map<String, dynamic>>> streamSeats(String schoolId, String eventId, String allocationId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .collection('allocations')
        .doc(allocationId)
        .collection('seats')
        .orderBy('seatNumber')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Stream daftar pengawas terdaftar
  Stream<List<Map<String, dynamic>>> streamProctors(String schoolId, String eventId) {
    return _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .collection('proctors')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Membuat Event Ujian baru
  Future<String> createEvent({
    required String schoolId,
    required Map<String, dynamic> eventInfo,
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> timetable,
  }) async {
    final callable = _functions.httpsCallable('createEvent');
    final response = await callable.call({
      'schoolId': schoolId,
      'eventInfo': eventInfo,
      'sessions': sessions,
      'timetable': timetable,
    });
    return response.data['eventId'] as String;
  }

  /// Simulasi preview alokasi tempat duduk
  Future<Map<String, dynamic>> previewAllocation({
    required String schoolId,
    required String eventId,
    required String mode,
    required Map<String, dynamic> options,
  }) async {
    final callable = _functions.httpsCallable('previewAllocation');
    final response = await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
      'mode': mode,
      'options': options,
    });
    return Map<String, dynamic>.from(response.data);
  }

  /// Eksekusi/simpan alokasi tempat duduk
  Future<String> executeAllocation({
    required String schoolId,
    required String eventId,
    required String mode,
    required Map<String, dynamic> options,
  }) async {
    final callable = _functions.httpsCallable('executeAllocation');
    final response = await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
      'mode': mode,
      'options': options,
    });
    return response.data['allocationId'] as String;
  }

  /// Generate nomor peserta
  Future<int> generateParticipantNumbers({
    required String schoolId,
    required String eventId,
    required String allocationId,
    required Map<String, dynamic> formatConfig,
  }) async {
    final callable = _functions.httpsCallable('generateParticipantNumbers');
    final response = await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
      'allocationId': allocationId,
      'formatConfig': formatConfig,
    });
    return response.data['generatedCount'] as int;
  }

  /// Ekspor daftar hadir per ruang
  Future<String> exportRoomList({
    required String schoolId,
    required String eventId,
    required String allocationId,
    String? roomId,
  }) async {
    final callable = _functions.httpsCallable('exportRoomList');
    final response = await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
      'allocationId': allocationId,
      if (roomId != null) 'roomId': roomId,
    });
    return response.data['downloadUrl'] as String;
  }

  /// Menugaskan pengawas ujian
  Future<void> assignProctors({
    required String schoolId,
    required String eventId,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final callable = _functions.httpsCallable('assignProctors');
    await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
      'assignments': assignments,
    });
  }

  /// Reschedule sesi ujian
  Future<void> rescheduleSession({
    required String schoolId,
    required String eventId,
    required String sessionId,
    required String newDate,
    required String newStartTime,
    required String newEndTime,
  }) async {
    final callable = _functions.httpsCallable('rescheduleSession');
    await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
      'sessionId': sessionId,
      'newDate': newDate,
      'newStartTime': newStartTime,
      'newEndTime': newEndTime,
    });
  }

  /// Membatalkan run alokasi tertentu
  Future<void> rollbackAllocation({
    required String schoolId,
    required String eventId,
    required String allocationId,
  }) async {
    final callable = _functions.httpsCallable('rollbackAllocation');
    await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
      'allocationId': allocationId,
    });
  }

  /// Memperbarui status event (e.g. publish atau close)
  Future<void> updateEventStatus(String schoolId, String eventId, String status) async {
    await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
