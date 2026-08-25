import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sys_exam_school/modules/teacher/controllers/teacher_proctor_controller.dart';

class ProctorSeatCard extends StatelessWidget {
  final int seatNum;
  final Map<String, dynamic>? seatData;
  final List<String> orderedRoomClasses;
  final String schoolId;
  final String eventId;
  final String roomId;
  final Map<String, bool> localAttendedMap;
  final ValueNotifier<int> seatNotifier;

  const ProctorSeatCard({
    super.key,
    required this.seatNum,
    required this.seatData,
    required this.orderedRoomClasses,
    required this.schoolId,
    required this.eventId,
    required this.roomId,
    required this.localAttendedMap,
    required this.seatNotifier,
  });

  @override
  Widget build(BuildContext context) {
    if (seatData == null) {
      // Empty Chair Card
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Meja #$seatNum',
                    style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const Icon(Icons.event_seat_rounded, size: 14, color: Color(0xFFCBD5E1)),
              ],
            ),
            Center(
              child: Text(
                'Kosong',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
              ),
            ),
            const SizedBox.shrink(),
          ],
        ),
      );
    }

    // Occupied Chair Card with Class Palette
    final fullName = (seatData!['displayName'] ?? seatData!['studentName'] ?? seatData!['name'] ?? 'Siswa').toString();
    final className = (seatData!['classId'] ?? seatData!['className'] ?? seatData!['class'] ?? '').toString();
    final number = (seatData!['participantNumber'] ?? '-').toString();
    final nis = (seatData!['nis'] ?? '').toString();
    final angkatan = (seatData!['angkatan'] ?? '').toString();
    final rawGender = (seatData!['gender'] ?? '').toString().toUpperCase();
    final genderSymbol = (rawGender == 'F' || rawGender == 'P') ? 'P' : 'L';
    final scheme = TeacherProctorController.getClassColorScheme(className, orderedRoomClasses);

    final bool isAttended = seatData!['isAttended'] == true || seatData!['attended'] == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => TeacherProctorController.showStudentDetailModal(
          context: context,
          seatNum: seatNum,
          seatData: seatData!,
          scheme: scheme,
          schoolId: schoolId,
          eventId: eventId,
          roomId: roomId,
          localAttendedMap: localAttendedMap,
          seatNotifier: seatNotifier,
          isAttended: isAttended,
        ),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isAttended ? scheme['primary']! : scheme['bg']!,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAttended ? scheme['primary']! : scheme['border']!,
              width: isAttended ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isAttended
                    ? scheme['primary']!.withValues(alpha: 0.35)
                    : scheme['primary']!.withValues(alpha: 0.06),
                blurRadius: isAttended ? 10 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Badges (Meja # and Class Name)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isAttended ? Colors.black.withValues(alpha: 0.25) : scheme['primary'],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Meja #$seatNum',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isAttended ? Colors.white.withValues(alpha: 0.25) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isAttended ? Colors.white.withValues(alpha: 0.3) : scheme['border']!),
                    ),
                    child: Text(
                      className.isNotEmpty ? className : 'Kelas',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: isAttended ? Colors.white : scheme['text'],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Full Student Name (readable 2-line wrap)
              Text(
                fullName,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: isAttended ? Colors.white : const Color(0xFF0F172A),
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // NIS & Angkatan Info
              Text(
                'NIS: ${nis.isEmpty ? '-' : nis}${angkatan.isNotEmpty ? ' • $angkatan' : ''}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isAttended ? const Color(0xFFE2E8F0) : const Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Bottom Bar: Participant Number & Hadir / Gender Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    number,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isAttended ? Colors.white : scheme['primary'],
                    ),
                  ),
                  if (isAttended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
                          const SizedBox(width: 3),
                          Text(
                            'HADIR',
                            style: GoogleFonts.inter(
                              fontSize: 9,
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
                            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, color: scheme['primary']),
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
}
