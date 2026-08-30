import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sys_exam_school/modules/teacher/controllers/teacher_proctor_controller.dart';

class ProctorQrScanDialog extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String roomId;
  final Set<String> roomAliases;
  final Map<int, Map<String, dynamic>> seatMap;
  final Map<String, bool> localAttendedMap;
  final ValueNotifier<int> seatNotifier;
  final MobileScannerController scannerController;
  final Future<void> Function() onStopCamera;

  final int dayIndex;
  final int sessionIndex;

  const ProctorQrScanDialog({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.roomId,
    required this.roomAliases,
    required this.seatMap,
    required this.localAttendedMap,
    required this.seatNotifier,
    required this.scannerController,
    required this.onStopCamera,
    this.dayIndex = 0,
    this.sessionIndex = 0,
  });

  static Future<void> show({
    required BuildContext context,
    required String schoolId,
    required String eventId,
    required String roomId,
    required Set<String> roomAliases,
    required Map<int, Map<String, dynamic>> seatMap,
    required Map<String, bool> localAttendedMap,
    required ValueNotifier<int> seatNotifier,
    int dayIndex = 0,
    int sessionIndex = 0,
  }) {
    final MobileScannerController scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      detectionTimeoutMs: 50,
      facing: CameraFacing.front,
      torchEnabled: false,
      returnImage: false,
      formats: const [BarcodeFormat.qrCode],
    );

    Future<void> stopCamera() async {
      try {
        await scannerController.stop();
      } catch (_) {}
      try {
        await scannerController.dispose();
      } catch (_) {}
    }

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PopScope(
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          await stopCamera();
        },
        child: ProctorQrScanDialog(
          schoolId: schoolId,
          eventId: eventId,
          roomId: roomId,
          roomAliases: roomAliases,
          seatMap: seatMap,
          localAttendedMap: localAttendedMap,
          seatNotifier: seatNotifier,
          scannerController: scannerController,
          onStopCamera: stopCamera,
          dayIndex: dayIndex,
          sessionIndex: sessionIndex,
        ),
      ),
    ).then((_) async {
      await stopCamera();
    });
  }

  @override
  State<ProctorQrScanDialog> createState() => _ProctorQrScanDialogState();
}

class _ProctorQrScanDialogState extends State<ProctorQrScanDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  int _activeTab = 0; // 0: Kamera QR, 1: Cari Manual
  bool _isMirrorMode = true;
  bool _isTorchOn = false;
  DateTime _lastScanTime = DateTime.now().subtract(const Duration(seconds: 5));

  String? _feedbackText;
  Color _feedbackBgColor = const Color(0xFF059669);
  IconData _feedbackIcon = Icons.check_circle_rounded;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _showFeedback(String text, Color color, IconData icon) {
    _feedbackTimer?.cancel();
    setState(() {
      _feedbackText = text;
      _feedbackBgColor = color;
      _feedbackIcon = icon;
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _feedbackText = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final attendedCount = widget.seatMap.values.where((s) => s['isAttended'] == true).length;
    final totalCount = widget.seatMap.length;

    final matchingSeats = widget.seatMap.entries.where((entry) {
      final s = entry.value;
      final name = (s['displayName'] ?? s['studentName'] ?? '').toString().toLowerCase();
      final nis = (s['nis'] ?? '').toString().toLowerCase();
      final className = (s['classId'] ?? s['className'] ?? '').toString().toLowerCase();
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return name.contains(q) || nis.contains(q) || className.contains(q) || entry.key.toString() == q;
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 760),
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
                  onPressed: () async {
                    await widget.onStopCamera();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Front-facing Floating Feedback Banner inside Dialog
            if (_feedbackText != null) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _feedbackBgColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _feedbackBgColor.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(_feedbackIcon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _feedbackText!,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _feedbackText = null),
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

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
                      onTap: () async {
                        setState(() => _activeTab = 0);
                        try {
                          if (!widget.scannerController.value.isRunning) {
                            await widget.scannerController.start();
                          }
                        } catch (e) {
                          debugPrint('Scanner start warning: $e');
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _activeTab == 0
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_front_rounded, size: 18, color: _activeTab == 0 ? const Color(0xFF059669) : const Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            Text(
                              'Kamera QR',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: _activeTab == 0 ? FontWeight.bold : FontWeight.w600,
                                color: _activeTab == 0 ? const Color(0xFF059669) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        setState(() => _activeTab = 1);
                        try {
                          await widget.scannerController.stop();
                        } catch (e) {
                          debugPrint('Scanner stop warning: $e');
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _activeTab == 1
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_rounded, size: 18, color: _activeTab == 1 ? const Color(0xFF059669) : const Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            Text(
                              'Cari Manual',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: _activeTab == 1 ? FontWeight.bold : FontWeight.w600,
                                color: _activeTab == 1 ? const Color(0xFF059669) : const Color(0xFF64748B),
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

            // Main Tab View Stack
            Expanded(
              child: Stack(
                children: [
                  // Tab 0: Kamera QR (Kept in widget tree via Offstage to prevent re-mount errors)
                  Offstage(
                    offstage: _activeTab != 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform(
                              alignment: Alignment.center,
                              transform: _isMirrorMode ? Matrix4.rotationY(pi) : Matrix4.identity(),
                              child: MobileScanner(
                                controller: widget.scannerController,
                                errorBuilder: (context, error, child) {
                                  return Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 36),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Kamera Nonaktif',
                                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                onDetect: (capture) {
                                  final now = DateTime.now();
                                  if (now.difference(_lastScanTime).inMilliseconds < 1500) return;
                                  final barcodes = capture.barcodes;
                                  for (final barcode in barcodes) {
                                    final rawValue = barcode.rawValue;
                                    if (rawValue != null && rawValue.isNotEmpty) {
                                      _lastScanTime = now;
                                      TeacherProctorController.processScannedQr(
                                        rawData: rawValue,
                                        schoolId: widget.schoolId,
                                        eventId: widget.eventId,
                                        roomId: widget.roomId,
                                        roomAliases: widget.roomAliases,
                                        seatMap: widget.seatMap,
                                        setDialogState: setState,
                                        localAttendedMap: widget.localAttendedMap,
                                        seatNotifier: widget.seatNotifier,
                                        onShowFeedback: _showFeedback,
                                        dayIndex: widget.dayIndex,
                                        sessionIndex: widget.sessionIndex,
                                      );
                                      break;
                                    }
                                  }
                                },
                              ),
                            ),

                            // Camera Viewfinder Target Frame (Enlarged 220x220)
                            Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFF10B981), width: 2.5),
                                borderRadius: BorderRadius.circular(20),
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
                                      setState(() => _isMirrorMode = !_isMirrorMode);
                                    },
                                    icon: Icon(
                                      _isMirrorMode ? Icons.flip_camera_ios_rounded : Icons.camera_rear_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black45,
                                    ),
                                    tooltip: _isMirrorMode ? 'Mode Mirror: Aktif' : 'Mode Mirror: Nonaktif',
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    onPressed: () async {
                                      await widget.scannerController.toggleTorch();
                                      setState(() => _isTorchOn = !_isTorchOn);
                                    },
                                    icon: Icon(
                                      _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                      color: _isTorchOn ? const Color(0xFFF59E0B) : Colors.white,
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
                                  _isMirrorMode ? '📷 Kamera Mirror Aktif' : '📷 Tampilan Kamera Normal',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Tab 1: Cari Manual (Search Field + Student List)
                  Offstage(
                    offstage: _activeTab != 1,
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (val) => setState(() => _query = val),
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
                                              setState(() {
                                                seatData['isAttended'] = newStatus;
                                              });
                                              widget.seatNotifier.value++;
                                              TeacherProctorController.triggerScanFeedback(isSuccess: newStatus);
                                              await TeacherProctorController.markStudentAttendance(
                                                schoolId: widget.schoolId,
                                                eventId: widget.eventId,
                                                roomId: widget.roomId,
                                                seatData: seatData,
                                                isAttended: newStatus,
                                                localAttendedMap: widget.localAttendedMap,
                                                seatNotifier: widget.seatNotifier,
                                                dayIndex: widget.dayIndex,
                                                sessionIndex: widget.sessionIndex,
                                              );
                                              _showFeedback(
                                                newStatus
                                                    ? '✅ "$name" (Meja #$seatNum) ditandai HADIR!'
                                                    : 'ℹ️ Presensi "$name" dibatalkan.',
                                                newStatus ? const Color(0xFF059669) : const Color(0xFF475569),
                                                newStatus ? Icons.check_circle_rounded : Icons.info_rounded,
                                              );
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
