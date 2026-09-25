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
import '../widgets/generate_password_dialog.dart';
import '../widgets/class_form_dialog.dart';
import '../widgets/select_angkatan_dialog.dart';
import 'event_list_screen.dart';

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
        return _buildTeachersTab(schoolId, isDesktop);
      case 2:
        return _buildStudentsTab(schoolId, isDesktop);
      case 3:
        return _buildAlumniTab(schoolId, isDesktop);
      case 4:
        return _buildSubjectsTab(schoolId, isDesktop);
      case 5:
        return _buildClassesTab(schoolId, isDesktop);
      case 6:
        return EventListScreen(schoolId: schoolId);
      case 7:
        return _buildSettingsTab(authService, schoolId);
      default:
        return const Center(child: Text('Konten Tidak Ditemukan'));
    }
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
                  onChanged: (val) => _searchNotifier.value = val,
                ),
              ),
              const SizedBox(height: 20),

              // ── Content ── only this part rebuilds on search
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: _searchNotifier,
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

  Widget _buildTeachersTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Teacher>>(
      initialData: _cachedTeachers,
      stream: _teachersStream ?? _adminUserService.streamTeachers(schoolId),
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
              _buildQuotaWarningBanner(schoolId),
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
                          onPressed: () => _exportTeachersExcel(allTeachers),
                          tooltip: 'Ekspor ke Excel',
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _generateAllTeacherPasswords(schoolId, allTeachers),
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
                            onPressed: () => _generateAllTeacherPasswords(schoolId, allTeachers),
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
 
              // Search Bar — updates ValueNotifier only, no setState
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
 
              // Content List — rebuilds on search query and state changes
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
                                  onPressed: () => setState(() {
                                    _selectedTeacherGenderFilter = null;
                                    _selectedTeacherSubjectFilter = null;
                                    _selectedTeacherStatusFilter = null;
                                    _teacherCurrentPage = 0;
                                  }),
                                  child: Text('Reset Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: filteredTeachers.isEmpty
                              ? const Center(child: Text('Tidak ada data guru.'))
                              : _buildTeachersTable(schoolId, paginatedTeachers, allTeachers),
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

  Widget _buildTeachersTable(String schoolId, List<Teacher> teachers, List<Teacher> allTeachers) {
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
                          width: 160,
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
                                  onPressed: () => _generateSingleTeacherPasswordDirectly(schoolId, t),
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
                              onTap: () => _toggleTeacherStatus(schoolId, t),
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
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 160,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 18),
                                tooltip: t.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                                onPressed: () => _resetPassword(schoolId, 'teachers', t.id, t.displayName),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 18),
                                tooltip: 'Ubah Data',
                                onPressed: () => _showTeacherForm(schoolId, teacher: t),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: Icon(
                                  t.disabled ? Icons.toggle_off_rounded : Icons.toggle_on_rounded,
                                  color: t.disabled ? const Color(0xFF94A3B8) : const Color(0xFF10B981),
                                  size: 24,
                                ),
                                tooltip: t.disabled ? 'Aktifkan Akun Guru' : 'Nonaktifkan Akun Guru',
                                onPressed: () => _toggleTeacherStatus(schoolId, t),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                tooltip: 'Hapus Permanen',
                                onPressed: () => _deleteUser(schoolId, 'teachers', t.id, t.displayName, t.nip),
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

  Widget _buildStudentsTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      initialData: _cachedClasses,
      stream: _classesStream ?? _adminUserService.streamClasses(schoolId),
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
          stream: _studentsStream ?? _adminUserService.streamStudents(schoolId),
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
                  _buildQuotaWarningBanner(schoolId),
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
                              onPressed: () => _exportStudentsExcel(allStudents),
                              tooltip: 'Ekspor ke Excel',
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _resetAllStudentSessions(schoolId, allStudents),
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
                              onPressed: () => _generateAllPasswords(schoolId, allStudents),
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
                              onPressed: () => _showGraduationDialog(schoolId, allStudents),
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
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.school_rounded, color: Color(0xFF059669), size: 20),
                                onPressed: () => _showGraduationDialog(schoolId, allStudents),
                                tooltip: 'Luluskan Murid',
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F9FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFBAE6FD)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFF0284C7), size: 20),
                                onPressed: () => _resetAllStudentSessions(schoolId, allStudents),
                                tooltip: 'Reset Semua Sesi Murid',
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
                                onPressed: () => _generateAllPasswords(schoolId, allStudents),
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

                  // Search Bar — updates ValueNotifier only, no setState
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
                      onChanged: (val) {
                        _searchNotifier.value = val;
                        _studentCurrentPage = 0;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Content List — rebuilds on search query and state changes
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _searchNotifier,
                      builder: (context, query, _) {
                        final filteredStudents = allStudents.where((s) {
                          final q = query.trim().toLowerCase();
                          final matchesQuery = q.isEmpty ||
                              s.displayName.toLowerCase().contains(q) ||
                              s.nis.toLowerCase().contains(q);
                          if (!matchesQuery) return false;

                          if (_selectedClassFilter != null && _selectedClassFilter != 'Semua Kelas') {
                            final sClass = studentClassMap[s.id] ?? '-';
                            if (sClass != _selectedClassFilter) return false;
                          }

                          if (_selectedGenderFilter != null && _selectedGenderFilter != 'Semua Gender') {
                            final genderStr = s.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                            if (genderStr != _selectedGenderFilter) return false;
                          }

                          if (_selectedReligionFilter != null && _selectedReligionFilter != 'Semua Agama') {
                            if (s.religion.trim().toLowerCase() != _selectedReligionFilter!.trim().toLowerCase()) return false;
                          }

                          if (_selectedAngkatanFilter != null && _selectedAngkatanFilter != 'Semua Angkatan') {
                            if (s.angkatan.trim() != _selectedAngkatanFilter!.trim()) return false;
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
                              final cA = studentClassMap[a.id] ?? '';
                              final cB = studentClassMap[b.id] ?? '';
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
                              cmp = a.angkatan.compareTo(b.angkatan);
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
                                      onPressed: () => setState(() {
                                        _selectedClassFilter = null;
                                        _selectedGenderFilter = null;
                                        _selectedReligionFilter = null;
                                        _selectedAngkatanFilter = null;
                                        _selectedStatusFilter = null;
                                        _studentCurrentPage = 0;
                                      }),
                                      child: Text('Reset Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: filteredStudents.isEmpty
                                  ? const Center(child: Text('Tidak ada data murid.'))
                                  : _buildStudentsTable(schoolId, paginatedStudents, studentClassMap, allStudents),
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

  Widget _buildStudentsTable(
    String schoolId,
    List<Student> students,
    Map<String, String> studentClassMap,
    List<Student> allStudents,
  ) {
    // Generate options for header filter dropdowns
    final classSet = studentClassMap.values.where((c) => c.isNotEmpty && c != '-').toSet().toList()..sort();
    final classOptions = ['Semua Kelas', ...classSet];

    final genderOptions = ['Semua Gender', 'Laki-laki', 'Perempuan'];

    // ONLY show religions that exist in this school's students
    final existingReligions = allStudents
        .map((s) => s.religion.trim())
        .where((r) => r.isNotEmpty && r != '-')
        .toSet()
        .toList()
      ..sort();
    final religionOptions = ['Semua Agama', ...existingReligions];

    // Angkatan options from students in this school
    final existingAngkatan = allStudents
        .map((s) => s.angkatan.trim())
        .where((a) => a.isNotEmpty && a != '-')
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final angkatanOptions = ['Semua Angkatan', ...existingAngkatan];

    // Status options
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
                                  onPressed: () => _generateSinglePasswordDirectly(schoolId, s),
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
                              onTap: () => _toggleStudentStatus(schoolId, s),
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
                                  onPressed: () => _resetStudentSession(schoolId, s),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 18),
                                  tooltip: s.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                                  onPressed: () => _resetPassword(schoolId, 'students', s.id, s.displayName),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 18),
                                  tooltip: 'Ubah Data',
                                  onPressed: () => _showStudentForm(schoolId, student: s),
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
                                  onPressed: () => _toggleStudentStatus(schoolId, s),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                  tooltip: 'Hapus Permanen',
                                  onPressed: () => _deleteUser(schoolId, 'students', s.id, s.displayName, s.nis),
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

  Widget _buildAlumniTab(String schoolId, bool isDesktop) {
    _initStreams(schoolId);

    return StreamBuilder<List<Map<String, dynamic>>>(
      initialData: _cachedClasses,
      stream: _classesStream ?? _adminUserService.streamClasses(schoolId),
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
          stream: _studentsStream ?? _adminUserService.streamStudents(schoolId),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _cachedStudents = snapshot.data;
            }
            if (snapshot.hasError && !snapshot.hasData) return Center(child: Text('Error: ${snapshot.error}'));
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const AppContentLoader(
                title: 'Memuat Data Alumni...',
                subtitle: 'Mengambil daftar murid alumni dari database',
              );
            }

            final rawStudents = snapshot.data ?? [];
            final allAlumni = rawStudents.where((s) => s.isGraduated).toList();

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
                              'Daftar Alumni',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kelola database murid yang telah dinyatakan lulus',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                              onPressed: () => _exportStudentsExcel(allAlumni),
                              tooltip: 'Ekspor Alumni ke Excel',
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _navigateToTab(2),
                              icon: const Icon(Icons.school_rounded, size: 16, color: Color(0xFF4F46E5)),
                              label: Text(
                                'Ke Manajemen Murid',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF4F46E5)),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFC7D2FE)),
                                backgroundColor: const Color(0xFFEEF2FF),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                          'Daftar Alumni',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Database murid yang telah lulus',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                              onPressed: () => _exportStudentsExcel(allAlumni),
                              tooltip: 'Ekspor ke Excel',
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
                      controller: _alumniSearchController,
                      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Cari alumni berdasarkan nama atau NIS...',
                        hintStyle: GoogleFonts.inter(
                          color: const Color(0xFF94A3B8),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (val) {
                        _alumniSearchNotifier.value = val;
                        _alumniCurrentPage = 0;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Content List
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _alumniSearchNotifier,
                      builder: (context, query, _) {
                        final filteredAlumni = allAlumni.where((s) {
                          final q = query.trim().toLowerCase();
                          final matchesQuery = q.isEmpty ||
                              s.displayName.toLowerCase().contains(q) ||
                              s.nis.toLowerCase().contains(q);
                          if (!matchesQuery) return false;

                          if (_selectedAlumniClassFilter != null && _selectedAlumniClassFilter != 'Semua Kelas') {
                            final sClass = studentClassMap[s.id] ?? '-';
                            if (sClass != _selectedAlumniClassFilter) return false;
                          }

                          if (_selectedAlumniGenderFilter != null && _selectedAlumniGenderFilter != 'Semua Gender') {
                            final genderStr = s.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                            if (genderStr != _selectedAlumniGenderFilter) return false;
                          }

                          if (_selectedAlumniReligionFilter != null && _selectedAlumniReligionFilter != 'Semua Agama') {
                            if (s.religion.trim().toLowerCase() != _selectedAlumniReligionFilter!.trim().toLowerCase()) return false;
                          }

                          if (_selectedAlumniAngkatanFilter != null && _selectedAlumniAngkatanFilter != 'Semua Angkatan') {
                            if (s.angkatan.trim() != _selectedAlumniAngkatanFilter!.trim()) return false;
                          }

                          return true;
                        }).toList();

                        // Sorting
                        filteredAlumni.sort((a, b) {
                          int cmp = 0;
                          switch (_alumniSortColumn) {
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
                              final cA = studentClassMap[a.id] ?? '';
                              final cB = studentClassMap[b.id] ?? '';
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
                              cmp = a.angkatan.compareTo(b.angkatan);
                              break;
                            case 'kata_sandi':
                              cmp = (a.tempPassword ?? '').compareTo(b.tempPassword ?? '');
                              break;
                            default:
                              cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                          }
                          return _alumniSortAscending ? cmp : -cmp;
                        });

                        final totalItems = filteredAlumni.length;
                        final totalPages = (totalItems / _alumniRowsPerPage).ceil();
                        final currentPage = (_alumniCurrentPage >= totalPages && totalPages > 0)
                            ? totalPages - 1
                            : _alumniCurrentPage;
                        final pageStart = currentPage * _alumniRowsPerPage;
                        final pageEnd = (pageStart + _alumniRowsPerPage < totalItems)
                            ? pageStart + _alumniRowsPerPage
                            : totalItems;
                        final paginatedAlumni = (pageStart < totalItems)
                            ? filteredAlumni.sublist(pageStart, pageEnd)
                            : <Student>[];

                        final hasActiveFilters = _selectedAlumniClassFilter != null ||
                            _selectedAlumniGenderFilter != null ||
                            _selectedAlumniReligionFilter != null ||
                            _selectedAlumniAngkatanFilter != null;

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
                                    if (_selectedAlumniClassFilter != null)
                                      Chip(
                                        label: Text('Kelas: $_selectedAlumniClassFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniClassFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    if (_selectedAlumniGenderFilter != null)
                                      Chip(
                                        label: Text('Gender: $_selectedAlumniGenderFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniGenderFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    if (_selectedAlumniReligionFilter != null)
                                      Chip(
                                        label: Text('Agama: $_selectedAlumniReligionFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniReligionFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    if (_selectedAlumniAngkatanFilter != null)
                                      Chip(
                                        label: Text('Angkatan: $_selectedAlumniAngkatanFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniAngkatanFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _selectedAlumniClassFilter = null;
                                        _selectedAlumniGenderFilter = null;
                                        _selectedAlumniReligionFilter = null;
                                        _selectedAlumniAngkatanFilter = null;
                                        _alumniCurrentPage = 0;
                                      }),
                                      child: Text('Reset Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: filteredAlumni.isEmpty
                                  ? const Center(child: Text('Tidak ada data alumni.'))
                                  : _buildAlumniTable(schoolId, paginatedAlumni, studentClassMap, allAlumni),
                            ),
                            if (filteredAlumni.isNotEmpty)
                              _buildPaginationControls(
                                currentPage: currentPage,
                                rowsPerPage: _alumniRowsPerPage,
                                totalItems: totalItems,
                                onPageChanged: (page) => setState(() => _alumniCurrentPage = page),
                                onRowsPerPageChanged: (rows) => setState(() {
                                  _alumniRowsPerPage = rows;
                                  _alumniCurrentPage = 0;
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

  Widget _buildAlumniTable(
    String schoolId,
    List<Student> alumni,
    Map<String, String> studentClassMap,
    List<Student> allAlumni,
  ) {
    final classSet = studentClassMap.values.where((c) => c.isNotEmpty && c != '-').toSet().toList()..sort();
    final classOptions = ['Semua Kelas', ...classSet];

    final genderOptions = ['Semua Gender', 'Laki-laki', 'Perempuan'];

    final existingReligions = allAlumni
        .map((s) => s.religion.trim())
        .where((r) => r.isNotEmpty && r != '-')
        .toSet()
        .toList()
      ..sort();
    final religionOptions = ['Semua Agama', ...existingReligions];

    final existingAngkatan = allAlumni
        .map((s) => s.angkatan.trim())
        .where((a) => a.isNotEmpty && a != '-')
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final angkatanOptions = ['Semua Angkatan', ...existingAngkatan];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _alumniTableHorizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 8,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: _alumniTableHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    columnSpacing: 14,
                    columns: [
                      _buildAlumniSortableHeader('Nama', 'nama', 200),
                      _buildAlumniSortableHeader('NIS', 'nis', 80),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Kelas',
                        colKey: 'kelas',
                        currentFilter: _selectedAlumniClassFilter,
                        options: classOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniClassFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Gender',
                        colKey: 'gender',
                        currentFilter: _selectedAlumniGenderFilter,
                        options: genderOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniGenderFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Agama',
                        colKey: 'agama',
                        currentFilter: _selectedAlumniReligionFilter,
                        options: religionOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniReligionFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Angkatan',
                        colKey: 'angkatan',
                        currentFilter: _selectedAlumniAngkatanFilter,
                        options: angkatanOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniAngkatanFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 125,
                      ),
                      _buildAlumniSortableHeader('Kata Sandi', 'kata_sandi', 110),
                      const DataColumn(
                        label: SizedBox(
                          width: 100,
                          child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const DataColumn(
                        label: SizedBox(
                          width: 180,
                          child: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    rows: alumni.map((s) {
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
                              : const Text('-', style: TextStyle(color: Color(0xFF94A3B8))),
                        )),
                        DataCell(SizedBox(
                          width: 100,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Alumni',
                              style: TextStyle(
                                color: Color(0xFF7C3AED),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 180,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 18),
                                tooltip: s.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                                onPressed: () => _resetPassword(schoolId, 'students', s.id, s.displayName),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.restore_rounded, color: Color(0xFF10B981), size: 20),
                                tooltip: 'Batalkan Kelulusan (Kembalikan ke Murid Aktif)',
                                onPressed: () => _restoreAlumniStudent(schoolId, s),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                tooltip: 'Hapus Permanen',
                                onPressed: () => _deleteUser(schoolId, 'students', s.id, s.displayName, s.nis),
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

  Future<void> _restoreAlumniStudent(String schoolId, Student s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Kembalikan ke Murid Aktif', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin membatalkan status kelulusan murid "${s.displayName}" (NIS: ${s.nis}) dan mengembalikannya ke daftar murid aktif?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ya, Kembalikan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminUserService.restoreGraduatedStudent(schoolId: schoolId, studentId: s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Murid "${s.displayName}" berhasil dikembalikan ke status Aktif.'),
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
            content: Text('Gagal mengembalikan murid: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  DataColumn _buildAlumniSortableHeader(String title, String colKey, double width) {
    final isSorted = _alumniSortColumn == colKey;
    return DataColumn(
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              if (_alumniSortColumn == colKey) {
                _alumniSortAscending = !_alumniSortAscending;
              } else {
                _alumniSortColumn = colKey;
                _alumniSortAscending = true;
              }
              _alumniCurrentPage = 0;
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
                      ? (_alumniSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
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

  DataColumn _buildAlumniFilterAndSortHeader({
    required String title,
    required String colKey,
    required String? currentFilter,
    required List<String> options,
    required ValueChanged<String?> onSelected,
    required double width,
  }) {
    final isSorted = _alumniSortColumn == colKey;
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
                  if (_alumniSortColumn == colKey) {
                    _alumniSortAscending = !_alumniSortAscending;
                  } else {
                    _alumniSortColumn = colKey;
                    _alumniSortAscending = true;
                  }
                  _alumniCurrentPage = 0;
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
                          ? (_alumniSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
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
                        if (isSelected)
                          const Icon(Icons.check_rounded, size: 16, color: Color(0xFF4F46E5))
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(
                          opt,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
            // Title & Triangle Sort Icon (Clickable for Sorting)
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
            // Filter Dropdown Icon (right next to sort icon)
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
            // Title & Triangle Sort Icon (Clickable for Sorting)
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
            // Filter Dropdown Icon (right next to sort icon)
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

  Future<void> _showTeacherForm(String schoolId, {Teacher? teacher}) async {
    if (teacher == null) {
      final sDoc = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
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
      builder: (context) => TeacherFormDialog(schoolId: schoolId, teacher: teacher),
    );
    _refreshTeachers(schoolId);
  }

  Future<void> _showStudentForm(String schoolId, {Student? student}) async {
    if (student == null) {
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
    }
    if (!mounted) return;
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

  void _showGraduationDialog(String schoolId, List<Student> students) {
    showDialog(
      context: context,
      builder: (_) => SelectAngkatanDialog(
        schoolId: schoolId,
        students: students,
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
    _refreshStudents(schoolId);
  }

  Future<void> _showImportTeachersDialog(String schoolId) async {
    final sDoc = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
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
      builder: (context) => ImportTeachersDialog(schoolId: schoolId),
    );
    _refreshTeachers(schoolId);
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
              onChanged: (val) => _searchNotifier.value = val,
                ),
              ),
              const SizedBox(height: 20),

              // Content List — only this part rebuilds on search
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: _searchNotifier,
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

  Widget _buildSettingsTab(AuthService authService, String schoolId) {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isSaving = false;
    bool isUploadingLogo = false;

    final userEmail = authService.user?.email ?? '';
    final initialLetter = userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'A';

    return StreamBuilder<DocumentSnapshot>(
      initialData: _cachedSchoolSnapshot,
      stream: FirebaseFirestore.instance.collection('schools').doc(schoolId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedSchoolSnapshot = snapshot.data;
        }
        final schoolData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final schoolName = schoolData['name'] ?? 'Sekolah';
        final schoolCode = schoolData['code'] ?? '-';
        final schoolLogoUrl = schoolData['logoUrl'] as String?;
        final maxStudentQuota = schoolData['maxStudentQuota'] ??
            schoolData['maxStudent'] ??
            schoolData['quotaStudent'] ??
            schoolData['studentLimit'] ??
            schoolData['quotaLimit'] ??
            500;
        final maxTeacherQuota = schoolData['maxTeacherQuota'] ??
            schoolData['maxTeacher'] ??
            schoolData['quotaTeacher'] ??
            schoolData['teacherLimit'] ??
            50;

        return LayoutBuilder(
          builder: (context, viewportConstraints) {
            final isDesktop = viewportConstraints.maxWidth > 768;

            return StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewportConstraints.maxHeight),
                    child: Container(
                      width: double.infinity,
                      color: const Color(0xFFF8FAFC),
                      padding: EdgeInsets.all(isDesktop ? 28.0 : 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🌟 HERO BANNER SECTION
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(isDesktop ? 24.0 : 18.0),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0F172A),
                                  Color(0xFF1E1B4B),
                                  Color(0xFF312E81),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1E1B4B).withValues(alpha: 0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: LayoutBuilder(
                              builder: (context, heroConstraints) {
                                final isHeroWide = heroConstraints.maxWidth > 650;
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: const Color(0xFF818CF8).withValues(alpha: 0.4),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.verified_user_rounded, color: Color(0xFFA5B4FC), size: 14),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'PUSAT KONTROL ADMIN',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: const Color(0xFFA5B4FC),
                                                        letterSpacing: 0.8,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Pengaturan Akun & Sekolah',
                                            style: GoogleFonts.inter(
                                              fontSize: isDesktop ? 24 : 20,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Kelola identitas resmi sekolah, kredensial administrator, dan konfigurasi keamanan sistem.',
                                            style: GoogleFonts.inter(
                                              fontSize: isDesktop ? 13 : 12,
                                              color: const Color(0xFFC7D2FE),
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isHeroWide) ...[
                                      const SizedBox(width: 24),
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.15),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFF10B981),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'System Online',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Encrypted TLS 1.3 Active',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 24),

                          // 🌟 RESPONSIVE CARDS GRID
                          LayoutBuilder(
                            builder: (context, gridConstraints) {
                              final isWide = gridConstraints.maxWidth > 950;

                              // --- CARD 1: SCHOOL LOGO & IDENTITAS ---
                              final schoolCard = Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
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
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEEF2FF),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.school_rounded,
                                            color: Color(0xFF4F46E5),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Identitas & Logo Sekolah',
                                                style: GoogleFonts.inter(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(0xFF0F172A),
                                                ),
                                              ),
                                              Text(
                                                'Profil resmi instansi',
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
                                    const SizedBox(height: 22),

                                    // LOGO DISPLAY & BUTTONS
                                    Center(
                                      child: Column(
                                        children: [
                                          Stack(
                                            children: [
                                              Container(
                                                width: 110,
                                                height: 110,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8FAFC),
                                                  borderRadius: BorderRadius.circular(24),
                                                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                                      blurRadius: 16,
                                                      offset: const Offset(0, 6),
                                                    ),
                                                  ],
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(22),
                                                  child: (schoolLogoUrl != null && schoolLogoUrl.isNotEmpty)
                                                      ? _buildLogoImage(schoolLogoUrl)
                                                      : Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            const Icon(
                                                              Icons.school_outlined,
                                                              size: 44,
                                                              color: Color(0xFF94A3B8),
                                                            ),
                                                            const SizedBox(height: 4),
                                                            Text(
                                                              'Belum ada logo',
                                                              style: GoogleFonts.inter(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w600,
                                                                color: const Color(0xFF94A3B8),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: isUploadingLogo
                                                    ? null
                                                    : () async {
                                                        try {
                                                          final result = await FilePicker.platform.pickFiles(
                                                            type: FileType.image,
                                                            withData: true,
                                                          );
                                                          if (result != null && result.files.single.bytes != null) {
                                                            setState(() => isUploadingLogo = true);
                                                            final bytes = result.files.single.bytes!;
                                                            final ext = result.files.single.extension?.toLowerCase() ?? 'png';
                                                            final mimeType = (ext == 'jpg' || ext == 'jpeg')
                                                                ? 'image/jpeg'
                                                                : (ext == 'webp' ? 'image/webp' : 'image/png');
                                                            final base64Str = 'data:$mimeType;base64,${base64Encode(bytes)}';

                                                            await FirebaseFirestore.instance
                                                                .collection('schools')
                                                                .doc(schoolId)
                                                                .update({'logoUrl': base64Str});

                                                            if (context.mounted) {
                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                SnackBar(
                                                                  content: Row(
                                                                    children: [
                                                                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                                                      const SizedBox(width: 8),
                                                                      Text(
                                                                        'Logo sekolah berhasil diunggah!',
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
                                                          }
                                                        } catch (e) {
                                                          debugPrint('Error pick logo: $e');
                                                        } finally {
                                                          setState(() => isUploadingLogo = false);
                                                        }
                                                      },
                                                icon: isUploadingLogo
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                      )
                                                    : const Icon(Icons.cloud_upload_rounded, size: 16),
                                                label: Text(
                                                  schoolLogoUrl != null ? 'Ganti Logo' : 'Unggah Logo',
                                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF4F46E5),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  elevation: 0,
                                                ),
                                              ),
                                              if (schoolLogoUrl != null && schoolLogoUrl.isNotEmpty)
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    await FirebaseFirestore.instance
                                                        .collection('schools')
                                                        .doc(schoolId)
                                                        .update({'logoUrl': FieldValue.delete()});
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Logo sekolah berhasil dihapus',
                                                            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                                  label: Text(
                                                    'Hapus',
                                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                                  ),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: const Color(0xFFEF4444),
                                                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 22),
                                    const Divider(color: Color(0xFFF1F5F9)),
                                    const SizedBox(height: 16),

                                    // SCHOOL METADATA TILES
                                    _buildModernTile(
                                      icon: Icons.business_rounded,
                                      iconBgColor: const Color(0xFFEEF2FF),
                                      iconColor: const Color(0xFF4F46E5),
                                      title: 'Nama Sekolah',
                                      value: schoolName,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildModernTile(
                                      icon: Icons.qr_code_rounded,
                                      iconBgColor: const Color(0xFFECFEFF),
                                      iconColor: const Color(0xFF0891B2),
                                      title: 'Kode Sekolah',
                                      value: schoolCode,
                                      isCode: true,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildModernTile(
                                      icon: Icons.people_outline_rounded,
                                      iconBgColor: const Color(0xFFF0FDF4),
                                      iconColor: const Color(0xFF16A34A),
                                      title: 'Batas Kuota Siswa',
                                      value: '$maxStudentQuota Siswa',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildModernTile(
                                      icon: Icons.badge_outlined,
                                      iconBgColor: const Color(0xFFFFF7ED),
                                      iconColor: const Color(0xFFEA580C),
                                      title: 'Batas Kuota Guru',
                                      value: '$maxTeacherQuota Guru',
                                    ),
                                  ],
                                ),
                              );

                              // --- CARD 2: ADMIN PROFILE ---
                              final profileCard = Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
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
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF0FDF4),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.admin_panel_settings_rounded,
                                            color: Color(0xFF16A34A),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Profil Administrator',
                                                style: GoogleFonts.inter(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(0xFF0F172A),
                                                ),
                                              ),
                                              Text(
                                                'Informasi akun yang sedang aktif',
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
                                    const SizedBox(height: 22),

                                    // USER AVATAR & EMAIL CARD
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 52,
                                            height: 52,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                initialLetter,
                                                style: GoogleFonts.inter(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  userEmail,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(0xFF0F172A),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEEF2FF),
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: const Color(0xFFC7D2FE)),
                                                  ),
                                                  child: Text(
                                                    'Admin Utama Sekolah',
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
                                    ),

                                    const SizedBox(height: 20),
                                    const Divider(color: Color(0xFFF1F5F9)),
                                    const SizedBox(height: 16),

                                    _buildModernTile(
                                      icon: Icons.verified_user_rounded,
                                      iconBgColor: const Color(0xFFECFDF5),
                                      iconColor: const Color(0xFF059669),
                                      title: 'Status Akun',
                                      value: 'Aktif & Terverifikasi',
                                      badgeColor: const Color(0xFF10B981),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildModernTile(
                                      icon: Icons.security_rounded,
                                      iconBgColor: const Color(0xFFEFF6FF),
                                      iconColor: const Color(0xFF2563EB),
                                      title: 'Keamanan Sesi',
                                      value: 'Enkripsi Tinggi (AES-256)',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildModernTile(
                                      icon: Icons.calendar_today_rounded,
                                      iconBgColor: const Color(0xFFF8FAFC),
                                      iconColor: const Color(0xFF64748B),
                                      title: 'Tanggal Akses',
                                      value: DateTime.now().toString().split(' ')[0],
                                    ),
                                  ],
                                ),
                              );

                              // --- CARD 3: CHANGE PASSWORD ---
                              final changePasswordCard = Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
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
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F3FF),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.lock_reset_rounded,
                                              color: Color(0xFF7C3AED),
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Ubah Kata Sandi Admin',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(0xFF0F172A),
                                                  ),
                                                ),
                                                Text(
                                                  'Perbarui kata sandi secara berkala',
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
                                      const SizedBox(height: 22),

                                      TextFormField(
                                        controller: passwordController,
                                        obscureText: obscurePassword,
                                        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                                        decoration: InputDecoration(
                                          labelText: 'Kata Sandi Baru',
                                          labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                                          hintText: 'Minimal 6 karakter',
                                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                                          ),
                                          prefixIcon: const Icon(Icons.key_rounded, size: 20, color: Color(0xFF94A3B8)),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                              size: 20,
                                              color: const Color(0xFF64748B),
                                            ),
                                            onPressed: () => setState(() => obscurePassword = !obscurePassword),
                                          ),
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
                                      const SizedBox(height: 16),

                                      TextFormField(
                                        controller: confirmController,
                                        obscureText: obscureConfirm,
                                        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                                        decoration: InputDecoration(
                                          labelText: 'Konfirmasi Kata Sandi Baru',
                                          labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                                          hintText: 'Ulangi kata sandi baru',
                                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                                          filled: true,
                                          fillColor: const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
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
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            elevation: 0,
                                          ),
                                          child: isSaving
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                                )
                                              : Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.save_rounded, size: 18),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Simpan Perubahan',
                                                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                                                    ),
                                                  ],
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
                                    Expanded(flex: 1, child: schoolCard),
                                    const SizedBox(width: 20),
                                    Expanded(flex: 1, child: profileCard),
                                    const SizedBox(width: 20),
                                    Expanded(flex: 1, child: changePasswordCard),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    schoolCard,
                                    const SizedBox(height: 20),
                                    profileCard,
                                    const SizedBox(height: 20),
                                    changePasswordCard,
                                  ],
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
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
