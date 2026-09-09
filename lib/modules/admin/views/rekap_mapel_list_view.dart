import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

class RekapMapelListView extends StatelessWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const RekapMapelListView({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

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
              context.go('/admin/eventujian');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rekap Nilai: $eventName',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Pilih Mata Pelajaran untuk melihat nilai per kelas',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('events')
            .doc(eventId)
            .collection('subjects')
            .snapshots(),
        builder: (context, subjectsSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('events')
                .doc(eventId)
                .collection('timetable')
                .snapshots(),
            builder: (context, timetableSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('schools')
                    .doc(schoolId)
                    .collection('subjects')
                    .snapshots(),
                builder: (context, masterSubjectsSnap) {
                  final isSubjectsLoading = subjectsSnap.connectionState == ConnectionState.waiting;
                  final isTimetableLoading = timetableSnap.connectionState == ConnectionState.waiting;

                  if (isSubjectsLoading && isTimetableLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
                    );
                  }

                  // 1. Map Master Subjects (id -> name)
                  final Map<String, String> masterMap = {};
                  for (var doc in masterSubjectsSnap.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? data['subjectName'] ?? data['title'] ?? '').toString().trim();
                    if (name.isNotEmpty) {
                      masterMap[doc.id] = name;
                    }
                  }

                  // 2. Map Timetable (subjectId -> subjectName & teacherName)
                  final Map<String, String> timetableNameMap = {};
                  final Map<String, Set<String>> teacherMap = {};
                  for (var doc in timetableSnap.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final sId = (data['subjectId'] ?? doc.id).toString().trim();
                    final sName = (data['subjectName'] ?? data['name'] ?? data['subject_name'] ?? '').toString().trim();
                    final tName = (data['teacherName'] ?? data['teacher'] ?? '').toString().trim();

                    if (sId.isNotEmpty && sName.isNotEmpty) {
                      timetableNameMap[sId] = sName;
                    }
                    if (sName.isNotEmpty) {
                      final teacherList = tName.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty && t != '-');
                      teacherMap.putIfAbsent(sName, () => {}).addAll(teacherList);
                      if (sId.isNotEmpty) {
                        teacherMap.putIfAbsent(sId, () => {}).addAll(teacherList);
                      }
                    }
                  }

                  // 3. Resolve combined subject list
                  final List<Map<String, dynamic>> items = [];
                  final Set<String> addedKeys = {};

                  for (var doc in subjectsSnap.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;

                    String name = (data['name'] ??
                            data['subjectName'] ??
                            data['subject_name'] ??
                            data['title'] ??
                            data['namaMapel'] ??
                            data['nama_mapel'] ??
                            data['nama'] ??
                            '')
                        .toString()
                        .trim();

                    if (name.isEmpty || name == 'null' || name == 'Tanpa Nama') {
                      name = timetableNameMap[docId] ?? masterMap[docId] ?? '';
                    }

                    if (name.isEmpty && docId.isNotEmpty && !docId.startsWith('doc_') && docId.length < 30) {
                      name = docId;
                    }

                    if (name.isEmpty) {
                      name = 'Mata Pelajaran';
                    }

                    final teachers = (teacherMap[docId] ?? teacherMap[name] ?? {}).toList();

                    items.add({
                      'id': docId,
                      'name': name,
                      'code': data['code'] ?? '',
                      'teachers': teachers,
                    });
                    addedKeys.add(docId);
                    addedKeys.add(name);
                  }

                  // Fallback: If subjects subcollection was empty or missing entries from timetable
                  for (var doc in timetableSnap.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final sId = (data['subjectId'] ?? doc.id).toString().trim();
                    final sName = (data['subjectName'] ?? data['name'] ?? '').toString().trim();
                    final tName = (data['teacherName'] ?? '').toString().trim();

                    if (sName.isNotEmpty && sName != 'null' && sName != '-' && !addedKeys.contains(sName) && !addedKeys.contains(sId)) {
                      final teachers = tName.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty && t != '-').toList();
                      items.add({
                        'id': sId.isNotEmpty ? sId : sName,
                        'name': sName,
                        'code': data['code'] ?? '',
                        'teachers': teachers,
                      });
                      addedKeys.add(sName);
                      if (sId.isNotEmpty) addedKeys.add(sId);
                    }
                  }

                  if (items.isEmpty) {
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        margin: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEEF2FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.auto_stories_outlined,
                                size: 48,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Belum Ada Mata Pelajaran',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Event ujian ini belum memiliki jadwal atau mata pelajaran yang terdaftar.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFF64748B),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 40 : 20,
                      vertical: 28,
                    ),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Event Banner Header Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFF818CF8).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.assessment_rounded,
                                      color: Color(0xFF818CF8),
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          eventName,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Daftar ${items.length} Mata Pelajaran Ujian',
                                          style: GoogleFonts.inter(
                                            color: const Color(0xFF94A3B8),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Section Title
                            Text(
                              'PILIH MATA PELAJARAN',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF64748B),
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Cards List
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final subjectName = item['name'] as String;
                                final teachers = item['teachers'] as List<String>;
                                final teachersStr = teachers.isNotEmpty ? teachers.join(', ') : null;

                                return Container(
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
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        context.go(
                                          '/admin/event/$eventId/rekap/${item['id']}?eventName=${Uri.encodeComponent(eventName)}&subjectName=${Uri.encodeComponent(subjectName)}',
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Row(
                                          children: [
                                            // Icon Container
                                            Container(
                                              width: 52,
                                              height: 52,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.auto_stories_rounded,
                                                color: Colors.white,
                                                size: 26,
                                              ),
                                            ),
                                            const SizedBox(width: 18),

                                            // Details
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    subjectName,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: const Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  if (teachersStr != null) ...[
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.person_outline_rounded,
                                                          size: 14,
                                                          color: Color(0xFF64748B),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Expanded(
                                                          child: Text(
                                                            'Guru: $teachersStr',
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: GoogleFonts.inter(
                                                              fontSize: 13,
                                                              color: const Color(0xFF64748B),
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),

                                            const SizedBox(width: 12),

                                            // Action Pill Button
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEEF2FF),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Pilih Kelas',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.bold,
                                                      color: const Color(0xFF4F46E5),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  const Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 16,
                                                    color: Color(0xFF4F46E5),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
