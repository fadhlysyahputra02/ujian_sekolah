import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:excel/excel.dart' as ex;
import '../../../core/models/student.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/services/student_session_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../../../core/utils/file_saver.dart';
import '../widgets/student_form_dialog.dart';
import '../widgets/import_students_dialog.dart';
import '../widgets/generate_password_dialog.dart';
import '../widgets/select_angkatan_dialog.dart';

class AdminStudentListView extends StatefulWidget {
  final String schoolId;
  final bool isDesktop;

  const AdminStudentListView({
    super.key,
    required this.schoolId,
    required this.isDesktop,
  });

  @override
  State<AdminStudentListView> createState() => _AdminStudentListViewState();
}

class _AdminStudentListViewState extends State<AdminStudentListView> {
  final AdminUserService _adminUserService = AdminUserService();

  Stream<List<Map<String, dynamic>>>? _classesStream;
  Stream<List<Student>>? _studentsStream;
  List<Map<String, dynamic>>? _cachedClasses;
  List<Student>? _cachedStudents;

  // Search & Filter States
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  final ScrollController _studentTableHorizontalScrollController = ScrollController();

  String? _selectedClassFilter;
  String? _selectedGenderFilter;
  String? _selectedReligionFilter;
  String? _selectedAngkatanFilter;
  String? _selectedStatusFilter;

  // Pagination & Sorting States
  int _studentCurrentPage = 0;
  int _studentRowsPerPage = 10;
  String _studentSortColumn = 'nama';
  bool _studentSortAscending = true;

  @override
  void initState() {
    super.initState();
    _classesStream = _adminUserService.streamClasses(widget.schoolId);
    _studentsStream = _adminUserService.streamStudents(widget.schoolId);
  }

  @override
  void didUpdateWidget(AdminStudentListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId) {
      _refreshStudents();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchNotifier.dispose();
    _studentTableHorizontalScrollController.dispose();
    super.dispose();
  }

  void _refreshStudents() {
    setState(() {
      _cachedClasses = null;
      _cachedStudents = null;
      _classesStream = _adminUserService.streamClasses(widget.schoolId);
      _studentsStream = _adminUserService.streamStudents(widget.schoolId);
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _searchNotifier.value = '';
    setState(() {
      _studentCurrentPage = 0;
      _studentSortColumn = 'nama';
      _studentSortAscending = true;
      _selectedClassFilter = null;
      _selectedGenderFilter = null;
      _selectedReligionFilter = null;
      _selectedAngkatanFilter = null;
      _selectedStatusFilter = null;
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

  Future<void> _showStudentForm({Student? student}) async {
    if (student == null) {
      final sDoc = await FirebaseFirestore.instance.collection('schools').doc(widget.schoolId).get();
      if (sDoc.exists) {
        final sData = sDoc.data() ?? {};
        final studentCount = (sData['meta'] as Map?)?['studentCount'] ?? 0;
        final maxQuota = sData['maxStudentQuota'] ?? 500;
        if (studentCount >= maxQuota) {
          _showQuotaFullDialog('Murid', studentCount, maxQuota);
          return;
        }
      }
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StudentFormDialog(schoolId: widget.schoolId, student: student),
    );
    _refreshStudents();
  }

  Future<void> _showImportDialog() async {
    final sDoc = await FirebaseFirestore.instance.collection('schools').doc(widget.schoolId).get();
    if (sDoc.exists) {
      final sData = sDoc.data() ?? {};
      final studentCount = (sData['meta'] as Map?)?['studentCount'] ?? 0;
      final maxQuota = sData['maxStudentQuota'] ?? 500;
      if (studentCount >= maxQuota) {
        _showQuotaFullDialog('Murid', studentCount, maxQuota);
        return;
      }
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportStudentsDialog(schoolId: widget.schoolId),
    );
    _refreshStudents();
  }

  void _showGraduationDialog(List<Student> students) {
    showDialog(
      context: context,
      builder: (_) => SelectAngkatanDialog(
        schoolId: widget.schoolId,
        students: students,
      ),
    );
  }

  Future<void> _exportStudentsExcel(List<Student> students) async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow([
        ex.TextCellValue('NIS'),
        ex.TextCellValue('Nama Lengkap'),
        ex.TextCellValue('Jenis Kelamin'),
        ex.TextCellValue('Agama'),
        ex.TextCellValue('Angkatan'),
        ex.TextCellValue('Email'),
        ex.TextCellValue('Kata Sandi'),
        ex.TextCellValue('Status Akun'),
      ]);

      for (var s in students) {
        sheet.appendRow([
          ex.TextCellValue(s.nis),
          ex.TextCellValue(s.displayName),
          ex.TextCellValue(s.gender == 'M' ? 'Laki-laki (M)' : 'Perempuan (F)'),
          ex.TextCellValue(s.religion),
          ex.TextCellValue(s.angkatan),
          ex.TextCellValue(s.email ?? '-'),
          ex.TextCellValue(s.tempPassword ?? '-'),
          ex.TextCellValue(s.isInactive ? 'Nonaktif' : 'Aktif'),
        ]);
      }

      final fileBytes = excel.save(fileName: 'SesiCermat_Daftar_Murid.xlsx');
      if (fileBytes != null) {
        if (!kIsWeb) {
          await saveAndDownloadFile(fileBytes, 'SesiCermat_Daftar_Murid.xlsx');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Daftar murid berhasil diekspor ke Excel!')),
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

  Future<void> _generateAllPasswords(List<Student> students) async {
    if (students.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Informasi'),
          content: const Text('Tidak ada data murid aktif.'),
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

    final missingPasswords = students.where((s) => s.tempPassword == null || s.tempPassword!.trim().isEmpty).toList();
    final bool isAllHavePassword = missingPasswords.isEmpty;
    final List<Student> targets = isAllHavePassword ? students : missingPasswords;

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
                isAllHavePassword ? 'Reset Semua Sandi Murid' : 'Generate Sandi Massal',
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
                    'Semua murid aktif (${students.length} murid) sudah memiliki kata sandi.',
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
                            'Peringatan: Tindakan ini akan menimpa dan mengganti kata sandi SEMUA (${students.length}) murid aktif dengan kata sandi baru. Kata sandi sebelumnya tidak akan bisa digunakan lagi.',
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
                    'Apakah Anda yakin ingin melanjutkan reset kata sandi massal untuk semua murid?',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Text(
                'Ditemukan ${targets.length} murid yang belum memiliki kata sandi.\n\nApakah Anda yakin ingin membuat kata sandi sementara untuk ${targets.length} murid tersebut?',
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
                          'Memproses $processed dari ${targets.length} murid...',
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
        final s = targets[i];
        if (!mounted) break;

        progressNotifier.value = {
          'pct': i / targets.length,
          'name': s.displayName,
          'processed': i,
        };

        await _adminUserService.generateTempPassword(
          schoolId: widget.schoolId,
          collectionType: 'students',
          docId: s.id,
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
        _refreshStudents();
      }
    }
  }

  Future<void> _generateSinglePasswordDirectly(Student s) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempPassword = await _adminUserService.generateTempPassword(
        schoolId: widget.schoolId,
        collectionType: 'students',
        docId: s.id,
      );

      if (mounted) {
        Navigator.of(context).pop();
        _refreshStudents();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kata sandi berhasil dibuat untuk ${s.displayName}: $tempPassword'),
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

  Future<void> _resetAllStudentSessions(List<Student> students) async {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data murid.')),
      );
      return;
    }

    final activeSessionCount = students.where((s) => s.hasActiveSession).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF0284C7), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reset Semua Sesi Login?',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tindakan ini akan mengeluarkan (logout) perangkat login dari ALL (${students.length}) murid terdaftar.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF0284C7), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saat ini ada $activeSessionCount murid yang sedang terdeteksi aktif/login.',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0369A1)),
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
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ya, Reset Semua', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
      await StudentSessionService.resetAllStudentSessions(schoolId: widget.schoolId);
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        _refreshStudents();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil mereset semua sesi login murid! ($activeSessionCount perangkat dikeluarkan)'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mereset sesi massal: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _resetStudentSession(Student student) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF0284C7), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reset Sesi Login?',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apakah Anda yakin ingin mengeluarkan akun murid "${student.displayName}" (NIS: ${student.nis}) dari sesi login perangkat saat ini?',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), height: 1.4),
            ),
            if (student.hasActiveSession) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.devices_rounded, color: Color(0xFF0284C7), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Perangkat Aktif: ${student.activeDeviceName ?? 'Perangkat Lain'}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0369A1)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: Text('Ya, Reset Sesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
      final success = await StudentSessionService.resetSession(
        schoolId: widget.schoolId,
        studentId: student.id,
      );

      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        if (success) {
          _refreshStudents();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sesi login murid "${student.displayName}" berhasil di-reset!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Siswa tidak memiliki sesi aktif untuk di-reset.'),
              backgroundColor: Color(0xFFF59E0B),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mereset sesi: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _toggleStudentStatus(Student student) async {
    final bool currentlyInactive = student.isInactive;
    final String newStatus = currentlyInactive ? 'active' : 'inactive';
    final String actionText = currentlyInactive ? 'mengaktifkan' : 'menonaktifkan';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Konfirmasi Status Murid', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin $actionText murid "${student.displayName}" (NIS: ${student.nis})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyInactive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(currentlyInactive ? 'Aktifkan' : 'Non-aktifkan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminUserService.toggleStudentStatus(
        schoolId: widget.schoolId,
        studentId: student.id,
        newStatus: newStatus,
      );
      if (mounted) {
        _refreshStudents();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status murid "${student.displayName}" berhasil diubah menjadi ${newStatus == 'active' ? 'Aktif' : 'Non-aktif'}.'),
            backgroundColor: newStatus == 'active' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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
        collectionType: 'students',
        docId: docId,
      );

      if (mounted) {
        Navigator.of(context).pop();
        _refreshStudents();

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
        collectionType: 'students',
        docId: docId,
      );
      if (mounted) {
        _refreshStudents();
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

  DataColumn _buildSortableHeader(String title, String colKey, double width) {
    final isSorted = _studentSortColumn == colKey;
    return DataColumn(
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              if (_studentSortColumn == colKey) {
                _studentSortAscending = !_studentSortAscending;
              } else {
                _studentSortColumn = colKey;
                _studentSortAscending = true;
              }
              _studentCurrentPage = 0;
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
                      ? (_studentSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
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

  DataColumn _buildFilterAndSortHeader({
    required String title,
    required String colKey,
    required String? currentFilter,
    required List<String> options,
    required ValueChanged<String?> onSelected,
    required double width,
  }) {
    final isSorted = _studentSortColumn == colKey;
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
                  if (_studentSortColumn == colKey) {
                    _studentSortAscending = !_studentSortAscending;
                  } else {
                    _studentSortColumn = colKey;
                    _studentSortAscending = true;
                  }
                  _studentCurrentPage = 0;
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
                          ? (_studentSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
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
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF0F172A),
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

  Widget _buildStudentsTable(
    List<Student> students,
    Map<String, String> studentClassMap,
    List<Student> allStudents,
  ) {
    final classSet = studentClassMap.values.where((c) => c.isNotEmpty && c != '-').toSet().toList()..sort();
    final classOptions = ['Semua Kelas', ...classSet];

    final genderOptions = ['Semua Gender', 'Laki-laki', 'Perempuan'];

    final existingReligions = allStudents
        .map((s) => s.religion.trim())
        .where((r) => r.isNotEmpty && r != '-')
        .toSet()
        .toList()
      ..sort();
    final religionOptions = ['Semua Agama', ...existingReligions];

    final existingAngkatan = allStudents
        .map((s) => s.angkatan.trim())
        .where((a) => a.isNotEmpty && a != '-')
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final angkatanOptions = ['Semua Angkatan', ...existingAngkatan];

    final statusOptions = ['Semua Status', 'Aktif', 'Nonaktif'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _studentTableHorizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 8,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: _studentTableHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    columnSpacing: 14,
                    columns: [
                      _buildSortableHeader('Nama', 'nama', 200),
                      _buildSortableHeader('NIS', 'nis', 80),
                      _buildFilterAndSortHeader(
                        title: 'Kelas',
                        colKey: 'kelas',
                        currentFilter: _selectedClassFilter,
                        options: classOptions,
                        onSelected: (val) => setState(() {
                          _selectedClassFilter = val;
                          _studentCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildFilterAndSortHeader(
                        title: 'Gender',
                        colKey: 'gender',
                        currentFilter: _selectedGenderFilter,
                        options: genderOptions,
                        onSelected: (val) => setState(() {
                          _selectedGenderFilter = val;
                          _studentCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildFilterAndSortHeader(
                        title: 'Agama',
                        colKey: 'agama',
                        currentFilter: _selectedReligionFilter,
                        options: religionOptions,
                        onSelected: (val) => setState(() {
                          _selectedReligionFilter = val;
                          _studentCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildFilterAndSortHeader(
                        title: 'Angkatan',
                        colKey: 'angkatan',
                        currentFilter: _selectedAngkatanFilter,
                        options: angkatanOptions,
                        onSelected: (val) => setState(() {
                          _selectedAngkatanFilter = val;
                          _studentCurrentPage = 0;
                        }),
                        width: 125,
                      ),
                      _buildSortableHeader('Kata Sandi', 'kata_sandi', 110),
                      _buildFilterAndSortHeader(
                        title: 'Status',
                        colKey: 'status',
                        currentFilter: _selectedStatusFilter,
                        options: statusOptions,
                        onSelected: (val) => setState(() {
                          _selectedStatusFilter = val;
                          _studentCurrentPage = 0;
                        }),
                        width: 100,
                      ),
                      const DataColumn(
                        label: SizedBox(
                          width: 250,
                          child: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    rows: students.map((s) {
                      return DataRow(cells: [
                        DataCell(SizedBox(
                          width: 180,
                          child: Text(
                            s.displayName,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 80,
                          child: Text(
                            s.nis,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: Text(
                            studentClassMap[s.id] ?? '-',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: Text(
                            s.gender == 'M' ? 'Laki-laki' : 'Perempuan',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: Text(
                            s.religion,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 125,
                          child: Text(
                            s.angkatan,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: s.tempPassword != null && s.tempPassword!.isNotEmpty
                              ? SelectableText(
                                  s.tempPassword!,
                                  style: GoogleFonts.firaCode(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF0F172A), letterSpacing: 1.2),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => _generateSinglePasswordDirectly(s),
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
                              onTap: () => _toggleStudentStatus(s),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: s.isInactive ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      s.isInactive ? 'Nonaktif' : 'Aktif',
                                      style: TextStyle(
                                        color: s.isInactive ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (s.hasActiveSession) ...[
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: 'Sedang Login: ${s.activeDeviceName ?? 'Perangkat Lain'}',
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
                          width: 250,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: Icon(
                                    Icons.phonelink_erase_rounded,
                                    color: s.hasActiveSession ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                                    size: 18,
                                  ),
                                  tooltip: s.hasActiveSession
                                      ? 'Reset Sesi Login (Aktif: ${s.activeDeviceName ?? 'Perangkat Lain'})'
                                      : 'Reset Sesi Login Perangkat',
                                  onPressed: () => _resetStudentSession(s),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 18),
                                  tooltip: s.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                                  onPressed: () => _resetPassword(s.id, s.displayName),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 18),
                                  tooltip: 'Ubah Data',
                                  onPressed: () => _showStudentForm(student: s),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: Icon(
                                    s.isInactive ? Icons.toggle_off_rounded : Icons.toggle_on_rounded,
                                    color: s.isInactive ? const Color(0xFF94A3B8) : const Color(0xFF10B981),
                                    size: 24,
                                  ),
                                  tooltip: s.isInactive ? 'Aktifkan Akun Murid' : 'Nonaktifkan Akun Murid',
                                  onPressed: () => _toggleStudentStatus(s),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                  tooltip: 'Hapus Permanen',
                                  onPressed: () => _deleteUser(s.id, s.displayName, s.nis),
                                ),
                              ],
                            ),
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

    return StreamBuilder<List<Map<String, dynamic>>>(
      initialData: _cachedClasses,
      stream: _classesStream ?? _adminUserService.streamClasses(widget.schoolId),
      builder: (context, classesSnapshot) {
        if (classesSnapshot.hasData) {
          _cachedClasses = classesSnapshot.data;
        }
        final classes = classesSnapshot.data ?? [];
        final Map<String, String> studentClassMap = {};
        for (var c in classes) {
          final className = c['name'] as String? ?? '-';
          final studentIds = c['studentIds'];
          if (studentIds is List) {
            for (var id in studentIds) {
              studentClassMap[id.toString()] = className;
            }
          }
        }

        return StreamBuilder<List<Student>>(
          initialData: _cachedStudents,
          stream: _studentsStream ?? _adminUserService.streamStudents(widget.schoolId),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _cachedStudents = snapshot.data;
            }
            if (snapshot.hasError && !snapshot.hasData) return Center(child: Text('Error: ${snapshot.error}'));
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const AppContentLoader(
                title: 'Memuat Data Murid...',
                subtitle: 'Mengambil daftar murid dari database',
              );
            }

            final rawStudents = snapshot.data ?? [];
            final allStudents = rawStudents.where((s) => !s.isGraduated).toList();

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
                              'Daftar Murid',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kelola database murid dan data login siswa',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF4F46E5)),
                              onPressed: () => _showImportDialog(),
                              tooltip: 'Impor Massal Excel/CSV',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                              onPressed: () => _exportStudentsExcel(allStudents),
                              tooltip: 'Ekspor ke Excel',
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _resetAllStudentSessions(allStudents),
                              icon: const Icon(Icons.phonelink_erase_rounded, size: 16, color: Color(0xFF0284C7)),
                              label: Text(
                                'Reset Semua Sesi',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFBAE6FD)),
                                backgroundColor: const Color(0xFFF0F9FF),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _generateAllPasswords(allStudents),
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
                              onPressed: () => _showGraduationDialog(allStudents),
                              icon: const Icon(Icons.school_rounded, size: 16),
                              label: Text(
                                'Luluskan',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showStudentForm(),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(
                                'Tambah Murid',
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
                          'Daftar Murid',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kelola database murid dan data login siswa',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showStudentForm(),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(
                                'Tambah Murid',
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
                            ElevatedButton.icon(
                              onPressed: () => _showGraduationDialog(allStudents),
                              icon: const Icon(Icons.school_rounded, size: 16),
                              label: Text(
                                'Luluskan',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF0284C7), size: 20),
                                onPressed: () => _resetAllStudentSessions(allStudents),
                                tooltip: 'Reset Semua Sesi',
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
                                onPressed: () => _generateAllPasswords(allStudents),
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
                                onPressed: () => _showImportDialog(),
                                tooltip: 'Impor Massal',
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
                                onPressed: () => _exportStudentsExcel(allStudents),
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
                        hintText: 'Cari berdasarkan nama, NIS, kelas, atau agama...',
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
                        _studentCurrentPage = 0;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Content List
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _searchNotifier,
                      builder: (context, query, _) {
                        final filteredStudents = allStudents.where((s) {
                          final q = query.trim().toLowerCase();
                          final studentClass = studentClassMap[s.id]?.toLowerCase() ?? '';
                          final matchesQuery = q.isEmpty ||
                              s.displayName.toLowerCase().contains(q) ||
                              s.nis.toLowerCase().contains(q) ||
                              studentClass.contains(q) ||
                              s.religion.toLowerCase().contains(q);
                          if (!matchesQuery) return false;

                          if (_selectedClassFilter != null && _selectedClassFilter != 'Semua Kelas') {
                            if (studentClassMap[s.id] != _selectedClassFilter) return false;
                          }

                          if (_selectedGenderFilter != null && _selectedGenderFilter != 'Semua Gender') {
                            final genderStr = s.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                            if (genderStr != _selectedGenderFilter) return false;
                          }

                          if (_selectedReligionFilter != null && _selectedReligionFilter != 'Semua Agama') {
                            if (s.religion != _selectedReligionFilter) return false;
                          }

                          if (_selectedAngkatanFilter != null && _selectedAngkatanFilter != 'Semua Angkatan') {
                            if (s.angkatan != _selectedAngkatanFilter) return false;
                          }

                          if (_selectedStatusFilter != null && _selectedStatusFilter != 'Semua Status') {
                            final statusStr = s.isInactive ? 'Nonaktif' : 'Aktif';
                            if (statusStr != _selectedStatusFilter) return false;
                          }

                          return true;
                        }).toList();

                        // Sort filtered students list
                        filteredStudents.sort((a, b) {
                          int cmp = 0;
                          switch (_studentSortColumn) {
                            case 'nama':
                              cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                              break;
                            case 'nis':
                              final nA = int.tryParse(a.nis);
                              final nB = int.tryParse(b.nis);
                              if (nA != null && nB != null) {
                                cmp = nA.compareTo(nB);
                              } else {
                                cmp = a.nis.compareTo(b.nis);
                              }
                              break;
                            case 'kelas':
                              final cA = (studentClassMap[a.id] ?? '').toLowerCase();
                              final cB = (studentClassMap[b.id] ?? '').toLowerCase();
                              cmp = cA.compareTo(cB);
                              break;
                            case 'gender':
                              final gA = a.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                              final gB = b.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                              cmp = gA.compareTo(gB);
                              break;
                            case 'agama':
                              cmp = a.religion.toLowerCase().compareTo(b.religion.toLowerCase());
                              break;
                            case 'angkatan':
                              cmp = b.angkatan.compareTo(a.angkatan);
                              break;
                            case 'kata_sandi':
                              cmp = (a.tempPassword ?? '').compareTo(b.tempPassword ?? '');
                              break;
                            case 'status':
                              final sA = a.isInactive ? 'Nonaktif' : 'Aktif';
                              final sB = b.isInactive ? 'Nonaktif' : 'Aktif';
                              cmp = sA.compareTo(sB);
                              break;
                            default:
                              cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                          }
                          return _studentSortAscending ? cmp : -cmp;
                        });

                        final totalItems = filteredStudents.length;
                        final totalPages = (totalItems / _studentRowsPerPage).ceil();
                        final currentPage = (_studentCurrentPage >= totalPages && totalPages > 0)
                            ? totalPages - 1
                            : _studentCurrentPage;
                        final pageStart = currentPage * _studentRowsPerPage;
                        final pageEnd = (pageStart + _studentRowsPerPage < totalItems)
                            ? pageStart + _studentRowsPerPage
                            : totalItems;
                        final paginatedStudents = (pageStart < totalItems)
                            ? filteredStudents.sublist(pageStart, pageEnd)
                            : <Student>[];

                        final hasActiveFilters = _selectedClassFilter != null ||
                            _selectedGenderFilter != null ||
                            _selectedReligionFilter != null ||
                            _selectedAngkatanFilter != null ||
                            _selectedStatusFilter != null;

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
                                    if (_selectedClassFilter != null)
                                      Chip(
                                        label: Text('Kelas: $_selectedClassFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedClassFilter = null; _studentCurrentPage = 0; }),
                                      ),
                                    if (_selectedGenderFilter != null)
                                      Chip(
                                        label: Text('Gender: $_selectedGenderFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedGenderFilter = null; _studentCurrentPage = 0; }),
                                      ),
                                    if (_selectedReligionFilter != null)
                                      Chip(
                                        label: Text('Agama: $_selectedReligionFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedReligionFilter = null; _studentCurrentPage = 0; }),
                                      ),
                                    if (_selectedAngkatanFilter != null)
                                      Chip(
                                        label: Text('Angkatan: $_selectedAngkatanFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAngkatanFilter = null; _studentCurrentPage = 0; }),
                                      ),
                                    if (_selectedStatusFilter != null)
                                      Chip(
                                        label: Text('Status: $_selectedStatusFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedStatusFilter = null; _studentCurrentPage = 0; }),
                                      ),
                                    TextButton(
                                      onPressed: _clearFilters,
                                      child: Text('Reset Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: filteredStudents.isEmpty
                                  ? const Center(child: Text('Tidak ada data murid.'))
                                  : _buildStudentsTable(paginatedStudents, studentClassMap, allStudents),
                            ),
                            if (filteredStudents.isNotEmpty)
                              _buildPaginationControls(
                                currentPage: currentPage,
                                rowsPerPage: _studentRowsPerPage,
                                totalItems: totalItems,
                                onPageChanged: (page) => setState(() => _studentCurrentPage = page),
                                onRowsPerPageChanged: (rows) => setState(() {
                                  _studentRowsPerPage = rows;
                                  _studentCurrentPage = 0;
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
      },
    );
  }
}
