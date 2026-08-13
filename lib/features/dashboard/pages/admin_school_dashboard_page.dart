import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../widgets/generate_password_dialog.dart';
import '../widgets/class_form_dialog.dart';
import 'class_detail_screen.dart';

class AdminSchoolDashboardPage extends StatefulWidget {
  const AdminSchoolDashboardPage({super.key});

  @override
  State<AdminSchoolDashboardPage> createState() => _AdminSchoolDashboardPageState();
}

class _AdminSchoolDashboardPageState extends State<AdminSchoolDashboardPage> {
  int _currentTab = 0; // 0: Overview, 1: Guru, 2: Murid
  
  final AdminUserService _adminUserService = AdminUserService();

  // Search & Filter States
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedGenderFilter = 'Semua';
  String _selectedAngkatanFilter = 'Semua';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedGenderFilter = 'Semua';
      _selectedAngkatanFilter = 'Semua';
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

      final fileBytes = excel.save();
      if (fileBytes != null) {
        await saveAndDownloadFile(fileBytes, 'SesiCermat_Daftar_Guru.xlsx');
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

      final fileBytes = excel.save();
      if (fileBytes != null) {
        await saveAndDownloadFile(fileBytes, 'SesiCermat_Daftar_Murid.xlsx');
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
    final schoolId = authService.schoolId ?? '';
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    final bottomNavItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard_rounded), label: 'Ringkasan'),
      const BottomNavigationBarItem(icon: Icon(Icons.assignment_ind_outlined), activeIcon: Icon(Icons.assignment_ind_rounded), label: 'Guru'),
      const BottomNavigationBarItem(icon: Icon(Icons.school_outlined), activeIcon: Icon(Icons.school_rounded), label: 'Murid'),
      const BottomNavigationBarItem(icon: Icon(Icons.book_outlined), activeIcon: Icon(Icons.book_rounded), label: 'Mapel'),
      const BottomNavigationBarItem(icon: Icon(Icons.class_outlined), activeIcon: Icon(Icons.class_rounded), label: 'Kelas'),
    ];

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
                color: const Color(0xFFF8FAFC),
                child: _buildTabContent(schoolId, isDesktop),
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
          title: Text(
            _currentTab == 0
                ? 'Ringkasan'
                : _currentTab == 1
                    ? 'Manajemen Guru'
                    : _currentTab == 2
                        ? 'Manajemen Murid'
                        : _currentTab == 3
                            ? 'Mata Pelajaran'
                            : 'Manajemen Kelas',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
              onPressed: () => authService.signOut(),
              tooltip: 'Keluar',
            )
          ],
          // Note: adjust title logic above for tab 4 & 5
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (idx) {
              _clearFilters();
              setState(() => _currentTab = idx);
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
        body: _buildTabContent(schoolId, isDesktop),
      );
    }
  }

  Widget _buildSidebarItem(int tabIndex, IconData outlineIcon, IconData solidIcon, String label, bool isExtended) {
    final isActive = _currentTab == tabIndex;
    return InkWell(
      onTap: () {
        _clearFilters();
        setState(() => _currentTab = tabIndex);
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

  Widget _buildTabContent(String schoolId, bool isDesktop) {
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

        return Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manajemen Kelas',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: -0.5),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Kelola kelas dan daftar murid di dalamnya',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
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
                    label: const Text('Tambah Kelas'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Content ──
              if (classes.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.class_outlined, size: 72, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text(
                          'Belum ada kelas yang dibuat.\nTekan "Tambah Kelas" untuk memulai.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      itemCount: classes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) => _buildClassListItem(classes[i], schoolId),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClassListItem(Map<String, dynamic> cls, String schoolId) {
    final name = cls['name'] as String? ?? '-';
    final studentCount = (cls['studentIds'] as List?)?.length ?? 0;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClassDetailScreen(schoolId: schoolId, classData: cls),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // ── Icon ──
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.class_rounded, color: Color(0xFF4F46E5), size: 18),
            ),
            const SizedBox(width: 14),
            // ── Name + count ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.people_outlined, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        '$studentCount murid',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Chevron ──
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
          ],
        ),
      ),
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

        return Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ringkasan Portal',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$schoolName • Kode: $schoolCode • Admin: $adminEmail',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              
              Row(
                children: [
                  Expanded(child: _buildDashboardCard('Total Guru', '$teacherCount', Icons.assignment_ind_rounded, const Color(0xFF4F46E5))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDashboardCard('Total Murid', '$studentCount', Icons.school_rounded, const Color(0xFF06B6D4))),
                ],
              ),
              const SizedBox(height: 32),
              const Text('Aktivitas Cepat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildQuickActionBtn('Tambah Guru', Icons.person_add_alt_1_rounded, () {
                    setState(() => _currentTab = 1);
                  }),
                  _buildQuickActionBtn('Tambah Murid', Icons.group_add_rounded, () {
                    setState(() => _currentTab = 2);
                  }),
                  _buildQuickActionBtn('Kelola Mapel', Icons.book_rounded, () {
                    setState(() => _currentTab = 3);
                  }),
                  _buildQuickActionBtn('Impor Siswa Massal', Icons.cloud_upload_rounded, () {
                    _showImportDialog(schoolId);
                  }),
                  _buildQuickActionBtn('Buka Tempat Sampah', Icons.delete_sweep_rounded, () {
                    setState(() => _currentTab = 4);
                  }),
                ],
              )
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
          final matchesQuery = t.displayName.toLowerCase().contains(query) || t.nip.contains(query);
          final matchesGender = _selectedGenderFilter == 'Semua' || t.gender == (_selectedGenderFilter == 'Laki-laki (M)' ? 'M' : 'F');
          return matchesQuery && matchesGender;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Daftar Guru', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Kelola profil guru dan subjek mata pelajaran', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                        onPressed: () => _exportTeachersExcel(filteredTeachers),
                        tooltip: 'Ekspor ke Excel',
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showTeacherForm(schoolId),
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Guru'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Filters Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Cari berdasarkan nama atau NIP...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedGenderFilter,
                    underline: const SizedBox(),
                    items: ['Semua', 'Laki-laki (M)', 'Perempuan (F)'].map((g) {
                      return DropdownMenuItem(value: g, child: Text(g));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedGenderFilter = val ?? 'Semua'),
                  )
                ],
              ),
              const SizedBox(height: 20),

              // Content List
              Expanded(
                child: filteredTeachers.isEmpty
                    ? const Center(child: Text('Tidak ada data guru.'))
                    : isDesktop
                        ? _buildTeachersTable(schoolId, filteredTeachers)
                        : _buildTeachersMobileList(schoolId, filteredTeachers),
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
              DataCell(SelectableText(
                t.tempPassword ?? '-',
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildTeachersMobileList(String schoolId, List<Teacher> teachers) {
    return ListView.builder(
      itemCount: teachers.length,
      itemBuilder: (context, idx) {
        final t = teachers[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(t.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.disabled ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t.disabled ? 'Nonaktif' : 'Aktif',
                        style: TextStyle(color: t.disabled ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 6),
                Text('NIP: ${t.nip} | Gender: ${t.gender == 'M' ? "Laki-laki" : "Perempuan"}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text('Mapel: ${t.subjects.isEmpty ? "-" : t.subjects.join(", ")}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text('Sandi Sementara: ${t.tempPassword ?? "-"}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                const SizedBox(height: 12),
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => _resetPassword(schoolId, 'teachers', t.id, t.displayName),
                      icon: const Icon(Icons.vpn_key_outlined, size: 16, color: Color(0xFFF59E0B)),
                      label: Text(t.uid == null ? 'Buat Akun' : 'Sandi', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () => _showTeacherForm(schoolId, teacher: t),
                      icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF4F46E5)),
                      label: const Text('Edit', style: TextStyle(color: Color(0xFF4F46E5), fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () => _deleteUser(schoolId, 'teachers', t.id, t.displayName, t.nip),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                      label: const Text('Hapus', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
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

  Widget _buildStudentsTab(String schoolId, bool isDesktop) {
    return StreamBuilder<List<Student>>(
      stream: _adminUserService.streamStudents(schoolId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final allStudents = snapshot.data ?? [];
        
        // Extract all unique angkatan values for filtering dropdown
        final angkatanValues = ['Semua', ...allStudents.map((s) => s.angkatan).toSet()];

        final filteredStudents = allStudents.where((s) {
          final query = _searchQuery.toLowerCase();
          final matchesQuery = s.displayName.toLowerCase().contains(query) || s.nis.contains(query);
          final matchesGender = _selectedGenderFilter == 'Semua' || s.gender == (_selectedGenderFilter == 'Laki-laki (M)' ? 'M' : 'F');
          final matchesAngkatan = _selectedAngkatanFilter == 'Semua' || s.angkatan == _selectedAngkatanFilter;
          return matchesQuery && matchesGender && matchesAngkatan;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Daftar Murid', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Kelola database murid dan data login siswa', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                        onPressed: () => _showStudentForm(schoolId),
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Murid'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Filters Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Cari berdasarkan nama atau NIS...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedGenderFilter,
                    underline: const SizedBox(),
                    items: ['Semua', 'Laki-laki (M)', 'Perempuan (F)'].map((g) {
                      return DropdownMenuItem(value: g, child: Text(g));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedGenderFilter = val ?? 'Semua'),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedAngkatanFilter,
                    underline: const SizedBox(),
                    items: angkatanValues.map((a) {
                      return DropdownMenuItem(value: a, child: Text('Angkatan: $a'));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedAngkatanFilter = val ?? 'Semua'),
                  )
                ],
              ),
              const SizedBox(height: 20),

              // Content List
              Expanded(
                child: filteredStudents.isEmpty
                    ? const Center(child: Text('Tidak ada data murid.'))
                    : isDesktop
                        ? _buildStudentsTable(schoolId, filteredStudents)
                        : _buildStudentsMobileList(schoolId, filteredStudents),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentsTable(String schoolId, List<Student> students) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Nama', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('NIS', style: TextStyle(fontWeight: FontWeight.bold))),
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
              DataCell(Text(s.gender == 'M' ? 'Laki-laki' : 'Perempuan')),
              DataCell(Text(s.angkatan)),
              DataCell(SelectableText(
                s.tempPassword ?? '-',
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildStudentsMobileList(String schoolId, List<Student> students) {
    return ListView.builder(
      itemCount: students.length,
      itemBuilder: (context, idx) {
        final s = students[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: s.disabled ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.disabled ? 'Nonaktif' : 'Aktif',
                        style: TextStyle(color: s.disabled ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 6),
                Text('NIS: ${s.nis} | Gender: ${s.gender == 'M' ? "Laki-laki" : "Perempuan"}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text('Angkatan: ${s.angkatan}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text('Sandi Sementara: ${s.tempPassword ?? "-"}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                const SizedBox(height: 12),
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => _resetPassword(schoolId, 'students', s.id, s.displayName),
                      icon: const Icon(Icons.vpn_key_outlined, size: 16, color: Color(0xFFF59E0B)),
                      label: Text(s.uid == null ? 'Buat Akun' : 'Sandi', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () => _showStudentForm(schoolId, student: s),
                      icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF4F46E5)),
                      label: const Text('Edit', style: TextStyle(color: Color(0xFF4F46E5), fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () => _deleteUser(schoolId, 'students', s.id, s.displayName, s.nis),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                      label: const Text('Hapus', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
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

  Widget _buildDashboardCard(String title, String count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 16,
            offset: Offset(0, 4),
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        foregroundColor: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showTeacherForm(String schoolId, {Teacher? teacher}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TeacherFormDialog(schoolId: schoolId, teacher: teacher),
    );
  }

  void _showStudentForm(String schoolId, {Student? student}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StudentFormDialog(schoolId: schoolId, student: student),
    );
  }

  void _showSubjectForm(String schoolId, {Map<String, dynamic>? subject}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SubjectFormDialog(schoolId: schoolId, subject: subject),
    );
  }

  void _showImportDialog(String schoolId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportStudentsDialog(schoolId: schoolId),
    );
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mata Pelajaran', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Kelola daftar mata pelajaran yang aktif di sekolah', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showSubjectForm(schoolId),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Mapel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Search Row
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cari berdasarkan nama atau kode mapel...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
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
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Kode: $code', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F46E5), size: 20),
                      onPressed: () => _showSubjectForm(schoolId, subject: sub),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                      onPressed: () => _confirmDeleteSubject(schoolId, sub['id'], name),
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
