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
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;
  DateTime? _lastBackPressTime;

  // Student Profile Cache
  Student? _student;
  String _schoolId = '';
  String? _myClassId;
  String? _myClassName;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _loadStudentProfile();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
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

    final mainWidget = Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school_rounded, color: Color(0xFF34D399), size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Portal Siswa SesiCermat',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Keluar',
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Banner: Nama, NIS, Kelas saja
              _buildStudentHeaderCard(),
              const SizedBox(height: 28),

              // Title Section: Event Ujian
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF10B981), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Event Ujian Sekolah',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Pilih event di bawah untuk melihat kartu & jadwal ujian Anda',
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
              const SizedBox(height: 16),

              // Event Cards Stream
              _buildEventCardsList(schoolId),
            ],
          ),
        ),
      ),
    );

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

  /// Header Banner menampilkan Nama, NIS, dan Kelas saja
  Widget _buildStudentHeaderCard() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _student?.displayName ?? 'Peserta Didik',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, color: Color(0xFFA7F3D0), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'NIS: ${_student?.nis ?? "-"}',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFA7F3D0),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.class_outlined, color: Color(0xFFA7F3D0), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Kelas: ${_myClassName ?? "-"}',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFA7F3D0),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// List Card Event Ujian yang diadakan oleh Admin
  Widget _buildEventCardsList(String schoolId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Gagal memuat event: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final publishedEvents = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'draft';
          return status != 'closed';
        }).toList();

        if (publishedEvents.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const Icon(Icons.event_busy_rounded, size: 56, color: Color(0xFF94A3B8)),
                const SizedBox(height: 16),
                Text(
                  'Tidak Ada Event Ujian Aktif',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sekolah belum menerbitkan jadwal event ujian.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Column(
          children: publishedEvents.map((doc) {
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

            final dateFormat = DateFormat('dd MMM yyyy', 'id_ID');
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
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    context.push('/student/event/$eventId?name=${Uri.encodeComponent(name)}');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.assignment_outlined, color: Color(0xFF10B981), size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (status == 'published') 
                                              ? const Color(0xFFD1FAE5) 
                                              : const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
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
                                      const SizedBox(width: 8),
                                      Text(
                                        'T.A $academicYear',
                                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 24),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      dateStr,
                                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Detail',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF10B981)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
