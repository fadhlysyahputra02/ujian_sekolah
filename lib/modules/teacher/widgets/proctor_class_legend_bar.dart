import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProctorClassLegendBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (roomClasses.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: roomClasses.map((cls) {
          final count = classStudentCounts[cls] ?? 0;
          final scheme = classColorMap[cls] ??
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
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: scheme['text']),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
