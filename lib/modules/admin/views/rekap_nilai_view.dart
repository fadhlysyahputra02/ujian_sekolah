import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RekapNilaiView extends StatefulWidget {
  final String schoolId;
  final bool isTeacher;
  final String? currentTeacherId;
  final String? currentTeacherName;
  final List<String> teacherSubjects;

  const RekapNilaiView({
    super.key,
    required this.schoolId,
    this.isTeacher = false,
    this.currentTeacherId,
    this.currentTeacherName,
    this.teacherSubjects = const [],
  });

  @override
  State<RekapNilaiView> createState() => _RekapNilaiViewState();
}

class _RekapNilaiViewState extends State<RekapNilaiView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _selectedSubject = 'ALL';
  String _selectedAngkatan = 'ALL';
  String _selectedClass = 'ALL';
  String _selectedStatus = 'ALL'; // ALL, UNFILLED, FILLED, GRADED
  String _searchQuery = '';

  // Sent grades dispatched to this teacher (if isTeacher)
  Set<String> _sentSubjectIds = {};
  Set<String> _sentSubjectNames = {};

  bool _isSendingGrade = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & Header Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rekap Nilai Murid',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isTeacher
                        ? 'Daftar nilai murid sesuai mata pelajaran kewenangan dan kiriman Admin Sekolah.'
                        : 'Rekapitulasi seluruh nilai murid terkelompok berdasarkan Angkatan & Kelas.',
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
              if (!widget.isTeacher)
                ElevatedButton.icon(
                  onPressed: _showDispatchGradeModal,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    'Kirim Nilai ke Guru',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Stream for Sent Grades (to populate dispatched subjects for teacher)
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('schools')
                .doc(widget.schoolId)
                .collection('sentGrades')
                .snapshots(),
            builder: (context, sentSnap) {
              if (sentSnap.hasData && widget.isTeacher && widget.currentTeacherId != null) {
                _sentSubjectIds.clear();
                _sentSubjectNames.clear();
                for (var doc in sentSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final tId = (data['teacherId'] ?? '').toString();
                  if (tId == widget.currentTeacherId || tId.contains(widget.currentTeacherId!)) {
                    if (data['subjectId'] != null) _sentSubjectIds.add(data['subjectId'].toString());
                    if (data['subjectName'] != null) _sentSubjectNames.add(data['subjectName'].toString().toLowerCase().trim());
                  }
                }
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('schools')
                    .doc(widget.schoolId)
                    .collection('students')
                    .where('archived', isEqualTo: false)
                    .snapshots(),
                builder: (context, studentSnap) {
                  if (studentSnap.connectionState == ConnectionState.waiting) {
                    return const Expanded(
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
                    );
                  }

                  final studentDocs = studentSnap.data?.docs ?? [];

                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('schools')
                        .doc(widget.schoolId)
                        .collection('events')
                        .snapshots(),
                    builder: (context, eventSnap) {
                      final eventDocs = eventSnap.data?.docs ?? [];

                      return FutureBuilder<List<Map<String, dynamic>>>(
                        future: _fetchAllSubmissions(eventDocs),
                        builder: (context, subSnap) {
                          if (subSnap.connectionState == ConnectionState.waiting) {
                            return const Expanded(
                              child: Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
                            );
                          }

                          final submissions = subSnap.data ?? [];

                          return _buildMainContent(studentDocs, submissions, sentSnap.data?.docs ?? []);
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllSubmissions(List<QueryDocumentSnapshot> eventDocs) async {
    final List<Map<String, dynamic>> allSubmissions = [];
    for (var evDoc in eventDocs) {
      try {
        final subSnap = await evDoc.reference.collection('submissions').get();
        for (var sDoc in subSnap.docs) {
          final data = sDoc.data();
          data['eventId'] = evDoc.id;
          data['subDocId'] = sDoc.id;
          allSubmissions.add(data);
        }
      } catch (_) {}
    }
    return allSubmissions;
  }

  Widget _buildMainContent(
    List<QueryDocumentSnapshot> studentDocs,
    List<Map<String, dynamic>> submissions,
    List<QueryDocumentSnapshot> sentGradeDocs,
  ) {
    // Extract available subjects, angkatan, classes
    final Set<String> allSubjects = {};
    final Set<String> allAngkatan = {};
    final Set<String> allClasses = {};

    for (var sDoc in studentDocs) {
      final sData = sDoc.data() as Map<String, dynamic>;
      final angk = (sData['angkatan'] ?? '').toString().trim();
      final cls = (sData['className'] ?? sData['kelas'] ?? sData['classId'] ?? '').toString().trim();
      if (angk.isNotEmpty) allAngkatan.add(angk);
      if (cls.isNotEmpty) allClasses.add(cls);
    }

    for (var sub in submissions) {
      final sName = (sub['subjectName'] ?? sub['subjectId'] ?? '').toString().trim();
      if (sName.isNotEmpty) allSubjects.add(sName);
    }

    // If teacher, filter subject choices to authorized or dispatched subjects only!
    List<String> subjectDropdownOptions = allSubjects.toList()..sort();
    if (widget.isTeacher) {
      subjectDropdownOptions = subjectDropdownOptions.where((sName) {
        final cleanSName = sName.toLowerCase().trim();
        final isAssigned = widget.teacherSubjects.any((ts) => ts.toLowerCase().trim() == cleanSName);
        final isDispatched = _sentSubjectNames.contains(cleanSName);
        return isAssigned || isDispatched;
      }).toList();
    }

    // Build Student Score Map
    // Key: studentId or NIS -> Map<SubjectName, SubmissionData>
    final Map<String, Map<String, dynamic>> studentSubmissionMap = {};
    for (var sub in submissions) {
      final studentId = (sub['studentId'] ?? sub['nis'] ?? sub['studentName'] ?? '').toString().trim();
      final sName = (sub['subjectName'] ?? sub['subjectId'] ?? '').toString().trim();
      if (studentId.isNotEmpty && sName.isNotEmpty) {
        studentSubmissionMap['${studentId}_$sName'] = sub;
      }
    }

    // Group Students by Angkatan & Kelas
    final Map<String, List<QueryDocumentSnapshot>> groupedStudents = {};
    for (var sDoc in studentDocs) {
      final sData = sDoc.data() as Map<String, dynamic>;
      final name = (sData['displayName'] ?? sData['name'] ?? '').toString();
      final nis = (sData['nis'] ?? '').toString();
      final angk = (sData['angkatan'] ?? 'Tanpa Angkatan').toString().trim();
      final cls = (sData['className'] ?? sData['kelas'] ?? sData['classId'] ?? 'Tanpa Kelas').toString().trim();

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!name.toLowerCase().contains(q) && !nis.toLowerCase().contains(q)) {
          continue;
        }
      }

      if (_selectedAngkatan != 'ALL' && angk != _selectedAngkatan) continue;
      if (_selectedClass != 'ALL' && cls != _selectedClass) continue;

      final groupKey = 'Angkatan $angk • Kelas $cls';
      groupedStudents.putIfAbsent(groupKey, () => []).add(sDoc);
    }

    return Expanded(
      child: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Search Input
                SizedBox(
                  width: 220,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Cari murid / NIS...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                // Subject Dropdown
                DropdownButton<String>(
                  value: subjectDropdownOptions.contains(_selectedSubject) ? _selectedSubject : 'ALL',
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('Semua Mata Pelajaran')),
                    ...subjectDropdownOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                  ],
                  onChanged: (val) => setState(() => _selectedSubject = val ?? 'ALL'),
                ),
                // Angkatan Dropdown
                DropdownButton<String>(
                  value: _selectedAngkatan,
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('Semua Angkatan')),
                    ...(allAngkatan.toList()..sort()).map((a) => DropdownMenuItem(value: a, child: Text('Angkatan $a'))),
                  ],
                  onChanged: (val) => setState(() => _selectedAngkatan = val ?? 'ALL'),
                ),
                // Class Dropdown
                DropdownButton<String>(
                  value: _selectedClass,
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('Semua Kelas')),
                    ...(allClasses.toList()..sort()).map((c) => DropdownMenuItem(value: c, child: Text('Kelas $c'))),
                  ],
                  onChanged: (val) => setState(() => _selectedClass = val ?? 'ALL'),
                ),
                // Status Dropdown
                DropdownButton<String>(
                  value: _selectedStatus,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Semua Status Nilai')),
                    DropdownMenuItem(value: 'UNFILLED', child: Text('Belum Diisi')),
                    DropdownMenuItem(value: 'FILLED', child: Text('Sudah Diisi')),
                    DropdownMenuItem(value: 'GRADED', child: Text('Sudah Dikoreksi')),
                  ],
                  onChanged: (val) => setState(() => _selectedStatus = val ?? 'ALL'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Grouped List View
          Expanded(
            child: groupedStudents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.assignment_late_outlined, size: 48, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 12),
                        Text(
                          'Tidak ada data nilai murid yang sesuai filter.',
                          style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: groupedStudents.entries.map((entry) {
                      final groupTitle = entry.key;
                      final students = entry.value;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Group Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_shared_rounded, color: Color(0xFF4F46E5), size: 20),
                                  const SizedBox(width: 10),
                                  Text(
                                    groupTitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${students.length} Murid',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            // Table Content
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('NIS')),
                                  DataColumn(label: Text('Nama Murid')),
                                  DataColumn(label: Text('Mata Pelajaran')),
                                  DataColumn(label: Text('Nilai PG')),
                                  DataColumn(label: Text('Nilai Essay')),
                                  DataColumn(label: Text('Total Nilai')),
                                  DataColumn(label: Text('Status Nilai')),
                                  DataColumn(label: Text('Keterangan')),
                                ],
                                rows: students.expand((sDoc) {
                                  final sData = sDoc.data() as Map<String, dynamic>;
                                  final sId = sDoc.id;
                                  final sNis = (sData['nis'] ?? '-').toString();
                                  final sName = (sData['displayName'] ?? sData['name'] ?? '-').toString();

                                  // List of subjects to show
                                  List<String> targetSubjects = subjectDropdownOptions;
                                  if (_selectedSubject != 'ALL') {
                                    targetSubjects = [_selectedSubject];
                                  }

                                  return targetSubjects.map((subj) {
                                    final subData = studentSubmissionMap['${sId}_$subj'] ??
                                        studentSubmissionMap['${sNis}_$subj'] ??
                                        studentSubmissionMap['${sName}_$subj'];

                                    final isSubmitted = subData != null;
                                    final isGraded = subData?['isGraded'] == true;
                                    final pgScore = subData?['pgScore'] ?? 0;
                                    final essayScore = subData?['essayScore'] ?? 0;
                                    final score = subData?['score'] ?? (isSubmitted ? (pgScore + essayScore) : 0);

                                    String statusKey = 'UNFILLED';
                                    if (isGraded) {
                                      statusKey = 'GRADED';
                                    } else if (isSubmitted) {
                                      statusKey = 'FILLED';
                                    }

                                    if (_selectedStatus != 'ALL' && statusKey != _selectedStatus) {
                                      return null;
                                    }

                                    final isDispatchedToTeacher = _sentSubjectNames.contains(subj.toLowerCase().trim());

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(sNis, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
                                        DataCell(Text(sName, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
                                        DataCell(Text(subj, style: GoogleFonts.inter(fontSize: 13))),
                                        DataCell(Text(isSubmitted ? '$pgScore' : '-', style: GoogleFonts.inter(fontSize: 13))),
                                        DataCell(Text(isSubmitted ? '$essayScore' : '-', style: GoogleFonts.inter(fontSize: 13))),
                                        DataCell(
                                          Text(
                                            isSubmitted ? '$score' : '-',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isGraded ? const Color(0xFF059669) : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        DataCell(_buildStatusBadge(statusKey)),
                                        DataCell(
                                          Row(
                                            children: [
                                              if (isGraded)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFECFDF5),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: const Color(0xFFA7F3D0)),
                                                  ),
                                                  child: Text(
                                                    'Dikoreksi oleh ${subData?['gradedByName'] ?? 'Guru'}',
                                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF047857)),
                                                  ),
                                                ),
                                              if (isDispatchedToTeacher && widget.isTeacher) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEEF2FF),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: const Color(0xFFC7D2FE)),
                                                  ),
                                                  child: Text(
                                                    'Dikirim oleh Admin Sekolah',
                                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4338CA)),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).whereType<DataRow>().toList();
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String statusKey) {
    if (statusKey == 'GRADED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
            const SizedBox(width: 4),
            Text(
              'Sudah Dikoreksi',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF047857)),
            ),
          ],
        ),
      );
    } else if (statusKey == 'FILLED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFF2563EB)),
            const SizedBox(width: 4),
            Text(
              'Sudah Diisi',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF1D4ED8)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle_outlined, size: 14, color: Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            'Belum Diisi',
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  void _showDispatchGradeModal() async {
    // Fetch teachers & subjects for school
    final teachersSnap = await _firestore.collection('schools').doc(widget.schoolId).collection('teachers').get();
    final subjectsSnap = await _firestore.collection('schools').doc(widget.schoolId).collection('subjects').get();

    final teachers = teachersSnap.docs;
    final subjects = subjectsSnap.docs;

    if (teachers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada data guru terdaftar di sekolah ini.')),
        );
      }
      return;
    }

    String? selectedTeacherId = teachers.first.id;
    String? selectedTeacherName = (teachers.first.data()['displayName'] ?? teachers.first.data()['name'] ?? '').toString();
    String? selectedSubjectName = subjects.isNotEmpty ? (subjects.first.data()['name'] ?? subjects.first.id).toString() : null;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.send_rounded, color: Color(0xFF4F46E5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Kirim Hasil Nilai ke Guru',
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih guru penerima dan mata pelajaran yang akan dikirimkan.',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              // Select Teacher
              Text('Pilih Guru:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedTeacherId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: teachers.map((tDoc) {
                  final tData = tDoc.data();
                  final tName = (tData['displayName'] ?? tData['name'] ?? tDoc.id).toString();
                  final tNip = (tData['nip'] ?? '').toString();
                  return DropdownMenuItem<String>(
                    value: tDoc.id,
                    child: Text('$tName ${tNip.isNotEmpty ? "($tNip)" : ""}'),
                  );
                }).toList(),
                onChanged: (val) {
                  setDialogState(() {
                    selectedTeacherId = val;
                    final selDoc = teachers.firstWhere((d) => d.id == val);
                    selectedTeacherName = (selDoc.data()['displayName'] ?? selDoc.data()['name'] ?? '').toString();
                  });
                },
              ),
              const SizedBox(height: 16),
              // Select Subject
              Text('Pilih Mata Pelajaran:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedSubjectName,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: subjects.map((sDoc) {
                  final sName = (sDoc.data()['name'] ?? sDoc.id).toString();
                  return DropdownMenuItem<String>(
                    value: sName,
                    child: Text(sName),
                  );
                }).toList(),
                onChanged: (val) => setDialogState(() => selectedSubjectName = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton.icon(
              onPressed: _isSendingGrade
                  ? null
                  : () async {
                      if (selectedTeacherId == null || selectedSubjectName == null) return;
                      setDialogState(() => _isSendingGrade = true);
                      try {
                        await _firestore.collection('schools').doc(widget.schoolId).collection('sentGrades').add({
                          'teacherId': selectedTeacherId,
                          'teacherName': selectedTeacherName,
                          'subjectName': selectedSubjectName,
                          'sentAt': FieldValue.serverTimestamp(),
                          'status': 'sent',
                        });

                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Hasil nilai $selectedSubjectName berhasil dikirim ke $selectedTeacherName!'),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Gagal mengirim nilai: $e'), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        setDialogState(() => _isSendingGrade = false);
                      }
                    },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Kirim Hasil Nilai'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
