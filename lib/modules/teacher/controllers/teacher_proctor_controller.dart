import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sys_exam_school/core/services/student_session_service.dart';
import 'package:sys_exam_school/core/utils/web_audio_helper.dart';

class TeacherProctorController {
  static const List<Map<String, Color>> classColorPalette = [
    {
      'primary': Color(0xFF4F46E5), // Indigo
      'bg': Color(0xFFEEF2FF),
      'border': Color(0xFFC7D2FE),
      'text': Color(0xFF3730A3),
    },
    {
      'primary': Color(0xFFEA580C), // Orange
      'bg': Color(0xFFFFF7ED),
      'border': Color(0xFFFFEDD5),
      'text': Color(0xFF9A3412),
    },
    {
      'primary': Color(0xFFD97706), // Amber
      'bg': Color(0xFFFFFBEB),
      'border': Color(0xFFFDE68A),
      'text': Color(0xFF92400E),
    },
    {
      'primary': Color(0xFF0891B2), // Cyan
      'bg': Color(0xFFECFEFF),
      'border': Color(0xFFA5F3FC),
      'text': Color(0xFF155E75),
    },
    {
      'primary': Color(0xFFE11D48), // Rose
      'bg': Color(0xFFFFF1F2),
      'border': Color(0xFFFECDD3),
      'text': Color(0xFF9F1239),
    },
    {
      'primary': Color(0xFF9333EA), // Purple
      'bg': Color(0xFFFAF5FF),
      'border': Color(0xFFE9D5FF),
      'text': Color(0xFF6B21A8),
    },
  ];

  static Map<String, Color> getClassColorScheme(String className, List<String> roomClasses) {
    final index = roomClasses.indexOf(className);
    if (index >= 0) {
      return classColorPalette[index % classColorPalette.length];
    }
    return classColorPalette[0];
  }

  static void triggerScanFeedback({required bool isSuccess}) {
    // 1. Audio Beep Tone (Web Audio API + SystemSound)
    try {
      SystemSound.play(SystemSoundType.click);
      if (!isSuccess) {
        Future.delayed(const Duration(milliseconds: 100), () {
          SystemSound.play(SystemSoundType.click);
        });
      }
      if (kIsWeb) {
        triggerWebAudioBeep(isSuccess);
      }
    } catch (e) {
      debugPrint('Audio feedback error: $e');
    }

    // 2. Mobile Vibration (1x for Success, 2x for Failure/Already Scanned/Invalid)
    try {
      if (!kIsWeb) {
        if (isSuccess) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 180), () {
            HapticFeedback.heavyImpact();
          });
        }
      }
    } catch (e) {
      debugPrint('Vibration error: $e');
    }
  }

  static Future<bool> markStudentAttendance({
    required String schoolId,
    required String eventId,
    required String roomId,
    required Map<String, dynamic> seatData,
    required bool isAttended,
    required Map<String, bool> localAttendedMap,
    required ValueNotifier<int> seatNotifier,
    int dayIndex = 0,
    int sessionIndex = 0,
  }) async {
    final studentId = (seatData['studentId'] ?? '').toString();
    final nis = (seatData['nis'] ?? '').toString();
    final seatNum = (seatData['seatNumber'] as num?)?.toInt() ?? 0;
    final name = (seatData['displayName'] ?? seatData['studentName'] ?? 'Siswa').toString();
    final className = (seatData['classId'] ?? seatData['className'] ?? '').toString();

    final sId = studentId.toLowerCase();
    final sNis = nis.toLowerCase();
    final sName = name.toLowerCase();

    seatData['isAttended'] = isAttended;
    seatData['attended'] = isAttended;

    if (isAttended) {
      if (sId.isNotEmpty) localAttendedMap[sId] = true;
      if (sNis.isNotEmpty) localAttendedMap[sNis] = true;
      if (sName.isNotEmpty) localAttendedMap[sName] = true;
      if (seatNum > 0) {
        localAttendedMap['${roomId}_seat_$seatNum'] = true;
        localAttendedMap['seat_${roomId}_$seatNum'] = true;
      }
    } else {
      if (sId.isNotEmpty) localAttendedMap.remove(sId);
      if (sNis.isNotEmpty) localAttendedMap.remove(sNis);
      if (sName.isNotEmpty) localAttendedMap.remove(sName);
      if (seatNum > 0) {
        localAttendedMap.remove('${roomId}_seat_$seatNum');
        localAttendedMap.remove('seat_${roomId}_$seatNum');
        localAttendedMap.remove('seat_$seatNum');
      }
    }

    seatNotifier.value++;

    final subjectId = (seatData['subjectId'] ?? '').toString().trim();
    final subjectName = (seatData['subjectName'] ?? '').toString().trim();

    final docKeySuffix = subjectId.isNotEmpty ? '_$subjectId' : '';
    final docKey = studentId.isNotEmpty
        ? '${roomId}_${dayIndex}_${sessionIndex}_$studentId$docKeySuffix'
        : (nis.isNotEmpty ? '${roomId}_${dayIndex}_${sessionIndex}_$nis$docKeySuffix' : '${roomId}_${dayIndex}_${sessionIndex}_seat_$seatNum$docKeySuffix');

    final attRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .collection('attendances')
        .doc(docKey);

    // Retry logic to handle transient Firestore Web SDK INTERNAL ASSERTION errors
    const int maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (isAttended) {
          final payload = <String, dynamic>{
            'eventId': eventId,
            'roomId': roomId,
            'dayIndex': dayIndex,
            'sessionIndex': sessionIndex,
            'studentId': studentId,
            'studentName': name,
            'nis': nis,
            'className': className,
            'seatNumber': seatNum,
            'isAttended': true,
            'attendedAt': FieldValue.serverTimestamp(),
            'updatedBy': 'proctor',
          };
          if (subjectId.isNotEmpty) payload['subjectId'] = subjectId;
          if (subjectName.isNotEmpty) payload['subjectName'] = subjectName;

          await attRef.set(payload, SetOptions(merge: true));
        } else {
          await attRef.delete();
        }

        debugPrint('📌 Attendance updated for $name (seat #$seatNum): $isAttended (attempt $attempt)');
        return true;
      } catch (e) {
        debugPrint('⚠️ Attendance write attempt $attempt/$maxRetries failed for $name: $e');
        if (attempt < maxRetries) {
          // Exponential backoff: 500ms, 1500ms
          final delayMs = 500 * attempt;
          debugPrint('🔄 Retrying in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          debugPrint('❌ All $maxRetries attendance write attempts failed for $name (seat #$seatNum)');
          return false;
        }
      }
    }
    return false;
  }

  static void processScannedQr({
    required String rawData,
    required String schoolId,
    required String eventId,
    required String roomId,
    required Set<String> roomAliases,
    required Map<int, Map<String, dynamic>> seatMap,
    required StateSetter setDialogState,
    required Map<String, bool> localAttendedMap,
    required ValueNotifier<int> seatNotifier,
    void Function(String text, Color color, IconData icon)? onShowFeedback,
    int dayIndex = 0,
    int sessionIndex = 0,
    Set<String>? allowedSubjectNames,
    Set<String>? allowedSubjectIds,
  }) {
    if (rawData.isEmpty) return;

    debugPrint('=================== 🔍 QR SCAN DETECTED ===================');
    debugPrint('📷 Raw Barcode Content: "$rawData"');

    String scannedStudentId = '';
    String scannedNis = '';
    String scannedParticipantNumber = '';
    String scannedName = '';
    String scannedRoomName = '';
    String scannedSubjectId = '';
    String scannedSubjectName = '';
    int? scannedDayIndex;
    int? scannedSessionIndex;

    try {
      final trimmed = rawData.trim();
      // Clean newlines/carriage returns that might have been introduced during console prints or rendering
      final sanitized = trimmed.replaceAll('\n', '').replaceAll('\r', '').trim();
      
      if (sanitized.startsWith('{') && sanitized.endsWith('}')) {
        final Map<String, dynamic> parsedJson = jsonDecode(sanitized);
        scannedStudentId = (parsedJson['studentId'] ?? parsedJson['id'] ?? '').toString().trim();
        scannedNis = (parsedJson['nis'] ?? '').toString().trim();
        scannedParticipantNumber = (parsedJson['participantNumber'] ?? '').toString().trim();
        scannedName = (parsedJson['studentName'] ?? parsedJson['name'] ?? '').toString().trim();
        scannedRoomName = (parsedJson['roomName'] ?? parsedJson['roomId'] ?? '').toString().trim();
        scannedSubjectId = (parsedJson['subjectId'] ?? '').toString().trim();
        scannedSubjectName = (parsedJson['subjectName'] ?? '').toString().trim();
        if (parsedJson.containsKey('dayIndex')) {
          scannedDayIndex = int.tryParse(parsedJson['dayIndex'].toString());
        }
        if (parsedJson.containsKey('sessionIndex')) {
          scannedSessionIndex = int.tryParse(parsedJson['sessionIndex'].toString());
        }
      } else {
        scannedStudentId = trimmed;
        scannedNis = trimmed;
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing scanned barcode JSON: $e');
      scannedStudentId = rawData.trim();
      scannedNis = rawData.trim();
    }

    // 1. Strict Day Index Verification
    if (scannedDayIndex != null && scannedDayIndex != dayIndex) {
      triggerScanFeedback(isSuccess: false);
      if (onShowFeedback != null) {
        onShowFeedback(
          '⚠️ Hari Ujian tidak sesuai! QR ini untuk Hari ke-${scannedDayIndex + 1}.',
          const Color(0xFFDC2626),
          Icons.warning_amber_rounded,
        );
      }
      return;
    }

    // 2. Strict Session Index Verification
    if (scannedSessionIndex != null && scannedSessionIndex != sessionIndex) {
      triggerScanFeedback(isSuccess: false);
      if (onShowFeedback != null) {
        onShowFeedback(
          '⚠️ Sesi Ujian tidak sesuai! QR ini untuk Sesi ke-${scannedSessionIndex + 1}.',
          const Color(0xFFDC2626),
          Icons.warning_amber_rounded,
        );
      }
      return;
    }

    // 3. Strict Room Name Verification
    if (scannedRoomName.isNotEmpty) {
      final cleanScannedRoom = scannedRoomName.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
      bool isRoomMatch = roomAliases.any((alias) {
        final cleanAlias = alias.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        return cleanAlias == cleanScannedRoom || cleanAlias.contains(cleanScannedRoom) || cleanScannedRoom.contains(cleanAlias);
      });
      if (!isRoomMatch) {
        triggerScanFeedback(isSuccess: false);
        if (onShowFeedback != null) {
          onShowFeedback(
            '⚠️ Ruangan tidak sesuai! QR ini untuk "$scannedRoomName".',
            const Color(0xFFDC2626),
            Icons.warning_amber_rounded,
          );
        }
        return;
      }
    }

    // 3.5. Room Level Subject Verification
    if (scannedSubjectId.isNotEmpty || scannedSubjectName.isNotEmpty) {
      if (allowedSubjectNames != null && allowedSubjectNames.isNotEmpty) {
        final cleanScannedName = scannedSubjectName.toLowerCase().trim();
        final cleanScannedId = scannedSubjectId.toLowerCase().trim();

        bool isAllowed = allowedSubjectNames.any((allowed) {
          final cleanAllowed = allowed.toLowerCase().trim();
          return cleanAllowed == cleanScannedName ||
              cleanAllowed.contains(cleanScannedName) ||
              cleanScannedName.contains(cleanAllowed) ||
              (allowedSubjectIds != null && allowedSubjectIds.contains(cleanScannedId));
        });

        if (!isAllowed) {
          triggerScanFeedback(isSuccess: false);
          if (onShowFeedback != null) {
            onShowFeedback(
              '⚠️ Mata pelajaran tidak sesuai! QR ini untuk "${scannedSubjectName.isNotEmpty ? scannedSubjectName : scannedSubjectId}".',
              const Color(0xFFDC2626),
              Icons.warning_amber_rounded,
            );
          }
          return;
        }
      }
    }

    // 4. Search student in this room's seatMap
    Map<String, dynamic>? matchedSeat;
    int? matchedSeatNum;
    bool hasSubjectMismatch = false;

    for (var entry in seatMap.entries) {
      final s = entry.value;
      final sId = (s['studentId'] ?? s['id'] ?? '').toString().trim();
      final sNis = (s['nis'] ?? '').toString().trim();
      final sPart = (s['participantNumber'] ?? '').toString().trim();
      final sName = (s['displayName'] ?? s['studentName'] ?? '').toString().trim();
      final sSubjId = (s['subjectId'] ?? '').toString().trim();
      final sSubjName = (s['subjectName'] ?? '').toString().trim();

      bool isMatch = false;
      if (scannedStudentId.isNotEmpty && (sId.toLowerCase() == scannedStudentId.toLowerCase() || sId.toLowerCase().contains(scannedStudentId.toLowerCase()))) {
        isMatch = true;
      } else if (scannedNis.isNotEmpty && sNis.toLowerCase() == scannedNis.toLowerCase()) {
        isMatch = true;
      } else if (scannedParticipantNumber.isNotEmpty && sPart.toLowerCase() == scannedParticipantNumber.toLowerCase()) {
        isMatch = true;
      } else if (scannedName.isNotEmpty && sName.toLowerCase() == scannedName.toLowerCase()) {
        isMatch = true;
      }

      if (isMatch) {
        if ((scannedSubjectId.isNotEmpty || scannedSubjectName.isNotEmpty) && (sSubjId.isNotEmpty || sSubjName.isNotEmpty)) {
          final subMatch = (scannedSubjectId.isNotEmpty && (sSubjId.toLowerCase() == scannedSubjectId.toLowerCase() || sSubjId.toLowerCase().contains(scannedSubjectId.toLowerCase()) || scannedSubjectId.toLowerCase().contains(sSubjId.toLowerCase()))) ||
              (scannedSubjectName.isNotEmpty && (sSubjName.toLowerCase() == scannedSubjectName.toLowerCase() || sSubjName.toLowerCase().contains(scannedSubjectName.toLowerCase()) || scannedSubjectName.toLowerCase().contains(sSubjName.toLowerCase())));
          if (subMatch) {
            matchedSeat = s;
            matchedSeatNum = entry.key;
            hasSubjectMismatch = false;
            break;
          } else {
            hasSubjectMismatch = true;
          }
        } else {
          matchedSeat = s;
          matchedSeatNum = entry.key;
          break;
        }
      }
    }

    if (matchedSeat == null || matchedSeatNum == null) {
      triggerScanFeedback(isSuccess: false);
      if (onShowFeedback != null) {
        if (hasSubjectMismatch) {
          onShowFeedback(
            '⚠️ Mata pelajaran tidak sesuai! QR ini untuk "${scannedSubjectName.isNotEmpty ? scannedSubjectName : scannedSubjectId}".',
            const Color(0xFFDC2626),
            Icons.warning_amber_rounded,
          );
        } else {
          onShowFeedback(
            '⚠️ Siswa "${scannedName.isNotEmpty ? scannedName : scannedStudentId}" tidak ditemukan di ruangan ini.',
            const Color(0xFFDC2626),
            Icons.warning_amber_rounded,
          );
        }
      }
      return;
    }

    final name = (matchedSeat['displayName'] ?? matchedSeat['studentName'] ?? 'Siswa').toString();
    final isAlreadyAttended = matchedSeat['isAttended'] == true;

    if (!isAlreadyAttended) {
      setDialogState(() {
        matchedSeat!['isAttended'] = true;
      });
      final mId = (matchedSeat['studentId'] ?? '').toString().toLowerCase();
      final mNis = (matchedSeat['nis'] ?? '').toString().toLowerCase();
      final mName = (matchedSeat['displayName'] ?? matchedSeat['studentName'] ?? '').toString().toLowerCase();
      if (mId.isNotEmpty) localAttendedMap[mId] = true;
      if (mNis.isNotEmpty) localAttendedMap[mNis] = true;
      if (mName.isNotEmpty) localAttendedMap[mName] = true;
      localAttendedMap['${roomId}_seat_$matchedSeatNum'] = true;
      localAttendedMap['seat_${roomId}_$matchedSeatNum'] = true;

      seatNotifier.value++;

      triggerScanFeedback(isSuccess: true);

      markStudentAttendance(
        schoolId: schoolId,
        eventId: eventId,
        roomId: roomId,
        seatData: matchedSeat,
        isAttended: true,
        localAttendedMap: localAttendedMap,
        seatNotifier: seatNotifier,
        dayIndex: dayIndex,
        sessionIndex: sessionIndex,
      );

      if (onShowFeedback != null) {
        onShowFeedback(
          '✅ Presensi Berhasil! Siswa "$name" (Meja #$matchedSeatNum) ditandai HADIR!',
          const Color(0xFF059669),
          Icons.check_circle_rounded,
        );
      }
    } else {
      triggerScanFeedback(isSuccess: false);
      if (onShowFeedback != null) {
        onShowFeedback(
          'ℹ️ Siswa "$name" (Meja #$matchedSeatNum) sudah melakukan presensi sebelumnya.',
          const Color(0xFF0284C7),
          Icons.info_rounded,
        );
      }
    }
  }

  static Future<void> updateProctorStatus({
    required BuildContext context,
    required String schoolId,
    required String eventId,
    required String proctorDocId,
    required String newStatus,
    String? roomId,
    Map<int, Map<String, dynamic>>? seatMap,
    Set<String>? allowedSubjectIds,
    Set<String>? allowedSubjectNames,
    int? dayIndex,
    int? sessionIndex,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final eventRef = db
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId);
      final proctorColl = eventRef.collection('proctors');

      final bool isEnded = newStatus == 'Selesai' || newStatus == 'Ujian Selesai';

      final Map<String, dynamic> proctorPayload = {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (isEnded) {
        proctorPayload['isEnded'] = true;
        proctorPayload['endedAt'] = FieldValue.serverTimestamp();
      }

      if (proctorDocId.isNotEmpty) {
        await proctorColl.doc(proctorDocId).set(proctorPayload, SetOptions(merge: true));
        if (proctorDocId.startsWith('grid_')) {
          await proctorColl.doc(proctorDocId.substring(5)).set(proctorPayload, SetOptions(merge: true));
        }
      }

      if (roomId != null && roomId.isNotEmpty) {
        final dIdx = dayIndex ?? 0;
        final sIdx = sessionIndex ?? 0;
        final compositeKey1 = 'day_${dIdx}_session_${sIdx}_room_$roomId';
        final compositeKey2 = 'grid_day_${dIdx}_session_${sIdx}_room_$roomId';
        final compositeKey3 = '${roomId}_${dIdx}_$sIdx';

        final roomPayload = {
          ...proctorPayload,
          'roomId': roomId,
          'dayIndex': dIdx,
          'sessionIndex': sIdx,
        };

        await proctorColl.doc(compositeKey1).set(roomPayload, SetOptions(merge: true));
        await proctorColl.doc(compositeKey2).set(roomPayload, SetOptions(merge: true));
        await proctorColl.doc(compositeKey3).set(roomPayload, SetOptions(merge: true));

        // JANGAN menimpa dokumen proctor sesi lain menggunakan where('roomId', isEqualTo: roomId)
        // Cukup perbarui status sesi spesifik di dokumen event utama
        await eventRef.set({
          'proctorGridStatus': {
            compositeKey1: newStatus,
            compositeKey2: newStatus,
          },
        }, SetOptions(merge: true));
      }

      // If exam is completed by proctor, force finish all active/allocated students in this room
      if (isEnded && seatMap != null && seatMap.isNotEmpty) {
        final realtimeColl = eventRef.collection('realtime_control');
        final submissionsColl = eventRef.collection('submissions');

        final dIdx = dayIndex ?? 0;
        final sIdx = sessionIndex ?? 0;

        final batch = db.batch();
        int batchCount = 0;

        // Default subject untuk sesi aktif saat ini jika di data kursi belum ada
        final defaultSubjId = (allowedSubjectIds != null && allowedSubjectIds.isNotEmpty)
            ? allowedSubjectIds.first.trim()
            : '';
        final defaultSubjName = (allowedSubjectNames != null && allowedSubjectNames.isNotEmpty)
            ? allowedSubjectNames.first.trim()
            : '';

        for (var sData in seatMap.values) {
          final bool isAttended = sData['isAttended'] == true || sData['attended'] == true;
          final bool isWorking = sData['isWorking'] == true || sData['status'] == 'in_progress' || sData['status'] == 'working';
          final bool isLeftApp = sData['isLeftApp'] == true || sData['status'] == 'left_app';
          final bool isAlreadyCompleted = sData['isCompleted'] == true || sData['status'] == 'completed';

          // HANYA proses murid yang sudah hadir/presensi ATAU yang sudah mulai pengerjaan
          // Murid yang belum hadir & belum mengerjakan jangan diubah agar tetap bisa ikut ujian susulan
          if (!isAttended && !isWorking && !isLeftApp && !isAlreadyCompleted) {
            continue;
          }

          final sId = (sData['studentId'] ?? sData['id'] ?? '').toString().trim();
          final nis = (sData['nis'] ?? '').toString().trim();
          final sName = (sData['displayName'] ?? sData['studentName'] ?? sData['name'] ?? '').toString().trim();
          final sClass = (sData['className'] ?? sData['classId'] ?? sData['class'] ?? '').toString().trim();
          final sSubjId = (sData['subjectId'] ?? '').toString().trim();
          final sSubjName = (sData['subjectName'] ?? '').toString().trim();

          String studentDocId = sId.isNotEmpty ? sId : (nis.isNotEmpty ? nis : sName.replaceAll(' ', '_'));
          if (studentDocId.isEmpty) continue;

          // Dapatkan subjectId dan subjectName yang valid untuk sesi ini
          final effectiveSubjId = sSubjId.isNotEmpty ? sSubjId : defaultSubjId;
          final effectiveSubjName = sSubjName.isNotEmpty ? sSubjName : defaultSubjName;

          final subjectIdList = <String>{};
          if (effectiveSubjId.isNotEmpty) subjectIdList.add(effectiveSubjId.toLowerCase());
          if (allowedSubjectIds != null) {
            for (var id in allowedSubjectIds) {
              if (id.trim().isNotEmpty) subjectIdList.add(id.trim().toLowerCase());
            }
          }

          final rtPayload = <String, dynamic>{
            'studentId': sId,
            'studentName': sName,
            'nis': nis,
            'className': sClass,
            'status': 'completed',
            'isCompleted': true,
            'isWorking': false,
            'isLeftApp': false,
            'isForceSubmitted': true,
            'dayIndex': dIdx,
            'sessionIndex': sIdx,
            'updatedAt': FieldValue.serverTimestamp(),
            'completedAt': FieldValue.serverTimestamp(),
          };
          // Write session-scoped documents (${studentDocId}_${subjectId})
          final targetSubjects = subjectIdList.isNotEmpty
              ? subjectIdList
              : (effectiveSubjId.isNotEmpty ? {effectiveSubjId.toLowerCase()} : <String>{});

          for (var subj in targetSubjects) {
            if (subj.isNotEmpty) {
              final sessionDocId = '${studentDocId}_$subj';
              final sessionRtPayload = Map<String, dynamic>.from(rtPayload);
              sessionRtPayload['subjectId'] = subj;
              batch.set(realtimeColl.doc(sessionDocId), sessionRtPayload, SetOptions(merge: true));
              batchCount++;

              // Also ensure submissions doc is marked as completed
              final subPayload = <String, dynamic>{
                'studentId': sId,
                'studentName': sName,
                'nis': nis,
                'className': sClass,
                'subjectId': subj,
                'status': 'completed',
                'isCompleted': true,
                'autoSubmitted': true,
                'isForceSubmitted': true,
                'dayIndex': dIdx,
                'sessionIndex': sIdx,
                'submittedAt': FieldValue.serverTimestamp(),
              };
              if (effectiveSubjName.isNotEmpty) subPayload['subjectName'] = effectiveSubjName;
              batch.set(submissionsColl.doc(sessionDocId), subPayload, SetOptions(merge: true));
              batchCount++;
            }
          }

          if (batchCount >= 400) {
            await batch.commit();
            batchCount = 0;
          }
        }

        if (batchCount > 0) {
          await batch.commit();
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status pengawasan diubah menjadi "$newStatus"'),
            backgroundColor: newStatus == 'Selesai' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating proctor status: $e');
    }
  }

  static Future<bool> resetRealtimeControlWarning({
    required String schoolId,
    required String eventId,
    required Map<String, dynamic> seatData,
  }) async {
    try {
      final studentId = (seatData['studentId'] ?? seatData['id'] ?? '').toString();
      final nis = (seatData['nis'] ?? '').toString();
      final docId = studentId.isNotEmpty ? studentId : nis;
      if (docId.isEmpty) return false;

      final ref = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId)
          .collection('realtime_control')
          .doc(docId);

      await ref.set({
        'isLeftApp': false,
        'status': 'in_progress',
        'resetAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      seatData['isLeftApp'] = false;
      seatData['status'] = 'in_progress';
      return true;
    } catch (e) {
      debugPrint('Error resetting realtime control warning: $e');
      return false;
    }
  }

  static void showStudentDetailModal({
    required BuildContext context,
    required int seatNum,
    required Map<String, dynamic> seatData,
    required Map<String, Color> scheme,
    required String schoolId,
    required String eventId,
    required String roomId,
    required Map<String, bool> localAttendedMap,
    required ValueNotifier<int> seatNotifier,
    bool isAttended = false,
    int dayIndex = 0,
    int sessionIndex = 0,
    bool isAdminView = false,
    bool isExamEnded = false,
  }) {
    final name = (seatData['displayName'] ?? seatData['studentName'] ?? 'Siswa').toString();
    final className = (seatData['classId'] ?? seatData['className'] ?? '').toString();
    final number = (seatData['participantNumber'] ?? '-').toString();
    final nis = (seatData['nis'] ?? '-').toString();
    final angkatan = (seatData['angkatan'] ?? '-').toString();
    final rawGender = (seatData['gender'] ?? '').toString().toUpperCase();
    final genderText = (rawGender == 'F' || rawGender == 'P') ? 'Perempuan (P)' : (rawGender == 'M' || rawGender == 'L') ? 'Laki-laki (L)' : '-';
    final bool isCompleted = seatData['isCompleted'] == true || seatData['status'] == 'completed';
    final bool isLeftApp = !isCompleted && (seatData['isLeftApp'] == true || seatData['status'] == 'left_app');

    final noteController = TextEditingController(
      text: (seatData['proctorNote'] ?? '').toString(),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isCompleted
                      ? const Color(0xFF10B981)
                      : (isLeftApp ? const Color(0xFFEF4444) : scheme['bg']),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: (isCompleted || isLeftApp) ? Colors.white : scheme['primary'],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: scheme['bg'],
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: scheme['border']!),
                            ),
                            child: Text(
                              'Kelas $className',
                              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: scheme['text']),
                            ),
                          ),
                          Text(
                            'No: $number',
                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFF10B981)
                          : (isLeftApp ? const Color(0xFFEF4444) : (isAttended ? const Color(0xFF059669) : scheme['primary'])),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isCompleted
                          ? 'SELESAI (#$seatNum)'
                          : (isLeftApp ? 'KELUAR APP! (#$seatNum)' : (isAttended ? 'HADIR (#$seatNum)' : 'Meja #$seatNum')),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('NIS', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(nis.isEmpty ? '-' : nis, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    ],
                  ),
                  Container(height: 24, width: 1, color: const Color(0xFFCBD5E1)),
                  Column(
                    children: [
                      Text('Angkatan', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(angkatan.isEmpty ? '-' : angkatan, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    ],
                  ),
                  Container(height: 24, width: 1, color: const Color(0xFFCBD5E1)),
                  Column(
                    children: [
                      Text('Gender', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(genderText, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: scheme['primary'])),
                    ],
                  ),
                ],
              ),
            ),
            if ((seatData['totalQuestions'] as num?) != null && (seatData['totalQuestions'] as num) > 0) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final totalQ = (seatData['totalQuestions'] as num).toInt();
                  final ansQ = (seatData['answeredCount'] as num?)?.toInt() ?? (isCompleted ? totalQ : 0);
                  final percent = (ansQ / totalQ * 100).clamp(0, 100).round();
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.fact_check_rounded, size: 16, color: Color(0xFF2563EB)),
                                const SizedBox(width: 6),
                                Text(
                                  'Progress Pengerjaan Soal',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                ),
                              ],
                            ),
                            Text(
                              '$ansQ / $totalQ Soal ($percent%)',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF2563EB)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: totalQ > 0 ? (ansQ / totalQ).clamp(0.0, 1.0) : 0.0,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isCompleted ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),
            if (!isAdminView) ...[
              Text(
                'Aksi Pengawasan Sesi Ujian',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(height: 12),
              if (isExamEnded)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_rounded, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Text(
                        'Ujian Telah Selesai (Presensi Dinonaktifkan)',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          final newStatus = !isAttended;
                          triggerScanFeedback(isSuccess: newStatus);
                          await markStudentAttendance(
                            schoolId: schoolId,
                            eventId: eventId,
                            roomId: roomId,
                            seatData: seatData,
                            isAttended: newStatus,
                            localAttendedMap: localAttendedMap,
                            seatNotifier: seatNotifier,
                            dayIndex: dayIndex,
                            sessionIndex: sessionIndex,
                          );
                        },
                        icon: Icon(isAttended ? Icons.cancel_outlined : Icons.check_circle_rounded),
                        label: Text(isAttended ? 'Batalkan Status Hadir' : 'Tandai Hadir Manual'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAttended ? const Color(0xFFDC2626) : const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (dlgCtx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Row(
                              children: [
                                const Icon(Icons.phonelink_erase_rounded, color: Color(0xFFEF4444)),
                                const SizedBox(width: 10),
                                Text('Reset Sesi Login?', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17)),
                              ],
                            ),
                            content: Text(
                              'Sesi login siswa "$name" di perangkat/browser aktif saat ini akan diakhiri. Siswa dapat login kembali di perangkat baru.',
                              style: GoogleFonts.inter(fontSize: 13.5, height: 1.45, color: const Color(0xFF334155)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dlgCtx, false),
                                child: Text('Batal', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(dlgCtx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                                child: Text('Ya, Reset Sesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          final studentIdVal = (seatData['studentId'] ?? seatData['id'])?.toString();
                          final nisVal = (seatData['nis'])?.toString();
                          final ok = await StudentSessionService.resetSession(
                            schoolId: schoolId,
                            studentId: studentIdVal,
                            studentNis: nisVal,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Sesi login siswa "$name" berhasil direset.'
                                    : 'Gagal mereset sesi login siswa.',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.phonelink_erase_rounded, size: 17, color: Color(0xFF475569)),
                      label: Text('Reset Sesi Login Siswa', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 16),
            ],
            // ── CATATAN PENGAWAS ─────────────────────────────────────
            Text(
              'Catatan Pengawas',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 4),
            Text(
              isAdminView
                  ? 'Catatan yang diinputkan oleh guru pengawas untuk siswa ini'
                  : 'Buat catatan untuk kejadian yang perlu dilaporkan',
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 10),
            if (isAdminView) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (seatData['proctorNote'] ?? '').toString().trim().isNotEmpty
                      ? const Color(0xFFFFFBEB)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (seatData['proctorNote'] ?? '').toString().trim().isNotEmpty
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  (seatData['proctorNote'] ?? '').toString().trim().isNotEmpty
                      ? seatData['proctorNote'].toString().trim()
                      : 'Tidak ada catatan pengawas untuk siswa ini.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: (seatData['proctorNote'] ?? '').toString().trim().isNotEmpty
                        ? const Color(0xFF92400E)
                        : const Color(0xFF64748B),
                    fontStyle: (seatData['proctorNote'] ?? '').toString().trim().isNotEmpty
                        ? FontStyle.normal
                        : FontStyle.italic,
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: noteController,
                maxLines: 3,
                minLines: 2,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Contoh: Kedapatan mencontek, membawa catatan, dll.',
                  hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD97706), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final noteText = noteController.text.trim();
                    try {
                      await saveProctorNote(
                        schoolId: schoolId,
                        eventId: eventId,
                        roomId: roomId,
                        seatData: seatData,
                        note: noteText,
                        dayIndex: dayIndex,
                        sessionIndex: sessionIndex,
                      );
                      seatData['proctorNote'] = noteText;
                      seatNotifier.value++;
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              noteText.isEmpty
                                  ? 'Catatan berhasil dihapus.'
                                  : 'Catatan pengawas berhasil disimpan.',
                            ),
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Gagal menyimpan catatan: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: Text('Simpan Catatan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).whenComplete(() => noteController.dispose());
  }

  static void showExitAppLogsModal({
    required BuildContext context,
    required String schoolId,
    required String eventId,
    Set<String>? allowedStudentIds,
    Set<String>? allowedStudentNises,
    Set<String>? allowedSubjectNames,
    Set<String>? allowedSubjectIds,
    String? sessionName,
    bool isMakeupRoom = false,
  }) {
    final cleanAllowedSubjNames = allowedSubjectNames
        ?.map((s) => s.toLowerCase().trim())
        .where((s) => s.isNotEmpty)
        .toSet() ??
        {};
    final cleanAllowedSubjIds = allowedSubjectIds
        ?.map((s) => s.toLowerCase().trim())
        .where((s) => s.isNotEmpty)
        .toSet() ??
        {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.history_toggle_off_rounded, color: Color(0xFFDC2626), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Riwayat Keluar Aplikasi',
                        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Daftar murid yang terdeteksi meminimalkan / keluar aplikasi saat ujian',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('schools')
                    .doc(schoolId)
                    .collection('events')
                    .doc(eventId)
                    .collection('realtime_control')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final studentMap = <String, Map<String, dynamic>>{};

                  for (var doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final sId = (data['studentId'] ?? '').toString().trim();
                    final sNis = (data['nis'] ?? '').toString().trim();
                    final docId = doc.id.trim();

                    // Unique student key for deduplication across studentId vs sessionDocId
                    final studentKey = sId.isNotEmpty
                        ? sId
                        : (sNis.isNotEmpty ? sNis : docId.split('_').first);

                    if (studentKey.isEmpty) continue;

                    // 1. Room Student Check
                    if (allowedStudentIds != null && allowedStudentIds.isNotEmpty) {
                      final bool isRoomStudent = allowedStudentIds.contains(sId) ||
                          (sNis.isNotEmpty && allowedStudentNises != null && allowedStudentNises.contains(sNis)) ||
                          allowedStudentIds.contains(docId) ||
                          allowedStudentIds.any((id) => id.isNotEmpty && docId.contains(id)) ||
                          (allowedStudentNises != null && allowedStudentNises.any((nis) => nis.isNotEmpty && docId.contains(nis)));

                      if (!isRoomStudent) continue;
                    }

                    // 2. Makeup / Regular Session Filter Check
                    final bool isDocMakeup = data['isMakeup'] == true ||
                        (data['sessionName'] ?? '').toString().toLowerCase().contains('susulan') ||
                        (data['roomId'] ?? data['roomName'] ?? '').toString().toLowerCase().contains('susulan') ||
                        docId.toLowerCase().contains('susulan') ||
                        docId.toLowerCase().contains('makeup');

                    if (isMakeupRoom && !isDocMakeup) continue; // Skip regular exam logs when in makeup room!
                    if (!isMakeupRoom && isDocMakeup) continue; // Skip makeup exam logs when in regular room!

                    // 3. Subject / Session Check
                    final rtSubjId = (data['subjectId'] ?? '').toString().toLowerCase().trim();
                    final rtSubjName = (data['subjectName'] ?? '').toString().toLowerCase().trim();

                    if (cleanAllowedSubjNames.isNotEmpty) {
                      bool subjMatches = cleanAllowedSubjNames.contains(rtSubjName) ||
                          cleanAllowedSubjIds.contains(rtSubjId) ||
                          cleanAllowedSubjIds.contains(rtSubjName);

                      if (!subjMatches && (docId.contains('_') || docId.contains('-'))) {
                        for (final sub in cleanAllowedSubjNames) {
                          if (sub.isNotEmpty && docId.toLowerCase().contains(sub)) {
                            subjMatches = true;
                            break;
                          }
                        }
                      }

                      if (!subjMatches) {
                        continue; // Skip document from another subject/session!
                      }
                    }

                    final isLeftApp = data['isLeftApp'] == true || data['status'] == 'left_app';
                    final rawLogs = data['logs'] as List? ?? [];

                    // Filter logs array entries for the active subject/session
                    final filteredLogs = <Map<String, dynamic>>[];
                    int actualLeftCount = 0;

                    for (var l in rawLogs) {
                      if (l is Map) {
                        final entrySubjId = (l['subjectId'] ?? '').toString().toLowerCase().trim();
                        final entrySubjName = (l['subjectName'] ?? '').toString().toLowerCase().trim();

                        if (cleanAllowedSubjNames.isNotEmpty) {
                          if (entrySubjName.isNotEmpty || entrySubjId.isNotEmpty) {
                            bool entryMatches = cleanAllowedSubjNames.contains(entrySubjName) ||
                                cleanAllowedSubjIds.contains(entrySubjId) ||
                                cleanAllowedSubjIds.contains(entrySubjName);
                            if (!entryMatches) continue; // Skip log entry from another session
                          }
                        }

                        final event = (l['event'] ?? l['status'] ?? '').toString();
                        if (event == 'left_app' || event == 'status_left_app') {
                          actualLeftCount++;
                        }
                        filteredLogs.add(Map<String, dynamic>.from(l));
                      }
                    }

                    // Jumlah keluar aplikasi HANYA dihitung dari peristiwa left_app yang benar-benar tercatat pada sesi ini
                    final leftAppCount = actualLeftCount > 0
                        ? actualLeftCount
                        : (isLeftApp ? 1 : 0);
                    // HANYA tampilkan murid jika murid benar-benar pernah keluar (atau sedang keluar) di sesi ini
                    final hasViolations = actualLeftCount > 0 || isLeftApp;

                    if (hasViolations) {
                      if (studentMap.containsKey(studentKey)) {
                        // Deduplicate: merge logs and keep highest count / active status
                        final existing = studentMap[studentKey]!;
                        final existingLogs = existing['logs'] as List<Map<String, dynamic>>;

                        final Set<String> logKeys = existingLogs
                            .map((l) => '${l['timestamp']}_${l['event'] ?? l['status']}')
                            .toSet();

                        for (var fl in filteredLogs) {
                          final lk = '${fl['timestamp']}_${fl['event'] ?? fl['status']}';
                          if (!logKeys.contains(lk)) {
                            existingLogs.add(fl);
                            logKeys.add(lk);
                          }
                        }

                        final existingCount = (existing['leftAppCount'] as num?)?.toInt() ?? 0;
                        if (leftAppCount > existingCount) {
                          existing['leftAppCount'] = leftAppCount;
                        }
                        if (isLeftApp) {
                          existing['isLeftApp'] = true;
                        }
                      } else {
                        studentMap[studentKey] = {
                          'docId': doc.id,
                          'studentId': sId.isNotEmpty ? sId : data['studentId'] ?? '',
                          'studentName': data['studentName'] ?? data['nis'] ?? 'Siswa',
                          'nis': sNis,
                          'className': data['className'] ?? '',
                          'isLeftApp': isLeftApp,
                          'leftAppCount': leftAppCount,
                          'status': data['status'] ?? (isLeftApp ? 'left_app' : 'in_progress'),
                          'lastLeftAppAt': data['lastLeftAppAt'],
                          'updatedAt': data['updatedAt'],
                          'logs': filteredLogs,
                        };
                      }
                    }
                  }

                  final logsList = studentMap.values.toList();

                  if (logsList.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0FDF4),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_user_rounded, size: 48, color: Color(0xFF10B981)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Belum Ada Peringatan Keluar App',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Semua murid mengerjakan ujian dengan tertib di dalam aplikasi.',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: logsList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = logsList[index];
                      final isCurrentlyOut = item['isLeftApp'] == true;
                      final studentName = item['studentName'].toString();
                      final className = item['className'].toString();
                      final nis = item['nis'].toString();
                      final count = item['leftAppCount'];

                      final rawLogs = item['logs'] as List? ?? [];
                      final parsedLogs = <Map<String, dynamic>>[];

                      for (var entry in rawLogs) {
                        if (entry is Map) {
                          final event = (entry['event'] ?? entry['status'] ?? '').toString();
                          final tsStr = (entry['timestamp'] ?? entry['time'] ?? '').toString();
                          DateTime? dt;
                          if (tsStr.isNotEmpty) {
                            dt = DateTime.tryParse(tsStr);
                          }
                          parsedLogs.add({
                            'event': event,
                            'dateTime': dt,
                          });
                        }
                      }

                      // Urutkan secara kronologis (paling awal ke paling baru)
                      parsedLogs.sort((a, b) {
                        final dtA = a['dateTime'] as DateTime?;
                        final dtB = b['dateTime'] as DateTime?;
                        if (dtA != null && dtB != null) return dtA.compareTo(dtB);
                        return 0;
                      });

                      if (parsedLogs.isEmpty) {
                        DateTime? fallbackTime;
                        if (item['lastLeftAppAt'] is Timestamp) {
                          fallbackTime = (item['lastLeftAppAt'] as Timestamp).toDate();
                        } else if (item['updatedAt'] is Timestamp) {
                          fallbackTime = (item['updatedAt'] as Timestamp).toDate();
                        }
                        parsedLogs.add({
                          'event': 'left_app',
                          'dateTime': fallbackTime,
                        });
                      }

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCurrentlyOut ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCurrentlyOut ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: isCurrentlyOut ? const Color(0xFFDC2626) : const Color(0xFFF59E0B),
                              child: Icon(
                                isCurrentlyOut ? Icons.warning_amber_rounded : Icons.history_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    studentName,
                                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Kelas $className • NIS: $nis',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.history_rounded, size: 14, color: isCurrentlyOut ? const Color(0xFFDC2626) : const Color(0xFFD97706)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Terdeteksi $count kali keluar',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isCurrentlyOut ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (parsedLogs.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Detail Peristiwa:',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF475569),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          // Urutan dibalik (.reversed) agar nomor 1 ada di bagian bawah dan update baru bertambah naik ke atas
                                          ...parsedLogs.asMap().entries.map((e) {
                                            final idx = e.key + 1;
                                            final logItem = e.value;
                                            final event = logItem['event'].toString();
                                            final dt = logItem['dateTime'] as DateTime?;
                                            final isExit = event == 'left_app' || event == 'exited';
                                            final isStarted = (idx == 1) || event == 'started';

                                            final timeText = dt != null
                                                ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} WIB'
                                                : 'Waktu tidak tercatat';

                                            final String eventLabel;
                                            final Color eventColor;
                                            final Color dotColor;

                                            if (isStarted) {
                                              eventLabel = 'Mulai mengerjakan (standby)';
                                              eventColor = const Color(0xFF059669);
                                              dotColor = const Color(0xFF10B981);
                                            } else if (isExit) {
                                              eventLabel = 'Keluar Aplikasi';
                                              eventColor = const Color(0xFFDC2626);
                                              dotColor = const Color(0xFFDC2626);
                                            } else {
                                              eventLabel = 'Kembali ke Aplikasi';
                                              eventColor = const Color(0xFF059669);
                                              dotColor = const Color(0xFF10B981);
                                            }

                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 6),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      color: dotColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '$idx. $eventLabel',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w600,
                                                        color: eventColor,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    timeText,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w500,
                                                      color: const Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList().reversed,
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Menyimpan catatan pengawas ke subkoleksi proctor_notes di Firestore secara terisolasi.
  /// Juga menyelaraskan dengan dokumen attendance untuk kompatibilitas.
  static Future<void> saveProctorNote({
    required String schoolId,
    required String eventId,
    required String roomId,
    required Map<String, dynamic> seatData,
    required String note,
    int dayIndex = 0,
    int sessionIndex = 0,
  }) async {
    final studentId = (seatData['studentId'] ?? '').toString();
    final nis = (seatData['nis'] ?? '').toString();
    final seatNum = (seatData['seatNumber'] as num?)?.toInt() ?? 0;
    final subjectId = (seatData['subjectId'] ?? '').toString().trim();

    final docKeySuffix = subjectId.isNotEmpty ? '_$subjectId' : '';
    final docKey = studentId.isNotEmpty
        ? '${roomId}_${dayIndex}_${sessionIndex}_$studentId$docKeySuffix'
        : (nis.isNotEmpty
            ? '${roomId}_${dayIndex}_${sessionIndex}_$nis$docKeySuffix'
            : '${roomId}_${dayIndex}_${sessionIndex}_seat_$seatNum$docKeySuffix');

    final eventRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId);

    final noteRef = eventRef.collection('proctor_notes').doc(docKey);
    final attRef = eventRef.collection('attendances').doc(docKey);

    if (note.trim().isEmpty) {
      await noteRef.delete();
      await attRef.set({'proctorNote': FieldValue.delete()}, SetOptions(merge: true));
    } else {
      final payload = <String, dynamic>{
        'eventId': eventId,
        'roomId': roomId,
        'dayIndex': dayIndex,
        'sessionIndex': sessionIndex,
        'seatNumber': seatNum,
        'studentId': studentId,
        'nis': nis,
        'studentName': (seatData['displayName'] ?? seatData['studentName'] ?? '').toString(),
        'className': (seatData['className'] ?? seatData['classId'] ?? '').toString(),
        if (subjectId.isNotEmpty) 'subjectId': subjectId,
        'note': note.trim(),
        'proctorNote': note.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await noteRef.set(payload, SetOptions(merge: true));

      // Selaraskan juga ke attRef dengan informasi roomId & sesi agar konsisten jika dibaca legacy
      await attRef.set({
        'eventId': eventId,
        'roomId': roomId,
        'dayIndex': dayIndex,
        'sessionIndex': sessionIndex,
        'seatNumber': seatNum,
        if (studentId.isNotEmpty) 'studentId': studentId,
        if (nis.isNotEmpty) 'nis': nis,
        'proctorNote': note.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
