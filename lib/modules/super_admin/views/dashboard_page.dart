import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:sys_exam_school/core/services/auth_service.dart';
import 'package:sys_exam_school/core/services/school_service.dart';
import 'package:sys_exam_school/core/constants/app_version.dart';
import 'package:sys_exam_school/core/services/app_update_service.dart';
import 'package:sys_exam_school/core/widgets/app_release_manager_dialog.dart';
import 'package:sys_exam_school/core/widgets/app_splash_loader.dart';
import 'package:sys_exam_school/modules/super_admin/views/school_list_page.dart';

class DashboardPage extends StatefulWidget {
  final String? tabName;
  const DashboardPage({super.key, this.tabName});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final SchoolService _schoolService = SchoolService();
  DateTime? _lastBackPressTime;

  // SchoolListPage is kept alive as a late final field so it is never rebuilt
  // when the dashboard re-renders. This preserves the Firestore stream.
  late final Widget _schoolListPage;

  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _schoolListPage = const SchoolListPage();
    _updateTabFromWidget();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndShowUpdateDialog(context);
      }
    });
  }

  @override
  void didUpdateWidget(DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabName != oldWidget.tabName) {
      _updateTabFromWidget();
    }
  }

  void _updateTabFromWidget() {
    setState(() {
      switch (widget.tabName) {
        case 'ringkasan': _selectedIndex = 0; break;
        case 'sekolah': _selectedIndex = 1; break;
        case 'pengaturan': _selectedIndex = 2; break;
        default: _selectedIndex = 0;
      }
    });
  }

  void _navigateToTab(int index) {
    String path;
    switch (index) {
      case 0: path = 'ringkasan'; break;
      case 1: path = 'sekolah'; break;
      case 2: path = 'pengaturan'; break;
      default: path = 'ringkasan';
    }
    context.go('/superadmin/$path');
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  final List<_NavItem> _navItems = const [
    _NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      label: 'Ringkasan',
    ),
    _NavItem(
      icon: Icons.business_outlined,
      activeIcon: Icons.business_rounded,
      label: 'Sekolah',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Pengaturan',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    if (authService.isLoading) {
      return const AppSplashScreen(
        title: 'SesiCermat SuperAdmin',
        subtitle: 'Memuat sesi super admin...',
      );
    }
    if (authService.role != 'super_admin') {
      return const Scaffold(
        body: Center(
          child: Text('Akses Ditolak: Halaman ini hanya untuk Super Admin.'),
        ),
      );
    }
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    // Overview and Settings are lightweight and can rebuild each time.
    // SchoolListPage is kept alive via _schoolListPage (late final field in initState).
    final settingsWidget = _buildSettingsContent(authService);
    final overviewWidget = _buildOverviewContent();

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

    // Use IndexedStack to keep all pages alive (preserves Firestore streams)
    final pageStack = IndexedStack(
      index: _selectedIndex,
      children: [
        overviewWidget,
        _schoolListPage,
        settingsWidget,
      ],
    );

    final mainScaffold = isDesktop
        ? Scaffold(
            body: Row(
              children: [
                _buildSidebar(authService, size),
                Expanded(
                  child: Container(
                    decoration: backgroundGradient,
                    child: pageStack,
                  ),
                ),
              ],
            ),
          )
        : Scaffold(
            appBar: _buildMobileAppBar(authService),
            body: Container(
              decoration: backgroundGradient,
              child: pageStack,
            ),
            bottomNavigationBar: _buildBottomNav(),
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
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
      child: mainScaffold,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SIDEBAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSidebar(AuthService authService, Size size) {
    final extended = size.width > 1100;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: extended ? 240 : 72,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo area
          Container(
            height: 72,
            padding: EdgeInsets.symmetric(
              horizontal: extended ? 20 : 0,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            child: extended
                ? Row(
                    children: [
                      _buildLogoIcon(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'SesiCermat',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Super Admin',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF818CF8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Center(child: _buildLogoIcon()),
          ),

          const SizedBox(height: 16),

          // Nav items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: _navItems.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return _buildSidebarItem(item, idx, extended);
                }).toList(),
              ),
            ),
          ),

          // Logout button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
              ),
            ),
            child: extended
                ? _buildLogoutTile(authService, extended: true)
                : _buildLogoutTile(authService, extended: false),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoIcon() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset('assets/images/Logo_SesiCermat.png', width: 40, height: 40, fit: BoxFit.cover),
    );
  }

  Widget _buildSidebarItem(_NavItem item, int idx, bool extended) {
    final isSelected = _selectedIndex == idx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => _navigateToTab(idx),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: extended ? 14 : 0,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4F46E5).withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            mainAxisAlignment:
                extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? item.activeIcon : item.icon,
                color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF64748B),
                size: 22,
              ),
              if (extended) ...[
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: GoogleFonts.inter(
                    color:
                        isSelected ? const Color(0xFFE0E7FF) : const Color(0xFF94A3B8),
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF818CF8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutTile(AuthService authService, {required bool extended}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => authService.confirmAndSignOut(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: extended ? 14 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.logout_rounded,
                      color: Color(0xFFFCA5A5), size: 16),
                ),
                if (extended) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Keluar',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFCA5A5),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppVersion.version,
          style: GoogleFonts.inter(
            color: const Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOBILE APP BAR & DRAWER
  // ─────────────────────────────────────────────────────────────────────────
  AppBar _buildMobileAppBar(AuthService authService) {
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
        child: _buildLogoIcon(),
      ),
      leadingWidth: 48,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SesiCermat',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Text(
                  'SuperAdmin',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF4F46E5)),
                ),
              ),
            ],
          ),
          Text(
            _selectedIndex == 0 ? 'Ringkasan Sistem' : (_selectedIndex == 1 ? 'Manajemen Sekolah' : 'Pengaturan Panel'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11, color: const Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
          tooltip: 'Keluar',
          onPressed: () => authService.confirmAndSignOut(context),
        ),
        const SizedBox(width: 4),
      ],
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F172A),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE2E8F0)),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(color: Color(0x0C000000), blurRadius: 10, offset: Offset(0, -3)),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (idx) => _navigateToTab(idx),
        selectedItemColor: const Color(0xFF4F46E5),
        unselectedItemColor: const Color(0xFF94A3B8),
        backgroundColor: Colors.white,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
        items: _navItems.map((item) {
          return BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Icon(item.icon, size: 20),
            ),
            activeIcon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.activeIcon, size: 20, color: const Color(0xFF4F46E5)),
            ),
            label: item.label,
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OVERVIEW CONTENT
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOverviewContent() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _schoolService.getSchoolsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppContentLoader(
            title: 'Memuat Dashboard Super Admin...',
            subtitle: 'Mengambil statistik real-time ekosistem sekolah',
          );
        }

        final schools = snapshot.data?.docs ?? [];
        final int totalSchools = schools.length;
        final int activeSchools =
            schools.where((s) => s.data()['disabled'] != true).length;
        final int inactiveSchools = totalSchools - activeSchools;

        int totalTeachers = 0;
        int totalStudents = 0;
        for (var s in schools) {
          final meta = s.data()['meta'] as Map<String, dynamic>? ?? {};
          totalTeachers += (meta['teacherCount'] ?? 0) as int;
          totalStudents += (meta['studentCount'] ?? 0) as int;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 768;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(isDesktop ? 28.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. HERO HEADER BANNER
                    _buildHeroBanner(isDesktop),
                    const SizedBox(height: 28),

                    // 2. RINGKASAN KPI CARDS
                    _buildSectionHeader(
                      'Statistik Ekosistem',
                      'Metrik real-time pengguna dan status sekolah terdaftar.',
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, gridConstraints) {
                        final gridWidth = gridConstraints.maxWidth;
                        final isMobile = gridWidth < 600;
                        final crossCount = gridWidth > 1100 ? 5 : (gridWidth > 700 ? 3 : 2);

                        return GridView.count(
                          crossAxisCount: crossCount,
                          crossAxisSpacing: isMobile ? 10 : 16,
                          mainAxisSpacing: isMobile ? 10 : 16,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: gridWidth > 1100 ? 1.25 : (gridWidth > 700 ? 1.35 : 1.38),
                          children: [
                            _buildEleganceKpiCard(
                              title: 'Total Sekolah',
                              count: '$totalSchools',
                              subtitle: 'Sekolah Terdaftar',
                              icon: Icons.business_rounded,
                              color: const Color(0xFF4F46E5),
                              gradientColors: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
                              onTap: () => _navigateToTab(1),
                            ),
                            _buildEleganceKpiCard(
                              title: 'Sekolah Aktif',
                              count: '$activeSchools',
                              subtitle: 'Penyelenggara Aktif',
                              icon: Icons.check_circle_rounded,
                              color: const Color(0xFF10B981),
                              gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
                              onTap: () => _navigateToTab(1),
                            ),
                            _buildEleganceKpiCard(
                              title: 'Nonaktif',
                              count: '$inactiveSchools',
                              subtitle: 'Perlu Perhatian',
                              icon: Icons.cancel_rounded,
                              color: const Color(0xFFEF4444),
                              gradientColors: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                              onTap: () => _navigateToTab(1),
                            ),
                            _buildEleganceKpiCard(
                              title: 'Total Guru',
                              count: '$totalTeachers',
                              subtitle: 'Tenaga Pendidik',
                              icon: Icons.assignment_ind_rounded,
                              color: const Color(0xFFF59E0B),
                              gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                              onTap: () => _navigateToTab(1),
                            ),
                            _buildEleganceKpiCard(
                              title: 'Total Murid',
                              count: '$totalStudents',
                              subtitle: 'Siswa Aktif Terdaftar',
                              icon: Icons.school_rounded,
                              color: const Color(0xFF06B6D4),
                              gradientColors: const [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
                              onTap: () => _navigateToTab(1),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // 3. AKTIVITAS & AKSES CEPAT
                    _buildSectionHeader(
                      'Aktivitas & Akses Cepat',
                      'Akses langsung ke manajemen sekolah dan pengaturan platform.',
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, actConstraints) {
                        final actWidth = actConstraints.maxWidth;
                        final isMobile = actWidth < 600;
                        final actCrossCount = actWidth > 900 ? 3 : (actWidth > 550 ? 2 : 1);

                        return GridView.count(
                          crossAxisCount: actCrossCount,
                          crossAxisSpacing: isMobile ? 10 : 16,
                          mainAxisSpacing: isMobile ? 10 : 16,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: actWidth > 900 ? 2.1 : (actWidth < 600 ? 3.0 : 2.5),
                          children: [
                            _buildEleganceActionCard(
                              title: 'Daftarkan Sekolah Baru',
                              desc: 'Tambah sekolah baru ke ekosistem SesiCermat',
                              icon: Icons.domain_add_rounded,
                              color: const Color(0xFF4F46E5),
                              gradientColors: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
                              onTap: () => _navigateToTab(1),
                            ),
                            _buildEleganceActionCard(
                              title: 'Kelola Status Sekolah',
                              desc: 'Aktifkan, nonaktifkan, atau atur akun sekolah',
                              icon: Icons.store_rounded,
                              color: const Color(0xFF06B6D4),
                              gradientColors: const [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
                              onTap: () => _navigateToTab(1),
                            ),
                            _buildEleganceActionCard(
                              title: 'Pengaturan Kredensial',
                              desc: 'Kelola profil & ubah kata sandi Super Admin',
                              icon: Icons.shield_rounded,
                              color: const Color(0xFF10B981),
                              gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
                              onTap: () => _navigateToTab(2),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // 4. DAFTAR SEKOLAH TERDAFTAR TERBARU
                    _buildSectionHeader(
                      'Ringkasan Ekosistem Sekolah',
                      'Daftar sekolah terdaftar dan statistik singkat.',
                    ),
                    const SizedBox(height: 14),
                    _buildRecentSchoolsSection(schools, isDesktop),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeroBanner(bool isDesktop) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isDesktop ? 28 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1B4B).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF818CF8).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Color(0xFF818CF8),
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'PORTAL SUPER ADMIN',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF818CF8),
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Sistem Online',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Ringkasan Ekosistem SesiCermat',
            style: GoogleFonts.inter(
              fontSize: isDesktop ? 26 : 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pantau statistik real-time, status sekolah terdaftar, dan kendalikan platform dari satu panel.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeaderChip(Icons.shield_rounded, 'Peran: Super Admin'),
              _buildHeaderChip(Icons.cloud_done_rounded, 'Firebase Production Cluster'),
              _buildHeaderChip(Icons.speed_rounded, 'Multi-Tenant Engine'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFC7D2FE), size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: const Color(0xFFE0E7FF),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
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

  Widget _buildRecentSchoolsSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> schools,
    bool isDesktop,
  ) {
    if (schools.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.business_center_outlined, size: 48, color: Color(0xFF94A3B8)),
              const SizedBox(height: 12),
              Text(
                'Belum Ada Sekolah Terdaftar',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF334155)),
              ),
              const SizedBox(height: 4),
              Text(
                'Klik menu "Sekolah" untuk mendaftarkan sekolah pertama.',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school_rounded, color: Color(0xFF4F46E5), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Daftar Sekolah Terdaftar (${schools.length})',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _navigateToTab(1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text('Lihat Semua', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF4F46E5)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: schools.length > 5 ? 5 : schools.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              final data = schools[index].data();
              final name = data['name'] ?? 'Sekolah Baru';
              final code = data['code'] ?? '-';
              final adminEmail = data['adminEmail'] ?? '-';
              final disabled = data['disabled'] == true;
              final meta = data['meta'] as Map<String, dynamic>? ?? {};
              final teachers = meta['teacherCount'] ?? 0;
              final students = meta['studentCount'] ?? 0;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: disabled
                          ? [const Color(0xFF94A3B8), const Color(0xFF64748B)]
                          : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$code',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.email_outlined, size: 13, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(adminEmail, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text('$teachers Guru • $students Murid', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: disabled ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: disabled ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7)),
                      ),
                      child: Text(
                        disabled ? 'Nonaktif' : 'Aktif',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: disabled ? const Color(0xFFDC2626) : const Color(0xFF059669),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                  ],
                ),
                onTap: () => _navigateToTab(1),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent(AuthService authService) {
    return _SuperAdminSettingsWidget(authService: authService);
  }
}

class _SuperAdminSettingsWidget extends StatefulWidget {
  final AuthService authService;
  const _SuperAdminSettingsWidget({required this.authService});

  @override
  State<_SuperAdminSettingsWidget> createState() => _SuperAdminSettingsWidgetState();
}

class _SuperAdminSettingsWidgetState extends State<_SuperAdminSettingsWidget> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _usernameFormKey = GlobalKey<FormState>();
  final SchoolService _schoolService = SchoolService();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSavingPassword = false;
  bool _isSavingUsername = false;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadCurrentUsername();
  }

  Future<void> _loadCurrentUsername() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists && mounted) {
          final uName = userDoc.data()?['customUsername'] as String?;
          if (uName != null && uName.isNotEmpty) {
            setState(() {
              _currentUsername = uName;
              _usernameController.text = uName;
            });
            return;
          }
        }
      }

      final doc = await FirebaseFirestore.instance.collection('system_settings').doc('super_admin').get();
      if (doc.exists && mounted) {
        setState(() {
          _currentUsername = doc.data()?['username'] as String?;
          if (_currentUsername != null && _currentUsername!.isNotEmpty) {
            _usernameController.text = _currentUsername!;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = widget.authService.user?.email ?? '';
    final initialLetter = userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'S';

    // Header Banner
    final headerBanner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1B4B).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pengaturan Akun & Keamanan',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Kelola profil super admin, kredensial login, dan parameter keamanan platform.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
            ),
            child: Row(
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
                const SizedBox(width: 6),
                Text(
                  'Sistem Aktif',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6EE7B7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Profile Card
    final profileCard = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF818CF8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x334F46E5),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initialLetter,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF10B981),
                      size: 18,
                    ),
                  ),
                ],
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
                        fontWeight: FontWeight.w800,
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
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Text(
                        'Role: Super Admin Platform',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
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
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 20),
          _buildInfoRow(
            Icons.alternate_email_rounded,
            'Username Default',
            'sadmin',
            const Color(0xFF4F46E5),
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            Icons.account_circle_rounded,
            'Username Aktif',
            _currentUsername ?? 'sadmin',
            const Color(0xFF059669),
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            Icons.security_rounded,
            'Hak Akses Root',
            'Full System Control',
            const Color(0xFF7C3AED),
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            Icons.check_circle_rounded,
            'Status Akun',
            'Aktif & Terverifikasi',
            const Color(0xFF10B981),
          ),
        ],
      ),
    );

    // Change Username Card
    final changeUsernameCard = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _usernameFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: Color(0xFF059669),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ubah Username Super Admin',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Username baru dapat digunakan sebagai alternatif login.',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _usernameController,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                labelText: 'Username Baru',
                labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                hintText: 'Masukkan username alfanumerik (min. 3 karakter)',
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
                  borderSide: const BorderSide(color: Color(0xFF059669), width: 1.8),
                ),
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: Color(0xFF059669)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Username tidak boleh kosong';
                if (val.trim().length < 3) return 'Username minimal 3 karakter';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingUsername
                    ? null
                    : () async {
                        if (_usernameFormKey.currentState!.validate()) {
                          setState(() => _isSavingUsername = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await _schoolService.updateSuperAdminUsername(_usernameController.text.trim());
                            setState(() => _currentUsername = _usernameController.text.trim());
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Username SuperAdmin berhasil diperbarui!',
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
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Gagal memperbarui username: $e'),
                                  backgroundColor: const Color(0xFFEF4444),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSavingUsername = false);
                          }
                        }
                      },
                icon: _isSavingUsername
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  _isSavingUsername ? 'Menyimpan...' : 'Simpan Username Baru',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Change Password Card
    final changePasswordCard = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
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
                    Icons.lock_rounded,
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
                        'Ubah Kata Sandi',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Perbarui kata sandi secara berkala untuk menjaga keamanan.',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
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
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
                ),
                prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20, color: Color(0xFF4F46E5)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: const Color(0xFF64748B),
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Kata sandi baru tidak boleh kosong';
                if (value.trim().length < 6) return 'Kata sandi minimal 6 karakter';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
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
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
                ),
                prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 20, color: Color(0xFF4F46E5)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: const Color(0xFF64748B),
                  ),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Konfirmasi kata sandi tidak boleh kosong';
                if (value != _passwordController.text) return 'Konfirmasi kata sandi tidak cocok';
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingPassword
                    ? null
                    : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _isSavingPassword = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await widget.authService.changeOwnPassword(_passwordController.text.trim());
                            _passwordController.clear();
                            _confirmController.clear();
                            if (mounted) {
                              messenger.showSnackBar(
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
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Gagal mengubah kata sandi: $e'),
                                  backgroundColor: const Color(0xFFEF4444),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSavingPassword = false);
                          }
                        }
                      },
                icon: _isSavingPassword
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.key_rounded, size: 18),
                label: Text(
                  _isSavingPassword ? 'Memproses...' : 'Simpan Kata Sandi Baru',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // System Info Card
    final systemInfoCard = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'SesiCermat Exam System v${AppVersion.version} • Status Terhubung Firebase Cloud Database',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );

    // App Update Card
    final appUpdateManagementCard = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 4),
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
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.system_update_rounded, color: Colors.indigo.shade700, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pembaruan & Rilis Aplikasi',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kelola rilis APK baru & cek pembaruan aplikasi secara instan',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => AppUpdateService().checkAndShowUpdateDialog(context, silentIfLatest: false),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('Cek Pembaruan', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => AppReleaseManagerDialog.show(context),
                icon: const Icon(Icons.cloud_upload_rounded, size: 18, color: Colors.white),
                label: Text('Kelola Rilis APK Baru', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerBanner,
          const SizedBox(height: 24),
          appUpdateManagementCard,
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 850;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: profileCard),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          changeUsernameCard,
                          const SizedBox(height: 24),
                          changePasswordCard,
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  profileCard,
                  const SizedBox(height: 24),
                  changeUsernameCard,
                  const SizedBox(height: 24),
                  changePasswordCard,
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          systemInfoCard,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
        ),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
        ),
      ],
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
          transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0),
          padding: EdgeInsets.all(isMobile ? 10 : 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 14 : 22),
            border: Border.all(
              color: _isHovered ? widget.color.withValues(alpha: 0.4) : widget.color.withValues(alpha: 0.12),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? widget.color.withValues(alpha: 0.2) : widget.color.withValues(alpha: 0.05),
                blurRadius: _isHovered ? 20 : 12,
                offset: Offset(0, _isHovered ? 6 : 3),
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
                    padding: EdgeInsets.all(isMobile ? 7 : 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(isMobile ? 9 : 14),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.25),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: isMobile ? 15 : 22),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.all(isMobile ? 4 : 8),
                    decoration: BoxDecoration(
                      color: _isHovered ? widget.color : widget.color.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: _isHovered ? Colors.white : widget.color,
                      size: isMobile ? 11 : 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 20 : 28,
                          fontWeight: FontWeight.w900,
                          color: _isHovered ? widget.color : const Color(0xFF0F172A),
                          letterSpacing: -0.6,
                        ),
                        child: Text(widget.count),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 11.5 : 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF334155),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 9.5 : 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
            horizontal: isMobile ? 12 : 18,
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
                blurRadius: _isHovered ? 16 : 6,
                offset: Offset(0, _isHovered ? 5 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 9 : 12),
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
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: isMobile ? 18 : 22),
              ),
              SizedBox(width: isMobile ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        fontWeight: FontWeight.bold,
                        color: _isHovered ? widget.color : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.desc,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 10.5 : 12,
                        color: const Color(0xFF64748B),
                      ),
                      maxLines: isMobile ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.only(left: _isHovered ? 6.0 : 0.0),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: _isHovered ? widget.color : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASS
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
