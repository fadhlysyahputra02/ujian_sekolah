import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
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
  final String? tabName;

  const TeacherEventDetailPage({
    super.key,
    required this.eventId,
    required this.eventName,
    this.tabName,
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

  // Subcollection caches for subject matching
  List<Map<String, dynamic>> _timetableSubcollection = [];
  List<Map<String, dynamic>> _sessionsSubcollection = [];

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

    // Wait for auth details to load if they are still null or empty (e.g. during hot restart)
    if (authService.isLoading || authService.schoolId == null || authService.schoolId!.isEmpty) {
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!authService.isLoading && authService.schoolId != null && authService.schoolId!.isNotEmpty) {
          break;
        }
      }
    }

    _schoolId = authService.schoolId ?? '';
    final uid = authService.user?.uid ?? '';

    if (_schoolId.isEmpty || uid.isEmpty) {
      debugPrint("Cannot check permissions: schoolId or uid is empty");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

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
        final evDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('events')
            .doc(widget.eventId)
            .get();

        final evData = evDoc.data() ?? {};
        final timetableList = <Map<String, dynamic>>[];

        try {
          final results = await Future.wait([
            evDoc.reference.collection('timetable').get(),
            evDoc.reference.collection('sessions').orderBy('order').get(),
          ]);
          final timetableSnap = results[0];
          final sessionsSnap = results[1];
          for (var doc in timetableSnap.docs) {
            timetableList.add(doc.data());
          }
          _timetableSubcollection = timetableSnap.docs.map((d) {
            final data = d.data();
            data['_docId'] = d.id;
            return data;
          }).toList();
          _sessionsSubcollection = sessionsSnap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        } catch (e) {
          debugPrint('Error fetching timetable/sessions subcollections: $e');
        }

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

        for (var doc in timetableList) {
          final tIds = doc['teacherId'];
          final tName = doc['teacherName']?.toString() ?? '';
          bool matched = false;
          if (tIds is List && (tIds.contains(teacherId) || tIds.contains(_teacher!.uid))) {
            matched = true;
          } else if (tIds is String && (tIds == teacherId || tIds == _teacher!.uid)) {
            matched = true;
          } else if (tName.isNotEmpty && (tName.contains(_teacher!.displayName) || _teacher!.displayName.contains(tName))) {
            matched = true;
          }

          if (matched) {
            _isPembuatSoal = true;
            break;
          }
        }

        // 3. Check Proctoring (Pengawas Ruangan)
        final proctorGrid = draftState?['proctorGrid'] ?? evData['proctorGrid'];
        if (proctorGrid is Map && (proctorGrid.values.contains(teacherId) || proctorGrid.values.contains(_teacher!.uid))) {
          _isPengawas = true;
        }
        if (!_isPengawas) {
          try {
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
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint("Error checking teacher permissions: $e");
    } finally {
      if (mounted) {
        if (widget.tabName != null) {
          if (widget.tabName == 'pengawas') {
            _tabController.index = 1;
          } else if (widget.tabName == 'soal') {
            _tabController.index = 2;
          } else if (widget.tabName == 'ringkasan') {
            _tabController.index = 0;
          }
        }
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
              : _buildLockedTab('Buat Soal', 'Anda tidak ditugaskan sebagai pembuat soal pada event ujian ini.'),
          _isPengawas
              ? _buildPengawasTab()
              : _buildLockedTab('Pengawas Ruangan', 'Anda tidak ditugaskan sebagai pengawas ruangan pada event ujian ini.'),
          _isPembuatSoal
              ? _buildKoreksiTab()
              : _buildLockedTab('Koreksi Ujian', 'Anda tidak ditugaskan sebagai penilai/korektor soal pada event ujian ini.'),
        ],
      ),
    );
  }

  Widget _buildLockedTab(String tabTitle, String customMessage) {
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
                color: const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFCD34D), width: 2),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Akses Terkunci — $tabTitle',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              customMessage,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Silakan hubungi admin sekolah jika terdapat perubahan tugas.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: BUAT SOAL
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBuatSoalTab() {
    if (_teacher == null) return const SizedBox();

    if (_selectedSubjectMap != null) {
      return _buildAngkatanQuestionManager(
        _selectedSubjectMap!['id']!,
        _selectedSubjectMap!['name']!,
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .snapshots(),
      builder: (context, evSnap) {
        if (evSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        final evData = evSnap.data?.data() as Map<String, dynamic>? ?? {};
        final timetableList = <Map<String, dynamic>>[];

        // 1. Dari field draftState -> timetable
        final draftState = evData['draftState'] as Map<String, dynamic>?;
        if (draftState != null && draftState['timetable'] is List) {
          for (var item in (draftState['timetable'] as List)) {
            if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
          }
        }

        // 2. Dari top-level field timetable
        if (evData['timetable'] is List) {
          for (var item in (evData['timetable'] as List)) {
            if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
          }
        }

        // Kelompokkan berdasarkan mapel yang ditugaskan kepada guru ini
        final subjectGroups = <String, Map<String, dynamic>>{};

        void processEntry(Map<String, dynamic> data) {
          final tIds = data['teacherId'];
          final tName = data['teacherName']?.toString() ?? '';
          bool isAssigned = false;

          if (tIds is List && (tIds.contains(_teacher!.id) || ( _teacher!.uid != null && tIds.contains(_teacher!.uid)))) {
            isAssigned = true;
          } else if (tIds is String && (tIds == _teacher!.id || tIds == _teacher!.uid)) {
            isAssigned = true;
          } else if (tName.isNotEmpty && (tName.contains(_teacher!.displayName) || _teacher!.displayName.contains(tName))) {
            isAssigned = true;
          }

          final sName = data['subjectName'] as String? ?? 'Mata Pelajaran';

          if (isAssigned) {
            final sId = data['subjectId'] as String? ?? sName;
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
        }

        for (var entry in timetableList) {
          processEntry(entry);
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
        final qDocs = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final qAng = data['angkatan'] as String?;
          return qAng == null || qAng == angkatan;
        }).toList();

        qDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>? ?? {};
          final bData = b.data() as Map<String, dynamic>? ?? {};
          final aUrutan = aData['urutan'] ?? aData['index'] ?? 999999;
          final bUrutan = bData['urutan'] ?? bData['index'] ?? 999999;
          return (aUrutan as num).compareTo(bUrutan as num);
        });

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
                    onPressed: () => _showQuestionDialog(
                      subjectId: subjectId,
                      angkatan: angkatan,
                      questionIndex: qDocs.length,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'Tambah Soal (Angkatan $angkatan)',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                    : ReorderableListView.builder(
                        itemCount: qDocs.length,
                        buildDefaultDragHandles: false,
                        onReorder: (oldIndex, newIndex) async {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final item = qDocs.removeAt(oldIndex);
                          qDocs.insert(newIndex, item);

                          try {
                            final batch = FirebaseFirestore.instance.batch();
                            for (int i = 0; i < qDocs.length; i++) {
                              final ref = FirebaseFirestore.instance
                                  .collection('schools')
                                  .doc(_schoolId)
                                  .collection('events')
                                  .doc(widget.eventId)
                                  .collection('subjects')
                                  .doc(subjectId)
                                  .collection('questions')
                                  .doc(qDocs[i].id);
                              batch.update(ref, {'urutan': i});
                            }
                            await batch.commit();
                          } catch (e) {
                            debugPrint('Error reordering questions: $e');
                          }
                        },
                        itemBuilder: (ctx, idx) {
                          final qData = qDocs[idx].data() as Map<String, dynamic>;
                          final qId = qDocs[idx].id;

                          return QuestionCard(
                            key: ValueKey(qId),
                            qData: qData,
                            qId: qId,
                            index: idx + 1,
                            subjectId: subjectId,
                            angkatan: angkatan,
                            onEdit: (id, data, index) => _showQuestionDialog(
                              subjectId: subjectId,
                              angkatan: angkatan,
                              questionId: id,
                              questionData: data,
                              questionIndex: index,
                            ),
                            onDelete: _deleteQuestion,
                            dragHandle: ReorderableDragStartListener(
                              index: idx,
                              child: const Icon(
                                Icons.drag_indicator_rounded,
                                color: Color(0xFF94A3B8),
                                size: 20,
                              ),
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

  Future<String?> _pickAndUploadImage(String path) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;

      // 1. Get raw bytes of the picked image file
      Uint8List originalBytes;
      if (kIsWeb) {
        if (file.bytes == null) return null;
        originalBytes = file.bytes!;
      } else {
        if (file.path == null) return null;
        originalBytes = await File(file.path!).readAsBytes();
      }

      // 2. Decode, resize, and compress the image
      try {
        final decoded = img.decodeImage(originalBytes);
        if (decoded != null) {
          img.Image resized = decoded;
          // Scale down to max 800px to ensure the Base64 string remains compact (<100KB)
          if (decoded.width > 800 || decoded.height > 800) {
            if (decoded.width > decoded.height) {
              resized = img.copyResize(decoded, width: 800);
            } else {
              resized = img.copyResize(decoded, height: 800);
            }
          }
          // Compress to JPEG with quality 60%
          final jpg = img.encodeJpg(resized, quality: 60);
          final base64String = base64Encode(jpg);
          return 'data:image/jpeg;base64,$base64String';
        }
      } catch (ce) {
        debugPrint('Image compression failed: $ce');
        // Fallback to original bytes if decoding fails and size is reasonable (<800KB)
        if (originalBytes.lengthInBytes < 800 * 1024) {
          final base64String = base64Encode(originalBytes);
          return 'data:image/jpeg;base64,$base64String';
        } else {
          throw Exception('Gambar terlalu besar untuk diproses tanpa kompresi.');
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error processing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses gambar: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  Widget _buildImageWidget(String url, {double? width, double? height, BoxFit fit = BoxFit.contain}) {
    if (url.startsWith('data:image/')) {
      try {
        final base64Content = url.split(',')[1];
        final bytes = base64Decode(base64Content);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
        );
      } catch (e) {
        return const Center(child: Icon(Icons.broken_image, color: Colors.grey));
      }
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) =>
          const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
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

  void _showQuestionDialog({
    required String subjectId,
    required String angkatan,
    String? questionId,
    Map<String, dynamic>? questionData,
    int? questionIndex,
  }) {
    final isNew = (questionId == null);
    final formKey = GlobalKey<FormState>();
    final textController = TextEditingController(text: questionData?['text'] ?? '');

    final initialType = questionData?['type'] ??
        (questionData?['options'] != null && (questionData?['options'] as Map).isNotEmpty ? 'pilihan_ganda' : 'pilihan_ganda');
    String questionType = initialType;

    List<OptionField> optionFields = [];
    if (questionData?['options'] != null && (questionData?['options'] as Map).isNotEmpty) {
      final opts = Map<String, dynamic>.from(questionData!['options']);
      final sortedKeys = opts.keys.toList()..sort();
      optionFields = sortedKeys
          .map((k) => OptionField(k, TextEditingController(text: opts[k]?.toString() ?? '')))
          .toList();
    } else {
      optionFields = [
        OptionField('A', TextEditingController()),
        OptionField('B', TextEditingController()),
        OptionField('C', TextEditingController()),
        OptionField('D', TextEditingController()),
      ];
    }

    String correctOption = questionData?['correctOption'] ?? 'A';
    bool isEditing = isNew;

    String? questionImageUrl = questionData?['imageUrl'];
    Map<String, String> optionImages = Map<String, String>.from(questionData?['optionImages'] ?? {});
    bool isUploadingQuestionImage = false;
    Map<String, bool> isUploadingOptionImage = {};

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final validLabels = optionFields.map((o) => o.label).toList();
            if (!validLabels.contains(correctOption)) {
              correctOption = validLabels.isNotEmpty ? validLabels.first : 'A';
            }

            final headerColor = questionType == 'essay' ? const Color(0xFFDB2777) : const Color(0xFF4F46E5);
            final headerBg = questionType == 'essay' ? const Color(0xFFFDF2F8) : const Color(0xFFEEF2FF);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: headerBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_note_rounded : Icons.quiz_outlined,
                      color: headerColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing
                          ? (isNew ? 'Tambah Soal Baru' : 'Edit Soal Ujian')
                          : 'Detail Soal Ujian #${questionIndex ?? ""}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(dialogCtx),
                    tooltip: 'Tutup Dialog',
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: isEditing
                      ? Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Tipe Soal',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF475569)),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setDialogState(() => questionType = 'pilihan_ganda'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: questionType == 'pilihan_ganda'
                                              ? const Color(0xFFECFDF5)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: questionType == 'pilihan_ganda'
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFE2E8F0),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(Icons.quiz_rounded,
                                                color: questionType == 'pilihan_ganda'
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFF64748B),
                                                size: 20),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Pilihan Ganda',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: questionType == 'pilihan_ganda'
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setDialogState(() => questionType = 'essay'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: questionType == 'essay' ? const Color(0xFFFDF2F8) : Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: questionType == 'essay'
                                                ? const Color(0xFFDB2777)
                                                : const Color(0xFFE2E8F0),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(Icons.edit_note_rounded,
                                                color: questionType == 'essay'
                                                    ? const Color(0xFFDB2777)
                                                    : const Color(0xFF64748B),
                                                size: 20),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Esai / Essay',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: questionType == 'essay'
                                                    ? const Color(0xFFDB2777)
                                                    : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Pertanyaan Soal',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF475569)),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: textController,
                                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                                decoration: InputDecoration(
                                  hintText: 'Tulis pertanyaan di sini...',
                                  hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                                maxLines: 3,
                                validator: (v) => v == null || v.isEmpty ? 'Pertanyaan wajib diisi' : null,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Gambar Soal (Opsional)',
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF475569)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (isUploadingQuestionImage) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF4F46E5)),
                                    ),
                                  ),
                                ),
                              ] else if (questionImageUrl != null && questionImageUrl!.isNotEmpty) ...[
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        Container(
                                          color: const Color(0xFFF8FAFC),
                                          width: double.infinity,
                                          height: 180,
                                          child: _buildImageWidget(
                                            questionImageUrl!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: CircleAvatar(
                                            backgroundColor: Colors.red.withValues(alpha: 0.9),
                                            radius: 16,
                                            child: IconButton(
                                              icon: const Icon(Icons.delete_outline, color: Colors.white, size: 16),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: () {
                                                setDialogState(() {
                                                  questionImageUrl = null;
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ] else ...[
                                InkWell(
                                  onTap: () async {
                                    setDialogState(() => isUploadingQuestionImage = true);
                                    final url = await _pickAndUploadImage('questions');
                                    setDialogState(() {
                                      if (url != null) {
                                        questionImageUrl = url;
                                      }
                                      isUploadingQuestionImage = false;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF4F46E5), size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Tambah Gambar Soal',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF4F46E5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (questionType == 'pilihan_ganda') ...[
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Opsi Jawaban',
                                          style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF475569)),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Ketuk lingkaran huruf untuk memilih kunci jawaban',
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: const Color(0xFF10B981),
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    if (optionFields.length < 8)
                                      TextButton.icon(
                                        onPressed: () {
                                          setDialogState(() {
                                            final nextChar = String.fromCharCode('A'.codeUnitAt(0) + optionFields.length);
                                            optionFields.add(OptionField(nextChar, TextEditingController()));
                                          });
                                        },
                                        icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Color(0xFF4F46E5)),
                                        label: Text(
                                          'Tambah Opsi',
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF4F46E5)),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...optionFields.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final field = entry.value;
                                  final isCorrect = field.label == correctOption;
                                  final optionImgUrl = optionImages[field.label];
                                  final isUploadingOpt = isUploadingOptionImage[field.label] ?? false;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10.0),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isCorrect ? const Color(0xFFF0FDF4) : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isCorrect ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                                          width: isCorrect ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Tooltip(
                                                message: 'Jadikan kunci jawaban',
                                                child: InkWell(
                                                  onTap: () {
                                                    setDialogState(() {
                                                      correctOption = field.label;
                                                    });
                                                  },
                                                  borderRadius: BorderRadius.circular(100),
                                                  child: Container(
                                                    width: 32,
                                                    height: 32,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: isCorrect ? const Color(0xFF10B981) : const Color(0xFFF1F5F9),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: isCorrect ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                                                        width: 1.5,
                                                      ),
                                                      boxShadow: isCorrect
                                                          ? [
                                                              BoxShadow(
                                                                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                                                blurRadius: 6,
                                                                offset: const Offset(0, 2),
                                                              )
                                                            ]
                                                          : null,
                                                    ),
                                                    child: Text(
                                                      field.label,
                                                      style: GoogleFonts.inter(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                        color: isCorrect ? Colors.white : const Color(0xFF475569),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: TextFormField(
                                                  controller: field.controller,
                                                  style: GoogleFonts.inter(fontSize: 13),
                                                  decoration: const InputDecoration(
                                                    hintText: 'Tulis opsi jawaban di sini...',
                                                    border: InputBorder.none,
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                                  ),
                                                  validator: (v) => v == null || v.isEmpty ? 'Opsi ${field.label} wajib diisi' : null,
                                                ),
                                              ),
                                              if (isCorrect) ...[
                                                const SizedBox(width: 4),
                                                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                                              ],
                                              if (isUploadingOpt) ...[
                                                const SizedBox(width: 8),
                                                const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                                                ),
                                              ] else if (optionImgUrl == null || optionImgUrl.isEmpty) ...[
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  icon: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF64748B), size: 20),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                  onPressed: () async {
                                                    setDialogState(() => isUploadingOptionImage[field.label] = true);
                                                    final url = await _pickAndUploadImage('options_${field.label}');
                                                    setDialogState(() {
                                                      if (url != null) {
                                                        optionImages[field.label] = url;
                                                      }
                                                      isUploadingOptionImage[field.label] = false;
                                                    });
                                                  },
                                                  tooltip: 'Tambah Gambar Opsi',
                                                ),
                                              ],
                                              if (optionFields.length > 2) ...[
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline_rounded,
                                                      color: Color(0xFFEF4444), size: 20),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                  onPressed: () {
                                                    setDialogState(() {
                                                      optionFields.removeAt(idx);
                                                      // Restructure optionImages map upon label shifts
                                                      final newOptionImages = <String, String>{};
                                                      for (int k = 0; k < optionFields.length; k++) {
                                                        final oldLabel = optionFields[k].label;
                                                        final newLabel = String.fromCharCode('A'.codeUnitAt(0) + k);
                                                        optionFields[k].label = newLabel;
                                                        if (optionImages.containsKey(oldLabel)) {
                                                          newOptionImages[newLabel] = optionImages[oldLabel]!;
                                                        }
                                                      }
                                                      optionImages = newOptionImages;
                                                    });
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (optionImgUrl != null && optionImgUrl.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Stack(
                                              alignment: Alignment.topRight,
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Container(
                                                    color: const Color(0xFFF8FAFC),
                                                    width: double.infinity,
                                                    height: 150,
                                                    child: _buildImageWidget(
                                                      optionImgUrl,
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 6,
                                                  right: 6,
                                                  child: CircleAvatar(
                                                    backgroundColor: Colors.red.withValues(alpha: 0.9),
                                                    radius: 14,
                                                    child: IconButton(
                                                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 14),
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: () {
                                                        setDialogState(() {
                                                          optionImages.remove(field.label);
                                                        });
                                                      },
                                                      tooltip: 'Hapus Gambar Opsi',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                              if (questionType == 'essay') ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFFECDD3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline_rounded, color: Color(0xFFE11D48), size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Siswa akan menjawab soal ini secara tertulis (esai). Soal esai diperiksa manual oleh guru.',
                                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9F1239), fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: questionType == 'essay' ? const Color(0xFFFFF1F2) : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    questionType == 'essay' ? Icons.edit_note_rounded : Icons.quiz_outlined,
                                    size: 16,
                                    color: questionType == 'essay' ? const Color(0xFFE11D48) : const Color(0xFF059669),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    questionType == 'essay' ? 'Tipe: Esai / Essay' : 'Tipe: Pilihan Ganda',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: questionType == 'essay' ? const Color(0xFFE11D48) : const Color(0xFF059669),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Pertanyaan:',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              textController.text.trim(),
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600, fontSize: 15, color: const Color(0xFF0F172A)),
                            ),
                            if (questionImageUrl != null && questionImageUrl!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: const Color(0xFFF8FAFC),
                                  width: double.infinity,
                                  height: 200,
                                  child: _buildImageWidget(
                                    questionImageUrl!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (questionType == 'pilihan_ganda') ...[
                              Text(
                                'Pilihan Jawaban:',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 8),
                              ...optionFields.map((opt) {
                                final isCorrect = opt.label == correctOption;
                                final optImg = optionImages[opt.label];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isCorrect ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isCorrect ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isCorrect ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          opt.label,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: isCorrect ? Colors.white : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (optImg != null && optImg.isNotEmpty) ...[
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: _buildImageWidget(
                                            optImg,
                                            width: 36,
                                            height: 36,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Text(
                                          opt.controller.text,
                                          style: GoogleFonts.inter(
                                            color: isCorrect ? const Color(0xFF065F46) : const Color(0xFF334155),
                                            fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (isCorrect)
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                                    ],
                                  ),
                                );
                              }),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  'Ujian Esai/Tertulis. Soal ini tidak memerlukan pilihan ganda. Nilai diinput guru secara manual setelah ujian.',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              actions: [
                if (isEditing) ...[
                  TextButton(
                    onPressed: () {
                      if (isNew) {
                        Navigator.pop(dialogCtx);
                      } else {
                        setDialogState(() => isEditing = false);
                      }
                    },
                    child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final dataToSave = <String, dynamic>{
                          'text': textController.text.trim(),
                          'type': questionType,
                          'angkatan': angkatan,
                          'imageUrl': questionImageUrl,
                          'updatedAt': FieldValue.serverTimestamp(),
                        };
                        if (isNew) {
                          dataToSave['urutan'] = questionIndex ?? 0;
                        }

                        if (questionType == 'pilihan_ganda') {
                          final optsMap = <String, String>{};
                          for (final opt in optionFields) {
                            if (opt.controller.text.trim().isNotEmpty) {
                              optsMap[opt.label] = opt.controller.text.trim();
                            }
                          }
                          dataToSave['options'] = optsMap;
                          dataToSave['correctOption'] = correctOption;
                          dataToSave['optionImages'] = optionImages;
                        } else {
                          dataToSave['options'] = {};
                          dataToSave['correctOption'] = '';
                          dataToSave['optionImages'] = {};
                        }

                        try {
                          if (isNew) {
                            await FirebaseFirestore.instance
                                .collection('schools')
                                .doc(_schoolId)
                                .collection('events')
                                .doc(widget.eventId)
                                .collection('subjects')
                                .doc(subjectId)
                                .collection('questions')
                                .add(dataToSave);
                          } else {
                            await FirebaseFirestore.instance
                                .collection('schools')
                                .doc(_schoolId)
                                .collection('events')
                                .doc(widget.eventId)
                                .collection('subjects')
                                .doc(subjectId)
                                .collection('questions')
                                .doc(questionId)
                                .update(dataToSave);
                          }

                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(
                                content: Text(isNew ? 'Soal berhasil dibuat!' : 'Perubahan soal disimpan!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(dialogCtx);
                          }
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Simpan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: Text('Tutup', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _deleteQuestion(subjectId, questionId!);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Hapus Soal'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      setDialogState(() => isEditing = true);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit Soal'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: PENGAWAS RUANGAN
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPengawasTab() {
    if (_teacher == null) return const SizedBox();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .snapshots(),
      builder: (context, evSnap) {
        if (evSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        final evData = evSnap.data?.data() as Map<String, dynamic>? ?? {};
        final draftState = evData['draftState'] as Map<String, dynamic>?;

        // 1. Timetable List — prefer subcollection (real Firestore IDs)
        final timetableList = <Map<String, dynamic>>[];
        if (_timetableSubcollection.isNotEmpty) {
          timetableList.addAll(_timetableSubcollection);
        } else {
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
        }

        // 2. Rooms Map
        final roomsList = <Map<String, dynamic>>[];
        if (draftState != null && draftState['step4']?['rooms'] is List) {
          for (var r in (draftState['step4']['rooms'] as List)) {
            if (r is Map) roomsList.add(Map<String, dynamic>.from(r));
          }
        } else if (draftState != null && draftState['rooms'] is List) {
          for (var r in (draftState['rooms'] as List)) {
            if (r is Map) roomsList.add(Map<String, dynamic>.from(r));
          }
        }
        if (evData['rooms'] is List) {
          for (var r in (evData['rooms'] as List)) {
            if (r is Map) roomsList.add(Map<String, dynamic>.from(r));
          }
        }

        // 3. Sessions Map — prefer subcollection (has real Firestore IDs & order)
        final sessionsList = <Map<String, dynamic>>[];
        if (_sessionsSubcollection.isNotEmpty) {
          sessionsList.addAll(_sessionsSubcollection);
        } else if (draftState != null && draftState['step2']?['sessions'] is List) {
          for (var s in (draftState['step2']['sessions'] as List)) {
            if (s is Map) sessionsList.add(Map<String, dynamic>.from(s));
          }
        } else if (draftState != null && draftState['sessions'] is List) {
          for (var s in (draftState['sessions'] as List)) {
            if (s is Map) sessionsList.add(Map<String, dynamic>.from(s));
          }
        } else if (evData['sessions'] is List) {
          for (var s in (evData['sessions'] as List)) {
            if (s is Map) sessionsList.add(Map<String, dynamic>.from(s));
          }
        }

        // 4. Default Allocation Mode
        final defaultAllocMode = draftState?['allocationMode'] as String? ?? evData['allocationMode'] as String? ?? 'zigzag';

        // 5. Proctor Stream
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('schools')
              .doc(_schoolId)
              .collection('events')
              .doc(widget.eventId)
              .collection('proctors')
              .snapshots(),
          builder: (context, proctorSnap) {
            final proctorDocs = proctorSnap.data?.docs ?? [];
            final assignedDutyList = <Map<String, dynamic>>[];

            final teacherId = _teacher!.id;
            final teacherUid = _teacher!.uid;

            // Primary source of truth: proctorGrid from draftState or evData
            final proctorGrid = draftState?['proctorGrid'] as Map? ?? evData['proctorGrid'] as Map? ?? {};
            final teacherName = _teacher!.displayName;

            if (proctorGrid.isNotEmpty) {
              proctorGrid.forEach((keyStr, tidStr) {
                final k = keyStr.toString();
                final v = tidStr.toString();
                bool isCurrentTeacher = (v == teacherId ||
                    v == teacherUid ||
                    v == teacherName ||
                    v.toLowerCase() == teacherName.toLowerCase());

                if (isCurrentTeacher) {
                  final parts = k.split('_');
                  if (parts.length >= 6 && parts[0] == 'day' && parts[2] == 'session' && parts[4] == 'room') {
                    final dIdx = int.tryParse(parts[1]) ?? 0;
                    final sIdx = int.tryParse(parts[3]) ?? 0;
                    final rId = parts.sublist(5).join('_');

                    assignedDutyList.add({
                      'docId': 'grid_$k',
                      'roomId': rId,
                      'sessionId': 'session_$sIdx',
                      'dayIndex': dIdx,
                      'sessionIndex': sIdx,
                      'status': 'Belum Dimulai',
                    });
                  }
                }
              });
            }

            // Fallback: check proctorDocs subcollection if proctorGrid has no entries for this teacher
            if (assignedDutyList.isEmpty && proctorDocs.isNotEmpty) {
              for (var pDoc in proctorDocs) {
                final pData = pDoc.data() as Map<String, dynamic>;
                final pTeacher = pData['teacherId']?.toString() ?? '';
                final pTeacherName = pData['teacherName']?.toString() ?? '';

                bool isCurrentTeacher = (pTeacher == teacherId ||
                    pTeacher == teacherUid ||
                    pTeacher == teacherName ||
                    pTeacher.toLowerCase() == teacherName.toLowerCase() ||
                    pTeacherName == teacherName ||
                    pTeacherName.toLowerCase() == teacherName.toLowerCase());

                if (isCurrentTeacher) {
                  int dIdx = (pData['dayIndex'] as num?)?.toInt() ?? 0;
                  int sIdx = (pData['sessionIndex'] as num?)?.toInt() ?? 0;
                  final sId = (pData['sessionId'] ?? '').toString();

                  if (sIdx == 0 && sId.startsWith('session_')) {
                    final parsedS = int.tryParse(sId.replaceAll('session_', '')) ?? 0;
                    if (parsedS > 0) sIdx = parsedS - 1;
                  }

                  assignedDutyList.add({
                    'docId': pDoc.id,
                    'roomId': pData['roomId'] ?? '',
                    'sessionId': sId,
                    'dayIndex': dIdx,
                    'sessionIndex': sIdx,
                    'status': pData['status'] ?? 'Belum Dimulai',
                  });
                }
              }
            }

            // Sort duties chronologically by dayIndex, sessionIndex, roomId
            assignedDutyList.sort((a, b) {
              int cDay = (a['dayIndex'] as int).compareTo(b['dayIndex'] as int);
              if (cDay != 0) return cDay;
              int cSess = (a['sessionIndex'] as int).compareTo(b['sessionIndex'] as int);
              if (cSess != 0) return cSess;
              return (a['roomId'] as String).compareTo(b['roomId'] as String);
            });

            if (assignedDutyList.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEEF2FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_busy_rounded, size: 56, color: Color(0xFF4F46E5)),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Anda tidak ditugaskan sebagai pengawas ruangan pada event ujian ini.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF1E293B), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Silakan hubungi administrator sekolah jika terdapat kekeliruan.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Stream allocations
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('schools')
                  .doc(_schoolId)
                  .collection('events')
                  .doc(widget.eventId)
                  .collection('allocations')
                  .snapshots(),
              builder: (context, allocSnap) {
                final allocDocs = allocSnap.data?.docs ?? [];
                String? activeAllocId;
                String activeAllocMode = defaultAllocMode;

                if (allocDocs.isNotEmpty) {
                  activeAllocId = allocDocs.first.id;
                  final aData = allocDocs.first.data() as Map<String, dynamic>?;
                  if (aData != null && aData['mode'] != null) {
                    activeAllocMode = aData['mode'].toString();
                  }
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: assignedDutyList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 18),
                  itemBuilder: (context, index) {
                    final duty = assignedDutyList[index];
                    final docId = duty['docId'] as String;
                    final roomId = duty['roomId'] as String;
                    final dayIndex = duty['dayIndex'] as int;
                    final sessionIndex = duty['sessionIndex'] as int;
                    final status = duty['status'] as String;

                    // Date Label
                    final startDateStr = evData['startDate'] ?? draftState?['startDate'];
                    DateTime? startDate;
                    if (startDateStr is String) {
                      startDate = DateTime.tryParse(startDateStr);
                    } else if (startDateStr is Timestamp) {
                      startDate = startDateStr.toDate();
                    }
                    
                    final dutyDate = startDate?.add(Duration(days: dayIndex));
                    final dateLabel = dutyDate != null
                        ? '${_getNamaHari(dutyDate.weekday)}, ${dutyDate.day} ${_getNamaBulan(dutyDate.month)} ${dutyDate.year}'
                        : 'Hari Ke-${dayIndex + 1}';

                    // Session Name
                    String sessionLabel = 'Sesi ${sessionIndex + 1}';
                    if (sessionsList.length > sessionIndex) {
                      final sMap = sessionsList[sessionIndex];
                      final sName = sMap['name'] ?? sMap['sessionName'] ?? 'Sesi ${sessionIndex + 1}';
                      final sStart = sMap['startTime'] ?? sMap['start'] ?? '';
                      final sEnd = sMap['endTime'] ?? sMap['end'] ?? '';
                      sessionLabel = sStart.isNotEmpty ? '$sName ($sStart - $sEnd)' : sName;
                    }

                    // Room Name & Capacity
                    String roomName = roomId;
                    int roomCapacity = 0;
                    for (var r in roomsList) {
                      if (r['id'] == roomId || r['code'] == roomId || r['name'] == roomId) {
                        roomName = r['name'] ?? roomId;
                        roomCapacity = (r['capacity'] as num?)?.toInt() ?? 0;
                        break;
                      }
                    }

                    // Resolve Classes assigned to this room
                    final rawRoomAssignments = draftState?['step6']?['roomAssignments'] as Map? ?? draftState?['roomAssignments'] as Map? ?? evData['roomAssignments'] as Map? ?? {};
                    final roomAliases = {roomId, roomName}.where((s) => s.isNotEmpty).toSet();
                    final Set<String> normalizedAliases = {};
                    for (var a in roomAliases) {
                      final clean = a.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
                      if (clean.isNotEmpty) normalizedAliases.add(clean);
                    }

                    final roomClassNames = <String>{};
                    if (rawRoomAssignments.isNotEmpty) {
                      rawRoomAssignments.forEach((key, val) {
                        final kStr = key.toString();
                        final kClean = kStr.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
                        bool isMatch = roomAliases.contains(kStr);
                        if (!isMatch) {
                          for (var norm in normalizedAliases) {
                            if (kClean == norm || (norm.length > 2 && kClean.contains(norm)) || (kClean.length > 2 && norm.contains(kClean))) {
                              isMatch = true;
                              break;
                            }
                          }
                        }
                        if (isMatch && val is List) {
                          for (var c in val) {
                            if (c is Map) {
                              final cName = (c['className'] ?? c['classId'] ?? '').toString();
                              final cId = (c['classId'] ?? '').toString();
                              if (cName.isNotEmpty) roomClassNames.add(cName);
                              if (cId.isNotEmpty) roomClassNames.add(cId);
                            }
                          }
                        }
                      });
                    }

                    // Subjects for this Day & Session & Room Classes
                    final matchedSubjects = <String>[];
                    final targetKeyStr = 'day_${dayIndex}_session_$sessionIndex';
                    final targetSessionIdStr1 = 'session_$sessionIndex';
                    final targetSessionIdStr2 = 'session_${sessionIndex + 1}';

                    // Helper: extract date string from String or Firestore Timestamp
                    String extractDateStr(dynamic d) {
                      if (d is String) return d.length >= 10 ? d.substring(0, 10) : d;
                      if (d is Timestamp) {
                        final dt = d.toDate();
                        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                      }
                      return '';
                    }

                    // Group sessions by date → map (dayIndex, sessionIndex) to Firestore ID
                    String? targetRealSessionId;
                    if (_sessionsSubcollection.isNotEmpty) {
                      final dateGroups = <String, List<Map<String, dynamic>>>{};
                      for (var s in _sessionsSubcollection) {
                        final dStr = extractDateStr(s['date'] ?? s['startDate']);
                        if (dStr.isNotEmpty) {
                          dateGroups.putIfAbsent(dStr, () => []).add(s);
                        }
                      }
                      final sortedDates = dateGroups.keys.toList()..sort();
                      if (dayIndex < sortedDates.length) {
                        final dayDate = sortedDates[dayIndex];
                        final daySessions = List<Map<String, dynamic>>.from(dateGroups[dayDate]!);
                        daySessions.sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
                        if (sessionIndex < daySessions.length) {
                          targetRealSessionId = daySessions[sessionIndex]['id']?.toString();
                        }
                      }
                    }

                    // Fallback targetOrder for legacy matching
                    final int targetOrder = dayIndex * (sessionsList.isNotEmpty ? sessionsList.length : 2) + sessionIndex + 1;
                    debugPrint('[PengawasTab] dayIdx=$dayIndex sessIdx=$sessionIndex targetRealSessionId=$targetRealSessionId timetableCount=${timetableList.length} sessionsCount=${sessionsList.length}');

                    for (var tItem in timetableList) {
                      final tSessionId = (tItem['sessionId'] ?? '').toString();
                      final tDay = (tItem['dayIndex'] ?? tItem['day'] as num?)?.toInt();
                      final tSession = (tItem['sessionIndex'] ?? tItem['session'] as num?)?.toInt();
                      final tOrder = (tItem['order'] as num?)?.toInt();

                      bool isMatch = false;

                      if (tSessionId.isNotEmpty) {
                        if (tSessionId == targetKeyStr ||
                            tSessionId == targetSessionIdStr1 ||
                            tSessionId == targetSessionIdStr2 ||
                            tSessionId == '$sessionIndex' ||
                            tSessionId == '${sessionIndex + 1}' ||
                            (targetRealSessionId != null && tSessionId == targetRealSessionId)) {
                          isMatch = true;
                        }
                      } else if (tSession != null) {
                        bool dayMatch = tDay == null || tDay == dayIndex || tDay == (dayIndex + 1);
                        bool sessMatch = tSession == sessionIndex || tSession == (sessionIndex + 1);
                        isMatch = dayMatch && sessMatch;
                      } else if (tOrder != null) {
                        isMatch = (tOrder == targetOrder);
                      }

                      if (isMatch) {
                        final subj = (tItem['subjectName'] ?? tItem['subject'] ?? '').toString();
                        final cls = (tItem['className'] ?? tItem['classId'] ?? '').toString();
                        final cId = (tItem['classId'] ?? '').toString();

                        if (subj.isNotEmpty) {
                          if (roomClassNames.isEmpty || roomClassNames.contains(cls) || roomClassNames.contains(cId)) {
                            if (!matchedSubjects.contains(subj)) {
                              matchedSubjects.add(subj);
                            }
                          }
                        }
                      }
                    }

                    // Fallback 1: scheduleGrid
                    if (matchedSubjects.isEmpty) {
                      final scheduleGrid = draftState?['step6']?['scheduleGrid'] as Map? ?? draftState?['scheduleGrid'] as Map? ?? evData['scheduleGrid'] as Map? ?? {};
                      final gridKeys = [
                        'day_${dayIndex}_session_$sessionIndex',
                        'day_${dayIndex}_session_${sessionIndex + 1}',
                        'session_$sessionIndex',
                        'session_${sessionIndex + 1}',
                        '${sessionIndex + 1}',
                      ];
                      for (var gk in gridKeys) {
                        final schedSubjectIds = scheduleGrid[gk];
                        if (schedSubjectIds is List && schedSubjectIds.isNotEmpty) {
                          final subjectsList = draftState?['subjects'] as List? ?? evData['subjects'] as List? ?? [];
                          for (var sId in schedSubjectIds) {
                            String foundName = sId.toString();
                            for (var sItem in subjectsList) {
                              if (sItem is Map && (sItem['id'] == sId || sItem['code'] == sId || sItem['name'] == sId)) {
                                foundName = sItem['name'] ?? sId.toString();
                                break;
                              }
                            }
                            if (!matchedSubjects.contains(foundName)) matchedSubjects.add(foundName);
                          }
                        }
                      }
                    }

                    // Fallback 2: Check all subjects in event if still empty
                    if (matchedSubjects.isEmpty) {
                      final subjectsList = draftState?['subjects'] as List? ?? evData['subjects'] as List? ?? [];
                      for (var sItem in subjectsList) {
                        if (sItem is Map) {
                          final sName = (sItem['name'] ?? sItem['subjectName'] ?? '').toString();
                          if (sName.isNotEmpty && !matchedSubjects.contains(sName)) {
                            matchedSubjects.add(sName);
                          }
                        }
                      }
                    }

                    final subjectText = matchedSubjects.isNotEmpty ? matchedSubjects.join(' • ') : 'Semua Mata Pelajaran';

                    return _buildProctorCard(
                      docId: docId,
                      dateLabel: dateLabel,
                      sessionLabel: sessionLabel,
                      roomName: roomName,
                      roomId: roomId,
                      roomCapacity: roomCapacity,
                      subjectText: subjectText,
                      status: status,
                      allocationMode: activeAllocMode,
                      activeAllocId: activeAllocId,
                      dayIndex: dayIndex,
                      sessionIndex: sessionIndex,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProctorCard({
    required String docId,
    required String dateLabel,
    required String sessionLabel,
    required String roomName,
    required String roomId,
    required int roomCapacity,
    required String subjectText,
    required String status,
    required String allocationMode,
    required String? activeAllocId,
    required int dayIndex,
    required int sessionIndex,
  }) {
    Color statusColor;
    switch (status) {
      case 'Sedang Berlangsung':
        statusColor = const Color(0xFFF59E0B);
        break;
      case 'Selesai':
        statusColor = const Color(0xFF10B981);
        break;
      default:
        statusColor = const Color(0xFF3B82F6);
    }

    // Allocation Mode styling & label
    Color modeColor;
    IconData modeIcon;
    String modeLabel;
    switch (allocationMode.toLowerCase()) {
      case 'zigzag':
        modeColor = const Color(0xFFD97706);
        modeIcon = Icons.alt_route_rounded;
        modeLabel = 'Pola Posisi: ZIGZAG (Silang Kelas)';
        break;
      case 'random':
      case 'acak':
        modeColor = const Color(0xFF6366F1);
        modeIcon = Icons.shuffle_rounded;
        modeLabel = 'Pola Posisi: ACAK / RANDOM';
        break;
      default:
        modeColor = const Color(0xFF059669);
        modeIcon = Icons.grid_view_rounded;
        modeLabel = 'Pola Posisi: NORMAL';
    }

    void navigateToProctorRoom() {
      context.go(
        '/teacher/event/${widget.eventId}/proctor-room/$roomId?dayIndex=$dayIndex&sessionIndex=$sessionIndex&docId=$docId',
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: navigateToProctorRoom,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
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
              // 1. Header Bar: Date & Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF475569)),
                      const SizedBox(width: 8),
                      Text(
                        dateLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 14),

              // 2. Room & Session Details
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF4F46E5), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ruangan: $roomName',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            Text(
                              sessionLabel,
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3. Subject Name Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_rounded, color: Color(0xFF166534), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mata Pelajaran Ujian',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF166534)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subjectText,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF14532D)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Seating Pattern Mode Badge & Capacity
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: modeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: modeColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(modeIcon, size: 16, color: modeColor),
                        const SizedBox(width: 8),
                        Text(
                          modeLabel,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: modeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (roomCapacity > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$roomCapacity Bangku',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),

              // 5. Action Buttons: Masuk ke Ruangan
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (status == 'Belum Dimulai')
                        ElevatedButton.icon(
                          onPressed: docId.startsWith('grid_')
                              ? null
                              : () => _updateProctorStatus(docId, 'Sedang Berlangsung'),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Mulai Pengawasan'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      if (status == 'Sedang Berlangsung')
                        ElevatedButton.icon(
                          onPressed: docId.startsWith('grid_')
                              ? null
                              : () => _updateProctorStatus(docId, 'Selesai'),
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                          label: const Text('Selesaikan Sesi'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: navigateToProctorRoom,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Masuk ke Ruangan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
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



  String _getNamaHari(int day) {
    switch (day) {
      case DateTime.monday: return 'Senin';
      case DateTime.tuesday: return 'Selasa';
      case DateTime.wednesday: return 'Rabu';
      case DateTime.thursday: return 'Kamis';
      case DateTime.friday: return 'Jumat';
      case DateTime.saturday: return 'Sabtu';
      case DateTime.sunday: return 'Minggu';
      default: return '';
    }
  }

  String _getNamaBulan(int month) {
    const bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'];
    return (month >= 1 && month <= 12) ? bulan[month - 1] : '';
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

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(widget.eventId)
          .snapshots(),
      builder: (context, evSnap) {
        if (evSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        final evData = evSnap.data?.data() as Map<String, dynamic>? ?? {};
        final timetableList = <Map<String, dynamic>>[];

        // 1. Dari field draftState -> timetable
        final draftState = evData['draftState'] as Map<String, dynamic>?;
        if (draftState != null && draftState['timetable'] is List) {
          for (var item in (draftState['timetable'] as List)) {
            if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
          }
        }

        // 2. Dari top-level field timetable
        if (evData['timetable'] is List) {
          for (var item in (evData['timetable'] as List)) {
            if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
          }
        }

        // Kelompokkan berdasarkan mapel yang ditugaskan kepada guru ini
        final subjectGroups = <String, Map<String, dynamic>>{};

        for (var entry in timetableList) {
          final tIds = entry['teacherId'];
          final tName = entry['teacherName']?.toString() ?? '';
          bool isAssigned = false;

          if (tIds is List && (tIds.contains(_teacher!.id) || (_teacher!.uid != null && tIds.contains(_teacher!.uid)))) {
            isAssigned = true;
          } else if (tIds is String && (tIds == _teacher!.id || tIds == _teacher!.uid)) {
            isAssigned = true;
          } else if (tName.isNotEmpty && (tName.contains(_teacher!.displayName) || _teacher!.displayName.contains(tName))) {
            isAssigned = true;
          }

          if (isAssigned) {
            final sName = entry['subjectName'] as String? ?? 'Mata Pelajaran';
            final sId = entry['subjectId'] as String? ?? sName;
            final cName = entry['className'] as String? ?? '';

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
                  child: const Icon(Icons.assignment_turned_in_outlined, size: 48, color: Color(0xFFD97706)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Belum Ada Mapel untuk Dikoreksi',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Anda tidak ditugaskan sebagai penilai/korektor soal pada event ujian ini.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: subjectList.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, idx) {
            final subj = subjectList[idx];
            final subjectName = subj['name'] as String;
            final classesSet = subj['classes'] as Set<String>;
            final classesStr = classesSet.isNotEmpty ? classesSet.join(', ') : 'Semua Kelas';

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.fact_check_rounded, color: Color(0xFF10B981), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            subjectName,
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Kelas: $classesStr',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Lembar Jawaban Siswa',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF475569)),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _viewSubmissionsDialog(subjectName, classesStr),
                        icon: const Icon(Icons.assignment_turned_in, size: 16),
                        label: const Text('Buka Koreksi'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

class OptionField {
  String label;
  final TextEditingController controller;
  OptionField(this.label, this.controller);
}

class QuestionCard extends StatefulWidget {
  final Map<String, dynamic> qData;
  final String qId;
  final int index;
  final String subjectId;
  final String angkatan;
  final Function(String, Map<String, dynamic>, int) onEdit;
  final Function(String, String) onDelete;
  final Widget dragHandle;

  const QuestionCard({
    super.key,
    required this.qData,
    required this.qId,
    required this.index,
    required this.subjectId,
    required this.angkatan,
    required this.onEdit,
    required this.onDelete,
    required this.dragHandle,
  });

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.qData['text'] ?? '';
    final options = Map<String, dynamic>.from(widget.qData['options'] ?? {});
    final correctOpt = widget.qData['correctOption'] ?? '';
    final type = widget.qData['type'] ?? (options.isNotEmpty ? 'pilihan_ganda' : 'essay');
    final isEssay = type == 'essay';
    final qImgUrl = widget.qData['imageUrl'] as String?;
    final optImages = Map<String, dynamic>.from(widget.qData['optionImages'] ?? {});
    final parentState = context.findAncestorStateOfType<_TeacherEventDetailPageState>();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEssay ? const Color(0xFFFCE7F3) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    widget.dragHandle,
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isEssay ? const Color(0xFFFDF2F8) : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Soal ${widget.index}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isEssay ? const Color(0xFFDB2777) : const Color(0xFF059669),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isEssay ? const Color(0xFFFFF1F2) : const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isEssay ? 'Essay' : 'Pilihan Ganda',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: isEssay ? const Color(0xFFE11D48) : const Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: Color(0xFF4F46E5), size: 18),
                      onPressed: () => widget.onEdit(widget.qId, widget.qData, widget.index),
                      tooltip: 'Edit / Review Soal',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                      onPressed: () => widget.onDelete(widget.subjectId, widget.qId),
                      tooltip: 'Hapus Soal',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF64748B),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  text,
                  maxLines: _isExpanded ? null : 1,
                  overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                if (_isExpanded) ...[
                  if (qImgUrl != null && qImgUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: const Color(0xFFF8FAFC),
                        width: double.infinity,
                        height: 180,
                        child: parentState?._buildImageWidget(
                          qImgUrl,
                          fit: BoxFit.contain,
                        ) ?? Image.network(qImgUrl, fit: BoxFit.contain),
                      ),
                    ),
                  ],
                  if (!isEssay && options.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...(options.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((opt) {
                      final isCorrect = opt.key == correctOpt;
                      final optImg = optImages[opt.key] as String?;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isCorrect ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
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
                            if (optImg != null && optImg.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: parentState?._buildImageWidget(
                                  optImg,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                ) ?? Image.network(optImg, width: 36, height: 36, fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                opt.value?.toString() ?? '',
                                style: GoogleFonts.inter(
                                  color: isCorrect ? const Color(0xFF065F46) : const Color(0xFF334155),
                                  fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (isCorrect)
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                          ],
                        ),
                      );
                    }),
                  ] else if (isEssay) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Soal esai / tertulis.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
