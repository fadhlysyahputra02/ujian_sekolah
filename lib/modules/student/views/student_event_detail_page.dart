import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/student.dart';
import '../../../core/widgets/app_refresh_indicator.dart';
import 'student_exam_page.dart';

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

  // Periodic timer that ticks every 30s to re-evaluate session time-based buttons
  Timer? _clockTimer;

  // Offset between server time and local device time (used for accurate session checks)
  Duration _serverTimeOffset = Duration.zero;

  // Event Date Range
  String _eventDateRange = 'Tanggal belum diatur';
  DateTime? _eventStartDate;

  // Seat Allocation Info
  Map<String, dynamic>? _allocatedSeat;

  // Timetable & Sessions
  List<Map<String, dynamic>> _myTimetable = [];
  final Map<String, Map<String, dynamic>> _sessionMap = {};

  @override
  void initState() {
    super.initState();
    _loadStudentAndEventDetails();
    // Tick every 30 seconds so time-based session buttons update without requiring a manual refresh
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStudentAndEventDetails() async {
    _allocatedSeat = null;
    _myClassId = null;
    _myClassName = null;
    _sessionMap.clear();
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
      final db = FirebaseFirestore.instance;
      final schoolRef = db.collection('schools').doc(_schoolId);
      final eventRef = schoolRef.collection('events').doc(widget.eventId);

      // Fetch server time to calculate offset against device local clock
      try {
        final serverTsRef = db.collection('_server_time').doc('now');
        await serverTsRef.set({'ts': FieldValue.serverTimestamp()});
        final serverDoc = await serverTsRef.get();
        final serverTs = serverDoc.data()?['ts'];
        if (serverTs is Timestamp) {
          final serverNow = serverTs.toDate();
          _serverTimeOffset = serverNow.difference(DateTime.now());
          debugPrint('🕐 Server time offset: ${_serverTimeOffset.inSeconds}s');
        }
      } catch (_) {
        _serverTimeOffset = Duration.zero;
      }

      // PARALLEL BATCH 1: Fetch Student profile, Classes, Event doc, Sessions, Timetable, Allocations concurrently
      final results = await Future.wait([
        schoolRef.collection('students').where('uid', isEqualTo: uid).limit(1).get(),
        schoolRef.collection('classes').get(),
        eventRef.get(),
        eventRef.collection('sessions').get(),
        eventRef.collection('timetable').get(),
        eventRef.collection('allocations').get(),
      ]);

      final studentSnap = results[0] as QuerySnapshot;
      final classSnap = results[1] as QuerySnapshot;
      final eventDoc = results[2] as DocumentSnapshot;
      final sessionsSnap = results[3] as QuerySnapshot;
      final timetableSnap = results[4] as QuerySnapshot;
      final allocSnap = results[5] as QuerySnapshot;

      if (studentSnap.docs.isNotEmpty) {
        final doc = studentSnap.docs.first;
        _student = Student.fromFirestore(doc);

        // Resolve student's class name
        for (var cDoc in classSnap.docs) {
          final cData = cDoc.data() as Map<String, dynamic>;
          final sIds = cData['studentIds'];
          if (sIds is List && sIds.contains(doc.id)) {
            _myClassId = cDoc.id;
            _myClassName = cData['name'] ?? cDoc.id;
            break;
          }
        }

        final docMap = doc.data() as Map<String, dynamic>;
        _myClassName ??= (docMap['className'] ?? docMap['classId'] ?? _student!.angkatan).toString();
        _myClassId ??= _myClassName;

        // Process Event Doc Date Range
        final Map<String, dynamic> evData = eventDoc.exists ? (eventDoc.data() as Map<String, dynamic>? ?? {}) : {};
        if (evData.isNotEmpty) {
          final sd = evData['startDate'];
          final ed = evData['endDate'];
          DateTime? start = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
          DateTime? end = ed is Timestamp ? ed.toDate() : (ed is String ? DateTime.tryParse(ed) : null);
          _eventStartDate = start;
          final dateFormat = DateFormat('dd MMM yyyy', 'id_ID');
          if (start != null && end != null) {
            _eventDateRange = '${dateFormat.format(start)} - ${dateFormat.format(end)}';
          } else {
            _eventDateRange = 'Tanggal belum diatur';
          }
        }

        // Process Sessions
        for (var sDoc in sessionsSnap.docs) {
          final sData = sDoc.data() as Map<String, dynamic>;
          sData['id'] = sDoc.id;
          _sessionMap[sDoc.id] = sData;
          final tempId = sData['tempId']?.toString();
          if (tempId != null && tempId.isNotEmpty) {
            _sessionMap[tempId] = sData;
          }
        }

        // Process Timetable Filter for student's class
        final filteredTimetable = <Map<String, dynamic>>[];
        final cleanMyClass = _myClassName?.toLowerCase().replaceAll(' ', '') ?? '';
        final cleanMyClassId = _myClassId?.toLowerCase().replaceAll(' ', '') ?? '';

        for (var tDoc in timetableSnap.docs) {
          final tData = tDoc.data() as Map<String, dynamic>;
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

        // PARALLEL BATCH 2: Fetch Seat allocation & Questions readiness concurrently
        final List<Future<void>> parallelTasks = [];

        // Task A: Seat lookup (pick LATEST allocation if multiple exist after re-allocation)
        if (allocSnap.docs.isNotEmpty) {
          final sortedAllocDocs = List<QueryDocumentSnapshot>.from(allocSnap.docs);
          sortedAllocDocs.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>?)?['createdAt'];
            final bTime = (b.data() as Map<String, dynamic>?)?['createdAt'];
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });
          final activeAllocId = sortedAllocDocs.first.id;
          final allocRef = eventRef.collection('allocations').doc(activeAllocId);
          parallelTasks.add(
            allocRef.collection('seats').get().then((seatSnap) {
              for (var sDoc in seatSnap.docs) {
                final sData = sDoc.data();
                if (sData['studentId'] == doc.id ||
                    (sData['nis'] != null && sData['nis'].toString().isNotEmpty && sData['nis'].toString() == _student!.nis) ||
                    (sData['studentName'] != null && sData['studentName'] == _student!.displayName) ||
                    (sData['displayName'] != null && sData['displayName'] == _student!.displayName)) {
                  _allocatedSeat = sData;
                  break;
                }
              }
            }).catchError((_) {}),
          );
        }

        // Task B: Question readiness & breakdown check for all subjects in parallel
        final studentAngkatan = (_student?.angkatan != null && _student!.angkatan.trim().isNotEmpty)
            ? _student!.angkatan.trim()
            : (_myClassName ?? '').trim();

        for (var item in filteredTimetable) {
          final subId = (item['subjectId'] ?? item['subjectName'] ?? '').toString();
          final subName = (item['subjectName'] ?? '').toString();

          if (subId.isNotEmpty) {
            parallelTasks.add(
              _countAndCategorizeQuestions(
                eventRef: eventRef,
                subId: subId,
                subName: subName,
                item: item,
                studentAngkatan: studentAngkatan,
                studentClass: _myClassName ?? '',
              ),
            );
          }
        }

        // Task C: Submission completion check for all subjects in parallel
        parallelTasks.add(
          eventRef.collection('submissions').get().then((subSnap) {
            for (var item in filteredTimetable) {
              final subId = (item['subjectId'] ?? item['subjectName'] ?? '').toString();
              final subName = (item['subjectName'] ?? '').toString();
              final docId = '${_student!.id}_$subId';

              for (var sDoc in subSnap.docs) {
                final sData = sDoc.data();
                final sStudentId = (sData['studentId'] ?? '').toString();
                final sSubId = (sData['subjectId'] ?? sData['subjectName'] ?? '').toString();
                final isCompleted = sData['isCompleted'] == true;

                final matchesStudent = sStudentId == _student!.id ||
                    (sData['nis'] != null && sData['nis'].toString().isNotEmpty && sData['nis'].toString() == _student!.nis);

                final matchesSubject = sSubId == subId || sSubId == subName || sDoc.id == docId;

                if (isCompleted && matchesStudent && matchesSubject) {
                  item['isSubmitted'] = true;
                  item['submittedScore'] = sData['score'];
                  debugPrint('✅ Subject "$subName" is already submitted (Score: ${sData['score']})');
                  break;
                }
              }
            }
          }).catchError((e) {
            debugPrint("Error checking submissions: $e");
          }),
        );

        await Future.wait(parallelTasks);

        if (_allocatedSeat == null) {
          final allStudentsSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(_schoolId)
              .collection('students')
              .get();

          _allocatedSeat = _synthesizeStudentSeatLocation(
            evData: evData,
            allStudentDocs: allStudentsSnap.docs,
            myStudentId: doc.id,
            myNis: _student?.nis ?? '',
            myName: _student?.displayName ?? '',
            myClassName: _myClassName ?? '',
          );
          if (_allocatedSeat != null) {
            debugPrint('🎯 Synthesized seat for ${_student?.displayName}: Room ${_allocatedSeat!['roomName']}, Seat #${_allocatedSeat!['seatNumber']}');
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
          title: Text('Memuat Detail Ujian...', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    // Group timetable by DateTime for CHRONOLOGICAL sorting
    final Map<DateTime, Map<String, dynamic>> dateGroupMap = {};

    for (var item in _myTimetable) {
      final sId = item['sessionId']?.toString() ?? '';
      final session = _sessionMap[sId];

      DateTime itemDate = DateTime(2099, 12, 31); // Default far future
      if (session != null && session['date'] != null) {
        final dVal = session['date'];
        if (dVal is Timestamp) {
          itemDate = dVal.toDate();
        } else if (dVal is String) {
          final dt = DateTime.tryParse(dVal);
          if (dt != null) itemDate = dt;
        }
      }

      // Fallback date calculation from dayIndex relative to event startDate
      if (itemDate.year == 2099) {
        final dayIdx = (item['dayIndex'] as num?)?.toInt() ?? 0;
        if (_eventStartDate != null) {
          itemDate = _eventStartDate!.add(Duration(days: dayIdx));
        } else {
          itemDate = DateTime(2026, 8, 23).add(Duration(days: dayIdx));
        }
      }

      final normDate = DateTime(itemDate.year, itemDate.month, itemDate.day);
      final dateStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(normDate);

      if (!dateGroupMap.containsKey(normDate)) {
        dateGroupMap[normDate] = {
          'dateStr': dateStr,
          'date': normDate,
          'items': <Map<String, dynamic>>[item],
        };
      } else {
        (dateGroupMap[normDate]!['items'] as List<Map<String, dynamic>>).add(item);
      }
    }

    // Sort dates CHRONOLOGICALLY
    final sortedDateKeys = dateGroupMap.keys.toList()..sort((a, b) => a.compareTo(b));

    final roomName = _allocatedSeat?['roomName'] ?? _allocatedSeat?['roomId'] ?? 'Belum Alokasi';
    final seatNumber = _allocatedSeat?['seatNumber']?.toString() ?? '-';
    final participantNumber = _allocatedSeat?['participantNumber']?.toString() ?? _student?.nis ?? '-';

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
              context.go('/student');
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
              'Kartu Peserta & Jadwal Ujian',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFA7F3D0)),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        top: false,
        child: AppRefreshIndicator(
          onRefresh: () async {
            await _loadStudentAndEventDetails();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 40.0),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card tanpa QR, Nama Event, Tanggal Event, No Peserta, Ruangan, No Kursi
              _buildParticipantCard(
                roomName: roomName,
                seatNumber: seatNumber,
                participantNumber: participantNumber,
                dateRange: _eventDateRange,
              ),
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
                      fontSize: 17,
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
                ...sortedDateKeys.map((dateKey) {
                  final group = dateGroupMap[dateKey]!;
                  final dateStr = group['dateStr'] as String;
                  final dayItems = group['items'] as List<Map<String, dynamic>>;

                  dayItems.sort((a, b) {
                    final sessA = _sessionMap[a['sessionId']];
                    final sessB = _sessionMap[b['sessionId']];
                    final startA = sessA?['startTime']?.toString() ?? '';
                    final startB = sessB?['startTime']?.toString() ?? '';
                    return startA.compareTo(startB);
                  });

                  return _buildDayScheduleGroup(dateStr, dayItems, sortedDateKeys.indexOf(dateKey));
                }),
            ],
          ),
        ),
      ),
    ),
  );
}

  /// Card Peserta Ujian berisi: Nama Event Ujian, Tanggal Event, No Peserta, Ruangan, No Kursi
  Widget _buildParticipantCard({
    required String roomName,
    required String seatNumber,
    required String participantNumber,
    required String dateRange,
  }) {
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
          // Background circles accent
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
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row: Event Name, Date Range
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'KARTU PESERTA UJIAN',
                              style: GoogleFonts.inter(
                                color: const Color(0xFFA7F3D0),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.eventName,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFFA7F3D0)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  dateRange,
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFFA7F3D0),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 14),

                // Student Identity Info
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _student?.displayName ?? 'Siswa SesiCermat',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'NIS: ${_student?.nis ?? "-"}  •  Kelas: ${_myClassName ?? "-"}',
                            style: GoogleFonts.inter(
                              color: const Color(0xFFA7F3D0),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Grid Details: Nomor Peserta, Ruangan, Nomor Kursi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      // Nomor Peserta
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NO. PESERTA',
                              style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              participantNumber,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(height: 28, width: 1, color: Colors.white24),
                      const SizedBox(width: 12),
                      // Ruangan
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RUANGAN',
                              style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              roomName,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(height: 28, width: 1, color: Colors.white24),
                      const SizedBox(width: 12),
                      // Nomor Kursi
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NO. KURSI',
                              style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              seatNumber,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
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

  void _showEnlargedQrDialog({
    required BuildContext context,
    required String qrData,
    required String participantNumber,
    required String roomName,
    required String seatNumber,
    String? subjectName,
    String? sessionName,
    int? dayIndex,
    int? sessionIndex,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StreamBuilder<QuerySnapshot>(
          stream: (dayIndex != null && sessionIndex != null && _student?.id != null)
              ? FirebaseFirestore.instance
                  .collection('schools')
                  .doc(_schoolId)
                  .collection('events')
                  .doc(widget.eventId)
                  .collection('attendances')
                  .where('studentId', isEqualTo: _student!.id)
                  .snapshots()
              : null,
          builder: (ctx, attSnap) {
            if (attSnap.hasData && dayIndex != null && sessionIndex != null) {
              final docs = attSnap.data?.docs ?? [];
              for (var d in docs) {
                final data = d.data() as Map<String, dynamic>? ?? {};
                final isAtt = data['isAttended'] == true;
                final aDay = (data['dayIndex'] as num?)?.toInt();
                final aSess = (data['sessionIndex'] as num?)?.toInt();

                if (isAtt && aDay == dayIndex && aSess == sessionIndex) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
                      Navigator.of(dialogCtx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ Presensi berhasil! Sesi ${sessionName ?? ""} telah diverifikasi oleh pengawas.'),
                          backgroundColor: const Color(0xFF059669),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  });
                  break;
                }
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Dialog Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF10B981), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'QR Sesi Ujian',
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                  const SizedBox(height: 20),

                  // Large QR Code Display Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      size: 320.0,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Detailed Student & Exam Info Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        _buildQrDetailRow('Nama Siswa', _student?.displayName ?? '-'),
                        const Divider(height: 16, color: Color(0xFFE2E8F0)),
                        _buildQrDetailRow('NIS / Kelas', '${_student?.nis ?? "-"} • ${_myClassName ?? "-"}'),
                        const Divider(height: 16, color: Color(0xFFE2E8F0)),
                        _buildQrDetailRow('Event Ujian', widget.eventName),
                        const Divider(height: 16, color: Color(0xFFE2E8F0)),
                        _buildQrDetailRow('No. Peserta', participantNumber),
                        const Divider(height: 16, color: Color(0xFFE2E8F0)),
                        _buildQrDetailRow('Ruangan / Kursi', '$roomName (Kursi $seatNumber)'),
                        if (subjectName != null) ...[
                          const Divider(height: 16, color: Color(0xFFE2E8F0)),
                          _buildQrDetailRow('Mata Pelajaran', subjectName),
                        ],
                        if (sessionName != null) ...[
                          const Divider(height: 16, color: Color(0xFFE2E8F0)),
                          _buildQrDetailRow('Sesi Ujian', sessionName),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Tunjukkan QR Code ini kepada pengawas untuk verifikasi kehadiran ujian.',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  },
);
}

  Widget _buildQrDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  bool _isAngkatanMatch(String qAngkatan, String studentAngkatan, String studentClass) {
    final qClean = qAngkatan.trim().toLowerCase();
    if (qClean.isEmpty || qClean == 'semua' || qClean == 'all' || qClean == '-') {
      return true;
    }

    final sAngClean = studentAngkatan.trim().toLowerCase();
    final sClassClean = studentClass.trim().toLowerCase();

    if (sAngClean.isNotEmpty && qClean == sAngClean) return true;
    if (sClassClean.isNotEmpty && qClean == sClassClean) return true;

    if (sAngClean.isNotEmpty && (qClean.contains(sAngClean) || sAngClean.contains(qClean))) return true;
    if (sClassClean.isNotEmpty && (qClean.contains(sClassClean) || sClassClean.contains(qClean))) return true;

    final RegExp numReg = RegExp(r'\d+');
    final qNum = numReg.firstMatch(qClean)?.group(0);
    final sAngNum = numReg.firstMatch(sAngClean)?.group(0);
    final sClassNum = numReg.firstMatch(sClassClean)?.group(0);

    if (qNum != null && qNum.isNotEmpty) {
      if (sAngNum != null && sAngNum == qNum) return true;
      if (sClassNum != null && sClassNum == qNum) return true;
    }
    return false;
  }

  Future<void> _countAndCategorizeQuestions({
    required DocumentReference eventRef,
    required String subId,
    required String subName,
    required Map<String, dynamic> item,
    required String studentAngkatan,
    required String studentClass,
  }) async {
    try {
      List<QueryDocumentSnapshot> rawDocs = [];

      try {
        final qSnap1 = await eventRef.collection('subjects').doc(subId).collection('questions').get();
        if (qSnap1.docs.isNotEmpty) {
          rawDocs = qSnap1.docs;
        }
      } catch (_) {}

      if (rawDocs.isEmpty && subName.isNotEmpty && subName != subId) {
        try {
          final qSnap2 = await eventRef.collection('subjects').doc(subName).collection('questions').get();
          if (qSnap2.docs.isNotEmpty) {
            rawDocs = qSnap2.docs;
          }
        } catch (_) {}
      }

      if (rawDocs.isEmpty) {
        try {
          final qSnap3 = await eventRef
              .collection('questions')
              .where('subjectId', isEqualTo: subId)
              .get();
          if (qSnap3.docs.isNotEmpty) {
            rawDocs = qSnap3.docs;
          }
        } catch (_) {}
      }

      List<QueryDocumentSnapshot> filtered = rawDocs.where((d) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        final qAng = (data['angkatan'] ?? data['grade'] ?? data['targetAngkatan'] ?? '').toString();
        return _isAngkatanMatch(qAng, studentAngkatan, studentClass);
      }).toList();

      if (filtered.isEmpty && rawDocs.isNotEmpty) {
        filtered = rawDocs;
      }

      int pgCount = 0;
      int essayCount = 0;

      for (var d in filtered) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        final type = (data['type'] ?? '').toString();
        final opts = data['options'];
        final hasOptions = opts is Map && opts.isNotEmpty;

        if (type == 'pilihan_ganda' || (type != 'essay' && hasOptions)) {
          pgCount++;
        } else {
          essayCount++;
        }
      }

      final totalCount = pgCount + essayCount;
      item['isQuestionReady'] = totalCount > 0;
      item['questionCount'] = totalCount;
      item['pgQuestionCount'] = pgCount;
      item['essayQuestionCount'] = essayCount;
    } catch (e) {
      item['isQuestionReady'] = false;
      item['questionCount'] = 0;
      item['pgQuestionCount'] = 0;
      item['essayQuestionCount'] = 0;
    }
  }

  void _showSessionGuidelinesDialog({
    required Map<String, dynamic> item,
    required String subjectName,
    required String sName,
    required String timeLabel,
  }) {
    final sId = item['sessionId']?.toString() ?? '';
    final session = _sessionMap[sId];
    
    String durationText = 'Menyesuaikan jadwal';
    if (session != null) {
      final startTimeStr = (session['startTime'] ?? '').toString();
      final endTimeStr = (session['endTime'] ?? '').toString();
      if (startTimeStr.isNotEmpty && endTimeStr.isNotEmpty) {
        try {
          final startParts = startTimeStr.split(':');
          final endParts = endTimeStr.split(':');
          final startMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
          final endMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
          final diff = endMin - startMin;
          if (diff > 0) {
            durationText = '$diff Menit';
          }
        } catch (_) {}
      }
    }

    final questionCount = item['questionCount'] ?? 0;
    final pgCount = item['pgQuestionCount'] ?? 0;
    final essayCount = item['essayQuestionCount'] ?? 0;
    final isReady = item['isQuestionReady'] == true;
    final questionCountText = isReady ? '$questionCount Butir Soal' : 'Sedang disiapkan';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_rounded, color: Color(0xFF2563EB), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Panduan Ujian',
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                subjectName,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
              Text(
                '$sName ($timeLabel)',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE2E8F0)),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  const Icon(Icons.timer_rounded, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text(
                    'Durasi Ujian:',
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  ),
                  const Spacer(),
                  Text(
                    durationText,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  const Icon(Icons.quiz_rounded, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text(
                    'Jumlah Soal:',
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  ),
                  const Spacer(),
                  Text(
                    questionCountText,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
              if (isReady && questionCount > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF059669)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Pilihan Ganda', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF047857), fontWeight: FontWeight.w600)),
                                    Text('$pgCount Soal', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF065F46), fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF2F8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFBCFE8)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFFDB2777)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Esai / Essay', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFBE185D), fontWeight: FontWeight.w600)),
                                    Text('$essayCount Soal', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9D174D), fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE2E8F0)),
              const SizedBox(height: 12),
              
              Text(
                'Tata Tertib Ujian:',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              _buildRuleItem('1. Murid dilarang keluar dari aplikasi selama ujian berlangsung.'),
              _buildRuleItem('2. Jawaban otomatis tersimpan sebagai draf setiap kali Anda memilih opsi.'),
              _buildRuleItem('3. Pastikan koneksi internet stabil sebelum mengirimkan ujian.'),
              _buildRuleItem('4. Tombol "Kerjakan" akan otomatis aktif saat waktu sesi dimulai.'),
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Saya Mengerti', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  int _naturalCompare(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final matchesA = re.allMatches(a).toList();
    final matchesB = re.allMatches(b).toList();

    for (int i = 0; i < min(matchesA.length, matchesB.length); i++) {
      final strA = matchesA[i].group(0)!;
      final strB = matchesB[i].group(0)!;

      final numA = int.tryParse(strA);
      final numB = int.tryParse(strB);

      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
      } else {
        final cmp = strA.toLowerCase().compareTo(strB.toLowerCase());
        if (cmp != 0) return cmp;
      }
    }
    return matchesA.length.compareTo(matchesB.length);
  }

  Map<String, dynamic>? _synthesizeStudentSeatLocation({
    required Map<String, dynamic> evData,
    required List<QueryDocumentSnapshot> allStudentDocs,
    required String myStudentId,
    required String myNis,
    required String myName,
    required String myClassName,
  }) {
    try {
      final roomsList = <Map<String, dynamic>>[];
      final rawRooms = evData['rooms'];
      if (rawRooms is List) {
        for (var r in rawRooms) {
          if (r is Map) roomsList.add(Map<String, dynamic>.from(r));
        }
      }

      final draftState = evData['draftState'] as Map<String, dynamic>?;
      final rawRoomAssignments = draftState?['step6']?['roomAssignments'] as Map<String, dynamic>? ??
          draftState?['roomAssignments'] as Map<String, dynamic>? ??
          evData['roomAssignments'] as Map<String, dynamic>? ??
          {};

      if (roomsList.isEmpty || rawRoomAssignments.isEmpty) return null;

      final Map<String, List<Map<String, dynamic>>> classRealStudents = {};
      for (var sDoc in allStudentDocs) {
        final sData = sDoc.data() as Map<String, dynamic>;
        if (sData['archived'] == true || sData['disabled'] == true) continue;

        final sName = (sData['displayName'] ?? sData['name'] ?? sData['fullName'] ?? '').toString().trim();
        final sNis = (sData['nis'] ?? sData['nisn'] ?? '').toString().trim();
        final sClass = (sData['className'] ?? sData['classId'] ?? sData['class'] ?? sData['kelas'] ?? '').toString().trim();

        if (sName.isNotEmpty) {
          final cKey = sClass.isNotEmpty ? sClass : 'Siswa';
          final item = {
            'studentId': sDoc.id,
            'displayName': sName,
            'studentName': sName,
            'nis': sNis,
            'className': cKey,
          };
          classRealStudents.putIfAbsent(cKey, () => []).add(item);
          final cleanKey = cKey.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
          if (cleanKey.isNotEmpty && cleanKey != cKey) {
            classRealStudents.putIfAbsent(cleanKey, () => []).add(item);
          }
        }
      }

      classRealStudents.forEach((cName, list) {
        list.sort((a, b) => _naturalCompare((a['studentName'] as String), (b['studentName'] as String)));
      });

      final skipMap = <String, int>{};

      for (var room in roomsList) {
        final rId = (room['id'] ?? room['name'] ?? room['code'] ?? '').toString();
        final rName = (room['name'] ?? room['code'] ?? room['id'] ?? '').toString();
        final assignments = rawRoomAssignments[rId] as List? ?? rawRoomAssignments[rName] as List? ?? [];

        final assignedClasses = <Map<String, dynamic>>[];
        for (var a in assignments) {
          if (a is Map) assignedClasses.add(Map<String, dynamic>.from(a));
        }

        int seatNum = 1;
        for (var cGroup in assignedClasses) {
          final cName = (cGroup['className'] ?? cGroup['classId'] ?? 'Kelas').toString().trim();
          final count = (cGroup['count'] as num?)?.toInt() ?? 0;
          final cleanC = cName.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
          final realList = classRealStudents[cName] ?? classRealStudents[cleanC] ?? [];
          final skipIdx = skipMap[cName] ?? skipMap[cleanC] ?? 0;

          for (int i = 0; i < count; i++) {
            final targetIdx = skipIdx + i;
            if (targetIdx < realList.length) {
              final r = realList[targetIdx];
              final sId = (r['studentId'] ?? '').toString();
              final sNis = (r['nis'] ?? '').toString();
              final sName = (r['displayName'] ?? r['studentName'] ?? '').toString();

              if ((myStudentId.isNotEmpty && sId == myStudentId) ||
                  (myNis.isNotEmpty && sNis == myNis) ||
                  (myName.isNotEmpty && sName.toLowerCase() == myName.toLowerCase())) {
                return {
                  'roomId': rId,
                  'roomName': rName,
                  'roomCode': (room['code'] ?? rName).toString(),
                  'seatNumber': seatNum,
                  'participantNumber': sNis.isNotEmpty ? sNis : myStudentId,
                  'className': cName,
                  'studentId': myStudentId,
                  'studentName': myName,
                  'nis': myNis,
                };
              }
            }
            seatNum++;
          }
          skipMap[cName] = (skipMap[cName] ?? 0) + count;
          if (cleanC.isNotEmpty && cleanC != cName) {
            skipMap[cleanC] = (skipMap[cleanC] ?? 0) + count;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error synthesizing seat in StudentEventDetailPage: $e');
    }
    return null;
  }

  bool _isSessionExpired(String? dateStr, String? timeStrOrRange) {
    if (timeStrOrRange == null || timeStrOrRange.trim().isEmpty) return false;

    try {
      final now = DateTime.now();

      String endTimeStr = timeStrOrRange.trim();
      if (endTimeStr.contains('-')) {
        final parts = endTimeStr.split('-');
        endTimeStr = parts.last.trim();
        if (endTimeStr.endsWith(')')) {
          endTimeStr = endTimeStr.substring(0, endTimeStr.length - 1).trim();
        }
      }

      final timeParts = endTimeStr.split(':');
      if (timeParts.length < 2) return false;

      final hour = int.tryParse(RegExp(r'\d+').stringMatch(timeParts[0]) ?? '');
      final minute = int.tryParse(RegExp(r'\d+').stringMatch(timeParts[1]) ?? '');

      if (hour == null || minute == null) return false;

      DateTime targetDate = DateTime(now.year, now.month, now.day);
      if (dateStr != null && dateStr.trim().isNotEmpty) {
        final cleanDate = dateStr.trim();
        final parsedDirect = DateTime.tryParse(cleanDate);
        if (parsedDirect != null) {
          targetDate = DateTime(parsedDirect.year, parsedDirect.month, parsedDirect.day);
        } else {
          final yearMatch = RegExp(r'20\d\d').firstMatch(cleanDate);
          final dayMatch = RegExp(r'\b\d{1,2}\b').firstMatch(cleanDate);
          if (yearMatch != null && dayMatch != null) {
            final year = int.parse(yearMatch.group(0)!);
            final day = int.parse(dayMatch.group(0)!);
            int month = now.month;
            final lower = cleanDate.toLowerCase();
            if (lower.contains('jan')) {
              month = 1;
            } else if (lower.contains('feb')) {
              month = 2;
            } else if (lower.contains('mar')) {
              month = 3;
            } else if (lower.contains('apr')) {
              month = 4;
            } else if (lower.contains('mei') || lower.contains('may')) {
              month = 5;
            } else if (lower.contains('jun')) {
              month = 6;
            } else if (lower.contains('jul')) {
              month = 7;
            } else if (lower.contains('agt') || lower.contains('agu') || lower.contains('aug')) {
              month = 8;
            } else if (lower.contains('sep')) {
              month = 9;
            } else if (lower.contains('okt') || lower.contains('oct')) {
              month = 10;
            } else if (lower.contains('nov')) {
              month = 11;
            } else if (lower.contains('des') || lower.contains('dec')) {
              month = 12;
            }

            targetDate = DateTime(year, month, day);
          }
        }
      }

      final sessionEnd = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute, 0);
      // Use server-adjusted time for accurate comparison
      final serverNow = DateTime.now().add(_serverTimeOffset);
      return serverNow.isAfter(sessionEnd);
    } catch (e) {
      debugPrint('⚠️ Error checking session expired: $e');
      return false;
    }
  }

  bool _isSessionNotStartedYet(String? dateStr, String? timeStrOrRange) {
    if (timeStrOrRange == null || timeStrOrRange.trim().isEmpty) return false;

    try {
      final now = DateTime.now();

      String startTimeStr = timeStrOrRange.trim();
      if (startTimeStr.contains('-')) {
        final parts = startTimeStr.split('-');
        startTimeStr = parts.first.trim();
      }

      final timeParts = startTimeStr.split(':');
      if (timeParts.length < 2) return false;

      final hour = int.tryParse(RegExp(r'\d+').stringMatch(timeParts[0]) ?? '');
      final minute = int.tryParse(RegExp(r'\d+').stringMatch(timeParts[1]) ?? '');

      if (hour == null || minute == null) return false;

      DateTime targetDate = DateTime(now.year, now.month, now.day);
      if (dateStr != null && dateStr.trim().isNotEmpty) {
        final cleanDate = dateStr.trim();
        final parsedDirect = DateTime.tryParse(cleanDate);
        if (parsedDirect != null) {
          targetDate = DateTime(parsedDirect.year, parsedDirect.month, parsedDirect.day);
        } else {
          final yearMatch = RegExp(r'20\d\d').firstMatch(cleanDate);
          final dayMatch = RegExp(r'\b\d{1,2}\b').firstMatch(cleanDate);
          if (yearMatch != null && dayMatch != null) {
            final year = int.parse(yearMatch.group(0)!);
            final day = int.parse(dayMatch.group(0)!);
            int month = now.month;
            final lower = cleanDate.toLowerCase();
            if (lower.contains('jan')) {
              month = 1;
            } else if (lower.contains('feb')) {
              month = 2;
            } else if (lower.contains('mar')) {
              month = 3;
            } else if (lower.contains('apr')) {
              month = 4;
            } else if (lower.contains('mei') || lower.contains('may')) {
              month = 5;
            } else if (lower.contains('jun')) {
              month = 6;
            } else if (lower.contains('jul')) {
              month = 7;
            } else if (lower.contains('agt') || lower.contains('agu') || lower.contains('aug')) {
              month = 8;
            } else if (lower.contains('sep')) {
              month = 9;
            } else if (lower.contains('okt') || lower.contains('oct')) {
              month = 10;
            } else if (lower.contains('nov')) {
              month = 11;
            } else if (lower.contains('des') || lower.contains('dec')) {
              month = 12;
            }

            targetDate = DateTime(year, month, day);
          }
        }
      }

      final sessionStart = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute, 0);
      // Use server-adjusted time for accurate comparison
      final serverNow = DateTime.now().add(_serverTimeOffset);
      return serverNow.isBefore(sessionStart);
    } catch (e) {
      debugPrint('⚠️ Error checking session not started: $e');
      return false;
    }
  }

  void _showExpiredSessionDialog(String subjectName, String sName, String timeLabel) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.history_toggle_off_rounded, color: Color(0xFF64748B), size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Sesi Ujian Telah Berakhir',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Waktu pengerjaan untuk mata pelajaran $subjectName ($sName: $timeLabel) telah melewati batas jam pelaksanaan.',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Murid tidak dapat lagi menekan tombol Kerjakan atau memulai pengerjaan soal pada sesi ini.',
                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Saya Mengerti', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLockedAttendanceDialog(Map<String, dynamic> item) {
    final subjectName = (item['subjectName'] ?? item['subject'] ?? 'Mata Pelajaran').toString();
    final sId = item['sessionId']?.toString() ?? '';
    final session = _sessionMap[sId];
    final sName = session?['name'] ?? session?['sessionName'] ?? 'Sesi Ujian';
    final roomName = (_allocatedSeat?['roomCode'] ?? _allocatedSeat?['roomName'] ?? _allocatedSeat?['roomId'] ?? 'Ruangan Ujian').toString();
    final seatNum = (_allocatedSeat?['seatNumber'] ?? '-').toString();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_person_rounded, color: Color(0xFFD97706), size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Akses Ujian Terkunci',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Anda belum dikonfirmasi hadir oleh Pengawas Ruangan untuk mata pelajaran $subjectName.',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Silakan tunjukkan QR Kartu Ujian Anda kepada Pengawas di ruangan tempat Anda ujian untuk meng-scan presensi dan membuka akses ujian ini.',
                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ruangan Ujian:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        Text(roomName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sesi Ujian:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        Text(sName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Nomor Kursi:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        Text('No. $seatNum', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF059669))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Saya Mengerti', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayScheduleGroup(String dateKey, List<Map<String, dynamic>> items, int dayIndex) {
    final roomName = _allocatedSeat?['roomName'] ?? _allocatedSeat?['roomId'] ?? 'Belum Alokasi';
    final seatNumber = _allocatedSeat?['seatNumber']?.toString() ?? '-';
    final participantNumber = _allocatedSeat?['participantNumber']?.toString() ?? _student?.nis ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Tanggal Ujian
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('schools')
                .doc(_schoolId)
                .collection('events')
                .doc(widget.eventId)
                .collection('attendances')
                .where('studentId', isEqualTo: _student?.id ?? '')
                .snapshots(),
            builder: (context, attSnap) {
              final attDocs = attSnap.data?.docs ?? [];

              return ListView.separated(
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
                  final startTime = (session?['startTime'] ?? '').toString();
                  final endTime = (session?['endTime'] ?? '').toString();
                  final timeLabel = startTime.isNotEmpty ? '$startTime - $endTime' : 'Waktu belum diatur';

                  final bool isQuestionReady = item['isQuestionReady'] == true;
                  final bool isSubmitted = item['isSubmitted'] == true;
                  final num? submittedScore = item['submittedScore'];
                  final bool isExpired = _isSessionExpired(dateKey, timeLabel);
                  final bool isNotStarted = _isSessionNotStartedYet(dateKey, timeLabel);

                  // Proctor Attendance Realtime Verification Check
                  bool isAttendedByProctor = false;

                  int resolvedDayIndex = dayIndex;
                  final rawDayIdx = (item['dayIndex'] ?? item['day'] as num?)?.toInt();
                  if (rawDayIdx != null) {
                    resolvedDayIndex = rawDayIdx;
                  }

                  int resolvedSessionIndex = 0;
                  final rawSessionIdx = (item['sessionIndex'] ?? item['session'] ?? session?['sessionIndex'] ?? session?['session'] as num?)?.toInt();
                  if (rawSessionIdx != null) {
                    resolvedSessionIndex = rawSessionIdx;
                  } else if (session != null) {
                    final tempId = (session['tempId'] ?? session['id'] ?? '').toString();
                    if (tempId.contains('_session_')) {
                      final parts = tempId.split('_session_');
                      if (parts.length >= 2) {
                        final idx = int.tryParse(parts[1]);
                        if (idx != null) resolvedSessionIndex = idx;
                      }
                    } else {
                      final match = RegExp(r'Sesi\s*(\d+)', caseSensitive: false).firstMatch(sName);
                      if (match != null) {
                        resolvedSessionIndex = (int.tryParse(match.group(1)!) ?? 1) - 1;
                      } else {
                        resolvedSessionIndex = index;
                      }
                    }
                  } else {
                    resolvedSessionIndex = index;
                  }

                  final String currentStudentId = _student?.id ?? '';
                  final String currentStudentNis = _student?.nis ?? '';

                  for (var doc in attDocs) {
                    if (isAttendedByProctor) break;
                    final aData = doc.data() as Map<String, dynamic>? ?? {};
                    final sIdVal = (aData['studentId'] ?? '').toString();
                    final sNis = (aData['nis'] ?? '').toString();
                    final isAtt = aData['isAttended'] == true;
                    if (!isAtt) continue;

                    final bool isStudentMatch =
                        (currentStudentId.isNotEmpty && sIdVal.isNotEmpty && sIdVal == currentStudentId) ||
                        (currentStudentNis.isNotEmpty && sNis.isNotEmpty && sNis == currentStudentNis);

                    if (!isStudentMatch) continue;

                    final aDay = (aData['dayIndex'] as num?)?.toInt();
                    final aSess = (aData['sessionIndex'] as num?)?.toInt();

                    // Match strictly by BOTH dayIndex AND sessionIndex
                    if (aDay != null && aSess != null) {
                      if (aDay == resolvedDayIndex && aSess == resolvedSessionIndex) {
                        isAttendedByProctor = true;
                        break;
                      }
                    }
                  }

                  final Map<String, dynamic> itemQrDataMap = {
                    'studentId': _student?.id ?? '',
                    'roomName': roomName,
                    'dayIndex': resolvedDayIndex,
                    'sessionIndex': resolvedSessionIndex,
                  };
                  final String itemQrDataString = jsonEncode(itemQrDataMap);

                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Tooltip(
                          message: 'Klik untuk memperbesar QR Code Sesi',
                          child: GestureDetector(
                            onTap: () {
                              _showEnlargedQrDialog(
                                context: context,
                                qrData: itemQrDataString,
                                participantNumber: participantNumber,
                                roomName: roomName,
                                seatNumber: seatNumber,
                                subjectName: subjectName.toString(),
                                sessionName: sName,
                                dayIndex: resolvedDayIndex,
                                sessionIndex: resolvedSessionIndex,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: itemQrDataString,
                                version: QrVersions.auto,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                                size: 36.0,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
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
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isAttendedByProctor
                                      ? const Color(0xFFD1FAE5)
                                      : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isAttendedByProctor
                                          ? Icons.check_circle_rounded
                                          : Icons.cancel_rounded,
                                      size: 11,
                                      color: isAttendedByProctor
                                          ? const Color(0xFF065F46)
                                          : const Color(0xFFD97706),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isAttendedByProctor ? 'Sudah Scan' : 'Belum Scan',
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: isAttendedByProctor
                                            ? const Color(0xFF065F46)
                                            : const Color(0xFFD97706),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Action Button or Status Badge
                        if (isSubmitted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF059669)),
                                const SizedBox(width: 6),
                                Text(
                                  submittedScore != null ? 'Selesai ($submittedScore)' : 'Sudah Dikumpulkan',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF475569)),
                                ),
                              ],
                            ),
                          )
                        else if (isExpired)
                          OutlinedButton.icon(
                            onPressed: () => _showExpiredSessionDialog(subjectName.toString(), sName, timeLabel),
                            icon: const Icon(Icons.history_toggle_off_rounded, size: 14, color: Color(0xFF64748B)),
                            label: Text(
                              'Waktu Sesi Berakhir',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF64748B)),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFF1F5F9),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          )
                        else if (isNotStarted)
                          OutlinedButton.icon(
                            onPressed: () => _showSessionGuidelinesDialog(
                              item: item,
                              subjectName: subjectName.toString(),
                              sName: sName,
                              timeLabel: timeLabel,
                            ),
                            icon: const Icon(Icons.menu_book_rounded, size: 14, color: Color(0xFF2563EB)),
                            label: SizedBox(
                              width: 130,
                              child: Text(
                                'Sesi belum mulai. Klik untuk membaca panduan',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF2563EB),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFEFF6FF),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              side: const BorderSide(color: Color(0xFF93C5FD)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          )
                        else if (!isAttendedByProctor)
                          ElevatedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.play_circle_fill_rounded, size: 16, color: Color(0xFF94A3B8)),
                            label: const Text('Kerjakan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE2E8F0),
                              foregroundColor: const Color(0xFF94A3B8),
                              disabledBackgroundColor: const Color(0xFFE2E8F0),
                              disabledForegroundColor: const Color(0xFF94A3B8),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          )
                        else if (isQuestionReady)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _showSessionGuidelinesDialog(
                                  item: item,
                                  subjectName: subjectName.toString(),
                                  sName: sName,
                                  timeLabel: timeLabel,
                                ),
                                icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF2563EB), size: 20),
                                tooltip: 'Panduan Ujian',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: () {
                                  final sid = (item['subjectId'] ?? subjectName).toString();
                                  debugPrint('🚀 Navigating to StudentExamPage');
                                  debugPrint('   subjectId  : "$sid"');
                                  debugPrint('   subjectName: "$subjectName"');
                                  debugPrint('   angkatan   : "${_student?.angkatan}"');
                                  debugPrint('   className  : "$_myClassName"');
                                  debugPrint('   item keys  : ${item.keys.toList()}');
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => StudentExamPage(
                                        schoolId: _schoolId,
                                        eventId: widget.eventId,
                                        eventName: widget.eventName,
                                        subjectId: sid,
                                        subjectName: subjectName.toString(),
                                        studentId: _student?.id ?? '',
                                        studentName: _student?.displayName ?? 'Siswa',
                                        nis: _student?.nis ?? '',
                                        className: _myClassName ?? '',
                                        angkatan: (_student?.angkatan != null && _student!.angkatan.trim().isNotEmpty) ? _student!.angkatan : (_myClassName ?? ''),
                                        sessionName: sName,
                                        startTimeStr: startTime,
                                        endTimeStr: endTime,
                                      ),
                                    ),
                                  ).then((_) => _loadStudentAndEventDetails());
                                },
                                icon: const Icon(Icons.play_circle_fill_rounded, size: 16),
                                label: const Text('Kerjakan'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Soal Belum Siap',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  );
                },
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
