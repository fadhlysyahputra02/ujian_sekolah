import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProctorKpiCards extends StatelessWidget {
  final int capacity;
  final int filledCount;
  final int classCount;
  final String status;

  const ProctorKpiCards({
    super.key,
    required this.capacity,
    required this.filledCount,
    required this.classCount,
    this.status = '',
  });

  @override
  Widget build(BuildContext context) {
    final emptyCount = (capacity - filledCount) > 0 ? (capacity - filledCount) : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        if (isCompact) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      value: '$capacity',
                      title: 'Kapasitas Ruangan',
                      subtitle: 'Disetting Admin',
                      icon: Icons.chair_rounded,
                      color: const Color(0xFF4F46E5),
                      bgIconColor: const Color(0xFFEEF2FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildKpiCard(
                      value: '$filledCount',
                      title: 'Murid Terdaftar',
                      subtitle: 'Dialokasikan',
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFF059669),
                      bgIconColor: const Color(0xFFECFDF5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      value: '$emptyCount',
                      title: 'Kursi Kosong',
                      subtitle: 'Sisa Kapasitas',
                      icon: Icons.event_seat_rounded,
                      color: const Color(0xFFD97706),
                      bgIconColor: const Color(0xFFFFFBEB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildKpiCard(
                      value: '$classCount',
                      title: 'Total Kelas',
                      subtitle: 'Kelas Berada di Ruangan',
                      icon: Icons.business_rounded,
                      color: const Color(0xFF0891B2),
                      bgIconColor: const Color(0xFFECFEFF),
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                value: '$capacity',
                title: 'Kapasitas Ruangan',
                subtitle: 'Disetting Admin',
                icon: Icons.chair_rounded,
                color: const Color(0xFF4F46E5),
                bgIconColor: const Color(0xFFEEF2FF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                value: '$filledCount',
                title: 'Murid Terdaftar',
                subtitle: 'Dialokasikan',
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF059669),
                bgIconColor: const Color(0xFFECFDF5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                value: '$emptyCount',
                title: 'Kursi Kosong',
                subtitle: 'Sisa Kapasitas',
                icon: Icons.event_seat_rounded,
                color: const Color(0xFFD97706),
                bgIconColor: const Color(0xFFFFFBEB),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                value: '$classCount',
                title: 'Total Kelas',
                subtitle: 'Kelas Berada di Ruangan',
                icon: Icons.business_rounded,
                color: const Color(0xFF0891B2),
                bgIconColor: const Color(0xFFECFEFF),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgIconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgIconColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF334155),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
