import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/school_service.dart';
import '../../../core/constants/app_version.dart';
import 'school_list_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

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
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
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
        onTap: () => setState(() {
          _selectedIndex = idx;
        }),
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
        onTap: (idx) => setState(() => _selectedIndex = idx),
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

        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Banner
              _buildWelcomeBanner(),
              const SizedBox(height: 28),

              // Section label
              _buildSectionLabel('Statistik Sistem'),
              const SizedBox(height: 14),

              // KPI Cards
              LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 2;
                  if (constraints.maxWidth > 1100) {
                    crossAxisCount = 5;
                  } else if (constraints.maxWidth > 700) {
                    crossAxisCount = 3;
                  }

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.35,
                    children: [
                      _buildStatCard(
                        title: 'Total Sekolah',
                        value: isLoading ? '—' : '$totalSchools',
                        icon: Icons.business_rounded,
                        gradientColors: [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                        bgColor: const Color(0xFFF5F3FF),
                        iconBg: const Color(0xFF4F46E5),
                      ),
                      _buildStatCard(
                        title: 'Sekolah Aktif',
                        value: isLoading ? '—' : '$activeSchools',
                        icon: Icons.check_circle_rounded,
                        gradientColors: [const Color(0xFF059669), const Color(0xFF10B981)],
                        bgColor: const Color(0xFFF0FDF4),
                        iconBg: const Color(0xFF10B981),
                      ),
                      _buildStatCard(
                        title: 'Nonaktif',
                        value: isLoading ? '—' : '$inactiveSchools',
                        icon: Icons.cancel_rounded,
                        gradientColors: [const Color(0xFFDC2626), const Color(0xFFEF4444)],
                        bgColor: const Color(0xFFFFF5F5),
                        iconBg: const Color(0xFFEF4444),
                      ),
                      _buildStatCard(
                        title: 'Total Guru',
                        value: isLoading ? '—' : '$totalTeachers',
                        icon: Icons.person_rounded,
                        gradientColors: [const Color(0xFFD97706), const Color(0xFFF59E0B)],
                        bgColor: const Color(0xFFFFFBEB),
                        iconBg: const Color(0xFFF59E0B),
                      ),
                      _buildStatCard(
                        title: 'Total Murid',
                        value: isLoading ? '—' : '$totalStudents',
                        icon: Icons.school_rounded,
                        gradientColors: [const Color(0xFF0284C7), const Color(0xFF06B6D4)],
                        bgColor: const Color(0xFFF0FDFF),
                        iconBg: const Color(0xFF06B6D4),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 32),
              _buildSectionLabel('Aktivitas Cepat'),
              const SizedBox(height: 14),
              _buildQuickActionCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF3730A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '👋  Selamat Datang!',
                  style: GoogleFonts.inter(
                    color: const Color(0xFFC7D2FE),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Super Admin\nSesiCermat',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Pantau dan kelola seluruh ekosistem sekolah dari sini.',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF818CF8),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: Color(0xFFC7D2FE), size: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Row(
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
          text,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required List<Color> gradientColors,
    required Color bgColor,
    required Color iconBg,
  }) {
    final themeColor = gradientColors.last;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradientColors),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF5F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDD6FE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.add_business_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daftarkan Sekolah Baru',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tambahkan sekolah baru ke ekosistem SesiCermat.',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => setState(() => _selectedIndex = 1),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(
              'Kelola',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
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
