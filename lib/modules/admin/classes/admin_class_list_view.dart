import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../widgets/class_form_dialog.dart';
import 'class_detail_screen.dart';

class AdminClassListView extends StatefulWidget {
  final String schoolId;
  final bool isDesktop;

  const AdminClassListView({
    super.key,
    required this.schoolId,
    required this.isDesktop,
  });

  @override
  State<AdminClassListView> createState() => _AdminClassListViewState();
}

class _AdminClassListViewState extends State<AdminClassListView> {
  final AdminUserService _adminUserService = AdminUserService();
  final TextEditingController _classSearchController = TextEditingController();
  final ValueNotifier<String> _classSearchNotifier = ValueNotifier<String>('');

  Stream<List<Map<String, dynamic>>>? _classesStream;
  List<Map<String, dynamic>>? _cachedClasses;
  DocumentSnapshot? _cachedSchoolSnapshot;

  @override
  void initState() {
    super.initState();
    _classesStream = _adminUserService.streamClasses(widget.schoolId);
    _classSearchController.addListener(() {
      _classSearchNotifier.value = _classSearchController.text;
    });
  }

  @override
  void dispose() {
    _classSearchController.dispose();
    _classSearchNotifier.dispose();
    super.dispose();
  }

  void _showClassForm(String schoolId, {Map<String, dynamic>? classData}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ClassFormDialog(schoolId: schoolId, existingClass: classData),
    );
  }

  Future<void> _deleteClass(String schoolId, String classId, String className) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kelas'),
        content: Text('Apakah Anda yakin ingin menghapus kelas "$className"?'),
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
      await _adminUserService.deleteClass(schoolId: schoolId, classId: classId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kelas "$className" berhasil dihapus.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus kelas: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildClassesTab(widget.schoolId, widget.isDesktop);
  }

  Widget _buildClassesTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      initialData: _cachedClasses,
      stream: _classesStream ?? _adminUserService.streamClasses(schoolId),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedClasses = snapshot.data;
        }
        if (snapshot.hasError && !snapshot.hasData) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const AppContentLoader(
            title: 'Memuat Data Kelas...',
            subtitle: 'Mengambil daftar kelas dari database',
          );
        }
        final classes = snapshot.data ?? [];

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              if (isDesktop) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kelas',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kelola kelas dan daftar murid di dalamnya',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final scaffoldMsg = ScaffoldMessenger.of(context);
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (_) => ClassFormDialog(schoolId: schoolId),
                        );
                        if (result == true) {
                          scaffoldMsg.showSnackBar(
                            const SnackBar(content: Text('Kelas berhasil ditambahkan!')),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        'Tambah Kelas',
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
                      'Kelas',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kelola kelas & daftar murid',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final scaffoldMsg = ScaffoldMessenger.of(context);
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (_) => ClassFormDialog(schoolId: schoolId),
                          );
                          if (result == true) {
                            scaffoldMsg.showSnackBar(
                              const SnackBar(content: Text('Kelas berhasil ditambahkan!')),
                            );
                          }
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          'Tambah Kelas',
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
                  controller: _classSearchController,
                  style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Cari berdasarkan nama kelas...',
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (val) => _classSearchNotifier.value = val,
                ),
              ),
              const SizedBox(height: 20),

              // ── Content ── only this part rebuilds on search
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: _classSearchNotifier,
                  builder: (context, query, _) {
                    final filteredClasses = classes.where((c) {
                      final q = query.toLowerCase();
                      final name = (c['name'] ?? '').toString().toLowerCase();
                      return name.contains(q);
                    }).toList();

                    if (filteredClasses.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.class_outlined, size: 72, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'Belum ada kelas yang dibuat.\nTekan "Tambah Kelas" untuk memulai.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 15),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredClasses.length,
                      itemBuilder: (context, i) {
                        final cls = filteredClasses[i];
                        final name = cls['name'] as String? ?? '-';
                        final studentCount = (cls['studentIds'] as List?)?.length ?? 0;
                        final colors = [
                          const Color(0xFF4F46E5),
                          const Color(0xFF0D9488),
                          const Color(0xFF0284C7),
                          const Color(0xFF7C3AED),
                          const Color(0xFFDB2777),
                        ];
                        final classColor = colors[name.hashCode % colors.length];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: classColor.withValues(alpha: 0.15)),
                            boxShadow: [
                              BoxShadow(
                                color: classColor.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => context.go(
                              '/class-detail/${cls['id']}',
                            ),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: classColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.class_rounded, color: classColor, size: 20),
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
                                        Row(
                                          children: [
                                            const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFF64748B)),
                                            const SizedBox(width: 6),
                                            Text(
                                              '$studentCount Murid',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: const Color(0xFF64748B),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: classColor.withValues(alpha: 0.6)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  // ignore: unused_element
  Widget _buildClassCard(Map<String, dynamic> cls, String schoolId) {
    final name = cls['name'] as String? ?? '-';
    final studentIds = (cls['studentIds'] as List?)?.length ?? 0;

    return InkWell(
      onTap: () async {
        context.go(
          '/class-detail/${cls['id']}',
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(color: Color(0x04000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.class_rounded, color: Color(0xFF4F46E5), size: 20),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people_rounded, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      '$studentIds murid',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF94A3B8)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncStats(String schoolId, Map<String, dynamic> currentMeta) async {
    try {
      final teachersSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .where('archived', isEqualTo: false)
          .count()
          .get();

      final studentsSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .where('archived', isEqualTo: false)
          .count()
          .get();

      final actualTeachers = teachersSnap.count ?? 0;
      final actualStudents = studentsSnap.count ?? 0;

      final currentTeachers = currentMeta['teacherCount'] ?? 0;
      final currentStudents = currentMeta['studentCount'] ?? 0;

      if (actualTeachers != currentTeachers || actualStudents != currentStudents) {
        await FirebaseFirestore.instance.collection('schools').doc(schoolId).update({
          'meta.teacherCount': actualTeachers,
          'meta.studentCount': actualStudents,
        });
      }
    } catch (e) {
      debugPrint('Error syncing stats: $e');
    }
  }

  Widget _buildQuotaWarningBanner(String schoolId) {
    return StreamBuilder<DocumentSnapshot>(
      initialData: _cachedSchoolSnapshot,
      stream: FirebaseFirestore.instance.collection('schools').doc(schoolId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedSchoolSnapshot = snapshot.data;
        }
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final meta = data['meta'] as Map<String, dynamic>? ?? {};
        final currentStudentCount = meta['studentCount'] ?? 0;
        final currentTeacherCount = meta['teacherCount'] ?? 0;
        final maxStudentQuota = data['maxStudentQuota'] ?? 500;
        final maxTeacherQuota = data['maxTeacherQuota'] ?? 50;

        final isStudentFull = currentStudentCount >= maxStudentQuota;
        final isTeacherFull = currentTeacherCount >= maxTeacherQuota;

        if (!isStudentFull && !isTeacherFull) return const SizedBox.shrink();

        final List<String> warnings = [];
        if (isTeacherFull) {
          warnings.add('Kuota Guru Terlampaui: saat ini $currentTeacherCount guru terdaftar (Batas maksimal SuperAdmin: $maxTeacherQuota).');
        }
        if (isStudentFull) {
          warnings.add('Kuota Murid Terlampaui: saat ini $currentStudentCount murid terdaftar (Batas maksimal SuperAdmin: $maxStudentQuota).');
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Peringatan Batas Kuota Sekolah!',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF991B1B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...warnings.map((w) => Text(
                          '• $w',
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFB91C1C), height: 1.4),
                        )),
                    const SizedBox(height: 6),
                    Text(
                      'Penambahan data baru telah dikunci. Silakan hubungi Super Admin untuk menambah alokasi kuota sekolah Anda.',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF7F1D1D)),
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
