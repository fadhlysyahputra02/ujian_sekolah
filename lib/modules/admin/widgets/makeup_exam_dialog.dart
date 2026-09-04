import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Dialog Konsol Ujian Susulan (Makeup Exam)
class MakeupExamDialog extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const MakeupExamDialog({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<MakeupExamDialog> createState() => _MakeupExamDialogState();
}

class _MakeupExamDialogState extends State<MakeupExamDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoadingMissed = true;
  bool _isSaving = false;

  List<Map<String, dynamic>> _missedStudents = [];
  final Set<String> _selectedStudentSubjectKeys = {};
  int _tab1Filter = 0; // 0 = Semua, 1 = Tidak Mengikuti Ujian, 2 = Request Susulan
  String? _selectedSubjectFilter; // null = Semua Mapel

  DateTime? _makeupDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  final TextEditingController _roomController =
      TextEditingController(text: 'Ruang Susulan 1');

  List<Map<String, dynamic>> _teachers = [];
  List<String> _selectedProctorIds = [];
  List<String> _selectedProctorNames = [];

  List<Map<String, dynamic>> _activeMakeupSessions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  bool _isSubjectCompatibleWithStudentTrack({
    required String subjectName,
    required String studentName,
    required String className,
    required Set<String> targetClasses,
  }) {
    final sNameLower = studentName.toLowerCase();
    final cNameLower = className.toLowerCase();
    final subNameLower = subjectName.toLowerCase();
    final targetLower = targetClasses.join(' ').toLowerCase();

    final bool isIpsStudent = sNameLower.contains('ips') || cNameLower.contains('ips');
    final bool isIpaStudent = sNameLower.contains('ipa') || cNameLower.contains('ipa');

    final bool isIpaSubject = subNameLower.contains('fisika') ||
        subNameLower.contains('kimia') ||
        subNameLower.contains('biologi') ||
        targetLower.contains('ipa');

    final bool isIpsSubject = subNameLower.contains('geografi') ||
        subNameLower.contains('sosiologi') ||
        subNameLower.contains('ekonomi') ||
        targetLower.contains('ips');

    // If student is explicitly IPS and subject is IPA-only -> incompatible
    if (isIpsStudent && !isIpaStudent && isIpaSubject && !isIpsSubject) {
      return false;
    }
    // If student is explicitly IPA and subject is IPS-only -> incompatible
    if (isIpaStudent && !isIpsStudent && isIpsSubject && !isIpaSubject) {
      return false;
    }

    return true;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoadingMissed = true);
    try {
      final db = FirebaseFirestore.instance;
      final schoolRef = db.collection('schools').doc(widget.schoolId);
      final eventRef = schoolRef.collection('events').doc(widget.eventId);

      final results = await Future.wait([
        eventRef.collection('timetable').get(),
        eventRef.collection('sessions').get(),
        eventRef.collection('submissions').get(),
        eventRef.collection('attendances').get(),
        schoolRef.collection('students').get(),
        schoolRef.collection('classes').get(),
        schoolRef.collection('teachers').get(),
        eventRef
            .collection('makeup_sessions')
            .orderBy('createdAt', descending: true)
            .get(),
        eventRef.collection('makeup_approvals').get(),
      ]);

      final timetableSnap = results[0] as QuerySnapshot;
      final sessionsSnap = results[1] as QuerySnapshot;
      final submissionsSnap = results[2] as QuerySnapshot;
      final attendancesSnap = results[3] as QuerySnapshot;
      final studentsSnap = results[4] as QuerySnapshot;
      final classesSnap = results[5] as QuerySnapshot;
      final teachersSnap = results[6] as QuerySnapshot;
      final makeupSessionsSnap = results[7] as QuerySnapshot;
      final makeupApprovalsSnap = results[8] as QuerySnapshot;

      // Session name map
      final Map<String, String> sessionNameMap = {};
      for (var doc in sessionsSnap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        sessionNameMap[doc.id] = d['name']?.toString() ?? doc.id;
      }

      // Fetch allocations seats for this event to identify exact participating students & classes & subject assignments
      final Set<String> eventAllocatedStudentIds = {};
      final Set<String> eventAllocatedClassNames = {};
      final Map<String, Set<String>> studentAssignedSubjectsMap = {};

      try {
        final allocSnap = await eventRef.collection('allocations').get();
        for (var allocDoc in allocSnap.docs) {
          final seatSnap = await allocDoc.reference.collection('seats').get();
          for (var sDoc in seatSnap.docs) {
            final sData = sDoc.data();
            final stId = (sData['studentId'] ?? '').toString().trim();
            final cName = (sData['className'] ?? sData['classId'] ?? '').toString().trim();
            final subId = (sData['subjectId'] ?? sData['subjectName'] ?? sData['subject'] ?? '').toString().trim().toLowerCase();
            final subName = (sData['subjectName'] ?? '').toString().trim().toLowerCase();

            if (stId.isNotEmpty) {
              eventAllocatedStudentIds.add(stId);
              if (subId.isNotEmpty) {
                studentAssignedSubjectsMap.putIfAbsent(stId, () => {}).add(subId);
              }
              if (subName.isNotEmpty) {
                studentAssignedSubjectsMap.putIfAbsent(stId, () => {}).add(subName);
              }
            }
            if (cName.isNotEmpty) {
              eventAllocatedClassNames.add(cName);
            }
          }
        }
      } catch (e) {
        debugPrint('Allocations seats fetch note: $e');
      }

      // Class -> students mapping (map by document ID and by class Name)
      final Map<String, String> studentClassMap = {};
      final Map<String, List<String>> classStudentsMap = {};
      for (var cDoc in classesSnap.docs) {
        final cData = cDoc.data() as Map<String, dynamic>? ?? {};
        final className = (cData['name'] ?? cDoc.id).toString().trim();
        final sIds = cData['studentIds'] as List<dynamic>? ?? [];
        final ids = sIds.map((s) => s.toString()).toList();
        classStudentsMap[cDoc.id.toLowerCase().trim()] = ids;
        classStudentsMap[className.toLowerCase().trim()] = ids;
        for (final sid in ids) {
          studentClassMap[sid] = className;
        }
      }

      // Student map
      final Map<String, Map<String, dynamic>> studentMap = {};
      for (var doc in studentsSnap.docs) {
        studentMap[doc.id] = doc.data() as Map<String, dynamic>;
      }

      // Submitted keys (match ANY document in submissionsSnap)
      final Set<String> submittedKeys = {};
      for (var doc in submissionsSnap.docs) {
        final sData = doc.data() as Map<String, dynamic>;
        final docIdLower = doc.id.toLowerCase().trim();
        submittedKeys.add(docIdLower);

        final stId = (sData['studentId'] ?? '').toString().trim().toLowerCase();
        final nis = (sData['nis'] ?? '').toString().trim().toLowerCase();
        final subId = (sData['subjectId'] ?? '').toString().trim().toLowerCase();
        final subName = (sData['subjectName'] ?? '').toString().trim().toLowerCase();

        if (stId.isNotEmpty) {
          submittedKeys.add('st_$stId');
          if (subId.isNotEmpty) submittedKeys.add('${stId}_$subId');
          if (subName.isNotEmpty) submittedKeys.add('${stId}_$subName');
        }
        if (nis.isNotEmpty) {
          submittedKeys.add('nis_$nis');
          if (subId.isNotEmpty) submittedKeys.add('${nis}_$subId');
          if (subName.isNotEmpty) submittedKeys.add('${nis}_$subName');
        }
      }

      // Already approved or pending in makeup_approvals
      final Set<String> alreadyApprovedKeys = {};
      final Map<String, Map<String, dynamic>> pendingRequestsMap = {};
      for (var doc in makeupApprovalsSnap.docs) {
        final aData = doc.data() as Map<String, dynamic>;
        final stId = (aData['studentId'] ?? '').toString().trim().toLowerCase();
        final nis = (aData['nis'] ?? '').toString().trim().toLowerCase();
        final subId = (aData['subjectId'] ?? '').toString().trim().toLowerCase();
        final subName = (aData['subjectName'] ?? '').toString().trim().toLowerCase();
        final status = (aData['status'] ?? 'approved').toString().trim().toLowerCase();

        if (status == 'approved') {
          if (stId.isNotEmpty && subId.isNotEmpty) alreadyApprovedKeys.add('${stId}_$subId');
          if (stId.isNotEmpty && subName.isNotEmpty) alreadyApprovedKeys.add('${stId}_$subName');
        } else if (status == 'pending') {
          pendingRequestsMap[doc.id.toLowerCase()] = aData;
          if (stId.isNotEmpty) {
            if (subId.isNotEmpty) pendingRequestsMap['${stId}_$subId'] = aData;
            if (subName.isNotEmpty) pendingRequestsMap['${stId}_$subName'] = aData;
          }
          if (nis.isNotEmpty) {
            if (subId.isNotEmpty) pendingRequestsMap['${nis}_$subId'] = aData;
            if (subName.isNotEmpty) pendingRequestsMap['${nis}_$subName'] = aData;
          }
        }
      }

      // Attendance tracking: store attended student+session combos
      final Set<String> attendedKeys = {};
      for (var doc in attendancesSnap.docs) {
        final aData = doc.data() as Map<String, dynamic>;
        final stId = (aData['studentId'] ?? '').toString();
        final nis = (aData['nis'] ?? '').toString();
        final dayIdx = aData['dayIndex']?.toString() ?? '';
        final sessIdx = aData['sessionIndex']?.toString() ?? '';
        final isAttended = aData['isAttended'] == true || aData['attendedAt'] != null;

        if (isAttended && (stId.isNotEmpty || nis.isNotEmpty)) {
          if (stId.isNotEmpty) {
            attendedKeys.add('${dayIdx}_${sessIdx}_$stId');
            attendedKeys.add('attended_$stId');
          }
          if (nis.isNotEmpty) {
            attendedKeys.add('${dayIdx}_${sessIdx}_$nis');
            attendedKeys.add('attended_$nis');
          }
          final sessId = (aData['sessionId'] ?? '').toString();
          if (sessId.isNotEmpty) {
            if (stId.isNotEmpty) attendedKeys.add('${dayIdx}_${sessId}_$stId');
            if (nis.isNotEmpty) attendedKeys.add('${dayIdx}_${sessId}_$nis');
          }
        }
      }

      // Active makeup sessions
      final List<Map<String, dynamic>> activeSessions = [];
      for (var doc in makeupSessionsSnap.docs) {
        final mData = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
        mData['id'] = doc.id;
        activeSessions.add(mData);
      }

      // Build missed list from timetable
      final List<Map<String, dynamic>> missed = [];
      final Set<String> processedKeys = {};
      final Map<String, int> studentSessionSlotIndexMap = {};
      final now = DateTime.now();

      for (var tDoc in timetableSnap.docs) {
        final tData = tDoc.data() as Map<String, dynamic>;
        final subjectId = (tData['subjectId'] ?? tData['subjectName'] ?? '').toString();
        final subjectName = (tData['subjectName'] ?? subjectId).toString();
        final sessionId = (tData['sessionId'] ?? '').toString();
        final sessionName = sessionNameMap[sessionId] ??
            (tData['sessionName'] ?? 'Sesi').toString();
        final dayIdx = ((tData['dayIndex'] ?? 0) as num).toInt();
        final sessIdx = ((tData['sessionIndex'] ?? tData['session'] ?? 0) as num).toInt();

        // Try to determine if session has ended
        final endTimeStr = (tData['endTime'] ?? '').toString();
        bool sessionExpired = true; // default: show all missed
        if (endTimeStr.isNotEmpty) {
          final parts = endTimeStr.split(':');
          if (parts.length >= 2) {
            final rawDate = tData['eventDate'] ?? tData['date'];
            if (rawDate is Timestamp) {
              final baseDate = rawDate.toDate().add(Duration(days: dayIdx));
              final sessionEnd = DateTime(
                baseDate.year, baseDate.month, baseDate.day,
                int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
              );
              sessionExpired = sessionEnd.isBefore(now);
            }
          }
        }
        if (!sessionExpired) continue;

        // Gather target classes for this timetable item
        final Set<String> targetClasses = {};
        final rawClassIds = tData['classIds'] as List<dynamic>? ??
            tData['classNames'] as List<dynamic>? ??
            tData['classes'] as List<dynamic>?;

        if (rawClassIds != null && rawClassIds.isNotEmpty) {
          for (final c in rawClassIds) {
            targetClasses.add(c.toString().trim().toLowerCase());
          }
        }
        final singleClassName = (tData['className'] ?? tData['classId'] ?? '').toString().trim().toLowerCase();
        if (singleClassName.isNotEmpty) {
          targetClasses.add(singleClassName);
        }

        final Set<String> candidateStudentIds = {};
        if (targetClasses.isNotEmpty) {
          for (final cStr in targetClasses) {
            final ids = classStudentsMap[cStr] ?? [];
            candidateStudentIds.addAll(ids);
          }
        }

        // If timetable item did not specify classIds or failed to match targetClasses:
        if (candidateStudentIds.isEmpty) {
          if (eventAllocatedStudentIds.isNotEmpty) {
            candidateStudentIds.addAll(eventAllocatedStudentIds);
          } else if (eventAllocatedClassNames.isNotEmpty) {
            for (final cName in eventAllocatedClassNames) {
              final ids = classStudentsMap[cName.toLowerCase()] ?? [];
              candidateStudentIds.addAll(ids);
            }
          }
        }

        // Filter: Restrict candidate students
        final List<String> studentIds = candidateStudentIds.where((stId) {
          if (eventAllocatedStudentIds.isNotEmpty) {
            return eventAllocatedStudentIds.contains(stId);
          }
          return true;
        }).toList();

        for (final stId in studentIds) {
          final stData = studentMap[stId];
          if (stData == null) continue;
          final stNis = (stData['nis'] ?? '').toString().trim();
          final stName = (stData['name'] ?? stData['displayName'] ?? '').toString().trim();
          final stClass = (studentClassMap[stId] ?? stData['className'] ?? stData['classId'] ?? '').toString().trim();

          final cleanStId = stId.trim().toLowerCase();
          final cleanStNis = stNis.toLowerCase();
          final cleanStName = stName.toLowerCase();
          final cleanStClass = stClass.toLowerCase();
          final cleanSubId = subjectId.trim().toLowerCase();
          final cleanSubName = subjectName.trim().toLowerCase();

          // 0. Track/Major compatibility check: IPS student cannot take IPA subjects & vice versa
          final isCompatibleTrack = _isSubjectCompatibleWithStudentTrack(
            subjectName: subjectName,
            studentName: stName,
            className: stClass,
            targetClasses: targetClasses,
          );
          if (!isCompatibleTrack) continue; // Skip incompatible track subjects!

          // 1. Strict Subject-Class verification: If timetable specifies targetClasses, student MUST belong to targetClasses!
          if (targetClasses.isNotEmpty) {
            final belongsToTargetClass = targetClasses.contains(cleanStClass) ||
                targetClasses.any((tc) => classStudentsMap[tc] != null && classStudentsMap[tc]!.contains(stId));
            if (!belongsToTargetClass) continue; // Skip student who is not in target class for this subject!
          }

          // 2. Strict Subject Allocation verification: If seat allocations map subjects to students, verify student is assigned to this subject!
          final assignedSubs = studentAssignedSubjectsMap[stId];
          if (assignedSubs != null && assignedSubs.isNotEmpty) {
            final isAssigned = assignedSubs.contains(cleanSubId) || assignedSubs.contains(cleanSubName);
            if (!isAssigned) continue; // Skip student who is not assigned to this subject!
          }

          final submitKey = '${cleanStId}_$cleanSubId';
          if (processedKeys.contains(submitKey)) continue;

          // Comprehensive submission check across all submission docs
          bool studentHasSubmitted = submittedKeys.contains(submitKey) ||
              submittedKeys.contains('${cleanStId}_$cleanSubName') ||
              (cleanStNis.isNotEmpty &&
                  (submittedKeys.contains('${cleanStNis}_$cleanSubId') ||
                      submittedKeys.contains('${cleanStNis}_$cleanSubName'))) ||
              (cleanStName.isNotEmpty &&
                  (submittedKeys.contains('${cleanStName}_$cleanSubId') ||
                      submittedKeys.contains('${cleanStName}_$cleanSubName')));

          if (!studentHasSubmitted) {
            for (var subDoc in submissionsSnap.docs) {
              final subData = subDoc.data() as Map<String, dynamic>;
              final subDocIdLower = subDoc.id.toLowerCase().trim();
              final subStId = (subData['studentId'] ?? '').toString().trim().toLowerCase();
              final subNis = (subData['nis'] ?? '').toString().trim().toLowerCase();

              final matchesStudent = (cleanStId.isNotEmpty && subStId == cleanStId) ||
                  (cleanStNis.isNotEmpty && subNis == cleanStNis) ||
                  (cleanStId.isNotEmpty && subDocIdLower.contains(cleanStId)) ||
                  (cleanStNis.isNotEmpty && subDocIdLower.contains(cleanStNis));

              if (!matchesStudent) continue;

              final subSubId = (subData['subjectId'] ?? '').toString().trim().toLowerCase();
              final subSubName = (subData['subjectName'] ?? '').toString().trim().toLowerCase();

              final matchesSubject = (cleanSubId.isNotEmpty && (subSubId == cleanSubId || subSubName == cleanSubId || subDocIdLower.contains(cleanSubId))) ||
                  (cleanSubName.isNotEmpty && (subSubId == cleanSubName || subSubName == cleanSubName || subDocIdLower.contains(cleanSubName)));

              if (matchesSubject) {
                studentHasSubmitted = true;
                break;
              }
            }
          }

          if (studentHasSubmitted) continue; // Skip students who completed/submitted the exam!
          if (alreadyApprovedKeys.contains(submitKey) || alreadyApprovedKeys.contains('${cleanStId}_$cleanSubName')) continue;

          // Check attendance status
          final attended = attendedKeys.contains('${dayIdx}_${sessIdx}_$stId') ||
              attendedKeys.contains('${dayIdx}_${sessIdx}_$stNis') ||
              attendedKeys.contains('${dayIdx}_${sessionId}_$stId') ||
              attendedKeys.contains('${dayIdx}_${sessionId}_$stNis') ||
              attendedKeys.contains('attended_$stId') ||
              attendedKeys.contains('attended_$stNis');

          Map<String, dynamic>? pendingDoc = pendingRequestsMap['${cleanStId}_$cleanSubId'] ??
              pendingRequestsMap['${cleanStId}_$cleanSubName'] ??
              (cleanStNis.isNotEmpty
                  ? (pendingRequestsMap['${cleanStNis}_$cleanSubId'] ??
                      pendingRequestsMap['${cleanStNis}_$cleanSubName'])
                  : null);

          final hasPendingRequest = pendingDoc != null;
          final pendingReason = pendingDoc?['reason']?.toString();

          // Skip students who attended the regular session OR completed the exam UNLESS they filed a pending makeup request for THIS subject!
          if ((attended || studentHasSubmitted) && !hasPendingRequest) continue;

          final statusLabel = hasPendingRequest ? 'Request Susulan' : 'Tidak Hadir';

          // Enforce 1 regular subject per student per session slot
          final slotKey = '${cleanStId}_${dayIdx}_${sessionId.isNotEmpty ? sessionId : sessIdx}';
          if (studentSessionSlotIndexMap.containsKey(slotKey)) {
            final existingIndex = studentSessionSlotIndexMap[slotKey]!;
            final existingItem = missed[existingIndex];

            // If current item has a pending request while existing does not, replace it
            if (hasPendingRequest && !(existingItem['hasPendingRequest'] == true)) {
              missed[existingIndex] = {
                'key': submitKey,
                'studentId': stId,
                'studentName': stName,
                'nis': stNis,
                'className': stClass.isNotEmpty ? stClass : 'Umum',
                'subjectId': subjectId,
                'subjectName': subjectName,
                'sessionName': sessionName,
                'sessionId': sessionId,
                'dayIndex': dayIdx,
                'statusLabel': statusLabel,
                'attended': attended,
                'hasPendingRequest': hasPendingRequest,
                'pendingReason': pendingReason,
              };
            }
            continue; // Skip duplicate subject for the same student in the same session
          }

          studentSessionSlotIndexMap[slotKey] = missed.length;
          processedKeys.add(submitKey);

          missed.add({
            'key': submitKey,
            'studentId': stId,
            'studentName': stName,
            'nis': stNis,
            'className': stClass.isNotEmpty ? stClass : 'Umum',
            'subjectId': subjectId,
            'subjectName': subjectName,
            'sessionName': sessionName,
            'sessionId': sessionId,
            'dayIndex': dayIdx,
            'statusLabel': statusLabel,
            'attended': attended,
            'hasPendingRequest': hasPendingRequest,
            'pendingReason': pendingReason,
          });
        }
      }

      // Guarantee ALL pending makeup requests from makeup_approvals are included in missed list!
      for (var appDoc in makeupApprovalsSnap.docs) {
        final aData = appDoc.data() as Map<String, dynamic>;
        final status = (aData['status'] ?? 'pending').toString().trim().toLowerCase();
        if (status != 'pending') continue;

        final stId = (aData['studentId'] ?? '').toString().trim();
        final subId = (aData['subjectId'] ?? '').toString().trim();
        final subName = (aData['subjectName'] ?? 'Ujian').toString().trim();

        final alreadyAdded = missed.any((m) =>
            m['studentId'].toString().toLowerCase() == stId.toLowerCase() &&
            (m['subjectId'].toString().toLowerCase() == subId.toLowerCase() ||
                m['subjectName'].toString().toLowerCase() == subName.toLowerCase()));

        if (!alreadyAdded && stId.isNotEmpty) {
          final stData = studentMap[stId];
          final studentName = (aData['studentName'] ?? stData?['name'] ?? stData?['displayName'] ?? stId).toString().trim();
          final className = (aData['className'] ?? studentClassMap[stId] ?? stData?['className'] ?? '').toString().trim();
          final nis = (aData['nis'] ?? stData?['nis'] ?? '').toString().trim();

          missed.add({
            'key': '${stId}_${subId.isNotEmpty ? subId : subName}',
            'studentId': stId,
            'studentName': studentName,
            'nis': nis,
            'className': className.isNotEmpty ? className : 'Umum',
            'subjectId': subId,
            'subjectName': subName,
            'sessionName': (aData['sessionName'] ?? 'Sesi 1').toString(),
            'sessionId': '',
            'dayIndex': 0,
            'statusLabel': 'Request Susulan',
            'attended': false,
            'hasPendingRequest': true,
            'pendingReason': aData['reason']?.toString() ?? 'Minta Susulan',
          });
        }
      }

      // Teachers: combine schoolRef.collection('teachers') and schoolRef.collection('users') (role == teacher)
      final Map<String, Map<String, dynamic>> teacherMap = {};
      for (var t in teachersSnap.docs) {
        final d = (t.data() as Map<String, dynamic>?) ?? {};
        final displayName = (d['displayName'] ?? d['name'] ?? d['fullName'] ?? d['username'] ?? t.id).toString().trim();
        teacherMap[t.id] = {
          'id': t.id,
          'name': displayName.isNotEmpty ? displayName : t.id,
          'displayName': displayName.isNotEmpty ? displayName : t.id,
        };
      }

      try {
        final usersTeacherSnap = await schoolRef
            .collection('users')
            .where('role', isEqualTo: 'teacher')
            .get();
        for (var t in usersTeacherSnap.docs) {
          final d = (t.data() as Map<String, dynamic>?) ?? {};
          final displayName = (d['displayName'] ?? d['name'] ?? d['fullName'] ?? d['username'] ?? t.id).toString().trim();
          teacherMap.putIfAbsent(t.id, () => {
            'id': t.id,
            'name': displayName.isNotEmpty ? displayName : t.id,
            'displayName': displayName.isNotEmpty ? displayName : t.id,
          });
        }
      } catch (e) {
        debugPrint('Fetch teacher users note: $e');
      }

      final List<Map<String, dynamic>> teachers = teacherMap.values.toList();
      teachers.sort((a, b) => (a['displayName'] as String).compareTo(b['displayName'] as String));

      if (mounted) {
        setState(() {
          _missedStudents = missed;
          _teachers = teachers;
          _activeMakeupSessions = activeSessions;
          _isLoadingMissed = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading makeup data: $e');
      if (mounted) setState(() => _isLoadingMissed = false);
    }
  }

  Map<String, List<String>> _findConflictingStudents() {
    final Map<String, Set<String>> studentSubjectsMap = {};
    final Map<String, String> studentNameMap = {};

    for (final key in _selectedStudentSubjectKeys) {
      final s = _missedStudents.firstWhere(
        (m) => m['key'] == key,
        orElse: () => {},
      );
      if (s.isEmpty) continue;
      final sId = (s['studentId'] ?? s['nis'] ?? s['studentName']).toString();
      final sName = (s['studentName'] ?? 'Siswa').toString();
      final subName = (s['subjectName'] ?? 'Mata Pelajaran').toString();

      studentNameMap[sId] = sName;
      studentSubjectsMap.putIfAbsent(sId, () => {}).add(subName);
    }

    final Map<String, List<String>> conflicts = {};
    studentSubjectsMap.forEach((sId, subjects) {
      if (subjects.length > 1) {
        conflicts[studentNameMap[sId] ?? sId] = subjects.toList();
      }
    });
    return conflicts;
  }

  void _showConflictWarningDialog(Map<String, List<String>> conflicts) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bentrok Sesi Ujian!',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Terdeteksi siswa yang dipilih untuk lebih dari 1 mata pelajaran sekaligus dalam 1 sesi:',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Scrollbar(
                  child: ListView(
                    shrinkWrap: true,
                    children: conflicts.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${e.key}: ${e.value.join(', ')}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF991B1B),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Aturan Keamanan Ujian Susulan:\nUntuk mencegah bentrok jam di HP siswa, silakan atur sesi susulan secara terpisah per mata pelajaran (misal: buat Sesi 1 untuk Agama terlebih dahulu, lalu Sesi 2 untuk Sastra).',
                style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B), height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Ubah Pilihan (Pisah Sesi)', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  bool _isTimeOverlapping(String start1, String end1, String start2, String end2) {
    int parseMin(String t) {
      final p = t.split(':');
      if (p.length < 2) return 0;
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    }

    final s1 = parseMin(start1);
    final e1 = parseMin(end1);
    final s2 = parseMin(start2);
    final e2 = parseMin(end2);

    return s1 < e2 && s2 < e1;
  }

  Future<void> _saveMakeupSession() async {
    if (_makeupDate == null) {
      _showSnack('Tanggal ujian susulan wajib diisi.', isError: true);
      return;
    }
    if (_selectedStudentSubjectKeys.isEmpty) {
      _showSnack('Pilih minimal 1 siswa untuk dijadwalkan.', isError: true);
      return;
    }
    if (_roomController.text.trim().isEmpty) {
      _showSnack('Nama ruangan wajib diisi.', isError: true);
      return;
    }

    // Validation 1: Simultaneous Multi-Subject Conflict Check
    final conflicts = _findConflictingStudents();
    if (conflicts.isNotEmpty) {
      _showConflictWarningDialog(conflicts);
      return;
    }

    final String makeupDateStr = DateFormat('yyyy-MM-dd').format(_makeupDate!);
    final String startStr =
        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final String endStr =
        '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

    // Validation 2: Time Overlap against active makeup sessions for any student in selection
    final Map<String, List<String>> timeOverlaps = {};

    for (final key in _selectedStudentSubjectKeys) {
      final student = _missedStudents.firstWhere(
        (m) => m['key'] == key,
        orElse: () => {},
      );
      if (student.isEmpty) continue;
      final stId = (student['studentId'] ?? '').toString().trim();
      final stName = (student['studentName'] ?? 'Siswa').toString();

      for (final sess in _activeMakeupSessions) {
        final sessDate = (sess['date'] ?? '').toString();
        if (sessDate != makeupDateStr) continue;

        final sessStart = (sess['startTime'] ?? '').toString();
        final sessEnd = (sess['endTime'] ?? '').toString();

        if (_isTimeOverlapping(startStr, endStr, sessStart, sessEnd)) {
          final approvedList = sess['approvedStudents'] as List<dynamic>? ?? [];
          for (final appSt in approvedList) {
            final appStId = (appSt['studentId'] ?? '').toString().trim();
            if (appStId.isNotEmpty && appStId == stId) {
              final appSubName = (appSt['subjectName'] ?? 'Mapel Lain').toString();
              timeOverlaps.putIfAbsent(stName, () => []).add('$appSubName ($sessStart - $sessEnd WIB)');
            }
          }
        }
      }
    }

    if (timeOverlaps.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bentrok Jam Sesi Susulan!',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: const Color(0xFF991B1B),
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Siswa berikut sudah terdaftar pada sesi susulan aktif lain dengan jam yang bentrok:',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: timeOverlaps.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${e.key} → Sesi Terdaftar: ${e.value.join(', ')}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF991B1B),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Solusi: Harap atur jam mulai / jam selesai atau tanggal ujian yang berbeda untuk sesi ini.',
                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Ubah Jam Sesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = FirebaseFirestore.instance;
      final eventRef = db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId);

      final String makeupDateStr = DateFormat('yyyy-MM-dd').format(_makeupDate!);
      final String startStr =
          '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
      final String endStr =
          '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

      final List<Map<String, dynamic>> approvedStudents = [];

      for (final key in _selectedStudentSubjectKeys) {
        final student = _missedStudents.firstWhere(
          (m) => m['key'] == key,
          orElse: () => {},
        );
        if (student.isEmpty) continue;

        approvedStudents.add({
          'studentId': student['studentId'],
          'studentName': student['studentName'],
          'nis': student['nis'],
          'className': student['className'],
          'subjectId': student['subjectId'],
          'subjectName': student['subjectName'],
          'sessionName': student['sessionName'],
        });

        final approvalDocId =
            '${student['studentId']}_${student['subjectId']}';
        await eventRef
            .collection('makeup_approvals')
            .doc(approvalDocId)
            .set({
          'studentId': student['studentId'],
          'studentName': student['studentName'],
          'nis': student['nis'],
          'className': student['className'],
          'subjectId': student['subjectId'],
          'subjectName': student['subjectName'],
          'sessionName': student['sessionName'],
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'makeupRoom': _roomController.text.trim(),
          'makeupDate': makeupDateStr,
          'makeupStartTime': startStr,
          'makeupEndTime': endStr,
          'proctorIds': _selectedProctorIds,
          'proctorNames': _selectedProctorNames,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await eventRef
          .collection('makeup_sessions')
          .doc('makeup_${DateTime.now().millisecondsSinceEpoch}')
          .set({
        'roomName': _roomController.text.trim(),
        'date': makeupDateStr,
        'startTime': startStr,
        'endTime': endStr,
        'proctorIds': _selectedProctorIds,
        'proctorNames': _selectedProctorNames,
        'approvedStudents': approvedStudents,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _isSaving = false;
          _selectedStudentSubjectKeys.clear();
          _makeupDate = null;
        });
        _showSnack('Jadwal Ujian Susulan berhasil disimpan!');
        await _loadData();
        _tabController.animateTo(2);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('Gagal menyimpan: $e', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor:
          isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dw = min(size.width * 0.96, 860.0);
    final dh = min(size.height * 0.90, 700.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: SizedBox(
        width: dw,
        height: dh,
        child: Column(
          children: [
            // Header gradient
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_edu_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Konsol Ujian Susulan',
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            Text(widget.eventName,
                                style: GoogleFonts.inter(
                                    color: Colors.white70, fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    indicatorWeight: 3,
                    labelStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 12),
                    unselectedLabelStyle:
                        GoogleFonts.inter(fontSize: 12),
                    tabs: [
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.group_off_rounded, size: 15),
                          const SizedBox(width: 5),
                          const Text('Siswa Absen'),
                          if (_missedStudents.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            _countBadge(_missedStudents.length,
                                const Color(0xFFEF4444)),
                          ],
                        ]),
                      ),
                      const Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.schedule_rounded, size: 15),
                          SizedBox(width: 5),
                          Text('Atur Sesi'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.sensors_rounded, size: 15),
                          const SizedBox(width: 5),
                          const Text('Sesi Aktif'),
                          if (_activeMakeupSessions.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            _countBadge(_activeMakeupSessions.length,
                                const Color(0xFF10B981)),
                          ],
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTab1(),
                  _buildTab2(),
                  _buildTab3(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countBadge(int count, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$count',
            style: const TextStyle(fontSize: 10, color: Colors.white)),
      );

  // ── TAB 1: SISWA ABSEN ──────────────────────────────────────────

  Widget _buildTab1() {
    if (_isLoadingMissed) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: Color(0xFF7C3AED)),
          SizedBox(height: 12),
          Text('Menganalisis data kehadiran & pengerjaan...'),
        ]),
      );
    }
    if (_missedStudents.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 72, color: Colors.green[300]),
          const SizedBox(height: 16),
          Text('Semua siswa sudah mengerjakan ujian! 🎉',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF0F172A))),
          const SizedBox(height: 8),
          Text('Tidak ada siswa yang perlu ujian susulan.',
              style: GoogleFonts.inter(
                  color: const Color(0xFF64748B), fontSize: 13)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Muat Ulang'),
          ),
        ]),
      );
    }

    final noShowCount = _missedStudents.where((s) => s['hasPendingRequest'] != true).length;
    final requestCount = _missedStudents.where((s) => s['hasPendingRequest'] == true).length;

    final Set<String> availableSubjectNames = {};
    for (final s in _missedStudents) {
      final sub = (s['subjectName'] ?? '').toString().trim();
      if (sub.isNotEmpty) availableSubjectNames.add(sub);
    }

    final filteredStudents = _missedStudents.where((s) {
      if (_tab1Filter == 1 && s['hasPendingRequest'] == true) return false;
      if (_tab1Filter == 2 && s['hasPendingRequest'] != true) return false;
      if (_selectedSubjectFilter != null && (s['subjectName'] ?? '').toString().trim() != _selectedSubjectFilter) return false;
      return true;
    }).toList();

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in filteredStudents) {
      grouped.putIfAbsent(s['className'] as String, () => []).add(s);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Filter Chips Header
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            _buildTab1FilterChip(0, 'Semua (${_missedStudents.length})', Icons.format_list_bulleted_rounded),
            _buildTab1FilterChip(1, 'Tidak Mengikuti ($noShowCount)', Icons.person_off_rounded),
            _buildTab1FilterChip(2, 'Request Susulan ($requestCount)', Icons.mark_email_unread_rounded),
          ],
        ),
      ),
      if (availableSubjectNames.length > 1)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.filter_list_rounded, size: 16, color: Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              Text('Filter Mapel: ',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF7C3AED))),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedSubjectFilter,
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Semua Mata Pelajaran'),
                      ),
                      ...availableSubjectNames.map((sub) => DropdownMenuItem<String?>(
                        value: sub,
                        child: Text(sub),
                      )),
                    ],
                    onChanged: (val) => setState(() => _selectedSubjectFilter = val),
                  ),
                ),
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${filteredStudents.length} siswa ditampilkan',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: const Color(0xFF0F172A))),
              Text('Centang siswa yang dijadwalkan ujian susulan',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFF64748B))),
            ]),
          ),
          TextButton(
            onPressed: () => setState(() {
              for (final s in filteredStudents) {
                _selectedStudentSubjectKeys.add(s['key'] as String);
              }
            }),
            child: Text('Pilih Semua',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF7C3AED))),
          ),
          TextButton(
            onPressed: () =>
                setState(() => _selectedStudentSubjectKeys.clear()),
            child: Text('Batal',
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF64748B))),
          ),
        ]),
      ),
      if (_selectedStudentSubjectKeys.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEDE9FE),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF7C3AED), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '${_selectedStudentSubjectKeys.length} siswa dipilih',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF5B21B6))),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final conflicts = _findConflictingStudents();
                if (conflicts.isNotEmpty) {
                  _showConflictWarningDialog(conflicts);
                  return;
                }
                _tabController.animateTo(1);
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
              label: Text('Atur Jadwal',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF7C3AED),
          child: filteredStudents.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text('Tidak ada siswa di kategori ini.',
                        style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: grouped.entries.map((entry) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(entry.key,
                                  style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            Text('${entry.value.length} siswa',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B))),
                          ]),
                        ),
                        ...entry.value.map(_buildStudentTile),
                        const SizedBox(height: 8),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ),
    ]);
  }

  Widget _buildTab1FilterChip(int filterVal, String label, IconData icon) {
    final isSel = _tab1Filter == filterVal;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab1Filter = filterVal),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSel
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: isSel ? const Color(0xFF7C3AED) : const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                    color: isSel ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentTile(Map<String, dynamic> s) {
    final key = s['key'] as String;
    final isSelected = _selectedStudentSubjectKeys.contains(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEDE9FE) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF7C3AED)
              : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => isSelected
            ? _selectedStudentSubjectKeys.remove(key)
            : _selectedStudentSubjectKeys.add(key)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Checkbox(
              value: isSelected,
              onChanged: (v) => setState(() =>
                  v == true
                      ? _selectedStudentSubjectKeys.add(key)
                      : _selectedStudentSubjectKeys.remove(key)),
              activeColor: const Color(0xFF7C3AED),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['studentName'] as String? ?? '-',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: const Color(0xFF0F172A))),
                const SizedBox(height: 2),
                Text('${s['subjectName']}  •  ${s['sessionName']}',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: const Color(0xFF64748B))),
                if (s['hasPendingRequest'] == true) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFC4B5FD)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.mark_email_unread_rounded, size: 10, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Pengajuan Siswa: "${s['pendingReason'] ?? 'Minta Susulan'}"',
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF5B21B6),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            ),
            Builder(builder: (context) {
              final hasReq = s['hasPendingRequest'] == true;
              final color = hasReq ? const Color(0xFF7C3AED) : const Color(0xFFDC2626);
              final bg = hasReq ? const Color(0xFFEDE9FE) : const Color(0xFFFEE2E2);
              final icon = hasReq ? Icons.mark_email_unread_rounded : Icons.person_off_rounded;
              final label = s['statusLabel'] as String? ?? (hasReq ? 'Request Susulan' : 'Tidak Hadir');

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    icon,
                    size: 12,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Text(label,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      )),
                ]),
              );
            }),
          ]),
        ),
      ),
    );
  }

  // ── TAB 2: ATUR SESI ────────────────────────────────────────────

  Widget _buildTab2() {
    final dateFmt = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Selected students info banner
        if (_selectedStudentSubjectKeys.isNotEmpty)
          _infoBanner(
            color: const Color(0xFFEDE9FE),
            borderColor: const Color(0xFF7C3AED),
            icon: Icons.people_rounded,
            iconColor: const Color(0xFF7C3AED),
            text:
                '${_selectedStudentSubjectKeys.length} siswa siap dijadwalkan',
            textColor: const Color(0xFF5B21B6),
            actionText: 'Ubah Pilihan',
            actionColor: const Color(0xFF7C3AED),
            onAction: () => _tabController.animateTo(0),
          )
        else
          _infoBanner(
            color: const Color(0xFFFEF3C7),
            borderColor: const Color(0xFFFCD34D),
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xFFD97706),
            text: 'Belum ada siswa dipilih. Kembali ke tab pertama.',
            textColor: const Color(0xFF92400E),
            actionText: 'Pilih Siswa',
            actionColor: const Color(0xFFD97706),
            onAction: () => _tabController.animateTo(0),
          ),
        const SizedBox(height: 16),

        _sectionLabel('1. Tanggal & Waktu', Icons.calendar_today_rounded),
        const SizedBox(height: 10),

        // Date picker tile
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 90)),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(
                        primary: Color(0xFF7C3AED))),
                child: child!,
              ),
            );
            if (picked != null) setState(() => _makeupDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _makeupDate != null
                  ? const Color(0xFFEDE9FE)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _makeupDate != null
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(children: [
              Icon(Icons.calendar_month_rounded,
                  color: _makeupDate != null
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF94A3B8)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _makeupDate != null
                      ? dateFmt.format(_makeupDate!)
                      : 'Pilih tanggal ujian susulan...',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight:
                        _makeupDate != null ? FontWeight.w600 : FontWeight.normal,
                    color: _makeupDate != null
                        ? const Color(0xFF5B21B6)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8)),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(child: _timeTile('Mulai', _startTime, () async {
            final p = await showTimePicker(
                context: context, initialTime: _startTime);
            if (p != null) setState(() => _startTime = p);
          })),
          const SizedBox(width: 12),
          Expanded(child: _timeTile('Selesai', _endTime, () async {
            final p = await showTimePicker(
                context: context, initialTime: _endTime);
            if (p != null) setState(() => _endTime = p);
          })),
        ]),

        const SizedBox(height: 20),
        _sectionLabel('2. Ruangan & Pengawas', Icons.meeting_room_rounded),
        const SizedBox(height: 10),

        TextField(
          controller: _roomController,
          decoration: InputDecoration(
            labelText: 'Nama Ruangan Susulan',
            hintText: 'misal: Lab Komputer 1, Ruang Susulan A',
            prefixIcon: const Icon(Icons.meeting_room_outlined,
                color: Color(0xFF7C3AED)),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF7C3AED), width: 1.5)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
          ),
        ),
        const SizedBox(height: 10),

        InkWell(
          onTap: _showProctorPicker,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(children: [
              const Icon(Icons.supervisor_account_rounded,
                  color: Color(0xFF7C3AED)),
              const SizedBox(width: 12),
              Expanded(
                child: _selectedProctorNames.isEmpty
                    ? Text('Pilih guru pengawas susulan...',
                        style: GoogleFonts.inter(
                            color: const Color(0xFF94A3B8), fontSize: 14))
                    : Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: List.generate(_selectedProctorNames.length, (idx) {
                          final name = _selectedProctorNames[idx];
                          return Container(
                            padding: const EdgeInsets.only(left: 10, right: 6, top: 4, bottom: 4),
                            decoration: BoxDecoration(
                                color: const Color(0xFFEDE9FE),
                                borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name,
                                    style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: const Color(0xFF5B21B6),
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedProctorNames.removeAt(idx);
                                      if (idx < _selectedProctorIds.length) {
                                        _selectedProctorIds.removeAt(idx);
                                      }
                                    });
                                  },
                                  child: const Icon(Icons.close_rounded,
                                      size: 14, color: Color(0xFF7C3AED)),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8)),
            ]),
          ),
        ),

        const SizedBox(height: 20),
        _sectionLabel('3. Siswa yang Dijadwalkan', Icons.checklist_rounded),
        const SizedBox(height: 8),
        if (_selectedStudentSubjectKeys.isEmpty)
          Text('Belum ada siswa dipilih.',
              style: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8), fontSize: 12))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedStudentSubjectKeys.map((key) {
              final s = _missedStudents.firstWhere(
                  (m) => m['key'] == key,
                  orElse: () => {});
              if (s.isEmpty) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Text(
                  '${s['studentName']} – ${s['subjectName']}',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF334155),
                      fontWeight: FontWeight.w500),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveMakeupSession,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.rocket_launch_rounded, size: 18),
            label: Text(
              _isSaving
                  ? 'Menyimpan jadwal...'
                  : 'Simpan & Aktifkan Jadwal Susulan',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _infoBanner({
    required Color color,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required String text,
    required Color textColor,
    required String actionText,
    required Color actionColor,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold, color: textColor, fontSize: 12)),
        ),
        TextButton(
          onPressed: onAction,
          child: Text(actionText,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: actionColor)),
        ),
      ]),
    );
  }

  Widget _sectionLabel(String text, IconData icon) => Row(children: [
        Icon(icon, color: const Color(0xFF7C3AED), size: 18),
        const SizedBox(width: 8),
        Text(text,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: const Color(0xFF0F172A))),
      ]);

  Widget _timeTile(String label, TimeOfDay time, VoidCallback onTap) {
    final fmt =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(children: [
          const Icon(Icons.access_time_rounded,
              color: Color(0xFF7C3AED), size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 10, color: const Color(0xFF64748B))),
            Text(fmt,
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A))),
          ]),
        ]),
      ),
    );
  }

  Future<void> _showProctorPicker() async {
    final tempSelected = Set<String>.from(_selectedProctorIds);
    final result = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stContext, setLS) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('Pilih Pengawas Susulan',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 350,
                height: 380,
                child: _teachers.isEmpty
                    ? const Center(child: Text('Belum ada data guru.'))
                    : Scrollbar(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _teachers.length,
                          itemBuilder: (_, i) {
                            final t = _teachers[i];
                            final tid = t['id']?.toString() ?? '';
                            final tname = (t['name'] ?? t['displayName'] ?? tid).toString().trim();
                            final displayTitle = tname.isNotEmpty ? tname : tid;
                            final isChecked = tempSelected.contains(tid);
                            return CheckboxListTile(
                              value: isChecked,
                              onChanged: (v) {
                                setLS(() {
                                  if (v == true) {
                                    tempSelected.add(tid);
                                  } else {
                                    tempSelected.remove(tid);
                                  }
                                });
                              },
                              title: Text(displayTitle,
                                  style: GoogleFonts.inter(fontSize: 13)),
                              activeColor: const Color(0xFF7C3AED),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: Text('Batal',
                      style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(tempSelected);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Konfirmasi',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      final List<String> names = [];
      final List<String> ids = [];
      for (final tid in result) {
        if (tid.trim().isEmpty) continue;
        ids.add(tid);
        final t = _teachers.firstWhere(
          (elem) => elem['id']?.toString() == tid,
          orElse: () => {'name': tid},
        );
        final nameStr = (t['name'] ?? t['displayName'] ?? tid).toString().trim();
        names.add(nameStr.isNotEmpty ? nameStr : tid);
      }

      setState(() {
        _selectedProctorIds = ids;
        _selectedProctorNames = names;
      });
    }
  }

  // ── TAB 3: SESI AKTIF ───────────────────────────────────────────

  Widget _buildTab3() {
    if (_isLoadingMissed) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)));
    }
    if (_activeMakeupSessions.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_today_outlined,
              size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Belum ada sesi susulan dijadwalkan.',
              style: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8), fontSize: 14)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _tabController.animateTo(0),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Buat Sesi Susulan'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _activeMakeupSessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final sess = _activeMakeupSessions[i];
        final room = sess['roomName'] ?? '-';
        final date = sess['date'] ?? '-';
        final startT = sess['startTime'] ?? '-';
        final endT = sess['endTime'] ?? '-';
        final proctors = (sess['proctorNames'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .join(', ');
        final students =
            (sess['approvedStudents'] as List<dynamic>? ?? []);
        final sessStatus = sess['status'] ?? 'active';
        final sessId = sess['id'] as String? ?? '';

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Session header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Row(children: [
                const Icon(Icons.meeting_room_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(room,
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text('$date  •  $startT – $endT WIB',
                            style: GoogleFonts.inter(
                                color: Colors.white70, fontSize: 11)),
                      ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sessStatus == 'active'
                        ? const Color(0xFF10B981)
                        : const Color(0xFF94A3B8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sessStatus == 'active' ? 'Aktif' : 'Selesai',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (proctors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          const Icon(Icons.supervisor_account_rounded,
                              size: 14, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Pengawas: $proctors',
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF334155))),
                          ),
                        ]),
                      ),
                    Text('${students.length} Siswa Dijadwalkan:',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: const Color(0xFF0F172A))),
                    const SizedBox(height: 6),
                    ...students.take(5).map((stRaw) {
                      final st = stRaw as Map<String, dynamic>? ?? {};
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          const Icon(Icons.circle,
                              size: 5, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${st['studentName'] ?? '-'} (${st['className'] ?? '-'})  –  ${st['subjectName'] ?? '-'}',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF475569)),
                            ),
                          ),
                        ]),
                      );
                    }),
                    if (students.length > 5)
                      Text('+ ${students.length - 5} siswa lainnya',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF94A3B8),
                              fontStyle: FontStyle.italic)),

                    if (sessStatus == 'active' && sessId.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 10),
                      _buildRealtimeMini(sessId, students),
                    ],
                  ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildRealtimeMini(
      String sessId, List<dynamic> students) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('realtime_control')
          .snapshots(),
      builder: (context, rtSnap) {
        final Map<String, Map<String, dynamic>> rtMap = {};
        if (rtSnap.hasData) {
          for (var doc in rtSnap.data!.docs) {
            rtMap[doc.id] = doc.data() as Map<String, dynamic>;
            final stId =
                ((doc.data() as Map)['studentId'] ?? '').toString();
            if (stId.isNotEmpty) rtMap[stId] = doc.data() as Map<String, dynamic>;
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.sensors_rounded,
                color: Color(0xFF10B981), size: 14),
            const SizedBox(width: 6),
            Text('Status Pengerjaan Realtime',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: const Color(0xFF0F172A))),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: students.map((stRaw) {
              final st = stRaw as Map<String, dynamic>? ?? {};
              final stId = (st['studentId'] ?? '').toString();
              final stName = (st['studentName'] ?? '-').toString();
              final subName = (st['subjectName'] ?? '-').toString();
              final rtDoc = rtMap[stId];
              final isCompleted = rtDoc?['isCompleted'] == true;
              final isLeftApp = rtDoc?['isLeftApp'] == true;
              final isWorking = rtDoc?['isWorking'] == true;

              Color statusColor;
              IconData statusIcon;
              String statusText;
              if (isCompleted) {
                statusColor = const Color(0xFF10B981);
                statusIcon = Icons.check_circle_rounded;
                statusText = 'Selesai';
              } else if (isLeftApp) {
                statusColor = const Color(0xFFEF4444);
                statusIcon = Icons.warning_rounded;
                statusText = 'Keluar App';
              } else if (isWorking) {
                statusColor = const Color(0xFF3B82F6);
                statusIcon = Icons.pending_rounded;
                statusText = 'Mengerjakan';
              } else if (rtDoc != null) {
                statusColor = const Color(0xFFF59E0B);
                statusIcon = Icons.hourglass_empty_rounded;
                statusText = 'Hadir';
              } else {
                statusColor = const Color(0xFF94A3B8);
                statusIcon = Icons.person_off_outlined;
                statusText = 'Belum Hadir';
              }

              return Container(
                constraints: const BoxConstraints(minWidth: 110),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(statusIcon, color: statusColor, size: 12),
                        const SizedBox(width: 4),
                        Text(statusText,
                            style: GoogleFonts.inter(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 2),
                      Text(stName,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis),
                      Text(subName,
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              color: const Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis),
                    ]),
              );
            }).toList(),
          ),
        ]);
      },
    );
  }
}
