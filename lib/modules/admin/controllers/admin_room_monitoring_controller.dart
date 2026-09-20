import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminRoomMonitoringController {
  static const List<Map<String, Color>> classColorPalette = [
    {
      'primary': Color(0xFF4F46E5), // Indigo
      'bg': Color(0xFFEEF2FF),
      'border': Color(0xFFC7D2FE),
      'text': Color(0xFF3730A3),
    },
    {
      'primary': Color(0xFFEA580C), // Orange
      'bg': Color(0xFFFFF7ED),
      'border': Color(0xFFFFEDD5),
      'text': Color(0xFF9A3412),
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

  static Map<String, Color> getClassColorScheme(String className, List<String> roomClasses) {
    final index = roomClasses.indexOf(className);
    if (index >= 0) {
      return classColorPalette[index % classColorPalette.length];
    }
    return classColorPalette[0];
  }

  /// Calculates dynamic status for a session based on its date and time range
  static String getSessionStatus({
    required DateTime? sessionDate,
    required String timeRange,
    String? fallbackStatus,
  }) {
    if (sessionDate == null) return fallbackStatus ?? 'Belum Dimulai';

    final timeMatch = RegExp(r'(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})').firstMatch(timeRange);
    if (timeMatch != null) {
      final sParts = timeMatch.group(1)!.split(':');
      final eParts = timeMatch.group(2)!.split(':');
      if (sParts.length >= 2 && eParts.length >= 2) {
        final startDt = DateTime(sessionDate.year, sessionDate.month, sessionDate.day, int.parse(sParts[0]), int.parse(sParts[1]));
        final endDt = DateTime(sessionDate.year, sessionDate.month, sessionDate.day, int.parse(eParts[0]), int.parse(eParts[1]));
        final now = DateTime.now();

        if (now.isAfter(endDt)) {
          return 'Ujian Selesai';
        } else if ((now.isAfter(startDt) || now.isAtSameMomentAs(startDt)) && now.isBefore(endDt)) {
          return 'Sedang Berlangsung';
        } else if (now.isBefore(startDt)) {
          return 'Belum Dimulai';
        }
      }
    }

    return fallbackStatus ?? 'Belum Dimulai';
  }

  /// Shows clean, read-only student details modal for School Admin
  static void showStudentDetailModal({
    required BuildContext context,
    required int seatNum,
    required Map<String, dynamic> seatData,
    required Map<String, Color> scheme,
    required bool isAttended,
    required int dayIndex,
    required int sessionIndex,
  }) {
    final name = (seatData['displayName'] ?? seatData['studentName'] ?? seatData['name'] ?? 'Siswa').toString();
    final className = (seatData['classId'] ?? seatData['className'] ?? seatData['class'] ?? '-').toString();
    final number = (seatData['participantNumber'] ?? '-').toString();
    final nis = (seatData['nis'] ?? '-').toString();
    final angkatan = (seatData['angkatan'] ?? '-').toString();
    final rawGender = (seatData['gender'] ?? '').toString().toUpperCase();
    final genderText = (rawGender == 'F' || rawGender == 'P') ? 'Perempuan (P)' : 'Laki-Laki (L)';

    final isCompleted = seatData['isCompleted'] == true || seatData['status'] == 'completed';
    final isLeftApp = !isCompleted && (seatData['isLeftApp'] == true || seatData['status'] == 'left_app');
    final isWorking = seatData['isWorking'] == true || seatData['status'] == 'in_progress' || seatData['status'] == 'working';

    final totalQ = (seatData['totalQuestions'] as num?)?.toInt();
    final ansQ = (seatData['answeredCount'] as num?)?.toInt() ?? (isCompleted ? totalQ : null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          maxWidth: 540,
        ),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: MediaQuery.of(ctx).size.width > 600 ? (MediaQuery.of(ctx).size.width - 540) / 2 : 0,
          right: MediaQuery.of(ctx).size.width > 600 ? (MediaQuery.of(ctx).size.width - 540) / 2 : 0,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header: Student Name, Class & Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                            Text(
                              'No: $number',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFF10B981)
                          : (isLeftApp ? const Color(0xFFEF4444) : (isWorking ? const Color(0xFF2563EB) : (isAttended ? const Color(0xFF059669) : const Color(0xFF64748B)))),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isCompleted
                          ? 'SELESAI (#$seatNum)'
                          : (isLeftApp
                              ? 'KELUAR APP! (#$seatNum)'
                              : (isWorking
                                  ? (totalQ != null && totalQ > 0 ? '${ansQ ?? 0}/$totalQ (#$seatNum)' : 'MENGERJAKAN (#$seatNum)')
                                  : (isAttended ? 'HADIR (#$seatNum)' : 'BELUM HADIR (#$seatNum)'))),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Student Info Cards
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

              // Progress Bar if questions are available
              if (totalQ != null && totalQ > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.fact_check_rounded, size: 16, color: Color(0xFF2563EB)),
                              const SizedBox(width: 6),
                              Text(
                                'Progress Pengerjaan Soal',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          Text(
                            '${ansQ ?? 0} / $totalQ Soal (${((ansQ ?? 0) / totalQ * 100).clamp(0, 100).round()}%)',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF2563EB)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (ansQ ?? 0) / totalQ,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isCompleted ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Proctor Note (if any)
              if ((seatData['proctorNote'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.assignment_late_rounded, size: 16, color: Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Catatan Pengawas:',
                              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF92400E)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              seatData['proctorNote'].toString(),
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF78350F)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Admin Read-Only Mode Tag
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_rounded, size: 16, color: Color(0xFF2563EB)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mode Pantau Admin: Seluruh data disinkronkan secara live untuk pemantauan ujian.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF1D4ED8), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Tutup', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
