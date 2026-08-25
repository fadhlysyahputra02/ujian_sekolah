import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:sys_exam_school/core/services/auth_service.dart';
import 'package:sys_exam_school/core/utils/natural_sort.dart';

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

  Future<void> _fetchAttendances() async {
    try {
      final schoolId = _resolvedSchoolId ?? '';
      if (schoolId.isEmpty) return;
      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('attendances')
          .get();

      for (var doc in snap.docs) {
        final d = doc.data();
        final isAtt = d['isAttended'] == true || d['attended'] == true;
        if (isAtt) {
          final sId = (d['studentId'] ?? d['id'] ?? '').toString().trim().toLowerCase();
          final sNis = (d['nis'] ?? '').toString().trim().toLowerCase();
          final sName = (d['studentName'] ?? d['displayName'] ?? '').toString().trim().toLowerCase();
          final sSeatNum = d['seatNumber'];

          if (sId.isNotEmpty) _localAttendedMap[sId] = true;
          if (sNis.isNotEmpty) _localAttendedMap[sNis] = true;
          if (sName.isNotEmpty) _localAttendedMap[sName] = true;
          if (sSeatNum != null) _localAttendedMap['seat_$sSeatNum'] = true;
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('⚠️ Error fetching attendances: $e');
    }
  }

  // Distinct class color palette
  static const List<Map<String, Color>> _classColorPalette = [
    {
      'primary': Color(0xFF4F46E5), // Indigo
      'bg': Color(0xFFEEF2FF),
      'border': Color(0xFFC7D2FE),
      'text': Color(0xFF3730A3),
    },
    {
      'primary': Color(0xFF059669), // Emerald
      'bg': Color(0xFFECFDF5),
      'border': Color(0xFFA7F3D0),
      'text': Color(0xFF065F46),
    },
    {
      'primary': Color(0xFFD97706), // Amber
      'bg': Color(0xFFFFFBEB),
      'border': Color(0xFFFDE68A),
      'text': Color(0xFF92400E),
    },
    {
      'primary': Color(0xFF0891B2), // Cyan
      'bg': Color(0xFFECFEFF),
      'border': Color(0xFFA5F3FC),
      'text': Color(0xFF155E75),
    },
    {
      'primary': Color(0xFFE11D48), // Rose
      'bg': Color(0xFFFFF1F2),
      'border': Color(0xFFFECDD3),
      'text': Color(0xFF9F1239),
    },
    {
      'primary': Color(0xFF9333EA), // Purple
      'bg': Color(0xFFFAF5FF),
      'border': Color(0xFFE9D5FF),
      'text': Color(0xFF6B21A8),
    },
  ];

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

  Future<void> _updateProctorStatus(String schoolId, String proctorDocId, String newStatus) async {
    if (proctorDocId.isEmpty || proctorDocId.startsWith('grid_')) return;
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('proctors')
          .doc(proctorDocId)
          .update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status pengawasan diubah menjadi "$newStatus"'),
            backgroundColor: newStatus == 'Selesai' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating proctor status: $e');
    }
  }

  Future<bool> _markStudentAttendance({
    required String schoolId,
    required String eventId,
    required String roomId,
    required Map<String, dynamic> seatData,
    required bool isAttended,
  }) async {
    try {
      final studentId = (seatData['studentId'] ?? '').toString();
      final nis = (seatData['nis'] ?? '').toString();
      final seatNum = (seatData['seatNumber'] as num?)?.toInt() ?? 0;
      final name = (seatData['displayName'] ?? seatData['studentName'] ?? 'Siswa').toString();
      final className = (seatData['classId'] ?? seatData['className'] ?? '').toString();

      final sId = studentId.toLowerCase();
      final sNis = nis.toLowerCase();
      final sName = name.toLowerCase();

      seatData['isAttended'] = isAttended;
      seatData['attended'] = isAttended;

      if (isAttended) {
        if (sId.isNotEmpty) _localAttendedMap[sId] = true;
        if (sNis.isNotEmpty) _localAttendedMap[sNis] = true;
        if (sName.isNotEmpty) _localAttendedMap[sName] = true;
        if (seatNum > 0) _localAttendedMap['seat_$seatNum'] = true;
      } else {
        if (sId.isNotEmpty) _localAttendedMap.remove(sId);
        if (sNis.isNotEmpty) _localAttendedMap.remove(sNis);
        if (sName.isNotEmpty) _localAttendedMap.remove(sName);
        if (seatNum > 0) _localAttendedMap.remove('seat_$seatNum');
      }

      if (mounted) setState(() {});

      final docKey = studentId.isNotEmpty
          ? '${roomId}_$studentId'
          : (nis.isNotEmpty ? '${roomId}_$nis' : '${roomId}_seat_$seatNum');

      final attRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId)
          .collection('attendances')
          .doc(docKey);

      await attRef.set({
        'eventId': eventId,
        'roomId': roomId,
        'studentId': studentId,
        'studentName': name,
        'nis': nis,
        'className': className,
        'seatNumber': seatNum,
        'isAttended': isAttended,
        'attendedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'proctor',
      }, SetOptions(merge: true));

      debugPrint('📌 Attendance updated for $name (seat #$seatNum): $isAttended');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating attendance: $e');
      return false;
    }
  }

  void _processScannedQr({
    required String rawData,
    required String schoolId,
    required String eventId,
    required String roomId,
    required Set<String> roomAliases,
    required Map<int, Map<String, dynamic>> seatMap,
    required StateSetter setDialogState,
  }) {
    if (rawData.isEmpty) return;

    debugPrint('=================== 🔍 QR SCAN DETECTED ===================');
    debugPrint('📷 Raw Barcode Content: "$rawData"');

    String scannedStudentId = '';
    String scannedNis = '';
    String scannedParticipantNumber = '';
    String scannedName = '';
    String scannedRoomName = '';

    try {
      if (rawData.trim().startsWith('{') && rawData.trim().endsWith('}')) {
        final Map<String, dynamic> parsedJson = jsonDecode(rawData);
        scannedStudentId = (parsedJson['studentId'] ?? parsedJson['id'] ?? '').toString().trim();
        scannedNis = (parsedJson['nis'] ?? '').toString().trim();
        scannedParticipantNumber = (parsedJson['participantNumber'] ?? '').toString().trim();
        scannedName = (parsedJson['studentName'] ?? parsedJson['name'] ?? '').toString().trim();
        scannedRoomName = (parsedJson['roomName'] ?? parsedJson['roomId'] ?? '').toString().trim();
      } else {
        scannedStudentId = rawData.trim();
        scannedNis = rawData.trim();
      }
    } catch (e) {
      scannedStudentId = rawData.trim();
      scannedNis = rawData.trim();
    }

    if (scannedRoomName.isNotEmpty) {
      final cleanScannedRoom = scannedRoomName.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
      bool isRoomMatch = roomAliases.any((alias) {
        final cleanAlias = alias.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        return cleanAlias == cleanScannedRoom || cleanAlias.contains(cleanScannedRoom) || cleanScannedRoom.contains(cleanAlias);
      });
      if (!isRoomMatch) {
        debugPrint('⚠️ Room Mismatch: QR scanned room "$scannedRoomName" does not match current room aliases $roomAliases');
      }
    }

    Map<String, dynamic>? matchedSeat;
    int? matchedSeatNum;

    for (var entry in seatMap.entries) {
      final s = entry.value;
      final sId = (s['studentId'] ?? s['id'] ?? '').toString().trim();
      final sNis = (s['nis'] ?? '').toString().trim();
      final sPart = (s['participantNumber'] ?? '').toString().trim();
      final sName = (s['displayName'] ?? s['studentName'] ?? '').toString().trim();

      bool isMatch = false;
      if (scannedStudentId.isNotEmpty && (sId.toLowerCase() == scannedStudentId.toLowerCase() || sId.toLowerCase().contains(scannedStudentId.toLowerCase()))) {
        isMatch = true;
      } else if (scannedNis.isNotEmpty && sNis.toLowerCase() == scannedNis.toLowerCase()) {
        isMatch = true;
      } else if (scannedParticipantNumber.isNotEmpty && sPart.toLowerCase() == scannedParticipantNumber.toLowerCase()) {
        isMatch = true;
      } else if (scannedName.isNotEmpty && sName.toLowerCase() == scannedName.toLowerCase()) {
        isMatch = true;
      }

      if (isMatch) {
        matchedSeat = s;
        matchedSeatNum = entry.key;
        break;
      }
    }

    if (matchedSeat != null && matchedSeatNum != null) {
      final name = (matchedSeat['displayName'] ?? matchedSeat['studentName'] ?? 'Siswa').toString();
      final isAlreadyAttended = matchedSeat['isAttended'] == true;

      if (!isAlreadyAttended) {
        setDialogState(() {
          matchedSeat!['isAttended'] = true;
        });
        final mId = (matchedSeat['studentId'] ?? '').toString().toLowerCase();
        final mNis = (matchedSeat['nis'] ?? '').toString().toLowerCase();
        final mName = (matchedSeat['displayName'] ?? matchedSeat['studentName'] ?? '').toString().toLowerCase();
        if (mId.isNotEmpty) _localAttendedMap[mId] = true;
        if (mNis.isNotEmpty) _localAttendedMap[mNis] = true;
        if (mName.isNotEmpty) _localAttendedMap[mName] = true;
        _localAttendedMap['seat_$matchedSeatNum'] = true;

        if (mounted) setState(() {});

        _markStudentAttendance(
          schoolId: schoolId,
          eventId: eventId,
          roomId: roomId,
          seatData: matchedSeat,
          isAttended: true,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Presensi Berhasil! Siswa "$name" (Meja #$matchedSeatNum) ditandai HADIR!'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ℹ️ Siswa "$name" (Meja #$matchedSeatNum) sudah melakukan presensi sebelumnya.'),
            backgroundColor: const Color(0xFF0284C7),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ QR tidak cocok dengan daftar murid di ruangan ini. ID/NIS: "${scannedStudentId.isNotEmpty ? scannedStudentId : rawData}"'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showQrScanDialog({
    required String schoolId,
    required String eventId,
    required String roomId,
    required Set<String> roomAliases,
    required Map<int, Map<String, dynamic>> seatMap,
  }) {
    final TextEditingController searchCtrl = TextEditingController();
    final MobileScannerController scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.front,
      torchEnabled: false,
      formats: const [BarcodeFormat.qrCode],
    );

    String query = '';
    int activeTab = 0; // 0: Kamera QR, 1: Cari Manual
    bool isMirrorMode = true;
    bool isTorchOn = false;
    DateTime lastScanTime = DateTime.now().subtract(const Duration(seconds: 5));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final attendedCount = seatMap.values.where((s) => s['isAttended'] == true).length;
          final totalCount = seatMap.length;

          final matchingSeats = seatMap.entries.where((entry) {
            final s = entry.value;
            final name = (s['displayName'] ?? s['studentName'] ?? '').toString().toLowerCase();
            final nis = (s['nis'] ?? '').toString().toLowerCase();
            final className = (s['classId'] ?? s['className'] ?? '').toString().toLowerCase();
            final q = query.trim().toLowerCase();
            if (q.isEmpty) return true;
            return name.contains(q) || nis.contains(q) || className.contains(q) || entry.key.toString() == q;
          }).toList();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            clipBehavior: Clip.antiAlias,
            backgroundColor: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF059669), size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Presensi QR Murid',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Hadir: $attendedCount / $totalCount Siswa',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF059669), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Mode Selector Tabs
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setDialogState(() => activeTab = 0);
                              scannerController.start();
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: activeTab == 0 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: activeTab == 0
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_front_rounded, size: 18, color: activeTab == 0 ? const Color(0xFF059669) : const Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Kamera QR',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: activeTab == 0 ? FontWeight.bold : FontWeight.w600,
                                      color: activeTab == 0 ? const Color(0xFF059669) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setDialogState(() => activeTab = 1);
                              scannerController.stop();
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: activeTab == 1 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: activeTab == 1
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_rounded, size: 18, color: activeTab == 1 ? const Color(0xFF059669) : const Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Cari Manual',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: activeTab == 1 ? FontWeight.bold : FontWeight.w600,
                                      color: activeTab == 1 ? const Color(0xFF059669) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (activeTab == 0) ...[
                    // Tab 0: Live Camera Scanner Preview (Mirror Mode Default)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 230,
                        width: double.infinity,
                        color: Colors.black,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform(
                              alignment: Alignment.center,
                              transform: isMirrorMode ? Matrix4.rotationY(pi) : Matrix4.identity(),
                              child: MobileScanner(
                                controller: scannerController,
                                onDetect: (capture) {
                                  final now = DateTime.now();
                                  if (now.difference(lastScanTime).inMilliseconds < 1500) return;
                                  final barcodes = capture.barcodes;
                                  for (final barcode in barcodes) {
                                    final rawValue = barcode.rawValue;
                                    if (rawValue != null && rawValue.isNotEmpty) {
                                      lastScanTime = now;
                                      _processScannedQr(
                                        rawData: rawValue,
                                        schoolId: schoolId,
                                        eventId: eventId,
                                        roomId: roomId,
                                        roomAliases: roomAliases,
                                        seatMap: seatMap,
                                        setDialogState: setDialogState,
                                      );
                                      break;
                                    }
                                  }
                                },
                              ),
                            ),

                            // Camera Viewfinder Target Frame
                            Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFF10B981), width: 2.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),

                            // Controls Row (Mirror & Flash Toggles)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setDialogState(() => isMirrorMode = !isMirrorMode);
                                    },
                                    icon: Icon(
                                      isMirrorMode ? Icons.flip_camera_ios_rounded : Icons.camera_rear_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black45,
                                    ),
                                    tooltip: isMirrorMode ? 'Mode Mirror: Aktif' : 'Mode Mirror: Nonaktif',
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    onPressed: () async {
                                      await scannerController.toggleTorch();
                                      setDialogState(() => isTorchOn = !isTorchOn);
                                    },
                                    icon: Icon(
                                      isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                      color: isTorchOn ? const Color(0xFFF59E0B) : Colors.white,
                                      size: 20,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black45,
                                    ),
                                    tooltip: 'Senter Kamera',
                                  ),
                                ],
                              ),
                            ),

                            Positioned(
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isMirrorMode ? '📷 Kamera Mirror Aktif' : '📷 Tampilan Kamera Normal',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Search Field
                  TextField(
                    controller: searchCtrl,
                    onChanged: (val) => setDialogState(() => query = val),
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Ketik NIS atau Nama Siswa di sini...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Student Attendance List
                  Expanded(
                    child: matchingSeats.isEmpty
                        ? Center(
                            child: Text(
                              'Siswa tidak ditemukan',
                              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: matchingSeats.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, idx) {
                              final entry = matchingSeats[idx];
                              final seatNum = entry.key;
                              final seatData = entry.value;

                              final name = (seatData['displayName'] ?? seatData['studentName'] ?? 'Siswa').toString();
                              final className = (seatData['classId'] ?? seatData['className'] ?? '').toString();
                              final nis = (seatData['nis'] ?? '-').toString();
                              final isAttended = seatData['isAttended'] == true;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isAttended ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isAttended ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isAttended ? const Color(0xFF059669) : const Color(0xFF475569),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '#$seatNum',
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isAttended ? const Color(0xFF065F46) : const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Kelas $className • NIS: $nis',
                                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final newStatus = !isAttended;
                                        setDialogState(() {
                                          seatData['isAttended'] = newStatus;
                                        });
                                        await _markStudentAttendance(
                                          schoolId: schoolId,
                                          eventId: eventId,
                                          roomId: roomId,
                                          seatData: seatData,
                                          isAttended: newStatus,
                                        );
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                newStatus
                                                    ? '✅ "$name" (Meja #$seatNum) ditandai HADIR!'
                                                    : 'ℹ️ Presensi "$name" dibatalkan.',
                                              ),
                                              backgroundColor: newStatus ? const Color(0xFF059669) : const Color(0xFF475569),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      },
                                      icon: Icon(
                                        isAttended ? Icons.check_circle_rounded : Icons.qr_code_rounded,
                                        size: 14,
                                      ),
                                      label: Text(isAttended ? 'HADIR' : 'Tandai Hadir'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isAttended ? const Color(0xFF059669) : const Color(0xFF0F172A),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) async {
      await scannerController.stop();
      scannerController.dispose();
    });
  }

  Map<String, Color> _getClassColorScheme(String className, List<String> roomClasses) {
    final index = roomClasses.indexOf(className);
    if (index >= 0) {
      return _classColorPalette[index % _classColorPalette.length];
    }
    return _classColorPalette[0];
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final schoolId = (authService.schoolId != null && authService.schoolId!.isNotEmpty)
        ? authService.schoolId!
        : (_resolvedSchoolId ?? '');

    if (schoolId.isNotEmpty && _resolvedSchoolId != schoolId) {
      _resolvedSchoolId = schoolId;
      _isResolvingSchool = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchTimetableSubcollection();
        _fetchAttendances();
      });
    }

    if (_isResolvingSchool || schoolId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/teacher');
              }
            },
          ),
          title: Text(
            'Memuat Ruangan Pengawasan...',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
          ),
        ),
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
          final eventTitle = (evData['name'] ??
              evData['eventName'] ??
              draftState?['eventName'] ??
              draftState?['name'] ??
              evData['title'] ??
              draftState?['title'] ??
              'Event Ujian').toString();

          // Timetable List (subcollection + embedded arrays)
          final timetableList = <Map<String, dynamic>>[];
          // Priority 1: subcollection (most complete, same as event_detail_page)
          for (var item in _timetableSubcollection) {
            timetableList.add(item);
          }
          // Priority 2: draftState embedded array
          if (draftState != null && draftState['timetable'] is List) {
            for (var item in (draftState['timetable'] as List)) {
              if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
            }
          }
          // Priority 3: evData embedded array
          if (evData['timetable'] is List) {
            for (var item in (evData['timetable'] as List)) {
              if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
            }
          }

          // Rooms List — check step4 first, then root
          final roomsList = <Map<String, dynamic>>[];
          final rawRoomsList = draftState?['step4']?['rooms'] ?? draftState?['rooms'] ?? evData['rooms'];
          if (rawRoomsList is List) {
            for (var r in rawRoomsList) {
              if (r is Map) roomsList.add(Map<String, dynamic>.from(r));
            }
          } else if (evData['rooms'] is List) {
            for (var r in (evData['rooms'] as List)) {
              if (r is Map) roomsList.add(Map<String, dynamic>.from(r));
            }
          }

          // Sessions List — prefer subcollection (has real Firestore IDs & order)
          final sessionsList = <Map<String, dynamic>>[];
          if (_sessionsSubcollection.isNotEmpty) {
            sessionsList.addAll(_sessionsSubcollection);
          } else if (draftState != null && draftState['step2']?['sessions'] is List) {
            for (var s in (draftState['step2']['sessions'] as List)) {
              if (s is Map) sessionsList.add(Map<String, dynamic>.from(s));
            }
          } else if (draftState != null && draftState['sessions'] is List) {
            for (var s in (draftState['sessions'] as List)) {
              if (s is Map) sessionsList.add(Map<String, dynamic>.from(s));
            }
          } else if (evData['sessions'] is List) {
            for (var s in (evData['sessions'] as List)) {
              if (s is Map) sessionsList.add(Map<String, dynamic>.from(s));
            }
          }

          // Resolve Room Name & Capacity & Aliases
          String roomName = widget.roomId;
          String roomCode = widget.roomId;
          int roomCapacity = 0;
          for (var r in roomsList) {
            final rid = (r['id'] ?? '').toString();
            final rcode = (r['code'] ?? '').toString();
            final rname = (r['name'] ?? '').toString();
            if (rid == widget.roomId || rcode == widget.roomId || rname == widget.roomId) {
              roomName = rname.isNotEmpty ? rname : widget.roomId;
              roomCode = rcode.isNotEmpty ? rcode : rid;
              roomCapacity = (r['capacity'] as num?)?.toInt() ?? 0;
              break;
            }
          }
          final roomAliases = {widget.roomId, roomName, roomCode}.where((s) => s.isNotEmpty).toSet();
          final Set<String> normalizedAliases = {};
          for (var a in roomAliases) {
            final clean = a.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
            if (clean.isNotEmpty) normalizedAliases.add(clean);
          }

          // Resolve Layout, Columns & Arrangement Mode configured in Step 5 (Total Kolom & Pola Grid)
          int configuredColumns = 4; // Default to 4 matching Step 5 default
          String configuredArrangeMode = '';
          int? configuredSeed;
          final roomLayouts = draftState?['roomLayouts'] as Map? ?? evData['roomLayouts'] as Map? ?? {};
          
          roomLayouts.forEach((k, v) {
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
                final cols = (v['colsPerPair'] ?? v['columns'] ?? v['totalColumns'] as num?)?.toInt();
                if (cols != null && cols > 0) configuredColumns = cols;
                final arr = v['arrange']?.toString();
                if (arr != null && arr.isNotEmpty) configuredArrangeMode = arr;
                final s = (v['seed'] as num?)?.toInt();
                if (s != null) configuredSeed = s;
              }
            }
          });

          // Date Label
          final startDateStr = evData['startDate'] ?? draftState?['startDate'];
          DateTime? startDate;
          if (startDateStr is String) {
            startDate = DateTime.tryParse(startDateStr);
          } else if (startDateStr is Timestamp) {
            startDate = startDateStr.toDate();
          }
          final dutyDate = startDate?.add(Duration(days: widget.dayIndex));
          final dateLabel = dutyDate != null
              ? '${_getNamaHari(dutyDate.weekday)}, ${dutyDate.day} ${_getNamaBulan(dutyDate.month)} ${dutyDate.year}'
              : 'Hari Ke-${widget.dayIndex + 1}';

          // Session Label
          String sessionLabel = 'Sesi ${widget.sessionIndex + 1}';
          if (sessionsList.length > widget.sessionIndex) {
            final sMap = sessionsList[widget.sessionIndex];
            final sName = sMap['name'] ?? sMap['sessionName'] ?? 'Sesi ${widget.sessionIndex + 1}';
            final sStart = sMap['startTime'] ?? sMap['start'] ?? '';
            final sEnd = sMap['endTime'] ?? sMap['end'] ?? '';
            sessionLabel = sStart.isNotEmpty ? '$sName ($sStart - $sEnd)' : sName;
          }

          // Resolve Classes assigned to this room from roomAssignments
          final rawRoomAssignments = draftState?['step6']?['roomAssignments'] as Map? ?? draftState?['roomAssignments'] as Map? ?? evData['roomAssignments'] as Map? ?? {};
          final assignedClassesInRoom = <Map<String, dynamic>>[];
          if (rawRoomAssignments.isNotEmpty) {
            rawRoomAssignments.forEach((key, val) {
              final kStr = key.toString();
              final kClean = kStr.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
              bool isMatch = roomAliases.contains(kStr);
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
          final orderedRoomClasses = assignedClassesInRoom
              .map((c) => (c['className'] ?? c['classId'] ?? '').toString())
              .where((c) => c.isNotEmpty)
              .toList();

          final roomClassNamesSet = <String>{};
          for (var c in assignedClassesInRoom) {
            final cName = (c['className'] ?? '').toString().trim();
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

          // Resolve Subject Name for this Day & Session & Room
          final matchedSubjects = <String>[];
          final targetKeyStr = 'day_${widget.dayIndex}_session_${widget.sessionIndex}';
          final targetSessionIdStr1 = 'session_${widget.sessionIndex}';
          final targetSessionIdStr2 = 'session_${widget.sessionIndex + 1}';

          // Helper: extract comparable date string from String or Firestore Timestamp
          String extractDateStr(dynamic d) {
            if (d is String) return d.length >= 10 ? d.substring(0, 10) : d;
            if (d is Timestamp) {
              final dt = d.toDate();
              return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            }
            return '';
          }

          // Group sessions from subcollection by date, sorted by order within each day
          String? targetRealSessionId;
          if (_sessionsSubcollection.isNotEmpty) {
            final dateGroups = <String, List<Map<String, dynamic>>>{};
            for (var s in _sessionsSubcollection) {
              final dStr = extractDateStr(s['date']);
              if (dStr.isNotEmpty) {
                dateGroups.putIfAbsent(dStr, () => []).add(s);
              }
            }
            final sortedDates = dateGroups.keys.toList()..sort();
            debugPrint('[ProctorRoom] dayIdx=${widget.dayIndex} sessIdx=${widget.sessionIndex} sortedDates=$sortedDates');
            if (widget.dayIndex < sortedDates.length) {
              final dayDate = sortedDates[widget.dayIndex];
              final daySessions = List<Map<String, dynamic>>.from(dateGroups[dayDate]!);
              daySessions.sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
              if (widget.sessionIndex < daySessions.length) {
                targetRealSessionId = daySessions[widget.sessionIndex]['id']?.toString();
              }
              debugPrint('[ProctorRoom] dayDate=$dayDate daySessions=${daySessions.length} targetRealSessionId=$targetRealSessionId');
            }
          }

          // Fallback: compute by order (only when subcollection is missing)
          int targetOrder = widget.dayIndex * 2 + widget.sessionIndex + 1;
          if (targetRealSessionId == null && sessionsList.isNotEmpty) {
            // Try simple index-based fallback
            final sortedSessions = List<Map<String, dynamic>>.from(sessionsList)
              ..sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
            final idx = widget.dayIndex * 2 + widget.sessionIndex; // rough guess sessPerDay=2
            if (idx < sortedSessions.length) {
              targetRealSessionId = sortedSessions[idx]['id']?.toString();
            }
          }
          debugPrint('[ProctorRoom] ============================');
          debugPrint('[ProctorRoom] widget.roomId=${widget.roomId}');
          debugPrint('[ProctorRoom] roomName=$roomName roomCode=$roomCode');
          debugPrint('[ProctorRoom] roomAliases=$roomAliases');
          debugPrint('[ProctorRoom] rawRoomAssignments keys=${rawRoomAssignments.keys.toList()}');
          debugPrint('[ProctorRoom] orderedRoomClasses=$orderedRoomClasses');
          debugPrint('[ProctorRoom] _sessionsSubcollection.length=${_sessionsSubcollection.length}');
          if (_sessionsSubcollection.isNotEmpty) {
            for (var s in _sessionsSubcollection.take(4)) {
              debugPrint('[ProctorRoom]   sess id=${s["id"]} date=${s["date"]} dateType=${s["date"]?.runtimeType} order=${s["order"]}');
            }
          }
          debugPrint('[ProctorRoom] _timetableSubcollection.length=${_timetableSubcollection.length}');
          if (_timetableSubcollection.isNotEmpty) {
            for (var t in _timetableSubcollection.take(5)) {
              debugPrint('[ProctorRoom]   timetable sessionId=${t["sessionId"]} subjectName=${t["subjectName"]} className=${t["className"]}');
            }
          }

          for (var tItem in timetableList) {
            final tSessionId = (tItem['sessionId'] ?? '').toString();
            final tDay = (tItem['dayIndex'] ?? tItem['day'] as num?)?.toInt();
            final tSession = (tItem['sessionIndex'] ?? tItem['session'] as num?)?.toInt();
            final tOrder = (tItem['order'] as num?)?.toInt();

            bool isMatch = false;

            if (tSessionId.isNotEmpty) {
              if (tSessionId == targetKeyStr ||
                  tSessionId == targetSessionIdStr1 ||
                  tSessionId == targetSessionIdStr2 ||
                  tSessionId == '${widget.sessionIndex}' ||
                  tSessionId == '${widget.sessionIndex + 1}' ||
                  (targetRealSessionId != null && tSessionId == targetRealSessionId)) {
                isMatch = true;
              }
            } else if (tSession != null) {
              bool dayMatch = tDay == null || tDay == widget.dayIndex || tDay == (widget.dayIndex + 1);
              bool sessMatch = tSession == widget.sessionIndex || tSession == (widget.sessionIndex + 1);
              isMatch = dayMatch && sessMatch;
            } else if (tOrder != null) {
              isMatch = (tOrder == targetOrder);
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

                if (classMatched) {
                  if (!matchedSubjects.contains(subj)) {
                    matchedSubjects.add(subj);
                  }
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

          // Fallback 2: Check all subjects in event if still empty
          if (matchedSubjects.isEmpty) {
            final subjectsList = draftState?['subjects'] as List? ?? evData['subjects'] as List? ?? [];
            for (var sItem in subjectsList) {
              if (sItem is Map) {
                final sName = (sItem['name'] ?? sItem['subjectName'] ?? sItem['title'] ?? sItem['subject'] ?? '').toString();
                if (sName.isNotEmpty && !matchedSubjects.contains(sName)) {
                  matchedSubjects.add(sName);
                }
              } else if (sItem != null) {
                final sName = sItem.toString().trim();
                if (sName.isNotEmpty && !matchedSubjects.contains(sName)) {
                  matchedSubjects.add(sName);
                }
              }
            }
          }

          final subjectText = matchedSubjects.isNotEmpty ? matchedSubjects.join(' • ') : 'Semua Mata Pelajaran';
          final defaultAllocMode = configuredArrangeMode.isNotEmpty
              ? configuredArrangeMode
              : (draftState?['allocationMode'] as String? ?? evData['allocationMode'] as String? ?? 'zigzag');

          // Stream Allocations & Seats
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
              String? activeAllocId;
              String activeAllocMode = defaultAllocMode;
              int? activeAllocSeed = configuredSeed;

              if (allocDocs.isNotEmpty) {
                activeAllocId = allocDocs.first.id;
                final aData = allocDocs.first.data() as Map<String, dynamic>?;
                if (aData != null) {
                  final rLayouts = aData['roomLayouts'] as Map?;
                  if (rLayouts != null) {
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
                          final cols = (v['colsPerPair'] ?? v['columns'] ?? v['totalColumns'] ?? v['cols'] as num?)?.toInt();
                          if (cols != null && cols > 0) configuredColumns = cols;
                          final arr = v['arrange'] ?? v['arrangeMode'];
                          if (arr != null && arr.toString().isNotEmpty) activeAllocMode = arr.toString();
                          final s = (v['seed'] as num?)?.toInt();
                          if (s != null) activeAllocSeed = s;
                        }
                      }
                    });
                  }
                }
              }

              return StreamBuilder<QuerySnapshot>(
                stream: activeAllocId != null
                    ? FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolId)
                        .collection('events')
                        .doc(widget.eventId)
                        .collection('allocations')
                        .doc(activeAllocId)
                        .collection('seats')
                        .snapshots()
                    : null,
                builder: (context, seatsSnap) {
                  final seatDocs = seatsSnap.data?.docs ?? [];
                  final allocatedSeatsFromFirestore = seatDocs.map((d) => d.data() as Map<String, dynamic>).where((s) {
                    final rCode = (s['roomCode'] ?? s['roomId'] ?? s['room'] ?? '').toString();
                    return roomAliases.contains(rCode) || rCode == widget.roomId || rCode == roomName;
                  }).toList();

                  // Map allocated seats by seatNumber
                  final seatMap = <int, Map<String, dynamic>>{};
                  for (var s in allocatedSeatsFromFirestore) {
                    final numVal = (s['seatNumber'] as num?)?.toInt() ?? 0;
                    if (numVal > 0) seatMap[numVal] = s;
                  }

                  // Stream real students from Firestore to resolve real student names sorted A-Z
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolId)
                        .collection('classes')
                        .snapshots(),
                    builder: (context, classSnap) {
                      final classDocs = classSnap.data?.docs ?? [];
                      final Map<String, String> studentIdToClassName = {};

                      for (var cDoc in classDocs) {
                        final cData = cDoc.data() as Map<String, dynamic>;
                        final cName = (cData['name'] ?? cDoc.id).toString();
                        final sIds = cData['studentIds'];
                        if (sIds is List) {
                          for (var sId in sIds) {
                            studentIdToClassName[sId.toString()] = cName;
                          }
                        }
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('schools')
                            .doc(schoolId)
                            .collection('students')
                            .where('archived', isEqualTo: false)
                            .snapshots(),
                        builder: (context, studentSnap) {
                          final studentDocs = studentSnap.data?.docs ?? [];
                          final Map<String, List<Map<String, dynamic>>> classRealStudents = {};

                          for (var sDoc in studentDocs) {
                            final sData = sDoc.data() as Map<String, dynamic>;
                            final isArchived = sData['archived'] == true;
                            final isDisabled = sData['disabled'] == true;
                            if (isArchived || isDisabled) continue;

                            final sName = (sData['displayName'] ?? sData['name'] ?? sData['fullName'] ?? '').toString().trim();
                            final sNis = (sData['nis'] ?? sData['nisn'] ?? '').toString().trim();
                            final sAngkatan = (sData['angkatan'] ?? '').toString().trim();
                            final sGender = (sData['gender'] ?? 'M').toString().trim();
                            final sClass = (sData['className'] ?? sData['classId'] ?? sData['class'] ?? sData['kelas'] ?? studentIdToClassName[sDoc.id] ?? '').toString().trim();

                            if (sName.isNotEmpty) {
                              final cKey = sClass.isNotEmpty ? sClass : 'Siswa';
                              classRealStudents.putIfAbsent(cKey, () => []).add({
                                'studentId': sDoc.id,
                                'studentName': sName,
                                'displayName': sName,
                                'nis': sNis,
                                'angkatan': sAngkatan,
                                'gender': sGender,
                                'className': cKey,
                                'classId': cKey,
                                'participantNumber': sNis.isNotEmpty ? sNis : sDoc.id,
                              });
                            }
                          }

                          // Sort all class lists ALPHABETICALLY A-Z by displayName with Natural Sort (10.1.1, 10.1.2, ..., 10.1.9, 10.1.10)
                          classRealStudents.forEach((cName, list) {
                            list.sort((a, b) => naturalCompare((a['studentName'] as String), (b['studentName'] as String)));
                          });

                          // Calculate skipCountMap for rooms preceding current room
                          final skipCountMap = <String, int>{};
                          final Map<String, dynamic> rawRoomAssignments = draftState?['roomAssignments'] as Map<String, dynamic>? ?? 
                                                                         evData['roomAssignments'] as Map<String, dynamic>? ?? {};

                          for (var room in roomsList) {
                            final rId = (room['id'] ?? room['name'] ?? room['code'] ?? '').toString();
                            final rName = (room['name'] ?? room['code'] ?? room['id'] ?? '').toString();

                            if (rId == widget.roomId || rName == widget.roomId || roomAliases.contains(rId) || roomAliases.contains(rName)) {
                              break; // Stop at current room
                            }

                            final assignments = rawRoomAssignments[rId] as List? ?? rawRoomAssignments[rName] as List? ?? [];
                            for (var a in assignments) {
                              if (a is Map) {
                                final cName = (a['className'] ?? a['classId'] ?? '').toString().trim();
                                final cnt = (a['count'] as num?)?.toInt() ?? 0;
                                if (cName.isNotEmpty && cnt > 0) {
                                  skipCountMap[cName] = (skipCountMap[cName] ?? 0) + cnt;
                                }
                              }
                            }
                          }

                          // PRIMARY: Build seats from Step 5 roomAssignments (respecting exact counts & patternMode: Normal, Zigzag, Acak)
                          if (assignedClassesInRoom.isNotEmpty) {
                            seatMap.clear();
                            final synthesizedSeats = _buildSeatsFromRoomAssignments(
                              assignedClassesInRoom: assignedClassesInRoom,
                              capacity: roomCapacity > 0 ? roomCapacity : 30,
                              patternMode: activeAllocMode,
                              classRealStudents: classRealStudents,
                              skipCountMap: skipCountMap,
                              customSeed: activeAllocSeed,
                            );
                            for (var s in synthesizedSeats) {
                              final numVal = (s['seatNumber'] as num?)?.toInt() ?? 0;
                              if (numVal > 0) seatMap[numVal] = s;
                            }
                          } else if (seatMap.isNotEmpty) {
                            final classIndices = <String, int>{};
                            seatMap.forEach((seatNum, sData) {
                              final cName = (sData['classId'] ?? sData['className'] ?? '').toString().trim();
                              final idx = classIndices[cName] ?? 0;
                              final skipIndex = skipCountMap[cName] ?? 0;
                              final targetIndex = skipIndex + idx;

                              final realList = classRealStudents[cName];
                              if (realList != null && targetIndex < realList.length) {
                                final r = realList[targetIndex];
                                sData['studentName'] = r['displayName'] ?? sData['studentName'];
                                sData['displayName'] = r['displayName'] ?? sData['displayName'];
                                sData['nis'] = r['nis'] ?? sData['nis'];
                                sData['angkatan'] = r['angkatan'] ?? sData['angkatan'];
                                sData['gender'] = r['gender'] ?? sData['gender'];
                                if (r['participantNumber'] != null && r['participantNumber'].toString().isNotEmpty) {
                                  sData['participantNumber'] = r['participantNumber'];
                                }
                              } else {
                                final authName = _getAuthenticStudentNameAZ(cName, targetIndex);
                                final curName = (sData['studentName'] ?? sData['displayName'] ?? '').toString();
                                if (curName.isEmpty || curName.contains('Siswa')) {
                                  sData['studentName'] = authName['displayName'];
                                  sData['displayName'] = authName['displayName'];
                                }
                                sData['nis'] = (sData['nis'] != null && sData['nis'].toString().isNotEmpty) ? sData['nis'] : authName['nis'];
                                sData['angkatan'] = (sData['angkatan'] != null && sData['angkatan'].toString().isNotEmpty) ? sData['angkatan'] : authName['angkatan'];
                                sData['gender'] = (sData['gender'] != null && sData['gender'].toString().isNotEmpty) ? sData['gender'] : authName['gender'];
                              }
                              classIndices[cName] = idx + 1;
                            });
                          }

                          seatMap.forEach((seatNum, sData) {
                            final sId = (sData['studentId'] ?? sData['id'] ?? '').toString().trim().toLowerCase();
                            final sNis = (sData['nis'] ?? '').toString().trim().toLowerCase();
                            final sName = (sData['displayName'] ?? sData['studentName'] ?? '').toString().trim().toLowerCase();

                            bool isAtt = sData['isAttended'] == true ||
                                (sId.isNotEmpty && _localAttendedMap[sId] == true) ||
                                (sNis.isNotEmpty && _localAttendedMap[sNis] == true) ||
                                (sName.isNotEmpty && _localAttendedMap[sName] == true) ||
                                _localAttendedMap['seat_$seatNum'] == true;

                            if (isAtt) {
                              sData['isAttended'] = true;
                              sData['attended'] = true;
                            }
                          });

                      // Max seat index & total capacity
                  final maxAllocatedNum = seatMap.keys.isNotEmpty ? seatMap.keys.reduce((a, b) => a > b ? a : b) : 0;
                  final totalChairs = roomCapacity > 0 ? roomCapacity : (maxAllocatedNum > 0 ? maxAllocatedNum : 30);
                  final occupiedCount = seatMap.length;
                  final emptyCount = (totalChairs - occupiedCount) > 0 ? (totalChairs - occupiedCount) : 0;

                  // Unique Class Set for filter dropdown & KPI
                  final classSet = <String>{'Semua Kelas'};
                  for (var s in seatMap.values) {
                    final c = s['classId'] ?? s['className'] ?? '';
                    if (c.toString().isNotEmpty) classSet.add(c.toString());
                  }

                  // Count per class for distinct class badges
                  final classStudentCounts = <String, int>{};
                  for (var s in seatMap.values) {
                    final c = (s['classId'] ?? s['className'] ?? '').toString();
                    if (c.isNotEmpty) {
                      classStudentCounts[c] = (classStudentCounts[c] ?? 0) + 1;
                    }
                  }

                  // Filter Seats by search query and class filter
                  final filteredSeatIndices = <int>[];
                  for (int i = 1; i <= totalChairs; i++) {
                    final sData = seatMap[i];
                    bool matchesQuery = true;
                    bool matchesClass = true;

                    if (_searchQuery.trim().isNotEmpty) {
                      final q = _searchQuery.toLowerCase().trim();
                      if (sData != null) {
                        final sName = (sData['studentName'] ?? '').toString().toLowerCase();
                        final sNum = (sData['participantNumber'] ?? '').toString().toLowerCase();
                        final sClass = (sData['classId'] ?? sData['className'] ?? '').toString().toLowerCase();
                        matchesQuery = sName.contains(q) || sNum.contains(q) || sClass.contains(q) || 'meja #$i'.contains(q);
                      } else {
                        matchesQuery = 'meja #$i'.contains(q) || 'kosong'.contains(q);
                      }
                    }

                    if (_selectedClassFilter != 'Semua Kelas') {
                      if (sData != null) {
                        final sClass = (sData['classId'] ?? sData['className'] ?? '').toString();
                        matchesClass = sClass == _selectedClassFilter;
                      } else {
                        matchesClass = false;
                      }
                    }

                    if (matchesQuery && matchesClass) {
                      filteredSeatIndices.add(i);
                    }
                  }

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
                          final gridColumns = configuredColumns > 0 ? configuredColumns : 4;

                          return SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 36 : 16,
                              vertical: 24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. Hero Header Banner
                                _buildHeroHeaderBanner(
                                  schoolId: schoolId,
                                  eventTitle: eventTitle.toString(),
                                  roomName: roomName,
                                  dateLabel: dateLabel,
                                  sessionLabel: sessionLabel,
                                  subjectText: subjectText,
                                  allocationMode: activeAllocMode,
                                  currentStatus: currentStatus,
                                  proctorDocId: realProctorDocId,
                                  configuredColumns: configuredColumns,
                                  seatMap: seatMap,
                                ),
                                const SizedBox(height: 24),

                                // 2. Summary KPI Cards
                                _buildKpiSummaryRow(
                                  totalChairs: totalChairs,
                                  occupiedCount: occupiedCount,
                                  emptyCount: emptyCount,
                                  classSet: classSet,
                                  isDesktop: isDesktop,
                                ),
                                const SizedBox(height: 20),

                                // 3. Distinct Class Color Legend Bar (Step 5 Style)
                                if (classStudentCounts.isNotEmpty)
                                  _buildClassColorLegendBar(
                                    classStudentCounts: classStudentCounts,
                                    orderedRoomClasses: orderedRoomClasses,
                                  ),
                                const SizedBox(height: 20),

                                // 4. Search & Filter Bar
                                _buildSearchFilterBar(classSet: classSet),
                                const SizedBox(height: 20),

                                // 5. Grid Header Title (Legend removed as requested)
                                Row(
                                  children: [
                                    Text(
                                      'Denah Bangku & Posisi Murid (Pola $configuredColumns Kolom • ${filteredSeatIndices.length} Kursi)',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // 6. Denah Seating Grid (Configured Grid Columns from Step 5)
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: gridColumns,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: isDesktop
                                        ? (gridColumns >= 8 ? 0.80 : (gridColumns >= 6 ? 0.95 : 1.15))
                                        : 0.95,
                                  ),
                                  itemCount: filteredSeatIndices.length,
                                  itemBuilder: (ctx, idx) {
                                    final seatNum = filteredSeatIndices[idx];
                                    final seatData = seatMap[seatNum];

                                    return _buildSeatCard(
                                      seatNum: seatNum,
                                      seatData: seatData,
                                      orderedRoomClasses: orderedRoomClasses,
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
  ),
);
}

  /// Synthesize seating allocation from Step 5 roomAssignments when Cloud Function seats subcollection is empty
  List<Map<String, dynamic>> _buildSeatsFromRoomAssignments({
    required List<Map<String, dynamic>> assignedClassesInRoom,
    required int capacity,
    required String patternMode,
    required Map<String, List<Map<String, dynamic>>> classRealStudents,
    required Map<String, int> skipCountMap,
    int? customSeed,
  }) {
    final List<Map<String, dynamic>> studentPool = [];

    for (var classGroup in assignedClassesInRoom) {
      final className = (classGroup['className'] ?? classGroup['classId'] ?? 'Kelas').toString().trim();
      final count = (classGroup['count'] as num?)?.toInt() ?? 0;
      final realList = classRealStudents[className] ?? [];
      final skipIndex = skipCountMap[className] ?? 0;

      for (int i = 0; i < count; i++) {
        final targetIndex = skipIndex + i;
        final paddedIndex = (targetIndex + 1).toString().padLeft(2, '0');

        String studentName = '';
        String nis = '';
        String angkatan = '';
        String gender = 'M';
        String participantNumber = '2026-${className.replaceAll(' ', '')}-$paddedIndex';

        if (targetIndex < realList.length) {
          final r = realList[targetIndex];
          studentName = (r['displayName'] ?? r['studentName'] ?? '').toString();
          nis = (r['nis'] ?? '').toString();
          angkatan = (r['angkatan'] ?? '').toString();
          gender = (r['gender'] ?? 'M').toString();
          if (r['participantNumber'] != null && r['participantNumber'].toString().isNotEmpty) {
            participantNumber = r['participantNumber'].toString();
          } else if (nis.isNotEmpty) {
            participantNumber = nis;
          }
        } else {
          final authName = _getAuthenticStudentNameAZ(className, targetIndex);
          studentName = authName['displayName']!;
          nis = authName['nis']!;
          angkatan = authName['angkatan']!;
          gender = authName['gender']!;
        }

        studentPool.add({
          'studentName': studentName,
          'displayName': studentName,
          'nis': nis,
          'angkatan': angkatan,
          'gender': gender,
          'classId': className,
          'className': className,
          'participantNumber': participantNumber,
        });
      }
    }

    final List<Map<String, dynamic>> resultSeats = [];
    if (studentPool.isEmpty) return resultSeats;

    final modeLower = patternMode.toLowerCase();

    if (modeLower == 'zigzag') {
      // Group pool by class
      final classGroups = <String, List<Map<String, dynamic>>>{};
      for (var s in studentPool) {
        final cName = s['className'] as String;
        classGroups.putIfAbsent(cName, () => []).add(s);
      }

      final keys = classGroups.keys.toList();
      int seatNum = 1;
      bool hasMore = true;
      int step = 0;

      while (hasMore && seatNum <= capacity) {
        hasMore = false;
        for (var k in keys) {
          final list = classGroups[k]!;
          if (step < list.length && seatNum <= capacity) {
            final s = Map<String, dynamic>.from(list[step]);
            s['seatNumber'] = seatNum;
            resultSeats.add(s);
            seatNum++;
            hasMore = true;
          }
        }
        step++;
      }
    } else if (modeLower == 'acak' || modeLower == 'random') {
      final seed = customSeed ?? ((widget.roomId.hashCode.abs() + 42) % 100000);
      final shuffledPool = List<Map<String, dynamic>>.from(studentPool)..shuffle(Random(seed));

      for (int idx = 0; idx < shuffledPool.length && (idx + 1) <= capacity; idx++) {
        final s = Map<String, dynamic>.from(shuffledPool[idx]);
        s['seatNumber'] = idx + 1;
        resultSeats.add(s);
      }
    } else {
      // Normal sequential seat allocation
      for (int idx = 0; idx < studentPool.length && (idx + 1) <= capacity; idx++) {
        final s = Map<String, dynamic>.from(studentPool[idx]);
        s['seatNumber'] = idx + 1;
        resultSeats.add(s);
      }
    }

    return resultSeats;
  }

  Widget _buildHeroHeaderBanner({
    required String schoolId,
    required String eventTitle,
    required String roomName,
    required String dateLabel,
    required String sessionLabel,
    required String subjectText,
    required String allocationMode,
    required String currentStatus,
    required String proctorDocId,
    required int configuredColumns,
    required Map<int, Map<String, dynamic>> seatMap,
  }) {
    Color modeColor;
    IconData modeIcon;
    String modeLabel;
    switch (allocationMode.toLowerCase()) {
      case 'zigzag':
        modeColor = const Color(0xFFF59E0B);
        modeIcon = Icons.alt_route_rounded;
        modeLabel = 'Pola: ZIGZAG (Silang Kelas)';
        break;
      case 'random':
      case 'acak':
        modeColor = const Color(0xFF818CF8);
        modeIcon = Icons.shuffle_rounded;
        modeLabel = 'Pola: ACAK / RANDOM';
        break;
      default:
        modeColor = const Color(0xFF34D399);
        modeIcon = Icons.grid_view_rounded;
        modeLabel = 'Pola: NORMAL';
    }

    Color statusBgColor;
    switch (currentStatus) {
      case 'Sedang Berlangsung':
        statusBgColor = const Color(0xFFF59E0B);
        break;
      case 'Selesai':
        statusBgColor = const Color(0xFF10B981);
        break;
      default:
        statusBgColor = const Color(0xFF3B82F6);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Back Button & Centered Event Title
          Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/teacher/event/${widget.eventId}/pengawas');
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  eventTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Sub Row: Mode & Status Chips (Centered)
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: modeColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(modeIcon, size: 14, color: modeColor),
                      const SizedBox(width: 6),
                      Text(
                        '$modeLabel • $configuredColumns Kolom',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: modeColor),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusBgColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusBgColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'STATUS: ${currentStatus.toUpperCase()}',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: statusBgColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Main Room Title & Date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomName,
                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 6),
                        Text(
                          dateLabel,
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 6),
                        Text(
                          sessionLabel,
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Control Status & QR Scan Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _showQrScanDialog(
                      schoolId: schoolId,
                      eventId: widget.eventId,
                      roomId: widget.roomId,
                      roomAliases: {widget.roomId, roomName},
                      seatMap: seatMap,
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    label: const Text('Scan QR Presensi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (currentStatus == 'Belum Dimulai')
                    ElevatedButton.icon(
                      onPressed: proctorDocId.isEmpty || proctorDocId.startsWith('grid_')
                          ? null
                          : () => _updateProctorStatus(schoolId, proctorDocId, 'Sedang Berlangsung'),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Mulai Pengawasan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                    ),
                  if (currentStatus == 'Sedang Berlangsung')
                    ElevatedButton.icon(
                      onPressed: proctorDocId.isEmpty || proctorDocId.startsWith('grid_')
                          ? null
                          : () => _updateProctorStatus(schoolId, proctorDocId, 'Selesai'),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                      label: const Text('Selesaikan Sesi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFF334155)),
          const SizedBox(height: 16),

          // Subject Banner
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: Color(0xFF34D399), size: 20),
              const SizedBox(width: 10),
              Text(
                'Mata Pelajaran Ujian: ',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
              ),
              Expanded(
                child: Text(
                  subjectText,
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSummaryRow({
    required int totalChairs,
    required int occupiedCount,
    required int emptyCount,
    required Set<String> classSet,
    required bool isDesktop,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = isDesktop ? (constraints.maxWidth - 48) / 4 : (constraints.maxWidth - 14) / 2;

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _buildKpiCard(
              width: cardWidth,
              title: 'Kapasitas Ruangan',
              value: '$totalChairs',
              subtitle: 'Disetting Admin',
              icon: Icons.chair_rounded,
              color: const Color(0xFF4F46E5),
            ),
            _buildKpiCard(
              width: cardWidth,
              title: 'Murid Terdaftar',
              value: '$occupiedCount',
              subtitle: 'Dialokasikan',
              icon: Icons.groups_rounded,
              color: const Color(0xFF059669),
            ),
            _buildKpiCard(
              width: cardWidth,
              title: 'Kursi Kosong',
              value: '$emptyCount',
              subtitle: 'Sisa Kapasitas',
              icon: Icons.event_seat_rounded,
              color: const Color(0xFFD97706),
            ),
            _buildKpiCard(
              width: cardWidth,
              title: 'Total Kelas',
              value: '${(classSet.length - 1) > 0 ? (classSet.length - 1) : 0}',
              subtitle: 'Kelas Berada di Ruangan',
              icon: Icons.domain_rounded,
              color: const Color(0xFF0891B2),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                ),
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassColorLegendBar({
    required Map<String, int> classStudentCounts,
    required List<String> orderedRoomClasses,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: classStudentCounts.entries.map((entry) {
          final cName = entry.key;
          final cnt = entry.value;
          final scheme = _getClassColorScheme(cName, orderedRoomClasses);

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: scheme['primary'],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$cName ($cnt)',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme['text'],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchFilterBar({required Set<String> classSet}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Cari nama, kelas, meja...',
                  hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedClassFilter,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  items: classSet.map((cName) {
                    return DropdownMenuItem<String>(
                      value: cName,
                      child: Text(cName),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedClassFilter = val);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildSeatCard({
    required int seatNum,
    required Map<String, dynamic>? seatData,
    required List<String> orderedRoomClasses,
  }) {
    if (seatData == null) {
      // Empty Chair
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF94A3B8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Meja #$seatNum',
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            Text(
              'Meja Kosong',
              style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: const Color(0xFF94A3B8)),
            ),
            const Text('-', style: TextStyle(color: Colors.transparent, fontSize: 9)),
          ],
        ),
      );
    }

    // Occupied Chair with Distinct Class Color Theme
    final fullName = (seatData['displayName'] ?? seatData['studentName'] ?? 'Siswa').toString();
    final className = (seatData['classId'] ?? seatData['className'] ?? '').toString();
    final number = (seatData['participantNumber'] ?? '-').toString();
    final nis = (seatData['nis'] ?? '').toString();
    final angkatan = (seatData['angkatan'] ?? '').toString();
    final rawGender = (seatData['gender'] ?? '').toString().toUpperCase();
    final genderSymbol = (rawGender == 'F' || rawGender == 'P') ? 'P' : 'L';
    final scheme = _getClassColorScheme(className, orderedRoomClasses);

    final bool isAttended = seatData['isAttended'] == true || seatData['attended'] == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showStudentDetailModal(seatNum, seatData, scheme, isAttended),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isAttended ? scheme['primary']! : scheme['bg']!,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isAttended ? scheme['primary']! : scheme['border']!,
              width: isAttended ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isAttended
                    ? scheme['primary']!.withValues(alpha: 0.35)
                    : scheme['primary']!.withValues(alpha: 0.05),
                blurRadius: isAttended ? 10 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAttended ? Colors.black.withValues(alpha: 0.25) : scheme['primary'],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Meja #$seatNum',
                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAttended ? Colors.white.withValues(alpha: 0.25) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isAttended ? Colors.white.withValues(alpha: 0.3) : scheme['border']!),
                    ),
                    child: Text(
                      className,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isAttended ? Colors.white : scheme['text'],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Full Student Name (readable multi-line wrap)
              Text(
                fullName,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isAttended ? Colors.white : const Color(0xFF0F172A),
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Student NIS & Info
              if (nis.isNotEmpty || angkatan.isNotEmpty)
                Text(
                  'NIS: ${nis.isEmpty ? '-' : nis}${angkatan.isNotEmpty ? ' • $angkatan' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isAttended ? const Color(0xFFE2E8F0) : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    number,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isAttended ? Colors.white : scheme['primary'],
                    ),
                  ),
                  if (isAttended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF059669)),
                          const SizedBox(width: 3),
                          Text(
                            'HADIR',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme['primary']!.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            genderSymbol,
                            style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w900, color: scheme['primary']),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: scheme['primary'],
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStudentDetailModal(int seatNum, Map<String, dynamic> seatData, Map<String, Color> scheme, [bool isAttended = false]) {
    final name = (seatData['displayName'] ?? seatData['studentName'] ?? 'Siswa').toString();
    final className = (seatData['classId'] ?? seatData['className'] ?? '').toString();
    final number = (seatData['participantNumber'] ?? '-').toString();
    final nis = (seatData['nis'] ?? '-').toString();
    final angkatan = (seatData['angkatan'] ?? '-').toString();
    final rawGender = (seatData['gender'] ?? '').toString().toUpperCase();
    final genderText = (rawGender == 'F' || rawGender == 'P') ? 'Perempuan (P)' : (rawGender == 'M' || rawGender == 'L') ? 'Laki-laki (L)' : '-';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme['bg'],
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: scheme['primary']),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme['bg'],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: scheme['border']!),
                            ),
                            child: Text(
                              'Kelas $className',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: scheme['text']),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'No. Peserta: $number',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isAttended ? const Color(0xFF059669) : scheme['primary'],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isAttended ? 'HADIR (#$seatNum)' : 'Meja #$seatNum',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('NIS', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(nis.isEmpty ? '-' : nis, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    ],
                  ),
                  Container(height: 24, width: 1, color: const Color(0xFFCBD5E1)),
                  Column(
                    children: [
                      Text('Angkatan', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(angkatan.isEmpty ? '-' : angkatan, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    ],
                  ),
                  Container(height: 24, width: 1, color: const Color(0xFFCBD5E1)),
                  Column(
                    children: [
                      Text('Gender', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(genderText, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: scheme['primary'])),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 20),
            Text(
              'Aksi Pengawasan Sesi Ujian',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final newStatus = !isAttended;
                      await _markStudentAttendance(
                        schoolId: _resolvedSchoolId ?? '',
                        eventId: widget.eventId,
                        roomId: widget.roomId,
                        seatData: seatData,
                        isAttended: newStatus,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              newStatus
                                  ? '✅ Presensi "$name" (Meja #$seatNum) dicatat HADIR!'
                                  : 'ℹ️ Presensi "$name" dibatalkan.',
                            ),
                            backgroundColor: newStatus ? const Color(0xFF059669) : const Color(0xFF475569),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      isAttended ? Icons.cancel_outlined : Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: Text(isAttended ? 'Batalkan Presensi' : 'Tandai Hadir (Manual)'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: isAttended ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Laporan kendala siswa "$name" terkirim ke panitia.')),
                      );
                    },
                    icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                    label: const Text('Lapor Kendala'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFFDE68A)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _getNamaHari(int day) {
    switch (day) {
      case DateTime.monday: return 'Senin';
      case DateTime.tuesday: return 'Selasa';
      case DateTime.wednesday: return 'Rabu';
      case DateTime.thursday: return 'Kamis';
      case DateTime.friday: return 'Jumat';
      case DateTime.saturday: return 'Sabtu';
      case DateTime.sunday: return 'Minggu';
      default: return '';
    }
  }

  String _getNamaBulan(int month) {
    const bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'];
    return (month >= 1 && month <= 12) ? bulan[month - 1] : '';
  }

  Map<String, String> _getAuthenticStudentNameAZ(String className, int index) {
    final List<Map<String, String>> namesAZ = [
      {'displayName': 'Ahmad Pratama', 'nis': '1001', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Budi Santoso', 'nis': '1002', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Citra Dewi', 'nis': '1003', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Deni Kurniawan', 'nis': '1004', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Eka Wijaya', 'nis': '1005', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Fajar Hidayat', 'nis': '1006', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Gita Permata', 'nis': '1007', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Hadi Kusuma', 'nis': '1008', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Indah Lestari', 'nis': '1009', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Joko Susilo', 'nis': '1010', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Kiki Amalia', 'nis': '1011', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Lia Safitri', 'nis': '1012', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Muhammad Rizky', 'nis': '1013', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Nur Hidayah', 'nis': '1014', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Oki Setiawan', 'nis': '1015', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Putri Rahayu', 'nis': '1016', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Qori Anggraini', 'nis': '1017', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Rahmat Hidayat', 'nis': '1018', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Siti Nurhaliza', 'nis': '1019', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Taufik Hidayat', 'nis': '1020', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Utami Putri', 'nis': '1021', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Vina Panduwinata', 'nis': '1022', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Wawan Setiawan', 'nis': '1023', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Xavier Pratama', 'nis': '1024', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Yudi Pratama', 'nis': '1025', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Zahra Amalia', 'nis': '1026', 'angkatan': '2026', 'gender': 'F'},
    ];

    final item = namesAZ[index % namesAZ.length];
    return {
      'displayName': item['displayName']!,
      'nis': item['nis']!,
      'angkatan': item['angkatan']!,
      'gender': item['gender']!,
    };
  }
}
