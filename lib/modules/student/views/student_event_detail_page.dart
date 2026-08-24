import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/student.dart';
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
      final db = FirebaseFirestore.instance;
      final schoolRef = db.collection('schools').doc(_schoolId);
      final eventRef = schoolRef.collection('events').doc(widget.eventId);

      // PARALLEL BATCH 1: Fetch Student profile, Classes, Event doc, Sessions, Timetable, Allocations concurrently
      final results = await Future.wait([
        schoolRef.collection('students').where('uid', isEqualTo: uid).limit(1).get(),
        schoolRef.collection('classes').get(),
        eventRef.get(),
        eventRef.collection('sessions').get(),
        eventRef.collection('timetable').get(),
        eventRef.collection('allocations').limit(1).get(),
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
        if (eventDoc.exists) {
          final eData = eventDoc.data() as Map<String, dynamic>?;
          if (eData != null) {
            final sd = eData['startDate'];
            final ed = eData['endDate'];
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

        // Task A: Seat lookup
        if (allocSnap.docs.isNotEmpty) {
          final activeAllocId = allocSnap.docs.first.id;
          final allocRef = eventRef.collection('allocations').doc(activeAllocId);
          parallelTasks.add(
            allocRef.collection('seats').get().then((seatSnap) {
              for (var sDoc in seatSnap.docs) {
                final sData = sDoc.data();
                if (sData['studentId'] == doc.id ||
                    (sData['nis'] != null && sData['nis'] == _student!.nis) ||
                    (sData['studentName'] != null && sData['studentName'] == _student!.displayName) ||
                    (sData['displayName'] != null && sData['displayName'] == _student!.displayName)) {
                  _allocatedSeat = sData;
                  break;
                }
              }
            }).catchError((_) {}),
          );
        }

        // Task B: Question readiness check for all subjects in parallel
        for (var item in filteredTimetable) {
          final subId = (item['subjectId'] ?? item['subjectName'] ?? '').toString();
          final subName = (item['subjectName'] ?? '').toString();

          if (subId.isNotEmpty) {
            parallelTasks.add(
              eventRef.collection('subjects').doc(subId).collection('questions').get().then((qSnap) {
                int qCount = qSnap.docs.length;
                item['isQuestionReady'] = qCount > 0;
                item['questionCount'] = qCount;
              }).catchError((_) {
                if (subName.isNotEmpty && subName != subId) {
                  return eventRef.collection('subjects').doc(subName).collection('questions').get().then((qSnap2) {
                    int qCount = qSnap2.docs.length;
                    item['isQuestionReady'] = qCount > 0;
                    item['questionCount'] = qCount;
                  }).catchError((_) {
                    item['isQuestionReady'] = false;
                    item['questionCount'] = 0;
                  });
                } else {
                  item['isQuestionReady'] = false;
                  item['questionCount'] = 0;
                }
              }),
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

    // JSON Payload encoded inside QR Code with full student and exam event data
    final Map<String, dynamic> qrDataMap = {
      'studentId': _student?.id ?? '',
      'studentName': _student?.displayName ?? 'Siswa SesiCermat',
      'nis': _student?.nis ?? '',
      'className': _myClassName ?? '',
      'schoolId': _schoolId,
      'eventId': widget.eventId,
      'eventName': widget.eventName,
      'eventDateRange': _eventDateRange,
      'participantNumber': participantNumber,
      'roomName': roomName,
      'seatNumber': seatNumber,
    };
    final String qrDataString = jsonEncode(qrDataMap);

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card dengan QR (Dapat diklik memperbesar), Nama Event, Tanggal Event, No Peserta, Ruangan, No Kursi
            _buildParticipantCard(
              roomName: roomName,
              seatNumber: seatNumber,
              participantNumber: participantNumber,
              dateRange: _eventDateRange,
              qrDataString: qrDataString,
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

                return _buildDayScheduleGroup(dateStr, dayItems);
              }),
          ],
        ),
      ),
    );
  }

  /// Card Peserta Ujian berisi: QR Code (Click to enlarge), Nama Event Ujian, Tanggal Event, No Peserta, Ruangan, No Kursi
  Widget _buildParticipantCard({
    required String roomName,
    required String seatNumber,
    required String participantNumber,
    required String dateRange,
    required String qrDataString,
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
                // Top Header Row: Event Name, Date Range, & Interactive QR Code Box
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
                    const SizedBox(width: 12),
                    // Clickable Interactive QR Code Box
                    Tooltip(
                      message: 'Klik untuk memperbesar QR Code',
                      child: InkWell(
                        onTap: () => _showEnlargedQrDialog(
                          context: context,
                          qrData: qrDataString,
                          participantNumber: participantNumber,
                          roomName: roomName,
                          seatNumber: seatNumber,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QrImageView(
                                data: qrDataString,
                                version: QrVersions.auto,
                                size: 56.0,
                                padding: EdgeInsets.zero,
                                backgroundColor: Colors.white,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.zoom_in_rounded, size: 10, color: Color(0xFF0F172A)),
                                  const SizedBox(width: 2),
                                  Text(
                                    'PERBESAR',
                                    style: GoogleFonts.inter(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF0F172A),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

  /// Dialog untuk memperbesar QR Code peserta
  void _showEnlargedQrDialog({
    required BuildContext context,
    required String qrData,
    required String participantNumber,
    required String roomName,
    required String seatNumber,
  }) {
    showDialog(
      context: context,
      builder: (context) {
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
                            'QR Kartu Ujian',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
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
                      size: 220.0,
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
              final startTime = (session?['startTime'] ?? '').toString();
              final endTime = (session?['endTime'] ?? '').toString();
              final timeLabel = startTime.isNotEmpty ? '$startTime - $endTime' : 'Waktu belum diatur';

              final bool isQuestionReady = item['isQuestionReady'] == true;
              final bool isSubmitted = item['isSubmitted'] == true;
              final num? submittedScore = item['submittedScore'];

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSubmitted
                            ? const Color(0xFFD1FAE5)
                            : (isQuestionReady ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isSubmitted
                            ? Icons.check_circle_rounded
                            : (isQuestionReady ? Icons.edit_note_rounded : Icons.lock_clock_rounded),
                        color: isSubmitted
                            ? const Color(0xFF047857)
                            : (isQuestionReady ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                        size: 22,
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
                    else if (isQuestionReady)
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
                                angkatan: _student?.angkatan ?? '',
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
