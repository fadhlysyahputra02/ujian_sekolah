import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/student.dart';

class StudentEventDetailPage extends StatefulWidget {
  final String eventId;
  final String eventName;

  const StudentEventDetailPage({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<StudentEventDetailPage> createState() => _StudentEventDetailPageState();
}

class _StudentEventDetailPageState extends State<StudentEventDetailPage> {
  bool _isLoading = true;
  Student? _student;
  String _schoolId = '';
  String? _myClassId;
  String? _myClassName;

  // Seat Allocation Info
  Map<String, dynamic>? _allocatedSeat;
  
  // Timetable & Sessions
  List<Map<String, dynamic>> _myTimetable = [];
  Map<String, Map<String, dynamic>> _sessionMap = {};
  
  @override
  void initState() {
    super.initState();
    _loadStudentAndEventDetails();
  }

  Future<void> _loadStudentAndEventDetails() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Wait for auth to load
    if (authService.isLoading || authService.schoolId == null || authService.schoolId!.isEmpty) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!authService.isLoading && authService.schoolId != null && authService.schoolId!.isNotEmpty) {
          break;
        }
      }
    }

    _schoolId = authService.schoolId ?? '';
    final uid = authService.user?.uid ?? '';

    if (_schoolId.isEmpty || uid.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch Student profile
      final studentSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('students')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (studentSnap.docs.isNotEmpty) {
        final doc = studentSnap.docs.first;
        _student = Student.fromFirestore(doc);
        
        // Resolve student's class name by looking up in classes collection
        final classSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('classes')
            .get();

        for (var cDoc in classSnap.docs) {
          final cData = cDoc.data();
          final sIds = cData['studentIds'];
          if (sIds is List && sIds.contains(doc.id)) {
            _myClassId = cDoc.id;
            _myClassName = cData['name'] ?? cDoc.id;
            break;
          }
        }

        // Fallback: Check if student document stores className directly
        _myClassName ??= (doc.data()['className'] ?? doc.data()['classId'] ?? _student!.angkatan).toString();
        _myClassId ??= _myClassName;

        // 2. Fetch Active Seat Allocation
        final eventRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('events')
            .doc(widget.eventId);

        final allocSnap = await eventRef.collection('allocations').limit(1).get();
        if (allocSnap.docs.isNotEmpty) {
          final activeAllocId = allocSnap.docs.first.id;
          final allocRef = eventRef.collection('allocations').doc(activeAllocId);
          
          Map<String, dynamic>? seatData;
          
          // 1. Try by studentId
          var seatSnap = await allocRef.collection('seats').where('studentId', isEqualTo: doc.id).limit(1).get();
          if (seatSnap.docs.isNotEmpty) {
            seatData = seatSnap.docs.first.data();
          }
          
          // 2. Try by nis
          if (seatData == null && _student!.nis.isNotEmpty) {
            seatSnap = await allocRef.collection('seats').where('nis', isEqualTo: _student!.nis).limit(1).get();
            if (seatSnap.docs.isNotEmpty) {
              seatData = seatSnap.docs.first.data();
            }
          }
          
          // 3. Try by studentName / displayName
          if (seatData == null && _student!.displayName.isNotEmpty) {
            seatSnap = await allocRef.collection('seats').where('studentName', isEqualTo: _student!.displayName).limit(1).get();
            if (seatSnap.docs.isNotEmpty) {
              seatData = seatSnap.docs.first.data();
            } else {
              seatSnap = await allocRef.collection('seats').where('displayName', isEqualTo: _student!.displayName).limit(1).get();
              if (seatSnap.docs.isNotEmpty) {
                seatData = seatSnap.docs.first.data();
              }
            }
          }

          if (seatData != null) {
            _allocatedSeat = seatData;
          }
        }

        // 3. Fetch Sessions and build SessionMap
        final sessionsSnap = await eventRef.collection('sessions').get();
        for (var sDoc in sessionsSnap.docs) {
          final sData = sDoc.data();
          sData['id'] = sDoc.id;
          _sessionMap[sDoc.id] = sData;
          // Support fallback matching tempId as well
          final tempId = sData['tempId']?.toString();
          if (tempId != null && tempId.isNotEmpty) {
            _sessionMap[tempId] = sData;
          }
        }

        // 4. Fetch Timetable & Filter for student's class
        final timetableSnap = await eventRef.collection('timetable').get();
        final filteredTimetable = <Map<String, dynamic>>[];
        
        final cleanMyClass = _myClassName?.toLowerCase().replaceAll(' ', '') ?? '';
        final cleanMyClassId = _myClassId?.toLowerCase().replaceAll(' ', '') ?? '';

        for (var tDoc in timetableSnap.docs) {
          final tData = tDoc.data();
          final tClass = (tData['className'] ?? tData['classId'] ?? '').toString().trim();
          final tClassId = (tData['classId'] ?? '').toString().trim();
          
          final cleanTClass = tClass.toLowerCase().replaceAll(' ', '');
          final cleanTClassId = tClassId.toLowerCase().replaceAll(' ', '');

          bool matched = cleanTClass == cleanMyClass || 
                         cleanTClassId == cleanMyClassId ||
                         (cleanMyClass.isNotEmpty && cleanTClass.contains(cleanMyClass)) ||
                         (cleanMyClassId.isNotEmpty && cleanTClassId.contains(cleanMyClassId));
                         
          if (matched) {
            filteredTimetable.add(tData);
          }
        }
        
        _myTimetable = filteredTimetable;
      }
    } catch (e) {
      debugPrint("Error loading student event details: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          title: Text('Memuat Jadwal...', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    // Group my timetable by Date
    final Map<String, List<Map<String, dynamic>>> timetableByDate = {};
    for (var item in _myTimetable) {
      final sId = item['sessionId']?.toString() ?? '';
      final session = _sessionMap[sId];
      
      String dateStr = 'Tanggal Belum Diatur';
      if (session != null && session['date'] != null) {
        final dVal = session['date'];
        DateTime? dt;
        if (dVal is Timestamp) {
          dt = dVal.toDate();
        } else if (dVal is String) {
          dt = DateTime.tryParse(dVal);
        }
        if (dt != null) {
          dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(dt);
        }
      }
      timetableByDate.putIfAbsent(dateStr, () => []).add(item);
    }

    // Sort dates
    final sortedDates = timetableByDate.keys.toList()..sort((a, b) {
      if (a.contains('Belum') || b.contains('Belum')) return 1;
      return a.compareTo(b);
    });

    final roomName = _allocatedSeat?['roomName'] ?? _allocatedSeat?['roomId'] ?? 'Belum Alokasi';
    final seatNumber = _allocatedSeat?['seatNumber']?.toString() ?? '-';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/student/ujian');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.eventName,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Jadwal & Kartu Peserta Ujian',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFA7F3D0)),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student Card Box
            _buildParticipantCard(roomName, seatNumber),
            const SizedBox(height: 28),

            // Schedule Section Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Jadwal Ujian Anda',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_myTimetable.isEmpty)
              _buildEmptySchedule()
            else
              ...sortedDates.map((dateKey) {
                final dayItems = timetableByDate[dateKey]!;
                // Sort items by session startTime
                dayItems.sort((a, b) {
                  final sessA = _sessionMap[a['sessionId']];
                  final sessB = _sessionMap[b['sessionId']];
                  final startA = sessA?['startTime']?.toString() ?? '';
                  final startB = sessB?['startTime']?.toString() ?? '';
                  return startA.compareTo(startB);
                });

                return _buildDayScheduleGroup(dateKey, dayItems);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantCard(String roomName, String seatNumber) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF065F46), Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF047857).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background accents
          Positioned(
            right: -20,
            top: -20,
            child: CircleAvatar(
              radius: 80,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -40,
            child: CircleAvatar(
              radius: 100,
              backgroundColor: Colors.white.withValues(alpha: 0.03),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'KARTU PESERTA UJIAN',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFA7F3D0),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Icon(Icons.qr_code_rounded, color: Colors.white60, size: 28),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  _student?.displayName ?? 'Siswa SesiCermat',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'NISN/NIS: ${_student?.nis ?? "-"}  •  Kelas: ${_myClassName ?? "-"}',
                  style: GoogleFonts.inter(
                    color: const Color(0xFFA7F3D0),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RUANGAN',
                              style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              roomName,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 32,
                        width: 1,
                        color: Colors.white24,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NOMOR KURSI',
                              style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              seatNumber,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayScheduleGroup(String dateKey, List<Map<String, dynamic>> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Text(
              dateKey,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          // Sesi-sesi pada hari ini
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              final item = items[index];
              final sId = item['sessionId']?.toString() ?? '';
              final session = _sessionMap[sId];
              final subjectName = item['subjectName'] ?? 'Mata Pelajaran';
              
              final sName = session?['name'] ?? session?['sessionName'] ?? 'Sesi ${index + 1}';
              final startTime = session?['startTime'] ?? '';
              final endTime = session?['endTime'] ?? '';
              final timeLabel = startTime.isNotEmpty ? '$startTime - $endTime' : 'Waktu belum diatur';

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.menu_book_rounded, color: Color(0xFF10B981), size: 22),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subjectName,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$sName ($timeLabel)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySchedule() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_busy_rounded, color: Color(0xFF94A3B8), size: 48),
          const SizedBox(height: 12),
          Text(
            'Belum Ada Jadwal Ujian',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Jadwal ujian untuk kelas Anda belum diterbitkan oleh pihak sekolah.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
