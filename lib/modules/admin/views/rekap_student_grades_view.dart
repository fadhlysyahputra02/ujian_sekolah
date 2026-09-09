import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

class RekapStudentGradesView extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String subjectId;
  final String classId;
  final String eventName;
  final String subjectName;
  final String className;

  const RekapStudentGradesView({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.subjectId,
    required this.classId,
    required this.eventName,
    required this.subjectName,
    required this.className,
  });

  @override
  State<RekapStudentGradesView> createState() => _RekapStudentGradesViewState();
}

class _RekapStudentGradesViewState extends State<RekapStudentGradesView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String _errorMessage = '';

  List<Map<String, dynamic>> _students = [];
  Map<String, Map<String, dynamic>> _submissionsMap = {};

  String _searchQuery = '';
  String _selectedFilter = 'ALL'; // ALL, GRADED, PENDING, UNSUBMITTED

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 1. Fetch Class Document to get studentIds & real class name
      DocumentSnapshot classDocSnap = await _firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('classes')
          .doc(widget.classId)
          .get();

      List<String> studentIdsInClass = [];
      String fetchedClassName = widget.className;
      if (classDocSnap.exists) {
        final cData = classDocSnap.data() as Map<String, dynamic>? ?? {};
        final rawIds = cData['studentIds'];
        if (rawIds is List) {
          studentIdsInClass = rawIds.map((e) => e.toString().trim()).toList();
        }
        final nameStr = (cData['name'] ?? cData['className'] ?? '').toString().trim();
        if (nameStr.isNotEmpty) {
          fetchedClassName = nameStr;
        }
      }

      // 2. Fetch All Students in School
      QuerySnapshot studentSnap = await _firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .get();

      final List<Map<String, dynamic>> filteredStudents = [];
      final Set<String> addedStudentIds = {};

      for (var doc in studentSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final sId = doc.id;
        final cId = (data['classId'] ?? data['class_id'] ?? '').toString().trim();
        final cName = (data['className'] ?? data['kelas'] ?? data['studentClass'] ?? '').toString().trim();

        bool isMember = false;
        if (studentIdsInClass.contains(sId)) {
          isMember = true;
        } else if (cId.isNotEmpty && (cId == widget.classId || cId.toLowerCase() == widget.classId.toLowerCase())) {
          isMember = true;
        } else if (cName.isNotEmpty &&
            (cName.toLowerCase() == widget.className.toLowerCase() ||
             cName.toLowerCase() == fetchedClassName.toLowerCase())) {
          isMember = true;
        }

        if (isMember && !addedStudentIds.contains(sId)) {
          addedStudentIds.add(sId);
          data['id'] = sId;
          data['displayName'] = (data['displayName'] ?? data['name'] ?? data['fullName'] ?? data['nama'] ?? 'Tanpa Nama').toString().trim();
          data['nis'] = (data['nis'] ?? data['username'] ?? data['nisn'] ?? '-').toString().trim();
          filteredStudents.add(data);
        }
      }

      // 3. Fetch Submissions for this event
      QuerySnapshot subSnap = await _firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('submissions')
          .get();

      final Map<String, Map<String, dynamic>> subMap = {};

      for (var doc in subSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final sSubId = (data['subjectId'] ?? '').toString().trim();
        final sSubName = (data['subjectName'] ?? '').toString().trim();

        bool matchSubject = false;
        if (sSubId.isNotEmpty && sSubId == widget.subjectId) {
          matchSubject = true;
        } else if (sSubName.isNotEmpty && sSubName.toLowerCase() == widget.subjectName.toLowerCase()) {
          matchSubject = true;
        } else if (widget.subjectId.isEmpty || widget.subjectName.isEmpty) {
          matchSubject = true;
        }

        if (matchSubject) {
          final studentId = (data['studentId'] ?? data['userId'] ?? doc.id).toString().trim();
          final nis = (data['studentNis'] ?? data['nis'] ?? '').toString().trim();
          final sName = (data['studentName'] ?? data['name'] ?? data['displayName'] ?? '').toString().trim();
          final sClass = (data['className'] ?? data['classId'] ?? data['studentClass'] ?? '').toString().trim();

          if (studentId.isNotEmpty) subMap[studentId] = data;
          if (nis.isNotEmpty) subMap[nis] = data;
          subMap[doc.id] = data;

          // If student submitted for this class & subject but wasn't in allStudentsSnap:
          bool matchClass = (sClass.isNotEmpty &&
              (sClass.toLowerCase() == widget.className.toLowerCase() ||
               sClass.toLowerCase() == fetchedClassName.toLowerCase() ||
               sClass == widget.classId));

          if (matchClass && !addedStudentIds.contains(studentId)) {
            addedStudentIds.add(studentId);
            subMap[studentId] = data;
            filteredStudents.add({
              'id': studentId,
              'displayName': sName.isNotEmpty ? sName : 'Murid',
              'nis': nis.isNotEmpty ? nis : '-',
              'classId': widget.classId,
              'className': widget.className,
            });
          }
        }
      }

      // Sort students alphabetically by name
      filteredStudents.sort((a, b) => (a['displayName'] as String).compareTo(b['displayName'] as String));

      if (mounted) {
        setState(() {
          _students = filteredStudents;
          _submissionsMap = subMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic>? _getSubmissionForStudent(Map<String, dynamic> student) {
    final id = (student['id'] ?? '').toString().trim();
    final nis = (student['nis'] ?? '').toString().trim();
    final name = (student['displayName'] ?? '').toString().trim();

    return _submissionsMap[id] ?? _submissionsMap[nis] ?? _submissionsMap[name];
  }

  num? _extractTotalScore(Map<String, dynamic>? sub) {
    if (sub == null) return null;
    final val = sub['score'] ?? sub['finalScore'] ?? sub['totalScore'] ?? sub['nilai'] ?? sub['nilaiTotal'];
    if (val is num) return val;
    if (val != null) return num.tryParse(val.toString());
    return null;
  }

  num? _extractPgScore(Map<String, dynamic>? sub) {
    if (sub == null) return null;
    final val = sub['pgScore'] ?? sub['objectiveScore'] ?? sub['scorePg'];
    if (val is num) return val;
    if (val != null) return num.tryParse(val.toString());
    return null;
  }

  num? _extractEssayScore(Map<String, dynamic>? sub) {
    if (sub == null) return null;
    final val = sub['essayScore'] ?? sub['scoreEssay'];
    if (val is num) return val;
    if (val != null) return num.tryParse(val.toString());
    return null;
  }

  bool _isGraded(Map<String, dynamic>? sub) {
    if (sub == null) return false;
    return sub['isGraded'] == true || sub['graded'] == true || sub['isEvaluated'] == true;
  }

  bool _hasSubmitted(Map<String, dynamic>? sub) {
    if (sub == null) return false;
    return sub['isSubmitted'] == true || sub['submitted'] == true || sub['submittedAt'] != null || sub['status'] == 'submitted' || sub['status'] == 'completed';
  }

  Widget _buildStatusBadge(Map<String, dynamic>? sub) {
    final submitted = _hasSubmitted(sub);
    final graded = _isGraded(sub);

    if (graded) {
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
            const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF059669)),
            const SizedBox(width: 4),
            Text(
              'Sudah Dikoreksi',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF059669)),
            ),
          ],
        ),
      );
    } else if (submitted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pending_actions_rounded, size: 13, color: Color(0xFFD97706)),
            const SizedBox(width: 4),
            Text(
              'Menunggu Koreksi',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(
          'Belum Ujian',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
        ),
      );
    }
  }

  void _showStudentDetailModal(Map<String, dynamic> student, Map<String, dynamic>? sub) {
    final name = student['displayName'] ?? '-';
    final nis = student['nis'] ?? '-';
    final submitted = _hasSubmitted(sub);
    final graded = _isGraded(sub);
    final pgScore = _extractPgScore(sub);
    final essayScore = _extractEssayScore(sub);
    final totalScore = _extractTotalScore(sub);
    final corrector = (sub?['gradedByName'] ?? sub?['evaluator'] ?? 'Guru').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_rounded, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
                  ),
                  Text(
                    'NIS: $nis • Kelas ${widget.className}',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 16),
            _buildDetailRow('Status Ujian', submitted ? 'Sudah Mengerjakan' : 'Belum Mengerjakan'),
            _buildDetailRow('Status Koreksi', graded ? 'Sudah Dikoreksi oleh $corrector' : (submitted ? 'Menunggu Koreksi' : '-')),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildScoreRow('Nilai Pilihan Ganda (PG)', pgScore != null ? '$pgScore' : '-'),
                  const SizedBox(height: 8),
                  _buildScoreRow('Nilai Essay / Uraian', essayScore != null ? '$essayScore' : '-'),
                  const Divider(height: 20, color: Color(0xFFCBD5E1)),
                  _buildScoreRow('TOTAL NILAI AKHIR', totalScore != null ? '$totalScore' : '-', isTotal: true),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildScoreRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            color: isTotal ? const Color(0xFF4F46E5) : const Color(0xFF334155),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
            color: isTotal ? const Color(0xFF059669) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    // Filter Students
    final filtered = _students.where((s) {
      final name = (s['displayName'] ?? '').toString().toLowerCase();
      final nis = (s['nis'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase().trim();

      final matchesQuery = q.isEmpty || name.contains(q) || nis.contains(q);
      if (!matchesQuery) return false;

      final sub = _getSubmissionForStudent(s);
      final submitted = _hasSubmitted(sub);
      final graded = _isGraded(sub);

      if (_selectedFilter == 'GRADED') return graded;
      if (_selectedFilter == 'PENDING') return submitted && !graded;
      if (_selectedFilter == 'UNSUBMITTED') return !submitted;
      return true; // ALL
    }).toList();

    // Stats
    int totalCount = _students.length;
    int gradedCount = 0;
    int pendingCount = 0;
    num totalSum = 0;
    int numScored = 0;

    for (var s in _students) {
      final sub = _getSubmissionForStudent(s);
      if (_isGraded(sub)) {
        gradedCount++;
      } else if (_hasSubmitted(sub)) {
        pendingCount++;
      }
      final score = _extractTotalScore(sub);
      if (score != null) {
        totalSum += score;
        numScored++;
      }
    }

    final double avgScore = numScored > 0 ? (totalSum / numScored) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(
                '/admin/event/${widget.eventId}/rekap/${widget.subjectId}?eventName=${Uri.encodeComponent(widget.eventName)}&subjectName=${Uri.encodeComponent(widget.subjectName)}',
              );
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nilai Murid: Kelas ${widget.className}',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.eventName} • Mapel ${widget.subjectName}',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4F46E5)),
            tooltip: 'Refresh Data',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
                        const SizedBox(height: 16),
                        Text('Terjadi Kesalahan: $_errorMessage', style: GoogleFonts.inter(color: const Color(0xFFEF4444))),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 40 : 20,
                    vertical: 28,
                  ),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── SUMMARY STATS CARDS ──
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Total Murid',
                                  '$totalCount',
                                  Icons.people_alt_rounded,
                                  const Color(0xFF4F46E5),
                                  const Color(0xFFEEF2FF),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Sudah Dikoreksi',
                                  '$gradedCount',
                                  Icons.check_circle_rounded,
                                  const Color(0xFF059669),
                                  const Color(0xFFECFDF5),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Menunggu',
                                  '$pendingCount',
                                  Icons.pending_actions_rounded,
                                  const Color(0xFFD97706),
                                  const Color(0xFFFEF3C7),
                                ),
                              ),
                              if (isDesktop) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    'Rata-Rata',
                                    avgScore.toStringAsFixed(1),
                                    Icons.analytics_rounded,
                                    const Color(0xFF2563EB),
                                    const Color(0xFFEFF6FF),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── SEARCH & FILTER CONTROLS ──
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
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
                                  child: TextField(
                                    onChanged: (val) => setState(() => _searchQuery = val),
                                    decoration: InputDecoration(
                                      hintText: 'Cari murid berdasarkan NIS atau Nama...',
                                      hintStyle: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
                                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
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
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedFilter,
                                      icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF64748B)),
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _selectedFilter = val);
                                      },
                                      items: const [
                                        DropdownMenuItem(value: 'ALL', child: Text('Semua Status')),
                                        DropdownMenuItem(value: 'GRADED', child: Text('Sudah Dikoreksi')),
                                        DropdownMenuItem(value: 'PENDING', child: Text('Menunggu Koreksi')),
                                        DropdownMenuItem(value: 'UNSUBMITTED', child: Text('Belum Ujian')),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── DATA TABLE / LIST ──
                          if (filtered.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.person_off_outlined, size: 54, color: Color(0xFFCBD5E1)),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Tidak Ada Data Murid',
                                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tidak ditemukan murid yang sesuai dengan filter atau pencarian Anda.',
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      color: const Color(0xFFF8FAFC),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.groups_rounded, size: 20, color: Color(0xFF4F46E5)),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Daftar Murid Kelas ${widget.className}',
                                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                          ),
                                          const Spacer(),
                                          Text(
                                            'Menampilkan ${filtered.length} dari ${totalCount} murid',
                                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(minWidth: isDesktop ? 900 : 700),
                                        child: DataTable(
                                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                          dataRowMinHeight: 60,
                                          dataRowMaxHeight: 65,
                                          horizontalMargin: 20,
                                          columnSpacing: 24,
                                          columns: const [
                                            DataColumn(label: Text('NIS', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('NAMA MURID', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('NILAI PG', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('NILAI ESSAY', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('TOTAL NILAI', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('STATUS KOREKSI', style: TextStyle(fontWeight: FontWeight.bold))),
                                            DataColumn(label: Text('AKSI', style: TextStyle(fontWeight: FontWeight.bold))),
                                          ],
                                          rows: filtered.map((sData) {
                                            final nis = (sData['nis'] ?? '-').toString();
                                            final name = (sData['displayName'] ?? sData['name'] ?? '-').toString();
                                            final sub = _getSubmissionForStudent(sData);

                                            final submitted = _hasSubmitted(sub);
                                            final graded = _isGraded(sub);
                                            final pgScore = _extractPgScore(sub);
                                            final essayScore = _extractEssayScore(sub);
                                            final totalScore = _extractTotalScore(sub);

                                            return DataRow(
                                              cells: [
                                                DataCell(
                                                  Text(nis, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                                                ),
                                                DataCell(
                                                  Row(
                                                    children: [
                                                      CircleAvatar(
                                                        radius: 14,
                                                        backgroundColor: const Color(0xFFEEF2FF),
                                                        child: Text(
                                                          name.isNotEmpty ? name[0].toUpperCase() : 'M',
                                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Text(
                                                        name,
                                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    submitted ? (pgScore != null ? '$pgScore' : '-') : '-',
                                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    submitted ? (essayScore != null ? '$essayScore' : 'Belum') : '-',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      color: essayScore != null ? const Color(0xFF0F172A) : const Color(0xFFD97706),
                                                      fontWeight: essayScore != null ? FontWeight.bold : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: graded
                                                          ? const Color(0xFFECFDF5)
                                                          : (submitted ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9)),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      submitted ? (totalScore != null ? '$totalScore' : '-') : '-',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w900,
                                                        color: graded
                                                            ? const Color(0xFF059669)
                                                            : (submitted ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                DataCell(_buildStatusBadge(sub)),
                                                DataCell(
                                                  IconButton(
                                                    icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF4F46E5), size: 20),
                                                    tooltip: 'Lihat Detail Nilai',
                                                    onPressed: () => _showStudentDetailModal(sData, sub),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                ),
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
