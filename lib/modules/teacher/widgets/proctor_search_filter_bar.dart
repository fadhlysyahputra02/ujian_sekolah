import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProctorSearchFilterBar extends StatelessWidget {
  final String searchQuery;
  final String selectedClassFilter;
  final Set<String> classSet;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onClassFilterChanged;
  final VoidCallback? onShowExitLogs;
  final int exitLogCount;

  const ProctorSearchFilterBar({
    super.key,
    required this.searchQuery,
    required this.selectedClassFilter,
    required this.classSet,
    required this.onSearchChanged,
    required this.onClassFilterChanged,
    this.onShowExitLogs,
    this.exitLogCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final itemsList = <String>['Semua Kelas', ...classSet];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onSearchChanged,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
              decoration: InputDecoration(
                hintText: 'Cari murid berdasarkan nama lengkap, kelas, atau nomor meja...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (onShowExitLogs != null) ...[
            ElevatedButton.icon(
              onPressed: onShowExitLogs,
              style: ElevatedButton.styleFrom(
                backgroundColor: exitLogCount > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                foregroundColor: exitLogCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF475569),
                elevation: 0,
                side: BorderSide(
                  color: exitLogCount > 0 ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              icon: Icon(
                Icons.history_rounded,
                size: 16,
                color: exitLogCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF475569),
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Riwayat Keluar App',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: exitLogCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF475569),
                    ),
                  ),
                  if (exitLogCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$exitLogCount',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: itemsList.contains(selectedClassFilter) ? selectedClassFilter : 'Semua Kelas',
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B), size: 18),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                items: itemsList.map((cName) {
                  return DropdownMenuItem<String>(
                    value: cName,
                    child: Text(cName),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onClassFilterChanged(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
