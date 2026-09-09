import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

class RekapClassListView extends StatelessWidget {
  final String schoolId;
  final String eventId;
  final String subjectId;
  final String eventName;
  final String subjectName;

  const RekapClassListView({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.subjectId,
    required this.eventName,
    required this.subjectName,
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
              context.go(
                '/admin/event/$eventId/rekap?eventName=${Uri.encodeComponent(eventName)}',
              );
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
              'Mapel: $subjectName • Pilih Kelas Peserta',
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
            .collection('classes')
            .orderBy('name')
            .snapshots(),
        builder: (context, classesSnap) {
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
                    .collection('events')
                    .doc(eventId)
                    .collection('submissions')
                    .snapshots(),
                builder: (context, subSnap) {
                  final isClassesLoading = classesSnap.connectionState == ConnectionState.waiting;
                  final isTimetableLoading = timetableSnap.connectionState == ConnectionState.waiting;

                  if (isClassesLoading && isTimetableLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF059669)),
                    );
                  }

                  // 1. Collect target classes assigned to this subject from Timetable
                  final Set<String> targetClassIds = {};
                  final Set<String> targetClassNames = {};

                  for (var doc in timetableSnap.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final sId = (data['subjectId'] ?? '').toString().trim();
                    final sName = (data['subjectName'] ?? data['name'] ?? '').toString().trim();

                    bool matchSub = false;
                    if (sId.isNotEmpty && (sId == subjectId || sId.toLowerCase() == subjectId.toLowerCase())) {
                      matchSub = true;
                    } else if (sName.isNotEmpty && (sName.toLowerCase() == subjectName.toLowerCase())) {
                      matchSub = true;
                    }

                    if (matchSub) {
                      final cId = (data['classId'] ?? '').toString().trim();
                      final cName = (data['className'] ?? data['name'] ?? '').toString().trim();
                      if (cId.isNotEmpty) targetClassIds.add(cId);
                      if (cName.isNotEmpty) targetClassNames.add(cName.toLowerCase());

                      if (data['classIds'] is List) {
                        for (var id in data['classIds']) {
                          targetClassIds.add(id.toString().trim());
                        }
                      }
                      if (data['classNames'] is List) {
                        for (var name in data['classNames']) {
                          targetClassNames.add(name.toString().trim().toLowerCase());
                        }
                      }
                      if (data['targetClasses'] is List) {
                        for (var tc in data['targetClasses']) {
                          targetClassNames.add(tc.toString().trim().toLowerCase());
                        }
                      }
                    }
                  }

                  // 2. Collect target classes from Submissions of this subject
                  for (var doc in subSnap.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final sId = (data['subjectId'] ?? '').toString().trim();
                    final sName = (data['subjectName'] ?? '').toString().trim();

                    bool matchSub = false;
                    if (sId.isNotEmpty && (sId == subjectId || sId.toLowerCase() == subjectId.toLowerCase())) {
                      matchSub = true;
                    } else if (sName.isNotEmpty && (sName.toLowerCase() == subjectName.toLowerCase())) {
                      matchSub = true;
                    }

                    if (matchSub) {
                      final cId = (data['classId'] ?? '').toString().trim();
                      final cName = (data['className'] ?? data['studentClass'] ?? data['kelas'] ?? '').toString().trim();
                      if (cId.isNotEmpty) targetClassIds.add(cId);
                      if (cName.isNotEmpty) targetClassNames.add(cName.toLowerCase());
                    }
                  }

                  // 3. Resolve filtered master classes
                  final List<Map<String, dynamic>> resolvedClasses = [];
                  final Set<String> addedKeys = {};
                  final bool hasFilters = targetClassIds.isNotEmpty || targetClassNames.isNotEmpty;

                  for (var doc in classesSnap.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final cId = doc.id;
                    final cName = (data['name'] ?? data['className'] ?? '').toString().trim();

                    bool isTarget = false;
                    if (hasFilters) {
                      if (targetClassIds.contains(cId)) {
                        isTarget = true;
                      } else if (targetClassNames.contains(cName.toLowerCase())) {
                        isTarget = true;
                      }
                    } else {
                      // Fallback: If no timetable/submission restrictions exist, include all
                      isTarget = true;
                    }

                    if (isTarget && !addedKeys.contains(cId) && !addedKeys.contains(cName.toLowerCase())) {
                      addedKeys.add(cId);
                      addedKeys.add(cName.toLowerCase());
                      resolvedClasses.add({
                        'id': cId,
                        'name': cName.isNotEmpty ? cName : 'Tanpa Nama',
                        'data': data,
                      });
                    }
                  }

                  // 4. Include targetClassNames that might not be in master classes snapshot
                  if (hasFilters) {
                    for (var tName in targetClassNames) {
                      if (tName.isNotEmpty && !addedKeys.contains(tName)) {
                        addedKeys.add(tName);
                        // Find uppercase / pretty name
                        String prettyName = tName.toUpperCase();
                        if (tName.startsWith('kelas ')) {
                          prettyName = tName.replaceFirst('kelas ', 'Kelas ').toUpperCase();
                        }
                        resolvedClasses.add({
                          'id': tName,
                          'name': prettyName,
                          'data': {'name': prettyName},
                        });
                      }
                    }
                  }

                  if (resolvedClasses.isEmpty) {
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
                                color: Color(0xFFECFDF5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.class_outlined,
                                size: 48,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Tidak Ada Kelas Peserta',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tidak ada kelas yang dijadwalkan mengikuti ujian mata pelajaran $subjectName.',
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
                            // Header Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF064E3B), Color(0xFF047857)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF064E3B).withValues(alpha: 0.15),
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
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.menu_book_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          subjectName,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$eventName • ${resolvedClasses.length} Kelas Peserta Ujian',
                                          style: GoogleFonts.inter(
                                            color: const Color(0xFFA7F3D0),
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
                              'PILIH KELAS PESERTA UJIAN',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF64748B),
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Class Cards List
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: resolvedClasses.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final cls = resolvedClasses[index];
                                final rawName = cls['name'] as String;
                                final className = rawName.toLowerCase().startsWith('kelas ')
                                    ? rawName
                                    : 'Kelas $rawName';

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
                                          '/admin/event/$eventId/rekap/$subjectId/class/${cls['id']}?eventName=${Uri.encodeComponent(eventName)}&subjectName=${Uri.encodeComponent(subjectName)}&className=${Uri.encodeComponent(rawName)}',
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Row(
                                          children: [
                                            // Icon
                                            Container(
                                              width: 52,
                                              height: 52,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF059669), Color(0xFF10B981)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF059669).withValues(alpha: 0.25),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.groups_rounded,
                                                color: Colors.white,
                                                size: 26,
                                              ),
                                            ),
                                            const SizedBox(width: 18),

                                            // Content
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    className,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: const Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Klik untuk membuka rekap nilai seluruh murid',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      color: const Color(0xFF64748B),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),

                                            // Action Pill Button
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFECFDF5),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Lihat Nilai',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.bold,
                                                      color: const Color(0xFF059669),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  const Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 16,
                                                    color: Color(0xFF059669),
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
