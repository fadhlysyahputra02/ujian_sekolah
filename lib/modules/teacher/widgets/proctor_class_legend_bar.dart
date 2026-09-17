import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProctorClassLegendBar extends StatefulWidget {
  final List<String> roomClasses;
  final Map<String, int> classStudentCounts;
  final Map<String, Map<String, Color>> classColorMap;

  const ProctorClassLegendBar({
    super.key,
    required this.roomClasses,
    required this.classStudentCounts,
    required this.classColorMap,
  });

  @override
  State<ProctorClassLegendBar> createState() => _ProctorClassLegendBarState();
}

class _ProctorClassLegendBarState extends State<ProctorClassLegendBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<Color?> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _blinkAnimation = ColorTween(
      begin: const Color(0xFFEF4444),
      end: const Color(0xFFF59E0B),
    ).animate(_blinkController);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        children: [
          // 1. Indikator Warna Kelas Siswa
          ...widget.roomClasses.map((cls) {
            final count = widget.classStudentCounts[cls] ?? 0;
            final scheme = widget.classColorMap[cls] ??
                const {
                  'primary': Color(0xFF4F46E5),
                  'bg': Color(0xFFEEF2FF),
                  'border': Color(0xFFC7D2FE),
                  'text': Color(0xFF3730A3),
                };

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: scheme['primary'],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$cls ($count)',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme['text'],
                  ),
                ),
              ],
            );
          }),

          // Pemisah (jika ada kelas)
          if (widget.roomClasses.isNotEmpty)
            Container(height: 14, width: 1, color: const Color(0xFFCBD5E1)),

          // 2. Indikator Meja Kosong
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Meja Kosong',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          Container(height: 14, width: 1, color: const Color(0xFFCBD5E1)),

          // 4. Indikator Animasi Kedip Merah-Kuning (Murid Keluar App)
          AnimatedBuilder(
            animation: _blinkAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _blinkAnimation.value ?? const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: (_blinkAnimation.value ?? const Color(0xFFEF4444))
                          .withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Kedip Merah-Kuning: Murid Keluar App',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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
}
