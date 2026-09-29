import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/file_saver.dart';

class EventComprehensiveReportPage extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const EventComprehensiveReportPage({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<EventComprehensiveReportPage> createState() =>
      _EventComprehensiveReportPageState();
}

// Backwards compatibility alias
typedef EventComprehensiveReportDialog = EventComprehensiveReportPage;

class _EventComprehensiveReportPageState
    extends State<EventComprehensiveReportPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TabController _tabController;

  // Filter States
  String _selectedClass = 'ALL';
  String _selectedStatus = 'ALL'; // ALL, PASS, REMEDIAL, UNFILLED
  String _rankingMode = 'GLOBAL'; // GLOBAL, PER_CLASS
  String _searchQuery = '';
  final double _kkmScore = 75.0;

  // Pagination States
  int _currentPage = 1;
  int _pageSize = 20;

  bool _isGeneratingPdf = false;
  bool _isExportingCsv = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot>(
          stream: _firestore
              .collection('schools')
              .doc(widget.schoolId)
              .collection('events')
              .doc(widget.eventId)
              .snapshots(),
          builder: (context, eventSnap) {
            if (eventSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final eventData =
                eventSnap.data?.data() as Map<String, dynamic>? ?? {};
            final String eventTitle =
                (eventData['title'] ?? eventData['name'] ?? widget.eventName)
                    .toString();
            final String status =
                (eventData['status'] ?? 'draft').toString().toLowerCase();

            return StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('schools')
                  .doc(widget.schoolId)
                  .collection('classes')
                  .snapshots(),
              builder: (context, classesSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('schools')
                      .doc(widget.schoolId)
                      .collection('students')
                      .where('archived', isEqualTo: false)
                      .snapshots(),
                  builder: (context, studentsSnap) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('schools')
                          .doc(widget.schoolId)
                          .collection('events')
                          .doc(widget.eventId)
                          .collection('submissions')
                          .snapshots(),
                      builder: (context, submissionsSnap) {
                        final classDocs = classesSnap.data?.docs ?? [];
                        final studentDocs = studentsSnap.data?.docs ?? [];
                        final submissionDocs = submissionsSnap.data?.docs ?? [];

                        return _buildReportContent(
                          context: context,
                          eventData: eventData,
                          eventTitle: eventTitle,
                          status: status,
                          classDocs: classDocs,
                          studentDocs: studentDocs,
                          submissionDocs: submissionDocs,
                          isDesktop: isDesktop,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportContent({
    required BuildContext context,
    required Map<String, dynamic> eventData,
    required String eventTitle,
    required String status,
    required List<QueryDocumentSnapshot> classDocs,
    required List<QueryDocumentSnapshot> studentDocs,
    required List<QueryDocumentSnapshot> submissionDocs,
    required bool isDesktop,
  }) {
    // ------------------------------------------------------------------------
    // 1. CLASS LOOKUP MAP & SET BUILDER
    // ------------------------------------------------------------------------
    final Map<String, String> classIdToNameMap = {};
    final Map<String, String> studentToClassFromClasses = {};
    final Set<String> allClassesSet = {};

    for (var cDoc in classDocs) {
      final cData = cDoc.data() as Map<String, dynamic>;
      final cName = (cData['name'] ?? cData['className'] ?? cData['nama'] ?? '')
          .toString()
          .trim();
      if (cName.isNotEmpty) {
        classIdToNameMap[cDoc.id] = cName;
        allClassesSet.add(cName);

        // Map studentIds / students list inside class document
        final studentIds = cData['studentIds'] ?? cData['students'];
        if (studentIds is List) {
          for (var item in studentIds) {
            if (item is Map) {
              final id = (item['id'] ?? item['studentId'] ?? item['nis'] ?? item['uid'] ?? '').toString().trim();
              if (id.isNotEmpty) {
                studentToClassFromClasses[id] = cName;
                studentToClassFromClasses[id.toLowerCase()] = cName;
              }
            } else if (item is String) {
              final cleanId = item.trim();
              if (cleanId.isNotEmpty) {
                studentToClassFromClasses[cleanId] = cName;
                studentToClassFromClasses[cleanId.toLowerCase()] = cName;
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------------------
    // 2. STUDENT PROFILES DIRECTORY BUILDER
    // ------------------------------------------------------------------------
    final Map<String, Map<String, dynamic>> studentProfilesMap = {};

    for (var sDoc in studentDocs) {
      final sData = sDoc.data() as Map<String, dynamic>;
      final sId = sDoc.id;
      final displayName = (sData['displayName'] ?? sData['name'] ?? sData['nama'] ?? sData['studentName'] ?? '').toString().trim();
      final nis = (sData['nis'] ?? sData['nisn'] ?? sData['username'] ?? sData['studentNis'] ?? '').toString().trim();
      final uid = (sData['uid'] ?? sData['userId'] ?? '').toString().trim();

      final rawCls = (sData['className'] ?? sData['kelas'] ?? sData['classId'] ?? sData['studentClass'] ?? sData['namaKelas'] ?? '').toString().trim();
      final resolvedCls = classIdToNameMap[rawCls] ?? rawCls;

      final profileRecord = {
        'docId': sId,
        'name': displayName,
        'nis': nis.isNotEmpty ? nis : sId,
        'className': resolvedCls.isNotEmpty ? resolvedCls : (studentToClassFromClasses[sId] ?? 'Tanpa Kelas'),
        'data': sData,
      };

      // Register profile under all possible key variants
      studentProfilesMap[sId] = profileRecord;
      studentProfilesMap[sId.toLowerCase()] = profileRecord;
      if (nis.isNotEmpty) {
        studentProfilesMap[nis] = profileRecord;
        studentProfilesMap[nis.toLowerCase()] = profileRecord;
      }
      if (uid.isNotEmpty) {
        studentProfilesMap[uid] = profileRecord;
        studentProfilesMap[uid.toLowerCase()] = profileRecord;
      }
      if (displayName.isNotEmpty) {
        studentProfilesMap[displayName] = profileRecord;
        studentProfilesMap[displayName.toLowerCase()] = profileRecord;
      }
    }

    // ------------------------------------------------------------------------
    // 3. SUBMISSIONS & SUBJECTS AGGREGATION (With Case-Insensitive Normalization)
    // ------------------------------------------------------------------------
    final Map<String, Map<String, dynamic>> studentSubmissionMap = {};
    final Set<String> allSubjects = {};
    final Map<String, String> lowerToCanonicalSubjectMap = {};

    String getCanonicalSubject(String rawName) {
      final clean = rawName.trim();
      if (clean.isEmpty) return '';
      final lower = clean.toLowerCase();
      if (!lowerToCanonicalSubjectMap.containsKey(lower)) {
        lowerToCanonicalSubjectMap[lower] = clean;
      } else {
        final existing = lowerToCanonicalSubjectMap[lower]!;
        if (existing == existing.toLowerCase() && clean != clean.toLowerCase()) {
          lowerToCanonicalSubjectMap[lower] = clean;
        }
      }
      return lowerToCanonicalSubjectMap[lower]!;
    }

    final List<Map<String, dynamic>> submissions = submissionDocs
        .map((d) => d.data() as Map<String, dynamic>)
        .toList();

    for (var sub in submissions) {
      final sId = (sub['studentId'] ?? sub['nis'] ?? sub['studentName'] ?? sub['uid'] ?? '')
          .toString()
          .trim();
      final rawSubject = (sub['subjectName'] ?? sub['subjectId'] ?? '')
          .toString()
          .trim();
      final sSubject = getCanonicalSubject(rawSubject);
      final rawCls = (sub['className'] ?? sub['studentClass'] ?? sub['classId'] ?? '')
          .toString()
          .trim();
      final cls = classIdToNameMap[rawCls] ?? rawCls;

      if (sId.isNotEmpty && sSubject.isNotEmpty) {
        final lowerSubj = sSubject.toLowerCase();
        studentSubmissionMap['${sId}_$sSubject'] = sub;
        studentSubmissionMap['${sId}_$lowerSubj'] = sub;
        studentSubmissionMap['${sId.toLowerCase()}_$sSubject'] = sub;
        studentSubmissionMap['${sId.toLowerCase()}_$lowerSubj'] = sub;
      }
      if (sSubject.isNotEmpty) allSubjects.add(sSubject);
      if (cls.isNotEmpty && cls.toLowerCase() != 'tanpa kelas') {
        allClassesSet.add(cls);
      }
    }

    final List<String> sortedSubjects = allSubjects.map((s) => getCanonicalSubject(s)).toSet().toList()..sort();

    // Helper to check if a student record is marked as alumni
    bool checkIfAlumni(Map<String, dynamic>? sData, String resolvedClassName) {
      if (sData != null) {
        final statusStr = (sData['status'] ?? '').toString().toLowerCase().trim();
        if (statusStr == 'alumni' || statusStr == 'graduated' || statusStr == 'lulus' || statusStr == 'alumnus') {
          return true;
        }
        if (sData['graduated'] == true ||
            sData['isGraduated'] == true ||
            sData['isAlumni'] == true ||
            sData['alumni'] == true) {
          return true;
        }
      }
      final lowerCls = resolvedClassName.toLowerCase().trim();
      if (lowerCls.contains('alumni')) {
        return true;
      }
      return false;
    }

    // ------------------------------------------------------------------------
    // 4. UNIFIED STUDENT LIST BUILDER (From Profiles + Submissions + Classes)
    // ------------------------------------------------------------------------
    final Map<String, Map<String, dynamic>> unifiedStudentInfoMap = {};

    // A. Add from studentDocs profiles
    for (var sDoc in studentDocs) {
      final sData = sDoc.data() as Map<String, dynamic>;
      final sId = sDoc.id;
      final name = (sData['displayName'] ?? sData['name'] ?? sData['nama'] ?? sData['studentName'] ?? '').toString().trim();
      final nis = (sData['nis'] ?? sData['nisn'] ?? sData['username'] ?? sData['studentNis'] ?? '').toString().trim();

      final rawCls = (sData['className'] ?? sData['kelas'] ?? sData['classId'] ?? sData['studentClass'] ?? sData['namaKelas'] ?? '').toString().trim();
      final cls = classIdToNameMap[rawCls] ?? (rawCls.isNotEmpty ? rawCls : (studentToClassFromClasses[sId] ?? 'Tanpa Kelas'));
      final angkatan = (sData['angkatan'] ?? sData['targetAngkatan'] ?? sData['year'] ?? '').toString().trim();
      final isAlumni = checkIfAlumni(sData, cls);

      unifiedStudentInfoMap[sId] = {
        'id': sId,
        'nis': nis.isNotEmpty ? nis : sId,
        'name': name.isNotEmpty ? name : (nis.isNotEmpty ? nis : 'Siswa $sId'),
        'className': cls,
        'rawClass': rawCls,
        'angkatan': angkatan,
        'isAlumni': isAlumni,
      };
    }

    // B. Add / Enrich from Submissions
    for (var sub in submissions) {
      final subStudentId = (sub['studentId'] ?? sub['nis'] ?? sub['uid'] ?? sub['studentName'] ?? '').toString().trim();
      final subNis = (sub['nis'] ?? sub['nisn'] ?? sub['username'] ?? sub['studentId'] ?? '').toString().trim();
      final subName = (sub['studentName'] ?? sub['displayName'] ?? sub['nama'] ?? sub['name'] ?? '').toString().trim();
      final rawSubCls = (sub['className'] ?? sub['studentClass'] ?? sub['kelas'] ?? sub['classId'] ?? '').toString().trim();
      final subCls = classIdToNameMap[rawSubCls] ?? rawSubCls;

      if (subStudentId.isEmpty) continue;

      // Check if profile exists in studentProfilesMap
      final profile = studentProfilesMap[subStudentId] ??
          studentProfilesMap[subNis] ??
          studentProfilesMap[subStudentId.toLowerCase()] ??
          studentProfilesMap[subNis.toLowerCase()];

      String resolvedId = profile?['docId'] ?? subStudentId;
      String resolvedNis = (profile?['nis'] as String?) ?? (subNis.isNotEmpty ? subNis : subStudentId);

      // Check name: Profile Name > Submission Name > NIS > ID
      String resolvedName = (profile?['name'] as String? ?? '').trim();
      if (resolvedName.isEmpty && subName.isNotEmpty && subName != subStudentId && subName != subNis) {
        resolvedName = subName;
      }
      if (resolvedName.isEmpty) {
        resolvedName = resolvedNis.isNotEmpty ? resolvedNis : 'Siswa $subStudentId';
      }

      // Check class: Profile Class > Class Collection Map > Submission Class
      String resolvedClass = (profile?['className'] as String? ?? '').trim();
      if ((resolvedClass.isEmpty || resolvedClass == 'Tanpa Kelas') && subCls.isNotEmpty) {
        resolvedClass = subCls;
      }
      if ((resolvedClass.isEmpty || resolvedClass == 'Tanpa Kelas')) {
        resolvedClass = studentToClassFromClasses[subStudentId] ??
            studentToClassFromClasses[resolvedNis] ??
            'Tanpa Kelas';
      }

      if (resolvedClass.isNotEmpty && resolvedClass.toLowerCase() != 'tanpa kelas') {
        allClassesSet.add(resolvedClass);
      }

      final profileData = profile?['data'] as Map<String, dynamic>?;
      final isAlumni = checkIfAlumni(profileData, resolvedClass);
      final angkatan = (profileData?['angkatan'] ?? profileData?['targetAngkatan'] ?? profileData?['year'] ?? '').toString().trim();

      unifiedStudentInfoMap.putIfAbsent(resolvedId, () => {
        'id': resolvedId,
        'nis': resolvedNis,
        'name': resolvedName,
        'className': resolvedClass,
        'rawClass': subCls,
        'angkatan': angkatan,
        'isAlumni': isAlumni,
      });

      // Update existing record if it had placeholder 'Tanpa Nama' or 'Tanpa Kelas'
      final existing = unifiedStudentInfoMap[resolvedId]!;
      if ((existing['name'] == null || existing['name'].toString().startsWith('Tanpa') || existing['name'].toString().isEmpty) && resolvedName.isNotEmpty) {
        existing['name'] = resolvedName;
      }
      if ((existing['className'] == null || existing['className'] == 'Tanpa Kelas' || existing['className'].toString().isEmpty) && resolvedClass.isNotEmpty && resolvedClass != 'Tanpa Kelas') {
        existing['className'] = resolvedClass;
      }
      if ((existing['nis'] == null || existing['nis'].toString().isEmpty) && resolvedNis.isNotEmpty) {
        existing['nis'] = resolvedNis;
      }
      if (profileData != null && checkIfAlumni(profileData, existing['className']?.toString() ?? '')) {
        existing['isAlumni'] = true;
      }
      if ((existing['angkatan'] == null || existing['angkatan'].toString().isEmpty) && angkatan.isNotEmpty) {
        existing['angkatan'] = angkatan;
      }
    }

    final List<String> sortedClasses = allClassesSet.toList()..sort();

    // ------------------------------------------------------------------------
    // COLLECT EVENT TARGET CLASSES & ANGKATANS
    // ------------------------------------------------------------------------
    final Set<String> eventTargetClasses = {};
    final Set<String> eventTargetAngkatans = {};

    void addTargetClass(dynamic val) {
      if (val == null) return;
      if (val is List) {
        for (var item in val) {
          addTargetClass(item);
        }
      } else if (val is Map) {
        if (val['id'] != null) addTargetClass(val['id']);
        if (val['classId'] != null) addTargetClass(val['classId']);
        if (val['className'] != null) addTargetClass(val['className']);
        if (val['name'] != null) addTargetClass(val['name']);
      } else {
        final str = val.toString().trim();
        if (str.isNotEmpty) {
          eventTargetClasses.add(str.toLowerCase());
          if (classIdToNameMap.containsKey(str)) {
            eventTargetClasses.add(classIdToNameMap[str]!.toLowerCase());
          }
        }
      }
    }

    void addTargetAngkatan(dynamic val) {
      if (val == null) return;
      if (val is List) {
        for (var item in val) {
          addTargetAngkatan(item);
        }
      } else {
        final str = val.toString().trim();
        if (str.isNotEmpty) eventTargetAngkatans.add(str.toLowerCase());
      }
    }

    // Direct event fields
    addTargetClass(eventData['classes']);
    addTargetClass(eventData['classIds']);
    addTargetClass(eventData['targetClasses']);
    addTargetClass(eventData['targetClassIds']);
    addTargetClass(eventData['classNames']);
    addTargetAngkatan(eventData['angkatan']);
    addTargetAngkatan(eventData['targetAngkatan']);
    addTargetAngkatan(eventData['targetAngkatans']);

    // Timetable / Schedule items
    final timetable = eventData['timetable'] ?? eventData['jadwal'] ?? eventData['schedules'] ?? eventData['exams'];
    if (timetable is List) {
      for (var t in timetable) {
        if (t is Map) {
          addTargetClass(t['classIds']);
          addTargetClass(t['classNames']);
          addTargetClass(t['classes']);
          addTargetClass(t['targetClasses']);
          addTargetClass(t['targetClassIds']);
          addTargetClass(t['classId']);
          addTargetClass(t['className']);
          addTargetClass(t['targetClass']);
          addTargetAngkatan(t['angkatan']);
          addTargetAngkatan(t['targetAngkatan']);
        }
      }
    }

    // ------------------------------------------------------------------------
    // 5. CALCULATE TOTALS & SCORE AGGREGATES PER STUDENT
    // ------------------------------------------------------------------------
    List<_StudentReportData> processedStudents = [];

    unifiedStudentInfoMap.forEach((key, stInfo) {
      final sId = stInfo['id'].toString();
      final sNis = stInfo['nis'].toString();
      final sName = stInfo['name'].toString();
      final sClass = stInfo['className'].toString();
      final sRawClass = (stInfo['rawClass'] ?? '').toString();
      final sAngkatan = (stInfo['angkatan'] ?? '').toString();
      final bool isAlumni = stInfo['isAlumni'] == true;

      Map<String, double?> subjectScores = {};
      double totalScoreSum = 0;
      int completedSubjectsCount = 0;

      for (var subj in sortedSubjects) {
        final subData = studentSubmissionMap['${sId}_$subj'] ??
            studentSubmissionMap['${sId.toLowerCase()}_$subj'] ??
            studentSubmissionMap['${sNis}_$subj'] ??
            studentSubmissionMap['${sNis.toLowerCase()}_$subj'] ??
            studentSubmissionMap['${sName}_$subj'];

        if (subData != null) {
          final pgScore = (subData['pgScore'] as num?)?.toDouble() ?? 0.0;
          final essayScore = (subData['essayScore'] as num?)?.toDouble() ?? 0.0;
          final rawScore = subData['score'] as num?;

          final score = rawScore?.toDouble() ?? (pgScore + essayScore);
          subjectScores[subj] = score;
          totalScoreSum += score;
          completedSubjectsCount++;
        } else {
          subjectScores[subj] = null;
        }
      }

      final double avgScore = sortedSubjects.isNotEmpty
          ? (completedSubjectsCount > 0 ? (totalScoreSum / sortedSubjects.length) : 0.0)
          : 0.0;

      final bool isPassed = avgScore >= _kkmScore;
      final bool hasDoneAny = completedSubjectsCount > 0;

      // Check target status in event
      bool isTargetedByEvent = false;
      if (eventTargetClasses.isNotEmpty) {
        if (eventTargetClasses.contains(sId.toLowerCase()) ||
            eventTargetClasses.contains(sNis.toLowerCase()) ||
            eventTargetClasses.contains(sRawClass.toLowerCase()) ||
            eventTargetClasses.contains(sClass.toLowerCase())) {
          isTargetedByEvent = true;
        }
      }
      if (!isTargetedByEvent && eventTargetAngkatans.isNotEmpty && sAngkatan.isNotEmpty) {
        if (eventTargetAngkatans.contains(sAngkatan.toLowerCase())) {
          isTargetedByEvent = true;
        }
      }

      // Filter rule: Exclude alumni students who did not work on any exam and were not targeted by the event
      if (isAlumni && !hasDoneAny && !isTargetedByEvent) {
        return;
      }

      processedStudents.add(_StudentReportData(
        id: sId,
        nis: sNis,
        name: sName,
        className: sClass,
        subjectScores: subjectScores,
        totalScore: totalScoreSum,
        averageScore: avgScore,
        completedCount: completedSubjectsCount,
        isPassed: isPassed,
        hasDoneAny: hasDoneAny,
      ));
    });

    // Sort Global Ranking (highest average first)
    processedStudents.sort((a, b) => b.averageScore.compareTo(a.averageScore));
    for (int i = 0; i < processedStudents.length; i++) {
      processedStudents[i].globalRank = i + 1;
    }

    // Sort Per-Class Ranking
    final Map<String, List<_StudentReportData>> classGrouped = {};
    for (var st in processedStudents) {
      classGrouped.putIfAbsent(st.className, () => []).add(st);
    }

    classGrouped.forEach((cls, list) {
      list.sort((a, b) => b.averageScore.compareTo(a.averageScore));
      for (int i = 0; i < list.length; i++) {
        list[i].classRank = i + 1;
      }
    });

    // Apply Filters to active list
    List<_StudentReportData> filteredStudents = processedStudents.where((st) {
      if (_selectedClass != 'ALL' && st.className != _selectedClass) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = st.name.toLowerCase().contains(q);
        final matchNis = st.nis.toLowerCase().contains(q);
        if (!matchName && !matchNis) return false;
      }
      if (_selectedStatus != 'ALL') {
        if (_selectedStatus == 'PASS' && !st.isPassed) return false;
        if (_selectedStatus == 'REMEDIAL' && (st.isPassed || !st.hasDoneAny)) {
          return false;
        }
        if (_selectedStatus == 'UNFILLED' && st.hasDoneAny) return false;
      }
      return true;
    }).toList();

    // Summary Metrics
    final totalStudentsCount = processedStudents.length;
    final totalSubmittedStudents =
        processedStudents.where((s) => s.hasDoneAny).length;
    final totalPassedCount =
        processedStudents.where((s) => s.hasDoneAny && s.isPassed).length;
    final totalRemedialCount =
        processedStudents.where((s) => s.hasDoneAny && !s.isPassed).length;

    double grandTotalAvg = 0;
    if (totalSubmittedStudents > 0) {
      grandTotalAvg = processedStudents
              .where((s) => s.hasDoneAny)
              .fold<double>(0.0, (acc, s) => acc + s.averageScore) /
          totalSubmittedStudents;
    }

    final topStudent = processedStudents.isNotEmpty && processedStudents.first.hasDoneAny
        ? processedStudents.first
        : null;

    return Column(
      children: [
        // 1. PAGE HEADER BAR
        _buildPageHeader(
          context: context,
          eventTitle: eventTitle,
          status: status,
          processedStudents: processedStudents,
          sortedSubjects: sortedSubjects,
          isDesktop: isDesktop,
        ),

        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // 2. EXECUTIVE METRIC SUMMARY CARDS
        _buildExecutiveMetrics(
          totalStudents: totalStudentsCount,
          submittedStudents: totalSubmittedStudents,
          passedStudents: totalPassedCount,
          remedialStudents: totalRemedialCount,
          overallAverage: grandTotalAvg,
          topStudent: topStudent,
          isDesktop: isDesktop,
        ),

        // 3. FILTER TOOLBAR & TAB BAR
        _buildFilterToolbar(
          sortedClasses: sortedClasses,
          sortedSubjects: sortedSubjects,
          isDesktop: isDesktop,
        ),

        // 4. TAB CONTENTS
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: Leger Nilai & Ranking Table (With Pagination)
              _buildLegerRankingTab(
                filteredStudents: filteredStudents,
                sortedSubjects: sortedSubjects,
                isDesktop: isDesktop,
              ),

              // TAB 2: Class Performance Analytics
              _buildClassAnalyticsTab(
                classGrouped: classGrouped,
                sortedSubjects: sortedSubjects,
                isDesktop: isDesktop,
              ),

              // TAB 3: Subject Performance Analytics
              _buildSubjectAnalyticsTab(
                processedStudents: processedStudents,
                sortedSubjects: sortedSubjects,
                isDesktop: isDesktop,
              ),

              // TAB 4: Score Distribution Chart/Breakdown
              _buildScoreDistributionTab(
                processedStudents: processedStudents,
                isDesktop: isDesktop,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET BUILDERS
  // --------------------------------------------------------------------------

  Widget _buildPageHeader({
    required BuildContext context,
    required String eventTitle,
    required String status,
    required List<_StudentReportData> processedStudents,
    required List<String> sortedSubjects,
    required bool isDesktop,
  }) {
    Color statusBg;
    Color statusText;
    String statusLabel;

    switch (status) {
      case 'active':
      case 'published':
        statusBg = const Color(0xFFDCFCE7);
        statusText = const Color(0xFF166534);
        statusLabel = 'BERLANGSUNG';
        break;
      case 'closed':
      case 'finished':
        statusBg = const Color(0xFFE0F2FE);
        statusText = const Color(0xFF075985);
        statusLabel = 'SELESAI';
        break;
      default:
        statusBg = const Color(0xFFFEF3C7);
        statusText = const Color(0xFF92400E);
        statusLabel = 'DRAFT';
    }

    final topInset = MediaQuery.of(context).padding.top;

    if (!isDesktop) {
      // MOBILE HEADER
      return Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(12, topInset > 0 ? (topInset + 8) : 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.go('/admin/eventujian');
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text('Kembali',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    backgroundColor: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eventTitle,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Rekapitulasi Leger Nilai, Ranking Siswa, & Analisis Hasil Ujian',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF64748B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isGeneratingPdf
                        ? null
                        : () => _exportPdfLeger(
                              eventTitle: eventTitle,
                              processedStudents: processedStudents,
                              sortedSubjects: sortedSubjects,
                            ),
                    icon: _isGeneratingPdf
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 14),
                    label: Text(
                      'PDF Leger',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isExportingCsv
                        ? null
                        : () => _exportCsvLeger(
                              eventTitle: eventTitle,
                              processedStudents: processedStudents,
                              sortedSubjects: sortedSubjects,
                            ),
                    icon: const Icon(Icons.table_chart_rounded, size: 14),
                    label: Text(
                      'CSV/Excel',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // DESKTOP HEADER
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // Back Button
          OutlinedButton.icon(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/admin/eventujian');
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text('Kembali',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              backgroundColor: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
          ),
          const SizedBox(width: 16),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Color(0xFF4F46E5),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Laporan Complete Event: $eventTitle',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Rekapitulasi Leger Nilai, Ranking Siswa, & Analisis Ketercapaian Hasil Ujian',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Export PDF Button
          ElevatedButton.icon(
            onPressed: _isGeneratingPdf
                ? null
                : () => _exportPdfLeger(
                      eventTitle: eventTitle,
                      processedStudents: processedStudents,
                      sortedSubjects: sortedSubjects,
                    ),
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_rounded, size: 16),
            label: Text(
              'Cetak PDF Leger',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 10),

          // Export Excel / CSV Button
          ElevatedButton.icon(
            onPressed: _isExportingCsv
                ? null
                : () => _exportCsvLeger(
                      eventTitle: eventTitle,
                      processedStudents: processedStudents,
                      sortedSubjects: sortedSubjects,
                    ),
            icon: const Icon(Icons.table_chart_rounded, size: 16),
            label: Text(
              'Ekspor CSV/Excel',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveMetrics({
    required int totalStudents,
    required int submittedStudents,
    required int passedStudents,
    required int remedialStudents,
    required double overallAverage,
    required _StudentReportData? topStudent,
    required bool isDesktop,
  }) {
    final double passRate =
        submittedStudents > 0 ? (passedStudents / submittedStudents) * 100 : 0.0;

    return Padding(
      padding: isDesktop
          ? const EdgeInsets.fromLTRB(24, 16, 24, 12)
          : const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;
          return GridView.count(
            crossAxisCount: isNarrow ? 2 : 4,
            crossAxisSpacing: isDesktop ? 14 : 8,
            mainAxisSpacing: isDesktop ? 14 : 8,
            childAspectRatio: isDesktop ? (isNarrow ? 2.5 : 3.0) : 2.1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildMetricCard(
                title: 'Total Peserta Ujian',
                value: '$submittedStudents / $totalStudents',
                subText:
                    '${((submittedStudents / (totalStudents == 0 ? 1 : totalStudents)) * 100).toInt()}% Mengerjakan',
                icon: Icons.people_alt_rounded,
                iconColor: const Color(0xFF3B82F6),
                bgColor: const Color(0xFFEFF6FF),
                isDesktop: isDesktop,
              ),
              _buildMetricCard(
                title: 'Rata-Rata Event',
                value: overallAverage.toStringAsFixed(1),
                subText: 'Standar KKM: ${_kkmScore.toInt()}',
                icon: Icons.auto_graph_rounded,
                iconColor: const Color(0xFF8B5CF6),
                bgColor: const Color(0xFFF5F3FF),
                isDesktop: isDesktop,
              ),
              _buildMetricCard(
                title: 'Tingkat Ketuntasan',
                value: '${passRate.toStringAsFixed(1)}%',
                subText: '$passedStudents Tuntas | $remedialStudents Remedial',
                icon: Icons.verified_rounded,
                iconColor: const Color(0xFF10B981),
                bgColor: const Color(0xFFECFDF5),
                isDesktop: isDesktop,
              ),
              _buildMetricCard(
                title: 'Juara 1 (Tertinggi)',
                value: topStudent != null
                    ? topStudent.averageScore.toStringAsFixed(1)
                    : '-',
                subText: topStudent != null
                    ? '${topStudent.name} (${topStudent.className})'
                    : 'Belum ada data',
                icon: Icons.emoji_events_rounded,
                iconColor: const Color(0xFFF59E0B),
                bgColor: const Color(0xFFFFFBEB),
                isDesktop: isDesktop,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subText,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required bool isDesktop,
  }) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 14 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isDesktop ? 12 : 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: isDesktop ? 24 : 18),
          ),
          SizedBox(width: isDesktop ? 12 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: isDesktop ? 12 : 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: isDesktop ? 18 : 14.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subText,
                  style: GoogleFonts.inter(
                    fontSize: isDesktop ? 11 : 9.5,
                    fontWeight: FontWeight.w500,
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

  Widget _buildFilterToolbar({
    required List<String> sortedClasses,
    required List<String> sortedSubjects,
    required bool isDesktop,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 24 : 10, vertical: isDesktop ? 10 : 6),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              // Tab Selector Bar
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: const Color(0xFF4F46E5),
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.bold, fontSize: 13.5),
                  unselectedLabelStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w500, fontSize: 13.5),
                  indicatorColor: const Color(0xFF4F46E5),
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(
                        child: Row(children: [
                      Icon(Icons.military_tech_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Leger & Ranking Siswa')
                    ])),
                    Tab(
                        child: Row(children: [
                      Icon(Icons.meeting_room_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Analisis Per Kelas')
                    ])),
                    Tab(
                        child: Row(children: [
                      Icon(Icons.menu_book_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Analisis Per Mapel')
                    ])),
                    Tab(
                        child: Row(children: [
                      Icon(Icons.donut_large_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Distribusi Nilai')
                    ])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filters Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Search Input
                SizedBox(
                  width: 240,
                  height: 40,
                  child: TextField(
                    onChanged: (val) => setState(() {
                      _searchQuery = val;
                      _currentPage = 1;
                    }),
                    decoration: InputDecoration(
                      hintText: 'Cari Nama / NISN...',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    style: GoogleFonts.inter(fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 12),

                // Filter Kelas
                _buildDropdownFilter(
                  label: 'Kelas',
                  value: _selectedClass,
                  options: ['ALL', ...sortedClasses],
                  onChanged: (val) => setState(() {
                    _selectedClass = val!;
                    _currentPage = 1;
                  }),
                ),
                const SizedBox(width: 12),

                // Filter Status
                _buildDropdownFilter(
                  label: 'Status',
                  value: _selectedStatus,
                  optionsMap: {
                    'ALL': 'Semua Status',
                    'PASS': 'Tuntas (>= KKM)',
                    'REMEDIAL': 'Remedial (< KKM)',
                    'UNFILLED': 'Belum Ujian',
                  },
                  onChanged: (val) => setState(() {
                    _selectedStatus = val!;
                    _currentPage = 1;
                  }),
                ),
                const SizedBox(width: 12),

                // Mode Ranking
                _buildDropdownFilter(
                  label: 'Mode Ranking',
                  value: _rankingMode,
                  optionsMap: {
                    'GLOBAL': '🏆 Ranking Global (Se-Event)',
                    'PER_CLASS': '🏫 Ranking Per Kelas',
                  },
                  onChanged: (val) => setState(() {
                    _rankingMode = val!;
                    _currentPage = 1;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    List<String>? options,
    Map<String, String>? optionsMap,
    required ValueChanged<String?> onChanged,
  }) {
    final Map<String, String> displayMap = optionsMap ??
        {for (var opt in (options ?? [])) opt: opt == 'ALL' ? 'Semua $label' : opt};

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: displayMap.containsKey(value) ? value : displayMap.keys.first,
          onChanged: onChanged,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: Color(0xFF64748B)),
          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF1E293B)),
          items: displayMap.entries.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 1: LEGER & RANKING TAB WITH PAGINATION (10, 20, 30, 50, 100)
  // --------------------------------------------------------------------------
  Widget _buildLegerRankingTab({
    required List<_StudentReportData> filteredStudents,
    required List<String> sortedSubjects,
    required bool isDesktop,
  }) {
    if (filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 54, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Tidak ada data siswa yang sesuai filter.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Pagination Calculation
    final int totalItems = filteredStudents.length;
    final int totalPages = totalItems > 0 ? (totalItems / _pageSize).ceil() : 1;
    if (_currentPage > totalPages) _currentPage = totalPages;
    if (_currentPage < 1) _currentPage = 1;

    final int startIndex = totalItems > 0 ? (_currentPage - 1) * _pageSize : 0;
    final int endIndex = (startIndex + _pageSize).clamp(0, totalItems);
    final currentPageStudents = totalItems > 0 ? filteredStudents.sublist(startIndex, endIndex) : <_StudentReportData>[];

    return Padding(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 8.0),
      child: Column(
        children: [
          // Table Card
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE2E8F0))),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor:
                        WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 52,
                    columnSpacing: isDesktop ? 24 : 16,
                    columns: [
                      DataColumn(
                        label: Text(
                          _rankingMode == 'GLOBAL' ? 'Rank Global' : 'Rank Kelas',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155)),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'NISN / ID',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155)),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Nama Siswa',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155)),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Kelas',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155)),
                        ),
                      ),
                      // Dynamic Subject Columns
                      ...sortedSubjects.map(
                        (s) => DataColumn(
                          label: Text(
                            s,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF334155)),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Total Nilai',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155)),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Rata-Rata',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155)),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Status',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155)),
                        ),
                      ),
                    ],
                    rows: currentPageStudents.map((st) {
                      final rank = _rankingMode == 'GLOBAL'
                          ? st.globalRank
                          : st.classRank;

                      return DataRow(
                        cells: [
                          // Rank Badge
                          DataCell(_buildRankBadge(rank)),
                          DataCell(Text(st.nis.isNotEmpty ? st.nis : st.id.substring(0, 6),
                              style: GoogleFonts.inter(fontSize: 12.5))),
                          DataCell(
                            Text(
                              st.name,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          DataCell(Text(st.className,
                              style: GoogleFonts.inter(fontSize: 12.5))),
                          // Subject Scores
                          ...sortedSubjects.map((s) {
                            final score = st.subjectScores[s];
                            return DataCell(
                              score != null
                                  ? Text(
                                      score.toStringAsFixed(1),
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: score >= _kkmScore
                                            ? const Color(0xFF166534)
                                            : const Color(0xFFDC2626),
                                      ),
                                    )
                                  : Text(
                                      '-',
                                      style: GoogleFonts.inter(
                                          fontSize: 12.5, color: const Color(0xFF94A3B8)),
                                    ),
                            );
                          }),
                          DataCell(
                            Text(
                              st.totalScore.toStringAsFixed(1),
                              style: GoogleFonts.inter(
                                  fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: st.averageScore >= _kkmScore
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                st.averageScore.toStringAsFixed(1),
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: st.averageScore >= _kkmScore
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: !st.hasDoneAny
                                    ? const Color(0xFFF1F5F9)
                                    : (st.isPassed
                                        ? const Color(0xFFDCFCE7)
                                        : const Color(0xFFFEE2E2)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                !st.hasDoneAny
                                    ? 'Belum Ujian'
                                    : (st.isPassed ? 'TUNTAS' : 'REMEDIAL'),
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: !st.hasDoneAny
                                      ? const Color(0xFF64748B)
                                      : (st.isPassed
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFFB91C1C)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // PAGINATION FOOTER CONTROL BAR
          Container(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Info Count Text
                  Text(
                    '${totalItems > 0 ? (startIndex + 1) : 0}-$endIndex dari $totalItems Siswa',
                    style: GoogleFonts.inter(
                      fontSize: isDesktop ? 12.5 : 11.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(width: isDesktop ? 24 : 12),

                  Row(
                    children: [
                      // Page Size Selector (10, 20, 30, 50, 100)
                      Text('Baris:',
                          style: GoogleFonts.inter(
                              fontSize: 11.5, color: const Color(0xFF64748B))),
                      const SizedBox(width: 6),
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _pageSize,
                            items: const [10, 20, 30, 50, 100].map((int val) {
                              return DropdownMenuItem<int>(
                                value: val,
                                child: Text('$val',
                                    style: GoogleFonts.inter(
                                        fontSize: 12, fontWeight: FontWeight.bold)),
                              );
                            }).toList(),
                            onChanged: (newSize) {
                              if (newSize != null) {
                                setState(() {
                                  _pageSize = newSize;
                                  _currentPage = 1;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // First Page Button
                      IconButton(
                        icon: const Icon(Icons.first_page_rounded, size: 18),
                        onPressed: _currentPage > 1
                            ? () => setState(() => _currentPage = 1)
                            : null,
                        tooltip: 'Halaman Pertama',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),

                      // Prev Page Button
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 18),
                        onPressed: _currentPage > 1
                            ? () => setState(() => _currentPage--)
                            : null,
                        tooltip: 'Halaman Sebelumnya',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),

                      // Current Page Display
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Hal $_currentPage/ $totalPages',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),

                      // Next Page Button
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, size: 18),
                        onPressed: _currentPage < totalPages
                            ? () => setState(() => _currentPage++)
                            : null,
                        tooltip: 'Halaman Selanjutnya',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),

                      // Last Page Button
                      IconButton(
                        icon: const Icon(Icons.last_page_rounded, size: 18),
                        onPressed: _currentPage < totalPages
                            ? () => setState(() => _currentPage = totalPages)
                            : null,
                        tooltip: 'Halaman Terakhir',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text('Rank 1',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ],
        ),
      );
    } else if (rank == 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF94A3B8), Color(0xFF64748B)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('Rank 2',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      );
    } else if (rank == 3) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFB45309), Color(0xFF78350F)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('Rank 3',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      );
    }

    return Text('#$rank',
        style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF475569)));
  }

  // --------------------------------------------------------------------------
  // TAB 2: CLASS PERFORMANCE ANALYTICS
  // --------------------------------------------------------------------------
  Widget _buildClassAnalyticsTab({
    required Map<String, List<_StudentReportData>> classGrouped,
    required List<String> sortedSubjects,
    required bool isDesktop,
  }) {
    if (classGrouped.isEmpty) {
      return const Center(child: Text('Belum ada data kelas.'));
    }

    return Padding(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 400,
          mainAxisExtent: isDesktop ? 220 : 190,
          crossAxisSpacing: isDesktop ? 20 : 12,
          mainAxisSpacing: isDesktop ? 20 : 12,
        ),
        itemCount: classGrouped.keys.length,
        itemBuilder: (context, index) {
          final className = classGrouped.keys.elementAt(index);
          final students = classGrouped[className]!;
          final totalClsStudents = students.length;
          final submittedClsStudents =
              students.where((s) => s.hasDoneAny).toList();

          final clsAvg = submittedClsStudents.isNotEmpty
              ? submittedClsStudents.fold<double>(
                      0.0, (acc, s) => acc + s.averageScore) /
                  submittedClsStudents.length
              : 0.0;

          final passedCount =
              submittedClsStudents.where((s) => s.isPassed).length;
          final passPercentage = submittedClsStudents.isNotEmpty
              ? (passedCount / submittedClsStudents.length) * 100
              : 0.0;

          final topClassStudent =
              students.isNotEmpty ? students.first : null;

          return Container(
            padding: EdgeInsets.all(isDesktop ? 18 : 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x05000000),
                    blurRadius: 6,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Kelas: $className',
                      style: GoogleFonts.inter(
                        fontSize: isDesktop ? 16 : 14.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$totalClsStudents Siswa',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rata-Rata Kelas',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: const Color(0xFF64748B))),
                          Text(
                            clsAvg.toStringAsFixed(1),
                            style: GoogleFonts.inter(
                              fontSize: isDesktop ? 22 : 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ketuntasan Kelas',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: const Color(0xFF64748B))),
                          Text(
                            '${passPercentage.toStringAsFixed(0)}%',
                            style: GoogleFonts.inter(
                              fontSize: isDesktop ? 22 : 18,
                              fontWeight: FontWeight.bold,
                              color: passPercentage >= 75
                                  ? const Color(0xFF166534)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Divider(height: 12),
                Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined,
                        size: 16, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        topClassStudent != null
                            ? 'Juara 1: ${topClassStudent.name} (${topClassStudent.averageScore.toStringAsFixed(1)})'
                            : 'Belum ada data',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF334155),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 3: SUBJECT PERFORMANCE ANALYTICS
  // --------------------------------------------------------------------------
  Widget _buildSubjectAnalyticsTab({
    required List<_StudentReportData> processedStudents,
    required List<String> sortedSubjects,
    required bool isDesktop,
  }) {
    if (sortedSubjects.isEmpty) {
      return const Center(child: Text('Belum ada mata pelajaran pada event ini.'));
    }

    return Padding(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
      child: ListView.separated(
        itemCount: sortedSubjects.length,
        separatorBuilder: (_, __) => SizedBox(height: isDesktop ? 14 : 10),
        itemBuilder: (context, index) {
          final subj = sortedSubjects[index];

          final scores = processedStudents
              .map((s) => s.subjectScores[subj])
              .whereType<double>()
              .toList();

          final count = scores.length;
          final positiveScores = scores.where((s) => s > 0).toList();

          final double subjAvg = positiveScores.isNotEmpty
              ? (positiveScores.fold(0.0, (acc, b) => acc + b) / positiveScores.length)
              : (count > 0 ? (scores.fold(0.0, (acc, b) => acc + b) / count) : 0.0);

          final double maxScore =
              count > 0 ? scores.reduce((a, b) => a > b ? a : b) : 0.0;

          final double minScore = positiveScores.isNotEmpty
              ? positiveScores.reduce((a, b) => a < b ? a : b)
              : (count > 0 ? scores.reduce((a, b) => a < b ? a : b) : 0.0);

          final passedCount = scores.where((sc) => sc >= _kkmScore).length;
          final double passPercent =
              count > 0 ? (passedCount / count) * 100 : 0.0;

          return Container(
            padding: EdgeInsets.all(isDesktop ? 18 : 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: isDesktop
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.menu_book_rounded,
                            color: Color(0xFF16A34A), size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subj,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$count Terkumpul | Ketuntasan: ${passPercent.toStringAsFixed(0)}%',
                              style: GoogleFonts.inter(
                                  fontSize: 12.5, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      _buildStatMetricBox('Rata-Rata', subjAvg.toStringAsFixed(1),
                          const Color(0xFF4F46E5)),
                      const SizedBox(width: 16),
                      _buildStatMetricBox('Tertinggi', maxScore.toStringAsFixed(1),
                          const Color(0xFF16A34A)),
                      const SizedBox(width: 16),
                      _buildStatMetricBox('Terendah', minScore.toStringAsFixed(1),
                          const Color(0xFFDC2626)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.menu_book_rounded,
                                color: Color(0xFF16A34A), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subj,
                                  style: GoogleFonts.inter(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '$count Terkumpul | Ketuntasan: ${passPercent.toStringAsFixed(0)}%',
                                  style: GoogleFonts.inter(
                                      fontSize: 11.5, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatMetricBox('Rata-Rata', subjAvg.toStringAsFixed(1),
                              const Color(0xFF4F46E5)),
                          _buildStatMetricBox('Tertinggi', maxScore.toStringAsFixed(1),
                              const Color(0xFF16A34A)),
                          _buildStatMetricBox('Terendah', minScore.toStringAsFixed(1),
                              const Color(0xFFDC2626)),
                        ],
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildStatMetricBox(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // TAB 4: SCORE DISTRIBUTION TAB
  // --------------------------------------------------------------------------
  Widget _buildScoreDistributionTab({
    required List<_StudentReportData> processedStudents,
    required bool isDesktop,
  }) {
    final activeStudents =
        processedStudents.where((s) => s.hasDoneAny).toList();
    final total = activeStudents.length;

    final excellent =
        activeStudents.where((s) => s.averageScore >= 90).length;
    final good = activeStudents
        .where((s) => s.averageScore >= 75 && s.averageScore < 90)
        .length;
    final fair = activeStudents
        .where((s) => s.averageScore >= 60 && s.averageScore < 75)
        .length;
    final poor = activeStudents.where((s) => s.averageScore < 60).length;

    return Padding(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sebaran Rentang Nilai Rata-Rata Siswa',
            style: GoogleFonts.inter(
              fontSize: isDesktop ? 17 : 15,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Berdasarkan $total siswa yang telah menyelesaikan minimal 1 ujian.',
            style: GoogleFonts.inter(fontSize: isDesktop ? 13 : 12, color: const Color(0xFF64748B)),
          ),
          SizedBox(height: isDesktop ? 24 : 16),
          _buildDistributionBar('Sangat Baik (90 - 100)', excellent, total,
              const Color(0xFF10B981)),
          const SizedBox(height: 16),
          _buildDistributionBar(
              'Baik (75 - 89)', good, total, const Color(0xFF3B82F6)),
          const SizedBox(height: 16),
          _buildDistributionBar(
              'Cukup (60 - 74)', fair, total, const Color(0xFFF59E0B)),
          const SizedBox(height: 16),
          _buildDistributionBar('Perlu Remedial (< 60)', poor, total,
              const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _buildDistributionBar(
      String label, int count, int total, Color color) {
    final double pct = total > 0 ? (count / total) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF334155))),
            Text('$count Siswa (${(pct * 100).toStringAsFixed(1)}%)',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 14,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // EXPORT EXCEL / CSV LOGIC
  // --------------------------------------------------------------------------
  Future<void> _exportCsvLeger({
    required String eventTitle,
    required List<_StudentReportData> processedStudents,
    required List<String> sortedSubjects,
  }) async {
    setState(() => _isExportingCsv = true);
    try {
      final List<List<dynamic>> rows = [];

      // Header Row
      List<dynamic> header = [
        'Rank Global',
        'Rank Kelas',
        'NISN',
        'Nama Siswa',
        'Kelas',
      ];
      for (var subj in sortedSubjects) {
        header.add(subj);
      }
      header.addAll(['Total Nilai', 'Rata-Rata', 'Status Ketuntasan']);
      rows.add(header);

      // Data Rows
      for (var st in processedStudents) {
        List<dynamic> row = [
          st.globalRank,
          st.classRank,
          st.nis,
          st.name,
          st.className,
        ];
        for (var subj in sortedSubjects) {
          final sc = st.subjectScores[subj];
          row.add(sc != null ? sc.toStringAsFixed(1) : '-');
        }
        row.add(st.totalScore.toStringAsFixed(1));
        row.add(st.averageScore.toStringAsFixed(1));
        row.add(!st.hasDoneAny
            ? 'Belum Ujian'
            : (st.isPassed ? 'TUNTAS' : 'REMEDIAL'));
        rows.add(row);
      }

      // Convert to CSV
      final String csvData = rows.map((r) => r.join(',')).join('\n');
      final bytes = utf8.encode(csvData);
      final fileName =
          'Leger_Nilai_${eventTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';

      await saveAndDownloadFile(bytes, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil mengekspor Leger Nilai ke file $fileName'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor CSV: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
    }
  }

  // --------------------------------------------------------------------------
  // EXPORT PDF LEGER LOGIC
  // --------------------------------------------------------------------------
  Future<void> _exportPdfLeger({
    required String eventTitle,
    required List<_StudentReportData> processedStudents,
    required List<String> sortedSubjects,
  }) async {
    setState(() => _isGeneratingPdf = true);
    try {
      final pdf = pw.Document();

      // Fetch School Info
      final schoolSnap = await _firestore
          .collection('schools')
          .doc(widget.schoolId)
          .get();
      final schoolData = schoolSnap.data() ?? {};
      final String schoolName =
          (schoolData['name'] ?? schoolData['nama'] ?? 'SEKOLAH').toString();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return [
              // Header Kop
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      schoolName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'LEGER REKAPITULASI NILAI & RANKING SISWA',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Event Ujian: $eventTitle | Tanggal Cetak: ${DateFormat('dd MMMM yyyy', 'id_ID').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Divider(thickness: 1.5),
                    pw.SizedBox(height: 12),
                  ],
                ),
              ),

              // Table
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                headerStyle: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                headers: [
                  'Rank',
                  'NISN',
                  'Nama Siswa',
                  'Kelas',
                  ...sortedSubjects,
                  'Total',
                  'Rata-Rata',
                  'Status',
                ],
                data: processedStudents.map((st) {
                  return [
                    '#${st.globalRank}',
                    st.nis,
                    st.name,
                    st.className,
                    ...sortedSubjects.map((s) {
                      final sc = st.subjectScores[s];
                      return sc != null ? sc.toStringAsFixed(1) : '-';
                    }),
                    st.totalScore.toStringAsFixed(1),
                    st.averageScore.toStringAsFixed(1),
                    !st.hasDoneAny
                        ? 'Belum'
                        : (st.isPassed ? 'TUNTAS' : 'REMEDIAL'),
                  ];
                }).toList(),
              ),

              pw.SizedBox(height: 24),
              // Signatures Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Mengetahui,', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Kepala Sekolah', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 40),
                      pw.Text('( ______________________ )', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Ketua Panitia Ujian,', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 50),
                      pw.Text('( ______________________ )', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final pdfBytes = await pdf.save();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Leger_Nilai_${eventTitle.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat PDF Leger: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }
}

// Data Model Helper
class _StudentReportData {
  final String id;
  final String nis;
  final String name;
  final String className;
  final Map<String, double?> subjectScores;
  final double totalScore;
  final double averageScore;
  final int completedCount;
  final bool isPassed;
  final bool hasDoneAny;

  int globalRank = 0;
  int classRank = 0;

  _StudentReportData({
    required this.id,
    required this.nis,
    required this.name,
    required this.className,
    required this.subjectScores,
    required this.totalScore,
    required this.averageScore,
    required this.completedCount,
    required this.isPassed,
    required this.hasDoneAny,
  });
}
