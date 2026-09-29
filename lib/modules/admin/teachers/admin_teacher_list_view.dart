import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:excel/excel.dart' as ex;
import '../../../core/models/teacher.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../../../core/utils/file_saver.dart';
import '../widgets/teacher_form_dialog.dart';
import '../widgets/import_teachers_dialog.dart';
import '../widgets/generate_password_dialog.dart';

class AdminTeacherListView extends StatefulWidget {
  final String schoolId;
  final bool isDesktop;

  const AdminTeacherListView({
    super.key,
    required this.schoolId,
    required this.isDesktop,
  });

  @override
  State<AdminTeacherListView> createState() => _AdminTeacherListViewState();
}

class _AdminTeacherListViewState extends State<AdminTeacherListView> {
  final AdminUserService _adminUserService = AdminUserService();

  Stream<List<Teacher>>? _teachersStream;
  List<Teacher>? _cachedTeachers;

  // Search & Filter States
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  final ScrollController _teacherTableHorizontalScrollController = ScrollController();

  String? _selectedTeacherGenderFilter;
  String? _selectedTeacherSubjectFilter;
  String? _selectedTeacherStatusFilter;

  // Pagination & Sorting States
  int _teacherCurrentPage = 0;
  int _teacherRowsPerPage = 10;
  String _teacherSortColumn = 'nama';
  bool _teacherSortAscending = true;

  @override
  void initState() {
    super.initState();
    _teachersStream = _adminUserService.streamTeachers(widget.schoolId);
  }

  @override
  void didUpdateWidget(AdminTeacherListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId) {
      _refreshTeachers();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchNotifier.dispose();
    _teacherTableHorizontalScrollController.dispose();
    super.dispose();
  }

  void _refreshTeachers() {
    setState(() {
      _cachedTeachers = null;
      _teachersStream = _adminUserService.streamTeachers(widget.schoolId);
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _searchNotifier.value = '';
    setState(() {
      _teacherCurrentPage = 0;
      _teacherSortColumn = 'nama';
      _teacherSortAscending = true;
      _selectedTeacherGenderFilter = null;
      _selectedTeacherSubjectFilter = null;
      _selectedTeacherStatusFilter = null;
    });
  }

  void _showQuotaFullDialog(String type, int current, int maxQuota) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            const SizedBox(width: 10),
            Text('Batas Kuota $type Penuh', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Jumlah $type saat ini telah mencapai batas maksimal ($current / $maxQuota).\n\nPenambahan $type baru dinonaktifkan. Silakan hubungi Super Admin untuk menambah kuota sekolah Anda.',
          style: GoogleFonts.inter(fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTeacherForm({Teacher? teacher}) async {
    if (teacher == null) {
      final sDoc = await FirebaseFirestore.instance.collection('schools').doc(widget.schoolId).get();
      if (sDoc.exists) {
        final sData = sDoc.data() ?? {};
        final teacherCount = (sData['meta'] as Map?)?['teacherCount'] ?? 0;
        final maxQuota = sData['maxTeacherQuota'] ?? 50;
        if (teacherCount >= maxQuota) {
          _showQuotaFullDialog('Guru', teacherCount, maxQuota);
          return;
        }
      }
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TeacherFormDialog(schoolId: widget.schoolId, teacher: teacher),
    );
    _refreshTeachers();
  }

  Future<void> _showImportTeachersDialog() async {
    final sDoc = await FirebaseFirestore.instance.collection('schools').doc(widget.schoolId).get();
    if (sDoc.exists) {
      final sData = sDoc.data() ?? {};
      final teacherCount = (sData['meta'] as Map?)?['teacherCount'] ?? 0;
      final maxQuota = sData['maxTeacherQuota'] ?? 50;
      if (teacherCount >= maxQuota) {
        _showQuotaFullDialog('Guru', teacherCount, maxQuota);
        return;
      }
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportTeachersDialog(schoolId: widget.schoolId),
    );
    _refreshTeachers();
  }

  Future<void> _exportTeachersExcel(List<Teacher> teachers) async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow([
        ex.TextCellValue('NIP'),
        ex.TextCellValue('Nama Lengkap'),
        ex.TextCellValue('Jenis Kelamin'),
        ex.TextCellValue('Mata Pelajaran'),
        ex.TextCellValue('Email'),
        ex.TextCellValue('Kata Sandi'),
        ex.TextCellValue('Status Akun'),
      ]);

      for (var t in teachers) {
        sheet.appendRow([
          ex.TextCellValue(t.nip),
          ex.TextCellValue(t.displayName),
          ex.TextCellValue(t.gender == 'M' ? 'Laki-laki (M)' : 'Perempuan (F)'),
          ex.TextCellValue(t.subjects.join(', ')),
          ex.TextCellValue(t.email ?? '-'),
          ex.TextCellValue(t.tempPassword ?? '-'),
          ex.TextCellValue(t.disabled ? 'Nonaktif' : 'Aktif'),
        ]);
      }

      final fileBytes = excel.save(fileName: 'SesiCermat_Daftar_Guru.xlsx');
      if (fileBytes != null) {
        if (!kIsWeb) {
          await saveAndDownloadFile(fileBytes, 'SesiCermat_Daftar_Guru.xlsx');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Daftar guru berhasil diekspor ke Excel!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor data: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _generateAllTeacherPasswords(List<Teacher> teachers) async {
    if (teachers.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Informasi'),
          content: const Text('Tidak ada data guru.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
      return;
    }

    final missingPasswords = teachers.where((t) => t.tempPassword == null || t.tempPassword!.trim().isEmpty).toList();
    final bool isAllHavePassword = missingPasswords.isEmpty;
    final List<Teacher> targets = isAllHavePassword ? teachers : missingPasswords;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isAllHavePassword ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isAllHavePassword ? Icons.warning_amber_rounded : Icons.key_rounded,
                color: isAllHavePassword ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                isAllHavePassword ? 'Reset Semua Sandi Guru' : 'Generate Sandi Massal',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: isAllHavePassword
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semua guru (${teachers.length} guru) sudah memiliki kata sandi.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Peringatan: Tindakan ini akan menimpa dan mengganti kata sandi SEMUA (${teachers.length}) guru dengan kata sandi baru. Kata sandi sebelumnya tidak akan bisa digunakan lagi.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF991B1B),
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Apakah Anda yakin ingin melanjutkan reset kata sandi massal untuk semua guru?',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Text(
                'Ditemukan ${targets.length} guru yang belum memiliki kata sandi.\n\nApakah Anda yakin ingin membuat kata sandi sementara untuk ${targets.length} guru tersebut?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF475569),
                  height: 1.5,
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Batal',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAllHavePassword ? const Color(0xFFDC2626) : const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(
              isAllHavePassword ? 'Ya, Reset Semua (${targets.length})' : 'Mulai Generate (${targets.length})',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final progressNotifier = ValueNotifier<Map<String, dynamic>>({
      'pct': 0.0,
      'name': '',
      'processed': 0,
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: progressNotifier,
          builder: (context, val, child) {
            final pct = val['pct'] as double;
            final processed = val['processed'] as int;
            final name = val['name'] as String;
            final pctInt = (pct * 100).toInt();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.all(24),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.vpn_key_rounded, color: Color(0xFFD97706), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Generate Sandi Massal',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Mohon tunggu sebentar...',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Memproses $processed dari ${targets.length} guru...',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF475569),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$pctInt%',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: const Color(0xFFF1F5F9),
                        color: const Color(0xFFD97706),
                        minHeight: 8,
                      ),
                    ),
                    if (name.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF334155),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    try {
      for (int i = 0; i < targets.length; i++) {
        final t = targets[i];
        if (!mounted) break;

        progressNotifier.value = {
          'pct': i / targets.length,
          'name': t.displayName,
          'processed': i,
        };

        await _adminUserService.generateTempPassword(
          schoolId: widget.schoolId,
          collectionType: 'teachers',
          docId: t.id,
        );
      }

      progressNotifier.value = {
        'pct': 1.0,
        'name': 'Selesai!',
        'processed': targets.length,
      };

      await Future.delayed(const Duration(milliseconds: 600));
    } catch (e) {
      debugPrint('Error mass generating password: $e');
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
        _refreshTeachers();
      }
    }
  }

  Future<void> _generateSingleTeacherPasswordDirectly(Teacher t) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempPassword = await _adminUserService.generateTempPassword(
        schoolId: widget.schoolId,
        collectionType: 'teachers',
        docId: t.id,
      );

      if (mounted) {
        Navigator.of(context).pop();
        _refreshTeachers();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kata sandi berhasil dibuat untuk ${t.displayName}: $tempPassword'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat kata sandi: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _resetSingleTeacherSession(Teacher teacher) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.phonelink_erase_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            Text('Reset Sesi Login', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin mereset sesi login untuk guru "${teacher.displayName}" (NIP: ${teacher.nip.isEmpty ? '-' : teacher.nip})?\n\nAkun guru ini akan otomatis keluar (logout) dari perangkat yang terhubung.',
          style: GoogleFonts.inter(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ya, Reset Sesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminUserService.resetTeacherSession(
        schoolId: widget.schoolId,
        teacherId: teacher.id,
      );
      _refreshTeachers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sesi login guru "${teacher.displayName}" berhasil direset.'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mereset sesi login: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _resetAllTeacherSessions(List<Teacher> teachers) async {
    final activeSessionTeachers = teachers.where((t) => t.hasActiveSession).toList();
    final countToReset = activeSessionTeachers.isEmpty ? teachers.length : activeSessionTeachers.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFFD97706), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Reset Semua Sesi Guru',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tindakan ini akan mereset dan mengeluarkan (logout) sesi login aktif untuk seluruh guru di sekolah ini ($countToReset guru).',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF4F46E5), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Isolasi Sekolah: Perintah ini secara ketat hanya memproses guru pada ID Sekolah ini (${widget.schoolId}) dan tidak mempengaruhi sekolah lain.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF3730A3), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ya, Reset Semua Sesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final totalReset = await _adminUserService.resetAllTeacherSessions(
        schoolId: widget.schoolId,
      );
      _refreshTeachers();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil mereset $totalReset sesi login guru.'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mereset sesi massal: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _toggleTeacherStatus(Teacher teacher) async {
    final bool currentlyDisabled = teacher.disabled;
    final bool newDisabled = !currentlyDisabled;
    final String actionText = currentlyDisabled ? 'mengaktifkan' : 'menonaktifkan';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Konfirmasi Status Guru', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin $actionText guru "${teacher.displayName}" (NIP: ${teacher.nip.isEmpty ? '-' : teacher.nip})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyDisabled ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(currentlyDisabled ? 'Aktifkan' : 'Non-aktifkan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (!newDisabled) {
        final schoolDoc = await FirebaseFirestore.instance.collection('schools').doc(widget.schoolId).get();
        final maxQuota = (schoolDoc.data()?['maxTeacherQuota'] as num?)?.toInt() ?? 50;
        final teachersSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolId)
            .collection('teachers')
            .get();
        final activeCount = teachersSnap.docs.where((d) => d.data()['archived'] != true && d.data()['disabled'] != true).length;
        if (activeCount >= maxQuota) {
          throw Exception('Kuota guru aktif telah mencapai batas maksimal ($maxQuota). Non-aktifkan guru lain terlebih dahulu.');
        }
      }

      final schoolRef = FirebaseFirestore.instance.collection('schools').doc(widget.schoolId);
      await schoolRef.collection('teachers').doc(teacher.id).update({
        'disabled': newDisabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final teachersSnap = await schoolRef.collection('teachers').get();
      final activeCount = teachersSnap.docs.where((d) => d.data()['archived'] != true && d.data()['disabled'] != true).length;
      await schoolRef.update({
        'meta.teacherCount': activeCount,
      });

      _refreshTeachers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status guru "${teacher.displayName}" berhasil diubah menjadi ${!newDisabled ? 'Aktif' : 'Non-aktif'}.'),
            backgroundColor: !newDisabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errStr),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _resetPassword(String docId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                'Buat Ulang Kata Sandi',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.5),
                  children: [
                    const TextSpan(text: 'Apakah Anda yakin ingin mengatur ulang kata sandi untuk '),
                    TextSpan(
                      text: displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const TextSpan(text: '? Sistem akan membuatkan kata sandi acak baru.'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        foregroundColor: const Color(0xFF64748B),
                      ),
                      child: Text('Batal', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text('Ya, Reset', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempPassword = await _adminUserService.generateTempPassword(
        schoolId: widget.schoolId,
        collectionType: 'teachers',
        docId: docId,
      );

      if (mounted) {
        Navigator.of(context).pop();
        _refreshTeachers();

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => GeneratePasswordDialog(
            tempPassword: tempPassword,
            displayName: displayName,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mereset kata sandi: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _deleteUser(String docId, String name, String identifier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pengguna'),
        content: Text('Apakah Anda yakin ingin menghapus akun $name ($identifier) secara permanen dari sistem? Tindakan ini tidak dapat dibatalkan.'),
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
      await _adminUserService.permanentDeleteUser(
        schoolId: widget.schoolId,
        collectionType: 'teachers',
        docId: docId,
      );
      if (mounted) {
        _refreshTeachers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Akun $name berhasil dihapus permanen!')),
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

  Widget _buildQuotaWarningBanner(String schoolId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('schools').doc(schoolId).snapshots(),
      builder: (context, snapshot) {
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

  Widget _buildPaginationControls({
    required int currentPage,
    required int rowsPerPage,
    required int totalItems,
    required ValueChanged<int> onPageChanged,
    required ValueChanged<int> onRowsPerPageChanged,
  }) {
    final totalPages = (totalItems / rowsPerPage).ceil();
    final start = currentPage * rowsPerPage;
    final end = (start + rowsPerPage < totalItems) ? start + rowsPerPage : totalItems;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!isMobile) ...[
            Text(
              'Baris per halaman:',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
          ],
          DropdownButton<int>(
            value: rowsPerPage,
            items: [10, 20, 50].map((val) {
              return DropdownMenuItem<int>(
                value: val,
                child: Text('$val', style: GoogleFonts.inter(fontSize: 12)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                onRowsPerPageChanged(val);
              }
            },
            underline: const SizedBox(),
          ),
          SizedBox(width: isMobile ? 12 : 24),
          Text(
            totalItems == 0 ? '0-0 dari 0' : '${start + 1}-$end dari $totalItems',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
          ),
          SizedBox(width: isMobile ? 8 : 16),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: currentPage < totalPages - 1 ? () => onPageChanged(currentPage + 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  DataColumn _buildTeacherSortableHeader(String title, String colKey, double width) {
    final isSorted = _teacherSortColumn == colKey;
    return DataColumn(
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              if (_teacherSortColumn == colKey) {
                _teacherSortAscending = !_teacherSortAscending;
              } else {
                _teacherSortColumn = colKey;
                _teacherSortAscending = true;
              }
              _teacherCurrentPage = 0;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  isSorted
                      ? (_teacherSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
                      : Icons.unfold_more_rounded,
                  size: isSorted ? 20 : 16,
                  color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataColumn _buildTeacherFilterAndSortHeader({
    required String title,
    required String colKey,
    required String? currentFilter,
    required List<String> options,
    required ValueChanged<String?> onSelected,
    required double width,
  }) {
    final isSorted = _teacherSortColumn == colKey;
    final hasFilter = currentFilter != null && currentFilter != options.first;

    return DataColumn(
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                setState(() {
                  if (_teacherSortColumn == colKey) {
                    _teacherSortAscending = !_teacherSortAscending;
                  } else {
                    _teacherSortColumn = colKey;
                    _teacherSortAscending = true;
                  }
                  _teacherCurrentPage = 0;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      isSorted
                          ? (_teacherSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
                          : Icons.unfold_more_rounded,
                      size: isSorted ? 20 : 16,
                      color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              tooltip: 'Filter $title',
              offset: const Offset(0, 32),
              color: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: hasFilter ? const Color(0xFFEEF2FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: hasFilter ? Border.all(color: const Color(0xFFC7D2FE)) : null,
                ),
                child: Icon(
                  Icons.filter_alt_rounded,
                  size: 14,
                  color: hasFilter ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                ),
              ),
              onSelected: (val) {
                onSelected(val == options.first ? null : val);
              },
              itemBuilder: (context) {
                return options.map((opt) {
                  final isSelected = (opt == currentFilter) || (opt == options.first && (currentFilter == null || currentFilter == options.first));
                  return PopupMenuItem<String>(
                    value: opt,
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          opt,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeachersTable(List<Teacher> teachers, List<Teacher> allTeachers) {
    final genderOptions = ['Semua Gender', 'Laki-laki', 'Perempuan'];

    final existingSubjects = allTeachers
        .expand((t) => t.subjects)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '-')
        .toSet()
        .toList()
      ..sort();
    final subjectOptions = ['Semua Mata Pelajaran', ...existingSubjects];

    final statusOptions = ['Semua Status', 'Aktif', 'Nonaktif'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _teacherTableHorizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 8,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: _teacherTableHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    columnSpacing: 14,
                    columns: [
                      _buildTeacherSortableHeader('Nama', 'nama', 180),
                      _buildTeacherSortableHeader('NIP', 'nip', 100),
                      _buildTeacherFilterAndSortHeader(
                        title: 'Gender',
                        colKey: 'gender',
                        currentFilter: _selectedTeacherGenderFilter,
                        options: genderOptions,
                        onSelected: (val) => setState(() {
                          _selectedTeacherGenderFilter = val;
                          _teacherCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildTeacherFilterAndSortHeader(
                        title: 'Mata Pelajaran',
                        colKey: 'subjects',
                        currentFilter: _selectedTeacherSubjectFilter,
                        options: subjectOptions,
                        onSelected: (val) => setState(() {
                          _selectedTeacherSubjectFilter = val;
                          _teacherCurrentPage = 0;
                        }),
                        width: 160,
                      ),
                      _buildTeacherSortableHeader('Kata Sandi', 'kata_sandi', 110),
                      _buildTeacherFilterAndSortHeader(
                        title: 'Status',
                        colKey: 'status',
                        currentFilter: _selectedTeacherStatusFilter,
                        options: statusOptions,
                        onSelected: (val) => setState(() {
                          _selectedTeacherStatusFilter = val;
                          _teacherCurrentPage = 0;
                        }),
                        width: 100,
                      ),
                      const DataColumn(
                        label: SizedBox(
                          width: 190,
                          child: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    rows: teachers.map((t) {
                      return DataRow(cells: [
                        DataCell(SizedBox(
                          width: 180,
                          child: Text(
                            t.displayName,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 100,
                          child: Text(
                            t.nip.isEmpty ? '-' : t.nip,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: Text(
                            t.gender == 'M' ? 'Laki-laki' : 'Perempuan',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 160,
                          child: Text(
                            t.subjects.isEmpty ? '-' : t.subjects.join(', '),
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: t.tempPassword != null && t.tempPassword!.isNotEmpty
                              ? SelectableText(
                                  t.tempPassword!,
                                  style: GoogleFonts.firaCode(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF0F172A), letterSpacing: 1.2),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => _generateSingleTeacherPasswordDirectly(t),
                                  icon: const Icon(Icons.vpn_key_rounded, size: 12),
                                  label: Text('Generate', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFF59E0B),
                                    side: const BorderSide(color: Color(0xFFF59E0B)),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                ),
                        )),
                        DataCell(SizedBox(
                          width: 100,
                          child: Tooltip(
                            message: 'Klik untuk ubah status',
                            child: InkWell(
                              onTap: () => _toggleTeacherStatus(t),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: t.disabled ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t.disabled ? 'Nonaktif' : 'Aktif',
                                      style: TextStyle(
                                        color: t.disabled ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (t.hasActiveSession) ...[
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: 'Sedang Login: ${t.activeDeviceName ?? 'Perangkat Lain'}',
                                        child: const Icon(Icons.devices_rounded, size: 13, color: Color(0xFF0284C7)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 190,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: Icon(
                                  Icons.phonelink_erase_rounded,
                                  color: t.hasActiveSession ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                                  size: 18,
                                ),
                                tooltip: t.hasActiveSession
                                    ? 'Reset Sesi Login Guru (${t.activeDeviceName ?? 'Aktif'})'
                                    : 'Reset Sesi Login Guru',
                                onPressed: () => _resetSingleTeacherSession(t),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 18),
                                tooltip: t.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                                onPressed: () => _resetPassword(t.id, t.displayName),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 18),
                                tooltip: 'Ubah Data',
                                onPressed: () => _showTeacherForm(teacher: t),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: Icon(
                                  t.disabled ? Icons.toggle_off_rounded : Icons.toggle_on_rounded,
                                  color: t.disabled ? const Color(0xFF94A3B8) : const Color(0xFF10B981),
                                  size: 22,
                                ),
                                tooltip: t.disabled ? 'Aktifkan Akun Guru' : 'Nonaktifkan Akun Guru',
                                onPressed: () => _toggleTeacherStatus(t),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                tooltip: 'Hapus Permanen',
                                onPressed: () => _deleteUser(t.id, t.displayName, t.nip),
                              ),
                            ],
                          ),
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = widget.isDesktop;

    return StreamBuilder<List<Teacher>>(
      initialData: _cachedTeachers,
      stream: _teachersStream ?? _adminUserService.streamTeachers(widget.schoolId),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedTeachers = snapshot.data;
        }
        if (snapshot.hasError && !snapshot.hasData) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const AppContentLoader(
            title: 'Memuat Data Guru...',
            subtitle: 'Mengambil daftar guru dari database',
          );
        }

        final allTeachers = snapshot.data ?? [];

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildQuotaWarningBanner(widget.schoolId),
              // Header & Buttons
              if (isDesktop) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daftar Guru',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kelola profil guru dan subjek mata pelajaran',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF4F46E5)),
                          onPressed: () => _showImportTeachersDialog(),
                          tooltip: 'Impor Guru dari Excel',
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                          onPressed: () => _exportTeachersExcel(allTeachers),
                          tooltip: 'Ekspor ke Excel',
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _resetAllTeacherSessions(allTeachers),
                          icon: const Icon(Icons.phonelink_erase_rounded, size: 16),
                          label: Text(
                            'Reset Sesi Massal',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _generateAllTeacherPasswords(allTeachers),
                          icon: const Icon(Icons.vpn_key_rounded, size: 16),
                          label: Text(
                            'Generate Sandi Massal',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showTeacherForm(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'Tambah Guru',
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
                  ],
                ),
              ] else ...[
                // Mobile layout header
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daftar Guru',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kelola profil guru dan mapel',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showTeacherForm(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'Tambah Guru',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFFEF4444), size: 20),
                            onPressed: () => _resetAllTeacherSessions(allTeachers),
                            tooltip: 'Reset Sesi Login Semua Guru',
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.vpn_key_rounded, color: Color(0xFFF59E0B), size: 20),
                            onPressed: () => _generateAllTeacherPasswords(allTeachers),
                            tooltip: 'Generate Sandi Massal',
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF4F46E5), size: 20),
                            onPressed: () => _showImportTeachersDialog(),
                            tooltip: 'Impor dari Excel',
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4), size: 20),
                            onPressed: () => _exportTeachersExcel(allTeachers),
                            tooltip: 'Ekspor ke Excel',
                          ),
                        ),
                      ],
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
                  controller: _searchController,
                  style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Cari berdasarkan nama atau NIP...',
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (val) {
                    _searchNotifier.value = val;
                    _teacherCurrentPage = 0;
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Content List
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: _searchNotifier,
                  builder: (context, query, _) {
                    final filteredTeachers = allTeachers.where((t) {
                      final q = query.trim().toLowerCase();
                      final matchesQuery = q.isEmpty ||
                          t.displayName.toLowerCase().contains(q) ||
                          t.nip.toLowerCase().contains(q) ||
                          t.subjects.any((s) => s.toLowerCase().contains(q));
                      if (!matchesQuery) return false;

                      if (_selectedTeacherGenderFilter != null && _selectedTeacherGenderFilter != 'Semua Gender') {
                        final genderStr = t.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                        if (genderStr != _selectedTeacherGenderFilter) return false;
                      }

                      if (_selectedTeacherSubjectFilter != null && _selectedTeacherSubjectFilter != 'Semua Mata Pelajaran') {
                        if (!t.subjects.contains(_selectedTeacherSubjectFilter)) return false;
                      }

                      if (_selectedTeacherStatusFilter != null && _selectedTeacherStatusFilter != 'Semua Status') {
                        final statusStr = t.disabled ? 'Nonaktif' : 'Aktif';
                        if (statusStr != _selectedTeacherStatusFilter) return false;
                      }

                      return true;
                    }).toList();

                    // Sort filtered teachers list
                    filteredTeachers.sort((a, b) {
                      int cmp = 0;
                      switch (_teacherSortColumn) {
                        case 'nama':
                          cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                          break;
                        case 'nip':
                          final nA = int.tryParse(a.nip);
                          final nB = int.tryParse(b.nip);
                          if (nA != null && nB != null) {
                            cmp = nA.compareTo(nB);
                          } else {
                            cmp = a.nip.compareTo(b.nip);
                          }
                          break;
                        case 'gender':
                          final gA = a.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                          final gB = b.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                          cmp = gA.compareTo(gB);
                          break;
                        case 'subjects':
                          final sA = a.subjects.join(', ').toLowerCase();
                          final sB = b.subjects.join(', ').toLowerCase();
                          cmp = sA.compareTo(sB);
                          break;
                        case 'kata_sandi':
                          cmp = (a.tempPassword ?? '').compareTo(b.tempPassword ?? '');
                          break;
                        case 'status':
                          final sA = a.disabled ? 'Nonaktif' : 'Aktif';
                          final sB = b.disabled ? 'Nonaktif' : 'Aktif';
                          cmp = sA.compareTo(sB);
                          break;
                        default:
                          cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                      }
                      return _teacherSortAscending ? cmp : -cmp;
                    });

                    final totalItems = filteredTeachers.length;
                    final totalPages = (totalItems / _teacherRowsPerPage).ceil();
                    final currentPage = (_teacherCurrentPage >= totalPages && totalPages > 0)
                        ? totalPages - 1
                        : _teacherCurrentPage;
                    final pageStart = currentPage * _teacherRowsPerPage;
                    final pageEnd = (pageStart + _teacherRowsPerPage < totalItems)
                        ? pageStart + _teacherRowsPerPage
                        : totalItems;
                    final paginatedTeachers = (pageStart < totalItems)
                        ? filteredTeachers.sublist(pageStart, pageEnd)
                        : <Teacher>[];

                    final hasActiveFilters = _selectedTeacherGenderFilter != null ||
                        _selectedTeacherSubjectFilter != null ||
                        _selectedTeacherStatusFilter != null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasActiveFilters)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Filter Aktif:',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                ),
                                if (_selectedTeacherGenderFilter != null)
                                  Chip(
                                    label: Text('Gender: $_selectedTeacherGenderFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                    backgroundColor: const Color(0xFFEEF2FF),
                                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                                    deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                    onDeleted: () => setState(() { _selectedTeacherGenderFilter = null; _teacherCurrentPage = 0; }),
                                  ),
                                if (_selectedTeacherSubjectFilter != null)
                                  Chip(
                                    label: Text('Mapel: $_selectedTeacherSubjectFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                    backgroundColor: const Color(0xFFEEF2FF),
                                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                                    deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                    onDeleted: () => setState(() { _selectedTeacherSubjectFilter = null; _teacherCurrentPage = 0; }),
                                  ),
                                if (_selectedTeacherStatusFilter != null)
                                  Chip(
                                    label: Text('Status: $_selectedTeacherStatusFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                    backgroundColor: const Color(0xFFEEF2FF),
                                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                                    deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                    onDeleted: () => setState(() { _selectedTeacherStatusFilter = null; _teacherCurrentPage = 0; }),
                                  ),
                                TextButton(
                                  onPressed: _clearFilters,
                                  child: Text('Reset Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: filteredTeachers.isEmpty
                              ? const Center(child: Text('Tidak ada data guru.'))
                              : _buildTeachersTable(paginatedTeachers, allTeachers),
                        ),
                        if (filteredTeachers.isNotEmpty)
                          _buildPaginationControls(
                            currentPage: currentPage,
                            rowsPerPage: _teacherRowsPerPage,
                            totalItems: totalItems,
                            onPageChanged: (page) => setState(() => _teacherCurrentPage = page),
                            onRowsPerPageChanged: (rows) => setState(() {
                              _teacherRowsPerPage = rows;
                              _teacherCurrentPage = 0;
                            }),
                          ),
                      ],
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
}
