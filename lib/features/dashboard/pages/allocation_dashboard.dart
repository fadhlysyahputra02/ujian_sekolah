import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/event_exam_service.dart';
import '../../../core/utils/file_saver.dart';

class AllocationDashboard extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const AllocationDashboard({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<AllocationDashboard> createState() => _AllocationDashboardState();
}

class _AllocationDashboardState extends State<AllocationDashboard> {
  final EventExamService _eventService = EventExamService();

  String? _selectedAllocationId;
  String? _selectedRoomId;
  List<Map<String, dynamic>> _rooms = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    final snap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('rooms')
        .get();
    if (snap.docs.isNotEmpty) {
      setState(() {
        _rooms = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        _selectedRoomId = _rooms.first['id'];
      });
    }
  }

  Future<void> _generateNumbers() async {
    if (_selectedAllocationId == null) return;
    setState(() => _isProcessing = true);
    try {
      final count = await _eventService.generateParticipantNumbers(
        schoolId: widget.schoolId,
        eventId: widget.eventId,
        allocationId: _selectedAllocationId!,
        formatConfig: {
          'seatPadding': 3,
          'delimiter': '-',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Berhasil membuat nomor peserta untuk $count meja murid!'), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat nomor peserta: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportCSV() async {
    if (_selectedAllocationId == null) return;
    setState(() => _isProcessing = true);
    try {
      final url = await _eventService.exportRoomList(
        schoolId: widget.schoolId,
        eventId: widget.eventId,
        allocationId: _selectedAllocationId!,
        roomId: _selectedRoomId,
      );
      await openUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ekspor berhasil! Mengunduh berkas CSV...'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _rollback() async {
    if (_selectedAllocationId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan Alokasi'),
        content: const Text('Apakah Anda yakin ingin menghapus data alokasi kursi ini? Tindakan ini akan membersihkan nomor peserta dan penempatan murid.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await _eventService.rollbackAllocation(
        schoolId: widget.schoolId,
        eventId: widget.eventId,
        allocationId: _selectedAllocationId!,
      );
      setState(() {
        _selectedAllocationId = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alokasi berhasil dibatalkan secara bersih!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membatalkan alokasi: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Alokasi Kursi: ${widget.eventName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(28.0),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _eventService.streamAllocations(widget.schoolId, widget.eventId),
                builder: (context, allocsSnap) {
                  if (allocsSnap.hasError) return Center(child: Text('Error: ${allocsSnap.error}'));
                  if (allocsSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allocations = allocsSnap.data ?? [];
                  if (allocations.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.grid_off_rounded, size: 72, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum ada run alokasi terbuat.\nSilakan buat event ujian baru dan jalankan alokasi.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_selectedAllocationId == null) {
                    _selectedAllocationId = allocations.first['id'];
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Control Bar ──
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedAllocationId,
                              decoration: const InputDecoration(labelText: 'Run Alokasi', border: OutlineInputBorder()),
                              items: allocations.map((a) {
                                final time = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                                final label = 'Mode: ${a['mode'].toString().toUpperCase()} (${time.hour}:${time.minute})';
                                return DropdownMenuItem(value: a['id'] as String, child: Text(label));
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedAllocationId = val),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedRoomId,
                              decoration: const InputDecoration(labelText: 'Pilih Ruangan', border: OutlineInputBorder()),
                              items: _rooms.map((r) {
                                return DropdownMenuItem(value: r['id'] as String, child: Text(r['name'] as String));
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedRoomId = val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Action Buttons ──
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _generateNumbers,
                            icon: const Icon(Icons.pin_rounded, size: 16),
                            label: const Text('Generate Nomor Ujian'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exportCSV,
                            icon: const Icon(Icons.file_download_outlined, size: 16),
                            label: const Text('Ekspor Daftar Ruang (CSV)'),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFCBD5E1))),
                          ),
                          OutlinedButton.icon(
                            onPressed: _rollback,
                            icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 16),
                            label: const Text('Batalkan Alokasi', style: TextStyle(color: Color(0xFFEF4444))),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFFEE2E2))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ── Seating Map ──
                      const Text('Denah Tempat Duduk', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 12),
                      Expanded(
                        child: StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _eventService.streamSeats(widget.schoolId, widget.eventId, _selectedAllocationId!),
                          builder: (context, seatsSnap) {
                            if (seatsSnap.hasError) return Center(child: Text('Error: ${seatsSnap.error}'));
                            if (seatsSnap.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final allSeats = seatsSnap.data ?? [];
                            // Filter seats by selectedRoomId
                            final roomSnap = _rooms.firstWhere((r) => r['id'] == _selectedRoomId, orElse: () => {});
                            final roomCode = roomSnap['code'] ?? '';

                            final seats = allSeats.where((s) => s['roomCode'] == roomCode).toList();

                            if (seats.isEmpty) {
                              return const Center(child: Text('Tidak ada murid dialokasikan ke ruangan ini.'));
                            }

                            return GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 1.8,
                              ),
                              itemCount: seats.length,
                              itemBuilder: (ctx, idx) {
                                final s = seats[idx];
                                final name = s['studentName'] ?? '-';
                                final classId = s['classId'] ?? '-';
                                final num = s['participantNumber'] ?? 'Belum ada nomor';
                                final seatNum = s['seatNumber'] ?? 0;

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x02000000), blurRadius: 4, offset: Offset(0, 2)),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('Meja $seatNum', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                          ),
                                          Text(classId, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                        ],
                                      ),
                                      Text(
                                        name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        num,
                                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF4F46E5), fontWeight: FontWeight.bold),
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
                },
              ),
            ),
    );
  }
}
