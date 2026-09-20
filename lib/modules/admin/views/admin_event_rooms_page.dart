import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../controllers/admin_room_monitoring_controller.dart';

class AdminEventRoomsPage extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const AdminEventRoomsPage({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<AdminEventRoomsPage> createState() => _AdminEventRoomsPageState();
}

class _AdminEventRoomsPageState extends State<AdminEventRoomsPage> {
  int _selectedDayIndex = 0;
  int _selectedSessionIndex = 0;
  bool _hasAutoSelectedDay = false;
  String _searchQuery = '';

  String _formatDate(DateTime dt) {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    return '$dayName, ${dt.day} $monthName ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final String effectiveSchoolId = widget.schoolId.isNotEmpty
        ? widget.schoolId
        : (authService.schoolId ?? '');

    if (effectiveSchoolId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('School ID tidak ditemukan')),
      );
    }

    final db = FirebaseFirestore.instance;
    final eventRef = db.collection('schools').doc(effectiveSchoolId).collection('events').doc(widget.eventId);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          tooltip: 'Kembali',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/admin/ujian');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Pantau Ruangan Ujian',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4F46E5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Admin Monitoring',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              widget.eventName,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: eventRef.snapshots(),
        builder: (context, eventSnap) {
          if (eventSnap.connectionState == ConnectionState.waiting && !eventSnap.hasData) {
            return const AppContentLoader(
              title: 'Memuat Data Ruangan...',
              subtitle: 'Mengambil jadwal dan alokasi ruangan ujian',
            );
          }

          final evData = eventSnap.data?.data() as Map<String, dynamic>? ?? {};
          final draftState = evData['draftState'] as Map<String, dynamic>?;

          return StreamBuilder<QuerySnapshot>(
            stream: eventRef.collection('sessions').orderBy('order').snapshots(),
            builder: (context, sessionSnap) {
              List<Map<String, dynamic>> sessions = [];
              if (sessionSnap.hasData && sessionSnap.data!.docs.isNotEmpty) {
                sessions = sessionSnap.data!.docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  data['id'] = d.id;
                  return data;
                }).toList();
              } else if (evData['sessions'] is List) {
                sessions = (evData['sessions'] as List)
                    .map((s) => Map<String, dynamic>.from(s as Map))
                    .toList();
              }

              // Group sessions by date
              final Map<String, List<Map<String, dynamic>>> dateGroups = {};
              for (var s in sessions) {
                final dStr = (s['date'] ?? s['startDate'] ?? '').toString();
                if (dStr.isNotEmpty) {
                  dateGroups.putIfAbsent(dStr, () => []).add(s);
                }
              }

              // Sort dates
              final sortedDates = dateGroups.keys.toList()..sort();
              if (sortedDates.isEmpty) {
                sortedDates.add(DateFormat('yyyy-MM-dd').format(DateTime.now()));
                dateGroups[sortedDates.first] = sessions;
              }

              // Auto select today's date if exists
              if (!_hasAutoSelectedDay) {
                _hasAutoSelectedDay = true;
                final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                final todayIdx = sortedDates.indexOf(todayStr);
                if (todayIdx >= 0) {
                  _selectedDayIndex = todayIdx;
                } else {
                  _selectedDayIndex = 0;
                }

                // Check active session for today
                final daySessions = dateGroups[sortedDates[_selectedDayIndex]] ?? [];
                final dt = DateTime.tryParse(sortedDates[_selectedDayIndex]) ?? DateTime.now();
                for (int si = 0; si < daySessions.length; si++) {
                  final s = daySessions[si];
                  final timeRange = '${s['startTime'] ?? s['start'] ?? ''} - ${s['endTime'] ?? s['end'] ?? ''}';
                  final st = AdminRoomMonitoringController.getSessionStatus(sessionDate: dt, timeRange: timeRange);
                  if (st == 'Sedang Berlangsung') {
                    _selectedSessionIndex = si;
                    break;
                  }
                }
              }

              if (_selectedDayIndex >= sortedDates.length) {
                _selectedDayIndex = 0;
              }

              final activeDateStr = sortedDates[_selectedDayIndex];
              final currentDayDate = DateTime.tryParse(activeDateStr) ?? DateTime.now();
              final daySessions = dateGroups[activeDateStr] ?? [];
              daySessions.sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));

              if (_selectedSessionIndex >= daySessions.length && daySessions.isNotEmpty) {
                _selectedSessionIndex = 0;
              }

              final currentSession = daySessions.isNotEmpty ? daySessions[_selectedSessionIndex] : <String, dynamic>{};
              final currentSessionTime = '${currentSession['startTime'] ?? currentSession['start'] ?? ''} - ${currentSession['endTime'] ?? currentSession['end'] ?? ''}';
              final currentSessionStatus = AdminRoomMonitoringController.getSessionStatus(
                sessionDate: currentDayDate,
                timeRange: currentSessionTime,
              );

              return StreamBuilder<QuerySnapshot>(
                stream: eventRef.collection('allocations').orderBy('createdAt', descending: true).limit(1).snapshots(),
                builder: (context, allocSnap) {
                  final allocDoc = allocSnap.data?.docs.isNotEmpty == true ? allocSnap.data!.docs.first : null;
                  final allocData = allocDoc?.data() as Map<String, dynamic>? ?? {};
                  final allocId = allocDoc?.id ?? '';

                  // Proctor Grid
                  final proctorGrid = <String, String>{};
                  final rLayouts = allocData['roomLayouts'] as Map<String, dynamic>? ?? evData['roomLayouts'] as Map<String, dynamic>? ?? {};
                  if (rLayouts['proctorGrid'] is Map) {
                    (rLayouts['proctorGrid'] as Map).forEach((k, v) => proctorGrid[k.toString()] = v.toString());
                  }

                  // Stream seats for this allocation
                  return StreamBuilder<QuerySnapshot>(
                    stream: allocId.isNotEmpty
                        ? eventRef.collection('allocations').doc(allocId).collection('seats').snapshots()
                        : const Stream.empty(),
                    builder: (context, seatSnap) {
                      final seatDocs = seatSnap.data?.docs ?? [];
                      final allSeats = seatDocs.map((d) => d.data() as Map<String, dynamic>).toList();

                      // Group seats by roomId
                      final Map<String, List<Map<String, dynamic>>> roomSeatsMap = {};
                      final Map<String, Map<String, dynamic>> roomsInfoMap = {};

                      for (var seat in allSeats) {
                        final rId = (seat['roomId'] ?? seat['roomCode'] ?? seat['roomName'] ?? '').toString().trim();
                        final rName = (seat['roomName'] ?? seat['roomCode'] ?? rId).toString().trim();
                        final rCode = (seat['roomCode'] ?? rName).toString().trim();
                        if (rId.isNotEmpty) {
                          roomSeatsMap.putIfAbsent(rId, () => []).add(seat);
                          roomsInfoMap.putIfAbsent(rId, () => {
                            'id': rId,
                            'name': rName,
                            'code': rCode,
                            'capacity': seat['roomCapacity'] ?? 0,
                          });
                        }
                      }

                      // Fallback rooms from event doc if seats are empty
                      if (roomsInfoMap.isEmpty) {
                        final rawRooms = evData['rooms'] ?? draftState?['rooms'] ?? draftState?['step4']?['rooms'] ?? [];
                        if (rawRooms is List) {
                          for (var r in rawRooms) {
                            if (r is Map) {
                              final rId = (r['id'] ?? r['code'] ?? r['name'] ?? '').toString();
                              if (rId.isNotEmpty) {
                                roomsInfoMap[rId] = {
                                  'id': rId,
                                  'name': (r['name'] ?? r['code'] ?? rId).toString(),
                                  'code': (r['code'] ?? r['name'] ?? rId).toString(),
                                  'capacity': (r['capacity'] as num?)?.toInt() ?? 0,
                                };
                              }
                            }
                          }
                        }
                      }

                      final sortedRoomIds = roomsInfoMap.keys.toList()
                        ..sort((a, b) {
                          final nameA = (roomsInfoMap[a]?['name'] ?? '').toString();
                          final nameB = (roomsInfoMap[b]?['name'] ?? '').toString();
                          return nameA.compareTo(nameB);
                        });

                      // Live Streams: attendances, realtime_control, submissions
                      return StreamBuilder<QuerySnapshot>(
                        stream: eventRef.collection('attendances').snapshots(),
                        builder: (context, attSnap) {
                          final attDocs = attSnap.data?.docs ?? [];
                          final attendedKeys = <String>{};
                          for (var d in attDocs) {
                            final data = d.data() as Map<String, dynamic>;
                            final sId = (data['studentId'] ?? '').toString().toLowerCase().trim();
                            final nis = (data['nis'] ?? '').toString().toLowerCase().trim();
                            final name = (data['studentName'] ?? '').toString().toLowerCase().trim();
                            if (sId.isNotEmpty) attendedKeys.add(sId);
                            if (nis.isNotEmpty) attendedKeys.add(nis);
                            if (name.isNotEmpty) attendedKeys.add(name);
                          }

                          return StreamBuilder<QuerySnapshot>(
                            stream: eventRef.collection('realtime_control').snapshots(),
                            builder: (context, rtSnap) {
                              final rtDocs = rtSnap.data?.docs ?? [];
                              final realtimeMap = <String, Map<String, dynamic>>{};
                              for (var d in rtDocs) {
                                final data = d.data() as Map<String, dynamic>;
                                final sId = (data['studentId'] ?? '').toString().toLowerCase().trim();
                                final nis = (data['nis'] ?? '').toString().toLowerCase().trim();
                                final docId = d.id.toLowerCase().trim();
                                final docPrefix = docId.contains('_') ? docId.substring(0, docId.lastIndexOf('_')) : docId;

                                if (sId.isNotEmpty) realtimeMap[sId] = data;
                                if (nis.isNotEmpty) realtimeMap[nis] = data;
                                if (docPrefix.isNotEmpty) realtimeMap[docPrefix] = data;
                                realtimeMap[docId] = data;
                              }

                              return StreamBuilder<QuerySnapshot>(
                                stream: eventRef.collection('submissions').snapshots(),
                                builder: (context, subSnap) {
                                  final subDocs = subSnap.data?.docs ?? [];
                                  final submissionsMap = <String, Map<String, dynamic>>{};
                                  for (var d in subDocs) {
                                    final data = d.data() as Map<String, dynamic>;
                                    final sId = (data['studentId'] ?? '').toString().toLowerCase().trim();
                                    final nis = (data['nis'] ?? '').toString().toLowerCase().trim();
                                    final docId = d.id.toLowerCase().trim();
                                    final docPrefix = docId.contains('_') ? docId.substring(0, docId.lastIndexOf('_')) : docId;

                                    if (sId.isNotEmpty) submissionsMap[sId] = data;
                                    if (nis.isNotEmpty) submissionsMap[nis] = data;
                                    if (docPrefix.isNotEmpty) submissionsMap[docPrefix] = data;
                                    submissionsMap[docId] = data;
                                  }

                                  return _buildBodyContent(
                                    context: context,
                                    sortedDates: sortedDates,
                                    dateGroups: dateGroups,
                                    daySessions: daySessions,
                                    currentDayDate: currentDayDate,
                                    currentSession: currentSession,
                                    currentSessionTime: currentSessionTime,
                                    currentSessionStatus: currentSessionStatus,
                                    sortedRoomIds: sortedRoomIds,
                                    roomsInfoMap: roomsInfoMap,
                                    roomSeatsMap: roomSeatsMap,
                                    proctorGrid: proctorGrid,
                                    attendedKeys: attendedKeys,
                                    realtimeMap: realtimeMap,
                                    submissionsMap: submissionsMap,
                                    evData: evData,
                                    draftState: draftState,
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

  Widget _buildBodyContent({
    required BuildContext context,
    required List<String> sortedDates,
    required Map<String, List<Map<String, dynamic>>> dateGroups,
    required List<Map<String, dynamic>> daySessions,
    required DateTime currentDayDate,
    required Map<String, dynamic> currentSession,
    required String currentSessionTime,
    required String currentSessionStatus,
    required List<String> sortedRoomIds,
    required Map<String, Map<String, dynamic>> roomsInfoMap,
    required Map<String, List<Map<String, dynamic>>> roomSeatsMap,
    required Map<String, String> proctorGrid,
    required Set<String> attendedKeys,
    required Map<String, Map<String, dynamic>> realtimeMap,
    required Map<String, Map<String, dynamic>> submissionsMap,
    required Map<String, dynamic> evData,
    required Map<String, dynamic>? draftState,
  }) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    // Filter rooms by search query
    final filteredRoomIds = sortedRoomIds.where((rId) {
      final rInfo = roomsInfoMap[rId] ?? {};
      final rName = (rInfo['name'] ?? '').toString().toLowerCase();
      final rCode = (rInfo['code'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase().trim();
      return q.isEmpty || rName.contains(q) || rCode.contains(q);
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Day Tabs Carousel / Row
              Text(
                'Pilih Hari Ujian:',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: List.generate(sortedDates.length, (dIdx) {
                    final dStr = sortedDates[dIdx];
                    final dt = DateTime.tryParse(dStr) ?? DateTime.now();
                    final isSelected = dIdx == _selectedDayIndex;
                    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == dStr;

                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDayIndex = dIdx;
                            _selectedSessionIndex = 0;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: isSelected ? Colors.white : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Hari ${dIdx + 1}',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      if (isToday) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: isSelected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFD1FAE5),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'HARI INI',
                                            style: GoogleFonts.inter(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected ? Colors.white : const Color(0xFF059669),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    _formatDate(dt),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 20),

              // 2. Session Selector & Active Sesi Indicator
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pilih Sesi Ujian:',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                        ),
                        if (currentSessionStatus == 'Sedang Berlangsung')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sensors_rounded, size: 13, color: Color(0xFF059669)),
                                const SizedBox(width: 4),
                                Text(
                                  'Sesi Sedang Berlangsung Sekarang',
                                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF059669)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (daySessions.isEmpty)
                      Text(
                        'Tidak ada sesi ujian yang terdaftar untuk hari ini.',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: List.generate(daySessions.length, (sIdx) {
                          final sess = daySessions[sIdx];
                          final isSelected = sIdx == _selectedSessionIndex;
                          final sTime = '${sess['startTime'] ?? sess['start'] ?? ''} - ${sess['endTime'] ?? sess['end'] ?? ''}';
                          final status = AdminRoomMonitoringController.getSessionStatus(
                            sessionDate: currentDayDate,
                            timeRange: sTime,
                          );
                          final isNow = status == 'Sedang Berlangsung';

                          return InkWell(
                            onTap: () {
                              setState(() => _selectedSessionIndex = sIdx);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0F172A)
                                    : (isNow ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF0F172A)
                                      : (isNow ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
                                  width: isSelected || isNow ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isNow ? Icons.sensors_rounded : Icons.schedule_rounded,
                                    size: 14,
                                    color: isSelected ? Colors.white : (isNow ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Sesi ${sIdx + 1} ($sTime)',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected ? Colors.white : (isNow ? const Color(0xFF15803D) : const Color(0xFF334155)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Search & Filter Bar
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Cari nama atau kode ruangan...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 4. Room Cards Grid
              if (filteredRoomIds.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.meeting_room_outlined, size: 54, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),
                      Text(
                        'Tidak ada ruangan yang ditemukan untuk sesi ini.',
                        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = isDesktop
                        ? (constraints.maxWidth > 1000 ? 3 : 2)
                        : 1;

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 250,
                      ),
                      itemCount: filteredRoomIds.length,
                      itemBuilder: (context, idx) {
                        final rId = filteredRoomIds[idx];
                        final rInfo = roomsInfoMap[rId] ?? {};
                        final rName = (rInfo['name'] ?? rId).toString();
                        final rSeats = roomSeatsMap[rId] ?? [];
                        final rCap = (rInfo['capacity'] as num?)?.toInt() ?? rSeats.length;

                        // Proctor key: e.g. proctor_d{dayIndex}_s{sessionIndex}_{roomId}
                        final pKey1 = 'proctor_d${_selectedDayIndex}_s${_selectedSessionIndex}_$rId';
                        final pKey2 = 'd${_selectedDayIndex}_s${_selectedSessionIndex}_$rId';
                        final proctorName = proctorGrid[pKey1] ?? proctorGrid[pKey2] ?? 'Belum ditentukan';

                        // Calculate live counts in room
                        int totalHadir = 0;
                        int totalWorking = 0;
                        int totalCompleted = 0;
                        int totalLeftApp = 0;

                        for (var seat in rSeats) {
                          final sId = (seat['studentId'] ?? seat['id'] ?? '').toString().toLowerCase().trim();
                          final sNis = (seat['nis'] ?? '').toString().toLowerCase().trim();
                          final sName = (seat['displayName'] ?? seat['studentName'] ?? seat['name'] ?? '').toString().toLowerCase().trim();

                          final isAtt = attendedKeys.contains(sId) || attendedKeys.contains(sNis) || attendedKeys.contains(sName);
                          final rt = (sId.isNotEmpty ? realtimeMap[sId] : null) ??
                              (sNis.isNotEmpty ? realtimeMap[sNis] : null);
                          final sub = (sId.isNotEmpty ? submissionsMap[sId] : null) ??
                              (sNis.isNotEmpty ? submissionsMap[sNis] : null);

                          final isComp = rt?['isCompleted'] == true || rt?['status'] == 'completed' || sub?['isCompleted'] == true;
                          final isLeft = !isComp && (rt?['isLeftApp'] == true || rt?['status'] == 'left_app');
                          final isWork = rt?['isWorking'] == true || rt?['status'] == 'in_progress' || rt?['status'] == 'working';

                          if (isComp) {
                            totalCompleted++;
                            totalHadir++;
                          } else if (isLeft) {
                            totalLeftApp++;
                            totalHadir++;
                          } else if (isWork) {
                            totalWorking++;
                            totalHadir++;
                          } else if (isAtt) {
                            totalHadir++;
                          }
                        }

                        final totalBelumHadir = (rSeats.length - totalHadir).clamp(0, 9999);

                        return _buildRoomCardItem(
                          context: context,
                          roomId: rId,
                          roomName: rName,
                          capacity: rCap,
                          filledSeatsCount: rSeats.length,
                          proctorName: proctorName,
                          totalHadir: totalHadir,
                          totalWorking: totalWorking,
                          totalCompleted: totalCompleted,
                          totalLeftApp: totalLeftApp,
                          totalBelumHadir: totalBelumHadir,
                          sessionStatus: currentSessionStatus,
                          sessionTime: currentSessionTime,
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCardItem({
    required BuildContext context,
    required String roomId,
    required String roomName,
    required int capacity,
    required int filledSeatsCount,
    required String proctorName,
    required int totalHadir,
    required int totalWorking,
    required int totalCompleted,
    required int totalLeftApp,
    required int totalBelumHadir,
    required String sessionStatus,
    required String sessionTime,
  }) {
    final isWorkingNow = sessionStatus == 'Sedang Berlangsung';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isWorkingNow ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0), width: isWorkingNow ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isWorkingNow ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: isWorkingNow ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.meeting_room_rounded,
                      size: 18,
                      color: isWorkingNow ? const Color(0xFF16A34A) : const Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      roomName,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    '$filledSeatsCount Kursi',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),

          // Body Stats
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Proctor Info
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Pengawas: $proctorName',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF475569), fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // KPI Counter Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildPillStat(
                      label: 'Hadir',
                      count: totalHadir,
                      color: const Color(0xFF059669),
                      bg: const Color(0xFFECFDF5),
                    ),
                    _buildPillStat(
                      label: 'Mengerjakan',
                      count: totalWorking,
                      color: const Color(0xFF2563EB),
                      bg: const Color(0xFFEFF6FF),
                    ),
                    _buildPillStat(
                      label: 'Selesai',
                      count: totalCompleted,
                      color: const Color(0xFF7C3AED),
                      bg: const Color(0xFFF5F3FF),
                    ),
                    if (totalLeftApp > 0)
                      _buildPillStat(
                        label: 'Keluar App',
                        count: totalLeftApp,
                        color: const Color(0xFFDC2626),
                        bg: const Color(0xFFFEF2F2),
                      ),
                    _buildPillStat(
                      label: 'Belum Hadir',
                      count: totalBelumHadir,
                      color: const Color(0xFF64748B),
                      bg: const Color(0xFFF1F5F9),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),

          // CTA Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final roomUrl = '/admin/event/${widget.eventId}/room/$roomId'
                      '?dayIndex=$_selectedDayIndex'
                      '&sessionIndex=$_selectedSessionIndex'
                      '&eventName=${Uri.encodeComponent(widget.eventName)}'
                      '&roomName=${Uri.encodeComponent(roomName)}';
                  context.push(roomUrl);
                },
                icon: const Icon(Icons.visibility_rounded, size: 15),
                label: Text('Pantau Denah Ruangan', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillStat({
    required String label,
    required int count,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $count',
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
