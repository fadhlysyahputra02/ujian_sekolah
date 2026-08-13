import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/school_service.dart';
import '../../schools/pages/school_list_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  final SchoolService _schoolService = SchoolService();

  final List<String> _titles = ['Ringkasan Sistem', 'Manajemen Sekolah'];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    final authService = Provider.of<AuthService>(context);

    // Sidebar items
    final navigationItems = [
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_rounded),
        selectedIcon: Icon(Icons.dashboard_rounded, color: Color(0xFF4F46E5)),
        label: Text('Ringkasan'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.school_rounded),
        selectedIcon: Icon(Icons.school_rounded, color: Color(0xFF4F46E5)),
        label: Text('Sekolah'),
      ),
    ];

    final bottomNavItems = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.dashboard_outlined),
        activeIcon: Icon(Icons.dashboard_rounded),
        label: 'Ringkasan',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.school_outlined),
        activeIcon: Icon(Icons.school_rounded),
        label: 'Sekolah',
      ),
    ];

    final pages = [
      _buildOverviewContent(),
      const SchoolListPage(),
    ];

    if (isDesktop) {
      // Desktop / Web Layout
      return Scaffold(
        body: Row(
          children: [
            // Sidebar Navigation Rail
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              extended: size.width > 1100,
              labelType: size.width > 1100 ? NavigationRailLabelType.none : NavigationRailLabelType.selected,
              backgroundColor: Colors.white,
              elevation: 4,
              minWidth: 72,
              minExtendedWidth: 220,
              leading: Column(
                children: [
                  const SizedBox(height: 24),
                  // App Branding
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Color(0xFF4F46E5),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (size.width > 1100) ...[
                    const Text(
                      'SesiCermat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Text(
                      'Super Admin',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
              destinations: navigationItems,
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(indent: 10, endIndent: 10),
                        const SizedBox(height: 12),
                        IconButton(
                          icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                          onPressed: () => authService.signOut(),
                          tooltip: 'Keluar',
                        ),
                        if (size.width > 1100) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Keluar',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Main Content Area
            Expanded(
              child: Container(
                color: const Color(0xFFF8FAFC),
                child: pages[_selectedIndex],
              ),
            ),
          ],
        ),
      );
    } else {
      // Mobile / Tablet Layout
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _titles[_selectedIndex],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          elevation: 0,
        ),
        drawer: Drawer(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                accountName: const Text(
                  'Super Admin',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                accountEmail: Text(authService.user?.email ?? 'sadmin@sesicermat.com'),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard_rounded),
                title: const Text('Ringkasan'),
                selected: _selectedIndex == 0,
                selectedColor: const Color(0xFF4F46E5),
                onTap: () {
                  setState(() {
                    _selectedIndex = 0;
                  });
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.school_rounded),
                title: const Text('Manajemen Sekolah'),
                selected: _selectedIndex == 1,
                selectedColor: const Color(0xFF4F46E5),
                onTap: () {
                  setState(() {
                    _selectedIndex = 1;
                  });
                  Navigator.of(context).pop();
                },
              ),
              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                title: const Text(
                  'Keluar',
                  style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await authService.signOut();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        body: pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          selectedItemColor: const Color(0xFF4F46E5),
          unselectedItemColor: const Color(0xFF64748B),
          backgroundColor: Colors.white,
          elevation: 8,
          items: bottomNavItems,
        ),
      );
    }
  }

  Widget _buildOverviewContent() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _schoolService.getSchoolsStream(),
      builder: (context, snapshot) {
        final schools = snapshot.data?.docs ?? [];
        int totalSchools = schools.length;
        int activeSchools = schools.where((s) => s.data()['disabled'] != true).length;
        int inactiveSchools = totalSchools - activeSchools;

        int totalTeachers = 0;
        int totalStudents = 0;
        for (var s in schools) {
          final meta = s.data()['meta'] as Map<String, dynamic>? ?? {};
          totalTeachers += (meta['teacherCount'] ?? 0) as int;
          totalStudents += (meta['studentCount'] ?? 0) as int;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selamat datang, Super Admin!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Berikut adalah ringkasan data sistem SesiCermat secara real-time.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 24),

              // KPI Stats Grid
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 1200
                    ? 5
                    : MediaQuery.of(context).size.width > 800
                        ? 3
                        : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.3,
                children: [
                  _buildStatCard(
                    title: 'Total Sekolah',
                    value: '$totalSchools',
                    icon: Icons.business_rounded,
                    color: const Color(0xFF4F46E5),
                  ),
                  _buildStatCard(
                    title: 'Sekolah Aktif',
                    value: '$activeSchools',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF10B981),
                  ),
                  _buildStatCard(
                    title: 'Sekolah Nonaktif',
                    value: '$inactiveSchools',
                    icon: Icons.remove_circle_rounded,
                    color: const Color(0xFFEF4444),
                  ),
                  _buildStatCard(
                    title: 'Total Guru',
                    value: '$totalTeachers',
                    icon: Icons.people_alt_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                  _buildStatCard(
                    title: 'Total Murid',
                    value: '$totalStudents',
                    icon: Icons.face_rounded,
                    color: const Color(0xFF06B6D4),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              // Subtitle
              const Text(
                'Aktivitas Cepat',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),

              // Quick Actions Container
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Daftarkan Sekolah Baru Sekarang',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tambahkan sekolah baru ke ekosistem SesiCermat dan buat akun administrator pertamanya.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedIndex = 1; // Go to schools management
                        });
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Kelola Sekolah'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
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
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              Icon(icon, color: color, size: 24),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}
