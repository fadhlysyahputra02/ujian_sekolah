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
import 'package:intl/intl.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/teacher.dart';

import '../../../core/utils/url_history_helper.dart';

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

  // In-page correction view state
  String? _selectedCorrSubjectId;
  String _selectedCorrClass = 'ALL';

  // Subcollection caches for subject matching
  List<Map<String, dynamic>> _timetableSubcollection = [];
  List<Map<String, dynamic>> _sessionsSubcollection = [];

  @override
  void initState() {
    super.initState();
    int initialIdx = 0;
    if (widget.tabName == 'pengawas') {
      initialIdx = 1;
    } else if (widget.tabName == 'koreksi' || widget.tabName == 'soal') {
      initialIdx = 2;
    }
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialIdx);
    _tabController.addListener(_handleTabSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  @override
  void didUpdateWidget(covariant TeacherEventDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabName != oldWidget.tabName && widget.tabName != null) {
      int targetIdx = 0;
      if (widget.tabName == 'pengawas') {
        targetIdx = 1;
      } else if (widget.tabName == 'koreksi' || widget.tabName == 'soal') {
        targetIdx = 2;
      }
      if (_tabController.index != targetIdx) {
        _tabController.animateTo(targetIdx);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      return;
    }
    String targetTab = 'buatsoal';
    if (_tabController.index == 1) {
      targetTab = 'pengawas';
    } else if (_tabController.index == 2) {
      targetTab = 'koreksi';
    }

    if (kIsWeb) {
      try {
        final nameParam = Uri.encodeComponent(widget.eventName);
        final newUrl = '/#/teacher/event/${widget.eventId}/$targetTab?name=$nameParam';
        updateWebUrlHistory(newUrl);
      } catch (_) {}
    }
  }

  static final Map<String, Map<String, dynamic>> _detailCache = {};
  static final Map<String, DateTime> _detailCacheTime = {};

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

    final cacheKey = '${_schoolId}_${widget.eventId}_$uid';
    final now = DateTime.now();

    if (_detailCache.containsKey(cacheKey) &&
        _detailCacheTime.containsKey(cacheKey) &&
        now.difference(_detailCacheTime[cacheKey]!).inMinutes < 5) {
      final cached = _detailCache[cacheKey]!;
      _teacher = cached['teacher'] as Teacher?;
      _timetableSubcollection = List<Map<String, dynamic>>.from(cached['timetableSubcollection'] ?? []);
      _sessionsSubcollection = List<Map<String, dynamic>>.from(cached['sessionsSubcollection'] ?? []);
      _isPembuatSoal = cached['isPembuatSoal'] == true;
      _isPengawas = cached['isPengawas'] == true;

      if (mounted) {
        if (widget.tabName != null) {
          if (widget.tabName == 'pengawas') {
            _tabController.index = 1;
          } else if (widget.tabName == 'koreksi' || widget.tabName == 'soal') {
            _tabController.index = 2;
          } else if (widget.tabName == 'buatsoal' || widget.tabName == 'ringkasan') {
            _tabController.index = 0;
          }
        }
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
            evDoc.reference.collection('sessions').get(),
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
            data['_docId'] = d.id;
            return data;
          }).toList();
          _sessionsSubcollection.sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
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

        _detailCache[cacheKey] = {
          'teacher': _teacher,
          'timetableSubcollection': _timetableSubcollection,
          'sessionsSubcollection': _sessionsSubcollection,
          'isPembuatSoal': _isPembuatSoal,
          'isPengawas': _isPengawas,
        };
        _detailCacheTime[cacheKey] = DateTime.now();
      }
    } catch (e) {
      debugPrint("Error checking teacher permissions: $e");
    } finally {
      if (mounted) {
        if (widget.tabName != null) {
          if (widget.tabName == 'pengawas') {
            _tabController.index = 1;
          } else if (widget.tabName == 'koreksi' || widget.tabName == 'soal') {
            _tabController.index = 2;
          } else if (widget.tabName == 'buatsoal' || widget.tabName == 'ringkasan') {
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            )
          : TabBarView(
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

        // 1. Dari subkoleksi timetable
        if (_timetableSubcollection.isNotEmpty) {
          timetableList.addAll(_timetableSubcollection);
        }

        // 2. Dari field draftState -> timetable
        final draftState = evData['draftState'] as Map<String, dynamic>?;
        if (draftState != null && draftState['timetable'] is List) {
          for (var item in (draftState['timetable'] as List)) {
            if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
          }
        }

        // 3. Dari top-level field timetable
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

  double _getDetectedPgScore(List<DocumentSnapshot> qDocs) {
    for (var doc in qDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final type = data['type'] ??
          ((data['options'] != null && (data['options'] as Map).isNotEmpty) ? 'pilihan_ganda' : 'essay');
      if (type == 'pilihan_ganda' && data['score'] != null) {
        return (data['score'] as num).toDouble();
      }
    }
    return 5.0;
  }

  double _getDetectedEssayScore(List<DocumentSnapshot> qDocs) {
    for (var doc in qDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final type = data['type'] ??
          ((data['options'] != null && (data['options'] as Map).isNotEmpty) ? 'pilihan_ganda' : 'essay');
      if (type == 'essay' && data['score'] != null) {
        return (data['score'] as num).toDouble();
      }
    }
    return 20.0;
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

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('schools')
              .doc(_schoolId)
              .collection('events')
              .doc(widget.eventId)
              .collection('subjects')
              .doc(subjectId)
              .snapshots(),
          builder: (context, subjectSnap) {
            final subData = subjectSnap.data?.data() as Map<String, dynamic>? ?? {};
            final isRandomized = subData['randomizeQuestions_$angkatan'] == true;

            final defaultPgScore = (subData['defaultPgScore_$angkatan'] as num?)?.toDouble() ??
                _getDetectedPgScore(qDocs);
            final defaultEssayScore = (subData['defaultEssayScore_$angkatan'] as num?)?.toDouble() ??
                _getDetectedEssayScore(qDocs);

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bank Soal — Angkatan $angkatan',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Soal: ${qDocs.length} butir',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: isRandomized ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isRandomized ? const Color(0xFF93C5FD) : const Color(0xFFCBD5E1),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shuffle_rounded,
                                  size: 16,
                                  color: isRandomized ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Acak Soal Murid',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isRandomized ? const Color(0xFF1E40AF) : const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Transform.scale(
                                  scale: 0.85,
                                  child: Switch(
                                    value: isRandomized,
                                    activeColor: const Color(0xFF2563EB),
                                    activeTrackColor: const Color(0xFFBFDBFE),
                                    inactiveThumbColor: const Color(0xFF94A3B8),
                                    inactiveTrackColor: const Color(0xFFE2E8F0),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (val) async {
                                      await FirebaseFirestore.instance
                                          .collection('schools')
                                          .doc(_schoolId)
                                          .collection('events')
                                          .doc(widget.eventId)
                                          .collection('subjects')
                                          .doc(subjectId)
                                          .set({
                                            'randomizeQuestions_$angkatan': val,
                                          }, SetOptions(merge: true));
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () => _showQuestionDialog(
                              subjectId: subjectId,
                              angkatan: angkatan,
                              questionIndex: qDocs.length,
                              defaultPgScore: defaultPgScore,
                              defaultEssayScore: defaultEssayScore,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(
                              'Tambah Soal',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTotalScoreSummaryBanner(subjectId, subjectName, angkatan, qDocs, defaultPgScore, defaultEssayScore),
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
                              defaultPgScore: defaultPgScore,
                              defaultEssayScore: defaultEssayScore,
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
      },
    );
  }

  Widget _buildTotalScoreSummaryBanner(
      String subjectId,
      String subjectName,
      String angkatan,
      List<DocumentSnapshot> qDocs,
      double defaultPgScore,
      double defaultEssayScore) {
    int pgCount = 0;
    double pgTotalScore = 0;
    int essayCount = 0;
    double essayTotalScore = 0;

    for (var doc in qDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final type = data['type'] ??
          ((data['options'] != null && (data['options'] as Map).isNotEmpty) ? 'pilihan_ganda' : 'essay');
      final score = (data['score'] as num?)?.toDouble() ?? (type == 'essay' ? defaultEssayScore : defaultPgScore);

      if (type == 'pilihan_ganda') {
        pgCount++;
        pgTotalScore += score;
      } else {
        essayCount++;
        essayTotalScore += score;
      }
    }

    final grandTotal = pgTotalScore + essayTotalScore;
    final isPerfect = (grandTotal == 100.0);
    final isUnder = (grandTotal < 100.0);

    final bgCard = isPerfect
        ? const Color(0xFFECFDF5)
        : (isUnder ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2));
    final borderColor = isPerfect
        ? const Color(0xFFA7F3D0)
        : (isUnder ? const Color(0xFFFDE68A) : const Color(0xFFFCA5A5));
    final iconColor = isPerfect
        ? const Color(0xFF059669)
        : (isUnder ? const Color(0xFFD97706) : const Color(0xFFDC2626));
    final textColor = isPerfect
        ? const Color(0xFF065F46)
        : (isUnder ? const Color(0xFF92400E) : const Color(0xFF991B1B));
    final iconData = isPerfect
        ? Icons.check_circle_rounded
        : (isUnder ? Icons.warning_amber_rounded : Icons.error_outline_rounded);

    String statusText = '';
    if (isPerfect) {
      statusText = '✅ Total Akumulasi Skor Pas 100 Poin (Sesuai Standar Ujian)';
    } else if (isUnder) {
      final diff = (100.0 - grandTotal).toStringAsFixed(grandTotal % 1 == 0 ? 0 : 1);
      statusText = '⚠️ Total Akumulasi Skor: ${grandTotal.toStringAsFixed(grandTotal % 1 == 0 ? 0 : 1)} / 100 Poin (Kurang $diff Poin)';
    } else {
      final diff = (grandTotal - 100.0).toStringAsFixed(grandTotal % 1 == 0 ? 0 : 1);
      statusText = '⚠️ Total Akumulasi Skor: ${grandTotal.toStringAsFixed(grandTotal % 1 == 0 ? 0 : 1)} / 100 Poin (Kelebihan $diff Poin)';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconData, color: iconColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Pilihan Ganda ($pgCount soal): ${pgTotalScore.toStringAsFixed(pgTotalScore % 1 == 0 ? 0 : 1)} pt',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569), fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '•',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                    ),
                    Text(
                      'Essay ($essayCount soal): ${essayTotalScore.toStringAsFixed(essayTotalScore % 1 == 0 ? 0 : 1)} pt',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _showBulkScoreDialog(
              subjectId: subjectId,
              angkatan: angkatan,
              qDocs: qDocs,
              defaultPgScore: defaultPgScore,
              defaultEssayScore: defaultEssayScore,
            ),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Text(
              'Atur Skor Massal',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              elevation: 0,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showBulkScoreDialog({
    required String subjectId,
    required String angkatan,
    required List<DocumentSnapshot> qDocs,
    double defaultPgScore = 5.0,
    double defaultEssayScore = 20.0,
  }) {
    final pgStr = defaultPgScore % 1 == 0 ? defaultPgScore.toInt().toString() : defaultPgScore.toString();
    final essayStr = defaultEssayScore % 1 == 0 ? defaultEssayScore.toInt().toString() : defaultEssayScore.toString();

    final pgScoreController = TextEditingController(text: pgStr);
    final essayScoreController = TextEditingController(text: essayStr);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tune_rounded, color: Color(0xFF2563EB), size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Pengaturan Skor Massal',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Atur skor secara serentak untuk seluruh soal di Angkatan $angkatan.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            Text(
              'Skor per Soal Pilihan Ganda',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: pgScoreController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                suffixText: 'poin',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Skor Maksimal per Soal Essay',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: essayScoreController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                suffixText: 'poin',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final pgScore = double.tryParse(pgScoreController.text.trim()) ?? defaultPgScore;
              final essayScore = double.tryParse(essayScoreController.text.trim()) ?? defaultEssayScore;

              Navigator.pop(ctx);

              try {
                final batch = FirebaseFirestore.instance.batch();
                int updatedCount = 0;

                for (var doc in qDocs) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final type = data['type'] ??
                      ((data['options'] != null && (data['options'] as Map).isNotEmpty) ? 'pilihan_ganda' : 'essay');
                  final newScore = (type == 'pilihan_ganda') ? pgScore : essayScore;

                  final ref = FirebaseFirestore.instance
                      .collection('schools')
                      .doc(_schoolId)
                      .collection('events')
                      .doc(widget.eventId)
                      .collection('subjects')
                      .doc(subjectId)
                      .collection('questions')
                      .doc(doc.id);

                  batch.update(ref, {'score': newScore});
                  updatedCount++;
                }

                // Also save default scores to subject doc
                final subjectRef = FirebaseFirestore.instance
                    .collection('schools')
                    .doc(_schoolId)
                    .collection('events')
                    .doc(widget.eventId)
                    .collection('subjects')
                    .doc(subjectId);

                batch.set(subjectRef, {
                  'defaultPgScore_$angkatan': pgScore,
                  'defaultEssayScore_$angkatan': essayScore,
                }, SetOptions(merge: true));

                await batch.commit();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Berhasil memperbarui skor untuk $updatedCount soal!'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal memperbarui skor massal: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Terapkan Ke Semua Soal', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
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
    double defaultPgScore = 5.0,
    double defaultEssayScore = 20.0,
  }) {
    final isNew = (questionId == null);
    final formKey = GlobalKey<FormState>();
    final textController = TextEditingController(text: questionData?['text'] ?? '');

    final initialType = questionData?['type'] ??
        (questionData?['options'] != null && (questionData?['options'] as Map).isNotEmpty ? 'pilihan_ganda' : 'pilihan_ganda');
    String questionType = initialType;

    final initialScoreVal = (questionData?['score'] as num?)?.toDouble() ??
        (initialType == 'essay' ? defaultEssayScore : defaultPgScore);
    final scoreStr = initialScoreVal % 1 == 0 ? initialScoreVal.toInt().toString() : initialScoreVal.toString();

    final scoreController = TextEditingController(text: scoreStr);

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
    bool isEditing = true;

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
                                      onTap: () {
                                        setDialogState(() {
                                          questionType = 'pilihan_ganda';
                                          if (isNew) {
                                            final s = defaultPgScore;
                                            scoreController.text = s % 1 == 0 ? s.toInt().toString() : s.toString();
                                          }
                                        });
                                      },
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
                                      onTap: () {
                                        setDialogState(() {
                                          questionType = 'essay';
                                          if (isNew) {
                                            final s = defaultEssayScore;
                                            scoreController.text = s % 1 == 0 ? s.toInt().toString() : s.toString();
                                          }
                                        });
                                      },
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
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          questionType == 'essay' ? 'Skor Maksimal Soal' : 'Bobot Skor Soal',
                                          style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF475569)),
                                        ),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                          controller: scoreController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                                          decoration: InputDecoration(
                                            suffixText: 'poin',
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
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          ),
                                          validator: (v) {
                                            if (v == null || v.trim().isEmpty) return 'Skor wajib diisi';
                                            if (double.tryParse(v.trim()) == null) return 'Masukkan angka yang valid';
                                            return null;
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
                                                  validator: (v) {
                                                    final hasImg = optionImgUrl != null && optionImgUrl.isNotEmpty;
                                                    if (!hasImg && (v == null || v.trim().isEmpty)) {
                                                      return 'Opsi ${field.label} wajib diisi (teks atau gambar)';
                                                    }
                                                    return null;
                                                  },
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
                      Navigator.pop(dialogCtx);
                    },
                    child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final authService = Provider.of<AuthService>(context, listen: false);
                        String currentUserName = _teacher?.displayName ?? '';
                        if (currentUserName.isEmpty) {
                          currentUserName = authService.user?.displayName ?? '';
                        }
                        if (currentUserName.isEmpty) {
                          currentUserName = authService.user?.email ?? 'Guru';
                        }

                        final dataToSave = <String, dynamic>{
                          'text': textController.text.trim(),
                          'type': questionType,
                          'score': double.tryParse(scoreController.text.trim()) ?? (questionType == 'essay' ? 10.0 : 5.0),
                          'angkatan': angkatan,
                          'imageUrl': questionImageUrl,
                          'updatedAt': FieldValue.serverTimestamp(),
                          'updatedByName': currentUserName,
                          'updatedBy': _teacher?.id ?? authService.user?.uid ?? '',
                        };
                        if (isNew) {
                          dataToSave['urutan'] = questionIndex ?? 0;
                          dataToSave['createdByName'] = currentUserName;
                          dataToSave['createdBy'] = _teacher?.id ?? authService.user?.uid ?? '';
                          dataToSave['createdAt'] = FieldValue.serverTimestamp();
                        }

                        if (questionType == 'pilihan_ganda') {
                          final optsMap = <String, String>{};
                          for (final opt in optionFields) {
                            final txt = opt.controller.text.trim();
                            final optImg = optionImages[opt.label];
                            if (txt.isNotEmpty || (optImg != null && optImg.isNotEmpty)) {
                              optsMap[opt.label] = txt;
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

        // 4. Proctor Stream
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
            final teacherId = _teacher!.id;
            final teacherUid = _teacher!.uid ?? '';
            final teacherName = _teacher!.displayName;
            final teacherNip = _teacher!.nip;

            // Helper to match current teacher strictly across all possible ID/Name formats
            bool matchesCurrentTeacher(String tid) {
              final target = tid.trim().toLowerCase();
              if (target.isEmpty) return false;

              final myId = teacherId.trim().toLowerCase();
              final myUid = teacherUid.trim().toLowerCase();
              final myName = teacherName.trim().toLowerCase();
              final myNip = teacherNip.trim().toLowerCase();

              // 1. Direct exact matches
              if (target == myId) return true;
              if (myUid.isNotEmpty && target == myUid) return true;
              if (myName.isNotEmpty && target == myName) return true;
              if (myNip.isNotEmpty && target == myNip) return true;

              // 2. Strict normalized comparison (strip 'guru', spaces, underscores, dashes)
              final cleanTarget = target.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
              final cleanMyName = myName.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
              final cleanMyId = myId.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
              final cleanMyNip = myNip.replaceAll('guru', '').replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');

              if (cleanTarget.isNotEmpty) {
                if (cleanTarget == cleanMyName) return true;
                if (cleanTarget == cleanMyId) return true;
                if (cleanMyNip.isNotEmpty && cleanTarget == cleanMyNip) return true;
              }

              return false;
            }

            // Primary source of truth: proctorGrid from draftState or evData
            final proctorGrid = draftState?['proctorGrid'] as Map? ?? evData['proctorGrid'] as Map? ?? {};
            final rawDutyList = <Map<String, dynamic>>[];

            if (proctorGrid.isNotEmpty) {
              proctorGrid.forEach((keyStr, tidStr) {
                final k = keyStr.toString();
                final v = tidStr.toString();

                if (matchesCurrentTeacher(v)) {
                  final parts = k.split('_');
                  if (parts.length >= 6 && parts[0] == 'day' && parts[2] == 'session' && parts[4] == 'room') {
                    final dIdx = int.tryParse(parts[1]) ?? 0;
                    final sIdx = int.tryParse(parts[3]) ?? 0;
                    final rId = parts.sublist(5).join('_');

                    rawDutyList.add({
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

            // Supplement with proctorDocs subcollection
            if (proctorDocs.isNotEmpty) {
              for (var pDoc in proctorDocs) {
                final pData = pDoc.data() as Map<String, dynamic>;
                final pTeacher = pData['teacherId']?.toString() ?? '';
                final pTeacherName = pData['teacherName']?.toString() ?? '';

                if (matchesCurrentTeacher(pTeacher) || matchesCurrentTeacher(pTeacherName)) {
                  int dIdx = (pData['dayIndex'] as num?)?.toInt() ?? -1;
                  int sIdx = (pData['sessionIndex'] as num?)?.toInt() ?? -1;
                  final sId = (pData['sessionId'] ?? '').toString();

                  if (dIdx < 0 || sIdx < 0) {
                    Map<String, dynamic>? matchedSession;
                    if (_sessionsSubcollection.isNotEmpty) {
                      for (var sObj in _sessionsSubcollection) {
                        if (sObj['id'] == sId || sObj['tempId'] == sId || sObj['_docId'] == sId) {
                          matchedSession = sObj;
                          break;
                        }
                      }
                    }

                    if (matchedSession != null) {
                      final tempId = (matchedSession['tempId'] ?? '').toString();
                      if (tempId.startsWith('day_')) {
                        final parts = tempId.split('_');
                        if (parts.length >= 4) {
                          if (dIdx < 0) dIdx = int.tryParse(parts[1]) ?? 0;
                          if (sIdx < 0) sIdx = int.tryParse(parts[3]) ?? 0;
                        }
                      } else {
                        final order = (matchedSession['order'] as num?)?.toInt() ?? 1;
                        final numSessionsPerDay = (sessionsList.isNotEmpty ? sessionsList.length : 2);
                        if (dIdx < 0) dIdx = (order - 1) ~/ numSessionsPerDay;
                        if (sIdx < 0) sIdx = (order - 1) % numSessionsPerDay;
                      }
                    } else if (sId.startsWith('day_')) {
                      final parts = sId.split('_');
                      if (parts.length >= 4) {
                        if (dIdx < 0) dIdx = int.tryParse(parts[1]) ?? 0;
                        if (sIdx < 0) sIdx = int.tryParse(parts[3]) ?? 0;
                      }
                    }

                    if (dIdx < 0) dIdx = 0;
                    if (sIdx < 0) sIdx = 0;
                  }

                  rawDutyList.add({
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

            // Deduplicate duties by dayIndex_sessionIndex_roomId
            final uniqueDutyMap = <String, Map<String, dynamic>>{};
            for (var duty in rawDutyList) {
              final uniqueKey = '${duty['dayIndex']}_${duty['sessionIndex']}_${duty['roomId']}';
              if (!uniqueDutyMap.containsKey(uniqueKey) || !uniqueDutyMap[uniqueKey]!['docId'].toString().startsWith('grid_')) {
                uniqueDutyMap[uniqueKey] = duty;
              }
            }

            final assignedDutyList = uniqueDutyMap.values.toList();

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
                if (allocDocs.isNotEmpty) {
                  activeAllocId = allocDocs.first.id;
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

                    final targetSId = duty['sessionId']?.toString() ?? '';
                    Map<String, dynamic>? matchedSession;

                    if (targetSId.isNotEmpty) {
                      for (var s in sessionsList) {
                        if (s['id'] == targetSId || s['_docId'] == targetSId || s['tempId'] == targetSId) {
                          matchedSession = s;
                          break;
                        }
                      }
                    }
                    if (matchedSession == null && sessionsList.length > sessionIndex) {
                      matchedSession = sessionsList[sessionIndex];
                    }

                    // Date Label - Prefer date stored in session document
                    DateTime? dutyDate;
                    if (matchedSession != null) {
                      final rawDate = matchedSession['date'] ?? matchedSession['startDate'];
                      if (rawDate is String && rawDate.isNotEmpty) {
                        dutyDate = DateTime.tryParse(rawDate);
                      } else if (rawDate is Timestamp) {
                        dutyDate = rawDate.toDate();
                      }
                    }

                    if (dutyDate == null) {
                      final startDateStr = evData['startDate'] ?? draftState?['startDate'];
                      DateTime? startDate;
                      if (startDateStr is String) {
                        startDate = DateTime.tryParse(startDateStr);
                      } else if (startDateStr is Timestamp) {
                        startDate = startDateStr.toDate();
                      }
                      if (startDate != null) {
                        dutyDate = startDate.add(Duration(days: dayIndex));
                      }
                    }

                    final dateLabel = dutyDate != null
                        ? '${_getNamaHari(dutyDate.weekday)}, ${dutyDate.day} ${_getNamaBulan(dutyDate.month)} ${dutyDate.year}'
                        : 'Hari Ke-${dayIndex + 1}';

                    // Session Name - Prefer data in matchedSession
                    String sessionLabel = 'Sesi ${sessionIndex + 1}';
                    if (matchedSession != null) {
                      final sName = matchedSession['name'] ?? matchedSession['sessionName'] ?? 'Sesi ${sessionIndex + 1}';
                      final sStart = matchedSession['startTime'] ?? matchedSession['start'] ?? '';
                      final sEnd = matchedSession['endTime'] ?? matchedSession['end'] ?? '';
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

                      if (tDay != null && tDay != dayIndex) {
                        isMatch = false;
                      } else if (tSessionId == targetKeyStr || (targetRealSessionId != null && tSessionId == targetRealSessionId)) {
                        isMatch = true;
                      } else if (tSessionId.isNotEmpty) {
                        if (tDay == dayIndex && (tSessionId == targetSessionIdStr1 || tSessionId == '$sessionIndex')) {
                          isMatch = true;
                        }
                      } else if (tSession != null) {
                        bool dayMatch = tDay == null || tDay == dayIndex;
                        bool sessMatch = tSession == sessionIndex;
                        isMatch = dayMatch && sessMatch;
                      } else if (tOrder != null) {
                        isMatch = (tOrder == targetOrder);
                      }

                       if (isMatch) {
                        final subj = (tItem['subjectName'] ?? tItem['subject'] ?? '').toString().trim();
                        final cls = (tItem['className'] ?? tItem['classId'] ?? '').toString().trim();
                        final cId = (tItem['classId'] ?? '').toString().trim();

                        if (subj.isNotEmpty) {
                          bool classMatched = roomClassNames.isEmpty;
                          if (!classMatched) {
                            final clsClean = cls.toLowerCase().replaceAll(' ', '');
                            final cIdClean = cId.toLowerCase().replaceAll(' ', '');
                            classMatched = roomClassNames.contains(cls) || 
                                           roomClassNames.contains(cId) ||
                                           roomClassNames.contains(clsClean) ||
                                           roomClassNames.contains(cIdClean) ||
                                           roomClassNames.any((c) {
                                             final cClean = c.toLowerCase().replaceAll(' ', '');
                                             return cClean.isNotEmpty && (clsClean.contains(cClean) || cClean.contains(clsClean));
                                           });
                          }

                          if (classMatched) {
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
                      dutyDate: dutyDate,
                      sessionLabel: sessionLabel,
                      roomName: roomName,
                      roomId: roomId,
                      roomCapacity: roomCapacity,
                      subjectText: subjectText,
                      status: status,
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
    required DateTime? dutyDate,
    required String sessionLabel,
    required String roomName,
    required String roomId,
    required int roomCapacity,
    required String subjectText,
    required String status,
    required String? activeAllocId,
    required int dayIndex,
    required int sessionIndex,
  }) {
    // 1. Clean Room Name (remove "Ruangan:" or "Ruangan :")
    String cleanRoomName = roomName.trim();
    if (cleanRoomName.toLowerCase().startsWith('ruangan:')) {
      cleanRoomName = cleanRoomName.substring(8).trim();
    } else if (cleanRoomName.toLowerCase().startsWith('ruangan :')) {
      cleanRoomName = cleanRoomName.substring(9).trim();
    }

    // 2. Compute dynamic time-based status
    DateTime? sessionStartDt;
    DateTime? sessionEndDt;
    final timeMatch = RegExp(r'(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})').firstMatch(sessionLabel);
    if (timeMatch != null && dutyDate != null) {
      final sParts = timeMatch.group(1)!.split(':');
      final eParts = timeMatch.group(2)!.split(':');
      if (sParts.length >= 2 && eParts.length >= 2) {
        sessionStartDt = DateTime(dutyDate.year, dutyDate.month, dutyDate.day, int.parse(sParts[0]), int.parse(sParts[1]));
        sessionEndDt = DateTime(dutyDate.year, dutyDate.month, dutyDate.day, int.parse(eParts[0]), int.parse(eParts[1]));
      }
    }

    final now = DateTime.now();
    String displayStatus = status;

    if (sessionEndDt != null && now.isAfter(sessionEndDt)) {
      displayStatus = 'Ujian Selesai';
    } else if (status == 'Selesai') {
      displayStatus = 'Ujian Selesai';
    } else if (sessionStartDt != null && sessionEndDt != null && (now.isAfter(sessionStartDt) || now.isAtSameMomentAs(sessionStartDt)) && now.isBefore(sessionEndDt)) {
      displayStatus = 'Sedang Berlangsung';
    } else if (sessionStartDt != null && now.isBefore(sessionStartDt)) {
      displayStatus = 'Belum Dimulai';
    }

    // 3. Status Badge Styling
    Color badgeBg;
    Color badgeText;
    Color badgeBorder;
    IconData badgeIcon;

    switch (displayStatus) {
      case 'Sedang Berlangsung':
        badgeBg = const Color(0xFFFFFBEB);
        badgeText = const Color(0xFFD97706);
        badgeBorder = const Color(0xFFFDE68A);
        badgeIcon = Icons.sensors_rounded;
        break;
      case 'Ujian Selesai':
      case 'Selesai':
        badgeBg = const Color(0xFFF1F5F9);
        badgeText = const Color(0xFF64748B);
        badgeBorder = const Color(0xFFCBD5E1);
        badgeIcon = Icons.check_circle_rounded;
        break;
      default:
        badgeBg = const Color(0xFFEFF6FF);
        badgeText = const Color(0xFF2563EB);
        badgeBorder = const Color(0xFFBFDBFE);
        badgeIcon = Icons.schedule_rounded;
    }

    final bool isSessionEnded = _isSessionExpired(dateLabel, sessionLabel);

    void navigateToProctorRoom() {
      if (isSessionEnded) {
        _showProctorExpiredDialog(context, cleanRoomName, sessionLabel);
        return;
      }
      context.go(
        '/teacher/event/${widget.eventId}/proctor-room/$roomId?dayIndex=$dayIndex&sessionIndex=$sessionIndex&docId=$docId',
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: navigateToProctorRoom,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER BAR: Date, Capacity & Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Text(
                          dateLabel,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        if (roomCapacity > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$roomCapacity Bangku',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF4F46E5)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSessionEnded ? const Color(0xFFFEF2F2) : badgeBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSessionEnded ? const Color(0xFFFCA5A5) : badgeBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isSessionEnded ? Icons.history_toggle_off_rounded : badgeIcon, size: 13, color: isSessionEnded ? const Color(0xFFDC2626) : badgeText),
                          const SizedBox(width: 5),
                          Text(
                            isSessionEnded ? 'Sesi Selesai' : displayStatus,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSessionEnded ? const Color(0xFFDC2626) : badgeText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // CARD BODY
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ROOM NAME & SESSION TIME
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isSessionEnded
                                  ? [const Color(0xFF64748B), const Color(0xFF94A3B8)]
                                  : [const Color(0xFF4F46E5), const Color(0xFF6366F1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (isSessionEnded ? const Color(0xFF64748B) : const Color(0xFF4F46E5)).withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(isSessionEnded ? Icons.history_toggle_off_rounded : Icons.meeting_room_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cleanRoomName,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_filled_rounded, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    sessionLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // SUBJECT BANNER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.auto_stories_rounded, color: Color(0xFF166534), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MATA PELAJARAN UJIAN',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF15803D),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subjectText,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF14532D),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // BOTTOM ACTION BAR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (displayStatus == 'Sedang Berlangsung' && !docId.startsWith('grid_') && !isSessionEnded)
                          OutlinedButton.icon(
                            onPressed: () => _updateProctorStatus(docId, 'Selesai'),
                            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                            label: const Text('Selesaikan Sesi'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF059669),
                              side: const BorderSide(color: Color(0xFFA7F3D0)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          )
                        else
                          const SizedBox(),

                        ElevatedButton(
                          onPressed: navigateToProctorRoom,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSessionEnded ? const Color(0xFF64748B) : const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: isSessionEnded ? 0 : 2,
                            shadowColor: isSessionEnded ? Colors.transparent : const Color(0xFF4F46E5).withValues(alpha: 0.4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isSessionEnded ? 'Sesi Selesai (Kadaluarsa)' : 'Masuk ke Ruangan',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 8),
                              Icon(isSessionEnded ? Icons.lock_clock_rounded : Icons.arrow_forward_rounded, size: 16),
                            ],
                          ),
                        ),
                      ],
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



  bool _isSessionExpired(String? dateStr, String? timeStrOrRange) {
    if (timeStrOrRange == null || timeStrOrRange.trim().isEmpty) return false;

    try {
      final now = DateTime.now();

      String endTimeStr = timeStrOrRange.trim();
      if (endTimeStr.contains('-')) {
        final parts = endTimeStr.split('-');
        endTimeStr = parts.last.trim();
        if (endTimeStr.endsWith(')')) {
          endTimeStr = endTimeStr.substring(0, endTimeStr.length - 1).trim();
        }
      }

      final timeParts = endTimeStr.split(':');
      if (timeParts.length < 2) return false;

      final hour = int.tryParse(RegExp(r'\d+').stringMatch(timeParts[0]) ?? '');
      final minute = int.tryParse(RegExp(r'\d+').stringMatch(timeParts[1]) ?? '');

      if (hour == null || minute == null) return false;

      DateTime targetDate = DateTime(now.year, now.month, now.day);
      if (dateStr != null && dateStr.trim().isNotEmpty) {
        final cleanDate = dateStr.trim();
        final parsedDirect = DateTime.tryParse(cleanDate);
        if (parsedDirect != null) {
          targetDate = DateTime(parsedDirect.year, parsedDirect.month, parsedDirect.day);
        } else {
          final yearMatch = RegExp(r'20\d\d').firstMatch(cleanDate);
          final dayMatch = RegExp(r'\b\d{1,2}\b').firstMatch(cleanDate);
          if (yearMatch != null && dayMatch != null) {
            final year = int.parse(yearMatch.group(0)!);
            final day = int.parse(dayMatch.group(0)!);
            int month = now.month;
            final lower = cleanDate.toLowerCase();
            if (lower.contains('jan')) {
              month = 1;
            } else if (lower.contains('feb')) {
              month = 2;
            } else if (lower.contains('mar')) {
              month = 3;
            } else if (lower.contains('apr')) {
              month = 4;
            } else if (lower.contains('mei') || lower.contains('may')) {
              month = 5;
            } else if (lower.contains('jun')) {
              month = 6;
            } else if (lower.contains('jul')) {
              month = 7;
            } else if (lower.contains('agt') || lower.contains('agu') || lower.contains('aug')) {
              month = 8;
            } else if (lower.contains('sep')) {
              month = 9;
            } else if (lower.contains('okt') || lower.contains('oct')) {
              month = 10;
            } else if (lower.contains('nov')) {
              month = 11;
            } else if (lower.contains('des') || lower.contains('dec')) {
              month = 12;
            }

            targetDate = DateTime(year, month, day);
          }
        }
      }

      final sessionEnd = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute, 59);
      return now.isAfter(sessionEnd);
    } catch (e) {
      debugPrint('⚠️ Error checking session expired: $e');
      return false;
    }
  }

  void _showProctorExpiredDialog(BuildContext context, String roomName, String sessionLabel) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_rounded, color: Color(0xFFDC2626), size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Sesi Pengawasan Berakhir',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Waktu pelaksanaan pengawasan untuk $roomName ($sessionLabel) telah melewati batas jam berakhirnya sesi.',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Pengawas maupun siswa tidak dapat lagi masuk ke dalam ruangan pengawas atau melakukan presensi pada sesi ini.',
                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Saya Mengerti', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
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

        // 1. Dari subkoleksi timetable
        if (_timetableSubcollection.isNotEmpty) {
          timetableList.addAll(_timetableSubcollection);
        }

        // 2. Dari field draftState -> timetable
        final draftState = evData['draftState'] as Map<String, dynamic>?;
        if (draftState != null && draftState['timetable'] is List) {
          for (var item in (draftState['timetable'] as List)) {
            if (item is Map) timetableList.add(Map<String, dynamic>.from(item));
          }
        }

        // 3. Dari top-level field timetable
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

        // Ensure selected subject is valid
        final validSubjectIds = subjectList.map((s) => s['id'] as String).toList();
        if (_selectedCorrSubjectId == null || !validSubjectIds.contains(_selectedCorrSubjectId)) {
          _selectedCorrSubjectId = validSubjectIds.first;
        }

        final selectedSubjectMap = subjectList.firstWhere((s) => s['id'] == _selectedCorrSubjectId);
        final selectedSubjectName = selectedSubjectMap['name'] as String;
        final selectedSubjectClassesSet = selectedSubjectMap['classes'] as Set<String>;
        final selectedSubjectClassesList = selectedSubjectClassesSet.toList()..sort();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. BAGIAN ATAS: LIST MAPEL RINGKAS (COMPACT HEIGHT ~90px)
              Text(
                'Pilih Mata Pelajaran Koreksi:',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: subjectList.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, idx) {
                    final subj = subjectList[idx];
                    final sId = subj['id'] as String;
                    final sName = subj['name'] as String;
                    final classesCount = (subj['classes'] as Set<String>).length;
                    final isSelected = sId == _selectedCorrSubjectId;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCorrSubjectId = sId;
                          _selectedCorrClass = 'ALL';
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFECFDF5) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF10B981) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isSelected ? Icons.fact_check_rounded : Icons.menu_book_rounded,
                                color: isSelected ? Colors.white : const Color(0xFF64748B),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  sName,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isSelected ? const Color(0xFF065F46) : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  classesCount > 0 ? '$classesCount Kelas Terdaftar' : 'Semua Kelas',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected ? const Color(0xFF047857) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 2. BAGIAN BAWAH: WORKSPACE KOREKSI FULL-HEIGHT
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('schools')
                        .doc(_schoolId)
                        .collection('events')
                        .doc(widget.eventId)
                        .collection('subjects')
                        .doc(_selectedCorrSubjectId!)
                        .collection('questions')
                        .snapshots(),
                    builder: (context, qSnap) {
                      if (qSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
                      }

                      final questionDocs = qSnap.data?.docs ?? [];

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('schools')
                            .doc(_schoolId)
                            .collection('events')
                            .doc(widget.eventId)
                            .collection('submissions')
                            .snapshots(),
                        builder: (context, subSnap) {
                          if (subSnap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
                          }

                          final allSubDocs = subSnap.data?.docs ?? [];
                          final subDocs = allSubDocs.where((d) {
                            final data = d.data() as Map<String, dynamic>;
                            final sId = (data['subjectId'] ?? '').toString();
                            final sName = (data['subjectName'] ?? '').toString();
                            return sId == _selectedCorrSubjectId! || sName.toLowerCase().trim() == selectedSubjectName.toLowerCase().trim();
                          }).toList();

                          // Extract all available classes for this subject from submissions or assignedClasses
                          final Map<String, int> classCounts = {};
                          for (var d in subDocs) {
                            final data = d.data() as Map<String, dynamic>;
                            final cls = (data['className'] ?? data['classId'] ?? data['studentClass'] ?? 'Tanpa Kelas').toString().trim();
                            classCounts[cls] = (classCounts[cls] ?? 0) + 1;
                          }

                          final availableClasses = (selectedSubjectClassesList.isNotEmpty
                                  ? selectedSubjectClassesList
                                  : classCounts.keys.toList())
                              ..sort();

                          // Filter student submission docs by class
                          final filteredSubDocs = subDocs.where((d) {
                            if (_selectedCorrClass == 'ALL') return true;
                            final data = d.data() as Map<String, dynamic>;
                            final cls = (data['className'] ?? data['classId'] ?? data['studentClass'] ?? 'Tanpa Kelas').toString().trim();
                            return cls == _selectedCorrClass || cls.toLowerCase().contains(_selectedCorrClass.toLowerCase());
                          }).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Workspace Sub-header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.fact_check_rounded, color: Color(0xFF10B981), size: 22),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Koreksi Lembar Jawaban: $selectedSubjectName',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF0F172A)),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFFA7F3D0)),
                                      ),
                                      child: Text(
                                        'Total: ${subDocs.length} siswa • Menampilkan ${filteredSubDocs.length} siswa',
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF059669)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // LIST CHOICECHIP KELAS
                              if (availableClasses.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Pilih Kelas:',
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              ChoiceChip(
                                                label: Text(
                                                  'Semua Kelas (${subDocs.length})',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: _selectedCorrClass == 'ALL' ? Colors.white : const Color(0xFF475569),
                                                  ),
                                                ),
                                                selected: _selectedCorrClass == 'ALL',
                                                selectedColor: const Color(0xFF2563EB),
                                                backgroundColor: const Color(0xFFF1F5F9),
                                                onSelected: (_) => setState(() => _selectedCorrClass = 'ALL'),
                                              ),
                                              ...availableClasses.map((cls) {
                                                final count = classCounts[cls] ?? 0;
                                                final isSel = _selectedCorrClass == cls;
                                                return Padding(
                                                  padding: const EdgeInsets.only(left: 8),
                                                  child: ChoiceChip(
                                                    label: Text(
                                                      '$cls ($count)',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: isSel ? Colors.white : const Color(0xFF475569),
                                                      ),
                                                    ),
                                                    selected: isSel,
                                                    selectedColor: const Color(0xFF2563EB),
                                                    backgroundColor: const Color(0xFFF1F5F9),
                                                    onSelected: (_) => setState(() => _selectedCorrClass = cls),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const Divider(height: 1),

                              // STEP 3: LIST NAMA MURID-MURID UNTUK DIKOREKSI
                              Expanded(
                                child: filteredSubDocs.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.assignment_outlined, size: 48, color: Color(0xFFCBD5E1)),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Belum ada lembar jawaban siswa yang dikumpulkan pada kategori ini.',
                                              style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.all(16),
                                        itemCount: filteredSubDocs.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                                        itemBuilder: (c, idx) {
                                          final subDoc = filteredSubDocs[idx];
                                          final subData = subDoc.data() as Map<String, dynamic>;
                                          final studentName = subData['studentName'] ?? 'Siswa';
                                          final nis = subData['nis'] ?? '-';
                                          final studentClass = (subData['className'] ?? subData['classId'] ?? subData['studentClass'] ?? '').toString().trim();
                                          final isCompleted = subData['isCompleted'] == true;
                                          final isGraded = subData['isGraded'] == true;

                                          // Auto PG Calculation
                                          final answers = Map<String, dynamic>.from(subData['answers'] ?? {});
                                          double autoPgScore = 0;
                                          double totalPgMax = 0;
                                          double totalEssayMax = 0;
                                          int correctPgCount = 0;
                                          int totalPgCount = 0;

                                          for (var qDoc in questionDocs) {
                                            final qData = qDoc.data() as Map<String, dynamic>;
                                            final qId = qDoc.id;
                                            final type = qData['type'] ??
                                                ((qData['options'] != null && (qData['options'] as Map).isNotEmpty) ? 'pilihan_ganda' : 'essay');
                                            final score = (qData['score'] as num?)?.toDouble() ?? (type == 'essay' ? 10.0 : 5.0);

                                            if (type == 'pilihan_ganda') {
                                              totalPgCount++;
                                              totalPgMax += score;
                                              final studentAns = answers[qId]?.toString().trim().toUpperCase();
                                              final correctAns = (qData['correctOption'] ?? '').toString().trim().toUpperCase();
                                              if (studentAns != null && studentAns == correctAns) {
                                                correctPgCount++;
                                                autoPgScore += score;
                                              }
                                            } else {
                                              totalEssayMax += score;
                                            }
                                          }

                                          final existingEssayScores = Map<String, dynamic>.from(subData['essayScores'] ?? {});
                                          double essayScore = 0;
                                          existingEssayScores.forEach((k, v) {
                                            if (v is num) essayScore += v.toDouble();
                                          });

                                          final totalEarnedRaw = autoPgScore + essayScore;
                                          final totalMaxRaw = totalPgMax + totalEssayMax;
                                          final calculatedScore = totalMaxRaw > 0 ? ((totalEarnedRaw / totalMaxRaw) * 100).round() : 0;
                                          final finalScore = (subData['score'] as num?)?.toInt() ?? calculatedScore;

                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: const Color(0xFFE2E8F0)),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Text(
                                                            studentName,
                                                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF0F172A)),
                                                          ),
                                                          if (studentClass.isNotEmpty) ...[
                                                            const SizedBox(width: 8),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFEFF6FF),
                                                                borderRadius: BorderRadius.circular(6),
                                                                border: Border.all(color: const Color(0xFFBFDBFE)),
                                                              ),
                                                              child: Text(
                                                                studentClass,
                                                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF2563EB)),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'NIS: $nis • PG: $correctPgCount/$totalPgCount Benar (${autoPgScore.toInt()} pt)',
                                                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                if (isCompleted)
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: isGraded ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(color: isGraded ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                                                        ),
                                                        child: Text(
                                                          isGraded ? 'Nilai: $finalScore / 100' : 'Perlu Koreksi Essay',
                                                          style: GoogleFonts.inter(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                            color: isGraded ? const Color(0xFF059669) : const Color(0xFFD97706),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      ElevatedButton.icon(
                                                        onPressed: () => _gradeStudentDialog(
                                                          subDocId: subDoc.id,
                                                          studentName: studentName,
                                                          subData: subData,
                                                          questionDocs: questionDocs,
                                                          autoPgScore: autoPgScore,
                                                          totalPgMax: totalPgMax,
                                                          correctPgCount: correctPgCount,
                                                          totalPgCount: totalPgCount,
                                                        ),
                                                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                                                        label: Text(
                                                          isGraded ? 'Edit Nilai' : 'Koreksi',
                                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: const Color(0xFF10B981),
                                                          foregroundColor: Colors.white,
                                                          elevation: 0,
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                else
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFEF2F2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      'Sedang Mengerjakan',
                                                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626), fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }





  void _gradeStudentDialog({
    required String subDocId,
    required String studentName,
    required Map<String, dynamic> subData,
    required List<DocumentSnapshot> questionDocs,
    required double autoPgScore,
    required double totalPgMax,
    required int correctPgCount,
    required int totalPgCount,
  }) {
    final essayDocs = questionDocs.where((qDoc) {
      final qData = qDoc.data() as Map<String, dynamic>;
      final type = qData['type'] ??
          ((qData['options'] != null && (qData['options'] as Map).isNotEmpty) ? 'pilihan_ganda' : 'essay');
      return type == 'essay';
    }).toList();

    final essayAnswers = Map<String, dynamic>.from(subData['essayAnswers'] ?? subData['answers'] ?? {});
    final existingEssayScores = Map<String, dynamic>.from(subData['essayScores'] ?? {});

    final Map<String, TextEditingController> scoreControllers = {};
    for (var eDoc in essayDocs) {
      final qId = eDoc.id;
      final maxScore = ((eDoc.data() as Map<String, dynamic>)['score'] as num?)?.toDouble() ?? 10.0;
      final savedScore = (existingEssayScores[qId] as num?)?.toDouble();
      final initVal = savedScore ?? maxScore;
      final str = initVal % 1 == 0 ? initVal.toInt().toString() : initVal.toString();
      scoreControllers[qId] = TextEditingController(text: str);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            double currentEssayTotal = 0;
            double essayMaxTotal = 0;
            bool hasAnyExceeded = false;

            for (var eDoc in essayDocs) {
              final qId = eDoc.id;
              final maxScore = ((eDoc.data() as Map<String, dynamic>)['score'] as num?)?.toDouble() ?? 10.0;
              essayMaxTotal += maxScore;

              final ctrl = scoreControllers[qId]!;
              final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
              if (val > maxScore || val < 0) {
                hasAnyExceeded = true;
              }
              currentEssayTotal += val;
            }

            final grandEarned = autoPgScore + currentEssayTotal;
            final grandMax = totalPgMax + essayMaxTotal;
            final finalScale100 = grandMax > 0 ? ((grandEarned / grandMax) * 100).round().clamp(0, 100) : 0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Icon(Icons.fact_check_rounded, color: Color(0xFF059669), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Form Koreksi Ujian',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
                        ),
                        Text(
                          'Murid: $studentName',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Banner Ringkasan Pilihan Ganda
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.task_alt_rounded, color: Color(0xFF2563EB), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pilihan Ganda (Koreksi Otomatis)',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E40AF)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$correctPgCount dari $totalPgCount Soal Benar',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF3B82F6)),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${autoPgScore.toInt()} / ${totalPgMax.toInt()} pt',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1E40AF)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Text(
                            'Koreksi Soal Essay',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF0F172A)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${essayDocs.length} Soal',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (essayDocs.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 10),
                              Text(
                                'Tidak ada soal essay pada ujian ini.',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        )
                      else
                        ...essayDocs.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final eDoc = entry.value;
                          final qData = eDoc.data() as Map<String, dynamic>;
                          final qId = eDoc.id;
                          final qText = qData['text'] ?? '';
                          final maxScore = (qData['score'] as num?)?.toDouble() ?? 10.0;
                          final rawAns = essayAnswers[qId]?.toString().trim() ?? '';
                          final isAnsEmpty = rawAns.isEmpty || rawAns == '(Murid tidak mengisi)';
                          final studentAns = isAnsEmpty ? '(Murid tidak mengisi jawaban)' : rawAns;
                          final ctrl = scoreControllers[qId]!;

                          final typedVal = double.tryParse(ctrl.text.trim());
                          final bool isExceeded = typedVal != null && (typedVal > maxScore || typedVal < 0);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isExceeded ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                                width: isExceeded ? 1.5 : 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFDF2F8),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFFBCFE8)),
                                      ),
                                      child: Text(
                                        'Essay #${idx + 1}',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFDB2777)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        qText,
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF1E293B)),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isAnsEmpty ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isAnsEmpty ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Jawaban Murid:',
                                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isAnsEmpty ? const Color(0xFFB45309) : const Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        studentAns,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: isAnsEmpty ? const Color(0xFF92400E) : const Color(0xFF334155),
                                          fontStyle: isAnsEmpty ? FontStyle.italic : FontStyle.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      'Nilai Diberikan:',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF475569)),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isExceeded ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Max ${maxScore % 1 == 0 ? maxScore.toInt() : maxScore} pt',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    SizedBox(
                                      width: 120,
                                      child: TextField(
                                        controller: ctrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                                        ),
                                        onChanged: (_) => setDialogState(() {}),
                                        decoration: InputDecoration(
                                          suffixText: 'pt',
                                          suffixStyle: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          filled: true,
                                          fillColor: isExceeded ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                              color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1),
                                              width: isExceeded ? 2.0 : 1.0,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                              color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                                              width: 2.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isExceeded) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Nilai melebihi batas maksimal (Max ${maxScore % 1 == 0 ? maxScore.toInt() : maxScore} pt)',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626)),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 12),

                      // Live Final Score Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: hasAnyExceeded ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: hasAnyExceeded ? const Color(0xFFFCA5A5) : const Color(0xFFA7F3D0), width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasAnyExceeded ? '⚠️ Peringatan Nilai Melebihi Batas' : 'Kalkulasi Total Nilai Akhir',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: hasAnyExceeded ? const Color(0xFF991B1B) : const Color(0xFF065F46)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hasAnyExceeded
                                      ? 'Perbaiki nilai essay bernilai merah sebelum menyimpan.'
                                      : 'Raw: ${grandEarned.toStringAsFixed(grandEarned % 1 == 0 ? 0 : 1)} / ${grandMax.toStringAsFixed(grandMax % 1 == 0 ? 0 : 1)} Poin (Skala 100)',
                                  style: GoogleFonts.inter(fontSize: 12, color: hasAnyExceeded ? const Color(0xFFDC2626) : const Color(0xFF047857), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: hasAnyExceeded ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: (hasAnyExceeded ? const Color(0xFFDC2626) : const Color(0xFF059669)).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                '$finalScale100 / 100',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                  label: Text('Simpan Nilai', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasAnyExceeded ? const Color(0xFF94A3B8) : const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    if (hasAnyExceeded) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ Gagal menyimpan! Terdapat input nilai essay yang melebihi batas maksimal.'),
                          backgroundColor: Color(0xFFDC2626),
                        ),
                      );
                      return;
                    }

                    final Map<String, double> essayScoresMap = {};
                    for (var eDoc in essayDocs) {
                      final qId = eDoc.id;
                      final rawVal = double.tryParse(scoreControllers[qId]?.text.trim() ?? '') ?? 0.0;
                      essayScoresMap[qId] = rawVal;
                    }

                    try {
                      await FirebaseFirestore.instance
                          .collection('schools')
                          .doc(_schoolId)
                          .collection('events')
                          .doc(widget.eventId)
                          .collection('submissions')
                          .doc(subDocId)
                          .set({
                        'score': finalScale100,
                        'pgScore': autoPgScore,
                        'essayScore': currentEssayTotal,
                        'essayScores': essayScoresMap,
                        'isGraded': true,
                        'gradedAt': FieldValue.serverTimestamp(),
                        'gradedByName': _teacher?.displayName ?? 'Guru',
                      }, SetOptions(merge: true));

                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nilai berhasil disimpan!'), backgroundColor: Color(0xFF10B981)),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal menyimpan nilai: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
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
                    const SizedBox(width: 8),
                    Builder(builder: (context) {
                      final scoreNum = (widget.qData['score'] as num?)?.toDouble() ?? (isEssay ? 10.0 : 5.0);
                      final scoreStr = scoreNum % 1 == 0 ? scoreNum.toInt().toString() : scoreNum.toString();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFD97706)),
                            const SizedBox(width: 4),
                            Text(
                              isEssay ? 'Max $scoreStr pt' : '$scoreStr pt',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
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
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),
                Text(
                  'Riwayat Soal:',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_circle_outline_rounded, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          'Dibuat oleh ${widget.qData['createdByName'] ?? 'Guru'} ${widget.qData['createdAt'] != null ? 'pada ${_formatTimestamp(widget.qData['createdAt'])}' : ''}',
                          style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    if (widget.qData['updatedByName'] != null &&
                        widget.qData['updatedAt'] != null &&
                        (widget.qData['updatedBy'] != widget.qData['createdBy'] ||
                         widget.qData['updatedByName'] != widget.qData['createdByName'])) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.edit_rounded, size: 12, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 6),
                          Text(
                            'Diedit oleh ${widget.qData['updatedByName']} pada ${_formatTimestamp(widget.qData['updatedAt'])}',
                            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic val) {
    if (val == null) return '';
    DateTime? dt;
    if (val is Timestamp) {
      dt = val.toDate();
    } else if (val is String) {
      dt = DateTime.tryParse(val);
    } else if (val is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(val);
    }
    if (dt == null) return '';
    try {
      return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt);
    } catch (_) {
      return DateFormat('dd MMM yyyy, HH:mm').format(dt);
    }
  }
}
