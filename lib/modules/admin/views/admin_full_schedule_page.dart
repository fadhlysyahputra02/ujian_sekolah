import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AdminFullSchedulePage extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const AdminFullSchedulePage({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<AdminFullSchedulePage> createState() => _AdminFullSchedulePageState();
}

class _AdminFullSchedulePageState extends State<AdminFullSchedulePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _eventData;

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _timetable = [];
  List<Map<String, dynamic>> _seats = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _proctorList = [];
  Map<String, String> _proctorGrid = {};
  Map<String, String> _teacherMap = {}; // teacherId -> teacherName
  Map<String, String> _classMap = {}; // classId -> className
  Map<String, String> _subjectMap = {}; // subjectId -> subjectName

  // Search Query
  String _searchQuery = '';
  // Day Tab selection (-1: Semua Hari, 0: Hari 1, 1: Hari 2, ...)
  int _selectedDayTab = 0;

  @override
  void initState() {
    super.initState();
    _loadAllScheduleData();
  }

  Future<void> _loadAllScheduleData() async {
    setState(() => _isLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      final schoolRef = db.collection('schools').doc(widget.schoolId);
      final eventRef = schoolRef.collection('events').doc(widget.eventId);

      // 1. Fetch Event Doc
      final eventSnap = await eventRef.get();
      if (eventSnap.exists) {
        _eventData = eventSnap.data();
        
        // Extract proctorGrid from event doc
        if (_eventData!['proctorGrid'] is Map) {
          (_eventData!['proctorGrid'] as Map).forEach((k, v) {
            _proctorGrid[k.toString()] = v.toString();
          });
        }
        final rLayouts = _eventData!['roomLayouts'] as Map<String, dynamic>?;
        if (rLayouts != null && rLayouts['proctorGrid'] is Map) {
          (rLayouts['proctorGrid'] as Map).forEach((k, v) {
            _proctorGrid[k.toString()] = v.toString();
          });
        }
      }

      // 2. Fetch Teachers map from teachers & users collections
      try {
        final teacherSnap = await schoolRef.collection('teachers').get();
        for (var doc in teacherSnap.docs) {
          final data = doc.data();
          final name = (data['displayName'] ?? data['name'] ?? doc.id).toString();
          _teacherMap[doc.id] = name;
        }
      } catch (_) {}

      try {
        final userSnap = await schoolRef.collection('users').where('role', isEqualTo: 'teacher').get();
        for (var doc in userSnap.docs) {
          final data = doc.data();
          final name = (data['displayName'] ?? data['name'] ?? doc.id).toString();
          _teacherMap[doc.id] = name;
        }
      } catch (_) {}

      try {
        final classSnap = await schoolRef.collection('classes').get();
        for (var doc in classSnap.docs) {
          final data = doc.data();
          final name = (data['name'] ?? doc.id).toString();
          _classMap[doc.id] = name;
        }
      } catch (_) {}

      try {
        final subjectSnap = await schoolRef.collection('subjects').get();
        for (var doc in subjectSnap.docs) {
          final data = doc.data();
          final name = (data['name'] ?? doc.id).toString();
          _subjectMap[doc.id] = name;
        }
      } catch (_) {}

      // 3. Fetch Sessions
      try {
        final sessionSnap = await eventRef.collection('sessions').orderBy('order').get();
        _sessions = sessionSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
      } catch (_) {
        final sessionSnap = await eventRef.collection('sessions').get();
        _sessions = sessionSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
        _sessions.sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
      }

      if (_sessions.isEmpty && _eventData != null && _eventData!['sessions'] is List) {
        _sessions = (_eventData!['sessions'] as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
      }

      // 4. Fetch Timetable
      final timetableSnap = await eventRef.collection('timetable').get();
      _timetable = timetableSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      if (_timetable.isEmpty && _eventData != null && _eventData!['timetable'] is List) {
        _timetable = (_eventData!['timetable'] as List)
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList();
      }

      // 5. Fetch Proctors Subcollection
      try {
        final proctorSnap = await eventRef.collection('proctors').get();
        _proctorList = proctorSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
      } catch (_) {}

      // 6. Fetch Active Allocation & Seats & Proctor Grid
      final allocSnap = await eventRef.collection('allocations').orderBy('createdAt', descending: true).limit(1).get();
      if (allocSnap.docs.isNotEmpty) {
        final allocData = allocSnap.docs.first.data();
        final allocId = allocSnap.docs.first.id;

        // Proctor Grid from allocation layout
        final roomLayouts = allocData['roomLayouts'] as Map<String, dynamic>? ?? {};
        final pGrid = roomLayouts['proctorGrid'] as Map<String, dynamic>? ?? {};
        pGrid.forEach((k, v) {
          _proctorGrid[k.toString()] = v.toString();
        });

        // Seats
        final seatSnap = await eventRef.collection('allocations').doc(allocId).collection('seats').get();
        _seats = seatSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();

        // Extract Unique Rooms
        final roomMap = <String, Map<String, dynamic>>{};
        for (var seat in _seats) {
          final rId = (seat['roomId'] ?? seat['roomCode'] ?? seat['roomName'] ?? '').toString();
          final rName = (seat['roomName'] ?? seat['roomCode'] ?? rId).toString();
          final rCode = (seat['roomCode'] ?? rName).toString();
          if (rId.isNotEmpty) {
            roomMap.putIfAbsent(rId, () => {'id': rId, 'name': rName, 'code': rCode});
          }
        }
        _rooms = roomMap.values.toList();
      }

      // Fallback rooms from event doc
      if (_rooms.isEmpty && _eventData != null && _eventData!['rooms'] is List) {
        final rList = _eventData!['rooms'] as List;
        _rooms = rList.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }

    } catch (e, stack) {
      debugPrint("Error loading full schedule data: $e\n$stack");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isClassInRoom(String cId, String cName, Set<String> roomClassSet) {
    if (roomClassSet.isEmpty) return true;
    final cleanId = cId.trim().toLowerCase().replaceAll(' ', '');
    final cleanName = cName.trim().toLowerCase().replaceAll(' ', '');

    for (var rc in roomClassSet) {
      final cleanRc = rc.trim().toLowerCase().replaceAll(' ', '');
      if (cleanRc.isEmpty) continue;
      if (cleanRc == cleanId || cleanRc == cleanName) return true;
      if (cleanName.isNotEmpty && (cleanName == cleanRc || cleanName.contains(cleanRc) || cleanRc.contains(cleanName))) return true;
      if (cleanId.isNotEmpty && (cleanId == cleanRc || cleanId.contains(cleanRc) || cleanRc.contains(cleanId))) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _buildSimpleScheduleRows() {
    final List<Map<String, dynamic>> result = [];

    // 1. Calculate daysCount from startDate & endDate
    DateTime? startDt;
    DateTime? endDt;
    if (_eventData != null) {
      final sd = _eventData!['startDate'];
      final ed = _eventData!['endDate'];
      if (sd != null) {
        startDt = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
      }
      if (ed != null) {
        endDt = ed is Timestamp ? ed.toDate() : (ed is String ? DateTime.tryParse(ed) : null);
      }
    }

    int calculatedDaysCount = 1;
    if (startDt != null && endDt != null) {
      final diff = endDt.difference(startDt).inDays + 1;
      if (diff > 0) calculatedDaysCount = diff;
    }

    // 2. Scan max dayIndex in _timetable & _proctorGrid
    int maxDayIndex = 0;
    for (var t in _timetable) {
      final tsId = (t['sessionId'] ?? '').toString();
      if (tsId.startsWith('day_')) {
        final parts = tsId.split('_');
        if (parts.length >= 2) {
          final d = int.tryParse(parts[1]);
          if (d != null && d > maxDayIndex) maxDayIndex = d;
        }
      }
      final tDay = (t['dayIndex'] as num?)?.toInt();
      if (tDay != null && tDay > maxDayIndex) maxDayIndex = tDay;
    }

    for (var k in _proctorGrid.keys) {
      if (k.startsWith('day_')) {
        final parts = k.split('_');
        if (parts.length >= 2) {
          final d = int.tryParse(parts[1]);
          if (d != null && d > maxDayIndex) maxDayIndex = d;
        }
      }
    }

    final int totalDays = (maxDayIndex + 1) > calculatedDaysCount
        ? (maxDayIndex + 1)
        : calculatedDaysCount;

    // 3. Determine sessionsPerDay & Session Resolver
    int sessionsPerDay = 0;
    for (var s in _sessions) {
      final tempId = (s['tempId'] ?? '').toString();
      if (tempId.startsWith('day_')) {
        final parts = tempId.split('_');
        if (parts.length >= 4 && parts[1] == '0') {
          sessionsPerDay++;
        }
      }
    }
    if (sessionsPerDay == 0) {
      final evSessions = _eventData?['sessions'] as List?;
      if (evSessions != null && evSessions.isNotEmpty) {
        sessionsPerDay = evSessions.length;
      } else {
        sessionsPerDay = 2;
      }
    }

    Map<String, dynamic> getSessionForSlot(int dIdx, int sIdx) {
      final targetKey = 'day_${dIdx}_session_$sIdx';
      for (var s in _sessions) {
        if ((s['tempId'] ?? s['id'] ?? '').toString() == targetKey) return s;
      }
      final targetOrder = dIdx * sessionsPerDay + sIdx + 1;
      for (var s in _sessions) {
        if ((s['order'] as num?)?.toInt() == targetOrder) return s;
      }
      final idx = dIdx * sessionsPerDay + sIdx;
      if (idx < _sessions.length) return _sessions[idx];
      if (sIdx < _sessions.length) return _sessions[sIdx];
      return {};
    }

    int globalRowIdx = 0;

    for (int dayIdx = 0; dayIdx < totalDays; dayIdx++) {
      for (int sessIdx = 0; sessIdx < sessionsPerDay; sessIdx++) {
        final sess = getSessionForSlot(dayIdx, sessIdx);
        final sId = (sess['id'] ?? 'day_${dayIdx}_session_$sessIdx').toString();
        final sName = (sess['name'] ?? sess['sessionName'] ?? 'Sesi ${sessIdx + 1}').toString();
        final sStart = (sess['startTime'] ?? '').toString();
        final sEnd = (sess['endTime'] ?? '').toString();
        final timeLabel = (sStart.isNotEmpty && sEnd.isNotEmpty) ? '$sStart - $sEnd' : (sStart.isNotEmpty ? sStart : 'Jam Sesi');

        // Resolve Date Label for Day dayIdx
        String dateStr = '';
        final dVal = sess['date'] ?? sess['startDate'];
        if (dVal is Timestamp) {
          dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dVal.toDate());
        } else if (dVal is String && dVal.isNotEmpty) {
          final dt = DateTime.tryParse(dVal);
          if (dt != null) dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dt);
        }

        if (dateStr.isEmpty && startDt != null) {
          final dayDate = startDt.add(Duration(days: dayIdx));
          dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dayDate);
        }

        if (dateStr.isEmpty) {
          dateStr = 'Hari ${dayIdx + 1}';
        }

        // Match timetable entries for this (dayIdx, sessIdx)
        final String daySessKey = 'day_${dayIdx}_session_$sessIdx';
        final List<Map<String, dynamic>> matchingTimetable = _timetable.where((t) {
          final tsId = (t['sessionId'] ?? '').toString();
          final tDay = (t['dayIndex'] as num?)?.toInt();
          final tSlot = (t['slotIndex'] as num?)?.toInt();

          // 1. Exact match on 'day_D_session_S'
          if (tsId == daySessKey) return true;

          // 2. Match on explicit dayIndex and slotIndex
          if (tDay != null && tSlot != null) {
            return tDay == dayIdx && tSlot == sessIdx;
          }

          // 3. If tsId starts with 'day_', check day index in string
          if (tsId.startsWith('day_')) {
            final parts = tsId.split('_');
            if (parts.length >= 4) {
              final d = int.tryParse(parts[1]);
              final s = int.tryParse(parts[3]);
              if (d != null && s != null) {
                return d == dayIdx && s == sessIdx;
              }
            }
          }

          // 4. Match if tsId equals session ID (sId) or session's tempId
          if (sId.isNotEmpty && tsId == sId) return true;
          final tempIdStr = (sess['tempId'] ?? '').toString();
          if (tempIdStr.isNotEmpty && tsId == tempIdStr) return true;

          return false;
        }).toList();

        final schedGrid = _eventData?['scheduleGrid'] as Map? ?? _eventData?['draftState']?['scheduleGrid'] as Map? ?? _eventData?['draftState']?['step6']?['scheduleGrid'] as Map? ?? {};
        final gridSubjects = schedGrid[daySessKey] as List? ?? schedGrid[sId] as List?;

        if (matchingTimetable.isEmpty && (gridSubjects == null || gridSubjects.isEmpty) && _timetable.isNotEmpty) {
          continue; // Skip slots that have no scheduled subjects in timetable or scheduleGrid
        }

        // Active Rooms
        final activeRooms = _rooms.isNotEmpty ? _rooms : [{'id': 'R1', 'name': 'Ruang 01', 'code': '01'}];

        for (var rMap in activeRooms) {
          final rId = (rMap['id'] ?? rMap['code'] ?? rMap['name'] ?? '').toString();
          final rName = (rMap['name'] ?? rMap['code'] ?? rId).toString();
          final rCode = (rMap['code'] ?? rName).toString();

          // Resolve Classes in this room for this session (use seats data which has actual room assignments)
          final Set<String> roomClassSet = {};
          for (var s in _seats) {
            final seatRoom = (s['roomId'] ?? s['roomName'] ?? s['roomCode'] ?? '').toString();
            if (seatRoom == rId || seatRoom == rName || seatRoom == rCode) {
              final cName = (s['className'] ?? s['classId'] ?? '').toString().trim();
              if (cName.isNotEmpty) roomClassSet.add(cName);
            }
          }
          // Fallback to timetable only if no seats data exists at all
          if (roomClassSet.isEmpty && _seats.isEmpty) {
            for (var t in matchingTimetable) {
              final cId = (t['classId'] ?? '').toString().trim();
              final cName = (t['className'] ?? '').toString().trim().isNotEmpty
                  ? t['className'].toString().trim()
                  : (_classMap[cId] ?? cId);
              if (cName.isNotEmpty) roomClassSet.add(cName);
            }
          }

          // Resolve Mapel in this session (filter specifically for classes in this room)
          final Set<String> subjectSet = {};
          for (var t in matchingTimetable) {
            final cId = (t['classId'] ?? '').toString().trim();
            final cName = (t['className'] ?? '').toString().trim().isNotEmpty
                ? t['className'].toString().trim()
                : (_classMap[cId] ?? cId);

            if (_isClassInRoom(cId, cName, roomClassSet)) {
              final sId = (t['subjectId'] ?? '').toString().trim();
              final subName = (t['subjectName'] ?? '').toString().trim().isNotEmpty
                  ? t['subjectName'].toString().trim()
                  : (_subjectMap[sId] ?? sId);
              if (subName.isNotEmpty) subjectSet.add(subName);
            }
          }

          if (subjectSet.isEmpty && roomClassSet.isEmpty) {
            for (var t in matchingTimetable) {
              final sId = (t['subjectId'] ?? '').toString().trim();
              final subName = (t['subjectName'] ?? '').toString().trim().isNotEmpty
                  ? t['subjectName'].toString().trim()
                  : (_subjectMap[sId] ?? sId);
              if (subName.isNotEmpty) subjectSet.add(subName);
            }
          }

          if (subjectSet.isEmpty && gridSubjects != null) {
            final subjectsList = _eventData?['subjects'] as List? ?? _eventData?['draftState']?['subjects'] as List? ?? [];
            for (var subId in gridSubjects) {
              String foundName = subId.toString();
              for (var sItem in subjectsList) {
                if (sItem is Map && (sItem['id'] == subId || sItem['code'] == subId || sItem['name'] == subId)) {
                  foundName = sItem['name'] ?? subId.toString();
                  break;
                }
              }
              if (foundName.isNotEmpty) subjectSet.add(foundName);
            }
          }

          // Resolve Proctor for this day/session/room
          String proctorName = '-';

          // 1. Try from _proctorList (subcollection proctors)
          for (var p in _proctorList) {
            final pSId = (p['sessionId'] ?? '').toString();
            final pRId = (p['roomId'] ?? '').toString();
            if ((pSId == sId || pSId == daySessKey) && (pRId == rId || pRId == rCode || pRId == rName)) {
              final tId = (p['teacherId'] ?? p['teacherName'] ?? '').toString();
              proctorName = p['teacherName'] ?? _teacherMap[tId] ?? tId;
              break;
            }
          }

          // 2. Try from _proctorGrid
          if (proctorName == '-') {
            final keysToTry = [
              'day_${dayIdx}_session_${sessIdx}_room_$rId',
              'day_${dayIdx}_session_${sessIdx}_room_$rCode',
              'day_${dayIdx}_session_${sessIdx}_room_$rName',
              'day_${dayIdx}_session_0_room_$rId',
              'day_${dayIdx}_session_0_room_$rCode',
              'day_${dayIdx}_session_0_room_$rName',
            ];
            for (final k in keysToTry) {
              if (_proctorGrid.containsKey(k)) {
                final pVal = _proctorGrid[k]!;
                proctorName = _teacherMap[pVal] ?? pVal;
                break;
              }
            }
          }

          // Resolve Guru Pembuat Soal in this session (filter specifically for classes in this room)
          final Map<String, Set<String>> teacherSubjectToClasses = {};
          for (var t in matchingTimetable) {
            final cId = (t['classId'] ?? '').toString().trim();
            final cName = (t['className'] ?? '').toString().trim().isNotEmpty
                ? t['className'].toString().trim()
                : (_classMap[cId] ?? cId);
            if (_isClassInRoom(cId, cName, roomClassSet)) {
              final teachName = (t['teacherName'] ?? '').toString().trim();
              final sId = (t['subjectId'] ?? '').toString().trim();
              final subName = (t['subjectName'] ?? '').toString().trim().isNotEmpty
                  ? t['subjectName'].toString().trim()
                  : (_subjectMap[sId] ?? sId);
              if (teachName.isNotEmpty && subName.isNotEmpty) {
                final key = '$teachName|$subName';
                teacherSubjectToClasses.putIfAbsent(key, () => {}).add(cName.isNotEmpty ? cName : cId);
              }
            }
          }
          if (teacherSubjectToClasses.isEmpty && roomClassSet.isEmpty) {
            for (var t in matchingTimetable) {
              final teachName = (t['teacherName'] ?? '').toString().trim();
              final sId = (t['subjectId'] ?? '').toString().trim();
              final subName = (t['subjectName'] ?? '').toString().trim().isNotEmpty
                  ? t['subjectName'].toString().trim()
                  : (_subjectMap[sId] ?? sId);
              final cId = (t['classId'] ?? '').toString().trim();
              final cName = (t['className'] ?? '').toString().trim().isNotEmpty
                  ? t['className'].toString().trim()
                  : (_classMap[cId] ?? cId);
              if (teachName.isNotEmpty && subName.isNotEmpty) {
                final key = '$teachName|$subName';
                teacherSubjectToClasses.putIfAbsent(key, () => {}).add(cName.isNotEmpty ? cName : cId);
              }
            }
          }

          final List<String> teacherLabels = [];
          final Set<String> addedTeacherSubjects = {};
          teacherSubjectToClasses.forEach((key, classes) {
            final parts = key.split('|');
            final teachName = parts[0];
            final subName = parts[1];
            final uniqueKey = '$teachName|$subName';
            if (!addedTeacherSubjects.contains(uniqueKey)) {
              addedTeacherSubjects.add(uniqueKey);
              teacherLabels.add('$teachName ($subName)');
            }
          });

          result.add({
            'rowIndex': globalRowIdx++,
            'dayIndex': dayIdx,
            'sessionIndex': sessIdx,
            'dateStr': dateStr,
            'sessionName': sName,
            'sessionTime': timeLabel,
            'roomName': rName,
            'classesList': roomClassSet.isNotEmpty ? roomClassSet.join(', ') : '-',
            'mapelList': subjectSet.isNotEmpty ? subjectSet.join(', ') : '-',
            'guruSoalList': teacherLabels.isNotEmpty ? teacherLabels.join(', ') : '-',
            'pengawasList': proctorName.isNotEmpty ? proctorName : '-',
          });
        }
      }
    }

    return result;
  }

  Widget _buildDayTabsBar(List<Map<String, dynamic>> dayTabs) {
    if (dayTabs.length <= 2) return const SizedBox.shrink(); // Don't show tabs if only 1 day exists

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 20),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dayTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final tab = dayTabs[index];
          final dIdx = tab['dayIndex'] as int;
          final isSelected = _selectedDayTab == dIdx;

          String label = tab['label'] as String;
          final dateStr = tab['dateStr'] as String;
          if (dateStr.isNotEmpty && dIdx != -1) {
            label = '$label • $dateStr';
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedDayTab = dIdx;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF4338CA) : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        dIdx == -1 ? Icons.calendar_view_day_rounded : Icons.today_rounded,
                        size: 16,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text('Memuat Jadwal Ujian...', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
        ),
      );
    }

    final allRows = _buildSimpleScheduleRows();

    // Collect Day Tabs
    final List<Map<String, dynamic>> dayTabsList = [
      {'dayIndex': -1, 'label': 'Semua Hari', 'dateStr': ''}
    ];
    final Set<int> addedDays = {};
    for (var r in allRows) {
      final dIdx = (r['dayIndex'] as num?)?.toInt() ?? 0;
      final dStr = (r['dateStr'] as String? ?? '');
      if (!addedDays.contains(dIdx)) {
        addedDays.add(dIdx);
        dayTabsList.add({
          'dayIndex': dIdx,
          'label': 'Hari ${dIdx + 1}',
          'dateStr': dStr,
        });
      }
    }

    // Filter rows by Day Tab & Search Query
    final filteredRows = allRows.where((row) {
      // 1. Day Tab Filter
      if (_selectedDayTab != -1) {
        final dIdx = (row['dayIndex'] as num?)?.toInt() ?? 0;
        if (dIdx != _selectedDayTab) return false;
      }

      // 2. Search Query Filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return (row['dateStr'] as String).toLowerCase().contains(q) ||
            (row['sessionName'] as String).toLowerCase().contains(q) ||
            (row['roomName'] as String).toLowerCase().contains(q) ||
            (row['classesList'] as String).toLowerCase().contains(q) ||
            (row['mapelList'] as String).toLowerCase().contains(q) ||
            (row['guruSoalList'] as String).toLowerCase().contains(q) ||
            (row['pengawasList'] as String).toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.eventName,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              'Jadwal Lengkap Pelaksanaan Ujian Sekolah',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _printOrExportPdf(filteredRows),
            icon: const Icon(Icons.print_rounded, size: 16),
            label: Text('Cetak / PDF', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Input Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Cari ruangan, kelas, mapel, guru, atau pengawas...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                      onPressed: () => setState(() => _searchQuery = ''),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Horizontal Day Tab Filter Bar
            _buildDayTabsBar(dayTabsList),

            // Simple Spreadsheet-style Table matching requested structure
            _buildSimpleScheduleTable(filteredRows),
          ],
        ),
      ),
    );
  }

  /// Simple Clean Spreadsheet-style Table matching requested format:
  /// | Hari | Sesi | Jam | Ruangan | Kelas | Mapel | Pengawas |
  /// Stretches full-width (100%) & Merges Hari cell for identical days.
  Widget _buildSimpleScheduleTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            const Icon(Icons.event_busy_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              'Belum Ada Jadwal Ditemukan',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columnSpacing: 18,
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                  headingTextStyle: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 80,
                  dividerThickness: 1,
                  border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 0.8),
                  columns: const [
                    DataColumn(label: SizedBox(width: 80, child: Text('Sesi'))),
                    DataColumn(label: SizedBox(width: 110, child: Text('Jam'))),
                    DataColumn(label: SizedBox(width: 100, child: Text('Ruangan'))),
                    DataColumn(label: SizedBox(width: 160, child: Text('Kelas'))),
                    DataColumn(label: SizedBox(width: 200, child: Text('Mapel'))),
                    DataColumn(label: SizedBox(width: 260, child: Text('Guru Pembuat Soal'))),
                    DataColumn(label: SizedBox(width: 180, child: Text('Pengawas'))),
                  ],
                  rows: rows.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;

                    return DataRow(
                      color: WidgetStateProperty.all(idx % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC)),
                      cells: [
                        // Sesi
                        DataCell(
                          SizedBox(
                            width: 80,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFC7D2FE)),
                              ),
                              child: Text(
                                row['sessionName'],
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: const Color(0xFF3730A3),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        // Jam
                        DataCell(
                          SizedBox(
                            width: 110,
                            child: Text(
                              row['sessionTime'],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF334155),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Ruangan
                        DataCell(
                          SizedBox(
                            width: 100,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Text(
                                row['roomName'],
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: const Color(0xFF92400E),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        // Kelas
                        DataCell(
                          SizedBox(
                            width: 160,
                            child: Text(
                              row['classesList'],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF0284C7),
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Mapel
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Text(
                              row['mapelList'],
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Guru Pembuat Soal
                        DataCell(
                          SizedBox(
                            width: 260,
                            child: Text(
                              row['guruSoalList'] ?? '-',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF475569),
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Pengawas
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(
                              row['pengawasList'],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF059669),
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Print or Export Schedule PDF Document matching A4 Landscape format perfectly
  Future<void> _printOrExportPdf(List<Map<String, dynamic>> rows) async {
    final doc = pw.Document();

    String activeDayText = 'Semua Hari';
    if (_selectedDayTab >= 0 && rows.isNotEmpty) {
      final firstRow = rows.first;
      final dateStr = (firstRow['dateStr'] ?? '').toString();
      activeDayText = 'Hari ${_selectedDayTab + 1}${dateStr.isNotEmpty ? " • $dateStr" : ""}';
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'JADWAL PELAKSANAAN UJIAN SEKOLAH',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Event: ${widget.eventName}  |  $activeDayText',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Halaman ${context.pageNumber} dari ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.Table.fromTextArray(
              headers: ['Sesi', 'Jam', 'Ruangan', 'Kelas', 'Mapel', 'Guru Pembuat Soal', 'Pengawas'],
              data: rows.map((r) {
                return [
                  r['sessionName'] ?? '-',
                  r['sessionTime'] ?? '-',
                  r['roomName'] ?? '-',
                  r['classesList'] ?? '-',
                  r['mapelList'] ?? '-',
                  r['guruSoalList'] ?? '-',
                  r['pengawasList'] ?? '-',
                ];
              }).toList(),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.9), // Sesi
                1: const pw.FlexColumnWidth(1.1), // Jam
                2: const pw.FlexColumnWidth(1.0), // Ruangan
                3: const pw.FlexColumnWidth(1.5), // Kelas
                4: const pw.FlexColumnWidth(1.8), // Mapel
                5: const pw.FlexColumnWidth(2.3), // Guru Pembuat Soal
                6: const pw.FlexColumnWidth(1.6), // Pengawas
              },
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9.5),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Jadwal_Ujian_${widget.eventName}.pdf',
      format: PdfPageFormat.a4.landscape,
    );
  }
}
