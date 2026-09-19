import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class EventExamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Stream daftar event ujian di sekolah
  Stream<List<Map<String, dynamic>>> streamEvents(String schoolId) {
    if (schoolId.isEmpty) return Stream.value([]);
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

  /// Membuat atau memperbarui Event Ujian
  Future<String> createEvent({
    required String schoolId,
    required Map<String, dynamic> eventInfo,
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> timetable,
    String? eventId,
  }) async {
    try {
      final callable = _functions.httpsCallable('createEvent');
      final response = await callable.call({
        'schoolId': schoolId,
        'eventInfo': eventInfo,
        'sessions': sessions,
        'timetable': timetable,
        'eventId': eventId,
      });
      return response.data['eventId'] as String;
    } catch (cfError) {
      // Direct Firestore write fallback
      final eventRef = (eventId != null && eventId.trim().isNotEmpty)
          ? _firestore.collection('schools').doc(schoolId).collection('events').doc(eventId)
          : _firestore.collection('schools').doc(schoolId).collection('events').doc();
      final actualEventId = eventRef.id;

      // Clean old subcollections
      final subcollections = ['sessions', 'timetable', 'proctors', 'allocations', 'participants'];
      for (final sub in subcollections) {
        final snap = await eventRef.collection(sub).get();
        if (snap.docs.isNotEmpty) {
          final b = _firestore.batch();
          for (final d in snap.docs) {
            b.delete(d.reference);
          }
          await b.commit();
        }
      }

      final startDt = eventInfo['startDate'] != null
          ? (DateTime.tryParse(eventInfo['startDate'].toString()) ?? DateTime.now())
          : DateTime.now();
      final endDt = eventInfo['endDate'] != null
          ? (DateTime.tryParse(eventInfo['endDate'].toString()) ?? DateTime.now())
          : DateTime.now();

      await eventRef.set({
        'name': eventInfo['name'] ?? '',
        'type': eventInfo['type'] ?? 'UAS',
        'academicYear': eventInfo['academicYear'] ?? '',
        'startDate': Timestamp.fromDate(startDt),
        'endDate': Timestamp.fromDate(endDt),
        'description': eventInfo['description'] ?? '',
        'status': 'draft',
        'targetClasses': eventInfo['targetClasses'] ?? [],
        'roomAssignments': eventInfo['roomAssignments'] ?? {},
        'roomLayouts': eventInfo['roomLayouts'] ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'config': {
          'participantNumberFormat': eventInfo['participantNumberFormat'] ?? '[angkatan][roomCode][seatNumber]',
          'seatNumberPadding': eventInfo['seatNumberPadding'] ?? 3,
        },
        'draftState': eventInfo['draftState'],
      }, SetOptions(merge: true));

      // Save sessions (per day & per session)
      final Map<String, String> sessionMap = {};
      final batch = _firestore.batch();
      for (int i = 0; i < sessions.length; i++) {
        final s = sessions[i];
        final orderVal = (s['order'] as num?)?.toInt() ?? (i + 1);
        final dIdx = s['dayIndex'] ?? 0;
        final sIdx = s['sessionIndex'] ?? i;
        final docId = s['docId']?.toString() ?? s['tempId']?.toString() ?? (s['dayIndex'] != null && s['sessionIndex'] != null ? 'day_${dIdx}_session_$sIdx' : 'session_$orderVal');
        final sRef = eventRef.collection('sessions').doc(docId);
        batch.set(sRef, {
          'name': s['name'] ?? 'Sesi ${sIdx + 1}',
          'date': s['date'] ?? '',
          'dayIndex': dIdx,
          'sessionIndex': sIdx,
          'startTime': s['startTime'] ?? '',
          'endTime': s['endTime'] ?? '',
          'maxDuration': s['maxDuration'] ?? 90,
          'order': orderVal,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (s['tempId'] != null) {
          sessionMap[s['tempId'].toString()] = docId;
        }
        sessionMap[docId] = docId;
      }

      // Save timetable
      for (final t in timetable) {
        final tRef = eventRef.collection('timetable').doc();
        final rawSessId = t['sessionId']?.toString();
        final dayIdx = (t['dayIndex'] as num?)?.toInt() ?? (t['day'] != null ? int.tryParse(t['day'].toString()) ?? 0 : 0);
        final sessIdx = (t['sessionIndex'] as num?)?.toInt() ?? (t['slotIndex'] != null ? int.tryParse(t['slotIndex'].toString()) ?? 0 : 0);
        final fallbackKey = 'day_${dayIdx}_session_$sessIdx';
        final mappedSessionId = (rawSessId != null && rawSessId.isNotEmpty)
            ? (sessionMap[rawSessId] ?? rawSessId)
            : fallbackKey;

        batch.set(tRef, {
          'classId': t['classId']?.toString() ?? '',
          'className': t['className']?.toString() ?? '',
          'subjectId': t['subjectId']?.toString() ?? '',
          'subjectName': t['subjectName']?.toString() ?? '',
          'sessionId': mappedSessionId,
          'dayIndex': dayIdx,
          'sessionIndex': sessIdx,
          'teacherId': t['teacherId']?.toString() ?? '',
          'teacherName': t['teacherName']?.toString() ?? '',
          'status': 'scheduled',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      return actualEventId;
    }
  }

  /// Menghapus Event Ujian beserta seluruh subkoleksinya via Cloud Function
  Future<void> deleteEvent({
    required String schoolId,
    required String eventId,
  }) async {
    final callable = _functions.httpsCallable('deleteEvent');
    await callable.call({
      'schoolId': schoolId,
      'eventId': eventId,
    });
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
    try {
      final callable = _functions.httpsCallable('assignProctors');
      await callable.call({
        'schoolId': schoolId,
        'eventId': eventId,
        'assignments': assignments,
      });
    } catch (cfError) {
      final proctorsRef = _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId)
          .collection('proctors');

      final existingSnap = await proctorsRef.get();
      if (existingSnap.docs.isNotEmpty) {
        final b = _firestore.batch();
        for (final doc in existingSnap.docs) {
          b.delete(doc.reference);
        }
        await b.commit();
      }

      final batch = _firestore.batch();
      for (final a in assignments) {
        final docRef = proctorsRef.doc();
        batch.set(docRef, {
          'sessionId': a['sessionId']?.toString() ?? '',
          'dayIndex': a['dayIndex'] ?? 0,
          'sessionIndex': a['sessionIndex'] ?? 0,
          'roomId': a['roomId']?.toString() ?? '',
          'teacherId': a['teacherId']?.toString() ?? '',
          'role': a['role']?.toString() ?? 'main',
          'notes': a['notes']?.toString() ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
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
