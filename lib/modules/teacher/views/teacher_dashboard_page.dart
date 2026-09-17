import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/teacher.dart';
import '../../../core/constants/app_version.dart';
import '../../admin/views/rekap_nilai_view.dart';

class TeacherDashboardPage extends StatefulWidget {
  final String? tabName;
  const TeacherDashboardPage({super.key, this.tabName});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  DateTime? _lastBackPressTime;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  // Cached statistics statically to persist across widget destructions/recreations during route changes
  static String? _lastTeacherId;
  static List<QueryDocumentSnapshot>? _lastEvents;
  static String? _lastEventsKey;
  static int _makingQuestionsCount = 0;
  static int _proctoringSessionsCount = 0;
  static bool _statsLoaded = false;

  bool _isEventFinished(Map<String, dynamic> evData) {
    final status = (evData['status'] as String? ?? '').toLowerCase().trim();
    return status == 'closed' ||
        status == 'finished' ||
        status == 'completed' ||
        status == 'archived' ||
        status == 'done' ||
        status == 'selesai';
  }

  bool _isEventActive(Map<String, dynamic> evData) {
    return !_isEventFinished(evData);
  }

  DateTime _parseEventDate(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is String) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) return parsed;
    }

    final startDate = data['startDate'];
    if (startDate is Timestamp) return startDate.toDate();
    if (startDate is String) {
      final parsed = DateTime.tryParse(startDate);
      if (parsed != null) return parsed;
    }

    final updatedAt = data['updatedAt'];
    if (updatedAt is Timestamp) return updatedAt.toDate();
    if (updatedAt is String) {
      final parsed = DateTime.tryParse(updatedAt);
      if (parsed != null) return parsed;
    }

    return DateTime(1970);
  }

  void _updateStats(String schoolId, String teacherId, List<QueryDocumentSnapshot> events) {
    final currentKey = events.map((e) {
      final d = e.data() as Map<String, dynamic>? ?? {};
      return '${e.id}_${d['status']}_${d['updatedAt']}';
    }).join('|');

    if (_lastTeacherId == teacherId && _lastEventsKey == currentKey && _statsLoaded) {
      return;
    }
    _lastTeacherId = teacherId;
    _lastEventsKey = currentKey;
    _lastEvents = events;
    _loadStatsAsync(schoolId, teacherId, events);
  }

  Future<void> _loadStatsAsync(String schoolId, String teacherId, List<QueryDocumentSnapshot> events) async {
    if (teacherId == 'fallback_id') return;

    int questionCount = 0;
    int proctorCount = 0;

    try {
      await Future.wait(events.map((evDoc) async {
        final evData = evDoc.data() as Map<String, dynamic>? ?? {};

        // Skip finished or closed events from active task statistics
        if (_isEventFinished(evData)) return;

        final assignments = await _checkTeacherAssignments(schoolId, evDoc.id, teacherId);

        final timetableList = <Map<String, dynamic>>[];

        // 1. Dari subkoleksi timetable
        try {
          final timetableSnap = await evDoc.reference.collection('timetable').get();
          for (var doc in timetableSnap.docs) {
            timetableList.add(doc.data());
          }
        } catch (_) {}

        // 2. Dari field draftState -> step3 -> timetable & draftState -> timetable
        final draftState = evData['draftState'] as Map<String, dynamic>?;
        if (draftState != null) {
          if (draftState['step3'] is Map && draftState['step3']['timetable'] is List) {
            for (var item in (draftState['step3']['timetable'] as List)) {
              if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
            }
          }
          if (draftState['timetable'] is List) {
            for (var item in (draftState['timetable'] as List)) {
              if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
            }
          }
        }

        // 3. Dari top-level field timetable
        if (evData['timetable'] is List) {
          for (var item in (evData['timetable'] as List)) {
            if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
          }
        }

        final teacherSubjects = <String>{};
        for (var entry in timetableList) {
          if (_isTeacherAssignedToEntry(entry, teacherId)) {
            final subjName = entry['subjectName']?.toString() ?? entry['subjectId']?.toString() ?? 'subj';
            teacherSubjects.add(subjName);
          }
        }

        if (teacherSubjects.isNotEmpty) {
          questionCount += teacherSubjects.length;
        } else if (assignments['isPembuatSoal'] == true) {
          questionCount += 1;
        }

        // Proctors count
        int eventProctors = 0;
        bool isCurrentTeacher(String tid) {
          final t = tid.trim().toLowerCase();
          if (t.isEmpty) return false;
          final myId = teacherId.trim().toLowerCase();
          if (t == myId) return true;
          final cT = t.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
          final cM = myId.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
          return cT.isNotEmpty && cT == cM;
        }

        try {
          final proctorsSnap = await evDoc.reference
              .collection('proctors')
              .get();
          for (var pDoc in proctorsSnap.docs) {
            final pData = pDoc.data();
            final pTid = (pData['teacherId'] ?? '').toString();
            final pTname = (pData['teacherName'] ?? '').toString();
            if (isCurrentTeacher(pTid) || isCurrentTeacher(pTname)) {
              eventProctors++;
            }
          }
        } catch (_) {}

        final proctorGrid = draftState?['proctorGrid'] ?? evData['proctorGrid'];
        if (proctorGrid is Map) {
          for (var val in proctorGrid.values) {
            if (isCurrentTeacher(val.toString())) eventProctors++;
          }
        }

        if (eventProctors > 0) {
          proctorCount += eventProctors;
        } else if (assignments['isPengawas'] == true) {
          proctorCount += 1;
        }
      }));
    } catch (e) {
      debugPrint("Error loading stats: $e");
    }

    if (mounted) {
      setState(() {
        _makingQuestionsCount = questionCount;
        _proctoringSessionsCount = proctorCount;
        _statsLoaded = true;
      });
    }
  }

  bool _isTeacherAssignedToEntry(Map<String, dynamic> entry, String teacherId) {
    final tIds = entry['teacherId'];
    if (tIds is List) {
      if (tIds.contains(teacherId)) return true;
    } else if (tIds is String) {
      if (tIds == teacherId) return true;
    }
    final tName = entry['teacherName']?.toString() ?? '';
    if (tName.isNotEmpty) {
      if (tName.contains('Guru 10.1') && teacherId.contains('Guru 10.1')) return true;
    }
    return false;
  }

  int _getIndexFromTab(String? tab) {
    if (tab == 'ringkasan') return 0;
    if (tab == 'eventujian') return 1;
    if (tab == 'rekapnilai') return 2;
    return 0; // Default
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    String route = '/teacher/ringkasan';
    if (index == 1) {
      route = '/teacher/eventujian';
    } else if (index == 2) {
      route = '/teacher/rekapnilai';
    }
    context.go(route);
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = _getIndexFromTab(widget.tabName);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(covariant TeacherDashboardPage oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final schoolId = authService.schoolId ?? '';
    final uid = authService.user?.uid ?? '';
    final email = authService.user?.email ?? '';

    if (schoolId.isEmpty || uid.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    final displayName = authService.user?.displayName ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .snapshots(),
      builder: (context, teacherSnapshot) {
        Teacher? currentTeacher;

        if (teacherSnapshot.hasData && teacherSnapshot.data!.docs.isNotEmpty) {
          final docs = teacherSnapshot.data!.docs;

          // 1. Match by UID
          QueryDocumentSnapshot? matchDoc;
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final tUid = data['uid']?.toString();
            if (tUid != null && tUid.isNotEmpty && tUid == uid) {
              matchDoc = doc;
              break;
            }
          }

          // 2. Fallback to Email match
          if (matchDoc == null && email.isNotEmpty) {
            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final tEmail = data['email']?.toString().toLowerCase();
              if (tEmail != null && tEmail == email.toLowerCase()) {
                matchDoc = doc;
                break;
              }
            }
          }

          // 3. Fallback to Display Name match
          if (matchDoc == null && displayName.isNotEmpty) {
            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final tName = data['displayName']?.toString();
              if (tName != null && tName.toLowerCase() == displayName.toLowerCase()) {
                matchDoc = doc;
                break;
              }
            }
          }

          if (matchDoc != null) {
            currentTeacher = Teacher.fromFirestore(matchDoc);
          }
        }

        // Fallback default Teacher object if still null
        currentTeacher ??= Teacher(
          id: 'fallback_id',
          uid: uid,
          displayName: authService.user?.displayName ?? 'Guru SesiCermat',
          email: email,
          gender: 'M',
          nip: '',
          subjects: ['Mata Pelajaran'],
          schoolId: schoolId,
          disabled: false,
          archived: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        return _buildTeacherBody(authService, currentTeacher, schoolId);
      },
    );
  }

  Widget _buildTeacherBody(AuthService authService, Teacher? currentTeacher, String schoolId) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    final pages = [
      _buildOverviewTab(authService, currentTeacher, schoolId),
      _buildEventUjianTab(schoolId),
      RekapNilaiView(
        schoolId: schoolId,
        isTeacher: true,
        currentTeacherId: currentTeacher?.id,
        currentTeacherName: currentTeacher?.displayName,
        teacherSubjects: currentTeacher?.subjects ?? [],
      ),
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

    final mainWidget = StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('schools').doc(schoolId).snapshots(),
      builder: (context, schoolSnapshot) {
        final schoolData = schoolSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final schoolName = schoolData['name'] as String? ?? 'SesiCermat';

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                _buildSidebar(authService, currentTeacher, size),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
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

        return Scaffold(
          appBar: _buildMobileAppBar(authService, schoolName),
          body: Container(
            decoration: backgroundGradient,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: pages[_selectedIndex],
            ),
          ),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          _onItemTapped(0);
          return;
        }
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
  // SIDEBAR (DESKTOP)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSidebar(AuthService authService, Teacher? teacher, Size size) {
    final extended = size.width > 1000;

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
          // Logo Area
          Container(
            height: 72,
            padding: EdgeInsets.symmetric(horizontal: extended ? 20 : 0),
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
                              'Portal Guru',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF10B981),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
                    extended: extended,
                  ),
                  _buildSidebarItem(
                    icon: Icons.event_note_outlined,
                    activeIcon: Icons.event_note_rounded,
                    label: 'Event Ujian',
                    idx: 1,
                    extended: extended,
                  ),
                  _buildSidebarItem(
                    icon: Icons.assessment_outlined,
                    activeIcon: Icons.assessment_rounded,
                    label: 'Rekap Nilai Murid',
                    idx: 2,
                    extended: extended,
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
            child: _buildLogoutTile(authService, extended: extended),
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

  Widget _buildSidebarItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int idx,
    required bool extended,
  }) {
    final isSelected = _selectedIndex == idx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => _onItemTapped(idx),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: extended ? 14 : 0,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25))
                : null,
          ),
          child: Row(
            mainAxisAlignment:
                extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                size: 22,
              ),
              if (extended) ...[
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color:
                        isSelected ? const Color(0xFFECFDF5) : const Color(0xFF94A3B8),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
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
          extended ? 'Versi ${AppVersion.version}' : AppVersion.version,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: extended ? 11 : 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOBILE APP BAR & DRAWER
  // ─────────────────────────────────────────────────────────────────────────
  AppBar _buildMobileAppBar(AuthService authService, String schoolName) {
    return AppBar(
      backgroundColor: const Color(0xFF0F172A), // Slate 900 (Biru Gelap)
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            schoolName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _selectedIndex == 0 ? 'Dashboard Guru' : 'Event Ujian Semester',
            style: TextStyle(
              fontSize: 11,
              color: Colors.indigo[200],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12.0, top: 4.0, bottom: 4.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => authService.confirmAndSignOut(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Keluar',
                        style: TextStyle(
                          color: Color(0xFFF87171),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppVersion.version,
                style: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDrawer(AuthService authService, Teacher? teacher) {
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacher?.displayName ?? 'Guru SesiCermat',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        teacher?.email ?? authService.user?.email ?? '',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF10B981),
                          fontSize: 12,
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
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildSidebarItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard_rounded,
                    label: 'Ringkasan',
                    idx: 0,
                    extended: true,
                  ),
                  _buildSidebarItem(
                    icon: Icons.event_note_outlined,
                    activeIcon: Icons.event_note_rounded,
                    label: 'Event Ujian',
                    idx: 1,
                    extended: true,
                  ),
                ],
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
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: const Color(0xFF0F172A), // Slate 900 (Biru Gelap)
        selectedItemColor: const Color(0xFF818CF8),
        unselectedItemColor: const Color(0xFF94A3B8),
        elevation: 0,
        selectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard_rounded),
            label: 'Ringkasan',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.event_note_outlined),
            activeIcon: const Icon(Icons.event_note_rounded),
            label: 'Event Ujian',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.assessment_outlined),
            activeIcon: const Icon(Icons.assessment_rounded),
            label: 'Rekap Nilai',
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: RINGKASAN (OVERVIEW)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOverviewTab(
      AuthService authService, Teacher? teacher, String schoolId) {
    if (teacher == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF10B981)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            padding: EdgeInsets.all(isMobile ? 14.0 : 28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTeacherWelcomeBanner(teacher),
                SizedBox(height: isMobile ? 16 : 24),
                _buildSectionLabel('Tugas & Statistik Anda', subtitle: 'Metrik tugas pembuat soal & pengawas ujian real-time.'),
                SizedBox(height: isMobile ? 10 : 12),
                _buildStatsGrid(schoolId, teacher.id),
                SizedBox(height: isMobile ? 20 : 28),
                _buildSectionLabel('Daftar Event Ujian Semester', subtitle: 'Pilih event ujian aktif untuk kelola soal & pengawasan.'),
                SizedBox(height: isMobile ? 10 : 12),
                _buildEventsList(schoolId, teacher.id),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeacherWelcomeBanner(Teacher teacher) {
    final isMale = teacher.gender == 'M';
    final honorific = isMale ? 'Pak' : 'Bu';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF047857), Color(0xFF065F46)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(isMobile ? 14 : 20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF047857).withValues(alpha: 0.2),
                blurRadius: isMobile ? 12 : 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.school_rounded, color: Color(0xFF6EE7B7), size: 12),
                              const SizedBox(width: 4),
                              Text(
                                'GURU / PENGAWAS',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFA7F3D0),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 6 : 8),
                    Text(
                      'Selamat Datang Kembali,',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFA7F3D0),
                        fontSize: isMobile ? 11 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$honorific ${teacher.displayName}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 8),
                    Text(
                      'NIP: ${teacher.nip.isNotEmpty ? teacher.nip : "-"} • Mapel: ${teacher.subjects.join(", ")}',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFD1FAE5),
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: isMobile ? 22 : 28,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                child: Icon(
                  isMale ? Icons.face_rounded : Icons.face_3_rounded,
                  color: Colors.white,
                  size: isMobile ? 26 : 36,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsGrid(String schoolId, String teacherId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !_statsLoaded) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF10B981)),
          );
        }

        final events = snapshot.data?.docs ?? [];

        // Trigger async calculation after the build passes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateStats(schoolId, teacherId, events);
        });

        return LayoutBuilder(builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;

          final statsData = [
            {
              'title': 'Pembuat Soal',
              'value': '$_makingQuestionsCount',
              'desc': 'Mapel diampu',
              'icon': Icons.edit_note_rounded,
              'gradientColors': [const Color(0xFF0284C7), const Color(0xFF0369A1)],
            },
            {
              'title': 'Mengawas Ujian',
              'value': '$_proctoringSessionsCount',
              'desc': 'Sesi ruangan',
              'icon': Icons.visibility_rounded,
              'gradientColors': [const Color(0xFFD97706), const Color(0xFFB45309)],
            },
            {
              'title': 'Event Aktif',
              'value': '${events.where((e) => _isEventActive(e.data() as Map<String, dynamic>)).length}',
              'desc': 'Event sekolah',
              'icon': Icons.event_available_rounded,
              'gradientColors': [const Color(0xFF059669), const Color(0xFF047857)],
            },
          ];

          if (isMobile) {
            return Column(
              children: statsData.map((item) {
                final gradientColors = item['gradientColors'] as List<Color>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: gradientColors.first.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: gradientColors.first.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            item['icon'] as IconData,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item['title'] as String,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['desc'] as String,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: gradientColors.first.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: gradientColors.first.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            item['value'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: gradientColors.first,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }

          return Row(
            children: statsData.map((item) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildStatsCard(
                    title: item['title'] as String,
                    value: item['value'] as String,
                    desc: item['desc'] as String,
                    icon: item['icon'] as IconData,
                    gradientColors: item['gradientColors'] as List<Color>,
                  ),
                ),
              );
            }).toList(),
          );
        });
      },
    );
  }

  Widget _buildStatsCard({
    required String title,
    required String value,
    required String desc,
    required IconData icon,
    required List<Color> gradientColors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradientColors),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    fontSize: 10,
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
    );
  }

  Widget _buildEventsList(String schoolId, String teacherId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF10B981)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final publishedEvents = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'draft';
          return status == 'published' || status == 'draft';
        }).toList();

        publishedEvents.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final dateA = _parseEventDate(dataA);
          final dateB = _parseEventDate(dataB);
          return dateB.compareTo(dateA);
        });

        if (publishedEvents.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const Icon(Icons.event_busy_rounded,
                    color: Color(0xFF94A3B8), size: 36),
                const SizedBox(height: 10),
                Text(
                  'Belum Ada Event Aktif',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF475569),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hubungi admin sekolah untuk menerbitkan jadwal ujian.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final isMobile = MediaQuery.of(context).size.width < 600;

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: publishedEvents.length,
          separatorBuilder: (_, __) => SizedBox(height: isMobile ? 10 : 12),
          itemBuilder: (context, index) {
            final doc = publishedEvents[index];
            final data = doc.data() as Map<String, dynamic>;
            final eventId = doc.id;
            final eventName = data['name'] ?? 'Event Ujian';

            final sd = data['startDate'];
            final ed = data['endDate'];
            DateTime? start;
            DateTime? end;
            if (sd != null) {
              start = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
            }
            if (ed != null) {
              end = ed is Timestamp ? ed.toDate() : (ed is String ? DateTime.tryParse(ed) : null);
            }
            final dateFormat = DateFormat('dd MMM yyyy');
            final dateStr = (start != null && end != null)
                ? '${dateFormat.format(start)} s/d ${dateFormat.format(end)}'
                : 'Tanggal belum diatur';

            return FutureBuilder<Map<String, bool>>(
              future: _checkTeacherAssignments(schoolId, eventId, teacherId),
              builder: (context, checkSnap) {
                final isPembuatSoal = checkSnap.data?['isPembuatSoal'] ?? false;
                final isPengawas = checkSnap.data?['isPengawas'] ?? false;

                return InkWell(
                  onTap: () {
                    context.go('/teacher/event/$eventId/buatsoal?name=${Uri.encodeComponent(eventName)}');
                  },
                  borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
                  child: Container(
                    padding: EdgeInsets.all(isMobile ? 12 : 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
                      border: Border.all(
                        color: (isPembuatSoal || isPengawas)
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFFE2E8F0),
                        width: (isPembuatSoal || isPengawas) ? 1.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                          blurRadius: isMobile ? 6 : 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 7 : 8, vertical: isMobile ? 2 : 3),
                                    decoration: BoxDecoration(
                                      color: (data['status'] == 'published')
                                          ? const Color(0xFFD1FAE5)
                                          : const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      (data['status'] == 'published') ? 'AKTIF' : 'DRAF',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 8.5 : 9,
                                        fontWeight: FontWeight.bold,
                                        color: (data['status'] == 'published')
                                            ? const Color(0xFF065F46)
                                            : const Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dateStr,
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 10.5 : 11,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isMobile ? 6 : 8),
                              Text(
                                eventName,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 14.5 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: isMobile ? 8 : 10),
                              Wrap(
                                spacing: isMobile ? 6 : 8,
                                runSpacing: isMobile ? 4 : 6,
                                children: [
                                  _buildAssignmentBadge(
                                    label: 'Pembuat Soal',
                                    active: isPembuatSoal,
                                    icon: Icons.edit_note_rounded,
                                    isMobile: isMobile,
                                  ),
                                  _buildAssignmentBadge(
                                    label: 'Pengawas Ruang',
                                    active: isPengawas,
                                    icon: Icons.visibility_rounded,
                                    isMobile: isMobile,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: const Color(0xFF94A3B8),
                          size: isMobile ? 14 : 16,
                        ),
                      ],
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

  Widget _buildAssignmentBadge({
    required String label,
    required bool active,
    required IconData icon,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 10,
        vertical: isMobile ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFECFDF5)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? const Color(0xFFA7F3D0)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isMobile ? 12 : 14,
            color: active ? const Color(0xFF047857) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 10 : 11,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: active ? const Color(0xFF047857) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  static final Map<String, Map<String, bool>> _assignmentCache = {};
  static final Map<String, DateTime> _assignmentCacheTime = {};

  Future<Map<String, bool>> _checkTeacherAssignments(
      String schoolId, String eventId, String teacherId) async {
    final cacheKey = '${eventId}_$teacherId';
    final now = DateTime.now();
    if (_assignmentCache.containsKey(cacheKey) &&
        _assignmentCacheTime.containsKey(cacheKey) &&
        now.difference(_assignmentCacheTime[cacheKey]!).inMinutes < 5) {
      return _assignmentCache[cacheKey]!;
    }

    bool isPembuatSoal = false;
    bool isPengawas = false;

    try {
      final eventRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId);

      final evSnap = await eventRef.get();
      final evData = evSnap.data() ?? {};

      final timetableList = <Map<String, dynamic>>[];
      final draftState = evData['draftState'] as Map<String, dynamic>?;
      if (draftState != null && draftState['timetable'] is List) {
        for (var item in (draftState['timetable'] as List)) {
          if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
        }
      }
      if (evData['timetable'] is List) {
        for (var item in (evData['timetable'] as List)) {
          if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
        }
      }

      // Only query subcollection if not found in top level/draftState
      if (timetableList.isEmpty) {
        try {
          final timetableSnap = await eventRef.collection('timetable').get();
          for (var doc in timetableSnap.docs) {
            timetableList.add(doc.data());
          }
        } catch (_) {}
      }

      for (var entry in timetableList) {
        if (_isTeacherAssignedToEntry(entry, teacherId)) {
          isPembuatSoal = true;
          break;
        }
      }

      // Check proctors
      bool isCurrentTeacher(String tid) {
        final t = tid.trim().toLowerCase();
        if (t.isEmpty) return false;
        final myId = teacherId.trim().toLowerCase();
        if (t == myId) return true;
        final cT = t.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        final cM = myId.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        return cT.isNotEmpty && cT == cM;
      }

      final proctorGrid = draftState?['proctorGrid'] ?? evData['proctorGrid'];
      if (proctorGrid is Map) {
        for (var val in proctorGrid.values) {
          if (isCurrentTeacher(val.toString())) {
            isPengawas = true;
            break;
          }
        }
      }

      if (!isPengawas) {
        try {
          final proctorsSnap = await eventRef
              .collection('proctors')
              .get();
          for (var pDoc in proctorsSnap.docs) {
            final pData = pDoc.data();
            final pTid = (pData['teacherId'] ?? '').toString();
            final pTname = (pData['teacherName'] ?? '').toString();
            if (isCurrentTeacher(pTid) || isCurrentTeacher(pTname)) {
              isPengawas = true;
              break;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    final res = {
      'isPembuatSoal': isPembuatSoal,
      'isPengawas': isPengawas,
    };
    _assignmentCache[cacheKey] = res;
    _assignmentCacheTime[cacheKey] = DateTime.now();
    return res;
  }

  Widget _buildSectionLabel(String text, {String? subtitle}) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: isMobile ? 15 : 18,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14.5 : 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 10.5 : 11,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: EVENT UJIAN SEMESTER (STREAM ALL EVENTS)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEventUjianTab(String schoolId) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF10B981)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Gagal memuat event ujian: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? []);
        docs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final dateA = _parseEventDate(dataA);
          final dateB = _parseEventDate(dataB);
          return dateB.compareTo(dateA);
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFA7F3D0), width: 2),
                  ),
                  child: const Icon(
                    Icons.event_note_rounded,
                    size: 64,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Belum Ada Event Ujian',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Admin belum membuat event ujian untuk sekolah ini.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }

        final isMobile = MediaQuery.of(context).size.width < 600;

        return ListView(
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 14 : 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.event_available_rounded, color: Color(0xFF10B981), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daftar Event Ujian Semester',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 16 : 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Pilih event ujian untuk melihat jadwal, mengedit/membuat soal, atau koreksi.',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 11.5 : 13,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 14 : 24),
            ...docs.map((doc) {
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

              final dateStr = (start != null && end != null)
                  ? '${dateFormat.format(start)} - ${dateFormat.format(end)}'
                  : 'Tanggal belum diatur';

              Color statusColor;
              String statusLabel;
              if (status == 'published' || status == 'active') {
                statusColor = const Color(0xFF10B981);
                statusLabel = 'Dipublikasi';
              } else {
                statusColor = const Color(0xFFF59E0B);
                statusLabel = 'Draft Admin';
              }

              final isDesktopWidth = MediaQuery.of(context).size.width > 600;

              return Container(
                margin: EdgeInsets.only(bottom: isMobile ? 10 : 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: isMobile ? 6 : 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(isDesktopWidth ? 20 : (isMobile ? 12 : 16)),
                  child: isDesktopWidth
                      ? Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.assignment_outlined, color: Color(0xFF4F46E5), size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
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
                                context.go('/teacher/event/$eventId/buatsoal?name=${Uri.encodeComponent(name)}');
                              },
                              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                              label: const Text('Buka Event'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.assignment_outlined, color: Color(0xFF4F46E5), size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: GoogleFonts.inter(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateStr,
                                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.school_rounded, size: 12, color: Color(0xFF64748B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'T.A $academicYear',
                                      style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  context.go('/teacher/event/$eventId/buatsoal?name=${Uri.encodeComponent(name)}');
                                },
                                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                label: const Text('Buka Event'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
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
