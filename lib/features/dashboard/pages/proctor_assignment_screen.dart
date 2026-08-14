import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/event_exam_service.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/models/teacher.dart';

class ProctorAssignmentScreen extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;

  const ProctorAssignmentScreen({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<ProctorAssignmentScreen> createState() => _ProctorAssignmentScreenState();
}

class _ProctorAssignmentScreenState extends State<ProctorAssignmentScreen> {
  final EventExamService _eventService = EventExamService();
  final AdminUserService _adminUserService = AdminUserService();

  String? _selectedSessionId;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _rooms = [];
  Map<String, String> _assignments = {}; // roomId -> teacherId
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final sSnap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('events')
        .doc(widget.eventId)
        .collection('sessions')
        .orderBy('order')
        .get();

    final rSnap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('rooms')
        .get();

    setState(() {
      _sessions = sSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _rooms = rSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      if (_sessions.isNotEmpty) {
        _selectedSessionId = _sessions.first['id'];
        _loadCurrentProctors();
      }
    });
  }

  Future<void> _loadCurrentProctors() async {
    if (_selectedSessionId == null) return;
    final proctorsSnap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('events')
        .doc(widget.eventId)
        .collection('proctors')
        .where('sessionId', isEqualTo: _selectedSessionId)
        .get();

    final map = <String, String>{};
    for (var doc in proctorsSnap.docs) {
      final data = doc.data();
      map[data['roomId']] = data['teacherId'];
    }

    setState(() {
      _assignments = map;
    });
  }

  Future<void> _saveAssignments() async {
    if (_selectedSessionId == null) return;
    setState(() => _isProcessing = true);

    final payload = _assignments.entries.map((e) => {
      'sessionId': _selectedSessionId,
      'roomId': e.key,
      'teacherId': e.value,
      'role': 'main',
      'notes': 'Mengawas Sesi',
    }).toList();

    try {
      await _eventService.assignProctors(
        schoolId: widget.schoolId,
        eventId: widget.eventId,
        assignments: payload,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Berhasil menyimpan jadwal pengawas!'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan pengawas: $e'), backgroundColor: const Color(0xFFEF4444)),
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
        title: Text('Pengawas Ujian: ${widget.eventName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(28.0),
              child: StreamBuilder<List<Teacher>>(
                stream: _adminUserService.streamTeachers(widget.schoolId),
                builder: (context, teachersSnap) {
                  if (teachersSnap.hasError) return Center(child: Text('Error: ${teachersSnap.error}'));
                  if (teachersSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final teachers = teachersSnap.data ?? [];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Session Dropdown ──
                      if (_sessions.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _selectedSessionId,
                          decoration: const InputDecoration(labelText: 'Pilih Sesi Ujian', border: OutlineInputBorder()),
                          items: _sessions.map((s) {
                            return DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String));
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedSessionId = val;
                            });
                            _loadCurrentProctors();
                          },
                        )
                      else
                        const Center(child: Text('Belum ada sesi di event ini.')),
                      const SizedBox(height: 24),

                      // ── Matriks Ruang vs Pengawas ──
                      const Text('Daftar Ruangan & Pengawas Ujian', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _rooms.isEmpty
                            ? const Center(child: Text('Belum ada ruangan terdaftar.'))
                            : ListView.separated(
                                itemCount: _rooms.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (ctx, idx) {
                                  final r = _rooms[idx];
                                  final roomId = r['id'] as String;
                                  final currentTeacherId = _assignments[roomId];

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.meeting_room_outlined, color: Color(0xFF4F46E5)),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(r['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                              Text('Kode: ${r['code']}  •  Kapasitas: ${r['capacity']}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        SizedBox(
                                          width: 250,
                                          child: DropdownButtonFormField<String>(
                                            value: currentTeacherId,
                                            decoration: const InputDecoration(
                                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              border: OutlineInputBorder(),
                                              hintText: 'Pilih Pengawas',
                                            ),
                                            items: [
                                              const DropdownMenuItem(value: null, child: Text('Belum Ditugaskan')),
                                              ...teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.displayName))),
                                            ],
                                            onChanged: (val) {
                                              setState(() {
                                                if (val == null) {
                                                  _assignments.remove(roomId);
                                                } else {
                                                  _assignments[roomId] = val;
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _saveAssignments,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Simpan Tugas Pengawas', style: TextStyle(fontWeight: FontWeight.bold)),
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
