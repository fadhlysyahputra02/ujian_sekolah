import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/models/student.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/services/auth_service.dart';

class AdminStudentGraduationPage extends StatefulWidget {
  final String schoolId;
  final String? initialAngkatan;

  const AdminStudentGraduationPage({
    super.key,
    required this.schoolId,
    this.initialAngkatan,
  });

  @override
  State<AdminStudentGraduationPage> createState() => _AdminStudentGraduationPageState();
}

class _AdminStudentGraduationPageState extends State<AdminStudentGraduationPage> {
  final AdminUserService _adminUserService = AdminUserService();
  final TextEditingController _searchController = TextEditingController();

  Set<String> _selectedAngkatans = {};
  final Set<String> _selectedStudentIds = {};
  bool _isProcessing = false;

  // Filters & Search
  String _searchQuery = '';
  String? _selectedClassFilter;
  String? _selectedGenderFilter;

  // Sorting
  String _sortColumn = 'nama';
  bool _sortAscending = true;

  // Pagination
  int _rowsPerPage = 10;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialAngkatan != null && widget.initialAngkatan!.trim().isNotEmpty) {
      final parts = widget.initialAngkatan!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      _selectedAngkatans = parts.toSet();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _currentPage = 0;
    });
  }

  Future<void> _handleGraduateStudents(String schoolId, List<Student> studentsToGraduate) async {
    final count = _selectedStudentIds.length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pilih setidaknya satu siswa untuk diluluskan.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w500),
          ),
          backgroundColor: const Color(0xFFE11D48),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final angkatanStr = _selectedAngkatans.join(', ');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.school_rounded, color: Color(0xFFD97706), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Konfirmasi Kelulusan Murid',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anda akan meluluskan $count murid dari Angkatan $angkatanStr.',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Murid yang sudah diluluskan akan berstatus Alumni dan TIDAK AKAN tertampil lagi di daftar murid aktif sekolah.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
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
            child: Text(
              'Batal',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: Text(
              'Ya, Luluskan Siswa',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      final idsList = _selectedStudentIds.toList();
      await _adminUserService.graduateStudents(
        schoolId: schoolId,
        studentIds: idsList,
      );

      if (mounted) {
        setState(() {
          _selectedStudentIds.clear();
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Berhasil meluluskan $count murid!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal meluluskan siswa: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final activeSchoolId = widget.schoolId.isNotEmpty ? widget.schoolId : (authService.schoolId ?? '');
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        context.go('/admin/murid');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
            tooltip: 'Kembali ke Daftar Murid',
            onPressed: () => context.go('/admin/murid'),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.school_rounded, color: Color(0xFF4F46E5), size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedAngkatans.isEmpty
                        ? 'Kelulusan Murid'
                        : 'Kelulusan Murid — Angkatan ${_selectedAngkatans.join(', ')}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Proses kelulusan angkatan & nonaktifkan akun murid aktif',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: _isProcessing || _selectedStudentIds.isEmpty
                    ? null
                    : () => _handleGraduateStudents(activeSchoolId, []),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.school_rounded, size: 16),
                label: Text(
                  _selectedStudentIds.isEmpty
                      ? 'Luluskan Siswa'
                      : 'Luluskan (${_selectedStudentIds.length}) Siswa',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  disabledForegroundColor: const Color(0xFF94A3B8),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _adminUserService.streamClasses(activeSchoolId),
          builder: (context, classSnap) {
            final classes = classSnap.data ?? [];
            final Map<String, String> studentClassMap = {};
            for (var c in classes) {
              final cName = c['name'] as String? ?? '-';
              final sIds = c['studentIds'];
              if (sIds is List) {
                for (var sId in sIds) {
                  studentClassMap[sId.toString()] = cName;
                }
              }
            }

            return StreamBuilder<List<Student>>(
              stream: _adminUserService.streamStudents(activeSchoolId),
              builder: (context, studentSnap) {
                if (studentSnap.connectionState == ConnectionState.waiting && !studentSnap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
                }

                final rawStudents = studentSnap.data ?? [];
                // Only consider students that are NOT already graduated
                final availableStudents = rawStudents.where((s) => !s.isGraduated).toList();

                // Compute all available angkatans
                final allAngkatans = availableStudents
                    .map((s) => s.angkatan.trim())
                    .where((a) => a.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort();

                // If no angkatan is currently selected, select the first one by default
                if (_selectedAngkatans.isEmpty && allAngkatans.isNotEmpty) {
                  _selectedAngkatans.add(allAngkatans.first);
                }

                // Filter students by selected angkatan(s)
                final angkatanStudents = availableStudents.where((s) {
                  if (_selectedAngkatans.isEmpty) return true;
                  return _selectedAngkatans.contains(s.angkatan.trim());
                }).toList();

                // Apply search and dropdown filters
                final filteredStudents = angkatanStudents.where((s) {
                  final q = _searchQuery.trim().toLowerCase();
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

                  return true;
                }).toList();

                // Sort
                filteredStudents.sort((a, b) {
                  int cmp = 0;
                  switch (_sortColumn) {
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
                    case 'angkatan':
                      cmp = a.angkatan.compareTo(b.angkatan);
                      break;
                    default:
                      cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                  }
                  return _sortAscending ? cmp : -cmp;
                });

                // Pagination
                final totalItems = filteredStudents.length;
                final totalPages = (totalItems / _rowsPerPage).ceil();
                final currentPage = (_currentPage >= totalPages && totalPages > 0)
                    ? totalPages - 1
                    : _currentPage;
                final pageStart = currentPage * _rowsPerPage;
                final pageEnd = (pageStart + _rowsPerPage < totalItems)
                    ? pageStart + _rowsPerPage
                    : totalItems;
                final paginatedList = (pageStart < totalItems)
                    ? filteredStudents.sublist(pageStart, pageEnd)
                    : <Student>[];

                // Check if all on current page are selected
                final allCurrentPageSelected = paginatedList.isNotEmpty &&
                    paginatedList.every((s) => _selectedStudentIds.contains(s.id));

                final classOptions = [
                  'Semua Kelas',
                  ...studentClassMap.values.where((c) => c.isNotEmpty && c != '-').toSet().toList()..sort(),
                ];

                return Padding(
                  padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Card: Angkatan Selection & Summary
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _buildSummaryItem(
                              icon: Icons.school_rounded,
                              color: const Color(0xFF4F46E5),
                              label: 'Angkatan',
                              value: _selectedAngkatans.isEmpty ? '-' : _selectedAngkatans.join(', '),
                            ),
                            const SizedBox(width: 24),
                            _buildSummaryItem(
                              icon: Icons.people_outline_rounded,
                              color: const Color(0xFF0284C7),
                              label: 'Total Murid di Angkatan',
                              value: '${angkatanStudents.length}',
                            ),
                            const SizedBox(width: 24),
                            _buildSummaryItem(
                              icon: Icons.check_circle_outline_rounded,
                              color: const Color(0xFF10B981),
                              label: 'Murid Terpilih',
                              value: '${_selectedStudentIds.length}',
                            ),
                            const Spacer(),
                                if (_selectedStudentIds.isNotEmpty) ...[
                                  TextButton.icon(
                                    onPressed: () => setState(() => _selectedStudentIds.clear()),
                                    icon: const Icon(Icons.clear_all_rounded, size: 16, color: Color(0xFFE11D48)),
                                    label: Text(
                                      'Batal Pilih Semua',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFFE11D48),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      final filteredIds = filteredStudents.map((s) => s.id).toSet();
                                      if (_selectedStudentIds.containsAll(filteredIds)) {
                                        _selectedStudentIds.removeAll(filteredIds);
                                      } else {
                                        _selectedStudentIds.addAll(filteredIds);
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    _selectedStudentIds.containsAll(filteredStudents.map((s) => s.id).toSet()) &&
                                            filteredStudents.isNotEmpty
                                        ? Icons.deselect_rounded
                                        : Icons.select_all_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _selectedStudentIds.containsAll(filteredStudents.map((s) => s.id).toSet()) &&
                                            filteredStudents.isNotEmpty
                                        ? 'Batal Pilih Semua'
                                        : 'Pilih Semua (${filteredStudents.length})',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF4F46E5),
                                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                      // Search & Filter Bar
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: TextField(
                                controller: _searchController,
                                style: GoogleFonts.inter(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Cari murid berdasarkan nama atau NIS...',
                                  hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 18),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _searchQuery = val;
                                    _currentPage = 0;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Class filter dropdown
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedClassFilter ?? 'Semua Kelas',
                                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                                items: classOptions.map((c) {
                                  return DropdownMenuItem(value: c, child: Text(c));
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedClassFilter = val == 'Semua Kelas' ? null : val;
                                    _currentPage = 0;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Gender filter dropdown
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedGenderFilter ?? 'Semua Gender',
                                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                                items: ['Semua Gender', 'Laki-laki', 'Perempuan'].map((g) {
                                  return DropdownMenuItem(value: g, child: Text(g));
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedGenderFilter = val == 'Semua Gender' ? null : val;
                                    _currentPage = 0;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Students Table
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: filteredStudents.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.school_outlined, size: 48, color: Color(0xFFCBD5E1)),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Tidak ada murid ditemukan',
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF475569),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Tidak ada data murid yang sesuai dengan filter atau pencarian.',
                                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                                            ),
                                          ],
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(minWidth: isDesktop ? screenWidth - 80 : 800),
                                            child: DataTable(
                                              showCheckboxColumn: false,
                                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                              headingTextStyle: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF475569),
                                              ),
                                              dataTextStyle: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: const Color(0xFF1E293B),
                                              ),
                                              columnSpacing: 20,
                                              horizontalMargin: 16,
                                              columns: [
                                                DataColumn(
                                                  label: Checkbox(
                                                    value: allCurrentPageSelected,
                                                    onChanged: (val) {
                                                      setState(() {
                                                        if (val == true) {
                                                          for (var s in paginatedList) {
                                                            _selectedStudentIds.add(s.id);
                                                          }
                                                        } else {
                                                          for (var s in paginatedList) {
                                                            _selectedStudentIds.remove(s.id);
                                                          }
                                                        }
                                                      });
                                                    },
                                                    activeColor: const Color(0xFF4F46E5),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                  ),
                                                ),
                                                DataColumn(
                                                  label: InkWell(
                                                    onTap: () => _onSort('nama'),
                                                    child: Row(
                                                      children: [
                                                        const Text('Nama Murid'),
                                                        const SizedBox(width: 4),
                                                        Icon(
                                                          _sortColumn == 'nama'
                                                              ? (_sortAscending
                                                                  ? Icons.arrow_upward_rounded
                                                                  : Icons.arrow_downward_rounded)
                                                              : Icons.unfold_more_rounded,
                                                          size: 14,
                                                          color: _sortColumn == 'nama'
                                                              ? const Color(0xFF4F46E5)
                                                              : const Color(0xFF94A3B8),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                DataColumn(
                                                  label: InkWell(
                                                    onTap: () => _onSort('nis'),
                                                    child: Row(
                                                      children: [
                                                        const Text('NIS'),
                                                        const SizedBox(width: 4),
                                                        Icon(
                                                          _sortColumn == 'nis'
                                                              ? (_sortAscending
                                                                  ? Icons.arrow_upward_rounded
                                                                  : Icons.arrow_downward_rounded)
                                                              : Icons.unfold_more_rounded,
                                                          size: 14,
                                                          color: _sortColumn == 'nis'
                                                              ? const Color(0xFF4F46E5)
                                                              : const Color(0xFF94A3B8),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                DataColumn(
                                                  label: InkWell(
                                                    onTap: () => _onSort('kelas'),
                                                    child: Row(
                                                      children: [
                                                        const Text('Kelas'),
                                                        const SizedBox(width: 4),
                                                        Icon(
                                                          _sortColumn == 'kelas'
                                                              ? (_sortAscending
                                                                  ? Icons.arrow_upward_rounded
                                                                  : Icons.arrow_downward_rounded)
                                                              : Icons.unfold_more_rounded,
                                                          size: 14,
                                                          color: _sortColumn == 'kelas'
                                                              ? const Color(0xFF4F46E5)
                                                              : const Color(0xFF94A3B8),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const DataColumn(label: Text('Gender')),
                                                const DataColumn(label: Text('Agama')),
                                                const DataColumn(label: Text('Angkatan')),
                                                const DataColumn(label: Text('Status')),
                                              ],
                                              rows: paginatedList.map((s) {
                                                final isSelected = _selectedStudentIds.contains(s.id);
                                                final sClass = studentClassMap[s.id] ?? '-';

                                                return DataRow(
                                                  selected: isSelected,
                                                  onSelectChanged: (val) {
                                                    setState(() {
                                                      if (val == true) {
                                                        _selectedStudentIds.add(s.id);
                                                      } else {
                                                        _selectedStudentIds.remove(s.id);
                                                      }
                                                    });
                                                  },
                                                  cells: [
                                                    DataCell(
                                                      Checkbox(
                                                        value: isSelected,
                                                        onChanged: (val) {
                                                          setState(() {
                                                            if (val == true) {
                                                              _selectedStudentIds.add(s.id);
                                                            } else {
                                                              _selectedStudentIds.remove(s.id);
                                                            }
                                                          });
                                                        },
                                                        activeColor: const Color(0xFF4F46E5),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                        s.displayName,
                                                        style: GoogleFonts.inter(
                                                          fontWeight: FontWeight.w600,
                                                          color: const Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(Text(s.nis)),
                                                    DataCell(
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFF1F5F9),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          sClass,
                                                          style: GoogleFonts.inter(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: const Color(0xFF334155),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(Text(s.gender == 'M' ? 'Laki-laki' : 'Perempuan')),
                                                    DataCell(Text(s.religion)),
                                                    DataCell(
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFEEF2FF),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          s.angkatan,
                                                          style: GoogleFonts.inter(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: const Color(0xFF4F46E5),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: s.isInactive
                                                              ? const Color(0xFFFEF2F2)
                                                              : const Color(0xFFECFDF5),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          s.isInactive ? 'Nonaktif' : 'Aktif',
                                                          style: GoogleFonts.inter(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            color: s.isInactive
                                                                ? const Color(0xFFEF4444)
                                                                : const Color(0xFF10B981),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),

                              // Pagination Bar (10 / 20 / 50)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: const BoxDecoration(
                                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Baris per halaman:',
                                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                        ),
                                        const SizedBox(width: 8),
                                        DropdownButton<int>(
                                          value: _rowsPerPage,
                                          underline: const SizedBox(),
                                          items: const [
                                            DropdownMenuItem(value: 10, child: Text('10')),
                                            DropdownMenuItem(value: 20, child: Text('20')),
                                            DropdownMenuItem(value: 50, child: Text('50')),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _rowsPerPage = val;
                                                _currentPage = 0;
                                              });
                                            }
                                          },
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          totalItems == 0
                                              ? '0 dari 0'
                                              : '${pageStart + 1}-$pageEnd dari $totalItems',
                                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                        ),
                                        const SizedBox(width: 16),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left_rounded, size: 20),
                                          onPressed: currentPage > 0
                                              ? () => setState(() => _currentPage--)
                                              : null,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right_rounded, size: 20),
                                          onPressed: currentPage < totalPages - 1
                                              ? () => setState(() => _currentPage++)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
