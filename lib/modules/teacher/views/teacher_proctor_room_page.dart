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

  @override
  void initState() {
    super.initState();
    _initSchoolId();
  }

  Future<void> _initSchoolId() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    // 1. Try authService
    if (authService.schoolId != null && authService.schoolId!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _resolvedSchoolId = authService.schoolId;
          _isResolvingSchool = false;
        });
      }
      await _fetchTimetableSubcollection();
      return;
    }

    // 2. Poll authService for up to 2 seconds
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      if (authService.schoolId != null && authService.schoolId!.isNotEmpty) {
        setState(() {
          _resolvedSchoolId = authService.schoolId;
          _isResolvingSchool = false;
        });
        await _fetchTimetableSubcollection();
        return;
      }
    }

    // 3. Fallback: Search event across schools collection group
    try {
      final evGroup = await FirebaseFirestore.instance
          .collectionGroup('events')
          .where(FieldPath.documentId, isEqualTo: widget.eventId)
          .limit(1)
          .get();

      if (evGroup.docs.isNotEmpty) {
        final parentSchool = evGroup.docs.first.reference.parent.parent;
        if (parentSchool != null && mounted) {
          setState(() {
            _resolvedSchoolId = parentSchool.id;
            _isResolvingSchool = false;
          });
          await _fetchTimetableSubcollection();
          return;
        }
      }
    } catch (e) {
      debugPrint("Error resolving schoolId via collectionGroup: $e");
    }

    if (mounted) {
      setState(() {
        _resolvedSchoolId = authService.schoolId ?? '';
        _isResolvingSchool = false;
      });
      await _fetchTimetableSubcollection();
    }
  }

  Future<void> _fetchTimetableSubcollection() async {
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

      if (mounted) {
        setState(() {
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
        });
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

  @override
  Widget build(BuildContext context) {
    final schoolId = _resolvedSchoolId ?? '';

    if (_isResolvingSchool || schoolId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF4F46E5)),
              const SizedBox(height: 16),
              Text(
                'Menyiapkan data denah ruangan...',
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('events')
            .doc(widget.eventId)
            .snapshots(),
        builder: (context, evSnap) {
          if (evSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
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
            stream: FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('events')
                .doc(widget.eventId)
                .collection('rooms')
                .snapshots(),
            builder: (context, roomSnap) {
              final roomDocs = roomSnap.data?.docs ?? [];

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

              final roomName = (targetRoom['name'] ?? targetRoom['roomName'] ?? widget.roomId).toString();
              final roomCapacity = (targetRoom['capacity'] as num?)?.toInt() ?? 35;

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

              final matchedSubjects = <String>[];

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
                      for (var sItem in subjectsList) {
                        if (sItem is Map && (sItem['id'] == sId || sItem['code'] == sId || sItem['name'] == sId)) {
                          foundName = sItem['name'] ?? sId.toString();
                          break;
                        }
                      }
                      if (!matchedSubjects.contains(foundName)) matchedSubjects.add(foundName);
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
                stream: FirebaseFirestore.instance
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
                      final sId = (aData['studentId'] ?? aData['id'] ?? '').toString().toLowerCase();
                      final sNis = (aData['nis'] ?? '').toString().toLowerCase();
                      final sName = (aData['studentName'] ?? aData['displayName'] ?? '').toString().toLowerCase();
                      final seatNum = (aData['seatNumber'] as num?)?.toInt();
                      if (sId.isNotEmpty) _localAttendedMap[sId] = true;
                      if (sNis.isNotEmpty) _localAttendedMap[sNis] = true;
                      if (sName.isNotEmpty) _localAttendedMap[sName] = true;
                      if (seatNum != null && seatNum > 0) _localAttendedMap['seat_$seatNum'] = true;
                    }
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolId)
                        .collection('events')
                        .doc(widget.eventId)
                        .collection('allocations')
                        .snapshots(),
                    builder: (context, allocSnap) {
                      final allocDocs = allocSnap.data?.docs ?? [];
                      String? resolvedAllocDocId = activeAllocId;
                      if ((resolvedAllocDocId == null || resolvedAllocDocId.isEmpty) && allocDocs.isNotEmpty) {
                        resolvedAllocDocId = allocDocs.last.id;
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: resolvedAllocDocId != null && resolvedAllocDocId.isNotEmpty
                            ? FirebaseFirestore.instance
                                .collection('schools')
                                .doc(schoolId)
                                .collection('events')
                                .doc(widget.eventId)
                                .collection('allocations')
                                .doc(resolvedAllocDocId)
                                .collection('seats')
                                .snapshots()
                            : null,
                        builder: (context, seatsSnap) {
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
                          for (var s in allocatedSeatsFromFirestore) {
                            final numVal = (s['seatNumber'] as num?)?.toInt() ?? 0;
                            if (numVal > 0) seatMap[numVal] = s;
                          }

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('schools')
                            .doc(schoolId)
                            .collection('classes')
                            .snapshots(),
                        builder: (context, classSnap) {
                          final classDocs = classSnap.data?.docs ?? [];
                          final classRealStudents = <String, List<Map<String, dynamic>>>{};

                          return StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('schools')
                                .doc(schoolId)
                                .collection('students')
                                .snapshots(),
                            builder: (context, studentSnap) {
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

                              if (seatMap.isEmpty) {
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

                              // Ensure attendance state synced into seatMap entries
                              seatMap.forEach((seatNum, sData) {
                                final sId = (sData['studentId'] ?? sData['id'] ?? '').toString().toLowerCase();
                                final sNis = (sData['nis'] ?? '').toString().toLowerCase();
                                final sName = (sData['displayName'] ?? sData['studentName'] ?? '').toString().toLowerCase();

                                bool isAttended = false;
                                if ((sId.isNotEmpty && _localAttendedMap[sId] == true) ||
                                    (sNis.isNotEmpty && _localAttendedMap[sNis] == true) ||
                                    (sName.isNotEmpty && _localAttendedMap[sName] == true) ||
                                    (_localAttendedMap['seat_$seatNum'] == true)) {
                                  isAttended = true;
                                }

                                sData['isAttended'] = isAttended;
                                sData['attended'] = isAttended;
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

                                            // 4. Search Bar & Class Filter Dropdown (Gambar 1 exact feature)
                                            ProctorSearchFilterBar(
                                              searchQuery: _searchQuery,
                                              selectedClassFilter: _selectedClassFilter,
                                              classSet: roomClassesSet,
                                              onSearchChanged: (val) => setState(() => _searchQuery = val),
                                              onClassFilterChanged: (val) => setState(() => _selectedClassFilter = val),
                                            ),
                                            const SizedBox(height: 20),

                                            // 5. Seating Grid Section Header & Legend Indicators
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Denah Bangku & Posisi Murid (Pola $gridColumns Kolom • $roomCapacity Bangku)',
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
  ),
);
  }
}
