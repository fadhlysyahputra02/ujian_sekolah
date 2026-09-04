import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sys_exam_school/core/services/auth_service.dart';
import 'package:sys_exam_school/core/utils/natural_sort.dart';
import 'package:sys_exam_school/modules/teacher/controllers/teacher_proctor_controller.dart';
import 'package:sys_exam_school/modules/teacher/widgets/proctor_class_legend_bar.dart';
import 'package:sys_exam_school/modules/teacher/widgets/proctor_header_banner.dart';
import 'package:sys_exam_school/modules/teacher/widgets/proctor_kpi_cards.dart';
import 'package:sys_exam_school/modules/teacher/widgets/proctor_search_filter_bar.dart';
import 'package:sys_exam_school/modules/teacher/widgets/proctor_seat_card.dart';

class TeacherProctorRoomPage extends StatefulWidget {
  final String eventId;
  final String roomId;
  final int dayIndex;
  final int sessionIndex;
  final String docId;

  const TeacherProctorRoomPage({
    super.key,
    required this.eventId,
    required this.roomId,
    this.dayIndex = 0,
    this.sessionIndex = 0,
    this.docId = '',
  });

  @override
  State<TeacherProctorRoomPage> createState() => _TeacherProctorRoomPageState();
}

class _TeacherProctorRoomPageState extends State<TeacherProctorRoomPage> {
  String? _resolvedSchoolId;
  bool _isResolvingSchool = true;
  String _searchQuery = '';
  String _selectedClassFilter = 'Semua Kelas';
  List<Map<String, dynamic>> _timetableSubcollection = [];
  List<Map<String, dynamic>> _sessionsSubcollection = [];
  final Map<String, bool> _localAttendedMap = {};
  final ValueNotifier<int> _seatNotifier = ValueNotifier<int>(0);

  Stream<DocumentSnapshot>? _eventStream;
  Stream<QuerySnapshot>? _roomsStream;
  Stream<QuerySnapshot>? _attendancesStream;
  Stream<QuerySnapshot>? _realtimeStream;
  Stream<QuerySnapshot>? _submissionsStream;
  Stream<QuerySnapshot>? _allocationsStream;
  Stream<QuerySnapshot>? _classesStream;
  Stream<QuerySnapshot>? _studentsStream;
  Stream<QuerySnapshot>? _makeupSessionsStream;

  Stream<QuerySnapshot>? _seatsStream;
  String? _seatsAllocDocId;

  @override
  void initState() {
    super.initState();
    _initSchoolId();
  }

  void _initStreams(String sid) {
    if (sid.isEmpty) return;
    final eventRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(sid)
        .collection('events')
        .doc(widget.eventId);

    _eventStream = eventRef.snapshots();
    _roomsStream = eventRef.collection('rooms').snapshots();
    _attendancesStream = eventRef.collection('attendances').snapshots();
    _realtimeStream = eventRef.collection('realtime_control').snapshots();
    _submissionsStream = eventRef.collection('submissions').snapshots();
    _allocationsStream = eventRef.collection('allocations').snapshots();
    _classesStream = FirebaseFirestore.instance.collection('schools').doc(sid).collection('classes').snapshots();
    _studentsStream = FirebaseFirestore.instance.collection('schools').doc(sid).collection('students').snapshots();
    _makeupSessionsStream = eventRef.collection('makeup_sessions').snapshots();
  }

  Future<void> _initSchoolId() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    String? foundSchoolId = authService.schoolId;

    if (foundSchoolId == null || foundSchoolId.isEmpty) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        if (authService.schoolId != null && authService.schoolId!.isNotEmpty) {
          foundSchoolId = authService.schoolId;
          break;
        }
      }
    }

    if (foundSchoolId == null || foundSchoolId.isEmpty) {
      try {
        final evGroup = await FirebaseFirestore.instance
            .collectionGroup('events')
            .where(FieldPath.documentId, isEqualTo: widget.eventId)
            .limit(1)
            .get();

        if (evGroup.docs.isNotEmpty) {
          final parentSchool = evGroup.docs.first.reference.parent.parent;
          if (parentSchool != null) {
            foundSchoolId = parentSchool.id;
          }
        }
      } catch (e) {
        debugPrint("Error resolving schoolId via collectionGroup: $e");
      }
    }

    _resolvedSchoolId = foundSchoolId ?? authService.schoolId ?? '';

    if (_resolvedSchoolId != null && _resolvedSchoolId!.isNotEmpty) {
      await _fetchTimetableSubcollection(shouldSetState: false);
      _initStreams(_resolvedSchoolId!);
    }

    if (mounted) {
      setState(() {
        _isResolvingSchool = false;
      });
    }
  }

  Future<void> _fetchTimetableSubcollection({bool shouldSetState = true}) async {
    final sid = _resolvedSchoolId;
    if (sid == null || sid.isEmpty) return;
    try {
      final eventRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(sid)
          .collection('events')
          .doc(widget.eventId);

      final results = await Future.wait([
        eventRef.collection('timetable').get(),
        eventRef.collection('sessions').orderBy('order').get(),
      ]);

      final timetableSnap = results[0];
      final sessionsSnap = results[1];

      _timetableSubcollection = timetableSnap.docs.map((d) {
        final data = d.data();
        data['_docId'] = d.id;
        return data;
      }).toList();
      _sessionsSubcollection = sessionsSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      if (shouldSetState && mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching timetable/sessions subcollection: $e');
    }
  }

  String _getNamaHari(DateTime dt) {
    const hari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    return hari[dt.weekday - 1];
  }

  String _getNamaBulan(DateTime dt) {
    const bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return bulan[dt.month - 1];
  }

  List<Map<String, dynamic>> _buildSeatsFromRoomAssignments({
    required List<Map<String, dynamic>> assignedClassesInRoom,
    required int capacity,
    required String patternMode,
    required Map<String, List<Map<String, dynamic>>> classRealStudents,
  }) {
    if (assignedClassesInRoom.isEmpty || capacity <= 0) return [];

    final activeClasses = assignedClassesInRoom.where((c) {
      final cName = (c['className'] ?? c['classId'] ?? c['name'] ?? '').toString().trim();
      return cName.isNotEmpty;
    }).toList();

    if (activeClasses.isEmpty) return [];

    final sortedClasses = List<Map<String, dynamic>>.from(activeClasses);
    sortedClasses.sort((a, b) {
      final nameA = (a['className'] ?? a['classId'] ?? a['name'] ?? '').toString();
      final nameB = (b['className'] ?? b['classId'] ?? b['name'] ?? '').toString();
      return naturalCompare(nameA, nameB);
    });

    final classQueues = <String, List<Map<String, dynamic>>>{};

    for (var cls in sortedClasses) {
      final cName = (cls['className'] ?? cls['classId'] ?? cls['name'] ?? '').toString().trim();
      final count = (cls['studentCount'] as num?)?.toInt() ?? (cls['count'] as num?)?.toInt() ?? (cls['capacity'] as num?)?.toInt() ?? 6;

      List<Map<String, dynamic>> realList = classRealStudents[cName] ?? [];
      if (realList.isEmpty) {
        final cClean = cName.toLowerCase().replaceAll(' ', '');
        for (var entry in classRealStudents.entries) {
          if (entry.key.toLowerCase().replaceAll(' ', '') == cClean) {
            realList = entry.value;
            break;
          }
        }
      }

      final list = <Map<String, dynamic>>[];
      for (int i = 0; i < count; i++) {
        if (i < realList.length) {
          list.add(Map<String, dynamic>.from(realList[i]));
        } else {
          final idx = i + 1;
          list.add({
            'displayName': '$cName Murid $idx',
            'studentName': '$cName Murid $idx',
            'className': cName,
            'classId': cName,
            'nis': '${1000 + idx}',
            'participantNumber': '2026-REG-$idx',
          });
        }
      }
      classQueues[cName] = list;
    }

    final seats = <Map<String, dynamic>>[];
    final isNormalSequential = patternMode.toUpperCase() == 'NORMAL' || patternMode.isEmpty;

    if (isNormalSequential) {
      // Sequential allocation class by class:
      // Seats 1..6 -> XI IPA 1
      // Seats 7..12 -> XI IPS 1
      int currentSeatNum = 1;
      for (var cName in classQueues.keys) {
        final q = classQueues[cName]!;
        for (int i = 0; i < q.length; i++) {
          if (currentSeatNum > capacity) break;
          final student = q[i];
          seats.add({
            'seatNumber': currentSeatNum,
            'studentId': (student['studentId'] ?? student['id'] ?? student['nis'] ?? '$cName-$i').toString(),
            'displayName': (student['displayName'] ?? student['studentName'] ?? student['name'] ?? 'Murid').toString(),
            'studentName': (student['displayName'] ?? student['studentName'] ?? student['name'] ?? 'Murid').toString(),
            'className': cName,
            'classId': cName,
            'nis': (student['nis'] ?? '').toString(),
            'participantNumber': (student['participantNumber'] ?? '').toString(),
            'gender': (student['gender'] ?? '').toString(),
            'angkatan': (student['angkatan'] ?? '').toString(),
          });
          currentSeatNum++;
        }
      }
    } else {
      // Alternating / Zigzag allocation
      final classKeys = classQueues.keys.toList();
      final classPointers = <String, int>{for (var k in classKeys) k: 0};
      int classIdx = 0;

      for (int seatNum = 1; seatNum <= capacity; seatNum++) {
        String? targetClass;
        for (int i = 0; i < classKeys.length; i++) {
          final candidate = classKeys[(classIdx + i) % classKeys.length];
          final ptr = classPointers[candidate] ?? 0;
          final total = classQueues[candidate]?.length ?? 0;
          if (ptr < total) {
            targetClass = candidate;
            classIdx = (classIdx + i + 1) % classKeys.length;
            break;
          }
        }

        if (targetClass != null) {
          final ptr = classPointers[targetClass]!;
          final student = classQueues[targetClass]![ptr];
          classPointers[targetClass] = ptr + 1;

          seats.add({
            'seatNumber': seatNum,
            'studentId': (student['studentId'] ?? student['id'] ?? student['nis'] ?? '$targetClass-$ptr').toString(),
            'displayName': (student['displayName'] ?? student['studentName'] ?? student['name'] ?? 'Murid').toString(),
            'studentName': (student['displayName'] ?? student['studentName'] ?? student['name'] ?? 'Murid').toString(),
            'className': targetClass,
            'classId': targetClass,
            'nis': (student['nis'] ?? '').toString(),
            'participantNumber': (student['participantNumber'] ?? '').toString(),
            'gender': (student['gender'] ?? '').toString(),
            'angkatan': (student['angkatan'] ?? '').toString(),
          });
        } else {
          break;
        }
      }
    }

    return seats;
  }

  Widget _buildProctorLoadingView(String message) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  color: Color(0xFF4F46E5),
                  strokeWidth: 3.5,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Menyiapkan data denah & presensi murid...',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = _resolvedSchoolId ?? '';

    if (_isResolvingSchool || schoolId.isEmpty) {
      return _buildProctorLoadingView('Menyiapkan Data Denah Ruangan...');
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _eventStream ??
            FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('events')
                .doc(widget.eventId)
                .snapshots(),
        builder: (context, evSnap) {
          if (!evSnap.hasData && evSnap.connectionState == ConnectionState.waiting) {
            return _buildProctorLoadingView('Memuat Data Event Ujian...');
          }

          final evData = evSnap.data?.data() as Map<String, dynamic>? ?? {};
          final draftState = evData['draftState'] as Map<String, dynamic>?;

          // Timetable List
          final timetableList = <Map<String, dynamic>>[];
          for (var item in _timetableSubcollection) {
            timetableList.add(item);
          }
          if (draftState != null && draftState['timetable'] is List) {
            for (var item in (draftState['timetable'] as List)) {
              if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
            }
          }
          if (evData['timetable'] is List) {
            for (var item in (evData['timetable'] as List)) {
              if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
            }
          }

          // Rooms List
          final roomsList = draftState?['step4']?['rooms'] as List? ??
              draftState?['rooms'] as List? ??
              evData['rooms'] as List? ??
              [];

          return StreamBuilder<QuerySnapshot>(
            stream: _roomsStream ??
                FirebaseFirestore.instance
                    .collection('schools')
                    .doc(schoolId)
                    .collection('events')
                    .doc(widget.eventId)
                    .collection('rooms')
                    .snapshots(),
            builder: (context, roomSnap) {
              final roomDocs = roomSnap.data?.docs ?? [];

              return StreamBuilder<QuerySnapshot>(
                stream: _makeupSessionsStream ??
                    FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolId)
                        .collection('events')
                        .doc(widget.eventId)
                        .collection('makeup_sessions')
                        .snapshots(),
                builder: (context, makeupSnap) {
                  final makeupDocs = makeupSnap.data?.docs ?? [];

                  // Check if this room is a makeup room:
                  // 1. docId keyword hints, OR
                  // 2. roomId keyword hint, OR
                  // 3. docId directly matches a makeup_session document ID (for Firestore auto-IDs)
                  final bool isMakeupRoom = widget.docId.startsWith('makeup_') ||
                      widget.docId.contains('makeup') ||
                      widget.roomId.toLowerCase().contains('susulan') ||
                      (widget.docId.isNotEmpty && makeupDocs.any((d) => d.id == widget.docId));

                  Map<String, dynamic>? targetMakeupSession;
                  if (isMakeupRoom) {
                    // Priority 1: Exact Firestore document ID match (most precise)
                    if (widget.docId.isNotEmpty) {
                      for (var mDoc in makeupDocs) {
                        if (mDoc.id == widget.docId) {
                          final mData = Map<String, dynamic>.from(mDoc.data() as Map<String, dynamic>);
                          mData['id'] = mDoc.id;
                          targetMakeupSession = mData;
                          break;
                        }
                      }
                    }
                    // Priority 2: Fallback to roomName matching (only if docId didn't match)
                    if (targetMakeupSession == null) {
                      for (var mDoc in makeupDocs) {
                        final mData = mDoc.data() as Map<String, dynamic>;
                        final mRoomName = (mData['roomName'] ?? '').toString();
                        if (mRoomName == widget.roomId || mRoomName.toLowerCase() == widget.roomId.toLowerCase()) {
                          final copy = Map<String, dynamic>.from(mData);
                          copy['id'] = mDoc.id;
                          targetMakeupSession = copy;
                          break;
                        }
                      }
                    }
                  }

                  final approvedStudents = <Map<String, dynamic>>[];
                  if (isMakeupRoom && targetMakeupSession != null) {
                    final rawList = targetMakeupSession['approvedStudents'];
                    if (rawList is List) {
                      for (var st in rawList) {
                        if (st is Map) approvedStudents.add(Map<String, dynamic>.from(st));
                      }
                    }
                  }

              Map<String, dynamic>? targetRoom;
              for (var doc in roomDocs) {
                final d = doc.data() as Map<String, dynamic>;
                if (doc.id == widget.roomId || d['code'] == widget.roomId || d['name'] == widget.roomId) {
                  targetRoom = d;
                  targetRoom['id'] = doc.id;
                  break;
                }
              }

              if (targetRoom == null) {
                for (var r in roomsList) {
                  if (r is Map) {
                    final rId = (r['id'] ?? r['code'] ?? r['name'] ?? '').toString();
                    if (rId == widget.roomId || r['name'] == widget.roomId) {
                      targetRoom = Map<String, dynamic>.from(r);
                      break;
                    }
                  }
                }
              }

              targetRoom ??= {
                'id': widget.roomId,
                'name': widget.roomId.startsWith('local_') ? 'Ruang B' : widget.roomId,
                'capacity': 35,
              };

              String roomName = (targetRoom['name'] ?? targetRoom['roomName'] ?? widget.roomId).toString();
              if (isMakeupRoom && targetMakeupSession != null) {
                roomName = (targetMakeupSession['roomName'] ?? widget.roomId).toString();
              }

              final int roomCapacity = isMakeupRoom
                  ? (approvedStudents.isNotEmpty ? approvedStudents.length : 1)
                  : ((targetRoom['capacity'] as num?)?.toInt() ?? 35);

              final roomAliases = <String>{
                widget.roomId,
                roomName,
                roomName.toLowerCase(),
                roomName.replaceAll(' ', ''),
              };
              final cleanRoomName = roomName.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
              roomAliases.add(cleanRoomName);

              // Step 5/6 Room Assignments
              final rawRoomAssignments = draftState?['step6']?['roomAssignments'] as Map? ??
                  draftState?['step5']?['roomAssignments'] as Map? ??
                  draftState?['roomAssignments'] as Map? ??
                  evData['roomAssignments'] as Map? ??
                  {};

              final Set<String> normalizedAliases = {};
              for (var a in roomAliases) {
                final clean = a.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
                if (clean.isNotEmpty) normalizedAliases.add(clean);
              }

              List<Map<String, dynamic>> assignedClassesInRoom = [];
              if (rawRoomAssignments.isNotEmpty) {
                rawRoomAssignments.forEach((key, val) {
                  final kStr = key.toString();
                  final kClean = kStr.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
                  bool isMatch = roomAliases.contains(kStr) ||
                      cleanRoomName == kClean ||
                      cleanRoomName.contains(kClean) ||
                      kClean.contains(cleanRoomName);
                  if (!isMatch) {
                    for (var norm in normalizedAliases) {
                      if (kClean == norm || (norm.length > 2 && kClean.contains(norm)) || (kClean.length > 2 && norm.contains(kClean))) {
                        isMatch = true;
                        break;
                      }
                    }
                  }
                  if (isMatch && val is List) {
                    for (var c in val) {
                      if (c is Map) assignedClassesInRoom.add(Map<String, dynamic>.from(c));
                    }
                  }
                });
              }

              if (assignedClassesInRoom.isEmpty) {
                final rClasses = targetRoom['classes'] as List? ?? targetRoom['assignedClasses'] as List? ?? targetRoom['roomAssignments'] as List? ?? [];
                for (var item in rClasses) {
                  if (item is Map) {
                    assignedClassesInRoom.add(Map<String, dynamic>.from(item));
                  } else if (item is String && item.isNotEmpty) {
                    assignedClassesInRoom.add({'className': item, 'count': 6});
                  }
                }
              }

              final roomClassNamesSet = <String>{};
              for (var c in assignedClassesInRoom) {
                final cName = (c['className'] ?? c['classId'] ?? c['name'] ?? '').toString().trim();
                final cId = (c['classId'] ?? '').toString().trim();
                if (cName.isNotEmpty) {
                  roomClassNamesSet.add(cName);
                  roomClassNamesSet.add(cName.toLowerCase().replaceAll(' ', ''));
                }
                if (cId.isNotEmpty) {
                  roomClassNamesSet.add(cId);
                  roomClassNamesSet.add(cId.toLowerCase().replaceAll(' ', ''));
                }
              }

              final matchedSubjects = <String>[];
              final matchedSubjectIds = <String>{};
              // For makeup rooms: also collect student IDs so realtime docs can be matched by student ID
              final makeupStudentIds = <String>{};

              if (isMakeupRoom) {
                for (var st in approvedStudents) {
                  final sName = (st['subjectName'] ?? '').toString().trim();
                  final sId = (st['subjectId'] ?? '').toString().trim();
                  final stId = (st['studentId'] ?? st['id'] ?? '').toString().trim().toLowerCase();
                  final stNis = (st['nis'] ?? '').toString().trim().toLowerCase();
                  final stName = (st['studentName'] ?? st['displayName'] ?? '').toString().trim().toLowerCase();
                  if (sName.isNotEmpty && !matchedSubjects.contains(sName)) {
                    matchedSubjects.add(sName);
                  }
                  if (sId.isNotEmpty) {
                    matchedSubjectIds.add(sId.toLowerCase());
                  }
                  if (stId.isNotEmpty) makeupStudentIds.add(stId);
                  if (stNis.isNotEmpty) makeupStudentIds.add(stNis);
                  if (stName.isNotEmpty) makeupStudentIds.add(stName);
                }
                if (matchedSubjects.isEmpty) {
                  matchedSubjects.add('Ujian Susulan');
                }
              } else {
                // Filter Subjects specifically for current session (e.g. Sesi 2)
                final targetKeyStr = 'day_${widget.dayIndex}_session_${widget.sessionIndex}';
                final targetSessionIdStr1 = 'session_${widget.sessionIndex}';

                String? targetRealSessionId;
                if (_sessionsSubcollection.isNotEmpty) {
                  final dateGroups = <String, List<Map<String, dynamic>>>{};
                  for (var s in _sessionsSubcollection) {
                    final dStr = (s['date'] ?? s['startDate'] ?? '').toString();
                    if (dStr.isNotEmpty) {
                      dateGroups.putIfAbsent(dStr, () => []).add(s);
                    }
                  }
                  final sortedDates = dateGroups.keys.toList()..sort();
                  if (widget.dayIndex < sortedDates.length) {
                    final dayDate = sortedDates[widget.dayIndex];
                    final daySessions = List<Map<String, dynamic>>.from(dateGroups[dayDate]!);
                    daySessions.sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
                    if (widget.sessionIndex < daySessions.length) {
                      targetRealSessionId = daySessions[widget.sessionIndex]['id']?.toString();
                    }
                  }
                }

                for (var tItem in timetableList) {
                  final tSessionId = (tItem['sessionId'] ?? tItem['session_id'] ?? '').toString();
                  final tDay = (tItem['dayIndex'] ?? tItem['day'] as num?)?.toInt();
                  final tSession = (tItem['sessionIndex'] ?? tItem['session'] as num?)?.toInt();

                  bool isMatch = false;

                  if (tDay != null && tDay != widget.dayIndex) {
                    isMatch = false;
                  } else if (tSessionId == targetKeyStr || (targetRealSessionId != null && tSessionId == targetRealSessionId)) {
                    isMatch = true;
                  } else if (tSessionId.isNotEmpty) {
                    if (tDay == widget.dayIndex && (tSessionId == targetSessionIdStr1 || tSessionId == '${widget.sessionIndex}')) {
                      isMatch = true;
                    }
                  } else if (tSession != null) {
                    bool dayMatch = tDay == null || tDay == widget.dayIndex;
                    bool sessMatch = tSession == widget.sessionIndex;
                    isMatch = dayMatch && sessMatch;
                  }

                  if (isMatch) {
                    final subj = (tItem['subjectName'] ?? tItem['subject'] ?? '').toString().trim();
                    final subjId = (tItem['subjectId'] ?? tItem['id'] ?? '').toString().trim().toLowerCase();
                    final cls = (tItem['className'] ?? tItem['classId'] ?? '').toString().trim();
                    final cId = (tItem['classId'] ?? '').toString().trim();

                    if (subj.isNotEmpty) {
                      bool classMatched = roomClassNamesSet.isEmpty;
                      if (!classMatched) {
                        final clsClean = cls.toLowerCase().replaceAll(' ', '');
                        final cIdClean = cId.toLowerCase().replaceAll(' ', '');
                        classMatched = roomClassNamesSet.contains(cls) ||
                            roomClassNamesSet.contains(cId) ||
                            roomClassNamesSet.contains(clsClean) ||
                            roomClassNamesSet.contains(cIdClean) ||
                            roomClassNamesSet.any((c) {
                              final cClean = c.toLowerCase().replaceAll(' ', '');
                              return cClean.isNotEmpty && (clsClean.contains(cClean) || cClean.contains(clsClean));
                            });
                      }
                      if (classMatched && !matchedSubjects.contains(subj)) {
                        matchedSubjects.add(subj);
                        if (subjId.isNotEmpty) matchedSubjectIds.add(subjId);
                      }
                    }
                  }
                }

                // Fallback 1: scheduleGrid
                if (matchedSubjects.isEmpty) {
                  final scheduleGrid = draftState?['step6']?['scheduleGrid'] as Map? ?? draftState?['scheduleGrid'] as Map? ?? evData['scheduleGrid'] as Map? ?? {};
                  final gridKeys = [
                    'day_${widget.dayIndex}_session_${widget.sessionIndex}',
                    'day_${widget.dayIndex}_session_${widget.sessionIndex + 1}',
                    'session_${widget.sessionIndex}',
                    'session_${widget.sessionIndex + 1}',
                    '${widget.sessionIndex + 1}',
                  ];
                  for (var gk in gridKeys) {
                    final schedSubjectIds = scheduleGrid[gk];
                    if (schedSubjectIds is List && schedSubjectIds.isNotEmpty) {
                      final subjectsList = draftState?['subjects'] as List? ?? evData['subjects'] as List? ?? [];
                      for (var sId in schedSubjectIds) {
                        String foundName = sId.toString();
                        final cleanSId = sId.toString().toLowerCase().trim();
                        if (cleanSId.isNotEmpty) matchedSubjectIds.add(cleanSId);
                        for (var sItem in subjectsList) {
                          if (sItem is Map && (sItem['id'] == sId || sItem['code'] == sId || sItem['name'] == sId)) {
                            foundName = sItem['name'] ?? sId.toString();
                            final sItemCode = (sItem['code'] ?? '').toString().toLowerCase().trim();
                            final sItemName = (sItem['name'] ?? '').toString().toLowerCase().trim();
                            if (sItemCode.isNotEmpty) matchedSubjectIds.add(sItemCode);
                            if (sItemName.isNotEmpty) matchedSubjectIds.add(sItemName);
                            break;
                          }
                        }
                        if (!matchedSubjects.contains(foundName)) matchedSubjects.add(foundName);
                      }
                    }
                  }
                }
              }

              final matchedSubjectsStr = matchedSubjects.isNotEmpty ? matchedSubjects.join(' • ') : 'Sosiologi • Fisika';

              // Date & Session Time Labels
              DateTime sessionDate = DateTime.now();
              String dateLabel = '${_getNamaHari(sessionDate)}, ${sessionDate.day} ${_getNamaBulan(sessionDate)} ${sessionDate.year}';

              String sessionTimeRange = '';
              if (widget.sessionIndex < _sessionsSubcollection.length) {
                final sData = _sessionsSubcollection[widget.sessionIndex];
                final startTime = (sData['startTime'] ?? sData['start'] ?? '').toString();
                final endTime = (sData['endTime'] ?? sData['end'] ?? '').toString();
                if (startTime.isNotEmpty && endTime.isNotEmpty) {
                  sessionTimeRange = ' ($startTime - $endTime)';
                }
              }
              if (sessionTimeRange.isEmpty) {
                sessionTimeRange = widget.sessionIndex == 0 ? ' (12:01 - 12:30)' : ' (14:00 - 15:30)';
              }
              String sessionLabel = 'Sesi ${widget.sessionIndex + 1}$sessionTimeRange';

              if (isMakeupRoom && targetMakeupSession != null) {
                final mDateStr = (targetMakeupSession['date'] ?? '').toString();
                final mStart = (targetMakeupSession['startTime'] ?? '').toString();
                final mEnd = (targetMakeupSession['endTime'] ?? '').toString();

                if (mDateStr.isNotEmpty) {
                  final dt = DateTime.tryParse(mDateStr);
                  if (dt != null) {
                    dateLabel = '${_getNamaHari(dt)}, ${dt.day} ${_getNamaBulan(dt)} ${dt.year}';
                  }
                }
                if (mStart.isNotEmpty && mEnd.isNotEmpty) {
                  sessionTimeRange = ' ($mStart - $mEnd WIB)';
                } else if (mStart.isNotEmpty) {
                  sessionTimeRange = ' ($mStart WIB)';
                }
                sessionLabel = 'Ujian Susulan$sessionTimeRange';
              }

              // Step 5/6 Allocations config
              final step5Allocations = draftState?['step6']?['allocations'] as List? ??
                  draftState?['step5']?['allocations'] as List? ??
                  draftState?['allocations'] as List? ??
                  evData['allocations'] as List? ??
                  [];

              String? activeAllocId;
              int configuredColumns = 8;
              String activeAllocMode = 'NORMAL';

              for (var alloc in step5Allocations) {
                if (alloc is Map) {
                  final rLayouts = alloc['roomLayouts'] as Map? ?? alloc['layouts'] as Map? ?? {};
                  rLayouts.forEach((k, v) {
                    if (v is Map) {
                      final kStr = k.toString().replaceAll('layout_', '');
                      final kClean = kStr.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
                      bool isMatch = roomAliases.contains(kStr) || roomAliases.contains(k.toString());
                      if (!isMatch) {
                        for (var norm in normalizedAliases) {
                          if (kClean == norm || (norm.length > 2 && kClean.contains(norm)) || (kClean.length > 2 && norm.contains(kClean))) {
                            isMatch = true;
                            break;
                          }
                        }
                      }
                      if (isMatch) {
                        activeAllocId = alloc['id']?.toString() ?? alloc['_docId']?.toString();
                        final cols = (v['colsPerPair'] ?? v['columns'] ?? v['totalColumns'] ?? v['cols'] as num?)?.toInt();
                        if (cols != null && cols > 0) configuredColumns = cols;
                        final arr = v['arrange'] ?? v['arrangeMode'];
                        if (arr != null && arr.toString().isNotEmpty) activeAllocMode = arr.toString();
                      }
                    }
                  });
                }
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _attendancesStream ??
                    FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('events')
                .doc(widget.eventId)
                .collection('attendances')
                .snapshots(),
        builder: (context, attendanceSnap) {
          _localAttendedMap.clear();

          final attDocs = attendanceSnap.data?.docs ?? [];
          for (var aDoc in attDocs) {
            final aData = aDoc.data() as Map<String, dynamic>;
            final isAtt = aData['isAttended'] == true || aData['attended'] == true;
            if (isAtt) {
              final aDay = (aData['dayIndex'] as num?)?.toInt() ?? 0;
              final aSess = (aData['sessionIndex'] as num?)?.toInt() ?? 0;
              if (aDay != widget.dayIndex || aSess != widget.sessionIndex) {
                continue;
              }
              final aRoomId = (aData['roomId'] ?? aData['room'] ?? '').toString().trim();
              if (aRoomId.isNotEmpty) {
                final cleanARoom = aRoomId.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
                final cleanWidgetRoom = widget.roomId.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
                final cleanRoomName = roomName.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');

                bool roomMatches = cleanARoom == cleanWidgetRoom ||
                    cleanARoom == cleanRoomName ||
                    cleanWidgetRoom.contains(cleanARoom) ||
                    cleanARoom.contains(cleanWidgetRoom) ||
                    cleanRoomName.contains(cleanARoom) ||
                    cleanARoom.contains(cleanRoomName);

                if (!roomMatches) {
                  continue; // Skip attendance document if it belongs to ANOTHER room!
                }
              }

              final sId = (aData['studentId'] ?? aData['id'] ?? '').toString().toLowerCase();
              final sNis = (aData['nis'] ?? '').toString().toLowerCase();
              final sName = (aData['studentName'] ?? aData['displayName'] ?? '').toString().toLowerCase();
              final sSubj = (aData['subjectId'] ?? aData['subjectName'] ?? '').toString().toLowerCase();
              final seatNum = (aData['seatNumber'] as num?)?.toInt();
              if (sId.isNotEmpty) {
                _localAttendedMap[sId] = true;
                if (sSubj.isNotEmpty) _localAttendedMap['${sId}_$sSubj'] = true;
              }
              if (sNis.isNotEmpty) {
                _localAttendedMap[sNis] = true;
                if (sSubj.isNotEmpty) _localAttendedMap['${sNis}_$sSubj'] = true;
              }
              if (sName.isNotEmpty) {
                _localAttendedMap[sName] = true;
                if (sSubj.isNotEmpty) _localAttendedMap['${sName}_$sSubj'] = true;
              }
              if (seatNum != null && seatNum > 0) {
                _localAttendedMap['${widget.roomId}_seat_$seatNum'] = true;
                _localAttendedMap['seat_${widget.roomId}_$seatNum'] = true;
                if (sSubj.isNotEmpty) {
                  _localAttendedMap['${widget.roomId}_seat_${seatNum}_$sSubj'] = true;
                }
              }
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _realtimeStream ??
                FirebaseFirestore.instance
                    .collection('schools')
                    .doc(schoolId)
                    .collection('events')
                    .doc(widget.eventId)
                    .collection('realtime_control')
                    .snapshots(),
            builder: (context, realtimeSnap) {
              final realtimeMap = <String, Map<String, dynamic>>{};
              final realtimeDocs = realtimeSnap.data?.docs ?? [];
              final cleanActiveSubjectNames = matchedSubjects.map((s) => s.toLowerCase().trim()).toSet();

              for (var doc in realtimeDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final rtSubjId = (data['subjectId'] ?? '').toString().toLowerCase().trim();
                final rtSubjName = (data['subjectName'] ?? '').toString().toLowerCase().trim();
                final rtStudentId = (data['studentId'] ?? doc.id).toString().toLowerCase().trim();
                final rtNis = (data['nis'] ?? '').toString().toLowerCase().trim();
                final rtStudentName = (data['studentName'] ?? '').toString().toLowerCase().trim();

                bool subjectMatches = false;
                if (matchedSubjects.isEmpty) {
                  subjectMatches = true;
                } else if (isMakeupRoom && makeupStudentIds.isNotEmpty) {
                  // For makeup rooms: match by student identity (bypass subject filter)
                  // because the student's realtime doc has the real subject (e.g. "Biologi"),
                  // not "Ujian Susulan"
                  subjectMatches = makeupStudentIds.contains(rtStudentId) ||
                      makeupStudentIds.contains(rtNis) ||
                      makeupStudentIds.contains(rtStudentName);
                } else {
                  if (cleanActiveSubjectNames.contains(rtSubjName) ||
                      matchedSubjectIds.contains(rtSubjId) ||
                      matchedSubjectIds.contains(rtSubjName)) {
                    subjectMatches = true;
                  }
                }

                if (!subjectMatches) {
                  continue; // Skip realtime states for other subjects/rooms!
                }

                final sId = rtStudentId;
                final sNis = rtNis;
                final sName = rtStudentName;
                if (sId.isNotEmpty) realtimeMap[sId] = data;
                if (sNis.isNotEmpty) realtimeMap[sNis] = data;
                if (sName.isNotEmpty) realtimeMap[sName] = data;
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _submissionsStream ??
                    FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolId)
                        .collection('events')
                        .doc(widget.eventId)
                        .collection('submissions')
                        .snapshots(),
                        builder: (context, subSnap) {
                          final submissionsMap = <String, Map<String, dynamic>>{};
                          final subDocs = subSnap.data?.docs ?? [];
                          for (var doc in subDocs) {
                            final data = doc.data() as Map<String, dynamic>;
                            final subSubjId = (data['subjectId'] ?? '').toString().toLowerCase().trim();
                            final subSubjName = (data['subjectName'] ?? '').toString().toLowerCase().trim();
                            final subStudentId = (data['studentId'] ?? '').toString().toLowerCase().trim();
                            final subNis = (data['nis'] ?? '').toString().toLowerCase().trim();
                            final subStudentName = (data['studentName'] ?? '').toString().toLowerCase().trim();

                            bool subjectMatches = false;
                            if (matchedSubjects.isEmpty) {
                              subjectMatches = true;
                            } else if (isMakeupRoom && makeupStudentIds.isNotEmpty) {
                              // For makeup rooms: match by student identity (bypass subject filter)
                              subjectMatches = makeupStudentIds.contains(subStudentId) ||
                                  makeupStudentIds.contains(subNis) ||
                                  makeupStudentIds.contains(subStudentName);
                            } else {
                              if (cleanActiveSubjectNames.contains(subSubjName) ||
                                  matchedSubjectIds.contains(subSubjId) ||
                                  matchedSubjectIds.contains(subSubjName)) {
                                subjectMatches = true;
                              }
                            }

                            if (!subjectMatches) {
                              continue; // Skip submissions for other subjects/rooms!
                            }

                            final sId = subStudentId;
                            final sNis = subNis;
                            final sName = subStudentName;
                            if (sId.isNotEmpty) submissionsMap[sId] = data;
                            if (sNis.isNotEmpty) submissionsMap[sNis] = data;
                            if (sName.isNotEmpty) submissionsMap[sName] = data;
                          }

                  return StreamBuilder<QuerySnapshot>(
                    stream: _allocationsStream ??
                        FirebaseFirestore.instance
                            .collection('schools')
                            .doc(schoolId)
                            .collection('events')
                            .doc(widget.eventId)
                            .collection('allocations')
                            .snapshots(),
                    builder: (context, allocSnap) {
                      if (!allocSnap.hasData && allocSnap.connectionState == ConnectionState.waiting) {
                        return _buildProctorLoadingView('Memuat Alokasi Tempat Duduk...');
                      }
                      final allocDocs = allocSnap.data?.docs ?? [];
                      String? resolvedAllocDocId = activeAllocId;
                      if (allocDocs.isNotEmpty) {
                        final sortedAllocDocs = List<QueryDocumentSnapshot>.from(allocDocs);
                        sortedAllocDocs.sort((a, b) {
                          final aTime = (a.data() as Map<String, dynamic>?)?['createdAt'];
                          final bTime = (b.data() as Map<String, dynamic>?)?['createdAt'];
                          if (aTime is Timestamp && bTime is Timestamp) {
                            return bTime.compareTo(aTime);
                          }
                          return 0;
                        });
                        resolvedAllocDocId = sortedAllocDocs.first.id;
                      }

                      if (_seatsAllocDocId != resolvedAllocDocId && resolvedAllocDocId != null && resolvedAllocDocId.isNotEmpty) {
                        _seatsAllocDocId = resolvedAllocDocId;
                        _seatsStream = FirebaseFirestore.instance
                            .collection('schools')
                            .doc(schoolId)
                            .collection('events')
                            .doc(widget.eventId)
                            .collection('allocations')
                            .doc(resolvedAllocDocId)
                            .collection('seats')
                            .snapshots();
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: _seatsStream ??
                            (resolvedAllocDocId != null && resolvedAllocDocId.isNotEmpty
                                ? FirebaseFirestore.instance
                                    .collection('schools')
                                    .doc(schoolId)
                                    .collection('events')
                                    .doc(widget.eventId)
                                    .collection('allocations')
                                    .doc(resolvedAllocDocId)
                                    .collection('seats')
                                    .snapshots()
                                : null),
                        builder: (context, seatsSnap) {
                          if (!seatsSnap.hasData && seatsSnap.connectionState == ConnectionState.waiting) {
                            return _buildProctorLoadingView('Memuat Denah Bangku...');
                          }
                          final seatDocs = seatsSnap.data?.docs ?? [];
                          final allocatedSeatsFromFirestore = seatDocs.map((d) => d.data() as Map<String, dynamic>).where((s) {
                            final rCode = (s['roomCode'] ?? s['roomId'] ?? s['roomName'] ?? s['room'] ?? '').toString();
                            final rName = (s['roomName'] ?? s['name'] ?? '').toString();
                            final rId = (s['roomId'] ?? s['id'] ?? '').toString();
                            return roomAliases.contains(rCode) ||
                                roomAliases.contains(rName) ||
                                roomAliases.contains(rId) ||
                                rCode == widget.roomId ||
                                rName == roomName ||
                                rId == widget.roomId;
                          }).toList();

                          final seatMap = <int, Map<String, dynamic>>{};
                          final roomStudentIds = <String>{};
                          final roomStudentNises = <String>{};
                          for (var s in allocatedSeatsFromFirestore) {
                            final numVal = (s['seatNumber'] as num?)?.toInt() ?? 0;
                            if (numVal > 0) seatMap[numVal] = s;
                            final stId = (s['studentId'] ?? s['id'] ?? '').toString().trim();
                            final stNis = (s['nis'] ?? '').toString().trim();
                            if (stId.isNotEmpty) roomStudentIds.add(stId);
                            if (stNis.isNotEmpty) roomStudentNises.add(stNis);
                          }

                      return StreamBuilder<QuerySnapshot>(
                        stream: _classesStream ??
                            FirebaseFirestore.instance
                                .collection('schools')
                                .doc(schoolId)
                                .collection('classes')
                                .snapshots(),
                        builder: (context, classSnap) {
                          if (!classSnap.hasData && classSnap.connectionState == ConnectionState.waiting) {
                            return _buildProctorLoadingView('Memuat Data Kelas...');
                          }
                          final classDocs = classSnap.data?.docs ?? [];
                          final classRealStudents = <String, List<Map<String, dynamic>>>{};

                          return StreamBuilder<QuerySnapshot>(
                            stream: _studentsStream ??
                                FirebaseFirestore.instance
                                    .collection('schools')
                                    .doc(schoolId)
                                    .collection('students')
                                    .snapshots(),
                            builder: (context, studentSnap) {
                              if (!studentSnap.hasData && studentSnap.connectionState == ConnectionState.waiting) {
                                return _buildProctorLoadingView('Memuat Data Murid...');
                              }
                              final studentDocs = studentSnap.data?.docs ?? [];
                              final realStudentsAZ = studentDocs.map((d) {
                                final data = d.data() as Map<String, dynamic>;
                                data['id'] = d.id;
                                return data;
                              }).toList();
                              realStudentsAZ.sort((a, b) {
                                final nameA = (a['displayName'] ?? a['studentName'] ?? a['name'] ?? '').toString();
                                final nameB = (b['displayName'] ?? b['studentName'] ?? b['name'] ?? '').toString();
                                return naturalCompare(nameA, nameB);
                              });

                              // Map classDocs -> classRealStudents
                              for (var cDoc in classDocs) {
                                final cData = cDoc.data() as Map<String, dynamic>;
                                final cName = (cData['name'] ?? cData['className'] ?? cDoc.id).toString();
                                final cStudents = (cData['students'] as List?) ?? [];
                                final studentList = <Map<String, dynamic>>[];
                                for (var st in cStudents) {
                                  if (st is Map) studentList.add(Map<String, dynamic>.from(st));
                                }

                                if (studentList.isEmpty && realStudentsAZ.isNotEmpty) {
                                  final matchingReal = realStudentsAZ.where((s) {
                                    final sClass = (s['className'] ?? s['classId'] ?? s['class'] ?? '').toString().trim();
                                    final cClean = cName.toLowerCase().replaceAll(' ', '');
                                    final sClean = sClass.toLowerCase().replaceAll(' ', '');
                                    return sClass == cName || sClean == cClean || sClean.contains(cClean) || cClean.contains(sClean);
                                  }).toList();
                                  if (matchingReal.isNotEmpty) studentList.addAll(matchingReal);
                                }

                                classRealStudents[cName] = studentList;
                              }

                              // Ensure assignedClassesInRoom classes have student entries mapped
                              for (var clsMap in assignedClassesInRoom) {
                                final cName = (clsMap['className'] ?? clsMap['classId'] ?? clsMap['name'] ?? '').toString().trim();
                                if (cName.isNotEmpty && !classRealStudents.containsKey(cName)) {
                                  final matchingReal = realStudentsAZ.where((s) {
                                    final sClass = (s['className'] ?? s['classId'] ?? s['class'] ?? '').toString().trim();
                                    final cClean = cName.toLowerCase().replaceAll(' ', '');
                                    final sClean = sClass.toLowerCase().replaceAll(' ', '');
                                    return sClass == cName || sClean == cClean || sClean.contains(cClean) || cClean.contains(sClean);
                                  }).toList();
                                  classRealStudents[cName] = matchingReal;
                                }
                              }

                              if (isMakeupRoom) {
                                seatMap.clear();
                                for (int i = 0; i < approvedStudents.length; i++) {
                                  final st = approvedStudents[i];
                                  final seatNum = i + 1;
                                  seatMap[seatNum] = {
                                    'seatNumber': seatNum,
                                    'studentId': (st['studentId'] ?? st['id'] ?? st['nis'] ?? 'susulan_$seatNum').toString(),
                                    'displayName': (st['studentName'] ?? st['displayName'] ?? st['name'] ?? 'Murid').toString(),
                                    'studentName': (st['studentName'] ?? st['displayName'] ?? st['name'] ?? 'Murid').toString(),
                                    'className': (st['className'] ?? 'Umum').toString(),
                                    'classId': (st['className'] ?? 'Umum').toString(),
                                    'nis': (st['nis'] ?? '').toString(),
                                    'subjectId': (st['subjectId'] ?? '').toString(),
                                    'subjectName': (st['subjectName'] ?? '').toString(),
                                  };
                                }
                              } else if (seatMap.isEmpty) {
                                final synthesizedSeats = _buildSeatsFromRoomAssignments(
                                  assignedClassesInRoom: assignedClassesInRoom.isNotEmpty
                                      ? assignedClassesInRoom
                                      : [
                                          {'className': 'XI IPA 1', 'count': 6},
                                          {'className': 'XI IPS 1', 'count': 6},
                                        ],
                                  capacity: roomCapacity,
                                  patternMode: activeAllocMode,
                                  classRealStudents: classRealStudents,
                                );
                                for (var s in synthesizedSeats) {
                                  final numVal = (s['seatNumber'] as num?)?.toInt() ?? 0;
                                  if (numVal > 0) seatMap[numVal] = s;
                                }
                              }

                              // Ensure attendance state & realtime control synced into seatMap entries
                              seatMap.forEach((seatNum, sData) {
                                final sId = (sData['studentId'] ?? sData['id'] ?? '').toString().toLowerCase();
                                final sNis = (sData['nis'] ?? '').toString().toLowerCase();
                                final sName = (sData['displayName'] ?? sData['studentName'] ?? '').toString().toLowerCase();
                                final sSubj = (sData['subjectId'] ?? sData['subjectName'] ?? '').toString().toLowerCase();

                                bool isAttended = false;
                                if (isMakeupRoom && sSubj.isNotEmpty) {
                                  if (sId.isNotEmpty && _localAttendedMap['${sId}_$sSubj'] == true) {
                                    isAttended = true;
                                  } else if (sNis.isNotEmpty && _localAttendedMap['${sNis}_$sSubj'] == true) {
                                    isAttended = true;
                                  } else if (sName.isNotEmpty && _localAttendedMap['${sName}_$sSubj'] == true) {
                                    isAttended = true;
                                  } else if (_localAttendedMap['${widget.roomId}_seat_${seatNum}_$sSubj'] == true) {
                                    isAttended = true;
                                  }
                                } else {
                                  if (sId.isNotEmpty && _localAttendedMap[sId] == true) {
                                    isAttended = true;
                                  } else if (sNis.isNotEmpty && _localAttendedMap[sNis] == true) {
                                    isAttended = true;
                                  } else if (sName.isNotEmpty && _localAttendedMap[sName] == true) {
                                    isAttended = true;
                                  } else if (sId.isEmpty && sNis.isEmpty && sName.isEmpty) {
                                    if (_localAttendedMap['${widget.roomId}_seat_$seatNum'] == true ||
                                        _localAttendedMap['seat_${widget.roomId}_$seatNum'] == true) {
                                      isAttended = true;
                                    }
                                  }
                                }

                                final cleanName = sName.replaceAll(' ', '').replaceAll('.', '').replaceAll('-', '');

                                Map<String, dynamic>? rtData = (sId.isNotEmpty ? realtimeMap[sId] : null) ??
                                    (sNis.isNotEmpty ? realtimeMap[sNis] : null) ??
                                    (sName.isNotEmpty ? realtimeMap[sName] : null) ??
                                    (cleanName.isNotEmpty ? realtimeMap[cleanName] : null);

                                Map<String, dynamic>? subData = (sId.isNotEmpty ? submissionsMap[sId] : null) ??
                                    (sNis.isNotEmpty ? submissionsMap[sNis] : null) ??
                                    (sName.isNotEmpty ? submissionsMap[sName] : null) ??
                                    (cleanName.isNotEmpty ? submissionsMap[cleanName] : null);

                                bool isCompleted = (rtData?['isCompleted'] == true) ||
                                    (rtData?['status'] == 'completed') ||
                                    (subData?['isCompleted'] == true);

                                bool isLeftApp = !isCompleted &&
                                    ((rtData?['isLeftApp'] == true) || (rtData?['status'] == 'left_app'));

                                bool isWorking = (rtData?['isWorking'] == true) ||
                                    (rtData?['status'] == 'in_progress') ||
                                    (rtData?['status'] == 'working');

                                sData['isAttended'] = isAttended || isCompleted || isLeftApp || isWorking;
                                sData['attended'] = isAttended || isCompleted || isLeftApp || isWorking;
                                sData['isCompleted'] = isCompleted;
                                sData['isLeftApp'] = isLeftApp;
                                sData['isWorking'] = isWorking;
                                sData['status'] = rtData?['status'] ?? (isCompleted ? 'completed' : (isLeftApp ? 'left_app' : (isWorking ? 'in_progress' : 'normal')));
                              });

                              final filledSeatsCount = seatMap.values.where((s) => (s['displayName'] ?? s['studentName'] ?? s['name'] ?? '').toString().isNotEmpty).length;

                              // Ordered Room Classes & Colors
                              final roomClassesSet = <String>{};
                              for (var s in seatMap.values) {
                                final cName = (s['classId'] ?? s['className'] ?? s['name'] ?? '').toString().trim();
                                if (cName.isNotEmpty) roomClassesSet.add(cName);
                              }
                              if (roomClassesSet.isEmpty) {
                                for (var c in assignedClassesInRoom) {
                                  final cName = (c['className'] ?? c['classId'] ?? c['name'] ?? '').toString().trim();
                                  if (cName.isNotEmpty) roomClassesSet.add(cName);
                                }
                              }
                              final orderedRoomClasses = roomClassesSet.toList()..sort(naturalCompare);

                              final classColorMap = <String, Map<String, Color>>{};
                              final classStudentCounts = <String, int>{};

                              for (var cls in orderedRoomClasses) {
                                classColorMap[cls] = TeacherProctorController.getClassColorScheme(cls, orderedRoomClasses);
                                classStudentCounts[cls] = seatMap.values.where((s) {
                                  final cName = (s['classId'] ?? s['className'] ?? s['name'] ?? '').toString().trim();
                                  return cName == cls;
                                }).length;
                              }

                              // Filter Seats by Search Query and Class Filter Dropdown
                              final filteredSeatIndices = <int>[];
                              seatMap.forEach((seatNum, sData) {
                                final fullName = (sData['displayName'] ?? sData['studentName'] ?? sData['name'] ?? '').toString().toLowerCase();
                                final className = (sData['classId'] ?? sData['className'] ?? sData['class'] ?? '').toString();
                                final nis = (sData['nis'] ?? '').toString().toLowerCase();
                                final seatStr = seatNum.toString();
                                final q = _searchQuery.trim().toLowerCase();

                                bool matchesSearch = q.isEmpty ||
                                    fullName.contains(q) ||
                                    className.toLowerCase().contains(q) ||
                                    nis.contains(q) ||
                                    seatStr == q;

                                bool matchesClass = _selectedClassFilter == 'Semua Kelas' ||
                                    className == _selectedClassFilter ||
                                    className.toLowerCase() == _selectedClassFilter.toLowerCase();

                                if (matchesSearch && matchesClass) {
                                  filteredSeatIndices.add(seatNum);
                                }
                              });
                              filteredSeatIndices.sort();

                              return StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('schools')
                                    .doc(schoolId)
                                    .collection('events')
                                    .doc(widget.eventId)
                                    .collection('proctors')
                                    .snapshots(),
                                builder: (context, proctorSnap) {
                                  final proctors = proctorSnap.data?.docs ?? [];
                                  String currentStatus = 'Belum Dimulai';
                                  String realProctorDocId = widget.docId;

                                  for (var pDoc in proctors) {
                                    final pData = pDoc.data() as Map<String, dynamic>;
                                    final pRoom = (pData['roomId'] ?? pData['roomCode'] ?? '').toString();
                                    if (roomAliases.contains(pRoom) || pRoom == widget.roomId) {
                                      currentStatus = pData['status'] ?? 'Belum Dimulai';
                                      if (realProctorDocId.isEmpty || realProctorDocId.startsWith('grid_')) {
                                        realProctorDocId = pDoc.id;
                                      }
                                      break;
                                    }
                                  }

                                  return LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isDesktop = constraints.maxWidth >= 900;
                                      final gridColumns = configuredColumns > 0 ? configuredColumns : 8;

                                      return SingleChildScrollView(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isDesktop ? 36 : 16,
                                          vertical: 24,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 1. Proctor Header Banner (Gambar 2 exact design)
                                            ProctorHeaderBanner(
                                              roomName: roomName,
                                              dateLabel: dateLabel,
                                              sessionLabel: sessionLabel,
                                              matchedSubjectsStr: matchedSubjectsStr,
                                              schoolId: schoolId,
                                              eventId: widget.eventId,
                                              roomId: widget.roomId,
                                              seatMap: seatMap,
                                              localAttendedMap: _localAttendedMap,
                                              seatNotifier: _seatNotifier,
                                              dayIndex: widget.dayIndex,
                                              sessionIndex: widget.sessionIndex,
                                              allowedSubjectNames: cleanActiveSubjectNames,
                                              allowedSubjectIds: matchedSubjectIds,
                                            ),
                                            const SizedBox(height: 20),

                                            // 2. KPI Cards Row (Gambar 1 exact design: 12 Murid Terdaftar, 23 Kursi Kosong)
                                            ProctorKpiCards(
                                              capacity: roomCapacity,
                                              filledCount: filledSeatsCount,
                                              classCount: orderedRoomClasses.length,
                                              status: currentStatus,
                                            ),
                                            const SizedBox(height: 20),

                                            // 3. Class Color Legend Bar
                                            ProctorClassLegendBar(
                                              roomClasses: orderedRoomClasses,
                                              classStudentCounts: classStudentCounts,
                                              classColorMap: classColorMap,
                                            ),
                                            const SizedBox(height: 20),

                                            // 4. Search Bar, Class Filter & Riwayat Keluar App Button
                                            ProctorSearchFilterBar(
                                              searchQuery: _searchQuery,
                                              selectedClassFilter: _selectedClassFilter,
                                              classSet: roomClassesSet,
                                              onSearchChanged: (val) => setState(() => _searchQuery = val),
                                              onClassFilterChanged: (val) => setState(() => _selectedClassFilter = val),
                                              onShowExitLogs: () => TeacherProctorController.showExitAppLogsModal(
                                                context: context,
                                                schoolId: schoolId,
                                                eventId: widget.eventId,
                                                allowedStudentIds: roomStudentIds,
                                                allowedStudentNises: roomStudentNises,
                                                allowedSubjectNames: cleanActiveSubjectNames,
                                                allowedSubjectIds: matchedSubjectIds,
                                                sessionName: sessionLabel,
                                              ),
                                              exitLogCount: realtimeDocs.where((doc) {
                                                final d = doc.data() as Map<String, dynamic>;
                                                final sId = (d['studentId'] ?? '').toString().trim();
                                                final sNis = (d['nis'] ?? '').toString().trim();
                                                final docId = doc.id.trim();

                                                final isRoomStudent = roomStudentIds.contains(sId) ||
                                                    (sNis.isNotEmpty && roomStudentNises.contains(sNis)) ||
                                                    roomStudentIds.contains(docId) ||
                                                    roomStudentIds.any((id) => id.isNotEmpty && docId.contains(id)) ||
                                                    (sNis.isNotEmpty && roomStudentNises.any((nis) => nis.isNotEmpty && docId.contains(nis)));

                                                if (!isRoomStudent && roomStudentIds.isNotEmpty) return false;

                                                // Check subject / session match
                                                final rtSubjId = (d['subjectId'] ?? '').toString().toLowerCase().trim();
                                                final rtSubjName = (d['subjectName'] ?? '').toString().toLowerCase().trim();
                                                if (cleanActiveSubjectNames.isNotEmpty) {
                                                  bool subjMatches = cleanActiveSubjectNames.contains(rtSubjName) ||
                                                      matchedSubjectIds.contains(rtSubjId) ||
                                                      matchedSubjectIds.contains(rtSubjName);

                                                  if (!subjMatches && (docId.contains('_') || docId.contains('-'))) {
                                                    for (final sub in cleanActiveSubjectNames) {
                                                      if (sub.isNotEmpty && docId.toLowerCase().contains(sub)) {
                                                        subjMatches = true;
                                                        break;
                                                      }
                                                    }
                                                  }

                                                  if (!subjMatches) return false;
                                                }

                                                final isLeftApp = d['isLeftApp'] == true || d['status'] == 'left_app';
                                                final logs = d['logs'] as List? ?? [];
                                                int actualLeft = 0;
                                                for (var l in logs) {
                                                  if (l is Map && (l['event'] == 'left_app' || l['status'] == 'left_app')) {
                                                    final entrySubjId = (l['subjectId'] ?? '').toString().toLowerCase().trim();
                                                    final entrySubjName = (l['subjectName'] ?? '').toString().toLowerCase().trim();
                                                    if (cleanActiveSubjectNames.isNotEmpty) {
                                                      if (entrySubjName.isNotEmpty || entrySubjId.isNotEmpty) {
                                                        bool entryMatches = cleanActiveSubjectNames.contains(entrySubjName) ||
                                                            matchedSubjectIds.contains(entrySubjId) ||
                                                            matchedSubjectIds.contains(entrySubjName);
                                                        if (!entryMatches) continue;
                                                      }
                                                    }
                                                    actualLeft++;
                                                  }
                                                }
                                                final count = actualLeft > 0 ? actualLeft : ((d['leftAppCount'] as num?)?.toInt() ?? 0);
                                                return isLeftApp || count > 0;
                                              }).length,
                                            ),
                                            const SizedBox(height: 20),

                                            // 5. Seating Grid Section Header & Legend Indicators
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Denah Bangku & Posisi Murid (${isMakeupRoom ? 'Ujian Susulan' : 'Pola $gridColumns Kolom'} • $roomCapacity Bangku)',
                                                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                                ),
                                                Row(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 12,
                                                          height: 12,
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF4F46E5),
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text('Meja Terisi', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                                                      ],
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 12,
                                                          height: 12,
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFCBD5E1),
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text('Meja Kosong', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),

                                            // 6. GridView of Seats
                                            ValueListenableBuilder<int>(
                                              valueListenable: _seatNotifier,
                                              builder: (context, seatValue, child) {
                                                final totalDisplayItems = filteredSeatIndices.length < roomCapacity && _searchQuery.isEmpty && _selectedClassFilter == 'Semua Kelas'
                                                    ? roomCapacity
                                                    : filteredSeatIndices.length;

                                                return GridView.builder(
                                                  shrinkWrap: true,
                                                  physics: const NeverScrollableScrollPhysics(),
                                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: isDesktop ? gridColumns : (gridColumns > 4 ? 4 : gridColumns),
                                                    crossAxisSpacing: 12,
                                                    mainAxisSpacing: 12,
                                                    childAspectRatio: 1.15,
                                                  ),
                                                  itemCount: totalDisplayItems,
                                                  itemBuilder: (context, idx) {
                                                    final seatNum = idx < filteredSeatIndices.length ? filteredSeatIndices[idx] : (idx + 1);
                                                    final seatData = seatMap[seatNum];

                                                    return ProctorSeatCard(
                                                      seatNum: seatNum,
                                                      seatData: seatData,
                                                      orderedRoomClasses: orderedRoomClasses,
                                                      schoolId: schoolId,
                                                      eventId: widget.eventId,
                                                      roomId: widget.roomId,
                                                      localAttendedMap: _localAttendedMap,
                                                      seatNotifier: _seatNotifier,
                                                      dayIndex: widget.dayIndex,
                                                      sessionIndex: widget.sessionIndex,
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  },
);
},
);
},
),
);
  }
}
