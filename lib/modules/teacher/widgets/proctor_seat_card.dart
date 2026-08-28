import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sys_exam_school/modules/teacher/controllers/teacher_proctor_controller.dart';

class ProctorSeatCard extends StatefulWidget {
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
  State<ProctorSeatCard> createState() => _ProctorSeatCardState();
}

class _ProctorSeatCardState extends State<ProctorSeatCard> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<Color?> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _blinkAnimation = ColorTween(
      begin: const Color(0xFFF59E0B), // Kuning (Amber)
      end: const Color(0xFFEF4444),   // Merah (Red)
    ).animate(_blinkController);

    if (_shouldBlink) {
      _blinkController.repeat(reverse: true);
    }
  }

  bool get _isCompleted {
    if (widget.seatData == null) return false;
    return widget.seatData!['isCompleted'] == true || widget.seatData!['status'] == 'completed';
  }

  bool get _shouldBlink {
    if (widget.seatData == null) return false;
    if (_isCompleted) return false;
    return widget.seatData!['isLeftApp'] == true || widget.seatData!['status'] == 'left_app';
  }

  @override
  void didUpdateWidget(covariant ProctorSeatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldBlink) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      if (_blinkController.isAnimating) {
        _blinkController.stop();
      }
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seatData == null) {
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
                    'Meja #${widget.seatNum}',
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

    final seatData = widget.seatData!;
    final fullName = (seatData['displayName'] ?? seatData['studentName'] ?? seatData['name'] ?? 'Siswa').toString();
    final className = (seatData['classId'] ?? seatData['className'] ?? seatData['class'] ?? '').toString();
    final number = (seatData['participantNumber'] ?? '-').toString();
    final rawGender = (seatData['gender'] ?? '').toString().toUpperCase();
    final genderSymbol = (rawGender == 'F' || rawGender == 'P') ? 'P' : 'L';
    final scheme = TeacherProctorController.getClassColorScheme(className, widget.orderedRoomClasses);

    final bool isAttended = seatData['isAttended'] == true || seatData['attended'] == true;
    final bool isCompleted = _isCompleted;
    final bool isLeftApp = _shouldBlink;
    final status = (seatData['status'] ?? '').toString();
    final bool isWorking = seatData['isWorking'] == true || status == 'in_progress' || status == 'working' || isAttended;

    return AnimatedBuilder(
      animation: _blinkAnimation,
      builder: (context, child) {
        // Color logic
        Color bgColor;
        Color borderColor;
        Color textColor;
        List<BoxShadow> boxShadow;

        if (isLeftApp) {
          // 1. Murid keluar aplikasi -> Kedap-kedip Kuning Merah
          bgColor = _blinkAnimation.value ?? const Color(0xFFEF4444);
          borderColor = Colors.white;
          textColor = Colors.white;
          boxShadow = [
            BoxShadow(
              color: (_blinkAnimation.value ?? const Color(0xFFEF4444)).withValues(alpha: 0.6),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 2),
            )
          ];
        } else if (isCompleted || isWorking) {
          // 2. Murid mulai / sedang / sudah mengerjakan -> Solid Hijau
          bgColor = const Color(0xFF10B981);
          borderColor = const Color(0xFF047857);
          textColor = Colors.white;
          boxShadow = [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 3),
            )
          ];
        } else {
          // 3. Belum mengerjakan & belum hadir -> Light class background
          bgColor = scheme['bg']!;
          borderColor = scheme['border']!;
          textColor = const Color(0xFF0F172A);
          boxShadow = [
            BoxShadow(
              color: scheme['primary']!.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 3),
            )
          ];
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => TeacherProctorController.showStudentDetailModal(
              context: context,
              seatNum: widget.seatNum,
              seatData: seatData,
              scheme: scheme,
              schoolId: widget.schoolId,
              eventId: widget.eventId,
              roomId: widget.roomId,
              localAttendedMap: widget.localAttendedMap,
              seatNotifier: widget.seatNotifier,
              isAttended: isAttended,
            ),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: (isCompleted || isLeftApp || isAttended) ? 2 : 1.5),
                boxShadow: boxShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Badges (Meja # and Class Name / Status Badge)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isCompleted || isLeftApp || isAttended) ? Colors.black.withValues(alpha: 0.3) : scheme['primary'],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Meja #${widget.seatNum}',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isCompleted || isLeftApp || isAttended) ? Colors.white.withValues(alpha: 0.25) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (isCompleted || isLeftApp || isAttended) ? Colors.white.withValues(alpha: 0.4) : scheme['border']!),
                        ),
                        child: Text(
                          className.isNotEmpty ? className : 'Kelas',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: (isCompleted || isLeftApp || isAttended) ? Colors.white : scheme['text'],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Full Student Name
                  Text(
                    fullName,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // Bottom Bar: Status Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          number,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: (isCompleted || isLeftApp || isWorking || isAttended) ? Colors.white : scheme['primary'],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (isCompleted)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF059669)),
                                const SizedBox(width: 2),
                                Text(
                                  'SELESAI',
                                  style: GoogleFonts.inter(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (isLeftApp)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 11, color: Color(0xFFDC2626)),
                                const SizedBox(width: 2),
                                Text(
                                  'KELUAR APP!',
                                  style: GoogleFonts.inter(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (isWorking || isAttended)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF059669)),
                                const SizedBox(width: 2),
                                Text(
                                  'STANDBY',
                                  style: GoogleFonts.inter(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
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
      },
    );
  }
}
