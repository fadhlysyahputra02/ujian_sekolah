import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sys_exam_school/core/services/auth_service.dart';
import 'package:sys_exam_school/modules/teacher/views/teacher_proctor_room_page.dart';

class AdminRoomControlPage extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const AdminRoomControlPage({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<AdminRoomControlPage> createState() => _AdminRoomControlPageState();
}

class _DayTabInfo {
  final int dayIndex;
  final String label;
  final String dateStr;
  final String shortDateStr;
  final DateTime? date;

  _DayTabInfo({
    required this.dayIndex,
    required this.label,
    required this.dateStr,
    required this.shortDateStr,
    this.date,
  });
}

class _SessionTabInfo {
  final int sessionIndex;
  final String id;
  final String name;
  final String startTime;
  final String endTime;
  final String timeRange;

  _SessionTabInfo({
    required this.sessionIndex,
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.timeRange,
  });
}

class _AdminRoomControlPageState extends State<AdminRoomControlPage> {
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _eventData;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _seats = [];
  List<Map<String, dynamic>> _timetable = [];
  List<Map<String, dynamic>> _proctorList = [];
  final Map<String, String> _proctorGrid = {};
  final Map<String, String> _teacherMap = {};
  final Map<String, String> _classMap = {};
  final Map<String, String> _subjectMap = {};

  // Real-time collections
  StreamSubscription<QuerySnapshot>? _attendancesSub;
  StreamSubscription<QuerySnapshot>? _submissionsSub;
  StreamSubscription<QuerySnapshot>? _realtimeSub;

  List<Map<String, dynamic>> _attendances = [];
  List<Map<String, dynamic>> _submissions = [];
  List<Map<String, dynamic>> _realtimeControl = [];

  int _selectedDayIndex = 0;
  int _selectedSessionIndex = 0;

  List<_DayTabInfo> _dayTabs = [];
  List<_SessionTabInfo> _currentSessionTabs = [];

  // Data mapping date string -> list of sessions
  final Map<String, List<Map<String, dynamic>>> _dateGroups = {};
  final List<String> _sortedDates = [];

  @override
  void initState() {
    super.initState();
    _loadEventData();
  }

  @override
  void dispose() {
    _attendancesSub?.cancel();
    _submissionsSub?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }

  String _getNamaHari(int weekday) {
    switch (weekday) {
      case 1:
        return 'Senin';
      case 2:
        return 'Selasa';
      case 3:
        return 'Rabu';
      case 4:
        return 'Kamis';
      case 5:
        return 'Jumat';
      case 6:
        return 'Sabtu';
      case 7:
        return 'Minggu';
      default:
        return '';
    }
  }

  String _getNamaBulan(int month) {
    const months = [
      '',
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    if (month >= 1 && month <= 12) return months[month];
    return '';
  }

  String _getNamaBulanSingkat(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    if (month >= 1 && month <= 12) return months[month];
    return '';
  }

  Future<void> _loadEventData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final effectiveSchoolId = widget.schoolId.isNotEmpty
          ? widget.schoolId
          : (auth.schoolId ?? '');

      if (effectiveSchoolId.isEmpty) {
        throw Exception('ID Sekolah tidak ditemukan.');
      }

      final db = FirebaseFirestore.instance;
      final schoolRef = db.collection('schools').doc(effectiveSchoolId);
      final eventRef = schoolRef.collection('events').doc(widget.eventId);

      // 1. Ambil dokumen event
      final eventSnap = await eventRef.get();
      if (!eventSnap.exists) {
        throw Exception('Event ujian tidak ditemukan.');
      }
      _eventData = eventSnap.data();

      // Proctor grid dari event doc
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

      // 2. Ambil master guru, kelas, mapel
      try {
        final teacherSnap = await schoolRef.collection('teachers').get();
        for (var doc in teacherSnap.docs) {
          final data = doc.data();
          final name =
              (data['displayName'] ?? data['name'] ?? doc.id).toString();
          _teacherMap[doc.id] = name;
        }
      } catch (_) {}

      try {
        final userSnap = await schoolRef
            .collection('users')
            .where('role', isEqualTo: 'teacher')
            .get();
        for (var doc in userSnap.docs) {
          final data = doc.data();
          final name =
              (data['displayName'] ?? data['name'] ?? doc.id).toString();
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
          final code = (data['code'] ?? '').toString();
          if (code.isNotEmpty) {
            _subjectMap[code] = name;
          }
        }
      } catch (_) {}

      // Ambil subjects juga dari event doc
      if (_eventData != null) {
        final evSubjects = _eventData!['subjects'] ??
            _eventData!['draftState']?['subjects'] ??
            _eventData!['draftState']?['step2']?['subjects'];
        if (evSubjects is List) {
          for (var s in evSubjects) {
            if (s is Map) {
              final sId = (s['id'] ?? s['docId'] ?? '').toString();
              final sName = (s['name'] ?? s['subjectName'] ?? '').toString();
              final sCode = (s['code'] ?? '').toString();
              if (sId.isNotEmpty && sName.isNotEmpty) {
                _subjectMap[sId] = sName;
              }
              if (sCode.isNotEmpty && sName.isNotEmpty) {
                _subjectMap[sCode] = sName;
              }
            }
          }
        }
      }

      // 3. Ambil subkoleksi sesi
      try {
        final sessionSnap =
            await eventRef.collection('sessions').orderBy('order').get();
        _sessions = sessionSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
      } catch (_) {
        try {
          final sessionSnap = await eventRef.collection('sessions').get();
          _sessions = sessionSnap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
          _sessions.sort((a, b) => ((a['order'] as num?) ?? 0)
              .compareTo((b['order'] as num?) ?? 0));
        } catch (_) {}
      }

      if (_sessions.isEmpty &&
          _eventData != null &&
          _eventData!['sessions'] is List) {
        _sessions = (_eventData!['sessions'] as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
      }

      // 4. Ambil timetable
      final timetableSnap = await eventRef.collection('timetable').get();
      _timetable = timetableSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      if (_timetable.isEmpty && _eventData != null) {
        final rawTt = _eventData!['timetable'] ??
            _eventData!['draftState']?['timetable'] ??
            _eventData!['draftState']?['step3']?['timetable'];
        if (rawTt is List) {
          _timetable =
              rawTt.map((t) => Map<String, dynamic>.from(t as Map)).toList();
        }
      }

      // 5. Ambil pengawas dari subkoleksi proctors
      try {
        final proctorSnap = await eventRef.collection('proctors').get();
        _proctorList = proctorSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
      } catch (_) {}

      // 6. Ambil alokasi ruangan & seats aktif
      final allocSnap = await eventRef
          .collection('allocations')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (allocSnap.docs.isNotEmpty) {
        final allocData = allocSnap.docs.first.data();
        final allocId = allocSnap.docs.first.id;

        final roomLayouts =
            allocData['roomLayouts'] as Map<String, dynamic>? ?? {};
        final pGrid = roomLayouts['proctorGrid'] as Map<String, dynamic>? ?? {};
        pGrid.forEach((k, v) {
          _proctorGrid[k.toString()] = v.toString();
        });

        // Seats
        final seatSnap = await eventRef
            .collection('allocations')
            .doc(allocId)
            .collection('seats')
            .get();
        _seats = seatSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();

        // Ambil data ruangan unik dari seats
        final roomMap = <String, Map<String, dynamic>>{};
        for (var seat in _seats) {
          final rId = (seat['roomId'] ??
                  seat['roomCode'] ??
                  seat['roomName'] ??
                  '')
              .toString();
          final rName =
              (seat['roomName'] ?? seat['roomCode'] ?? rId).toString();
          final rCode = (seat['roomCode'] ?? rName).toString();
          if (rId.isNotEmpty) {
            roomMap.putIfAbsent(rId, () => {
                  'id': rId,
                  'name': rName,
                  'code': rCode,
                });
          }
        }
        _rooms = roomMap.values.toList();
      }

      // Fallback data ruangan dari event doc
      if (_rooms.isEmpty && _eventData != null) {
        final rList = _eventData!['rooms'] ??
            _eventData!['draftState']?['rooms'] ??
            _eventData!['draftState']?['step4']?['rooms'];
        if (rList is List) {
          _rooms =
              rList.map((r) => Map<String, dynamic>.from(r as Map)).toList();
        }
      }

      // Fallback data ruangan dari sekolah
      if (_rooms.isEmpty) {
        try {
          final roomSnap = await schoolRef.collection('rooms').get();
          _rooms = roomSnap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        } catch (_) {}
      }

      // 7. Setup Live Streams untuk Kehadiran Realtime
      _initAttendanceStreams(eventRef);

      // Hitung tab hari dan tab sesi
      _buildDayAndSessionTabs();
    } catch (e, stack) {
      debugPrint('Error loading room control data: $e\n$stack');
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _initAttendanceStreams(DocumentReference eventRef) {
    _attendancesSub?.cancel();
    _attendancesSub =
        eventRef.collection('attendances').snapshots().listen((snap) {
      if (mounted) {
        setState(() {
          _attendances = snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        });
      }
    });

    _submissionsSub?.cancel();
    _submissionsSub =
        eventRef.collection('submissions').snapshots().listen((snap) {
      if (mounted) {
        setState(() {
          _submissions = snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        });
      }
    });

    _realtimeSub?.cancel();
    _realtimeSub =
        eventRef.collection('realtime_control').snapshots().listen((snap) {
      if (mounted) {
        setState(() {
          _realtimeControl = snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        });
      }
    });
  }

  String _extractGrade(String str) {
    final lower = str.toLowerCase().replaceAll(' ', '');
    if (lower.startsWith('xii') || lower.contains('12') || lower.contains('xii')) return '12';
    if (lower.startsWith('xi') || lower.contains('11') || lower.contains('xi')) return '11';
    if (lower.startsWith('x') || lower.contains('10') || lower.contains('x')) return '10';
    return '';
  }

  bool _isClassMatched(Set<String> targetClasses, Set<String> roomClasses) {
    if (roomClasses.isEmpty || targetClasses.isEmpty) return false;

    for (var tc in targetClasses) {
      if (tc.trim().isEmpty) continue;
      final cleanTc = tc.trim().toLowerCase().replaceAll(' ', '');
      final resolvedTc = (_classMap[tc] ?? _classMap[tc.trim()] ?? '').trim().toLowerCase().replaceAll(' ', '');

      for (var rc in roomClasses) {
        if (rc.trim().isEmpty) continue;
        final cleanRc = rc.trim().toLowerCase().replaceAll(' ', '');
        final resolvedRc = (_classMap[rc] ?? _classMap[rc.trim()] ?? '').trim().toLowerCase().replaceAll(' ', '');

        if (cleanRc.isEmpty) continue;

        // 1. Exact string match on raw or resolved
        if (cleanTc == cleanRc) return true;
        if (resolvedTc.isNotEmpty && resolvedTc == cleanRc) return true;
        if (resolvedRc.isNotEmpty && cleanTc == resolvedRc) return true;
        if (resolvedTc.isNotEmpty && resolvedRc.isNotEmpty && resolvedTc == resolvedRc) return true;

        // 2. Avoid major stream/grade conflicts before checking substring
        final bool tcIsIpa = cleanTc.contains('ipa') || resolvedTc.contains('ipa');
        final bool tcIsIps = cleanTc.contains('ips') || resolvedTc.contains('ips');
        final bool rcIsIpa = cleanRc.contains('ipa') || resolvedRc.contains('ipa');
        final bool rcIsIps = cleanRc.contains('ips') || resolvedRc.contains('ips');

        if ((tcIsIpa && rcIsIps) || (tcIsIps && rcIsIpa)) {
          continue; // Incompatible majors (IPA vs IPS)
        }

        // Check grade conflicts (X vs XI vs XII)
        final String tcGrade = _extractGrade(cleanTc.isNotEmpty ? cleanTc : resolvedTc);
        final String rcGrade = _extractGrade(cleanRc.isNotEmpty ? cleanRc : resolvedRc);
        if (tcGrade.isNotEmpty && rcGrade.isNotEmpty && tcGrade != rcGrade) {
          continue; // Incompatible grades (e.g. 10 vs 11 vs 12)
        }

        // 3. Substring match only if long enough (>= 3 chars)
        final String matchTc = resolvedTc.isNotEmpty ? resolvedTc : cleanTc;
        final String matchRc = resolvedRc.isNotEmpty ? resolvedRc : cleanRc;
        if (matchTc.length >= 3 && matchRc.length >= 3) {
          if (matchTc == matchRc) return true;
          if (matchRc.contains(matchTc) || matchTc.contains(matchRc)) return true;
        }
      }
    }
    return false;
  }

  bool _isSubjectForRoomClasses(String sId, String sName, Set<String> roomClasses, List<Map<String, dynamic>> timetableList) {
    if (roomClasses.isEmpty) return true;
    final cleanSId = sId.toLowerCase().trim();
    final cleanSName = sName.toLowerCase().trim();

    bool foundInTimetable = false;
    for (var t in timetableList) {
      final tSubId = (t['subjectId'] ?? t['id'] ?? '').toString().toLowerCase().trim();
      final tSubName = (t['subjectName'] ?? t['subject'] ?? '').toString().toLowerCase().trim();

      if ((cleanSId.isNotEmpty && tSubId == cleanSId) || (cleanSName.isNotEmpty && tSubName == cleanSName)) {
        foundInTimetable = true;
        final Set<String> tClasses = {};
        final rawClassIds = t['classIds'] as List? ?? t['classNames'] as List? ?? t['classes'] as List? ?? t['targetClasses'] as List?;
        if (rawClassIds != null) {
          for (var c in rawClassIds) {
            if (c != null && c.toString().trim().isNotEmpty) tClasses.add(c.toString().trim());
          }
        }
        final singleCId = (t['classId'] ?? '').toString().trim();
        final singleCName = (t['className'] ?? '').toString().trim();
        if (singleCId.isNotEmpty) tClasses.add(singleCId);
        if (singleCName.isNotEmpty) tClasses.add(singleCName);

        if (_isClassMatched(tClasses, roomClasses)) {
          return true;
        }
      }
    }

    if (foundInTimetable) {
      return false;
    }

    return true;
  }

  void _buildDayAndSessionTabs() {
    _dateGroups.clear();
    _sortedDates.clear();

    // 1. Group sessions by date jika ada field date/startDate pada sesi
    for (var s in _sessions) {
      final dStr = (s['date'] ?? s['startDate'] ?? '').toString();
      if (dStr.isNotEmpty) {
        _dateGroups.putIfAbsent(dStr, () => []).add(s);
      }
    }
    for (var k in _dateGroups.keys) {
      _dateGroups[k]!.sort((a, b) {
        final oA = (a['order'] as num?) ?? 0;
        final oB = (b['order'] as num?) ?? 0;
        if (oA != oB) return oA.compareTo(oB);
        final stA = (a['startTime'] ?? '').toString();
        final stB = (b['startTime'] ?? '').toString();
        return stA.compareTo(stB);
      });
    }
    _sortedDates.addAll(_dateGroups.keys.toList()..sort());

    DateTime? startDt;
    DateTime? endDt;

    if (_eventData != null) {
      final sd = _eventData!['startDate'];
      final ed = _eventData!['endDate'];
      if (sd != null) {
        startDt = sd is Timestamp
            ? sd.toDate()
            : (sd is String ? DateTime.tryParse(sd) : null);
      }
      if (ed != null) {
        endDt = ed is Timestamp
            ? ed.toDate()
            : (ed is String ? DateTime.tryParse(ed) : null);
      }
    }

    final List<_DayTabInfo> generatedDays = [];

    if (_sortedDates.isNotEmpty) {
      // Jika sesi memiliki tanggal eksplisit
      for (int i = 0; i < _sortedDates.length; i++) {
        final dateKey = _sortedDates[i];
        final dt = DateTime.tryParse(dateKey) ??
            startDt?.add(Duration(days: i));

        String namaHari = '';
        String namaBulan = '';
        String shortDate = '';
        String fullDateStr = dateKey;

        if (dt != null) {
          namaHari = _getNamaHari(dt.weekday);
          namaBulan = _getNamaBulan(dt.month);
          final namaBulanSingkat = _getNamaBulanSingkat(dt.month);
          shortDate = '${dt.day} $namaBulanSingkat';
          fullDateStr = '$namaHari, ${dt.day} $namaBulan ${dt.year}';
        }

        generatedDays.add(
          _DayTabInfo(
            dayIndex: i,
            label: 'Hari ${i + 1}',
            dateStr: fullDateStr,
            shortDateStr: shortDate.isNotEmpty ? shortDate : 'Hari ${i + 1}',
            date: dt,
          ),
        );
      }
    } else {
      // Hitung dari rentang startDate - endDate
      int calculatedDays = 1;
      if (startDt != null && endDt != null) {
        final diff = endDt.difference(startDt).inDays + 1;
        if (diff > 0) calculatedDays = diff;
      }

      int maxDayIndex = 0;
      for (var t in _timetable) {
        final tDay = (t['dayIndex'] as num?)?.toInt();
        if (tDay != null && tDay > maxDayIndex) maxDayIndex = tDay;
        final tsId = (t['sessionId'] ?? '').toString();
        if (tsId.startsWith('day_')) {
          final parts = tsId.split('_');
          if (parts.length >= 2) {
            final d = int.tryParse(parts[1]);
            if (d != null && d > maxDayIndex) maxDayIndex = d;
          }
        }
      }

      for (var s in _sessions) {
        final sDay = (s['dayIndex'] as num?)?.toInt();
        if (sDay != null && sDay > maxDayIndex) maxDayIndex = sDay;
      }

      final totalDays = (maxDayIndex + 1) > calculatedDays
          ? (maxDayIndex + 1)
          : calculatedDays;

      final baseDate = startDt ?? DateTime.now();

      for (int i = 0; i < totalDays; i++) {
        final dayDate = DateTime(baseDate.year, baseDate.month, baseDate.day)
            .add(Duration(days: i));
        final namaHari = _getNamaHari(dayDate.weekday);
        final namaBulan = _getNamaBulan(dayDate.month);
        final namaBulanSingkat = _getNamaBulanSingkat(dayDate.month);

        generatedDays.add(
          _DayTabInfo(
            dayIndex: i,
            label: 'Hari ${i + 1}',
            dateStr: '$namaHari, ${dayDate.day} $namaBulan ${dayDate.year}',
            shortDateStr: '${dayDate.day} $namaBulanSingkat',
            date: dayDate,
          ),
        );
      }
    }

    _dayTabs = generatedDays;

    if (_selectedDayIndex >= _dayTabs.length) {
      _selectedDayIndex = 0;
    }

    _updateSessionTabsForSelectedDay();
  }

  void _updateSessionTabsForSelectedDay() {
    List<Map<String, dynamic>> matchedSessions = [];

    // 1. Cek dari _sortedDates & _dateGroups jika ada
    if (_sortedDates.isNotEmpty && _selectedDayIndex < _sortedDates.length) {
      final dateKey = _sortedDates[_selectedDayIndex];
      matchedSessions = List.from(_dateGroups[dateKey] ?? []);
    }

    // 2. Cek sesi yang punya dayIndex spesifik
    if (matchedSessions.isEmpty) {
      matchedSessions = _sessions.where((s) {
        final dIdx = (s['dayIndex'] as num?)?.toInt();
        return dIdx == _selectedDayIndex;
      }).toList();
    }

    // 3. Jika tidak ada sesi spesifik hari, gunakan seluruh template sesi
    if (matchedSessions.isEmpty) {
      matchedSessions = List.from(_sessions);
    }

    // 4. Jika sesi masih kosong, buat fallback sesi standar
    if (matchedSessions.isEmpty) {
      matchedSessions = [
        {
          'id': 'session_1',
          'name': 'Sesi 1',
          'startTime': '07:30',
          'endTime': '09:30',
          'order': 1,
        },
        {
          'id': 'session_2',
          'name': 'Sesi 2',
          'startTime': '10:00',
          'endTime': '12:00',
          'order': 2,
        },
      ];
    }

    matchedSessions.sort((a, b) {
      final oA = (a['order'] as num?) ?? 0;
      final oB = (b['order'] as num?) ?? 0;
      if (oA != oB) return oA.compareTo(oB);
      final stA = (a['startTime'] ?? '').toString();
      final stB = (b['startTime'] ?? '').toString();
      return stA.compareTo(stB);
    });

    final List<_SessionTabInfo> sessionTabs = [];
    for (int idx = 0; idx < matchedSessions.length; idx++) {
      final s = matchedSessions[idx];
      final sId = (s['id'] ?? s['docId'] ?? 'session_${idx + 1}').toString();
      final sName =
          (s['name'] ?? s['sessionName'] ?? 'Sesi ${idx + 1}').toString();
      final sStart = (s['startTime'] ?? s['start'] ?? '').toString();
      final sEnd = (s['endTime'] ?? s['end'] ?? '').toString();
      final timeRange = (sStart.isNotEmpty && sEnd.isNotEmpty)
          ? '$sStart - $sEnd'
          : (sStart.isNotEmpty ? sStart : 'Waktu Fleksibel');

      sessionTabs.add(
        _SessionTabInfo(
          sessionIndex: idx,
          id: sId,
          name: sName,
          startTime: sStart,
          endTime: sEnd,
          timeRange: timeRange,
        ),
      );
    }

    _currentSessionTabs = sessionTabs;
    if (_selectedSessionIndex >= _currentSessionTabs.length) {
      _selectedSessionIndex = 0;
    }
  }

  List<Map<String, dynamic>> _getRoomsForCurrentSelection() {
    final activeRooms = _rooms.isNotEmpty
        ? _rooms
        : [
            {'id': 'R1', 'name': 'Ruang 01', 'code': '01', 'capacity': 30}
          ];

    final currentSession = _currentSessionTabs.isNotEmpty &&
            _selectedSessionIndex < _currentSessionTabs.length
        ? _currentSessionTabs[_selectedSessionIndex]
        : null;

    final sId = currentSession?.id ?? 'session_${_selectedSessionIndex + 1}';
    final daySessKey = 'day_${_selectedDayIndex}_session_$_selectedSessionIndex';

    // Cari ID sesi riil dari list sesi/dateGroups
    String? targetRealSessionId = currentSession?.id;
    if (targetRealSessionId == null ||
        targetRealSessionId.startsWith('session_')) {
      if (_sortedDates.isNotEmpty && _selectedDayIndex < _sortedDates.length) {
        final dayDate = _sortedDates[_selectedDayIndex];
        final daySessions = _dateGroups[dayDate] ?? [];
        if (_selectedSessionIndex < daySessions.length) {
          targetRealSessionId =
              daySessions[_selectedSessionIndex]['id']?.toString();
        }
      }
    }

    // Cari jadwal mapel yang match dengan hari & sesi ini
    final List<Map<String, dynamic>> matchingTimetable = _timetable.where((t) {
      final tsId = (t['sessionId'] ?? t['session_id'] ?? '').toString().trim();
      final tDay = (t['dayIndex'] as num?)?.toInt() ??
          (t['day'] != null ? int.tryParse(t['day'].toString()) : null);
      final tSlot = (t['sessionIndex'] ?? t['slotIndex'] ?? t['session'] as num?)?.toInt();

      if (tDay != null && tSlot != null) {
        return tDay == _selectedDayIndex && tSlot == _selectedSessionIndex;
      }
      if (tsId == daySessKey) return true;
      if (targetRealSessionId != null &&
          targetRealSessionId.isNotEmpty &&
          tsId == targetRealSessionId) {
        return true;
      }
      if (tsId.startsWith('day_')) {
        final parts = tsId.split('_');
        if (parts.length >= 4) {
          final d = int.tryParse(parts[1]);
          final s = int.tryParse(parts[3]);
          if (d != null && s != null) {
            return d == _selectedDayIndex && s == _selectedSessionIndex;
          }
        }
      }
      if (tDay != null) {
        if (tDay == _selectedDayIndex) {
          if (tSlot != null) return tSlot == _selectedSessionIndex;
          if (tsId == sId ||
              tsId == 'session_$_selectedSessionIndex' ||
              tsId == '$_selectedSessionIndex') {
            return true;
          }
          if (tsId.isEmpty) return _selectedSessionIndex == 0;
        }
        return false;
      }
      if (tsId == sId ||
          tsId == 'session_$_selectedSessionIndex' ||
          tsId == '$_selectedSessionIndex') {
        return _selectedDayIndex == 0;
      }
      return false;
    }).toList();

    final List<Map<String, dynamic>> roomDetails = [];

    for (var rMap in activeRooms) {
      final rId =
          (rMap['id'] ?? rMap['code'] ?? rMap['name'] ?? '').toString();
      final rName = (rMap['name'] ?? rMap['code'] ?? rId).toString();
      final rCode = (rMap['code'] ?? rName).toString();
      final rCapacity = (rMap['capacity'] as num?)?.toInt() ?? 0;

      // 1. Data Siswa dan Kelas yang dialokasikan ke ruangan ini
      final Set<String> roomClassSet = {};
      final Set<String> roomStudentIds = {};
      final Set<String> roomStudentNis = {};
      final Set<int> roomSeatNumbers = {};
      int actualSeatCount = 0;

      for (var s in _seats) {
        final seatRoom =
            (s['roomId'] ?? s['roomName'] ?? s['roomCode'] ?? '').toString();
        if (seatRoom == rId || seatRoom == rName || seatRoom == rCode) {
          actualSeatCount++;
          final cName =
              (s['className'] ?? s['classId'] ?? '').toString().trim();
          if (cName.isNotEmpty) roomClassSet.add(cName);

          final stId =
              (s['studentId'] ?? s['id'] ?? '').toString().trim().toLowerCase();
          final stNis = (s['nis'] ?? '').toString().trim().toLowerCase();
          final seatNum = (s['seatNumber'] as num?)?.toInt();
          if (stId.isNotEmpty) roomStudentIds.add(stId);
          if (stNis.isNotEmpty) roomStudentNis.add(stNis);
          if (seatNum != null && seatNum > 0) roomSeatNumbers.add(seatNum);
        }
      }

      if (roomClassSet.isEmpty && _seats.isEmpty) {
        for (var t in matchingTimetable) {
          final cId = (t['classId'] ?? '').toString().trim();
          final cName = (t['className'] ?? '').toString().trim().isNotEmpty
              ? t['className'].toString().trim()
              : (_classMap[cId] ?? cId);
          if (cName.isNotEmpty) roomClassSet.add(cName);
        }
      }

      // 2. Mata pelajaran yang sedang diujikan di sesi & ruangan ini
      final Set<String> subjectSet = {};
      final Set<String> subjectIdSet = {};

      // A. Cek dari matchingTimetable yang cocok dengan kelas di ruangan
      for (var t in matchingTimetable) {
        final Set<String> tClasses = {};
        final rawClassIds = t['classIds'] as List? ??
            t['classNames'] as List? ??
            t['classes'] as List? ??
            t['targetClasses'] as List?;
        if (rawClassIds != null) {
          for (var c in rawClassIds) {
            if (c != null && c.toString().trim().isNotEmpty) {
              tClasses.add(c.toString().trim());
            }
          }
        }
        final singleCId = (t['classId'] ?? '').toString().trim();
        final singleCName = (t['className'] ?? '').toString().trim();
        if (singleCId.isNotEmpty) tClasses.add(singleCId);
        if (singleCName.isNotEmpty) tClasses.add(singleCName);

        bool classMatched = roomClassSet.isEmpty || _isClassMatched(tClasses, roomClassSet);

        if (classMatched) {
          final sIdVal = (t['subjectId'] ?? '').toString().trim().toLowerCase();
          final subName = (t['subjectName'] ?? '').toString().trim().isNotEmpty
              ? t['subjectName'].toString().trim()
              : (_subjectMap[sIdVal] ?? sIdVal);
          if (subName.isNotEmpty) subjectSet.add(subName);
          if (sIdVal.isNotEmpty) subjectIdSet.add(sIdVal);
        }
      }

      // B. Fallback dari scheduleGrid (strictly filter by room classes)
      if (subjectSet.isEmpty) {
        final schedGrid = _eventData?['scheduleGrid'] as Map? ??
            _eventData?['draftState']?['scheduleGrid'] as Map? ??
            _eventData?['draftState']?['step6']?['scheduleGrid'] as Map? ??
            {};
        final keysToTry = [
          'day_${_selectedDayIndex}_session_$_selectedSessionIndex',
          'session_$_selectedSessionIndex',
          daySessKey,
          sId,
        ];
        for (var k in keysToTry) {
          final schedSubjects = schedGrid[k];
          if (schedSubjects is List && schedSubjects.isNotEmpty) {
            for (var subId in schedSubjects) {
              final sIdStr = subId.toString().trim().toLowerCase();
              String foundName = _subjectMap[sIdStr] ?? sIdStr;
              final subjectsList = _eventData?['subjects'] as List? ??
                  _eventData?['draftState']?['subjects'] as List? ??
                  [];
              for (var sItem in subjectsList) {
                if (sItem is Map &&
                    (sItem['id']?.toString().toLowerCase() == sIdStr ||
                        sItem['code']?.toString().toLowerCase() == sIdStr ||
                        sItem['name']?.toString().toLowerCase() == sIdStr)) {
                  foundName = (sItem['name'] ?? sIdStr).toString();
                  break;
                }
              }
              if (_isSubjectForRoomClasses(sIdStr, foundName, roomClassSet, _timetable)) {
                if (foundName.isNotEmpty) subjectSet.add(foundName);
                if (sIdStr.isNotEmpty) subjectIdSet.add(sIdStr);
              }
            }
            if (subjectSet.isNotEmpty) break;
          }
        }
      }

      // C. Jika belum ketemu dan tidak ada data kelas di ruangan, ambil mapel dari matchingTimetable
      if (subjectSet.isEmpty && roomClassSet.isEmpty) {
        for (var t in matchingTimetable) {
          final sIdVal = (t['subjectId'] ?? '').toString().trim().toLowerCase();
          final subName = (t['subjectName'] ?? '').toString().trim().isNotEmpty
              ? t['subjectName'].toString().trim()
              : (_subjectMap[sIdVal] ?? sIdVal);
          if (subName.isNotEmpty) subjectSet.add(subName);
          if (sIdVal.isNotEmpty) subjectIdSet.add(sIdVal);
        }
      }

      // D. Fallback jika hanya 1 mapel di event doc
      if (subjectSet.isEmpty && _eventData != null) {
        final subjectsList = _eventData!['subjects'] as List? ??
            _eventData!['draftState']?['subjects'] as List? ??
            [];
        if (subjectsList.length == 1) {
          final sName = (subjectsList.first is Map)
              ? (subjectsList.first['name'] ??
                      subjectsList.first['subjectName'] ??
                      '')
                  .toString()
              : subjectsList.first.toString();
          if (sName.isNotEmpty) {
            subjectSet.add(sName);
            subjectIdSet.add(sName.toLowerCase());
          }
        }
      }

      // 3. Hitung Kehadiran Siswa di Ruangan Ini (dari stream Firestore)
      final Set<String> attendedStudentKeys = {};
      final cleanSubjNames = subjectSet.map((s) => s.toLowerCase().trim()).toSet();

      // A. Cek dari koleksi attendances
      for (var a in _attendances) {
        final aDay = (a['dayIndex'] as num?)?.toInt();
        final aSess = (a['sessionIndex'] as num?)?.toInt();
        final aDocId = (a['id'] ?? '').toString();

        // 1. Day Check
        if (aDay != null) {
          if (aDay != _selectedDayIndex) continue;
        } else {
          final daySessPattern = '_${_selectedDayIndex}_${_selectedSessionIndex}_';
          if (!aDocId.contains(daySessPattern)) continue;
        }

        // 2. Session Check
        if (aSess != null) {
          if (aSess != _selectedSessionIndex) continue;
        } else {
          final daySessPattern = '_${_selectedDayIndex}_${_selectedSessionIndex}_';
          if (!aDocId.contains(daySessPattern)) continue;
        }

        // 3. Attendance Status
        final isAtt = a['isAttended'] == true || a['attended'] == true;
        if (!isAtt) continue;

        // 4. Room Check
        final aRoom = (a['roomId'] ?? a['room'] ?? '').toString().trim();
        final stId =
            (a['studentId'] ?? a['id'] ?? '').toString().trim().toLowerCase();
        final stNis = (a['nis'] ?? '').toString().trim().toLowerCase();
        final seatNum = (a['seatNumber'] as num?)?.toInt();

        bool belongsToRoom = false;
        if (aRoom.isNotEmpty) {
          final cleanARoom = aRoom
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          final cleanRId = rId
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          final cleanRName = rName
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          final cleanRCode = rCode
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');

          belongsToRoom = aRoom == rId ||
              aRoom == rName ||
              aRoom == rCode ||
              cleanARoom == cleanRId ||
              cleanARoom == cleanRName ||
              cleanARoom == cleanRCode;
        } else if (aDocId.contains('_${_selectedDayIndex}_${_selectedSessionIndex}_')) {
          final prefix = aDocId.split('_${_selectedDayIndex}_${_selectedSessionIndex}_').first.toLowerCase();
          final cleanPrefix = prefix.replaceAll('ruangan', '').replaceAll('ruang', '').replaceAll('room', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
          final cleanRId = rId.toLowerCase().replaceAll('ruangan', '').replaceAll('ruang', '').replaceAll('room', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
          final cleanRName = rName.toLowerCase().replaceAll('ruangan', '').replaceAll('ruang', '').replaceAll('room', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
          belongsToRoom = cleanPrefix == cleanRId || cleanPrefix == cleanRName;
        }

        if (!belongsToRoom && aRoom.isEmpty) {
          if (stId.isNotEmpty && roomStudentIds.contains(stId)) {
            belongsToRoom = true;
          } else if (stNis.isNotEmpty && roomStudentNis.contains(stNis)) {
            belongsToRoom = true;
          }
        }
        if (!belongsToRoom) continue;

        // 5. Subject Check (jika dokumen presensi punya subject dan ruangan ada mapel aktif)
        final aSubjId = (a['subjectId'] ?? '').toString().trim().toLowerCase();
        final aSubjName = (a['subjectName'] ?? '').toString().trim().toLowerCase();
        if (cleanSubjNames.isNotEmpty && (aSubjId.isNotEmpty || aSubjName.isNotEmpty)) {
          final bool matchesSubj = cleanSubjNames.contains(aSubjName) ||
              subjectIdSet.contains(aSubjId) ||
              subjectIdSet.contains(aSubjName);
          if (!matchesSubj) continue;
        }

        final key = stId.isNotEmpty
            ? stId
            : (stNis.isNotEmpty ? stNis : 'seat_$seatNum');
        attendedStudentKeys.add(key);
      }

      // B. Cek dari koleksi submissions
      for (var sub in _submissions) {
        final subDay = (sub['dayIndex'] as num?)?.toInt();
        final subSess = (sub['sessionIndex'] as num?)?.toInt();
        if (subDay != null && subDay != _selectedDayIndex) continue;
        if (subSess != null && subSess != _selectedSessionIndex) continue;

        final isCompleted =
            sub['isCompleted'] == true || (sub['status'] == 'completed');
        if (!isCompleted) continue;

        final subRoom =
            (sub['roomId'] ?? sub['room'] ?? '').toString().trim();
        final stId = (sub['studentId'] ?? sub['id'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final stNis = (sub['nis'] ?? '').toString().trim().toLowerCase();

        bool belongsToRoom = false;
        if (subRoom.isNotEmpty) {
          final cleanSubRoom = subRoom
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          final cleanRId = rId
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          final cleanRName = rName
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          belongsToRoom = subRoom == rId || subRoom == rName || cleanSubRoom == cleanRId || cleanSubRoom == cleanRName;
        }
        if (!belongsToRoom && subRoom.isEmpty) {
          if (stId.isNotEmpty && roomStudentIds.contains(stId)) {
            belongsToRoom = true;
          } else if (stNis.isNotEmpty && roomStudentNis.contains(stNis)) {
            belongsToRoom = true;
          }
        }
        if (!belongsToRoom) continue;

        // Subject check for submissions
        final subSubjId = (sub['subjectId'] ?? '').toString().trim().toLowerCase();
        final subSubjName = (sub['subjectName'] ?? '').toString().trim().toLowerCase();
        if (cleanSubjNames.isNotEmpty) {
          final bool matchesSubj = cleanSubjNames.contains(subSubjName) ||
              subjectIdSet.contains(subSubjId) ||
              subjectIdSet.contains(subSubjName);
          if (!matchesSubj) continue;
        }

        // Validasi pengerjaan: murid yang tidak menjawab sama sekali tidak dihitung hadir
        final ansMap = sub['answers'] as Map? ?? {};
        final essayMap = sub['essayAnswers'] as Map? ?? {};
        final ansCount = (sub['answeredCount'] as num?)?.toInt() ?? (ansMap.length + essayMap.length);
        if (ansCount == 0 && ansMap.isEmpty && essayMap.isEmpty) {
          continue;
        }

        final key = stId.isNotEmpty
            ? stId
            : (stNis.isNotEmpty ? stNis : sub['id'].toString());
        attendedStudentKeys.add(key);
      }

      // C. Cek dari koleksi realtime_control
      for (var rt in _realtimeControl) {
        final rtDay = (rt['dayIndex'] as num?)?.toInt();
        final rtSess = (rt['sessionIndex'] as num?)?.toInt();
        if (rtDay != null && rtDay != _selectedDayIndex) continue;
        if (rtSess != null && rtSess != _selectedSessionIndex) continue;

        final status = (rt['status'] ?? '').toString().toLowerCase();
        final isWorking = rt['isWorking'] == true ||
            status == 'in_progress' ||
            status == 'working' ||
            status == 'completed' ||
            rt['isCompleted'] == true;
        if (!isWorking) continue;

        final rtRoom = (rt['roomId'] ?? rt['room'] ?? '').toString().trim();
        final stId =
            (rt['studentId'] ?? rt['id'] ?? '').toString().trim().toLowerCase();
        final stNis = (rt['nis'] ?? '').toString().trim().toLowerCase();

        bool belongsToRoom = false;
        if (rtRoom.isNotEmpty) {
          final cleanRtRoom = rtRoom
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          final cleanRId = rId
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          final cleanRName = rName
              .toLowerCase()
              .replaceAll('ruangan', '')
              .replaceAll('ruang', '')
              .replaceAll('room', '')
              .replaceAll(' ', '')
              .replaceAll('_', '')
              .replaceAll('-', '');
          belongsToRoom = rtRoom == rId || rtRoom == rName || cleanRtRoom == cleanRId || cleanRtRoom == cleanRName;
        }
        if (!belongsToRoom && rtRoom.isEmpty) {
          if (stId.isNotEmpty && roomStudentIds.contains(stId)) {
            belongsToRoom = true;
          } else if (stNis.isNotEmpty && roomStudentNis.contains(stNis)) {
            belongsToRoom = true;
          }
        }
        if (!belongsToRoom) continue;

        // Subject check for realtime_control
        final rtSubjId = (rt['subjectId'] ?? '').toString().trim().toLowerCase();
        final rtSubjName = (rt['subjectName'] ?? '').toString().trim().toLowerCase();
        if (cleanSubjNames.isNotEmpty) {
          final bool matchesSubj = cleanSubjNames.contains(rtSubjName) ||
              subjectIdSet.contains(rtSubjId) ||
              subjectIdSet.contains(rtSubjName);
          if (!matchesSubj) continue;
        }

        // Validasi pengerjaan: jika berstatus completed tapi jawaban 0 dan tidak aktif bekerja, abaikan
        final ansCount = (rt['answeredCount'] as num?)?.toInt() ?? 0;
        final isLeftApp = rt['isLeftApp'] == true || status == 'left_app';
        final isCompleted = status == 'completed' || rt['isCompleted'] == true;
        if (isCompleted && ansCount == 0 && !isLeftApp && !isWorking) {
          continue;
        }

        final key = stId.isNotEmpty
            ? stId
            : (stNis.isNotEmpty ? stNis : rt['id'].toString());
        attendedStudentKeys.add(key);
      }

      final int attendedCount = attendedStudentKeys.length;

      // D. Fallback jika hanya 1 mapel di event doc
      if (subjectSet.isEmpty && _eventData != null) {
        final subjectsList = _eventData!['subjects'] as List? ??
            _eventData!['draftState']?['subjects'] as List? ??
            [];
        if (subjectsList.length == 1) {
          final sName = (subjectsList.first is Map)
              ? (subjectsList.first['name'] ??
                      subjectsList.first['subjectName'] ??
                      '')
                  .toString()
              : subjectsList.first.toString();
          if (sName.isNotEmpty) subjectSet.add(sName);
        }
      }

      // 4. Pengawas ruangan
      String proctorName = '';

      for (var p in _proctorList) {
        final pSId = (p['sessionId'] ?? '').toString();
        final pRId = (p['roomId'] ?? '').toString();
        final pDayIdx = (p['dayIndex'] as num?)?.toInt();
        final pSessIdx = (p['sessionIndex'] as num?)?.toInt();

        final bool dayMatch = pDayIdx == null ||
            pDayIdx == _selectedDayIndex ||
            pDayIdx == _selectedDayIndex + 1;
        final bool sessMatch = pSessIdx != null
            ? (pSessIdx == _selectedSessionIndex ||
                pSessIdx == _selectedSessionIndex + 1)
            : (pSId == sId ||
                pSId == 'session_${_selectedSessionIndex + 1}' ||
                pSId == daySessKey);
        final bool roomMatch =
            (pRId == rId || pRId == rCode || pRId == rName);

        if (dayMatch && sessMatch && roomMatch) {
          final tId = (p['teacherId'] ?? p['teacherName'] ?? '').toString();
          proctorName = p['teacherName'] ?? _teacherMap[tId] ?? tId;
          break;
        }
      }

      if (proctorName.isEmpty) {
        final keysToTry = [
          'day_${_selectedDayIndex}_session_${_selectedSessionIndex}_room_$rId',
          'day_${_selectedDayIndex}_session_${_selectedSessionIndex}_room_$rCode',
          'day_${_selectedDayIndex}_session_${_selectedSessionIndex}_room_$rName',
          'day_${_selectedDayIndex}_session_0_room_$rId',
          'day_${_selectedDayIndex}_session_0_room_$rCode',
          'day_${_selectedDayIndex}_session_0_room_$rName',
        ];
        for (final k in keysToTry) {
          if (_proctorGrid.containsKey(k)) {
            final pVal = _proctorGrid[k]!;
            proctorName = _teacherMap[pVal] ?? pVal;
            break;
          }
        }
      }

      final effectiveCapacity = actualSeatCount > 0
          ? actualSeatCount
          : (rCapacity > 0 ? rCapacity : 30);

      roomDetails.add({
        'id': rId,
        'name': rName,
        'code': rCode,
        'capacity': effectiveCapacity,
        'attendedCount': attendedCount,
        'classes': roomClassSet.toList(),
        'subjects': subjectSet.toList(),
        'proctorName': proctorName,
      });
    }

    return roomDetails;
  }

  void _openRoomMonitoring(String roomId) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final effectiveSchoolId = widget.schoolId.isNotEmpty
        ? widget.schoolId
        : (auth.schoolId ?? '');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherProctorRoomPage(
          eventId: widget.eventId,
          roomId: roomId,
          dayIndex: _selectedDayIndex,
          sessionIndex: _selectedSessionIndex,
          isAdminView: true,
          schoolId: effectiveSchoolId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/admin/eventujian');
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        // App bar jelek dihapus sesuai permintaan, diganti in-body header modern
        body: SafeArea(
          child: Column(
            children: [
              // Header Modern menyatu dengan halaman
              _buildTopHeader(),

              // Konten Utama
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                                color: Color(0xFF0D9488)),
                            SizedBox(height: 16),
                            Text(
                              'Memuat Kontrol Ruangan...',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _errorMessage != null
                        ? _buildErrorView()
                        : _buildMainBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// HEADER ATAS MODERN (Menggantikan AppBar lama yang jelek)
  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          // Tombol Kembali
          InkWell(
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/admin/eventujian');
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 18,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Judul dan Nama Event
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Kontrol Ruangan',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Admin',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.eventName,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Live Indicator
          if (MediaQuery.of(context).size.width >= 550)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Live Monitor',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            ),

          // Tombol Segarkan
          OutlinedButton.icon(
            onPressed: _loadEventData,
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Segarkan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              'Gagal Memuat Data',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Terjadi kesalahan saat memuat kontrol ruangan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadEventData,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainBody() {
    final activeDay = _dayTabs.isNotEmpty && _selectedDayIndex < _dayTabs.length
        ? _dayTabs[_selectedDayIndex]
        : null;

    final activeSession = _currentSessionTabs.isNotEmpty &&
            _selectedSessionIndex < _currentSessionTabs.length
        ? _currentSessionTabs[_selectedSessionIndex]
        : null;

    final roomDetails = _getRoomsForCurrentSelection();

    final totalRooms = roomDetails.length;
    int totalSeats = 0;
    int totalAttended = 0;
    int assignedProctors = 0;

    for (var r in roomDetails) {
      totalSeats += (r['capacity'] as int? ?? 0);
      totalAttended += (r['attendedCount'] as int? ?? 0);
      if ((r['proctorName'] as String? ?? '').isNotEmpty) {
        assignedProctors++;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Tab Bar Hari (Level 1)
          _buildDayTabBar(),
          const SizedBox(height: 16),

          // 2. Tab Bar Sesi (Level 2 - di bawah Tab Hari)
          _buildSessionTabBar(),
          const SizedBox(height: 20),

          // 3. Banner Ringkasan Hari & Sesi Terpilih
          _buildActiveInfoBanner(activeDay, activeSession),
          const SizedBox(height: 16),

          // 4. Kartu Metrik Ringkas (termasuk total murid yang hadir)
          _buildKpiCards(
            totalRooms: totalRooms,
            totalSeats: totalSeats,
            totalAttended: totalAttended,
            assignedProctors: assignedProctors,
          ),
          const SizedBox(height: 24),

          // 5. Header Daftar Ruangan
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.meeting_room_rounded,
                      size: 20, color: Color(0xFF0D9488)),
                  const SizedBox(width: 8),
                  Text(
                    'Daftar Ruangan Ujian',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  '$totalRooms Ruangan',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 6. Grid / List Kartu Ruangan
          if (roomDetails.isEmpty)
            _buildEmptyRoomsState()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900;
                final isTablet =
                    constraints.maxWidth >= 600 && constraints.maxWidth < 900;

                final crossAxisCount = isDesktop ? 3 : (isTablet ? 2 : 1);

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: roomDetails.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 250,
                  ),
                  itemBuilder: (context, idx) {
                    final room = roomDetails[idx];
                    return _buildRoomCard(room);
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  /// TAB BAR HARI (Level 1)
  Widget _buildDayTabBar() {
    if (_dayTabs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_month_rounded,
                size: 15, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              'PILIH HARI UJIAN',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _dayTabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final day = _dayTabs[index];
              final isSelected = _selectedDayIndex == day.dayIndex;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_selectedDayIndex != day.dayIndex) {
                        setState(() {
                          _selectedDayIndex = day.dayIndex;
                          _updateSessionTabsForSelectedDay();
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF0D9488)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF0F766E)
                              : const Color(0xFFCBD5E1),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF0D9488)
                                      .withValues(alpha: 0.25),
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
                            Icons.calendar_today_rounded,
                            size: 15,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            day.label,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              day.shortDateStr,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              ),
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
        ),
      ],
    );
  }

  /// TAB BAR SESI (Level 2 - di bawah Tab Hari)
  Widget _buildSessionTabBar() {
    if (_currentSessionTabs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule_rounded,
                size: 15, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              'PILIH SESI UJIAN',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _currentSessionTabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final sess = _currentSessionTabs[index];
              final isSelected = _selectedSessionIndex == sess.sessionIndex;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_selectedSessionIndex != sess.sessionIndex) {
                        setState(() {
                          _selectedSessionIndex = sess.sessionIndex;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF4F46E5)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF4338CA)
                              : const Color(0xFFCBD5E1),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF4F46E5)
                                      .withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
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
                            Icons.alarm_rounded,
                            size: 14,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            sess.name,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${sess.timeRange})',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : const Color(0xFF64748B),
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
        ),
      ],
    );
  }

  /// BANNER RINGKASAN HARI & SESI TERPILIH
  Widget _buildActiveInfoBanner(
      _DayTabInfo? activeDay, _SessionTabInfo? activeSession) {
    final dayLabel = activeDay?.label ?? 'Hari 1';
    final dateStr = activeDay?.dateStr ?? '-';
    final sessionLabel = activeSession?.name ?? 'Sesi 1';
    final sessionTime = activeSession?.timeRange ?? '-';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 600;

          final dayWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF99F6E4)),
                ),
                child: const Icon(Icons.event_available_rounded,
                    color: Color(0xFF0D9488), size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayLabel,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    dateStr,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          );

          final sessionWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: const Icon(Icons.access_time_filled_rounded,
                    color: Color(0xFF4F46E5), size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sessionLabel,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    sessionTime,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (isSmall) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                dayWidget,
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                sessionWidget,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              dayWidget,
              Container(
                height: 32,
                width: 1,
                color: const Color(0xFFE2E8F0),
              ),
              sessionWidget,
            ],
          );
        },
      ),
    );
  }

  /// KARTU METRIK RINGKAS (Termasuk Total Siswa Hadir)
  Widget _buildKpiCards({
    required int totalRooms,
    required int totalSeats,
    required int totalAttended,
    required int assignedProctors,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final attendancePct = totalSeats > 0
            ? ((totalAttended / totalSeats) * 100).toStringAsFixed(0)
            : '0';

        final items = [
          _buildKpiItem(
            title: 'Ruangan Aktif',
            value: '$totalRooms Ruangan',
            icon: Icons.meeting_room_outlined,
            iconColor: const Color(0xFF0D9488),
            bgColor: const Color(0xFFF0FDFA),
          ),
          _buildKpiItem(
            title: 'Kapasitas Peserta',
            value: '$totalSeats Kursi',
            icon: Icons.event_seat_rounded,
            iconColor: const Color(0xFF3B82F6),
            bgColor: const Color(0xFFEFF6FF),
          ),
          _buildKpiItem(
            title: 'Total Murid Hadir',
            value: '$totalAttended / $totalSeats',
            subtitle: '$attendancePct% hadir',
            icon: Icons.how_to_reg_rounded,
            iconColor: totalAttended > 0
                ? const Color(0xFF10B981)
                : const Color(0xFF64748B),
            bgColor: totalAttended > 0
                ? const Color(0xFFECFDF5)
                : const Color(0xFFF8FAFC),
          ),
          _buildKpiItem(
            title: 'Pengawas Bertugas',
            value: '$assignedProctors / $totalRooms',
            icon: Icons.badge_outlined,
            iconColor: assignedProctors >= totalRooms && totalRooms > 0
                ? const Color(0xFF10B981)
                : const Color(0xFFF59E0B),
            bgColor: assignedProctors >= totalRooms && totalRooms > 0
                ? const Color(0xFFECFDF5)
                : const Color(0xFFFFFBEB),
          ),
        ];

        if (constraints.maxWidth < 600) {
          return Column(
            children: items
                .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: w,
                    ))
                .toList(),
          );
        } else if (constraints.maxWidth < 1000) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: items[0]),
                  const SizedBox(width: 10),
                  Expanded(child: items[1]),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: items[2]),
                  const SizedBox(width: 10),
                  Expanded(child: items[3]),
                ],
              ),
            ],
          );
        }

        return Row(
          children: items
              .map((w) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: w,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildKpiItem({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      value,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// KARTU RUANGAN
  Widget _buildRoomCard(Map<String, dynamic> room) {
    final rId = (room['id'] ?? '').toString();
    final rName = (room['name'] ?? 'Ruangan').toString();
    final rCapacity = (room['capacity'] as int?) ?? 0;
    final attendedCount = (room['attendedCount'] as int?) ?? 0;
    final classes = (room['classes'] as List?)?.cast<String>() ?? [];
    final subjects = (room['subjects'] as List?)?.cast<String>() ?? [];
    final proctorName = (room['proctorName'] as String?) ?? '';

    final hasProctor = proctorName.isNotEmpty;
    final hasAttended = attendedCount > 0;
    final isFullAttendance = attendedCount >= rCapacity && rCapacity > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Ruangan & Chip Kehadiran
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.meeting_room_rounded,
                        size: 16, color: Color(0xFF0D9488)),
                    const SizedBox(width: 6),
                    Text(
                      rName,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                // Chip Kehadiran Murid
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isFullAttendance
                        ? const Color(0xFFD1FAE5)
                        : (hasAttended
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isFullAttendance
                          ? const Color(0xFFA7F3D0)
                          : (hasAttended
                              ? const Color(0xFFDBEAFE)
                              : const Color(0xFFCBD5E1)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.how_to_reg_rounded,
                        size: 12,
                        color: isFullAttendance
                            ? const Color(0xFF059669)
                            : (hasAttended
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$attendedCount / $rCapacity Hadir',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isFullAttendance
                              ? const Color(0xFF059669)
                              : (hasAttended
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Detail Pengawas, Mapel, Kelas, dan Progress Kehadiran
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. Info Pengawas
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        hasProctor
                            ? Icons.verified_user_rounded
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: hasProctor
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hasProctor
                              ? 'Pengawas: $proctorName'
                              : 'Pengawas: Belum ditentukan',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: hasProctor
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFD97706),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // 2. Info Mapel yang sedang diujikan (TIDAK ADA kata "Semua Mapel")
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.menu_book_rounded,
                          size: 14, color: Color(0xFF0D9488)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subjects.isNotEmpty
                              ? 'Mapel: ${subjects.join(', ')}'
                              : 'Mapel: Belum Terjadwal',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: subjects.isNotEmpty
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // 3. Info Kelas
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.groups_rounded,
                          size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          classes.isNotEmpty
                              ? 'Kelas: ${classes.join(', ')}'
                              : 'Kelas: Sesuai Alokasi',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // 4. Baris Status Kehadiran Murid
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Kehadiran Siswa',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            rCapacity > 0
                                ? '$attendedCount dari $rCapacity murid (${((attendedCount / rCapacity) * 100).toStringAsFixed(0)}%)'
                                : '$attendedCount murid',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: hasAttended
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: rCapacity > 0
                              ? (attendedCount / rCapacity).clamp(0.0, 1.0)
                              : 0.0,
                          backgroundColor: const Color(0xFFF1F5F9),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isFullAttendance
                                ? const Color(0xFF10B981)
                                : (hasAttended
                                    ? const Color(0xFF0D9488)
                                    : const Color(0xFFCBD5E1)),
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Tombol Aksi Kontrol Ruangan
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openRoomMonitoring(rId),
                icon: const Icon(Icons.visibility_rounded, size: 14),
                label: Text(
                  'Pantau Denah Ruangan',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// EMPTY STATE RUANGAN
  Widget _buildEmptyRoomsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.meeting_room_outlined,
              size: 44, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            'Belum Ada Ruangan Terdaftar',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ruangan untuk hari dan sesi ini belum dialokasikan pada event ujian ini.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
