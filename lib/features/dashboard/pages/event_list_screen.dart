import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/event_exam_service.dart';
import 'event_editor_wizard.dart';
import 'allocation_dashboard.dart';
import 'proctor_assignment_screen.dart';

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

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'published':
        return 'Aktif / Published';
      case 'closed':
        return 'Selesai / Closed';
      default:
        return 'Draft';
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
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newStatus == 'published' ? 'Publish Event' : 'Tutup Event'),
        content: Text(confirmMsg),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'published' ? const Color(0xFF10B981) : const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
            child: Text(newStatus == 'published' ? 'Publish' : 'Tutup'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _eventService.updateEventStatus(widget.schoolId, eventId, newStatus);
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
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _eventService.streamEvents(widget.schoolId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final events = snapshot.data ?? [];

          return Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Event Ujian Semester',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: -0.5),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Buat event ujian, atur sesi, alokasikan meja, dan kelola pengawas.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EventEditorWizard(schoolId: widget.schoolId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Buat Event Ujian'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                      .limit(1)
                      .snapshots(),
                  builder: (context, draftSnap) {
                    if (!draftSnap.hasData || draftSnap.data!.docs.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final draftDoc = draftSnap.data!.docs.first;
                    final draftData = draftDoc.data() as Map<String, dynamic>;
                    final draftName = draftData['eventName'] as String? ?? '';
                    final updatedAt = (draftData['updatedAt'] as Timestamp?)?.toDate();
                    final agoLabel = updatedAt != null ? _timeAgoLabel(updatedAt) : 'beberapa saat lalu';
                    final draftStep = (draftData['step'] as num?)?.toInt() ?? 0;
                    const stepLabels = ['Info Dasar', 'Sesi', 'Jadwal Mapel', 'Ruangan', 'Review'];
                    final stepLabel = stepLabels[draftStep.clamp(0, stepLabels.length - 1)];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
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
                  },
                ),

                // ── Content ──
                if (events.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_note_outlined, size: 72, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum ada event ujian yang dibuat.\nTekan "Buat Event Ujian" untuk memulai.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
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
                          start = (e['startDate'] as Timestamp).toDate();
                        }
                        if (e['endDate'] != null) {
                          end = (e['endDate'] as Timestamp).toDate();
                        }

                        final dateRangeStr = (start != null && end != null)
                            ? '${dateFormat.format(start)} - ${dateFormat.format(end)}'
                            : '-';

                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: const [
                              BoxShadow(color: Color(0x02000000), blurRadius: 12, offset: Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.event_rounded, color: Color(0xFF4F46E5), size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Tahun Ajaran: $academicYear  •  Rentang Tanggal: $dateRangeStr',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(status).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _getStatusText(status),
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _getStatusColor(status)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => AllocationDashboard(schoolId: widget.schoolId, eventId: e['id'], eventName: name),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.grid_on_rounded, size: 16),
                                    label: const Text('Alokasi Tempat Duduk'),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ProctorAssignmentScreen(schoolId: widget.schoolId, eventId: e['id'], eventName: name),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.assignment_ind_outlined, size: 16),
                                    label: const Text('Atur Pengawas Ujian'),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
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
