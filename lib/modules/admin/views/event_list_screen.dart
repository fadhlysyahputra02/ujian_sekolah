import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/event_exam_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import 'package:go_router/go_router.dart';
import 'event_editor_wizard.dart';
import 'admin_full_schedule_page.dart';

class EventListScreen extends StatefulWidget {
  final String schoolId;

  const EventListScreen({super.key, required this.schoolId});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final EventExamService _eventService = EventExamService();

  String _timeAgoLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  Future<void> _deleteDraft(String draftId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Hapus Draft?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Draft event yang belum selesai ini akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('eventDrafts')
        .doc(draftId)
        .delete();
  }

  Future<void> _deleteEvent(String eventId, String eventName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Hapus Event?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Event "$eventName" beserta seluruh data sesi, jadwal, alokasi, dan pengawasnya akan dihapus permanen. Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _eventService.deleteEvent(
        schoolId: widget.schoolId,
        eventId: eventId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event ujian berhasil dihapus.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus event: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'published':
        return const Color(0xFF10B981); // Emerald 500
      case 'closed':
        return const Color(0xFF64748B); // Slate 500
      default:
        return const Color(0xFFF59E0B); // Amber 500
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'published':
        return const Color(0xFFD1FAE5); // Emerald 100
      case 'closed':
        return const Color(0xFFF1F5F9); // Slate 100
      default:
        return const Color(0xFFFEF3C7); // Amber 100
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'published':
        return 'Aktif / Published';
      case 'closed':
        return 'Selesai / Closed';
      default:
        return 'Siap Publish';
    }
  }

  Future<void> _updateStatus(String eventId, String currentStatus) async {
    String newStatus = 'draft';
    String confirmMsg = '';
    if (currentStatus == 'draft') {
      newStatus = 'published';
      confirmMsg = 'Publish event ini? Jadwal ujian akan aktif bagi murid & guru.';
    } else if (currentStatus == 'published') {
      newStatus = 'closed';
      confirmMsg = 'Tutup event ini? Event ujian akan ditandai selesai.';
    } else {
      newStatus = 'draft';
      confirmMsg = 'Ubah status event ini kembali ke draf?';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Konfirmasi Status', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(confirmMsg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'published' ? const Color(0xFF10B981) : const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Lanjutkan'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(eventId)
          .update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status event berhasil diubah menjadi ${_getStatusText(newStatus)}!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah status: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.schoolId.isEmpty) {
      return const AppContentLoader(
        title: 'Memuat Profil Sekolah...',
        subtitle: 'Menyiapkan ruang ujian',
      );
    }
    final dateFormat = DateFormat('dd MMM yyyy');
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 750;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _eventService.streamEvents(widget.schoolId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppContentLoader(
              title: 'Memuat Event Ujian...',
              subtitle: 'Mengambil daftar pelaksanaan ujian dari database',
            );
          }

          final events = snapshot.data ?? [];

          return Padding(
            padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                if (isDesktop)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Event Ujian Semester',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Buat event ujian, atur sesi, alokasikan meja, dan kelola pengawas.',
                              style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventEditorWizard(schoolId: widget.schoolId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Buat Event Ujian', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Event Ujian Semester',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Buat event ujian, atur sesi, & kelola pengawas.',
                        style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EventEditorWizard(schoolId: widget.schoolId),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('Buat Event Ujian', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),

                // ── Draft Banner ──
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('schools')
                      .doc(widget.schoolId)
                      .collection('eventDrafts')
                      .orderBy('updatedAt', descending: true)
                      .snapshots(),
                  builder: (context, draftSnap) {
                    if (!draftSnap.hasData || draftSnap.data!.docs.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final draftDocs = draftSnap.data!.docs;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: draftDocs.map((draftDoc) {
                        final draftData = draftDoc.data() as Map<String, dynamic>;
                        final draftName = draftData['eventName'] as String? ?? '';
                        final rawUpdated = draftData['updatedAt'];
                        final updatedAt = rawUpdated is Timestamp
                            ? rawUpdated.toDate()
                            : (rawUpdated is String ? DateTime.tryParse(rawUpdated) : null);
                        final agoLabel = updatedAt != null ? _timeAgoLabel(updatedAt) : 'beberapa saat lalu';
                        final draftStep = (draftData['step'] as num?)?.toInt() ?? 0;
                        const stepLabels = ['Info Dasar', 'Sesi', 'Jadwal Mapel', 'Ruangan', 'Review'];
                        final stepLabel = stepLabels[draftStep.clamp(0, stepLabels.length - 1)];

                        if (isDesktop) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFCD34D), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.edit_note_rounded, color: Color(0xFFD97706), size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text('Draft tersimpan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E))),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFCD34D),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('Step: $stepLabel', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${draftName.isNotEmpty ? '"$draftName"' : 'Tanpa Nama'}  •  Terakhir disimpan $agoLabel',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => EventEditorWizard(
                                          schoolId: widget.schoolId,
                                          draftId: draftDoc.id,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.restore_rounded, size: 16),
                                  label: const Text('Lanjutkan Draft'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97706),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB45309), size: 20),
                                  tooltip: 'Hapus Draft',
                                  onPressed: () => _deleteDraft(draftDoc.id),
                                ),
                              ],
                            ),
                          );
                        } else {
                          // Premium Responsive Draft Card for Mobile
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFCD34D), width: 1.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.edit_note_rounded, color: Color(0xFFD97706), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text('Draft tersimpan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E))),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFCD34D),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(stepLabel, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${draftName.isNotEmpty ? '"$draftName"' : 'Tanpa Nama'} • saved $agoLabel',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB45309), size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _deleteDraft(draftDoc.id),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => EventEditorWizard(
                                          schoolId: widget.schoolId,
                                          draftId: draftDoc.id,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.restore_rounded, size: 16),
                                  label: Text('Lanjutkan Draft', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97706),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // ── Event Cards ──
                if (events.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_note_outlined, size: 72, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            'Belum ada event ujian yang dibuat.\nTekan "Buat Event Ujian" untuk memulai.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, i) {
                        final e = events[i];
                        final name = e['name'] ?? '-';
                        final academicYear = e['academicYear'] ?? '-';
                        final status = e['status'] ?? 'draft';

                        DateTime? start;
                        DateTime? end;
                        if (e['startDate'] != null) {
                          final sd = e['startDate'];
                          start = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
                        }
                        if (e['endDate'] != null) {
                          final ed = e['endDate'];
                          end = ed is Timestamp ? ed.toDate() : (ed is String ? DateTime.tryParse(ed) : null);
                        }

                        final dateRangeStr = (start != null && end != null)
                            ? '${dateFormat.format(start)} - ${dateFormat.format(end)}'
                            : '-';

                        return Container(
                          padding: EdgeInsets.all(isDesktop ? 20 : 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.inter(
                                            fontSize: isDesktop ? 16 : 15,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'TA: $academicYear  •  Jadwal: $dateRangeStr',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: const Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusBgColor(status),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _getStatusText(status),
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _getStatusColor(status),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              StreamBuilder<List<Map<String, dynamic>>>(
                                stream: _eventService.streamTimetable(widget.schoolId, e['id']),
                                builder: (context, timetableSnap) {
                                  if (!timetableSnap.hasData || timetableSnap.data!.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  // Group teachers by subject
                                  final Map<String, Set<String>> subjectToTeachers = {};
                                  for (final entry in timetableSnap.data!) {
                                    final subName = entry['subjectName'] as String? ?? '-';
                                    final tName = entry['teacherName'] as String? ?? '-';

                                    if (!subjectToTeachers.containsKey(subName)) {
                                      subjectToTeachers[subName] = {};
                                    }
                                    if (tName.isNotEmpty && tName != '-') {
                                      for (final t in tName.split(',')) {
                                        if (t.trim().isNotEmpty) {
                                          subjectToTeachers[subName]!.add(t.trim());
                                        }
                                      }
                                    }
                                  }

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 16),
                                      Text(
                                        'Mata Pelajaran & Pembuat Soal:',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ...subjectToTeachers.entries.map((entry) {
                                        final teachersList = entry.value.isNotEmpty
                                            ? entry.value.join(', ')
                                            : 'Belum ditentukan';
                                        // Cari subjectId dari timetable berdasarkan nama mapel
                                        final subjectEntry = timetableSnap.data!.firstWhere(
                                          (t) => t['subjectName'] == entry.key,
                                          orElse: () => {},
                                        );
                                        final subjectId = subjectEntry['subjectId'] as String? ?? entry.key;

                                        return StreamBuilder<QuerySnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection('schools')
                                              .doc(widget.schoolId)
                                              .collection('events')
                                              .doc(e['id'])
                                              .collection('subjects')
                                              .doc(subjectId)
                                              .collection('questions')
                                              .limit(1)
                                              .snapshots(),
                                          builder: (context, qSnap) {
                                            final hasQuestions = qSnap.hasData && qSnap.data!.docs.isNotEmpty;
                                            final isChecking = qSnap.connectionState == ConnectionState.waiting;

                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 3),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    width: 5,
                                                    height: 5,
                                                    margin: const EdgeInsets.only(top: 6),
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFF94A3B8),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF334155)),
                                                        children: [
                                                          TextSpan(
                                                            text: '${entry.key}: ',
                                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                                          ),
                                                          TextSpan(
                                                            text: teachersList,
                                                            style: const TextStyle(color: Color(0xFF64748B)),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  if (isChecking)
                                                    const SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF94A3B8)),
                                                    )
                                                  else if (hasQuestions)
                                                    Tooltip(
                                                      message: 'Soal sudah siap',
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFD1FAE5),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: const Color(0xFF6EE7B7)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF059669)),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              'Soal sudah siap',
                                                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF059669)),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                  else
                                                    Tooltip(
                                                      message: 'Belum ada soal untuk mapel ini',
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFFEF3C7),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: const Color(0xFFFCD34D)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.warning_amber_rounded, size: 11, color: Color(0xFFD97706)),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              'Belum ada soal',
                                                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      }),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              const SizedBox(height: 16),
                              if (isDesktop)
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        context.push('/admin/event/${e['id']}/schedule?name=${Uri.encodeComponent(name)}');
                                      },
                                      icon: const Icon(Icons.calendar_month_rounded, size: 16),
                                      label: const Text('Lihat Jadwal Lengkap'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4F46E5),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                    if (status == 'draft')
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => EventEditorWizard(
                                                schoolId: widget.schoolId,
                                                eventId: e['id'],
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.edit_rounded, size: 16),
                                        label: const Text('Edit Event'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF4F46E5),
                                          side: const BorderSide(color: Color(0xFF4F46E5)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    if (status != 'closed')
                                      ElevatedButton.icon(
                                        onPressed: () => _updateStatus(e['id'], status),
                                        icon: Icon(status == 'draft' ? Icons.publish_rounded : Icons.check_circle_outline, size: 16),
                                        label: Text(status == 'draft' ? 'Publish Event' : 'Tutup Event'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: status == 'draft' ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    OutlinedButton.icon(
                                      onPressed: () => _deleteEvent(e['id'], e['name'] ?? 'Tanpa Nama'),
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                      label: const Text('Hapus'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFEF4444),
                                        side: const BorderSide(color: Color(0xFFEF4444)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                // Premium stacked/row action layout on Mobile
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        context.push('/admin/event/${e['id']}/schedule?name=${Uri.encodeComponent(name)}');
                                      },
                                      icon: const Icon(Icons.calendar_month_rounded, size: 16),
                                      label: Text('Lihat Jadwal Lengkap', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF4F46E5),
                                        side: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (status != 'closed') ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _updateStatus(e['id'], status),
                                        icon: Icon(status == 'draft' ? Icons.publish_rounded : Icons.check_circle_outline, size: 16),
                                        label: Text(status == 'draft' ? 'Publish Event' : 'Tutup Event', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: status == 'draft' ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    Row(
                                      children: [
                                        if (status == 'draft') ...[
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => EventEditorWizard(
                                                      schoolId: widget.schoolId,
                                                      eventId: e['id'],
                                                    ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.edit_rounded, size: 16),
                                              label: Text('Edit', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(0xFF4F46E5),
                                                side: const BorderSide(color: Color(0xFF4F46E5)),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                        ],
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _deleteEvent(e['id'], e['name'] ?? 'Tanpa Nama'),
                                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                            label: Text('Hapus', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(0xFFEF4444),
                                              side: const BorderSide(color: Color(0xFFEF4444)),
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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
      ),
    );
  }
}
