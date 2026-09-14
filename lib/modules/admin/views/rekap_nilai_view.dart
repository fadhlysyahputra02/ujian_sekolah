import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/natural_sort.dart';

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

  // Selected Event (null = show Event List screen first)
  DocumentSnapshot? _selectedEventDoc;
  String _eventSearchQuery = '';

  // Detail View Filters
  String _selectedSubject = 'ALL';
  String _selectedAngkatan = 'ALL';
  String _selectedClass = 'ALL';
  String _selectedStatus = 'ALL'; // ALL, UNFILLED, FILLED, GRADED
  String _searchQuery = '';

  // Pagination Controls (Default 50, customizable: 30, 50, 80, 100)
  int _currentPage = 1;
  int _pageSize = 50;

  bool _hasInitializedDefaultClass = false;
  bool _hasCheckedUrlEvent = false;

  // Sent grades dispatched to this teacher (if isTeacher)
  final Set<String> _sentSubjectIds = {};
  final Set<String> _sentSubjectNames = {};

  bool _isSendingGrade = false;

  Stream<QuerySnapshot>? _eventsStream;
  Stream<QuerySnapshot>? _sentGradesStream;
  Stream<QuerySnapshot>? _classesStream;
  Stream<QuerySnapshot>? _studentsStream;
  Stream<QuerySnapshot>? _submissionsStream;
  String? _cachedSubmissionsEventId;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    _eventsStream ??= _firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('events')
        .snapshots();

    _sentGradesStream ??= _firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('sentGrades')
        .snapshots();

    _classesStream ??= _firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('classes')
        .snapshots();

    _studentsStream ??= _firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('students')
        .where('archived', isEqualTo: false)
        .snapshots();
  }

  Stream<QuerySnapshot>? _getSubmissionsStream(DocumentSnapshot? eventDoc) {
    if (eventDoc == null) return null;
    if (_cachedSubmissionsEventId != eventDoc.id || _submissionsStream == null) {
      _cachedSubmissionsEventId = eventDoc.id;
      _submissionsStream = eventDoc.reference.collection('submissions').snapshots();
    }
    return _submissionsStream;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasCheckedUrlEvent) {
      _hasCheckedUrlEvent = true;
      _checkUrlForEventId();
    }
  }

  Future<void> _checkUrlForEventId() async {
    try {
      final uri = GoRouterState.of(context).uri;
      final eventId = uri.queryParameters['eventId'];
      if (eventId != null && eventId.isNotEmpty && _selectedEventDoc == null) {
        final docSnap = await _firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('events')
            .doc(eventId)
            .get();

        if (docSnap.exists && mounted) {
          setState(() {
            _selectedEventDoc = docSnap;
            _hasInitializedDefaultClass = false;
            _selectedClass = 'ALL';
            _selectedSubject = 'ALL';
            _selectedAngkatan = 'ALL';
            _selectedStatus = 'ALL';
            _searchQuery = '';
            _currentPage = 1;
          });
        }
      }
    } catch (_) {}
  }

  void _openEventRekap(DocumentSnapshot eDoc) {
    final eData = eDoc.data() as Map<String, dynamic>;
    final title = (eData['title'] ?? eData['eventName'] ?? eData['name'] ?? 'Event').toString();

    setState(() {
      _selectedEventDoc = eDoc;
      _hasInitializedDefaultClass = false;
      _selectedClass = 'ALL';
      _selectedSubject = 'ALL';
      _selectedAngkatan = 'ALL';
      _selectedStatus = 'ALL';
      _searchQuery = '';
      _currentPage = 1;
    });

    try {
      final currentLoc = GoRouterState.of(context).matchedLocation;
      context.go('$currentLoc?eventId=${eDoc.id}&eventName=${Uri.encodeComponent(title)}');
    } catch (_) {}
  }

  void _closeEventRekap() {
    setState(() {
      _selectedEventDoc = null;
    });

    try {
      final currentLoc = GoRouterState.of(context).matchedLocation;
      context.go(currentLoc);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _selectedEventDoc == null
            ? _buildEventSelectionScreen()
            : _buildEventDetailRekapScreen(),
      ),
    );
  }

  // ==========================================
  // LEVEL 1: DAFTAR EVENT UJIAN (REKAP NILAI THEME)
  // ==========================================
  Widget _buildEventSelectionScreen() {
    final dateFormat = DateFormat('dd MMM yyyy');
    final isDesktop = MediaQuery.of(context).size.width > 750;

    return Column(
      key: const ValueKey('EventListScreen'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Header Banner Card (Unique Rekap Nilai Teal/Emerald Analytics Theme)
        Container(
          padding: EdgeInsets.all(isDesktop ? 20 : 16),
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
          child: isDesktop
              ? Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9488), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rekapitulasi Nilai Murid',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Pilih event ujian di bawah untuk menganalisis & merekapitulasi nilai hasil ujian siswa.',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        onChanged: (val) => setState(() => _eventSearchQuery = val),
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Cari event ujian...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0D9488), Color(0xFF059669)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rekapitulasi Nilai Murid',
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'Pilih event ujian untuk melihat rekap nilai.',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (val) => setState(() => _eventSearchQuery = val),
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Cari event ujian...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 20),

        // Stream Events List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _eventsStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF0D9488)));
              }

              final eventDocs = snapshot.data?.docs ?? [];
              final filteredEvents = eventDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = (data['title'] ?? data['eventName'] ?? data['name'] ?? '').toString().toLowerCase();
                return _eventSearchQuery.isEmpty || title.contains(_eventSearchQuery.toLowerCase());
              }).toList();

              if (filteredEvents.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_busy_rounded, size: 48, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada Event Ujian yang ditemukan.',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Silakan pilih atau buat event ujian di menu Event Ujian terlebih dahulu.',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: filteredEvents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final eDoc = filteredEvents[index];
                  final eData = eDoc.data() as Map<String, dynamic>;
                  final title = (eData['title'] ?? eData['eventName'] ?? eData['name'] ?? 'Event Ujian').toString();
                  final status = (eData['status'] ?? 'draft').toString();
                  final academicYear = (eData['academicYear'] ?? eData['tahunAjaran'] ?? '-').toString();

                  DateTime? start;
                  DateTime? end;
                  if (eData['startDate'] != null) {
                    final sd = eData['startDate'];
                    start = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
                  }
                  if (eData['endDate'] != null) {
                    final ed = eData['endDate'];
                    end = ed is Timestamp ? ed.toDate() : (ed is String ? DateTime.tryParse(ed) : null);
                  }

                  final dateRangeStr = (start != null && end != null)
                      ? '${dateFormat.format(start)} - ${dateFormat.format(end)}'
                      : (start != null ? dateFormat.format(start) : '-');

                  String statusLabel = 'Draft Admin';
                  Color statusBg = const Color(0xFFFEF3C7);
                  Color statusText = const Color(0xFFD97706);

                  final lowerStatus = status.toLowerCase();
                  if (lowerStatus == 'published' || lowerStatus == 'active' || lowerStatus == 'aktif') {
                    statusLabel = 'Aktif / Published';
                    statusBg = const Color(0xFFCCFBF1);
                    statusText = const Color(0xFF0F766E);
                  } else if (lowerStatus == 'closed' || lowerStatus == 'completed' || lowerStatus == 'selesai') {
                    statusLabel = 'Selesai / Closed';
                    statusBg = const Color(0xFFF1F5F9);
                    statusText = const Color(0xFF64748B);
                  }

                  return Container(
                    padding: EdgeInsets.all(isDesktop ? 20 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: isDesktop
                        ? Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFDCFCE7)),
                                ),
                                child: const Icon(
                                  Icons.bar_chart_rounded,
                                  color: Color(0xFF0D9488),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF64748B)),
                                            const SizedBox(width: 5),
                                            Text(
                                              dateRangeStr,
                                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 16),
                                        Row(
                                          children: [
                                            const Icon(Icons.school_outlined, size: 13, color: Color(0xFF64748B)),
                                            const SizedBox(width: 5),
                                            Text(
                                              'T.A $academicYear',
                                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 16),
                                        FutureBuilder<AggregateQuerySnapshot>(
                                          future: eDoc.reference.collection('submissions').count().get(),
                                          builder: (context, subSnap) {
                                            final subCount = subSnap.data?.count ?? 0;
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFDCFCE7),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.people_outline_rounded, size: 12, color: Color(0xFF15803D)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '$subCount Lembar Dijawab',
                                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                              const SizedBox(width: 14),
                              ElevatedButton.icon(
                                onPressed: () => _openEventRekap(eDoc),
                                icon: const Icon(Icons.bar_chart_rounded, size: 16),
                                label: Text(
                                  'Lihat Rekap Nilai',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFDCFCE7)),
                                    ),
                                    child: const Icon(Icons.bar_chart_rounded, color: Color(0xFF0D9488), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                                    child: Text(statusLabel, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusText)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 6,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF64748B)),
                                      const SizedBox(width: 4),
                                      Text(dateRangeStr, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.school_outlined, size: 12, color: Color(0xFF64748B)),
                                      const SizedBox(width: 4),
                                      Text('T.A $academicYear', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                    ],
                                  ),
                                  FutureBuilder<AggregateQuerySnapshot>(
                                    future: eDoc.reference.collection('submissions').count().get(),
                                    builder: (context, subSnap) {
                                      final subCount = subSnap.data?.count ?? 0;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                                        child: Text('$subCount Lembar Dijawab', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF15803D))),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _openEventRekap(eDoc),
                                  icon: const Icon(Icons.bar_chart_rounded, size: 16),
                                  label: Text('Lihat Rekap Nilai', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0D9488),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // LEVEL 2: DETAIL REKAP NILAI PER EVENT
  // ==========================================
  Widget _buildEventDetailRekapScreen() {
    final eData = _selectedEventDoc!.data() as Map<String, dynamic>;
    final eventTitle = (eData['title'] ?? eData['eventName'] ?? eData['name'] ?? 'Event Ujian').toString();

    return Column(
      key: const ValueKey('EventDetailRekapScreen'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Navigation Header Bar
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _closeEventRekap,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text('Daftar Event', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Rekap Nilai:',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          eventTitle,
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!widget.isTeacher)
              ElevatedButton.icon(
                onPressed: _showDispatchGradeModal,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  'Kirim Nilai ke Guru',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),

        // Streams: SentGrades -> Students -> Selected Event Submissions
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _sentGradesStream,
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
                stream: _classesStream,
                builder: (context, classSnap) {
                  final classDocs = classSnap.data?.docs ?? [];

                  return StreamBuilder<QuerySnapshot>(
                    stream: _studentsStream,
                    builder: (context, studentSnap) {
                      if (!studentSnap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
                      }

                      final studentDocs = studentSnap.data?.docs ?? [];

                      // Direct Stream for Selected Event Submissions
                      return StreamBuilder<QuerySnapshot>(
                        stream: _getSubmissionsStream(_selectedEventDoc),
                        builder: (context, subSnap) {
                          if (!subSnap.hasData) {
                            return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
                          }

                          final submissionDocs = subSnap.data?.docs ?? [];
                          final submissions = submissionDocs.map((d) {
                            final data = d.data() as Map<String, dynamic>;
                            data['eventId'] = _selectedEventDoc!.id;
                            data['subDocId'] = d.id;
                            return data;
                          }).toList();

                          return _buildMainContent(classDocs, studentDocs, submissions);
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent(
    List<QueryDocumentSnapshot> classDocs,
    List<QueryDocumentSnapshot> studentDocs,
    List<Map<String, dynamic>> submissions,
  ) {
    // Map submissions by studentId_subjectName / nis_subjectName / name_subjectName
    final Map<String, Map<String, dynamic>> studentSubmissionMap = {};
    final Set<String> allSubjects = {};
    final Set<String> allClassesSet = {};
    final Set<String> allAngkatan = {};

    // Build class lookup map from master classes collection
    final Map<String, String> classMapFromClasses = {};
    final Map<String, String> classIdToNameMap = {};

    for (var cDoc in classDocs) {
      final cData = cDoc.data() as Map<String, dynamic>;
      final cName = (cData['name'] ?? cData['className'] ?? cData['nama'] ?? '').toString().trim();
      if (cName.isNotEmpty) {
        allClassesSet.add(cName);
        classIdToNameMap[cDoc.id] = cName;

        // 1. studentIds (List of IDs/NIS/UIDs)
        if (cData['studentIds'] is List) {
          for (var id in cData['studentIds']) {
            final cleanId = id.toString().trim();
            if (cleanId.isNotEmpty) {
              classMapFromClasses[cleanId] = cName;
              classMapFromClasses[cleanId.toLowerCase()] = cName;
            }
          }
        }

        // 2. students (List of Maps or Strings)
        if (cData['students'] is List) {
          for (var st in cData['students']) {
            if (st is Map) {
              final id = (st['id'] ?? st['studentId'] ?? st['nis'] ?? st['uid'] ?? '').toString().trim();
              if (id.isNotEmpty) {
                classMapFromClasses[id] = cName;
                classMapFromClasses[id.toLowerCase()] = cName;
              }
            } else if (st is String) {
              final cleanId = st.trim();
              if (cleanId.isNotEmpty) {
                classMapFromClasses[cleanId] = cName;
                classMapFromClasses[cleanId.toLowerCase()] = cName;
              }
            }
          }
        }
      }
    }

    for (var sub in submissions) {
      final studentId = (sub['studentId'] ?? sub['nis'] ?? sub['studentName'] ?? '').toString().trim();
      final sName = (sub['subjectName'] ?? sub['subjectId'] ?? '').toString().trim();
      final rawCls = (sub['className'] ?? sub['studentClass'] ?? sub['classId'] ?? '').toString().trim();
      final cls = classIdToNameMap[rawCls] ?? rawCls;
      if (studentId.isNotEmpty && sName.isNotEmpty) {
        studentSubmissionMap['${studentId}_$sName'] = sub;
      }
      if (sName.isNotEmpty) allSubjects.add(sName);
      if (cls.isNotEmpty && cls.toLowerCase() != 'tanpa kelas') allClassesSet.add(cls);
    }

    for (var sDoc in studentDocs) {
      final sData = sDoc.data() as Map<String, dynamic>;
      final angk = (sData['angkatan'] ?? '').toString().trim();
      final rawCls = (sData['className'] ?? sData['kelas'] ?? sData['classId'] ?? sData['studentClass'] ?? '').toString().trim();
      final cls = classIdToNameMap[rawCls] ?? rawCls;
      if (angk.isNotEmpty) allAngkatan.add(angk);
      if (cls.isNotEmpty && cls.toLowerCase() != 'tanpa kelas') allClassesSet.add(cls);
    }

    final sortedClasses = allClassesSet.toList()..sort();
    final sortedAngkatan = allAngkatan.toList()..sort();

    // Default selected class to ALL initially
    if (!_hasInitializedDefaultClass) {
      _selectedClass = 'ALL';
      _hasInitializedDefaultClass = true;
    }

    // Filter subject options for teachers if needed
    List<String> subjectDropdownOptions = allSubjects.toList()..sort();
    if (widget.isTeacher) {
      subjectDropdownOptions = subjectDropdownOptions.where((sName) {
        final cleanSName = sName.toLowerCase().trim();
        final isAssigned = widget.teacherSubjects.any((ts) => ts.toLowerCase().trim() == cleanSName);
        final isDispatched = _sentSubjectNames.contains(cleanSName);
        return isAssigned || isDispatched;
      }).toList();
    }

    // Group filtered students & collect matching docs
    final List<QueryDocumentSnapshot> matchingStudentDocs = [];
    final Map<String, String> studentEffectiveClassMap = {};

    int totalFilteredStudents = 0;
    int gradedCount = 0;
    int filledCount = 0;
    int unfilledCount = 0;
    double totalScoreSum = 0;
    int totalGradedScoresCount = 0;

    for (var sDoc in studentDocs) {
      final sData = sDoc.data() as Map<String, dynamic>;
      final sId = sDoc.id;
      final name = (sData['displayName'] ?? sData['name'] ?? '').toString().trim();
      final nis = (sData['nis'] ?? sData['username'] ?? '').toString().trim();
      final uid = (sData['uid'] ?? sData['userId'] ?? '').toString().trim();
      final angk = (sData['angkatan'] ?? 'Tanpa Angkatan').toString().trim();

      // Find any submission for this student to resolve class if profile class is missing
      Map<String, dynamic>? firstSubMatch;
      for (var subj in allSubjects) {
        final match = studentSubmissionMap['${sId}_$subj'] ??
            studentSubmissionMap['${nis}_$subj'] ??
            studentSubmissionMap['${name}_$subj'];
        if (match != null) {
          firstSubMatch = match;
          break;
        }
      }

      final docClassRaw = (sData['className'] ?? sData['kelas'] ?? sData['classId'] ?? sData['studentClass'] ?? sData['namaKelas'] ?? '').toString().trim();
      final docClass = classIdToNameMap[docClassRaw] ?? docClassRaw;

      final subClassRaw = (firstSubMatch?['className'] ?? firstSubMatch?['studentClass'] ?? firstSubMatch?['classId'] ?? '').toString().trim();
      final subClass = classIdToNameMap[subClassRaw] ?? subClassRaw;

      final classFromClassesColl = classMapFromClasses[sId] ??
          classMapFromClasses[sId.toLowerCase()] ??
          (nis.isNotEmpty ? (classMapFromClasses[nis] ?? classMapFromClasses[nis.toLowerCase()]) : null) ??
          (uid.isNotEmpty ? (classMapFromClasses[uid] ?? classMapFromClasses[uid.toLowerCase()]) : null);

      final effectiveClass = classFromClassesColl != null && classFromClassesColl.isNotEmpty && classFromClassesColl.toLowerCase() != 'tanpa kelas'
          ? classFromClassesColl
          : (subClass.isNotEmpty && subClass.toLowerCase() != 'tanpa kelas'
              ? subClass
              : (docClass.isNotEmpty && docClass.toLowerCase() != 'tanpa kelas'
                  ? docClass
                  : 'Tanpa Kelas'));

      studentEffectiveClassMap[sId] = effectiveClass;

      // Search Query Filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!name.toLowerCase().contains(q) && !nis.toLowerCase().contains(q)) {
          continue;
        }
      }

      // Angkatan Filter
      if (_selectedAngkatan != 'ALL' && angk != _selectedAngkatan) continue;

      // Robust Flexible Class Filter
      if (_selectedClass != 'ALL') {
        final cleanSel = _selectedClass.toLowerCase().trim();
        final cleanEff = effectiveClass.toLowerCase().trim();
        final cleanDoc = docClass.toLowerCase().trim();
        final cleanSub = subClass.toLowerCase().trim();
        final cleanName = name.toLowerCase().trim();

        final matchesClass = cleanEff == cleanSel ||
            cleanDoc == cleanSel ||
            cleanSub == cleanSel ||
            cleanEff.replaceAll('kelas', '').trim() == cleanSel.replaceAll('kelas', '').trim() ||
            cleanSel.contains(cleanEff) ||
            cleanEff.contains(cleanSel) ||
            cleanName.contains(cleanSel);

        if (!matchesClass) continue;
      }

      List<String> targetSubjects = subjectDropdownOptions;
      if (_selectedSubject != 'ALL') {
        targetSubjects = [_selectedSubject];
      }

      // Status Filter Check & Metric Calculations
      bool matchesStatusFilter = false;
      for (var subj in targetSubjects) {
        final subData = studentSubmissionMap['${sId}_$subj'] ??
            studentSubmissionMap['${nis}_$subj'] ??
            studentSubmissionMap['${name}_$subj'];

        final isSubmitted = subData != null;
        final isGraded = subData?['isGraded'] == true;

        String statusKey = 'UNFILLED';
        if (isGraded) {
          statusKey = 'GRADED';
        } else if (isSubmitted) {
          statusKey = 'FILLED';
        }

        if (_selectedStatus == 'ALL' || statusKey == _selectedStatus) {
          matchesStatusFilter = true;
        }

        if (isGraded) {
          gradedCount++;
          final score = (subData?['score'] as num?)?.toDouble() ?? 0.0;
          totalScoreSum += score;
          totalGradedScoresCount++;
        } else if (isSubmitted) {
          filledCount++;
        } else {
          unfilledCount++;
        }
      }

      if (!matchesStatusFilter) continue;

      matchingStudentDocs.add(sDoc);
      totalFilteredStudents++;
    }

    // Sort matching student docs alphabetically (Aa-Zz) by student name
    matchingStudentDocs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;

      final aName = (aData['displayName'] ?? aData['name'] ?? aData['fullName'] ?? aData['nis'] ?? '').toString().trim();
      final bName = (bData['displayName'] ?? bData['name'] ?? bData['fullName'] ?? bData['nis'] ?? '').toString().trim();

      return naturalCompare(aName, bName);
    });

    // PAGINATION LOGIC (Configurable: 30, 50, 80, 100 per page)
    final int totalItems = matchingStudentDocs.length;
    final int totalPages = totalItems > 0 ? (totalItems / _pageSize).ceil() : 1;
    if (_currentPage > totalPages) _currentPage = totalPages;
    if (_currentPage < 1) _currentPage = 1;

    final int startIndex = totalItems > 0 ? (_currentPage - 1) * _pageSize : 0;
    final int endIndex = (startIndex + _pageSize).clamp(0, totalItems);
    final pagedStudentDocs = totalItems > 0 ? matchingStudentDocs.sublist(startIndex, endIndex) : <QueryDocumentSnapshot>[];

    final double averageScore = totalGradedScoresCount > 0 ? (totalScoreSum / totalGradedScoresCount) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. STATS METRIC CARDS
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Total Murid',
                value: '$totalFilteredStudents',
                subtitle: _selectedClass != 'ALL' ? 'Murid di Kelas $_selectedClass' : 'Seluruh Murid Terfilter',
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF2563EB),
                bgColor: const Color(0xFFEFF6FF),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Sudah Dikoreksi',
                value: '$gradedCount',
                subtitle: 'Nilai ujian terverifikasi',
                icon: Icons.task_alt_rounded,
                color: const Color(0xFF059669),
                bgColor: const Color(0xFFECFDF5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Sudah Diisi / Belum',
                value: '$filledCount / $unfilledCount',
                subtitle: 'Belum dikoreksi / belum diisi',
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFD97706),
                bgColor: const Color(0xFFFEF3C7),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Rata-Rata Nilai',
                value: totalGradedScoresCount > 0 ? averageScore.toStringAsFixed(1) : '-',
                subtitle: 'Dari $totalGradedScoresCount data terperiksa',
                icon: Icons.analytics_outlined,
                color: const Color(0xFF7C3AED),
                bgColor: const Color(0xFFF3E8FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // 2. ADVANCED FILTER TOOLBAR
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search Input
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (val) => setState(() {
                    _searchQuery = val;
                    _currentPage = 1;
                  }),
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Cari nama murid / NIS...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                    ),
                  ),
                ),
              ),

              // Subject Dropdown Filter
              _buildFilterDropdown(
                icon: Icons.menu_book_rounded,
                label: 'Mata Pelajaran',
                value: subjectDropdownOptions.contains(_selectedSubject) ? _selectedSubject : 'ALL',
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('Semua Mata Pelajaran')),
                  ...subjectDropdownOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) => setState(() {
                  _selectedSubject = val ?? 'ALL';
                  _currentPage = 1;
                }),
              ),

              // Kelas Dropdown Filter
              _buildFilterDropdown(
                icon: Icons.class_rounded,
                label: 'Kelas',
                value: (sortedClasses.contains(_selectedClass) || _selectedClass == 'ALL') ? _selectedClass : 'ALL',
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('Semua Kelas')),
                  ...sortedClasses.map((c) => DropdownMenuItem(value: c, child: Text('Kelas $c'))),
                ],
                onChanged: (val) => setState(() {
                  _selectedClass = val ?? 'ALL';
                  _currentPage = 1;
                }),
              ),

              // Angkatan Dropdown Filter
              _buildFilterDropdown(
                icon: Icons.school_rounded,
                label: 'Angkatan',
                value: _selectedAngkatan,
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('Semua Angkatan')),
                  ...sortedAngkatan.map((a) => DropdownMenuItem(value: a, child: Text('Angkatan $a'))),
                ],
                onChanged: (val) => setState(() {
                  _selectedAngkatan = val ?? 'ALL';
                  _currentPage = 1;
                }),
              ),

              // Status Dropdown Filter
              _buildFilterDropdown(
                icon: Icons.filter_alt_rounded,
                label: 'Status Nilai',
                value: _selectedStatus,
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('Semua Status Nilai')),
                  DropdownMenuItem(value: 'GRADED', child: Text('Sudah Dikoreksi')),
                  DropdownMenuItem(value: 'FILLED', child: Text('Sudah Diisi')),
                  DropdownMenuItem(value: 'UNFILLED', child: Text('Belum Diisi')),
                ],
                onChanged: (val) => setState(() {
                  _selectedStatus = val ?? 'ALL';
                  _currentPage = 1;
                }),
              ),

              if (_selectedSubject != 'ALL' || _selectedAngkatan != 'ALL' || _selectedClass != 'ALL' || _selectedStatus != 'ALL' || _searchQuery.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedSubject = 'ALL';
                      _selectedAngkatan = 'ALL';
                      _selectedClass = 'ALL';
                      _selectedStatus = 'ALL';
                      _searchQuery = '';
                      _currentPage = 1;
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFEF4444)),
                  label: Text(
                    'Reset Filter',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. SINGLE UNIFIED DATA TABLE LIST (PAGINATED WITH SIZE SELECTOR)
        Expanded(
          child: pagedStudentDocs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.assignment_late_outlined, size: 40, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Tidak ada data murid yang sesuai dengan filter kelas/kategori ini.',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Coba ganti filter kelas atau pencarian nama murid di atas.',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Table Header Bar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFA7F3D0)),
                                  ),
                                  child: const Icon(Icons.table_chart_rounded, color: Color(0xFF059669), size: 18),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Tabel Rekapitulasi Nilai Siswa',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: Text(
                                    '$totalFilteredStudents Murid Terfilter',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Single Unified DataTable
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                  child: DataTable(
                                    headingRowHeight: 44,
                                    dataRowMaxHeight: 52,
                                    columnSpacing: 16,
                                    horizontalMargin: 16,
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFFAFAFA)),
                                    columns: [
                                      DataColumn(label: Text('NIS', style: _headerTextStyle)),
                                      DataColumn(label: Text('Nama Murid', style: _headerTextStyle)),
                                      DataColumn(label: Text('Kelas & Angkatan', style: _headerTextStyle)),
                                      DataColumn(label: Text('Mata Pelajaran', style: _headerTextStyle)),
                                      DataColumn(label: Text('Nilai PG', style: _headerTextStyle)),
                                      DataColumn(label: Text('Nilai Essay', style: _headerTextStyle)),
                                      DataColumn(label: Text('Total Nilai', style: _headerTextStyle)),
                                      DataColumn(label: Text('Status Nilai', style: _headerTextStyle)),
                                      DataColumn(label: Text('Keterangan', style: _headerTextStyle)),
                                    ],
                                    rows: pagedStudentDocs.expand((sDoc) {
                                      final sData = sDoc.data() as Map<String, dynamic>;
                                      final sId = sDoc.id;
                                      final sNis = (sData['nis'] ?? '-').toString();
                                      final sName = (sData['displayName'] ?? sData['name'] ?? '-').toString();
                                      final sAngk = (sData['angkatan'] ?? '-').toString();
                                      final sCls = studentEffectiveClassMap[sId] ?? 'Tanpa Kelas';

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
                                            // NIS
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  sNis,
                                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                                                ),
                                              ),
                                            ),
                                            // Nama Murid
                                            DataCell(
                                              Text(
                                                sName,
                                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                                              ),
                                            ),
                                            // Kelas & Angkatan
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF0FDF4),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFFBBF7D0)),
                                                ),
                                                child: Text(
                                                  'Kelas $sCls ($sAngk)',
                                                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF15803D)),
                                                ),
                                              ),
                                            ),
                                            // Mata Pelajaran
                                            DataCell(
                                              Text(
                                                subj,
                                                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
                                              ),
                                            ),
                                            // Nilai PG
                                            DataCell(
                                              Text(
                                                isSubmitted ? '$pgScore' : '-',
                                                style: GoogleFonts.inter(fontSize: 13, color: isSubmitted ? const Color(0xFF2563EB) : const Color(0xFF94A3B8), fontWeight: isSubmitted ? FontWeight.w600 : FontWeight.normal),
                                              ),
                                            ),
                                            // Nilai Essay
                                            DataCell(
                                              Text(
                                                isSubmitted ? '$essayScore' : '-',
                                                style: GoogleFonts.inter(fontSize: 13, color: isSubmitted ? const Color(0xFF7C3AED) : const Color(0xFF94A3B8), fontWeight: isSubmitted ? FontWeight.w600 : FontWeight.normal),
                                              ),
                                            ),
                                            // Total Nilai
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isGraded ? const Color(0xFFECFDF5) : Colors.transparent,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  isSubmitted ? '$score' : '-',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: isGraded
                                                        ? const Color(0xFF059669)
                                                        : (isSubmitted ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Status Nilai
                                            DataCell(_buildStatusBadge(statusKey)),
                                            // Keterangan
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
                                                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF047857), fontWeight: FontWeight.w500),
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
                                                        'Dikirim oleh Admin',
                                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4338CA)),
                                                      ),
                                                    ),
                                                  ],
                                                  if (!isGraded && !isDispatchedToTeacher)
                                                    Text('-', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }).whereType<DataRow>().toList();
                                    }).toList(),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // PAGINATION CONTROLS BAR (With Page Size Selector 30, 50, 80, 100)
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                totalItems > 0
                                    ? 'Menampilkan ${startIndex + 1} - $endIndex dari $totalItems data murid'
                                    : 'Menampilkan 0 data murid',
                                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _pageSize,
                                    isDense: true,
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF0F172A), fontWeight: FontWeight.w700),
                                    items: const [
                                      DropdownMenuItem(value: 30, child: Text('30 / hal')),
                                      DropdownMenuItem(value: 50, child: Text('50 / hal')),
                                      DropdownMenuItem(value: 80, child: Text('80 / hal')),
                                      DropdownMenuItem(value: 100, child: Text('100 / hal')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _pageSize = val;
                                          _currentPage = 1;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _currentPage > 1
                                    ? () => setState(() => _currentPage--)
                                    : null,
                                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                                label: Text('Sebelumnya', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(color: _currentPage > 1 ? const Color(0xFFCBD5E1) : const Color(0xFFF1F5F9)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Halaman $_currentPage dari $totalPages',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _currentPage < totalPages
                                    ? () => setState(() => _currentPage++)
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                                label: Text('Berikutnya', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(color: _currentPage < totalPages ? const Color(0xFFCBD5E1) : const Color(0xFFF1F5F9)),
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
      ],
    );
  }

  TextStyle get _headerTextStyle => GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF475569),
      );

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
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
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8)),
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

  Widget _buildFilterDropdown({
    required IconData icon,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A), fontWeight: FontWeight.w500),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
              items: items,
              onChanged: onChanged,
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
            const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF059669)),
            const SizedBox(width: 4),
            Text(
              'Sudah Dikoreksi',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF047857)),
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
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF1D4ED8)),
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
          const Icon(Icons.circle_outlined, size: 13, color: Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            'Belum Diisi',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  void _showDispatchGradeModal() async {
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
