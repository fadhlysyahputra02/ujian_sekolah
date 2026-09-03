import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/school_service.dart';
import '../../../core/constants/app_version.dart';
import '../../../core/widgets/app_splash_loader.dart';
import 'school_list_page.dart';

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

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _updateTabFromWidget();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
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

    final pages = [
      _buildOverviewContent(),
      const SchoolListPage(),
      _buildSettingsContent(authService),
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

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _buildSidebar(authService, size),
            Expanded(
              child: Container(
                decoration: backgroundGradient,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: pages[_selectedIndex],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Mobile layout
    return Scaffold(
      appBar: _buildMobileAppBar(authService),
      drawer: _buildDrawer(authService),
      body: Container(
        decoration: backgroundGradient,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: pages[_selectedIndex],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
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
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.school_rounded, color: Colors.white, size: 22),
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
          onTap: () => authService.signOut(),
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
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Text(
        _selectedIndex == 0 ? 'Ringkasan Sistem' : 'Manajemen Sekolah',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
      ),
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

  Widget _buildDrawer(AuthService authService) {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                _buildLogoIcon(),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SesiCermat',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      authService.user?.email ?? 'sadmin@sesicermat.com',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF818CF8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: _navItems.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _buildSidebarItem(item, idx, true),
                  );
                }).toList(),
              ),
            ),
          ),
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.all(12),
            child: _buildLogoutTile(authService, extended: true),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (idx) => _navigateToTab(idx),
        selectedItemColor: const Color(0xFF4F46E5),
        unselectedItemColor: const Color(0xFF94A3B8),
        backgroundColor: Colors.white,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
        items: _navItems.map((item) {
          return BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.only(bottom: 2),
              child: Icon(item.icon),
            ),
            activeIcon: Container(
              padding: const EdgeInsets.only(bottom: 2),
              child: Icon(item.activeIcon),
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
                        final crossCount = gridWidth > 1100 ? 5 : (gridWidth > 700 ? 3 : (gridWidth > 480 ? 2 : 1));

                        return GridView.count(
                          crossAxisCount: crossCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: gridWidth > 1100 ? 1.25 : (gridWidth > 700 ? 1.35 : 1.5),
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
                              subtitle: 'Siswa Terdaftar CBT',
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
                        final actCrossCount = actWidth > 900 ? 3 : (actWidth > 550 ? 2 : 1);

                        return GridView.count(
                          crossAxisCount: actCrossCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: actWidth > 900 ? 2.1 : 2.5,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Color(0xFF818CF8),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'PORTAL UTAMA SUPER ADMIN',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF818CF8),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sistem Online',
                      style: GoogleFonts.inter(
                        fontSize: 11,
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
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isSaving = false;

    final userEmail = authService.user?.email ?? '';
    final initialLetter = userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'S';

    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                                      'Super Admin',
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0.0, _isHovered ? -5.0 : 0.0, 0.0),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _isHovered ? widget.color.withValues(alpha: 0.4) : widget.color.withValues(alpha: 0.12),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? widget.color.withValues(alpha: 0.2) : widget.color.withValues(alpha: 0.05),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 22),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isHovered ? widget.color : widget.color.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: _isHovered ? Colors.white : widget.color,
                      size: 14,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _isHovered ? widget.color : const Color(0xFF0F172A),
                      letterSpacing: -0.8,
                    ),
                    child: Text(widget.count),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: _isHovered ? widget.color.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(18),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _isHovered ? widget.color : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.desc,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                      maxLines: 2,
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
