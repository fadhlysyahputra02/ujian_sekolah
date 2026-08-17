import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/school_service.dart';
import 'add_school_page.dart';

class SchoolListPage extends StatefulWidget {
  const SchoolListPage({super.key});

  @override
  State<SchoolListPage> createState() => _SchoolListPageState();
}

class _SchoolListPageState extends State<SchoolListPage> {
  final SchoolService _schoolService = SchoolService();
  String _searchQuery = '';

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

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
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
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
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
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kelola semua sekolah yang terdaftar di SesiCermat',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _openAddSchoolDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        'Daftar Sekolah',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search bar
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Cari nama sekolah atau kode...',
                      hintStyle: GoogleFonts.inter(
                        color: const Color(0xFF94A3B8),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF94A3B8), size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
              stream: _schoolService.getSchoolsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }

                var schools = snapshot.data?.docs ?? [];

                // Apply search and deleted filters
                schools = schools.where((s) {
                  final data = s.data();
                  if (data['deleted'] == true) return false;
                  if (_searchQuery.isNotEmpty) {
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final code = (data['code'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) || code.contains(_searchQuery);
                  }
                  return true;
                }).toList();

                if (schools.isEmpty && _searchQuery.isEmpty) {
                  return _buildEmptyState();
                }
                if (schools.isEmpty) {
                  return _buildNoResultState();
                }

                return isDesktop
                    ? _buildDesktopView(schools)
                    : _buildMobileView(schools);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DESKTOP TABLE VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopView(List<QueryDocumentSnapshot<Map<String, dynamic>>> schools) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
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
                  _buildTableHeader('Sekolah', flex: 3),
                  _buildTableHeader('Kode', flex: 1),
                  _buildTableHeader('Admin Email', flex: 3),
                  _buildTableHeader('Pengguna', flex: 2),
                  _buildTableHeader('Status', flex: 2),
                  _buildTableHeader('Kontrol', flex: 2),
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
              final disabled = data['disabled'] == true;
              final name = data['name'] ?? '-';
              final avatarColor = _getSchoolAvatarColor(name);

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
                    // School name with avatar
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: avatarColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: avatarColor.withValues(alpha: 0.25),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _getInitials(name),
                              style: GoogleFonts.inter(
                                color: avatarColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
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
                        ],
                      ),
                    ),
                    // Code badge
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          data['code'] ?? '-',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: const Color(0xFF475569),
                            letterSpacing: 0.5,
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
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          _buildMiniStat(
                            Icons.person_rounded,
                            '$teacherCount',
                            const Color(0xFF4F46E5),
                          ),
                          const SizedBox(width: 8),
                          _buildMiniStat(
                            Icons.school_rounded,
                            '$studentCount',
                            const Color(0xFF06B6D4),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _buildStatusBadge(disabled),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Switch.adaptive(
                            value: !disabled,
                            activeTrackColor: const Color(0xFF10B981),
                            onChanged: (_) => _toggleSchoolStatus(doc.id, disabled),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.key_rounded, color: Color(0xFFD97706), size: 20),
                            tooltip: 'Reset Password Admin',
                            onPressed: () => _showResetPasswordDialog(doc.id, name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 20),
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
          ],
        ),
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

  Widget _buildMiniStat(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOBILE CARD VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileView(List<QueryDocumentSnapshot<Map<String, dynamic>>> schools) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: schools.length,
      itemBuilder: (context, index) {
        final doc = schools[index];
        final data = doc.data();
        final meta = data['meta'] as Map<String, dynamic>? ?? {};
        final teacherCount = meta['teacherCount'] ?? 0;
        final studentCount = meta['studentCount'] ?? 0;
        final disabled = data['disabled'] == true;
        final name = data['name'] ?? '-';
        final avatarColor = _getSchoolAvatarColor(name);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: avatarColor.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: avatarColor.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Card header with avatar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: avatarColor.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border(
                    bottom: BorderSide(
                      color: avatarColor.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            avatarColor,
                            avatarColor.withValues(alpha: 0.75),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: avatarColor.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _getInitials(name),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
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
                        ],
                      ),
                    ),
                    _buildStatusBadge(disabled),
                  ],
                ),
              ),

              // Card body
              Padding(
                padding: const EdgeInsets.all(16),
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
                              fontSize: 13,
                              color: const Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatPill(
                            Icons.person_rounded,
                            '$teacherCount Guru',
                            const Color(0xFF4F46E5),
                            const Color(0xFFF5F3FF),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatPill(
                            Icons.school_rounded,
                            '$studentCount Murid',
                            const Color(0xFF0284C7),
                            const Color(0xFFEFF6FF),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: disabled
                                ? const Color(0xFFFEF2F2)
                                : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: disabled
                                  ? const Color(0xFFFECACA)
                                  : const Color(0xFFBBF7D0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
                                child: Text(
                                  disabled ? 'Nonaktif' : 'Aktif',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: disabled
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF059669),
                                  ),
                                ),
                              ),
                              Switch.adaptive(
                                value: !disabled,
                                activeTrackColor: const Color(0xFF10B981),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (_) => _toggleSchoolStatus(doc.id, disabled),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.key_rounded, color: Color(0xFFD97706), size: 20),
                          onPressed: () => _showResetPasswordDialog(doc.id, name),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(8),
                            backgroundColor: const Color(0xFFFFFBEB),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Color(0xFFFDE68A)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 20),
                          onPressed: () => _deleteSchool(doc.id, name),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(8),
                            backgroundColor: const Color(0xFFFEF2F2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
