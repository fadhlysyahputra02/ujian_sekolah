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

  // Search Query
  String _searchQuery = '';

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

      // 3. Fetch Sessions
      final sessionSnap = await eventRef.collection('sessions').orderBy('order').get();
      _sessions = sessionSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

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

    final int sessionsPerDay = _sessions.isNotEmpty ? _sessions.length : 2;

    int globalRowIdx = 0;

    for (int dayIdx = 0; dayIdx < totalDays; dayIdx++) {
      for (int sessIdx = 0; sessIdx < sessionsPerDay; sessIdx++) {
        final sess = (sessIdx < _sessions.length) ? _sessions[sessIdx] : <String, dynamic>{};
        final sId = (sess['id'] ?? 'day_${dayIdx}_session_$sessIdx').toString();
        final sName = (sess['name'] ?? sess['sessionName'] ?? 'Sesi ${sessIdx + 1}').toString();
        final sStart = (sess['startTime'] ?? '').toString();
        final sEnd = (sess['endTime'] ?? '').toString();
        final timeLabel = (sStart.isNotEmpty && sEnd.isNotEmpty) ? '$sStart - $sEnd' : (sStart.isNotEmpty ? sStart : 'Jam Sesi');

        // Resolve Date Label for Day dayIdx
        String dateStr = 'Hari ${dayIdx + 1}';
        if (_eventData != null && _eventData!['startDate'] != null) {
          final sd = _eventData!['startDate'];
          DateTime? startDt = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
          if (startDt != null) {
            final dayDate = startDt.add(Duration(days: dayIdx));
            dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dayDate);
          }
        }
        if (dateStr.startsWith('Hari') && sess['date'] != null) {
          final dVal = sess['date'];
          if (dVal is Timestamp) {
            dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dVal.toDate());
          } else if (dVal is String && dVal.isNotEmpty) {
            final dt = DateTime.tryParse(dVal);
            if (dt != null) dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dt);
          }
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

          // 4. Fallback match if tsId equals sId and tDay matches dayIdx
          if (tsId == sId) {
            return tDay == dayIdx || (tDay == null && dayIdx == 0);
          }

          return false;
        }).toList();

        if (matchingTimetable.isEmpty && _timetable.isNotEmpty) {
          continue; // Skip slots that have no scheduled subjects
        }

        // Active Rooms
        final activeRooms = _rooms.isNotEmpty ? _rooms : [{'id': 'R1', 'name': 'Ruang 01', 'code': '01'}];

        for (var rMap in activeRooms) {
          final rId = (rMap['id'] ?? rMap['code'] ?? rMap['name'] ?? '').toString();
          final rName = (rMap['name'] ?? rMap['code'] ?? rId).toString();
          final rCode = (rMap['code'] ?? rName).toString();

          // Resolve Classes in this room for this session
          final Set<String> roomClassSet = {};
          for (var t in matchingTimetable) {
            final cName = (t['className'] ?? t['classId'] ?? '').toString().trim();
            if (cName.isNotEmpty) roomClassSet.add(cName);
          }
          if (roomClassSet.isEmpty) {
            for (var s in _seats) {
              final seatRoom = (s['roomId'] ?? s['roomName'] ?? s['roomCode'] ?? '').toString();
              if (seatRoom == rId || seatRoom == rName || seatRoom == rCode) {
                final cName = (s['className'] ?? s['classId'] ?? '').toString().trim();
                if (cName.isNotEmpty) roomClassSet.add(cName);
              }
            }
          }
          if (roomClassSet.isEmpty) {
            for (var s in _seats) {
              final cName = (s['className'] ?? s['classId'] ?? '').toString().trim();
              if (cName.isNotEmpty) roomClassSet.add(cName);
            }
          }

          // Resolve Mapel in this session
          final Set<String> subjectSet = {};
          for (var t in matchingTimetable) {
            final subName = (t['subjectName'] ?? t['subjectId'] ?? '').toString().trim();
            if (subName.isNotEmpty) subjectSet.add(subName);
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
            'pengawasList': proctorName.isNotEmpty ? proctorName : '-',
          });
        }
      }
    }

    return result;
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

    // Search filter
    final filteredRows = allRows.where((row) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return (row['dateStr'] as String).toLowerCase().contains(q) ||
          (row['sessionName'] as String).toLowerCase().contains(q) ||
          (row['roomName'] as String).toLowerCase().contains(q) ||
          (row['classesList'] as String).toLowerCase().contains(q) ||
          (row['mapelList'] as String).toLowerCase().contains(q) ||
          (row['pengawasList'] as String).toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.eventName,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Jadwal Ujian Sederhana (Hari, Sesi, Jam, Ruangan, Kelas, Mapel & Pengawas)',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF818CF8)),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFF64748B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Cari hari, ruangan, kelas, mapel, atau pengawas...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

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
                    DataColumn(label: Text('Hari')),
                    DataColumn(label: Text('Sesi')),
                    DataColumn(label: Text('Jam')),
                    DataColumn(label: Text('Ruangan')),
                    DataColumn(label: Text('Kelas')),
                    DataColumn(label: Text('Mapel')),
                    DataColumn(label: Text('Pengawas')),
                  ],
                  rows: rows.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;

                    // Day cell merging: Only display Day text on the first row of each date group
                    final bool isFirstRowOfDay = (idx == 0 || rows[idx]['dateStr'] != rows[idx - 1]['dateStr']);
                    final String displayDayText = isFirstRowOfDay ? row['dateStr'] : '';

                    return DataRow(
                      color: WidgetStateProperty.all(isFirstRowOfDay ? Colors.white : const Color(0xFFF8FAFC)),
                      cells: [
                        // Hari (Merged appearance when empty)
                        DataCell(
                          Container(
                            constraints: const BoxConstraints(minWidth: 140, maxWidth: 160),
                            child: Text(
                              displayDayText,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        // Sesi
                        DataCell(
                          Container(
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
                            ),
                          ),
                        ),
                        // Jam
                        DataCell(
                          Text(
                            row['sessionTime'],
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ),
                        // Ruangan
                        DataCell(
                          Container(
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
                            ),
                          ),
                        ),
                        // Kelas
                        DataCell(
                          Container(
                            constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
                            child: Text(
                              row['classesList'],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ),
                        // Mapel
                        DataCell(
                          Container(
                            constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
                            child: Text(
                              row['mapelList'],
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        // Pengawas
                        DataCell(
                          Container(
                            constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
                            child: Text(
                              row['pengawasList'],
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF059669),
                              ),
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

  /// Print or Export Schedule PDF Document matching requested simple table format
  Future<void> _printOrExportPdf(List<Map<String, dynamic>> rows) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'JADWAL PELAKSANAAN UJIAN SEKOLAH',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Event: ${widget.eventName}',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 14),
              pw.Table.fromTextArray(
                headers: ['Hari', 'Sesi', 'Jam', 'Ruangan', 'Kelas', 'Mapel', 'Pengawas'],
                data: rows.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;
                  final bool isFirstRowOfDay = (idx == 0 || rows[idx]['dateStr'] != rows[idx - 1]['dateStr']);
                  final String displayDayText = isFirstRowOfDay ? r['dateStr'] : '';
                  return [
                    displayDayText,
                    r['sessionName'],
                    r['sessionTime'],
                    r['roomName'],
                    r['classesList'],
                    r['mapelList'],
                    r['pengawasList'],
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellHeight: 22,
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }
}
