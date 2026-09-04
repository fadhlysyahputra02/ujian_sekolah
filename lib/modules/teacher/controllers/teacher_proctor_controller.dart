import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

    final docKey = studentId.isNotEmpty
        ? '${roomId}_${dayIndex}_${sessionIndex}_$studentId'
        : (nis.isNotEmpty ? '${roomId}_${dayIndex}_${sessionIndex}_$nis' : '${roomId}_${dayIndex}_${sessionIndex}_seat_$seatNum');

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
          await attRef.set({
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
          }, SetOptions(merge: true));
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
  }) {
    if (rawData.isEmpty) return;

    debugPrint('=================== 🔍 QR SCAN DETECTED ===================');
    debugPrint('📷 Raw Barcode Content: "$rawData"');

    String scannedStudentId = '';
    String scannedNis = '';
    String scannedParticipantNumber = '';
    String scannedName = '';
    String scannedRoomName = '';
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

    // 4. Search student in this room's seatMap
    Map<String, dynamic>? matchedSeat;
    int? matchedSeatNum;

    for (var entry in seatMap.entries) {
      final s = entry.value;
      final sId = (s['studentId'] ?? s['id'] ?? '').toString().trim();
      final sNis = (s['nis'] ?? '').toString().trim();
      final sPart = (s['participantNumber'] ?? '').toString().trim();
      final sName = (s['displayName'] ?? s['studentName'] ?? '').toString().trim();

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
        matchedSeat = s;
        matchedSeatNum = entry.key;
        break;
      }
    }

    if (matchedSeat == null || matchedSeatNum == null) {
      triggerScanFeedback(isSuccess: false);
      if (onShowFeedback != null) {
        onShowFeedback(
          '⚠️ Siswa "${scannedName.isNotEmpty ? scannedName : scannedStudentId}" tidak ditemukan di ruangan ini.',
          const Color(0xFFDC2626),
          Icons.warning_amber_rounded,
        );
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
  }) async {
    if (proctorDocId.isEmpty || proctorDocId.startsWith('grid_')) return;
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId)
          .collection('proctors')
          .doc(proctorDocId)
          .update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: isCompleted
                      ? const Color(0xFF10B981)
                      : (isLeftApp ? const Color(0xFFEF4444) : scheme['bg']),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: (isCompleted || isLeftApp) ? Colors.white : scheme['primary'],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme['bg'],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: scheme['border']!),
                            ),
                            child: Text(
                              'Kelas $className',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: scheme['text']),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'No. Peserta: $number',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFF10B981)
                        : (isLeftApp ? const Color(0xFFEF4444) : (isAttended ? const Color(0xFF059669) : scheme['primary'])),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isCompleted
                        ? 'SELESAI (#$seatNum)'
                        : (isLeftApp ? 'KELUAR APP! (#$seatNum)' : (isAttended ? 'HADIR (#$seatNum)' : 'Meja #$seatNum')),
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
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
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 20),
            Text(
              'Aksi Pengawasan Sesi Ujian',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),
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
            if (isLeftApp) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await resetRealtimeControlWarning(
                          schoolId: schoolId,
                          eventId: eventId,
                          seatData: seatData,
                        );
                        seatNotifier.value++;
                        triggerScanFeedback(isSuccess: true);
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reset Peringatan Keluar App'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void showExitAppLogsModal({
    required BuildContext context,
    required String schoolId,
    required String eventId,
    Set<String>? allowedStudentIds,
    Set<String>? allowedStudentNises,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.history_toggle_off_rounded, color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Riwayat Keluar Aplikasi',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Daftar murid yang terdeteksi meminimalkan / keluar aplikasi saat ujian',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),
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
                  final logsList = <Map<String, dynamic>>[];

                  for (var doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final sId = (data['studentId'] ?? '').toString().trim();
                    final sNis = (data['nis'] ?? '').toString().trim();
                    final docId = doc.id.trim();

                    if (allowedStudentIds != null && allowedStudentIds.isNotEmpty) {
                      final bool isRoomStudent = allowedStudentIds.contains(sId) ||
                          (sNis.isNotEmpty && allowedStudentNises != null && allowedStudentNises.contains(sNis)) ||
                          allowedStudentIds.contains(docId) ||
                          allowedStudentIds.any((id) => id.isNotEmpty && docId.contains(id)) ||
                          (allowedStudentNises != null && allowedStudentNises.any((nis) => nis.isNotEmpty && docId.contains(nis)));

                      if (!isRoomStudent) continue;
                    }

                    final isLeftApp = data['isLeftApp'] == true || data['status'] == 'left_app';
                    final logs = data['logs'] as List? ?? [];

                    int actualLeftCount = 0;
                    for (var l in logs) {
                      if (l is Map && (l['event'] == 'left_app' || l['status'] == 'left_app')) {
                        actualLeftCount++;
                      }
                    }
                    final leftAppCount = actualLeftCount > 0
                        ? actualLeftCount
                        : ((data['leftAppCount'] as num?)?.toInt() ?? (isLeftApp ? 1 : 0));
                    final hasLogs = logs.isNotEmpty || isLeftApp || leftAppCount > 0;

                    if (hasLogs) {
                      logsList.add({
                        'docId': doc.id,
                        'studentId': data['studentId'] ?? '',
                        'studentName': data['studentName'] ?? data['nis'] ?? 'Siswa',
                        'nis': data['nis'] ?? '',
                        'className': data['className'] ?? '',
                        'isLeftApp': isLeftApp,
                        'leftAppCount': leftAppCount > 0 ? leftAppCount : 1,
                        'status': data['status'] ?? (isLeftApp ? 'left_app' : 'in_progress'),
                        'lastLeftAppAt': data['lastLeftAppAt'],
                        'updatedAt': data['updatedAt'],
                        'logs': logs,
                      });
                    }
                  }

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
                                          ...parsedLogs.asMap().entries.map((e) {
                                            final idx = e.key + 1;
                                            final logItem = e.value;
                                            final event = logItem['event'].toString();
                                            final dt = logItem['dateTime'] as DateTime?;
                                            final isExit = event == 'left_app' || event == 'exited';

                                            final timeText = dt != null
                                                ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} WIB'
                                                : 'Waktu tidak tercatat';

                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 6),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      color: isExit ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      '$idx. ${isExit ? "Keluar Aplikasi" : "Kembali ke Aplikasi"}',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w600,
                                                        color: isExit ? const Color(0xFFDC2626) : const Color(0xFF059669),
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
                                          }),
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
}
