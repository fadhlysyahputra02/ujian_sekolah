import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sys_exam_school/modules/teacher/controllers/teacher_proctor_controller.dart';
import 'package:sys_exam_school/modules/teacher/widgets/proctor_qr_scan_dialog.dart';

class ProctorHeaderBanner extends StatelessWidget {
  final String roomName;
  final String dateLabel;
  final String sessionLabel;
  final String matchedSubjectsStr;
  final String schoolId;
  final String eventId;
  final String roomId;
  final Map<int, Map<String, dynamic>> seatMap;
  final Map<String, bool> localAttendedMap;
  final ValueNotifier<int> seatNotifier;

  final Set<String>? allowedSubjectNames;
  final Set<String>? allowedSubjectIds;

  final int dayIndex;
  final int sessionIndex;

  final String? currentStatus;
  final String? proctorDocId;
  final String? proctorName;
  final bool isAdminView;
  final VoidCallback? onFinishExam;

  const ProctorHeaderBanner({
    super.key,
    required this.roomName,
    required this.dateLabel,
    required this.sessionLabel,
    required this.matchedSubjectsStr,
    required this.schoolId,
    required this.eventId,
    required this.roomId,
    required this.seatMap,
    required this.localAttendedMap,
    required this.seatNotifier,
    this.allowedSubjectNames,
    this.allowedSubjectIds,
    this.dayIndex = 0,
    this.sessionIndex = 0,
    this.currentStatus,
    this.proctorDocId,
    this.proctorName,
    this.isAdminView = false,
    this.onFinishExam,
  });

  Future<void> _showFinishExamDialog(BuildContext context) async {
    final isAlreadyFinished = currentStatus == 'Selesai' || currentStatus == 'Ujian Selesai';
    if (isAlreadyFinished) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sesi ujian ruangan "$roomName" sudah berstatus selesai.'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Selesaikan Ujian?',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menyelesaikan sesi ujian untuk ruangan $roomName? Status pengawasan ruangan ini akan diubah menjadi "Selesai".',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: const Color(0xFF334155)),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ya, Selesaikan'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;
      if (onFinishExam != null) {
        onFinishExam!();
      } else {
        await TeacherProctorController.updateProctorStatus(
          context: context,
          schoolId: schoolId,
          eventId: eventId,
          proctorDocId: proctorDocId ?? '',
          newStatus: 'Selesai',
          roomId: roomId,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEnded = currentStatus == 'Selesai' || currentStatus == 'Ujian Selesai';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 16 : 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                // Mobile layout: Icon & Title on top
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.meeting_room_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        roomName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF64748B)),
                        const SizedBox(width: 5),
                        Text(
                          dateLabel,
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_filled_rounded, size: 13, color: Color(0xFF64748B)),
                        const SizedBox(width: 5),
                        Text(
                          sessionLabel,
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (proctorName != null && proctorName!.isNotEmpty && proctorName != 'Belum ditentukan')
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_pin_rounded, size: 13, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 5),
                          Text(
                            'Pengawas: $proctorName',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF4F46E5), fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isAdminView)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF475569)),
                        const SizedBox(width: 6),
                        Text(
                          'Mode Pantau Admin (Read-Only)',
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF475569), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      // Selesaikan Ujian Button (di sebelah kiri tombol QR Presensi)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isEnded ? null : () => _showFinishExamDialog(context),
                          icon: Icon(
                            isEnded ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                            size: 16,
                            color: isEnded ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                          label: Text(
                            isEnded ? 'Selesai' : 'Selesaikan Ujian',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isEnded ? const Color(0xFF059669) : const Color(0xFFDC2626),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: isEnded ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                              width: 1.5,
                            ),
                            backgroundColor: isEnded ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Scan QR Presensi Button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => ProctorQrScanDialog.show(
                            context: context,
                            schoolId: schoolId,
                            eventId: eventId,
                            roomId: roomId,
                            roomAliases: {roomId, roomName},
                            seatMap: seatMap,
                            localAttendedMap: localAttendedMap,
                            seatNotifier: seatNotifier,
                            dayIndex: dayIndex,
                            sessionIndex: sessionIndex,
                            allowedSubjectNames: allowedSubjectNames,
                            allowedSubjectIds: allowedSubjectIds,
                          ),
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                          label: const Text(
                            'Scan Presensi',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
              ] else ...[
                // Desktop Top Row: Room Info & Buttons
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.meeting_room_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roomName,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    dateLabel,
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.access_time_filled_rounded, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    sessionLabel,
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              if (proctorName != null && proctorName!.isNotEmpty && proctorName != 'Belum ditentukan')
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person_pin_rounded, size: 14, color: Color(0xFF4F46E5)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Pengawas: $proctorName',
                                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF4F46E5), fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isAdminView)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF475569)),
                            const SizedBox(width: 8),
                            Text(
                              'Mode Pantau Admin (Read-Only)',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // Selesaikan Ujian Button (di sebelah kiri tombol QR Presensi)
                      OutlinedButton.icon(
                        onPressed: isEnded ? null : () => _showFinishExamDialog(context),
                        icon: Icon(
                          isEnded ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                          size: 18,
                          color: isEnded ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        ),
                        label: Text(
                          isEnded ? 'Ujian Selesai' : 'Selesaikan Ujian',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isEnded ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isEnded ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                            width: 1.5,
                          ),
                          backgroundColor: isEnded ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Scan QR Presensi Button
                      ElevatedButton.icon(
                        onPressed: () => ProctorQrScanDialog.show(
                          context: context,
                          schoolId: schoolId,
                          eventId: eventId,
                          roomId: roomId,
                          roomAliases: {roomId, roomName},
                          seatMap: seatMap,
                          localAttendedMap: localAttendedMap,
                          seatNotifier: seatNotifier,
                          dayIndex: dayIndex,
                          sessionIndex: sessionIndex,
                          allowedSubjectNames: allowedSubjectNames,
                          allowedSubjectIds: allowedSubjectIds,
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text('Scan QR Presensi'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Subject Banner Container (Gambar 2 Exact Design)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF166534), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MATA PELAJARAN UJIAN',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF15803D),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            matchedSubjectsStr.isNotEmpty ? matchedSubjectsStr : 'Ujian Terjadwal',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF14532D),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
      },
    );
  }
}

