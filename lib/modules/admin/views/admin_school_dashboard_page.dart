import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:excel/excel.dart' as ex;
import '../../../core/models/student.dart';
import '../../../core/models/teacher.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/file_saver.dart';
import '../widgets/teacher_form_dialog.dart';
import '../widgets/student_form_dialog.dart';
import '../widgets/subject_form_dialog.dart';
import '../widgets/import_students_dialog.dart';
import '../widgets/import_teachers_dialog.dart';
import '../widgets/generate_password_dialog.dart';
import '../widgets/class_form_dialog.dart';
import 'class_detail_screen.dart';
import 'event_list_screen.dart';

class AdminSchoolDashboardPage extends StatefulWidget {
  final String? tabName;
  const AdminSchoolDashboardPage({super.key, this.tabName});

  @override
  State<AdminSchoolDashboardPage> createState() => _AdminSchoolDashboardPageState();
}

class _AdminSchoolDashboardPageState extends State<AdminSchoolDashboardPage> {
  int _currentTab = 0; // 0: Overview, 1: Guru, 2: Murid, 3: Mapel, 4: Kelas, 5: Event, 6: Pengaturan
  
  @override
  void initState() {
    super.initState();
    _updateTabFromWidget();
  }

  @override
  void didUpdateWidget(AdminSchoolDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabName != oldWidget.tabName) {
      _updateTabFromWidget();
    }
  }

  void _updateTabFromWidget() {
    setState(() {
      switch (widget.tabName) {
        case 'ringkasan': _currentTab = 0; break;
        case 'guru': _currentTab = 1; break;
        case 'murid': _currentTab = 2; break;
        case 'mapel': _currentTab = 3; break;
        case 'kelas': _currentTab = 4; break;
        case 'eventujian': _currentTab = 5; break;
        case 'pengaturan': _currentTab = 6; break;
        default: _currentTab = 0;
      }
    });
  }

  void _navigateToTab(int index) {
    String path;
    switch (index) {
      case 0: path = 'ringkasan'; break;
      case 1: path = 'guru'; break;
      case 2: path = 'murid'; break;
      case 3: path = 'mapel'; break;
      case 4: path = 'kelas'; break;
      case 5: path = 'eventujian'; break;
      case 6: path = 'pengaturan'; break;
      default: path = 'ringkasan';
    }
    context.go('/admin/$path');
  }
  
  final AdminUserService _adminUserService = AdminUserService();

  // Pagination states
  int _teacherRowsPerPage = 10;
  int _teacherCurrentPage = 0;

  int _studentRowsPerPage = 10;
  int _studentCurrentPage = 0;

  void _refreshTeachers(String schoolId) {
    if (schoolId.isNotEmpty) {
      setState(() {
        _teacherCurrentPage = 0;
      });
    }
  }

  void _refreshStudents(String schoolId) {
    if (schoolId.isNotEmpty) {
      setState(() {
        _studentCurrentPage = 0;
      });
    }
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

  // Search & Filter States
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _teacherCurrentPage = 0;
      _studentCurrentPage = 0;
    });
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
        ex.TextCellValue('Sandi Sementara'),
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

  Future<void> _exportStudentsExcel(List<Student> students) async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow([
        ex.TextCellValue('NIS'),
        ex.TextCellValue('Nama Lengkap'),
        ex.TextCellValue('Jenis Kelamin'),
        ex.TextCellValue('Angkatan'),
        ex.TextCellValue('Email'),
        ex.TextCellValue('Sandi Sementara'),
        ex.TextCellValue('Status Akun'),
      ]);

      for (var s in students) {
        sheet.appendRow([
          ex.TextCellValue(s.nis),
          ex.TextCellValue(s.displayName),
          ex.TextCellValue(s.gender == 'M' ? 'Laki-laki (M)' : 'Perempuan (F)'),
          ex.TextCellValue(s.angkatan),
          ex.TextCellValue(s.email ?? '-'),
          ex.TextCellValue(s.tempPassword ?? '-'),
          ex.TextCellValue(s.disabled ? 'Nonaktif' : 'Aktif'),
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

  Future<void> _resetPassword(String schoolId, String collectionType, String docId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buat Ulang Kata Sandi'),
        content: Text('Apakah Anda yakin ingin mengatur ulang kata sandi untuk $displayName? Sistem akan menghasilkan kata sandi baru secara acak.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            child: const Text('Ya, Reset'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    // Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempPassword = await _adminUserService.generateTempPassword(
        schoolId: schoolId,
        collectionType: collectionType,
        docId: docId,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Dismiss loading indicator
        
        if (collectionType == 'teachers') {
          _refreshTeachers(schoolId);
        } else {
          _refreshStudents(schoolId);
        }

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
        Navigator.of(context).pop(); // Dismiss loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mereset kata sandi: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _generateAllPasswords(String schoolId, List<Student> students) async {
    final targets = students.where((s) => s.tempPassword == null || s.tempPassword!.isEmpty).toList();

    if (targets.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Informasi'),
          content: const Text('Semua murid dalam list ini sudah memiliki kata sandi.'),
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
              child: const Icon(Icons.key_rounded, color: Color(0xFFD97706), size: 24),
            ),
            const SizedBox(width: 14),
            Text(
              'Generate Sandi Massal',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin membuat kata sandi sementara untuk ${targets.length} murid yang belum memilikinya?',
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
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(
              'Mulai Generate',
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
          schoolId: schoolId,
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
        _refreshStudents(schoolId);
      }
    }
  }

  Future<void> _generateSinglePasswordDirectly(String schoolId, Student s) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempPassword = await _adminUserService.generateTempPassword(
        schoolId: schoolId,
        collectionType: 'students',
        docId: s.id,
      );

      if (mounted) {
        Navigator.of(context).pop();
        _refreshStudents(schoolId);
        
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

  Future<void> _generateAllTeacherPasswords(String schoolId, List<Teacher> teachers) async {
    final targets = teachers.where((t) => t.tempPassword == null || t.tempPassword!.isEmpty).toList();

    if (targets.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Informasi'),
          content: const Text('Semua guru dalam list ini sudah memiliki kata sandi.'),
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
              child: const Icon(Icons.key_rounded, color: Color(0xFFD97706), size: 24),
            ),
            const SizedBox(width: 14),
            Text(
              'Generate Sandi Massal',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin membuat kata sandi sementara untuk ${targets.length} guru yang belum memilikinya?',
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
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(
              'Mulai Generate',
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
          schoolId: schoolId,
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
        _refreshTeachers(schoolId);
      }
    }
  }

  Future<void> _generateSingleTeacherPasswordDirectly(String schoolId, Teacher t) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempPassword = await _adminUserService.generateTempPassword(
        schoolId: schoolId,
        collectionType: 'teachers',
        docId: t.id,
      );

      if (mounted) {
        Navigator.of(context).pop();
        _refreshTeachers(schoolId);
        
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

  Future<void> _deleteUser(String schoolId, String collectionType, String docId, String name, String identifier) async {
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
        schoolId: schoolId,
        collectionType: collectionType,
        docId: docId,
      );
      if (mounted) {
        if (collectionType == 'teachers') {
          _refreshTeachers(schoolId);
        } else {
          _refreshStudents(schoolId);
        }
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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final role = authService.role;
    if (role != 'school_admin' && role != 'super_admin') {
      return const Scaffold(
        body: Center(
          child: Text('Akses Ditolak: Anda tidak memiliki wewenang administrator.'),
        ),
      );
    }
    final schoolId = authService.schoolId ?? '';
    if (schoolId.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
          ),
        ),
      );
    }
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    final bottomNavItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard_rounded), label: 'Ringkasan'),
      const BottomNavigationBarItem(icon: Icon(Icons.assignment_ind_outlined), activeIcon: Icon(Icons.assignment_ind_rounded), label: 'Guru'),
      const BottomNavigationBarItem(icon: Icon(Icons.school_outlined), activeIcon: Icon(Icons.school_rounded), label: 'Murid'),
      const BottomNavigationBarItem(icon: Icon(Icons.book_outlined), activeIcon: Icon(Icons.book_rounded), label: 'Mapel'),
      const BottomNavigationBarItem(icon: Icon(Icons.class_outlined), activeIcon: Icon(Icons.class_rounded), label: 'Kelas'),
      const BottomNavigationBarItem(icon: Icon(Icons.event_note_outlined), activeIcon: Icon(Icons.event_note_rounded), label: 'Ujian'),
      const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings_rounded), label: 'Pengaturan'),
    ];

    final backgroundGradient = const BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(0xFFF8FAFC),
          Color(0xFFEFF6FF),
          Color(0xFFE2E8F0),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('schools').doc(schoolId).snapshots(),
      builder: (context, schoolSnapshot) {
        final schoolData = schoolSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final schoolName = schoolData['name'] as String? ?? 'SesiCermat';

        if (isDesktop) {
          // Desktop Layout
          return Scaffold(
            body: Row(
              children: [
                // Custom Premium Sidebar
                Container(
                  width: size.width > 1150 ? 260 : 80,
                  color: const Color(0xFF0F172A), // Slate 900
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                      // Sidebar Header Logo
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: size.width > 1150 ? MainAxisAlignment.start : MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Color(0xFF818CF8),
                                size: 24,
                              ),
                            ),
                            if (size.width > 1150) ...[
                              const SizedBox(width: 12),
                              const Text(
                                'SesiCermat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Sidebar Items
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _buildSidebarItem(0, Icons.dashboard_outlined, Icons.dashboard_rounded, 'Ringkasan', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(1, Icons.assignment_ind_outlined, Icons.assignment_ind_rounded, 'Manajemen Guru', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(2, Icons.school_outlined, Icons.school_rounded, 'Manajemen Murid', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(3, Icons.book_outlined, Icons.book_rounded, 'Mata Pelajaran', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(4, Icons.class_outlined, Icons.class_rounded, 'Manajemen Kelas', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(5, Icons.event_note_outlined, Icons.event_note_rounded, 'Event Ujian', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(6, Icons.settings_outlined, Icons.settings_rounded, 'Pengaturan', size.width > 1150),
                          ],
                        ),
                      ),
                      // Sidebar Footer
                      const Divider(color: Color(0xFF1E293B), indent: 16, endIndent: 16),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: InkWell(
                          onTap: () => authService.signOut(),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            child: Row(
                              mainAxisAlignment: size.width > 1150 ? MainAxisAlignment.start : MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 20),
                                if (size.width > 1150) ...[
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Keluar',
                                    style: TextStyle(
                                      color: Color(0xFFF87171),
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: backgroundGradient,
                    child: _buildTabContent(schoolId, isDesktop, authService),
                  ),
                )
              ],
            ),
          );
        } else {
          // Mobile Layout
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0F172A), // Slate 900 (Biru Gelap)
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schoolName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _currentTab == 0
                        ? 'Ringkasan'
                        : _currentTab == 1
                            ? 'Manajemen Guru'
                            : _currentTab == 2
                                ? 'Manajemen Murid'
                                : _currentTab == 3
                                    ? 'Mata Pelajaran'
                                    : _currentTab == 4
                                        ? 'Manajemen Kelas'
                                        : _currentTab == 5
                                            ? 'Event Ujian'
                                            : 'Pengaturan Akun',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.indigo[200],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: InkWell(
                    onTap: () => authService.signOut(),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Keluar',
                            style: TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (idx) {
              _clearFilters();
              _navigateToTab(idx);
            },
            backgroundColor: const Color(0xFF0F172A), // Slate 900 (Biru Gelap)
            selectedItemColor: const Color(0xFF818CF8),
            unselectedItemColor: const Color(0xFF94A3B8),
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: bottomNavItems,
          ),
        ),
        body: Container(
          decoration: backgroundGradient,
          child: _buildTabContent(schoolId, isDesktop, authService),
        ),
      );
    }
  },
);
}

  Widget _buildSidebarItem(int tabIndex, IconData outlineIcon, IconData solidIcon, String label, bool isExtended) {
    final isActive = _currentTab == tabIndex;
    return InkWell(
      onTap: () {
        _clearFilters();
        _navigateToTab(tabIndex);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? solidIcon : outlineIcon,
              color: isActive ? const Color(0xFF818CF8) : const Color(0xFF94A3B8),
              size: 20,
            ),
            if (isExtended) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(String schoolId, bool isDesktop, AuthService authService) {
    switch (_currentTab) {
      case 0:
        return _buildOverviewTab(schoolId);
      case 1:
        return _buildTeachersTab(schoolId, isDesktop);
      case 2:
        return _buildStudentsTab(schoolId, isDesktop);
      case 3:
        return _buildSubjectsTab(schoolId, isDesktop);
      case 4:
        return _buildClassesTab(schoolId, isDesktop);
      case 5:
        return EventListScreen(schoolId: schoolId);
      case 6:
        return _buildSettingsTab(authService);
      default:
        return const Center(child: Text('Konten Tidak Ditemukan'));
    }
  }

  Widget _buildClassesTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _adminUserService.streamClasses(schoolId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final classes = snapshot.data ?? [];
        final filteredClasses = classes.where((c) {
          final query = _searchQuery.toLowerCase();
          final name = (c['name'] ?? '').toString().toLowerCase();
          return name.contains(query);
        }).toList();

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
                          'Manajemen Kelas',
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
                      'Manajemen Kelas',
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
                  controller: _searchController,
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
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(height: 20),

              // ── Content ──
              if (filteredClasses.isEmpty)
                Expanded(
                  child: Center(
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
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ClassDetailScreen(schoolId: schoolId, classData: cls),
                            ),
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
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClassDetailScreen(schoolId: schoolId, classData: cls),
          ),
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

  Widget _buildOverviewTab(String schoolId) {
    final size = MediaQuery.of(context).size;
    final isDesktopWidth = size.width > 600;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('schools').doc(schoolId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final schoolData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final schoolName = schoolData['name'] ?? 'Sekolah';
        final schoolCode = schoolData['code'] ?? '';
        final adminEmail = schoolData['adminEmail'] ?? '';
        final meta = schoolData['meta'] as Map<String, dynamic>? ?? {};
        final teacherCount = meta['teacherCount'] ?? 0;
        final studentCount = meta['studentCount'] ?? 0;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncStats(schoolId, meta);
        });

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktopWidth ? 32.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDesktopWidth) ...[
                Text(
                  'Ringkasan Portal',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$schoolName • Kode: $schoolCode • Admin: $adminEmail',
                  style: TextStyle(
                    fontSize: isDesktopWidth ? 13 : 11,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else ...[
                // Premium Banner for Mobile
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF818CF8).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              color: Color(0xFF818CF8),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'PORTAL SEKOLAH',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF818CF8),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        schoolName,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.key_rounded, size: 12, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Text(
                                  'Kode: $schoolCode',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.admin_panel_settings_rounded, size: 12, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    adminEmail,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              
              if (isDesktopWidth)
                Row(
                  children: [
                    Expanded(child: _buildDashboardCard('Total Guru', '$teacherCount', Icons.assignment_ind_rounded, const Color(0xFF4F46E5), true)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildDashboardCard('Total Murid', '$studentCount', Icons.school_rounded, const Color(0xFF06B6D4), true)),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: _buildDashboardCard('Total Guru', '$teacherCount', Icons.assignment_ind_rounded, const Color(0xFF4F46E5), false)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDashboardCard('Total Murid', '$studentCount', Icons.school_rounded, const Color(0xFF06B6D4), false)),
                  ],
                ),
              const SizedBox(height: 28),
              Text(
                'Aktivitas Cepat',
                style: TextStyle(
                  fontSize: isDesktopWidth ? 16 : 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              if (isDesktopWidth)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildQuickActionBtn('Tambah Guru', Icons.person_add_alt_1_rounded, () => _navigateToTab(1)),
                    _buildQuickActionBtn('Tambah Murid', Icons.group_add_rounded, () => _navigateToTab(2)),
                    _buildQuickActionBtn('Kelola Mapel', Icons.book_rounded, () => _navigateToTab(3)),
                    _buildQuickActionBtn('Impor Siswa Massal', Icons.cloud_upload_rounded, () => _showImportDialog(schoolId)),
                  ],
                )
              else
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: [
                    _buildQuickActionCard(
                      label: 'Tambah Guru',
                      description: 'Registrasi guru',
                      icon: Icons.person_add_alt_1_rounded,
                      color: const Color(0xFF4F46E5),
                      onTap: () => _navigateToTab(1),
                    ),
                    _buildQuickActionCard(
                      label: 'Tambah Murid',
                      description: 'Registrasi murid',
                      icon: Icons.group_add_rounded,
                      color: const Color(0xFF06B6D4),
                      onTap: () => _navigateToTab(2),
                    ),
                    _buildQuickActionCard(
                      label: 'Kelola Mapel',
                      description: 'Daftar pelajaran',
                      icon: Icons.book_rounded,
                      color: const Color(0xFFF59E0B),
                      onTap: () => _navigateToTab(3),
                    ),
                    _buildQuickActionCard(
                      label: 'Impor Siswa',
                      description: 'Unggah dari Excel',
                      icon: Icons.cloud_upload_rounded,
                      color: const Color(0xFF10B981),
                      onTap: () => _showImportDialog(schoolId),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeachersTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Teacher>>(
      stream: _adminUserService.streamTeachers(schoolId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
 
        final allTeachers = snapshot.data ?? [];
        final filteredTeachers = allTeachers.where((t) {
          final query = _searchQuery.toLowerCase();
          return t.displayName.toLowerCase().contains(query) || t.nip.contains(query);
        }).toList();

        // Slice for pagination
        final totalItems = filteredTeachers.length;
        final totalPages = (totalItems / _teacherRowsPerPage).ceil();
        if (_teacherCurrentPage >= totalPages && totalPages > 0) {
          _teacherCurrentPage = totalPages - 1;
        }
        final pageStart = _teacherCurrentPage * _teacherRowsPerPage;
        final pageEnd = (pageStart + _teacherRowsPerPage < totalItems) ? pageStart + _teacherRowsPerPage : totalItems;
        final paginatedTeachers = (pageStart < totalItems) ? filteredTeachers.sublist(pageStart, pageEnd) : <Teacher>[];
 
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
                          onPressed: () => _showImportTeachersDialog(schoolId),
                          tooltip: 'Impor Guru dari Excel',
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                          onPressed: () => _exportTeachersExcel(filteredTeachers),
                          tooltip: 'Ekspor ke Excel',
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _generateAllTeacherPasswords(schoolId, filteredTeachers),
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
                          onPressed: () => _showTeacherForm(schoolId),
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
                          onPressed: () => _showTeacherForm(schoolId),
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
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.vpn_key_rounded, color: Color(0xFFF59E0B), size: 20),
                            onPressed: () => _generateAllTeacherPasswords(schoolId, filteredTeachers),
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
                            onPressed: () => _showImportTeachersDialog(schoolId),
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
                            onPressed: () => _exportTeachersExcel(filteredTeachers),
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
                  onChanged: (val) => setState(() {
                    _searchQuery = val;
                    _teacherCurrentPage = 0; // Reset page on filter
                  }),
                ),
              ),
              const SizedBox(height: 20),
 
              // Content List
              Expanded(
                child: filteredTeachers.isEmpty
                    ? const Center(child: Text('Tidak ada data guru.'))
                    : _buildTeachersTable(schoolId, paginatedTeachers),
              ),
              if (filteredTeachers.isNotEmpty)
                _buildPaginationControls(
                  currentPage: _teacherCurrentPage,
                  rowsPerPage: _teacherRowsPerPage,
                  totalItems: totalItems,
                  onPageChanged: (page) => setState(() => _teacherCurrentPage = page),
                  onRowsPerPageChanged: (rows) => setState(() {
                    _teacherRowsPerPage = rows;
                    _teacherCurrentPage = 0;
                  }),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeachersTable(String schoolId, List<Teacher> teachers) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Nama', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('NIP', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Gender', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Mata Pelajaran', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Sandi Sementara', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: teachers.map((t) {
            return DataRow(cells: [
              DataCell(Text(t.displayName)),
              DataCell(Text(t.nip)),
              DataCell(Text(t.gender == 'M' ? 'Laki-laki' : 'Perempuan')),
              DataCell(Text(t.subjects.isEmpty ? '-' : t.subjects.join(', '))),
              DataCell(t.tempPassword != null && t.tempPassword!.isNotEmpty
                  ? SelectableText(
                      t.tempPassword!,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _generateSingleTeacherPasswordDirectly(schoolId, t),
                      icon: const Icon(Icons.vpn_key_rounded, size: 12),
                      label: Text('Generate', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    )),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: t.disabled ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  t.disabled ? 'Nonaktif' : 'Aktif',
                  style: TextStyle(color: t.disabled ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              )),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 20),
                    tooltip: t.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                    onPressed: () => _resetPassword(schoolId, 'teachers', t.id, t.displayName),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 20),
                    tooltip: 'Ubah Data',
                    onPressed: () => _showTeacherForm(schoolId, teacher: t),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    tooltip: 'Hapus Permanen',
                    onPressed: () => _deleteUser(schoolId, 'teachers', t.id, t.displayName, t.nip),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
        ),
      ),
    );
  }

  Widget _buildStudentsTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _adminUserService.streamClasses(schoolId),
      builder: (context, classesSnapshot) {
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
          stream: _adminUserService.streamStudents(schoolId),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

            final allStudents = snapshot.data ?? [];
            final filteredStudents = allStudents.where((s) {
              final query = _searchQuery.toLowerCase();
              return s.displayName.toLowerCase().contains(query) || s.nis.contains(query);
            }).toList();

            // Slice for pagination
            final totalItems = filteredStudents.length;
            final totalPages = (totalItems / _studentRowsPerPage).ceil();
            if (_studentCurrentPage >= totalPages && totalPages > 0) {
              _studentCurrentPage = totalPages - 1;
            }
            final pageStart = _studentCurrentPage * _studentRowsPerPage;
            final pageEnd = (pageStart + _studentRowsPerPage < totalItems) ? pageStart + _studentRowsPerPage : totalItems;
            final paginatedStudents = (pageStart < totalItems) ? filteredStudents.sublist(pageStart, pageEnd) : <Student>[];

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
                              onPressed: () => _showImportDialog(schoolId),
                              tooltip: 'Impor Massal Excel/CSV',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                              onPressed: () => _exportStudentsExcel(filteredStudents),
                              tooltip: 'Ekspor ke Excel',
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _generateAllPasswords(schoolId, filteredStudents),
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
                              onPressed: () => _showStudentForm(schoolId),
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
                          'Kelola database murid & login',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showStudentForm(schoolId),
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
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.vpn_key_rounded, color: Color(0xFFF59E0B), size: 20),
                                onPressed: () => _generateAllPasswords(schoolId, filteredStudents),
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
                                onPressed: () => _showImportDialog(schoolId),
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
                                onPressed: () => _exportStudentsExcel(filteredStudents),
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
                        hintText: 'Cari berdasarkan nama atau NIS...',
                        hintStyle: GoogleFonts.inter(
                          color: const Color(0xFF94A3B8),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (val) => setState(() {
                        _searchQuery = val;
                        _studentCurrentPage = 0; // Reset page on filter
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Content List
                  Expanded(
                    child: filteredStudents.isEmpty
                        ? const Center(child: Text('Tidak ada data murid.'))
                        : _buildStudentsTable(schoolId, paginatedStudents, studentClassMap),
                  ),
                  if (filteredStudents.isNotEmpty)
                    _buildPaginationControls(
                      currentPage: _studentCurrentPage,
                      rowsPerPage: _studentRowsPerPage,
                      totalItems: totalItems,
                      onPageChanged: (page) => setState(() => _studentCurrentPage = page),
                      onRowsPerPageChanged: (rows) => setState(() {
                        _studentRowsPerPage = rows;
                        _studentCurrentPage = 0;
                      }),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStudentsTable(String schoolId, List<Student> students, Map<String, String> studentClassMap) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Nama', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('NIS', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Kelas', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Gender', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Angkatan', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Sandi Sementara', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: students.map((s) {
            return DataRow(cells: [
              DataCell(Text(s.displayName)),
              DataCell(Text(s.nis)),
              DataCell(Text(studentClassMap[s.id] ?? '-')),
              DataCell(Text(s.gender == 'M' ? 'Laki-laki' : 'Perempuan')),
              DataCell(Text(s.angkatan)),
               DataCell(s.tempPassword != null && s.tempPassword!.isNotEmpty
                  ? SelectableText(
                      s.tempPassword!,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _generateSinglePasswordDirectly(schoolId, s),
                      icon: const Icon(Icons.vpn_key_rounded, size: 12),
                      label: Text('Generate', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    )),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: s.disabled ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  s.disabled ? 'Nonaktif' : 'Aktif',
                  style: TextStyle(color: s.disabled ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              )),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 20),
                    tooltip: s.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                    onPressed: () => _resetPassword(schoolId, 'students', s.id, s.displayName),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 20),
                    tooltip: 'Ubah Data',
                    onPressed: () => _showStudentForm(schoolId, student: s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    tooltip: 'Hapus Permanen',
                    onPressed: () => _deleteUser(schoolId, 'students', s.id, s.displayName, s.nis),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard(String title, String count, IconData icon, Color color, bool isDesktopWidth) {
    if (isDesktopWidth) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    count,
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              count,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildQuickActionBtn(String label, IconData icon, VoidCallback onTap, {bool isCompact = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20, vertical: isCompact ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: isCompact ? MainAxisAlignment.center : MainAxisAlignment.start,
          mainAxisSize: isCompact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, size: isCompact ? 16 : 18, color: const Color(0xFF4F46E5)),
            SizedBox(width: isCompact ? 8 : 10),
            Expanded(
              flex: isCompact ? 1 : 0,
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: isCompact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required String label,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const Spacer(),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTeacherForm(String schoolId, {Teacher? teacher}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TeacherFormDialog(schoolId: schoolId, teacher: teacher),
    );
    _refreshTeachers(schoolId);
  }

  Future<void> _showStudentForm(String schoolId, {Student? student}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StudentFormDialog(schoolId: schoolId, student: student),
    );
    _refreshStudents(schoolId);
  }

  void _showSubjectForm(String schoolId, {Map<String, dynamic>? subject}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SubjectFormDialog(schoolId: schoolId, subject: subject),
    );
  }

  Future<void> _showImportDialog(String schoolId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportStudentsDialog(schoolId: schoolId),
    );
    _refreshStudents(schoolId);
  }

  Future<void> _showImportTeachersDialog(String schoolId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportTeachersDialog(schoolId: schoolId),
    );
    _refreshTeachers(schoolId);
  }

  Widget _buildSubjectsTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _adminUserService.streamSubjects(schoolId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final allSubjects = snapshot.data ?? [];
        final filteredSubjects = allSubjects.where((sub) {
          final query = _searchQuery.toLowerCase();
          final name = (sub['name'] ?? '').toString().toLowerCase();
          final code = (sub['code'] ?? '').toString().toLowerCase();
          return name.contains(query) || code.contains(query);
        }).toList();

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
                  controller: _searchController,
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
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(height: 20),

              // Content List
              Expanded(
                child: filteredSubjects.isEmpty
                    ? const Center(child: Text('Tidak ada data mata pelajaran.'))
                    : isDesktop
                        ? _buildSubjectsTable(schoolId, filteredSubjects)
                        : _buildSubjectsMobileList(schoolId, filteredSubjects),
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

  Widget _buildSettingsTab(AuthService authService) {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isSaving = false;

    final userEmail = authService.user?.email ?? '';
    final initialLetter = userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'A';

    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Text(
                'Pengaturan Akun',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Kelola detail profil dan keamanan kata sandi akun Anda.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 28),

              // Responsive Layout Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 850;
                  
                  final profileCard = Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Color(0xFF4F46E5), Color(0xFF818CF8)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  initialLetter,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userEmail,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFFE0E7FF)),
                                    ),
                                    child: Text(
                                      'Admin Sekolah',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF4F46E5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Divider(color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          Icons.verified_user_rounded,
                          'Status Akun',
                          'Aktif',
                          const Color(0xFF10B981),
                        ),
                        const SizedBox(height: 14),
                        _buildInfoRow(
                          Icons.security_rounded,
                          'Keamanan Sesi',
                          'Tinggi',
                          const Color(0xFF3B82F6),
                        ),
                        const SizedBox(height: 14),
                        _buildInfoRow(
                          Icons.calendar_today_rounded,
                          'Tanggal Akses',
                          DateTime.now().toString().split(' ')[0],
                          const Color(0xFF64748B),
                        ),
                      ],
                    ),
                  );

                  final changePasswordCard = Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.lock_rounded,
                                  color: Color(0xFF7C3AED),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Ubah Kata Sandi',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: passwordController,
                            obscureText: obscurePassword,
                            style: GoogleFonts.inter(fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Kata Sandi Baru',
                              labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                              hintText: 'Minimal 6 karakter',
                              hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20, color: Color(0xFF94A3B8)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 20,
                                  color: const Color(0xFF64748B),
                                ),
                                onPressed: () => setState(() => obscurePassword = !obscurePassword),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Kata sandi baru tidak boleh kosong';
                              }
                              if (value.trim().length < 6) {
                                return 'Kata sandi minimal 6 karakter';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: confirmController,
                            obscureText: obscureConfirm,
                            style: GoogleFonts.inter(fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Konfirmasi Kata Sandi Baru',
                              labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                              hintText: 'Ulangi kata sandi baru',
                              hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 20, color: Color(0xFF94A3B8)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 20,
                                  color: const Color(0xFF64748B),
                                ),
                                onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Konfirmasi kata sandi tidak boleh kosong';
                              }
                              if (value != passwordController.text) {
                                return 'Konfirmasi kata sandi tidak cocok';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (formKey.currentState!.validate()) {
                                        setState(() => isSaving = true);
                                        try {
                                          await authService.changeOwnPassword(
                                            passwordController.text.trim(),
                                          );
                                          passwordController.clear();
                                          confirmController.clear();
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Row(
                                                  children: [
                                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Kata sandi berhasil diperbarui.',
                                                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ),
                                                backgroundColor: const Color(0xFF10B981),
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Row(
                                                  children: [
                                                    const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Gagal mengubah kata sandi: $e',
                                                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ),
                                                backgroundColor: const Color(0xFFEF4444),
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            );
                                          }
                                        } finally {
                                          setState(() => isSaving = false);
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      'Simpan Perubahan',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: profileCard),
                        const SizedBox(width: 24),
                        Expanded(flex: 4, child: changePasswordCard),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        profileCard,
                        const SizedBox(height: 24),
                        changePasswordCard,
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color badgeColor) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: badgeColor,
            ),
          ),
        ),
      ],
    );
  }
}
