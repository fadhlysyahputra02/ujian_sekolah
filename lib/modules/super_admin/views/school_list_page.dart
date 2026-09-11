import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sys_exam_school/core/services/school_service.dart';
import 'package:sys_exam_school/modules/super_admin/views/add_school_page.dart';

class SchoolListPage extends StatefulWidget {
  const SchoolListPage({super.key});

  @override
  State<SchoolListPage> createState() => _SchoolListPageState();
}

class _SchoolListPageState extends State<SchoolListPage> {
  final _firestore = FirebaseFirestore.instance;
  final _schoolService = SchoolService();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _schoolsStream;
  String _searchQuery = '';
  int _rowsPerPage = 10;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    // Cache stream so it is NOT recreated on every build() call.
    // Creating a new stream in build() causes it to reset on every rebuild,
    // which is why data never appears in debug mode.
    _schoolsStream = _firestore.collection('schools').snapshots();
  }

  Future<void> _toggleSchoolStatus(String schoolId, bool currentDisabled) async {
    try {
      await _schoolService.toggleSchoolStatus(
        schoolId: schoolId,
        disabled: !currentDisabled,
      );
      if (mounted) {
        _showSnackBar(
          !currentDisabled
              ? 'Sekolah dinonaktifkan sementara'
              : 'Sekolah berhasil diaktifkan kembali',
          !currentDisabled ? const Color(0xFFEF4444) : const Color(0xFF10B981),
          !currentDisabled ? Icons.pause_circle_rounded : Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Gagal mengubah status sekolah: $e',
          const Color(0xFFEF4444),
          Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _deleteSchool(String schoolId, String schoolName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
            const SizedBox(width: 10),
            Text(
              'Hapus Sekolah',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus sekolah "$schoolName"?\n\nAksi ini akan menghapus semua hak login admin sekolah, guru, dan murid dari sekolah ini secara permanen. Tindakan ini tidak dapat dibatalkan.',
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Batal',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Hapus Permanen',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
        ),
      ),
    );

    try {
      await _schoolService.deleteSchool(schoolId: schoolId);
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        _showSnackBar(
          'Sekolah "$schoolName" berhasil dihapus beserta seluruh akun penggunanya',
          const Color(0xFFDC2626),
          Icons.delete_forever_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        _showSnackBar(
          'Gagal menghapus sekolah: $e',
          const Color(0xFFEF4444),
          Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _showResetPasswordDialog(String schoolId, String schoolName) async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscureText = true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.key_rounded, color: Color(0xFFD97706), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reset Password Admin',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Masukkan password baru untuk admin sekolah "$schoolName".',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passwordController,
                      obscureText: obscureText,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Password Baru',
                        labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                        hintText: 'Minimal 6 karakter',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 20,
                            color: const Color(0xFF64748B),
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureText = !obscureText;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Password tidak boleh kosong';
                        }
                        if (value.trim().length < 6) {
                          return 'Password minimal 6 karakter';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Batal',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final newPassword = passwordController.text.trim();
                      Navigator.pop(context); // close reset dialog

                      // show loading dialog
                      showDialog(
                        context: this.context,
                        barrierDismissible: false,
                        builder: (ctx) => const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
                      );

                      try {
                        await _schoolService.resetSchoolAdminPassword(
                          schoolId: schoolId,
                          newPassword: newPassword,
                        );
                        if (mounted) {
                          Navigator.pop(this.context); // close loading dialog
                          _showSnackBar(
                            'Password admin sekolah "$schoolName" berhasil direset.',
                            const Color(0xFF10B981),
                            Icons.check_circle_rounded,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Navigator.pop(this.context); // close loading dialog
                          _showSnackBar(
                            'Gagal mereset password: $e',
                            const Color(0xFFEF4444),
                            Icons.error_outline_rounded,
                          );
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Simpan',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSnackBar(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openAddSchoolDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddSchoolDialog(),
    );
  }

  Color _getSchoolAvatarColor(String name) {
    final colors = [
      const Color(0xFF4F46E5),
      const Color(0xFF059669),
      const Color(0xFFD97706),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
      const Color(0xFF0284C7),
      const Color(0xFFDB2777),
      const Color(0xFF0891B2),
    ];
    final index = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return colors[index];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Top Bar
          Container(
            color: Colors.white.withValues(alpha: 0.6),
            padding: EdgeInsets.fromLTRB(isDesktop ? 24 : 14, isDesktop ? 20 : 12, isDesktop ? 24 : 14, isDesktop ? 10 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manajemen Sekolah',
                            style: GoogleFonts.inter(
                              fontSize: isDesktop ? 22 : 17,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kelola sekolah terdaftar di platform',
                            style: GoogleFonts.inter(
                              fontSize: isDesktop ? 13 : 11.5,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _openAddSchoolDialog,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(
                        isDesktop ? 'Daftar Sekolah' : 'Tambah',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12, vertical: isDesktop ? 14 : 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Search bar
                Container(
                  height: isDesktop ? 44 : 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() {
                      _searchQuery = v.toLowerCase();
                      _currentPage = 0;
                    }),
                    style: GoogleFonts.inter(fontSize: isDesktop ? 14 : 13, color: const Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Cari nama sekolah atau kode...',
                      hintStyle: GoogleFonts.inter(
                        color: const Color(0xFF94A3B8),
                        fontSize: isDesktop ? 14 : 12.5,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF94A3B8), size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: isDesktop ? 12 : 9),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE2E8F0)),

          // Body
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _schoolsStream,
              builder: (context, snapshot) {
                // Show any error prominently
                if (snapshot.hasError) {
                  return _buildErrorState('Error: ${snapshot.error}\n\nStack: ${snapshot.stackTrace}');
                }

                // Still connecting
                if (snapshot.connectionState == ConnectionState.waiting ||
                    snapshot.connectionState == ConnectionState.none) {
                  return _buildLoadingState();
                }

                // Got data (even if empty)
                final allDocs = snapshot.data?.docs ?? [];

                // Filter out deleted, apply search
                var schools = allDocs.where((s) {
                  final data = s.data();
                  if (data['deleted'] == true) return false;
                  if (_searchQuery.isNotEmpty) {
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final code = (data['code'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) || code.contains(_searchQuery);
                  }
                  return true;
                }).toList();

                // Sort newest first
                schools.sort((a, b) {
                  final aTs = a.data()['createdAt'];
                  final bTs = b.data()['createdAt'];
                  int toMs(dynamic ts) {
                    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
                    return 0;
                  }
                  return toMs(bTs).compareTo(toMs(aTs));
                });

                if (schools.isEmpty && _searchQuery.isEmpty) {
                  return _buildEmptyState();
                }
                if (schools.isEmpty) {
                  return _buildNoResultState();
                }
                // Calculate pagination
                final totalSchools = schools.length;
                final totalPages = (totalSchools / _rowsPerPage).ceil();

                if (_currentPage >= totalPages && totalPages > 0) {
                  _currentPage = totalPages - 1;
                }

                final startIndex = _currentPage * _rowsPerPage;
                final endIndex = (startIndex + _rowsPerPage > totalSchools)
                    ? totalSchools
                    : startIndex + _rowsPerPage;

                final pagedSchools = totalSchools > 0
                    ? schools.sublist(startIndex, endIndex)
                    : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                return isDesktop
                    ? _buildDesktopView(pagedSchools, totalSchools, totalPages, startIndex, endIndex)
                    : _buildMobileView(pagedSchools, totalSchools, totalPages, startIndex, endIndex);
              },
            ),

          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PAGINATION BAR WIDGET
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPaginationBar({
    required int totalSchools,
    required int totalPages,
    required int startIndex,
    required int endIndex,
    required bool isDesktop,
  }) {
    final displayStart = totalSchools > 0 ? startIndex + 1 : 0;
    final displayEnd = endIndex;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 20 : 12,
        vertical: isDesktop ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: isDesktop
            ? const Border(top: BorderSide(color: Color(0xFFE2E8F0)))
            : Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: isDesktop
            ? const BorderRadius.vertical(bottom: Radius.circular(18))
            : BorderRadius.circular(14),
      ),
      child: isDesktop
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: Dropdown per page
                Row(
                  children: [
                    Text(
                      'Tampilkan:',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _rowsPerPage,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                          isDense: true,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                          items: const [10, 20, 50, 100].map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value per halaman'),
                            );
                          }).toList(),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _rowsPerPage = newValue;
                                _currentPage = 0;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Menampilkan $displayStart–$displayEnd dari $totalSchools sekolah',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                // Right: Page navigation
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      iconSize: 22,
                      color: const Color(0xFF475569),
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage--)
                          : null,
                      tooltip: 'Halaman Sebelumnya',
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Halaman ${_currentPage + 1} dari ${totalPages == 0 ? 1 : totalPages}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      iconSize: 22,
                      color: const Color(0xFF475569),
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage++)
                          : null,
                      tooltip: 'Halaman Selanjutnya',
                    ),
                  ],
                ),
              ],
            )
          : Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$displayStart–$displayEnd dari $totalSchools sekolah',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Tampil: ',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _rowsPerPage,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                              isDense: true,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                              items: const [10, 20, 50, 100].map((int value) {
                                return DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                );
                              }).toList(),
                              onChanged: (int? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _rowsPerPage = newValue;
                                    _currentPage = 0;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage--)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded, size: 16),
                      label: Text('Sebelumnya', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage++)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded, size: 16),
                      label: Text('Selanjutnya', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DESKTOP TABLE VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> schools,
    int totalSchools,
    int totalPages,
    int startIndex,
    int endIndex,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Give the table a concrete bounded width so that Expanded
          // children inside Row headers/rows work correctly.
          // Without this, ConstrainedBox(minWidth) inside a horizontal
          // SingleChildScrollView gives the Column an *unbounded* max
          // width, causing all Expanded columns to collapse.
          final tableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : (MediaQuery.of(context).size.width > 1100
                  ? MediaQuery.of(context).size.width - 280
                  : 1000.0);

          return Container(
            width: tableWidth,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildTableHeader('Sekolah', flex: 4),
                      _buildTableHeader('Kode', flex: 2),
                      _buildTableHeader('Admin Email', flex: 3),
                      _buildTableHeader('Batas Kuota', flex: 3),
                      _buildTableHeader('Status', flex: 2),
                      _buildTableHeader('Kontrol', flex: 3),
                    ],
                  ),
                ),
                // Rows
                ...schools.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final doc = entry.value;
                  final data = doc.data();
                  final meta = data['meta'] as Map<String, dynamic>? ?? {};
                  final teacherCount = meta['teacherCount'] ?? 0;
                  final studentCount = meta['studentCount'] ?? 0;
                  final maxTeacherQuota = data['maxTeacherQuota'] ?? 50;
                  final maxStudentQuota = data['maxStudentQuota'] ?? 500;
                  final disabled = data['disabled'] == true;
                  final name = data['name'] ?? '-';

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: idx % 2 == 0 ? Colors.white : const Color(0xFFFAFAFC),
                      border: const Border(
                        bottom: BorderSide(color: Color(0xFFF1F5F9)),
                      ),
                    ),
                    child: Row(
                      children: [
                        // School name
                        Expanded(
                          flex: 4,
                          child: Text(
                            name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Code badge
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                data['code'] ?? '-',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: const Color(0xFF334155),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            data['adminEmail'] ?? '-',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Quota info column
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Guru: $teacherCount / $maxTeacherQuota',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: teacherCount >= maxTeacherQuota
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Murid: $studentCount / $maxStudentQuota',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: studentCount >= maxStudentQuota
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _buildStatusBadge(disabled),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Switch.adaptive(
                                value: !disabled,
                                activeTrackColor: const Color(0xFF10B981),
                                onChanged: (_) => _toggleSchoolStatus(doc.id, disabled),
                              ),
                              IconButton(
                                icon: const Icon(Icons.tune_rounded,
                                    color: Color(0xFF4F46E5), size: 20),
                                tooltip: 'Atur Kuota Sekolah',
                                onPressed: () => _showEditQuotaDialog(
                                    doc.id, name, maxStudentQuota, maxTeacherQuota),
                              ),
                              IconButton(
                                icon: const Icon(Icons.key_rounded,
                                    color: Color(0xFFD97706), size: 20),
                                tooltip: 'Reset Password Admin',
                                onPressed: () => _showResetPasswordDialog(doc.id, name),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Color(0xFFDC2626), size: 20),
                                tooltip: 'Hapus Sekolah',
                                onPressed: () => _deleteSchool(doc.id, name),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                // Bottom Pagination Bar
                _buildPaginationBar(
                  totalSchools: totalSchools,
                  totalPages: totalPages,
                  startIndex: startIndex,
                  endIndex: endIndex,
                  isDesktop: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: const Color(0xFF475569),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOBILE CARD VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileView(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> schools,
    int totalSchools,
    int totalPages,
    int startIndex,
    int endIndex,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: schools.length,
            itemBuilder: (context, index) {
              final doc = schools[index];
              final data = doc.data();
              final meta = data['meta'] as Map<String, dynamic>? ?? {};
              final teacherCount = meta['teacherCount'] ?? 0;
              final studentCount = meta['studentCount'] ?? 0;
              final maxTeacherQuota = data['maxTeacherQuota'] ?? 50;
              final maxStudentQuota = data['maxStudentQuota'] ?? 500;
              final disabled = data['disabled'] == true;
              final name = data['name'] ?? '-';
              final avatarColor = _getSchoolAvatarColor(name);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: avatarColor.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: avatarColor.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Card header with avatar, school name & code
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: avatarColor.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        border: Border(
                          bottom: BorderSide(
                            color: avatarColor.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    data['code'] ?? '-',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF475569),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildStatusBadge(disabled),
                        ],
                      ),
                    ),

                    // Card body info
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.email_outlined,
                                  size: 15, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  data['adminEmail'] ?? '-',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: const Color(0xFF64748B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Quota pills
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatPill(
                                  Icons.group_rounded,
                                  'Guru: $teacherCount/$maxTeacherQuota',
                                  teacherCount >= maxTeacherQuota
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF4F46E5),
                                  teacherCount >= maxTeacherQuota
                                      ? const Color(0xFFFEF2F2)
                                      : const Color(0xFFF5F3FF),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildStatPill(
                                  Icons.school_rounded,
                                  'Murid: $studentCount/$maxStudentQuota',
                                  studentCount >= maxStudentQuota
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF0284C7),
                                  studentCount >= maxStudentQuota
                                      ? const Color(0xFFFEF2F2)
                                      : const Color(0xFFEFF6FF),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Card footer action bar (ALL features accessible)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFAFAFC),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        border: Border(
                          top: BorderSide(color: Color(0xFFF1F5F9)),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Status toggle switch
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch.adaptive(
                                value: !disabled,
                                activeTrackColor: const Color(0xFF10B981),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (_) => _toggleSchoolStatus(doc.id, disabled),
                              ),
                              Text(
                                disabled ? 'Nonaktif' : 'Aktif',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: disabled
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Action buttons
                          Row(
                            children: [
                              // Atur Kuota
                              IconButton(
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                color: const Color(0xFF4F46E5),
                                tooltip: 'Atur Kuota',
                                onPressed: () => _showEditQuotaDialog(
                                    doc.id, name, maxStudentQuota, maxTeacherQuota),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(7),
                                  backgroundColor: const Color(0xFFEEF2FF),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Reset Password Admin
                              IconButton(
                                icon: const Icon(Icons.key_rounded, size: 18),
                                color: const Color(0xFFD97706),
                                tooltip: 'Reset Password Admin',
                                onPressed: () => _showResetPasswordDialog(doc.id, name),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(7),
                                  backgroundColor: const Color(0xFFFFFBEB),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Color(0xFFFDE68A)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Hapus Sekolah
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                color: const Color(0xFFDC2626),
                                tooltip: 'Hapus Sekolah',
                                onPressed: () => _deleteSchool(doc.id, name),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(7),
                                  backgroundColor: const Color(0xFFFEF2F2),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Color(0xFFFECACA)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Pagination bar at bottom of mobile view
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _buildPaginationBar(
            totalSchools: totalSchools,
            totalPages: totalPages,
            startIndex: startIndex,
            endIndex: endIndex,
            isDesktop: false,
          ),
        ),
      ],
    );
  }

  Widget _buildStatPill(IconData icon, String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool disabled) {
    final isActive = !disabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                    .withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFF0FDF4)
                : const Color(0xFFFFF5F5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
            ),
          ),
          child: Text(
            isActive ? 'Aktif' : 'Nonaktif',
            style: GoogleFonts.inter(
              color: isActive ? const Color(0xFF059669) : const Color(0xFFDC2626),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATES
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
    );
  }

  void _showEditQuotaDialog(String schoolId, String schoolName, int currentMaxStudent, int currentMaxTeacher) {
    final studentCtrl = TextEditingController(text: '$currentMaxStudent');
    final teacherCtrl = TextEditingController(text: '$currentMaxTeacher');
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFF4F46E5)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Atur Kuota - $schoolName',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: teacherCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Batas Kuota Maksimal Guru',
                    prefixIcon: const Icon(Icons.group_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                    if (int.tryParse(v.trim()) == null) return 'Angka saja';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: studentCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Batas Kuota Maksimal Murid',
                    prefixIcon: const Icon(Icons.school_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                    if (int.tryParse(v.trim()) == null) return 'Angka saja';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);
                        try {
                          await _schoolService.updateSchoolQuota(
                            schoolId: schoolId,
                            maxStudentQuota: int.parse(studentCtrl.text.trim()),
                            maxTeacherQuota: int.parse(teacherCtrl.text.trim()),
                          );
                          if (mounted) {
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Kuota sekolah berhasil diperbarui!'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Gagal memperbarui kuota: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          setDialogState(() => isSaving = false);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(
            'Terjadi kesalahan',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.business_outlined,
              size: 56,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Belum ada sekolah terdaftar',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Daftarkan sekolah pertama ke ekosistem SesiCermat.',
            style: GoogleFonts.inter(
              color: const Color(0xFF64748B),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openAddSchoolDialog,
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Daftarkan Sekolah',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            'Tidak ada hasil untuk "$_searchQuery"',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}
