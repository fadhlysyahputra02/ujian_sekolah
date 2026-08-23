import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/student.dart';

class StudentDashboardPage extends StatefulWidget {
  final String? tabName;

  const StudentDashboardPage({
    super.key,
    this.tabName,
  });

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;
  DateTime? _lastBackPressTime;

  // Student Profile Cache
  Student? _student;
  String _schoolId = '';
  String? _myClassId;
  String? _myClassName;
  bool _isLoadingProfile = true;

  // Stats Card data
  int _totalEventsCount = 0;
  String _allocatedRoom = '-';
  String _allocatedSeat = '-';

  @override
  void initState() {
    super.initState();
    _selectedIndex = _getIndexFromTab(widget.tabName);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _loadStudentProfile();
  }

  @override
  void didUpdateWidget(covariant StudentDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabName != oldWidget.tabName) {
      setState(() {
        _selectedIndex = _getIndexFromTab(widget.tabName);
        _fadeController.forward(from: 0.0);
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  int _getIndexFromTab(String? tab) {
    if (tab == 'ringkasan') return 0;
    if (tab == 'ujian') return 1;
    return 0; // Default
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    String route = '/student/ringkasan';
    if (index == 1) {
      route = '/student/ujian';
    }
    context.go(route);
  }

  Future<void> _loadStudentProfile() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    // Wait for auth to resolve
    if (authService.isLoading || authService.schoolId == null || authService.schoolId!.isEmpty) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!authService.isLoading && authService.schoolId != null && authService.schoolId!.isNotEmpty) {
          break;
        }
      }
    }

    _schoolId = authService.schoolId ?? '';
    final uid = authService.user?.uid ?? '';

    if (_schoolId.isEmpty || uid.isEmpty) {
      if (mounted) setState(() => _isLoadingProfile = false);
      return;
    }

    try {
      // 1. Load Student Doc
      final studentSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('students')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (studentSnap.docs.isNotEmpty) {
        final doc = studentSnap.docs.first;
        _student = Student.fromFirestore(doc);

        // 2. Resolve Class
        final classSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('classes')
            .get();

        for (var cDoc in classSnap.docs) {
          final cData = cDoc.data();
          final sIds = cData['studentIds'];
          if (sIds is List && sIds.contains(doc.id)) {
            _myClassId = cDoc.id;
            _myClassName = cData['name'] ?? cDoc.id;
            break;
          }
        }

        _myClassName ??= (doc.data()['className'] ?? doc.data()['classId'] ?? _student!.angkatan).toString();
        _myClassId ??= _myClassName;

        // 3. Load Events stats & seat allocation fallback from the first active event
        final eventsSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('events')
            .get();

        _totalEventsCount = eventsSnap.docs.where((d) => (d.data()['status'] != 'closed')).length;

        if (eventsSnap.docs.isNotEmpty) {
          // Look for student seat in any active event allocation
          for (var evDoc in eventsSnap.docs) {
            final status = evDoc.data()['status'] as String? ?? 'draft';
            if (status == 'closed') continue;
            
            final allocSnap = await evDoc.reference.collection('allocations').limit(1).get();
            if (allocSnap.docs.isNotEmpty) {
              final activeAllocId = allocSnap.docs.first.id;
              final allocRef = evDoc.reference.collection('allocations').doc(activeAllocId);
              
              // Multi-stage seat resolution fallback
              Map<String, dynamic>? seatData;
              
              // 1. Try by studentId
              var seatSnap = await allocRef.collection('seats').where('studentId', isEqualTo: doc.id).limit(1).get();
              if (seatSnap.docs.isNotEmpty) {
                seatData = seatSnap.docs.first.data();
              }
              
              // 2. Try by nis
              if (seatData == null && _student!.nis.isNotEmpty) {
                seatSnap = await allocRef.collection('seats').where('nis', isEqualTo: _student!.nis).limit(1).get();
                if (seatSnap.docs.isNotEmpty) {
                  seatData = seatSnap.docs.first.data();
                }
              }
              
              // 3. Try by studentName / displayName
              if (seatData == null && _student!.displayName.isNotEmpty) {
                seatSnap = await allocRef.collection('seats').where('studentName', isEqualTo: _student!.displayName).limit(1).get();
                if (seatSnap.docs.isNotEmpty) {
                  seatData = seatSnap.docs.first.data();
                } else {
                  seatSnap = await allocRef.collection('seats').where('displayName', isEqualTo: _student!.displayName).limit(1).get();
                  if (seatSnap.docs.isNotEmpty) {
                    seatData = seatSnap.docs.first.data();
                  }
                }
              }

              if (seatData != null) {
                _allocatedRoom = (seatData['roomName'] ?? seatData['roomId'] ?? '-').toString();
                _allocatedSeat = (seatData['seatNumber'] ?? '-').toString();
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading student profile: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final schoolId = _schoolId.isNotEmpty ? _schoolId : (authService.schoolId ?? '');

    if (_isLoadingProfile || schoolId.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    final pages = [
      _buildOverviewTab(authService),
      _buildEventsTab(schoolId),
    ];

    Widget mainWidget;
    if (isDesktop) {
      mainWidget = Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Row(
          children: [
            // Web Sidebar
            _buildSidebar(authService),
            // Web Content
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: pages[_selectedIndex],
              ),
            ),
          ],
        ),
      );
    } else {
      // Mobile Layout
      mainWidget = Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _selectedIndex == 0 ? 'Ringkasan Siswa' : 'Daftar Event Ujian',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded, size: 20),
              onPressed: () => authService.signOut(),
            ),
          ],
        ),
        body: FadeTransition(
          opacity: _fadeAnim,
          child: pages[_selectedIndex],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: const Color(0xFF10B981),
          unselectedItemColor: const Color(0xFF94A3B8),
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Ringkasan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment_rounded),
              label: 'Ujian',
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
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
      child: mainWidget,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SIDEBAR (WEB DESKTOP)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSidebar(AuthService authService) {
    return Container(
      width: 250,
      color: const Color(0xFF0F172A), // Slate 900
      child: Column(
        children: [
          // Header Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white10),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFF34D399), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SesiCermat',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Portal Siswa',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF34D399),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Nav Items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _buildSidebarItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard_rounded,
                    label: 'Ringkasan',
                    idx: 0,
                  ),
                  _buildSidebarItem(
                    icon: Icons.assignment_outlined,
                    activeIcon: Icons.assignment_rounded,
                    label: 'Ujian Ujian',
                    idx: 1,
                  ),
                ],
              ),
            ),
          ),
          // Logout Button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLogoutTile(authService),
                const SizedBox(height: 8),
                Text(
                  'Versi 1.0.1',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int idx,
  }) {
    final isSelected = _selectedIndex == idx;
    return InkWell(
      onTap: () => _onItemTapped(idx),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
              size: 20,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutTile(AuthService authService) {
    return InkWell(
      onTap: () => authService.signOut(),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFFCA5A5), size: 16),
            ),
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
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: OVERVIEW / RINGKASAN
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOverviewTab(AuthService authService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Welcome
          _buildWelcomeBanner(),
          const SizedBox(height: 24),
          
          // Stats Section
          Text(
            'Informasi Statistik & Ujian',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          
          // Stats Grid
          _buildStatsGrid(),
          const SizedBox(height: 28),

          // Instructions Box
          _buildInstructionBox(),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    final isMale = _student?.gender == 'M';
    final titleLabel = isMale ? 'Siswa' : 'Siswi';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF065F46), Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF047857).withValues(alpha: 0.25),
            blurRadius: 16,
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
                  '👋 Selamat Datang Kembali,',
                  style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  _student?.displayName ?? 'Peserta Didik',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  '$titleLabel  •  NISN: ${_student?.nis ?? "-"}  •  Kelas: ${_myClassName ?? "-"}',
                  style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final size = MediaQuery.of(context).size;
    final crossAxisCount = size.width > 600 ? 3 : 1;

    return GridView.count(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: size.width > 600 ? 1.8 : 3.2,
      children: [
        _buildStatsCard(
          title: 'Total Event Ujian',
          value: '$_totalEventsCount',
          desc: 'Event sedang berlangsung',
          icon: Icons.event_available_rounded,
          colors: [const Color(0xFF059669), const Color(0xFF065F46)],
        ),
        _buildStatsCard(
          title: 'Ruangan Anda',
          value: _allocatedRoom,
          desc: 'Ruang alokasi tempat duduk',
          icon: Icons.meeting_room_rounded,
          colors: [const Color(0xFF0D9488), const Color(0xFF0F766E)],
        ),
        _buildStatsCard(
          title: 'Nomor Kursi',
          value: _allocatedSeat,
          desc: 'Nomor bangku ujian Anda',
          icon: Icons.chair_rounded,
          colors: [const Color(0xFFD97706), const Color(0xFFB45309)],
        ),
      ],
    );
  }

  Widget _buildStatsCard({
    required String title,
    required String value,
    required String desc,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A), letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 10),
              Text(
                'Panduan Peserta Ujian',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBulletPoint('Hadir di ruangan ujian 15 menit sebelum sesi dimulai.'),
          _buildBulletPoint('Gunakan aplikasi mobile resmi sekolah untuk melakukan verifikasi wajah.'),
          _buildBulletPoint('Persiapkan Kartu Peserta Ujian Anda (dapat diakses pada detail event).'),
          _buildBulletPoint('Dilarang membawa alat komunikasi genggam lainnya ke dalam ruangan.'),
          _buildBulletPoint('Patuhi seluruh instruksi dan tata tertib dari pengawas ruangan.'),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5.0),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: EVENTS LIST
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEventsTab(String schoolId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        if (snapshot.hasError) {
          return Center(child: Text('Gagal memuat event: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        }

        final docs = snapshot.data?.docs ?? [];
        final publishedEvents = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'draft';
          return status != 'closed';
        }).toList();

        if (publishedEvents.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_busy_rounded, size: 64, color: Color(0xFF94A3B8)),
                const SizedBox(height: 16),
                Text(
                  'Tidak Ada Event Ujian Aktif',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sekolah belum menerbitkan jadwal event ujian semester.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Event Ujian Semester',
                        style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        'Silakan pilih event ujian di bawah ini untuk melihat detail jadwal Anda.',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ...publishedEvents.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final eventId = doc.id;
              final name = data['name'] as String? ?? 'Event Ujian';
              final academicYear = data['academicYear'] as String? ?? '-';
              final status = data['status'] as String? ?? 'draft';

              DateTime? start;
              DateTime? end;
              final sd = data['startDate'];
              final ed = data['endDate'];
              if (sd != null) {
                start = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
              }
              if (ed != null) {
                end = ed is Timestamp ? ed.toDate() : (ed is String ? DateTime.tryParse(ed) : null);
              }

              final dateFormat = DateFormat('dd MMM yyyy');
              final dateStr = (start != null && end != null)
                  ? '${dateFormat.format(start)} - ${dateFormat.format(end)}'
                  : 'Tanggal belum diatur';

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
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
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.assignment_outlined, color: Color(0xFF10B981), size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (status == 'published') 
                                        ? const Color(0xFFD1FAE5) 
                                        : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (status == 'published')
                                          ? const Color(0xFFA7F3D0)
                                          : const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Text(
                                    (status == 'published') ? 'PUBLISHED' : 'DRAFT ADMIN',
                                    style: GoogleFonts.inter(
                                      color: (status == 'published') 
                                          ? const Color(0xFF065F46) 
                                          : const Color(0xFF92400E),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                ),
                                const SizedBox(width: 16),
                                const Icon(Icons.school_rounded, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Text(
                                  'T.A $academicYear',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          context.push('/student/ujian/event/$eventId?name=${Uri.encodeComponent(name)}');
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('Buka Ujian'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
