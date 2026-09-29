import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../../../core/utils/file_saver.dart';
import '../widgets/subject_form_dialog.dart';

class AdminSubjectListView extends StatefulWidget {
  final String schoolId;
  final bool isDesktop;

  const AdminSubjectListView({
    super.key,
    required this.schoolId,
    required this.isDesktop,
  });

  @override
  State<AdminSubjectListView> createState() => _AdminSubjectListViewState();
}

class _AdminSubjectListViewState extends State<AdminSubjectListView> {
  final AdminUserService _adminUserService = AdminUserService();
  final TextEditingController _subjectSearchController = TextEditingController();
  final ValueNotifier<String> _subjectSearchNotifier = ValueNotifier<String>('');

  Stream<List<Map<String, dynamic>>>? _subjectsStream;
  List<Map<String, dynamic>>? _cachedSubjects;

  String? _selectedSubjectKelompokFilter;
  String? _selectedSubjectTingkatFilter;

  @override
  void initState() {
    super.initState();
    _subjectsStream = _adminUserService.streamSubjects(widget.schoolId);
    _subjectSearchController.addListener(() {
      _subjectSearchNotifier.value = _subjectSearchController.text;
    });
  }

  @override
  void dispose() {
    _subjectSearchController.dispose();
    _subjectSearchNotifier.dispose();
    super.dispose();
  }

  void _showSubjectForm(String schoolId, {Map<String, dynamic>? subject}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SubjectFormDialog(schoolId: schoolId, subject: subject),
    );
  }

  Future<void> _deleteSubject(String schoolId, String subjectId, String subjectName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Mata Pelajaran'),
        content: Text('Apakah Anda yakin ingin menghapus mata pelajaran "$subjectName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminUserService.deleteSubject(schoolId: schoolId, docId: subjectId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mata pelajaran "$subjectName" berhasil dihapus.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus mata pelajaran: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildSubjectsTab(widget.schoolId, widget.isDesktop);
  }

  Widget _buildSubjectsTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      initialData: _cachedSubjects,
      stream: _subjectsStream ?? _adminUserService.streamSubjects(schoolId),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedSubjects = snapshot.data;
        }
        if (snapshot.hasError && !snapshot.hasData) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const AppContentLoader(
            title: 'Memuat Mata Pelajaran...',
            subtitle: 'Mengambil daftar mata pelajaran dari database',
          );
        }

        final allSubjects = snapshot.data ?? [];

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Buttons
              if (isDesktop) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mata Pelajaran',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kelola daftar mata pelajaran yang aktif di sekolah',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showSubjectForm(schoolId),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        'Tambah Mapel',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Mobile layout header
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mata Pelajaran',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kelola daftar mata pelajaran aktif',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showSubjectForm(schoolId),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          'Tambah Mapel',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // Search Bar
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _subjectSearchController,
                  style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Cari berdasarkan nama atau kode mapel...',
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
              onChanged: (val) => _subjectSearchNotifier.value = val,
                ),
              ),
              const SizedBox(height: 20),

              // Content List — only this part rebuilds on search
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: _subjectSearchNotifier,
                  builder: (context, query, _) {
                    final filteredSubjects = allSubjects.where((sub) {
                      final q = query.toLowerCase();
                      final name = (sub['name'] ?? '').toString().toLowerCase();
                      final code = (sub['code'] ?? '').toString().toLowerCase();
                      return name.contains(q) || code.contains(q);
                    }).toList();

                    return filteredSubjects.isEmpty
                        ? const Center(child: Text('Tidak ada data mata pelajaran.'))
                        : isDesktop
                            ? _buildSubjectsTable(schoolId, filteredSubjects)
                            : _buildSubjectsMobileList(schoolId, filteredSubjects);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubjectsTable(String schoolId, List<Map<String, dynamic>> subjects) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Nama Mata Pelajaran', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Kode / Singkatan', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: subjects.map((sub) {
            return DataRow(cells: [
              DataCell(Text(sub['name'] ?? '')),
              DataCell(Text(sub['code'] ?? '')),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 20),
                    tooltip: 'Ubah Data',
                    onPressed: () => _showSubjectForm(schoolId, subject: sub),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    tooltip: 'Hapus Mata Pelajaran',
                    onPressed: () => _confirmDeleteSubject(schoolId, sub['id'], sub['name'] ?? ''),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSubjectsMobileList(String schoolId, List<Map<String, dynamic>> subjects) {
    return ListView.builder(
      itemCount: subjects.length,
      itemBuilder: (context, idx) {
        final sub = subjects[idx];
        final name = sub['name'] ?? '';
        final code = sub['code'] ?? '';
        final colors = [
          const Color(0xFF4F46E5),
          const Color(0xFF0D9488),
          const Color(0xFF0284C7),
          const Color(0xFF7C3AED),
          const Color(0xFFDB2777),
        ];
        final subjectColor = colors[name.hashCode % colors.length];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: subjectColor.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: subjectColor.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: subjectColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.book_rounded, color: subjectColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Kode: $code',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 20),
                      onPressed: () => _showSubjectForm(schoolId, subject: sub),
                      tooltip: 'Ubah Data',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                      onPressed: () => _confirmDeleteSubject(schoolId, sub['id'], name),
                      tooltip: 'Hapus',
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteSubject(String schoolId, String docId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Mata Pelajaran'),
        content: Text('Apakah Anda yakin ingin menghapus mata pelajaran $name? Guru yang dikaitkan dengan mapel ini tidak akan terhapus, tetapi mapel ini tidak akan lagi muncul di pilihan.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminUserService.deleteSubject(schoolId: schoolId, docId: docId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mata pelajaran $name berhasil dihapus.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }


}
