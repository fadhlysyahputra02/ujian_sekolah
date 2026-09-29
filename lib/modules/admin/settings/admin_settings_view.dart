import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../widgets/report_bug_dialog.dart';

class AdminSettingsView extends StatefulWidget {
  final String schoolId;

  const AdminSettingsView({
    super.key,
    required this.schoolId,
  });

  @override
  State<AdminSettingsView> createState() => _AdminSettingsViewState();
}

class _AdminSettingsViewState extends State<AdminSettingsView> {
  final AdminUserService _adminUserService = AdminUserService();
  DocumentSnapshot? _cachedSchoolSnapshot;

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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return _buildSettingsTab(authService, widget.schoolId);
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
                                          const SizedBox(height: 16),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (context) => ReportBugDialog(
                                                  schoolId: schoolId,
                                                  schoolName: schoolName,
                                                  schoolCode: schoolCode,
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.bug_report, size: 16),
                                            label: const Text('Laporkan Bug'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: const Color(0xFF4338CA),
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


}
