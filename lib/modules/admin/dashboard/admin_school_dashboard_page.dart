import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:excel/excel.dart' as ex;
import '../../../core/models/student.dart';
import '../../../core/models/teacher.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/student_session_service.dart';
import '../../../core/constants/app_version.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../../../core/utils/file_saver.dart';
import '../widgets/teacher_form_dialog.dart';
import '../widgets/student_form_dialog.dart';
import '../widgets/subject_form_dialog.dart';
import '../widgets/import_students_dialog.dart';
import '../widgets/import_teachers_dialog.dart';
import '../widgets/report_bug_dialog.dart';
import '../widgets/generate_password_dialog.dart';
import '../widgets/class_form_dialog.dart';
import '../widgets/select_angkatan_dialog.dart';
import '../events/event_list_screen.dart';
import '../teachers/admin_teacher_list_view.dart';
import '../students/admin_student_list_view.dart';
import '../alumni/admin_alumni_list_view.dart';
import '../subjects/admin_subject_list_view.dart';
import '../classes/admin_class_list_view.dart';
import '../settings/admin_settings_view.dart';

class AdminSchoolDashboardPage extends StatefulWidget {
  final String? tabName;
  const AdminSchoolDashboardPage({super.key, this.tabName});

  @override
  State<AdminSchoolDashboardPage> createState() => _AdminSchoolDashboardPageState();
}

class _AdminSchoolDashboardPageState extends State<AdminSchoolDashboardPage> {
  int _currentTab = 0; // 0: Overview, 1: Guru, 2: Murid, 3: Alumni, 4: Mapel, 5: Kelas, 6: Event, 7: Pengaturan
  DateTime? _lastBackPressTime;
  
  @override
  void initState() {
    super.initState();
    _updateTabFromWidget();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndShowUpdateDialog(context);
      }
    });
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
        case 'alumni': _currentTab = 3; break;
        case 'mapel': _currentTab = 4; break;
        case 'kelas': _currentTab = 5; break;
        case 'eventujian': _currentTab = 6; break;
        case 'pengaturan': _currentTab = 7; break;
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
      case 3: path = 'alumni'; break;
      case 4: path = 'mapel'; break;
      case 5: path = 'kelas'; break;
      case 6: path = 'eventujian'; break;
      case 7: path = 'pengaturan'; break;
      default: path = 'ringkasan';
    }
    context.go('/admin/$path');
  }
  
  final AdminUserService _adminUserService = AdminUserService();

  // Cached streams to prevent rebuilding/flickering and losing focus on mobile keyboard resize
  Stream<List<Teacher>>? _teachersStream;
  Stream<List<Student>>? _studentsStream;
  Stream<List<Map<String, dynamic>>>? _classesStream;
  Stream<List<Map<String, dynamic>>>? _subjectsStream;
  String? _initializedSchoolId;

  // Cached data in memory so tabs render immediately without waiting spinners upon tab switching
  DocumentSnapshot? _cachedSchoolSnapshot;
  List<Map<String, dynamic>>? _cachedClasses;
  List<Map<String, dynamic>>? _cachedSubjects;
  List<Teacher>? _cachedTeachers;
  List<Student>? _cachedStudents;

  void _initStreams(String schoolId) {
    if (_initializedSchoolId == schoolId && _teachersStream != null) return;
    _initializedSchoolId = schoolId;
    _teachersStream = _adminUserService.streamTeachers(schoolId);
    _studentsStream = _adminUserService.streamStudents(schoolId);
    _classesStream = _adminUserService.streamClasses(schoolId);
    _subjectsStream = _adminUserService.streamSubjects(schoolId);
  }

  // Pagination states
  int _teacherRowsPerPage = 10;
  int _teacherCurrentPage = 0;
  String _teacherSortColumn = 'nama';
  bool _teacherSortAscending = true;
  String? _selectedTeacherGenderFilter;
  String? _selectedTeacherSubjectFilter;
  String? _selectedTeacherStatusFilter;

  int _studentRowsPerPage = 10;
  int _studentCurrentPage = 0;
  String _studentSortColumn = 'nama';
  bool _studentSortAscending = true;
  String? _selectedClassFilter;
  String? _selectedGenderFilter;
  String? _selectedReligionFilter;
  String? _selectedAngkatanFilter;
  String? _selectedStatusFilter;

  // Alumni Pagination & Filter states
  int _alumniRowsPerPage = 10;
  int _alumniCurrentPage = 0;
  String _alumniSortColumn = 'nama';
  bool _alumniSortAscending = true;
  String? _selectedAlumniClassFilter;
  String? _selectedAlumniGenderFilter;
  String? _selectedAlumniReligionFilter;
  String? _selectedAlumniAngkatanFilter;

  void _refreshTeachers(String schoolId) {
    if (schoolId.isNotEmpty) {
      setState(() {
        _teacherCurrentPage = 0;
        _teachersStream = _adminUserService.streamTeachers(schoolId);
      });
    }
  }

  void _refreshStudents(String schoolId) {
    if (schoolId.isNotEmpty) {
      setState(() {
        _studentCurrentPage = 0;
        _studentsStream = _adminUserService.streamStudents(schoolId);
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
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  final ScrollController _teacherTableHorizontalScrollController = ScrollController();
  final ScrollController _studentTableHorizontalScrollController = ScrollController();

  final TextEditingController _alumniSearchController = TextEditingController();
  final ValueNotifier<String> _alumniSearchNotifier = ValueNotifier('');
  final ScrollController _alumniTableHorizontalScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _searchNotifier.dispose();
    _teacherTableHorizontalScrollController.dispose();
    _studentTableHorizontalScrollController.dispose();
    _alumniSearchController.dispose();
    _alumniSearchNotifier.dispose();
    _alumniTableHorizontalScrollController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _searchController.clear();
    _searchNotifier.value = '';
    _alumniSearchController.clear();
    _alumniSearchNotifier.value = '';
    setState(() {
      _teacherCurrentPage = 0;
      _studentCurrentPage = 0;
      _alumniCurrentPage = 0;
      _teacherSortColumn = 'nama';
      _teacherSortAscending = true;
      _selectedTeacherGenderFilter = null;
      _selectedTeacherSubjectFilter = null;
      _selectedTeacherStatusFilter = null;
      _selectedClassFilter = null;
      _selectedGenderFilter = null;
      _selectedReligionFilter = null;
      _selectedAngkatanFilter = null;
      _selectedStatusFilter = null;
      _selectedAlumniClassFilter = null;
      _selectedAlumniGenderFilter = null;
      _selectedAlumniReligionFilter = null;
      _selectedAlumniAngkatanFilter = null;
      _studentSortColumn = 'nama';
      _studentSortAscending = true;
      _alumniSortColumn = 'nama';
      _alumniSortAscending = true;
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

  Future<void> _syncMissingStudentsReligion(String schoolId) async {
    try {
      final studentsSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;
      int totalUpdated = 0;

      for (var doc in studentsSnap.docs) {
        final data = doc.data();
        final hasReligion = data.containsKey('religion') && data['religion'] != null && data['religion'].toString().isNotEmpty;
        final hasAgama = data.containsKey('agama') && data['agama'] != null && data['agama'].toString().isNotEmpty;

        if (!hasReligion || !hasAgama) {
          final rel = (data['religion'] ?? data['agama'] ?? 'Islam').toString().trim();
          final finalRel = rel.isEmpty ? 'Islam' : rel;
          batch.update(doc.reference, {
            'religion': finalRel,
            'agama': finalRel,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          count++;
          totalUpdated++;

          if (count >= 400) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            count = 0;
          }
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      if (mounted) {
        if (totalUpdated > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Berhasil memperbarui atribut Agama untuk $totalUpdated murid di database!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Semua murid sudah memiliki atribut Agama lengkap di database.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui agama murid: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _resetPassword(String schoolId, String collectionType, String docId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
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
    if (students.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Informasi'),
          content: const Text('Tidak ada data murid.'),
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
                    'Semua murid (${students.length} murid) sudah memiliki kata sandi.',
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
                            'Peringatan: Tindakan ini akan menimpa dan mengganti kata sandi SEMUA (${students.length}) murid dengan kata sandi baru. Kata sandi sebelumnya tidak akan bisa digunakan lagi.',
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

  Future<void> _resetAllStudentSessions(String schoolId, List<Student> students) async {
    if (students.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Informasi'),
          content: const Text('Tidak ada data murid.'),
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
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF0284C7), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reset Sesi Semua Murid',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin mereset seluruh sesi login murid (${students.length} murid) dari 0?\n\nSemua sesi login di perangkat/browser aktif saat ini akan dikosongkan sehingga seluruh murid dapat login kembali dari perangkat mana pun.',
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.5, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text('Ya, Reset Semua Sesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sedang mereset sesi semua murid dari 0...'),
        backgroundColor: Color(0xFF0284C7),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      int count = 0;
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final s in students) {
        final ref = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(s.id);
        batch.update(ref, {'activeSession': null, 'updatedAt': FieldValue.serverTimestamp()});
        count++;
        if (count % 400 == 0) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
        }
      }
      await batch.commit();

      // Panggil Cloud Function juga untuk konsistensi
      await StudentSessionService.resetAllStudentSessions(schoolId: schoolId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil mereset seluruh sesi login untuk ${students.length} murid dari 0.'),
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
            content: Text('Gagal mereset sesi massal: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _generateAllTeacherPasswords(String schoolId, List<Teacher> teachers) async {
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

  Future<void> _toggleStudentStatus(String schoolId, Student student) async {
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
        schoolId: schoolId,
        studentId: student.id,
        newStatus: newStatus,
      );
      if (mounted) {
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

  Future<void> _toggleTeacherStatus(String schoolId, Teacher teacher) async {
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
        final schoolDoc = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
        final maxQuota = (schoolDoc.data()?['maxTeacherQuota'] as num?)?.toInt() ?? 50;
        final teachersSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('teachers')
            .get();
        final activeCount = teachersSnap.docs.where((d) => d.data()['archived'] != true && d.data()['disabled'] != true).length;
        if (activeCount >= maxQuota) {
          throw Exception('Kuota guru aktif telah mencapai batas maksimal ($maxQuota). Non-aktifkan guru lain terlebih dahulu.');
        }
      }

      final schoolRef = FirebaseFirestore.instance.collection('schools').doc(schoolId);
      await schoolRef.collection('teachers').doc(teacher.id).update({
        'disabled': newDisabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final teachersSnap = await schoolRef.collection('teachers').get();
      final activeCount = teachersSnap.docs.where((d) => d.data()['archived'] != true && d.data()['disabled'] != true).length;
      await schoolRef.update({
        'meta.teacherCount': activeCount,
      });

      _refreshTeachers(schoolId);

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

  Future<void> _resetStudentSession(String schoolId, Student student) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF0284C7)),
            const SizedBox(width: 10),
            Text('Reset Sesi Login?', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sesi login siswa "${student.displayName}" di perangkat aktif saat ini akan diakhiri. Siswa dapat login kembali di perangkat baru.',
              style: GoogleFonts.inter(fontSize: 13.5, height: 1.45, color: const Color(0xFF334155)),
            ),
            if (student.hasActiveSession) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.devices_rounded, size: 16, color: Color(0xFF0284C7)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Perangkat aktif: ${student.activeDeviceName ?? 'Perangkat Lain'}',
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
            child: Text('Batal', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text('Ya, Reset Sesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await StudentSessionService.resetSession(
        schoolId: schoolId,
        studentId: student.id,
        studentNis: student.nis,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Sesi login siswa "${student.displayName}" berhasil direset.'
                  : 'Gagal mereset sesi login siswa.',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _openReportBugDialog(String schoolId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
      final data = doc.data() ?? {};
      final name = data['name'] ?? 'Sekolah';
      final code = data['npsn'] ?? data['code'] ?? '-';
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => ReportBugDialog(
          schoolId: schoolId,
          schoolName: name,
          schoolCode: code,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => ReportBugDialog(
          schoolId: schoolId,
          schoolName: 'Sekolah',
          schoolCode: '-',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    if (authService.isLoading) {
      return const AppSplashScreen(
        title: 'SesiCermat Admin',
        subtitle: 'Memuat sesi administrator...',
      );
    }
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
      return const AppSplashScreen(
        title: 'SesiCermat Admin',
        subtitle: 'Memuat profil sekolah administrator...',
      );
    }
    _initStreams(schoolId);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    final bottomNavItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard_rounded), label: 'Ringkasan'),
      const BottomNavigationBarItem(icon: Icon(Icons.assignment_ind_outlined), activeIcon: Icon(Icons.assignment_ind_rounded), label: 'Guru'),
      const BottomNavigationBarItem(icon: Icon(Icons.school_outlined), activeIcon: Icon(Icons.school_rounded), label: 'Murid'),
      const BottomNavigationBarItem(icon: Icon(Icons.workspace_premium_outlined), activeIcon: Icon(Icons.workspace_premium_rounded), label: 'Alumni'),
      const BottomNavigationBarItem(icon: Icon(Icons.book_outlined), activeIcon: Icon(Icons.book_rounded), label: 'Mapel'),
      const BottomNavigationBarItem(icon: Icon(Icons.class_outlined), activeIcon: Icon(Icons.class_rounded), label: 'Kelas'),
      const BottomNavigationBarItem(icon: Icon(Icons.event_note_outlined), activeIcon: Icon(Icons.event_note_rounded), label: 'Ujian'),
      const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings_rounded), label: 'Setelan'),
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

    final Widget mainWidget;
    if (isDesktop) {
      // Desktop Layout
      mainWidget = Scaffold(
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
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/images/Logo_SesiCermat.png',
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
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
                            _buildSidebarItem(3, Icons.workspace_premium_outlined, Icons.workspace_premium_rounded, 'Alumni', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(4, Icons.book_outlined, Icons.book_rounded, 'Mata Pelajaran', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(5, Icons.class_outlined, Icons.class_rounded, 'Kelas', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(6, Icons.event_note_outlined, Icons.event_note_rounded, 'Event Ujian', size.width > 1150),
                            const SizedBox(height: 8),
                            _buildSidebarItem(7, Icons.settings_outlined, Icons.settings_rounded, 'Pengaturan', size.width > 1150),
                          ],
                        ),
                      ),
                      // Sidebar Footer
                      const Divider(color: Color(0xFF1E293B), indent: 16, endIndent: 16),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => authService.confirmAndSignOut(context),
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
                            const SizedBox(height: 4),
                            Text(
                              AppVersion.version,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
            floatingActionButton: _currentTab == 7
                ? FloatingActionButton.extended(
                    onPressed: () => _openReportBugDialog(schoolId),
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    elevation: 6,
                    highlightElevation: 10,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    icon: const Icon(Icons.bug_report_rounded, size: 20),
                    label: Text(
                      'Laporkan Bug',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  )
                : null,
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          );
        } else {
          // Mobile Layout
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0F172A), // Slate 900 (Biru Gelap)
              elevation: 0,
              title: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/images/Logo_SesiCermat.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: Color(0xFF818CF8), size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'SesiCermat',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12.0, top: 4.0, bottom: 4.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => authService.confirmAndSignOut(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Keluar',
                                style: TextStyle(
                                  color: Color(0xFFF87171),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppVersion.version,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
            selectedFontSize: 10,
            unselectedFontSize: 10,
            iconSize: 20,
            selectedLabelStyle: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w500),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: bottomNavItems,
          ),
        ),
        body: Container(
          decoration: backgroundGradient,
          child: _buildTabContent(schoolId, isDesktop, authService),
        ),
        floatingActionButton: _currentTab == 7
            ? FloatingActionButton.extended(
                onPressed: () => _openReportBugDialog(schoolId),
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                elevation: 6,
                highlightElevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                icon: const Icon(Icons.bug_report_rounded, size: 20),
                label: Text(
                  'Laporkan Bug',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_currentTab != 0) {
          _clearFilters();
          _navigateToTab(0);
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Tekan kembali lagi untuk keluar aplikasi',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF1E293B),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: mainWidget,
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
        return AdminTeacherListView(schoolId: schoolId, isDesktop: isDesktop);
      case 2:
        return AdminStudentListView(schoolId: schoolId, isDesktop: isDesktop);
      case 3:
        return AdminAlumniListView(schoolId: schoolId, isDesktop: isDesktop);
      case 4:
        return AdminSubjectListView(schoolId: schoolId, isDesktop: isDesktop);
      case 5:
        return AdminClassListView(schoolId: schoolId, isDesktop: isDesktop);
      case 6:
        return EventListScreen(schoolId: schoolId);
      case 7:
        return AdminSettingsView(schoolId: schoolId);
      default:
        return const Center(child: Text('Konten Tidak Ditemukan'));
    }
  }

  Widget _buildOverviewTab(String schoolId) {
    return StreamBuilder<DocumentSnapshot>(
      initialData: _cachedSchoolSnapshot,
      stream: FirebaseFirestore.instance.collection('schools').doc(schoolId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedSchoolSnapshot = snapshot.data;
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const AppContentLoader(
            title: 'Memuat Ringkasan...',
            subtitle: 'Mengambil statistik profil sekolah',
          );
        }

        final schoolData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final schoolName = schoolData['name'] ?? 'Sekolah';
        final logoUrl = schoolData['logoUrl'] as String?;
        final meta = schoolData['meta'] as Map<String, dynamic>? ?? {};
        final teacherCount = meta['teacherCount'] ?? 0;
        final studentCount = meta['studentCount'] ?? 0;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncStats(schoolId, meta);
        });

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 768;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                padding: EdgeInsets.all(isDesktop ? 28.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildQuotaWarningBanner(schoolId),
                    // 1. HERO HEADER BANNER (DYNAMIC ANIMATED FEATURE HIGHLIGHTS)
                    _HeroAnimatedFeatureBanner(
                      schoolName: schoolName,
                      logoUrl: logoUrl,
                      isDesktop: isDesktop,
                    ),
                    const SizedBox(height: 28),

                    // 2. RINGKASAN KPI CARDS
                    _buildSectionHeader('Ringkasan Statistik', 'Statistik real-time pengguna dan data sekolah.'),
                    const SizedBox(height: 14),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _subjectsStream ?? _adminUserService.streamSubjects(schoolId),
                      builder: (context, subjectsSnap) {
                        final realSubjectCount = subjectsSnap.hasData ? subjectsSnap.data!.length : ((schoolData['subjects'] as List?)?.length ?? 0);

                        return StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _classesStream ?? _adminUserService.streamClasses(schoolId),
                          builder: (context, classesSnap) {
                            final realClassCount = classesSnap.hasData ? classesSnap.data!.length : ((schoolData['classes'] as List?)?.length ?? 0);

                            return LayoutBuilder(
                              builder: (context, gridConstraints) {
                                final gridWidth = gridConstraints.maxWidth;
                                final crossCount = isDesktop ? 4 : (gridWidth > 550 ? 4 : 2);
                                final isMobileGrid = gridWidth <= 550 || !isDesktop;

                                return GridView.count(
                                  crossAxisCount: crossCount,
                                  crossAxisSpacing: isMobileGrid ? 10 : (gridWidth < 1000 ? 12 : 16),
                                  mainAxisSpacing: isMobileGrid ? 10 : (gridWidth < 1000 ? 12 : 16),
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: isDesktop
                                      ? (gridWidth > 1100 ? 1.35 : (gridWidth > 800 ? 1.25 : 1.15))
                                      : (gridWidth > 550 ? 1.3 : 1.28),
                                  children: [
                                    _buildEleganceKpiCard(
                                      title: 'Total Guru',
                                      count: '$teacherCount',
                                      subtitle: 'Tenaga Pengajar Aktif',
                                      icon: Icons.assignment_ind_rounded,
                                      color: const Color(0xFF4F46E5),
                                      gradientColors: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
                                      onTap: () => _navigateToTab(1),
                                    ),
                                    _buildEleganceKpiCard(
                                      title: 'Total Murid',
                                      count: '$studentCount',
                                      subtitle: 'Siswa Terdaftar CBT',
                                      icon: Icons.school_rounded,
                                      color: const Color(0xFF06B6D4),
                                      gradientColors: const [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
                                      onTap: () => _navigateToTab(2),
                                    ),
                                    _buildEleganceKpiCard(
                                      title: 'Mata Pelajaran',
                                      count: '$realSubjectCount',
                                      subtitle: 'Mapel Kurikulum',
                                      icon: Icons.menu_book_rounded,
                                      color: const Color(0xFF10B981),
                                      gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
                                      onTap: () => _navigateToTab(3),
                                    ),
                                    _buildEleganceKpiCard(
                                      title: 'Kelas',
                                      count: '$realClassCount',
                                      subtitle: 'Rombongan Belajar',
                                      icon: Icons.class_rounded,
                                      color: const Color(0xFF8B5CF6),
                                      gradientColors: const [Color(0xFF8B5CF6), Color(0xFFA855F7)],
                                      onTap: () => _navigateToTab(4),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // 3. AKTIVITAS CEPAT (QUICK ACTIONS)
                    _buildSectionHeader('Aktivitas Cepat', 'Akses instan ke menu pengolahan data utama.'),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, actConstraints) {
                        final actWidth = actConstraints.maxWidth;
                        final actCrossCount = isDesktop ? 4 : (actWidth > 550 ? 4 : 2);
                        final isMobileAct = actWidth <= 550 || !isDesktop;

                        return GridView.count(
                          crossAxisCount: actCrossCount,
                          crossAxisSpacing: isMobileAct ? 10 : (actWidth < 1000 ? 10 : 14),
                          mainAxisSpacing: isMobileAct ? 10 : (actWidth < 1000 ? 10 : 14),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: isDesktop
                              ? (actWidth > 1100 ? 1.55 : (actWidth > 800 ? 1.35 : 1.2))
                              : (actWidth > 550 ? 1.5 : 1.42),
                          children: [
                            _buildEleganceActionCard(
                              title: 'Tambah Guru Baru',
                              desc: 'Registrasi pengajar',
                              icon: Icons.person_add_alt_1_rounded,
                              color: const Color(0xFF4F46E5),
                              gradientColors: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
                              onTap: () => _navigateToTab(1),
                            ),
                            _buildEleganceActionCard(
                              title: 'Tambah Murid Baru',
                              desc: 'Input data siswa',
                              icon: Icons.group_add_rounded,
                              color: const Color(0xFF06B6D4),
                              gradientColors: const [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
                              onTap: () => _navigateToTab(2),
                            ),
                            _buildEleganceActionCard(
                              title: 'Kelola Mapel',
                              desc: 'Atur mata pelajaran',
                              icon: Icons.menu_book_rounded,
                              color: const Color(0xFF10B981),
                              gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
                              onTap: () => _navigateToTab(3),
                            ),
                            _buildEleganceActionCard(
                              title: 'Impor Massal',
                              desc: 'Unggah berkas Excel',
                              icon: Icons.cloud_upload_rounded,
                              color: const Color(0xFF8B5CF6),
                              gradientColors: const [Color(0xFF8B5CF6), Color(0xFFA855F7)],
                              onTap: () => _showImportDialog(schoolId),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // 4. BANNER PUSAT EVENT UJIAN SEMESTER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: isDesktop
                          ? Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 32),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pusat Pembuatan & Pelaksanaan Event Ujian',
                                        style: GoogleFonts.inter(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Kelola jadwal ujian, denah alokasi tempat duduk murid, dan penugasan pengawas dalam wizard 7-langkah.',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                ElevatedButton.icon(
                                  onPressed: () => _navigateToTab(5),
                                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                                  label: const Text('Kelola Event Ujian'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4F46E5),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Pusat Event Ujian Semester',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Kelola jadwal ujian, denah tempat duduk, dan pengawas ruangan.',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _navigateToTab(5),
                                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                    label: const Text('Kelola Event Ujian'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4F46E5),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildEleganceKpiCard({
    required String title,
    required String count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return _EleganceKpiCardWidget(
      title: title,
      count: count,
      subtitle: subtitle,
      icon: icon,
      color: color,
      gradientColors: gradientColors,
      onTap: onTap,
    );
  }

  Widget _buildEleganceActionCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return _EleganceActionCardWidget(
      title: title,
      desc: desc,
      icon: icon,
      color: color,
      gradientColors: gradientColors,
      onTap: onTap,
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

  Future<void> _showImportDialog(String schoolId) async {
    final sDoc = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
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
      builder: (context) => ImportStudentsDialog(schoolId: schoolId),
    );
  }

  Widget _buildModernTile({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String value,
    bool isCode = false,
    Color? badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isCode ? FontWeight.w800 : FontWeight.w600,
                    color: isCode ? const Color(0xFF0891B2) : const Color(0xFF0F172A),
                    letterSpacing: isCode ? 1.0 : 0.0,
                  ),
                ),
              ],
            ),
          ),
          if (badgeColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogoImage(String logoUrl) {
    if (logoUrl.startsWith('data:image/')) {
      try {
        final base64Data = logoUrl.split(',').last;
        final bytes = base64Decode(base64Data);
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (e) {
        debugPrint('Error decoding base64 logo: $e');
      }
    }
    return Image.network(
      logoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
      ),
    );
  }

}

class _EleganceKpiCardWidget extends StatefulWidget {
  final String title;
  final String count;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _EleganceKpiCardWidget({
    required this.title,
    required this.count,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<_EleganceKpiCardWidget> createState() => _EleganceKpiCardWidgetState();
}

class _EleganceKpiCardWidgetState extends State<_EleganceKpiCardWidget> {
  bool _isHovered = false;

  @override
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final cardWidth = cardConstraints.maxWidth;
        final isCompact = cardWidth < 210;

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0),
              padding: EdgeInsets.all(isMobile ? 12 : (isCompact ? 12 : 18)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 16 : (isCompact ? 16 : 22)),
                border: Border.all(
                  color: _isHovered ? widget.color.withValues(alpha: 0.4) : widget.color.withValues(alpha: 0.12),
                  width: _isHovered ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isHovered ? widget.color.withValues(alpha: 0.18) : widget.color.withValues(alpha: 0.05),
                    blurRadius: _isHovered ? 24 : 14,
                    offset: Offset(0, _isHovered ? 8 : 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 8 : (isCompact ? 8 : 12)),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: widget.gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(isMobile ? 10 : (isCompact ? 10 : 14)),
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: isMobile ? 18 : (isCompact ? 18 : 22)),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.all(isMobile ? 6 : (isCompact ? 6 : 8)),
                        decoration: BoxDecoration(
                          color: _isHovered ? widget.color : widget.color.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: _isHovered ? Colors.white : widget.color,
                          size: isMobile ? 12 : (isCompact ? 12 : 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: isMobile ? 22 : (isCompact ? 22 : 30),
                          fontWeight: FontWeight.w900,
                          color: _isHovered ? widget.color : const Color(0xFF0F172A),
                          letterSpacing: -0.8,
                        ),
                        child: Text(widget.count),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.title,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 12 : (isCompact ? 12.5 : 14),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.subtitle,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 10 : (isCompact ? 10 : 11),
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

class _EleganceActionCardWidget extends StatefulWidget {
  final String title;
  final String desc;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _EleganceActionCardWidget({
    required this.title,
    required this.desc,
    required this.icon,
    required this.color,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<_EleganceActionCardWidget> createState() => _EleganceActionCardWidgetState();
}

class _EleganceActionCardWidgetState extends State<_EleganceActionCardWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0.0, _isHovered ? -3.0 : 0.0, 0.0),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 10 : 18,
            vertical: isMobile ? 10 : 16,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? widget.color.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
            border: Border.all(
              color: _isHovered ? widget.color.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? widget.color.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.02),
                blurRadius: _isHovered ? 18 : 8,
                offset: Offset(0, _isHovered ? 6 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 8 : 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: isMobile ? 16 : 20),
              ),
              SizedBox(width: isMobile ? 8 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 14,
                        fontWeight: FontWeight.bold,
                        color: _isHovered ? widget.color : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.desc,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 10 : 11,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  transform: Matrix4.translationValues(_isHovered ? 3.0 : 0.0, 0.0, 0.0),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _isHovered ? widget.color : const Color(0xFFCBD5E1),
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF10B981).withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: _animation.value * 0.6),
                blurRadius: 6,
                spreadRadius: 2 * _animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroFeatureHighlight {
  final String title;
  final String desc;
  final IconData icon;
  final Color accentColor;
  final List<Color> gradientColors;

  const _HeroFeatureHighlight({
    required this.title,
    required this.desc,
    required this.icon,
    required this.accentColor,
    required this.gradientColors,
  });
}

class _HeroAnimatedFeatureBanner extends StatefulWidget {
  final String schoolName;
  final String? logoUrl;
  final bool isDesktop;

  const _HeroAnimatedFeatureBanner({
    required this.schoolName,
    this.logoUrl,
    required this.isDesktop,
  });

  @override
  State<_HeroAnimatedFeatureBanner> createState() => _HeroAnimatedFeatureBannerState();
}

class _HeroAnimatedFeatureBannerState extends State<_HeroAnimatedFeatureBanner> {
  int _currentIndex = 0;
  Timer? _timer;

  static const List<_HeroFeatureHighlight> _features = [
    _HeroFeatureHighlight(
      title: 'Keamanan CBT & Anti-Curang',
      desc: 'Proteksi Kunci Layar, AI Deteksi Multitasking & Keamanan Berkas Ujian Real-Time.',
      icon: Icons.shield_rounded,
      accentColor: Color(0xFF818CF8),
      gradientColors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
    ),
    _HeroFeatureHighlight(
      title: 'Koreksi & Rekap Nilai Otomatis',
      desc: 'Penilaian Kuantum instan, analisis ketuntasan siswa, & ekspor rekap ke Excel.',
      icon: Icons.bolt_rounded,
      accentColor: Color(0xFFF59E0B),
      gradientColors: [Color(0xFFF59E0B), Color(0xFFD97706)],
    ),
    _HeroFeatureHighlight(
      title: 'Denah Tempat Duduk & Wizard 7-Langkah',
      desc: 'Otomatisasi penyusunan denah ujian, alokasi ruang murid & pengawas ruangan.',
      icon: Icons.grid_view_rounded,
      accentColor: Color(0xFF10B981),
      gradientColors: [Color(0xFF10B981), Color(0xFF059669)],
    ),
    _HeroFeatureHighlight(
      title: 'Bank Soal Cloud & Impor Massal',
      desc: 'Pengolahan ribuan variasi soal acak, kunci jawaban terenkripsi & impor Excel.',
      icon: Icons.cloud_done_rounded,
      accentColor: Color(0xFF06B6D4),
      gradientColors: [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
    ),
    _HeroFeatureHighlight(
      title: 'Monitoring & Presensi Real-Time',
      desc: 'Pantau status pengerjaan siswa, waktu tersisa, & absensi pengawas secara live.',
      icon: Icons.analytics_rounded,
      accentColor: Color(0xFFEC4899),
      gradientColors: [Color(0xFFDB2777), Color(0xFFE11D48)],
    ),
    _HeroFeatureHighlight(
      title: 'Kartu Peserta & Berita Acara PDF',
      desc: 'Cetak kartu ujian otomatis, daftar hadir, & berita acara pelaksanaan instan.',
      icon: Icons.print_rounded,
      accentColor: Color(0xFF8B5CF6),
      gradientColors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 3800), (timer) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _features.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildSchoolLogoWidget() {
    final logoUrl = widget.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: _buildBannerLogoImage(logoUrl),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF818CF8).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(
        Icons.school_rounded,
        color: Color(0xFF818CF8),
        size: 16,
      ),
    );
  }

  Widget _buildBannerLogoImage(String logoUrl) {
    if (logoUrl.startsWith('data:image/')) {
      try {
        final base64Data = logoUrl.split(',').last;
        final bytes = base64Decode(base64Data);
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {}
    }
    return Image.network(
      logoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: Color(0xFF818CF8), size: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentFeature = _features[_currentIndex];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.isDesktop ? 24 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1B4B).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Header Row with Uploaded School Logo & School Name & Live Active Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildSchoolLogoWidget(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.schoolName,
                        style: GoogleFonts.inter(
                          fontSize: widget.isDesktop ? 22 : 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LivePulseDot(),
                    SizedBox(width: 6),
                    Text(
                      'Sistem Aktif',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 14),

          // Animated Switcher Feature Card with Slide & Fade Transition and STRICT FIXED HEIGHT
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0.04, 0.0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey<int>(_currentIndex),
              width: double.infinity,
              height: widget.isDesktop ? 74 : 78,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: currentFeature.accentColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: currentFeature.gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: currentFeature.accentColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(currentFeature.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentFeature.title,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentFeature.desc,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFFCBD5E1),
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: List.generate(_features.length, (index) {
                  final isActive = index == _currentIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _currentIndex = index);
                      _startTimer();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 6),
                      width: isActive ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isActive ? _features[_currentIndex].accentColor : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
              Text(
                'Keunggulan SesiCermat',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
