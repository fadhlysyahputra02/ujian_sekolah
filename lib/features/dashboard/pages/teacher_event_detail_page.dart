import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/teacher.dart';

class TeacherEventDetailPage extends StatefulWidget {
  final String eventId;
  final String eventName;

  const TeacherEventDetailPage({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<TeacherEventDetailPage> createState() => _TeacherEventDetailPageState();
}

class _TeacherEventDetailPageState extends State<TeacherEventDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isPembuatSoal = false;
  bool _isPengawas = false;
  Teacher? _teacher;
  String _schoolId = '';
  Map<String, String>? _selectedSubjectMap;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    _schoolId = authService.schoolId ?? '';
    final uid = authService.user?.uid ?? '';

    try {
      // 1. Fetch Teacher Info
      final teacherSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('teachers')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (teacherSnap.docs.isNotEmpty) {
        _teacher = Teacher.fromFirestore(teacherSnap.docs.first);
        final teacherId = _teacher!.id;

        // 2. Check Timetable (Buat Soal & Koreksi)
        final timetableSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('events')
            .doc(widget.eventId)
            .collection('timetable')
            .get();

        for (var doc in timetableSnap.docs) {
          final tIds = List<String>.from(doc.data()['teacherId'] ?? []);
          if (tIds.contains(teacherId)) {
            _isPembuatSoal = true;
            break;
          }
        }

        // 3. Check Proctoring (Pengawas Ruangan)
        final proctorsSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('events')
            .doc(widget.eventId)
            .collection('proctors')
            .where('teacherId', isEqualTo: teacherId)
            .limit(1)
            .get();

        if (proctorsSnap.docs.isNotEmpty) {
          _isPengawas = true;
        }
      }
    } catch (e) {
      debugPrint("Error checking teacher permissions: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.eventName),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/teacher');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.eventName,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Detail Tugas & Event Ujian Semester',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF34D399)),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF34D399),
          unselectedLabelColor: Colors.white70,
          indicatorColor: const Color(0xFF10B981),
          tabs: const [
            Tab(icon: Icon(Icons.edit_note_rounded), text: 'Buat Soal'),
            Tab(icon: Icon(Icons.visibility_rounded), text: 'Pengawas Ruangan'),
            Tab(icon: Icon(Icons.assignment_turned_in_rounded), text: 'Koreksi Ujian'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _isPembuatSoal
              ? _buildBuatSoalTab()
              : _buildLockedTab('Buat Soal', 'pembuat soal'),
          _isPengawas
              ? _buildPengawasTab()
              : _buildLockedTab('Pengawas Ruangan', 'pengawas ruangan'),
          _isPembuatSoal
              ? _buildKoreksiTab()
              : _buildLockedTab('Koreksi Ujian', 'pembuat soal'),
        ],
      ),
    );
  }

  Widget _buildLockedTab(String tabName, String roleNeeded) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Akses Terkunci',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Anda tidak memiliki tugas sebagai $roleNeeded pada event ujian ini. Silakan hubungi admin sekolah jika ada kekeliruan.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: BUAT SOAL (MAPEL DITUGASKAN -> ANGKATAN TAB)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBuatSoalTab() {
    if (_teacher == null) return const SizedBox();

    // Jika guru telah memilih mapel tertentu, tampilkan layar kelola soal per angkatan
    if (_selectedSubjectMap != null) {
      return _buildAngkatanQuestionManager(
        _selectedSubjectMap!['id']!,
        _selectedSubjectMap!['name']!,
      );
    }

    // TAMPILAN 1: Daftar Mapel yang ditugaskan oleh admin pada guru ini di event ini
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('timetable')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        final allTimetables = snapshot.data?.docs ?? [];
        final assignedTimetables = allTimetables.where((doc) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final tIds = List<String>.from(data['teacherId'] ?? []);
          return tIds.contains(_teacher!.id);
        }).toList();

        // Kelompokkan berdasarkan mata pelajaran unik
        final subjectGroups = <String, Map<String, dynamic>>{};
        for (var doc in assignedTimetables) {
          final data = doc.data() as Map<String, dynamic>;
          final sId = data['subjectId'] as String? ?? doc.id;
          final sName = data['subjectName'] as String? ?? 'Mata Pelajaran';
          final cName = data['className'] as String? ?? '';

          if (!subjectGroups.containsKey(sId)) {
            subjectGroups[sId] = {
              'id': sId,
              'name': sName,
              'classes': <String>{if (cName.isNotEmpty) cName},
            };
          } else {
            if (cName.isNotEmpty) {
              (subjectGroups[sId]!['classes'] as Set<String>).add(cName);
            }
          }
        }

        final subjectList = subjectGroups.values.toList();

        if (subjectList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_ind_outlined, size: 48, color: Color(0xFFD97706)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Belum Ada Mapel Ditugaskan',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Admin belum menugaskan Anda sebagai pembuat soal pada event ujian ini.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  textAlign: TextAlign.center,
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
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_document, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tugas Pembuat Soal',
                      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      'Pilih mata pelajaran di bawah untuk mengelola bank soal berdasarkan angkatan siswa.',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            ...subjectList.map((subj) {
              final subjectId = subj['id'] as String;
              final subjectName = subj['name'] as String;
              final classesSet = subj['classes'] as Set<String>;
              final classesStr = classesSet.isNotEmpty ? classesSet.join(', ') : 'Semua Kelas';

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
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
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.menu_book_rounded, color: Color(0xFF10B981), size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subjectName,
                              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.groups_rounded, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Kelas Terkait: $classesStr',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedSubjectMap = {
                              'id': subjectId,
                              'name': subjectName,
                            };
                          });
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('Kelola Soal'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

  // TAMPILAN 2: Kelola Soal dengan TabBar Angkatan Aktif Sekolah
  Widget _buildAngkatanQuestionManager(String subjectId, String subjectName) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('students')
          .snapshots(),
      builder: (context, studentSnap) {
        if (studentSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        final studentDocs = studentSnap.data?.docs ?? [];
        final angkatanCounts = <String, int>{};

        for (var doc in studentDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final isArchived = data['archived'] == true;
          final isDisabled = data['disabled'] == true;
          if (isArchived || isDisabled) continue;

          final ang = data['angkatan']?.toString().trim() ?? '';
          if (ang.isNotEmpty) {
            angkatanCounts[ang] = (angkatanCounts[ang] ?? 0) + 1;
          }
        }

        final activeAngkatans = angkatanCounts.keys.toList()..sort();
        final displayAngkatans = activeAngkatans.isNotEmpty
            ? activeAngkatans
            : ['2022', '2023', '2024'];

        return Column(
          children: [
            // Header Bar Navigasi Kembali ke Daftar Mapel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedSubjectMap = null;
                      });
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Kembali ke Daftar Mapel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(height: 24, width: 1, color: const Color(0xFFCBD5E1)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Soal Ujian: $subjectName',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${displayAngkatans.length} Angkatan Aktif Terdeteksi',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF10B981), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // TabBar Angkatan Aktif
            Expanded(
              child: DefaultTabController(
                length: displayAngkatans.length,
                child: Scaffold(
                  backgroundColor: const Color(0xFFF8FAFC),
                  appBar: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Container(
                      color: Colors.white,
                      child: TabBar(
                        isScrollable: true,
                        labelColor: const Color(0xFF10B981),
                        unselectedLabelColor: const Color(0xFF64748B),
                        indicatorColor: const Color(0xFF10B981),
                        indicatorWeight: 3,
                        tabs: displayAngkatans.map((ang) {
                          final count = angkatanCounts[ang] ?? 0;
                          return Tab(
                            child: Row(
                              children: [
                                const Icon(Icons.school_rounded, size: 15),
                                const SizedBox(width: 6),
                                Text(
                                  'Angkatan $ang',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                if (count > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: Text(
                                      '$count murid',
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF059669), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  body: TabBarView(
                    children: displayAngkatans.map((ang) {
                      return _buildQuestionBankForAngkatan(subjectId, subjectName, ang);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // TAMPILAN 3: Bank Soal untuk Angkatan Tertentu
  Widget _buildQuestionBankForAngkatan(String subjectId, String subjectName, String angkatan) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('subjects')
          .doc(subjectId)
          .collection('questions')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        final allDocs = snap.data?.docs ?? [];
        // Filter soal yang ditujukan untuk angkatan ini
        final qDocs = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final qAng = data['angkatan'] as String?;
          return qAng == null || qAng == angkatan;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bank Soal — Angkatan $angkatan',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        'Total Soal: ${qDocs.length} butir',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _addNewQuestionForm(subjectId, angkatan),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('Tambah Soal (Angkatan $angkatan)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: qDocs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.quiz_outlined, size: 48, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 12),
                            Text(
                              'Belum ada soal untuk Angkatan $angkatan.',
                              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Klik tombol "Tambah Soal" di atas untuk membuat soal baru.',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: qDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final qData = qDocs[idx].data() as Map<String, dynamic>;
                          final qId = qDocs[idx].id;
                          final text = qData['text'] ?? '';
                          final options = Map<String, dynamic>.from(qData['options'] ?? {});
                          final correctOpt = qData['correctOption'] ?? '';

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Soal ${idx + 1}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF059669)),
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                      onPressed: () => _deleteQuestion(subjectId, qId),
                                      tooltip: 'Hapus Soal',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  text,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 12),
                                ...options.entries.map((opt) {
                                  final isCorrect = opt.key == correctOpt;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isCorrect ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isCorrect ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${opt.key}.',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isCorrect ? const Color(0xFF059669) : const Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${opt.value}',
                                            style: TextStyle(
                                              color: isCorrect ? const Color(0xFF065F46) : const Color(0xFF334155),
                                              fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        if (isCorrect)
                                          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _deleteQuestion(String subjectId, String questionId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Soal'),
        content: const Text('Apakah Anda yakin ingin menghapus soal ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance
                    .collection('schools')
                    .doc(_schoolId)
                    .collection('events')
                    .doc(widget.eventId)
                    .collection('subjects')
                    .doc(subjectId)
                    .collection('questions')
                    .doc(questionId)
                    .delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Soal berhasil dihapus!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addNewQuestionForm(String subjectId, String angkatan) {
    final formKey = GlobalKey<FormState>();
    final textController = TextEditingController();
    final optA = TextEditingController();
    final optB = TextEditingController();
    final optC = TextEditingController();
    final optD = TextEditingController();
    final optE = TextEditingController();
    String correctOption = 'A';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (formCtx, setFormState) {
          return AlertDialog(
            title: Text('Buat Soal Baru — Angkatan $angkatan', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: textController,
                        decoration: const InputDecoration(labelText: 'Pertanyaan', border: OutlineInputBorder()),
                        maxLines: 3,
                        validator: (v) => v == null || v.isEmpty ? 'Pertanyaan wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: optA,
                        decoration: const InputDecoration(labelText: 'Pilihan A', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.isEmpty ? 'Pilihan A wajib diisi' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: optB,
                        decoration: const InputDecoration(labelText: 'Pilihan B', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.isEmpty ? 'Pilihan B wajib diisi' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: optC,
                        decoration: const InputDecoration(labelText: 'Pilihan C', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.isEmpty ? 'Pilihan C wajib diisi' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: optD,
                        decoration: const InputDecoration(labelText: 'Pilihan D (opsional)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: optE,
                        decoration: const InputDecoration(labelText: 'Pilihan E (opsional)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: correctOption,
                        decoration: const InputDecoration(labelText: 'Jawaban Benar', border: OutlineInputBorder()),
                        items: ['A', 'B', 'C', 'D', 'E'].map((opt) {
                          return DropdownMenuItem(value: opt, child: Text('Pilihan $opt'));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setFormState(() {
                              correctOption = val;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(formCtx), child: const Text('Batal')),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final optsMap = <String, String>{
                      'A': optA.text.trim(),
                      'B': optB.text.trim(),
                      'C': optC.text.trim(),
                    };
                    if (optD.text.trim().isNotEmpty) optsMap['D'] = optD.text.trim();
                    if (optE.text.trim().isNotEmpty) optsMap['E'] = optE.text.trim();

                    try {
                      await FirebaseFirestore.instance
                          .collection('schools')
                          .doc(_schoolId)
                          .collection('events')
                          .doc(widget.eventId)
                          .collection('subjects')
                          .doc(subjectId)
                          .collection('questions')
                          .add({
                        'text': textController.text.trim(),
                        'options': optsMap,
                        'correctOption': correctOption,
                        'angkatan': angkatan,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      if (formCtx.mounted) {
                        ScaffoldMessenger.of(formCtx).showSnackBar(
                          const SnackBar(content: Text('Soal berhasil ditambahkan!'), backgroundColor: Colors.green),
                        );
                        Navigator.pop(formCtx);
                      }
                    } catch (e) {
                      if (formCtx.mounted) {
                        ScaffoldMessenger.of(formCtx).showSnackBar(
                          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                child: const Text('Simpan', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: PENGAWAS RUANGAN
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPengawasTab() {
    if (_teacher == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('proctors')
          .where('teacherId', isEqualTo: _teacher!.id)
          .snapshots(),
      builder: (context, proctorSnap) {
        if (proctorSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final assignments = proctorSnap.data?.docs ?? [];

        if (assignments.isEmpty) {
          return const Center(child: Text('Tidak ada tugas pengawas ruangan untuk Anda di event ini.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: assignments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = assignments[index];
            final data = doc.data() as Map<String, dynamic>;
            final roomId = data['roomId'] as String;
            final sessionId = data['sessionId'] as String;
            final status = data['status'] ?? 'Belum Dimulai';

            return FutureBuilder<Map<String, String>>(
              future: _resolveRoomAndSessionNames(roomId, sessionId),
              builder: (ctx, nameSnap) {
                final roomName = nameSnap.data?['roomName'] ?? 'Memuat...';
                final sessionName = nameSnap.data?['sessionName'] ?? 'Memuat...';

                Color statusColor;
                switch (status) {
                  case 'Sedang Berlangsung':
                    statusColor = Colors.orange;
                    break;
                  case 'Selesai':
                    statusColor = Colors.green;
                    break;
                  default:
                    statusColor = Colors.blue;
                }

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const Icon(Icons.meeting_room_rounded, color: Color(0xFF64748B)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Ruangan: $roomName',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sesi: $sessionName',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          if (status == 'Belum Dimulai')
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _updateProctorStatus(doc.id, 'Sedang Berlangsung'),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Mulai Pengawasan'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                              ),
                            ),
                          if (status == 'Sedang Berlangsung')
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _updateProctorStatus(doc.id, 'Selesai'),
                                icon: const Icon(Icons.check_circle_outline_rounded),
                                label: const Text('Selesaikan Sesi'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                              ),
                            ),
                          if (status == 'Selesai')
                            const Expanded(
                              child: Center(
                                child: Text(
                                  'Sesi Pengawasan Selesai dilakukan.',
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>> _resolveRoomAndSessionNames(String roomId, String sessionId) async {
    String roomName = 'Ruangan';
    String sessionName = 'Sesi';

    try {
      final roomSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('rooms')
          .doc(roomId)
          .get();
      if (roomSnap.exists) {
        roomName = roomSnap.data()?['name'] ?? roomId;
      }

      final sessionSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('sessions')
          .doc(sessionId)
          .get();
      if (sessionSnap.exists) {
        sessionName = sessionSnap.data()?['name'] ?? sessionId;
      }
    } catch (_) {}

    return {
      'roomName': roomName,
      'sessionName': sessionName,
    };
  }

  Future<void> _updateProctorStatus(String proctorDocId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('proctors')
          .doc(proctorDocId)
          .update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status pengawasan diubah menjadi "$newStatus"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: KOREKSI UJIAN
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildKoreksiTab() {
    if (_teacher == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('timetable')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final timetables = snapshot.data?.docs ?? [];
        final myTimetables = timetables.where((doc) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final tIds = List<String>.from(data['teacherId'] ?? []);
          return tIds.contains(_teacher!.id);
        }).toList();

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: myTimetables.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, idx) {
            final tData = myTimetables[idx].data() as Map<String, dynamic>? ?? {};
            final subjectName = tData['subjectName'] ?? '';
            final className = tData['className'] ?? '';

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        subjectName,
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Kelas: $className',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Simulasi Lembar Jawaban Siswa',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF475569)),
                      ),
                      TextButton.icon(
                        onPressed: () => _viewSubmissionsDialog(subjectName, className),
                        icon: const Icon(Icons.assignment_turned_in, size: 16, color: Color(0xFF10B981)),
                        label: const Text('Buka Koreksi', style: TextStyle(color: Color(0xFF10B981))),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _viewSubmissionsDialog(String subjectName, String className) {
    // Generates a mock list of students for interactive demonstration of the grading page
    final List<Map<String, dynamic>> mockSubmissions = [
      {'name': 'Ahmad Fauzi', 'nis': '23401', 'status': 'Selesai', 'score': 85},
      {'name': 'Budi Santoso', 'nis': '23402', 'status': 'Selesai', 'score': 90},
      {'name': 'Citra Lestari', 'nis': '23403', 'status': 'Selesai', 'score': 0}, // Needs grading
      {'name': 'Dewi Sartika', 'nis': '23404', 'status': 'Belum Mengerjakan', 'score': 0},
      {'name': 'Eko Prasetyo', 'nis': '23405', 'status': 'Selesai', 'score': 72},
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text('Koreksi: $subjectName - $className', style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 500,
                height: 400,
                child: ListView.separated(
                  itemCount: mockSubmissions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (c, idx) {
                    final item = mockSubmissions[idx];
                    final isSubmitted = item['status'] == 'Selesai';
                    final score = item['score'] as int;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('NIS: ${item['nis']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isSubmitted)
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: score > 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    score > 0 ? 'Nilai: $score' : 'Butuh Koreksi',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: score > 0 ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Color(0xFF10B981), size: 18),
                                  onPressed: () => _gradeStudentDialog(item['name'], score, (newScore) {
                                    setDialogState(() {
                                      mockSubmissions[idx]['score'] = newScore;
                                    });
                                  }),
                                ),
                              ],
                            )
                          else
                            const Text(
                              'Belum Mengerjakan',
                              style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Tutup')),
              ],
            );
          },
        );
      },
    );
  }

  void _gradeStudentDialog(String studentName, int currentScore, ValueChanged<int> onGraded) {
    final scoreController = TextEditingController(text: currentScore > 0 ? '$currentScore' : '');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Beri Nilai: $studentName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Jawaban Siswa: [Pilihan Ganda Benar: 8/10, Soal Essai terisi lengkap]'),
              const SizedBox(height: 14),
              TextField(
                controller: scoreController,
                decoration: const InputDecoration(labelText: 'Skor / Nilai (0-100)', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () {
                final score = int.tryParse(scoreController.text.trim()) ?? 0;
                onGraded(score);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nilai siswa berhasil disimpan!'), backgroundColor: Colors.green),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text('Simpan Nilai', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
