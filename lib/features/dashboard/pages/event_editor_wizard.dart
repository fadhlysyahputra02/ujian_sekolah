import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/services/event_exam_service.dart';
import '../../../core/models/teacher.dart';
import 'exam_pdf_generator.dart';

class EventEditorWizard extends StatefulWidget {
  final String schoolId;
  final String? draftId;

  const EventEditorWizard({super.key, required this.schoolId, this.draftId});

  @override
  State<EventEditorWizard> createState() => _EventEditorWizardState();
}

class _EventEditorWizardState extends State<EventEditorWizard> {
  final _formKey1 = GlobalKey<FormState>();
  final AdminUserService _adminUserService = AdminUserService();
  final EventExamService _eventService = EventExamService();

  int _currentStep = 0;
  bool _isLoading = false;

  // Step 1: Info Dasar
  final _nameController = TextEditingController();
  final _academicYearController = TextEditingController(text: '2026/2027');
  final _descController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _examType = 'UTS';

  // Step 2: Sesi
  final List<Map<String, dynamic>> _sessions = [];
  final _sessionNameController = TextEditingController();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Step 3: Timetable / Jadwal Mapel
  final List<Map<String, dynamic>> _timetable = [];
  final List<String> _selectedClassIds = [];
  String? _selectedSubjectId;
  String? _selectedTeacherId;
  int? _selectedSessionIndex;

  // Step 4: Ruangan
  List<Map<String, dynamic>> _rooms = [];

  // Step 5: Alokasi Murid ke Ruangan
  String? _selectedRoomId;
  // roomId -> [ { classId, className, count, isAll } ]
  Map<String, List<Map<String, dynamic>>> _roomAssignments = {};
  // Persist local selection UI configurations for each class
  final Map<String, Map<String, dynamic>> _addState = {};


  // Step 5: Aturan Alokasi (retained for submit compatibility)
  String _allocationMode = 'zigzag';
  bool _respectAngkatan = true;
  bool _avoidSameClassAdjacent = true;
  String _numberDelimiter = '-';
  int _seatPadding = 3;

  // Step 6: Schedule Grid
  // Key: 'day_$dayIndex_session_$sessionIdx' -> subjectId assigned
  final Map<String, String> _scheduleGrid = {};

  // Step 7: Proctor Grid
  // Key: 'day_$dayIndex_session_$sessionIdx' -> teacherId assigned
  final Map<String, String> _proctorGrid = {};

  // Draft auto-save
  String? _draftId;
  bool _isSavingDraft = false;
  String _draftStatus = ''; // 'saving', 'saved', ''

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initOrLoadDraft());
  }

  Future<void> _initOrLoadDraft() async {
    if (widget.draftId != null) {
      // Load the specific draft passed from the event list screen
      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('eventDrafts')
          .doc(widget.draftId)
          .get();
      if (mounted && doc.exists) {
        _loadDraftData(doc.data()!, doc.id);
        return;
      }
    }
    // No draft to load — start fresh
    _initDefaultState();
  }

  void _initDefaultState() {
    _loadRooms();
    if (_sessions.isEmpty) {
      setState(() {
        _sessions.addAll([
          {'name': 'Sesi 1', 'startTime': '07:00', 'endTime': '08:00', 'order': 1, 'date': DateTime.now().toIso8601String()},
          {'name': 'Sesi 2', 'startTime': '09:00', 'endTime': '10:00', 'order': 2, 'date': DateTime.now().toIso8601String()},
        ]);
      });
    }
  }

  void _loadDraftData(Map<String, dynamic> data, String id) {
    setState(() {
      _draftId = id;
      _currentStep = (data['step'] as num?)?.toInt() ?? 0;
      _nameController.text = data['eventName'] as String? ?? '';
      _academicYearController.text = data['academicYear'] as String? ?? '2026/2027';
      _descController.text = data['description'] as String? ?? '';
      _examType = data['examType'] as String? ?? 'UTS';
      if (data['startDate'] != null) _startDate = DateTime.tryParse(data['startDate'] as String);
      if (data['endDate'] != null) _endDate = DateTime.tryParse(data['endDate'] as String);
      _sessions.clear();
      if (data['sessions'] is List) {
        _sessions.addAll((data['sessions'] as List).cast<Map<String, dynamic>>());
      }
      _timetable.clear();
      if (data['timetable'] is List) {
        _timetable.addAll((data['timetable'] as List).cast<Map<String, dynamic>>());
      }
      _rooms.clear();
      if (data['rooms'] is List) {
        _rooms.addAll((data['rooms'] as List).cast<Map<String, dynamic>>());
      }
      _roomAssignments.clear();
      if (data['roomAssignments'] is Map) {
        (data['roomAssignments'] as Map).forEach((k, v) {
          if (v is List) {
            _roomAssignments[k as String] = v.cast<Map<String, dynamic>>();
          }
        });
      }
      _scheduleGrid.clear();
      if (data['scheduleGrid'] is Map) {
        (data['scheduleGrid'] as Map).forEach((k, v) {
          _scheduleGrid[k as String] = v as String;
        });
      }
      _proctorGrid.clear();
      if (data['proctorGrid'] is Map) {
        (data['proctorGrid'] as Map).forEach((k, v) {
          _proctorGrid[k as String] = v as String;
        });
      }
    });
  }

  Future<void> _autoSaveDraft() async {
    if (!mounted) return;
    setState(() { _draftStatus = 'saving'; });

    final draftData = {
      'step': _currentStep,
      'eventName': _nameController.text.trim(),
      'academicYear': _academicYearController.text.trim(),
      'description': _descController.text.trim(),
      'examType': _examType,
      'startDate': _startDate?.toIso8601String(),
      'endDate': _endDate?.toIso8601String(),
      'sessions': _sessions,
      'timetable': _timetable,
      'rooms': _rooms,
      'roomAssignments': _roomAssignments,
      'scheduleGrid': _scheduleGrid,
      'proctorGrid': _proctorGrid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final draftsRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('eventDrafts');

    try {
      if (_draftId != null) {
        await draftsRef.doc(_draftId).update(draftData);
      } else {
        final doc = await draftsRef.add(draftData);
        if (mounted) setState(() => _draftId = doc.id);
      }
      if (mounted) setState(() { _draftStatus = 'saved'; });
      // Clear status after 2 seconds
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() { _draftStatus = ''; });
    } catch (e) {
      if (mounted) {
        setState(() { _draftStatus = ''; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan draft: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _deleteDraft() async {
    if (_draftId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('eventDrafts')
          .doc(_draftId)
          .delete();
    } catch (_) {}
  }

  String _timeAgoLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  Future<void> _loadRooms() async {
    final snap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('rooms')
        .get();
    setState(() {
      _rooms = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    });
  }

  Future<void> _selectDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
        // Sync session dates with the selected start date
        for (var session in _sessions) {
          session['date'] = range.start.toIso8601String();
        }
      });
    }
  }

  void _addSession() {
    if (_sessionNameController.text.trim().isEmpty || _startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi nama sesi, waktu mulai & selesai!'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _sessions.add({
        'name': _sessionNameController.text.trim(),
        'startTime': '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}',
        'endTime': '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}',
        'order': _sessions.length + 1,
        // Default using startDate for simplicity
        'date': _startDate?.toIso8601String() ?? DateTime.now().toIso8601String(),
      });
      _sessionNameController.clear();
      _startTime = null;
      _endTime = null;
    });
    _autoSaveDraft();
  }

  void _addTimetableEntry(List<Map<String, dynamic>> subjects, List<Teacher> teachers, List<Map<String, dynamic>> classes) {
    if (_selectedClassIds.isEmpty || _selectedSubjectId == null || _selectedTeacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi pilihan kelas, mapel & guru pembuat soal!'), backgroundColor: Colors.red),
      );
      return;
    }

    final sub = subjects.firstWhere((s) => s['id'] == _selectedSubjectId);
    final teacher = teachers.firstWhere((t) => t.id == _selectedTeacherId);

    setState(() {
      for (final cid in _selectedClassIds) {
        final exists = _timetable.any((t) => t['classId'] == cid && t['subjectId'] == _selectedSubjectId);
        if (!exists) {
          final classDoc = classes.firstWhere((c) => c['id'] == cid, orElse: () => {});
          final className = classDoc['name'] as String? ?? cid;

          _timetable.add({
            'classId': cid,
            'className': className,
            'subjectId': _selectedSubjectId,
            'subjectName': sub['name'] ?? '',
            'teacherId': _selectedTeacherId,
            'teacherName': teacher.displayName,
            'sessionId': null,
            'sessionName': null,
          });
        }
      }
      _selectedClassIds.clear();
      _selectedSubjectId = null;
      _selectedTeacherId = null;
      _selectedSessionIndex = null;
    });
    _autoSaveDraft();
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      // 1. Create Event
      final eventId = await _eventService.createEvent(
        schoolId: widget.schoolId,
        eventInfo: {
          'name': _nameController.text.trim(),
          'type': _examType,
          'academicYear': _academicYearController.text.trim(),
          'startDate': Timestamp.fromDate(_startDate!),
          'endDate': Timestamp.fromDate(_endDate!),
          'description': _descController.text.trim(),
          'participantNumberFormat': '[angkatan][roomCode][seatNumber]',
          'seatNumberPadding': _seatPadding
        },
        sessions: _sessions,
        timetable: _timetable,
      );

      // 2. Execute Seating Allocation
      final allocationId = await _eventService.executeAllocation(
        schoolId: widget.schoolId,
        eventId: eventId,
        mode: _allocationMode,
        options: {
          'respectAngkatan': _respectAngkatan,
          'avoidSameClassAdjacent': _avoidSameClassAdjacent,
          'seed': 42
        },
      );

      // 3. Generate Participant Numbers
      await _eventService.generateParticipantNumbers(
        schoolId: widget.schoolId,
        eventId: eventId,
        allocationId: allocationId,
        formatConfig: {
          'seatPadding': _seatPadding,
          'delimiter': _numberDelimiter
        },
      );

      // 4. Delete draft on success
      await _deleteDraft();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event ujian & alokasi tempat duduk berhasil dibuat!'), backgroundColor: Color(0xFF10B981)),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses pembuatan event: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Buat Event Ujian Semester Baru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (_draftStatus == 'saving')
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                  SizedBox(width: 8),
                  Text('Menyimpan...', style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            )
          else if (_draftStatus == 'saved')
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.cloud_done_rounded, size: 16, color: Color(0xFF10B981)),
                  SizedBox(width: 6),
                  Text('Draft tersimpan', style: TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                ],
              ),
            )
          else if (_draftId != null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.cloud_outlined, size: 16, color: Colors.white38),
                  SizedBox(width: 6),
                  Text('Draft aktif', style: TextStyle(fontSize: 12, color: Colors.white38)),
                ],
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Memproses alokasi tempat duduk dan penomoran meja...', style: TextStyle(color: Color(0xFF64748B))),
                ],
              ),
            )
          : Column(
              children: [
                // Steps Indicator
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(8, (i) {
                      final isActive = _currentStep == i;
                      final isCompleted = _currentStep > i;
                      return Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF4F46E5)
                                  : isCompleted
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFE2E8F0),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: isCompleted
                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                : Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color: isActive || isCompleted ? Colors.white : const Color(0xFF64748B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                          if (i < 7)
                            Container(
                              width: isDesktop ? 60 : 20,
                              height: 2,
                              color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                            ),
                        ],
                      );
                    }),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: _buildStepContent(),
                      ),
                    ),
                  ),
                ),

                // Navigation buttons
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0)
                        OutlinedButton(
                          onPressed: () => setState(() => _currentStep--),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Sebelumnya'),
                        )
                      else
                        const SizedBox(),
                      ElevatedButton(
                        onPressed: () {
                          if (_currentStep == 0) {
                            if (_formKey1.currentState!.validate() && _startDate != null && _endDate != null) {
                              setState(() => _currentStep++);
                              _autoSaveDraft();
                            } else if (_startDate == null || _endDate == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pilih rentang tanggal terlebih dahulu!'), backgroundColor: Colors.red),
                              );
                            }
                          } else if (_currentStep == 1) {
                            if (_sessions.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tambahkan minimal 1 sesi ujian!'), backgroundColor: Colors.red),
                              );
                            } else {
                              setState(() => _currentStep++);
                              _autoSaveDraft();
                            }
                          } else if (_currentStep == 2) {
                            if (_timetable.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tambahkan minimal 1 jadwal mata pelajaran!'), backgroundColor: Colors.red),
                              );
                            } else {
                              setState(() => _currentStep++);
                              _autoSaveDraft();
                            }
                          } else if (_currentStep == 7) {
                            _submit();
                          } else {
                            setState(() => _currentStep++);
                            _autoSaveDraft();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(_currentStep == 7 ? 'Eksekusi & Simpan' : 'Selanjutnya'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      case 4:
        return _buildStep5();
      case 5:
        return _buildStep6();
      case 6:
        return _buildStep7();
      case 7:
        return _buildStep8();
      default:
        return const SizedBox();
    }
  }

  // Step 1: Info Dasar
  Widget _buildStep1() {
    return Form(
      key: _formKey1,
      child: ListView(
        children: [
          const Text('Langkah 1: Informasi Dasar Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nama Event Ujian',
              hintText: 'contoh: Ujian Semester Ganjil ',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.trim().isEmpty ? 'Nama event harus diisi!' : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                const Text('Tipe Ujian: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155))),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('UTS (Tengah Semester)'),
                  selected: _examType == 'UTS',
                  onSelected: (selected) {
                    if (selected) setState(() => _examType = 'UTS');
                  },
                  selectedColor: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                  checkmarkColor: const Color(0xFF4F46E5),
                  labelStyle: TextStyle(
                    color: _examType == 'UTS' ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                    fontWeight: _examType == 'UTS' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('UAS (Akhir Semester)'),
                  selected: _examType == 'UAS',
                  onSelected: (selected) {
                    if (selected) setState(() => _examType = 'UAS');
                  },
                  selectedColor: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                  checkmarkColor: const Color(0xFF4F46E5),
                  labelStyle: TextStyle(
                    color: _examType == 'UAS' ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                    fontWeight: _examType == 'UAS' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _academicYearController,
            decoration: const InputDecoration(
              labelText: 'Tahun Ajaran',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v!.trim().isEmpty ? 'Tahun ajaran harus diisi!' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Deskripsi / Petunjuk Ujian',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _selectDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _startDate != null && _endDate != null
                        ? 'Rentang: ${ExamPdfGenerator.formatIndonesianDate(_startDate!, includeDayName: false)} - ${ExamPdfGenerator.formatIndonesianDate(_endDate!, includeDayName: false)}'
                        : 'Pilih Rentang Tanggal Ujian',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Step 2: Sesi
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Langkah 2: Konfigurasi Sesi Ujian', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _sessionNameController,
                decoration: const InputDecoration(labelText: 'Nama Sesi (e.g. Sesi 1)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () async {
                final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (time != null) setState(() => _startTime = time);
              },
              child: Text(_startTime == null ? 'Mulai' : _startTime!.format(context)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (time != null) setState(() => _endTime = time);
              },
              child: Text(_endTime == null ? 'Selesai' : _endTime!.format(context)),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _addSession,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
              child: const Text('Tambah'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: _sessions.isEmpty
              ? const Center(child: Text('Belum ada sesi ditambahkan.'))
              : ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (ctx, idx) {
                    final s = _sessions[idx];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${idx + 1}')),
                        title: Text(s['name']),
                        subtitle: Text('Waktu: ${s['startTime']} - ${s['endTime']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => setState(() => _sessions.removeAt(idx)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Helper: compact toggle button for seating arrangement mode
  Widget _arrangeToggleBtn({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: active ? Colors.white : const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 3: Timetable
  Widget _buildStep3() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _adminUserService.streamClasses(widget.schoolId),
      builder: (context, classesSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _adminUserService.streamSubjects(widget.schoolId),
          builder: (context, subjectsSnap) {
            return StreamBuilder<List<Teacher>>(
              stream: _adminUserService.streamTeachers(widget.schoolId),
              builder: (context, teachersSnap) {
                // Wait until classes stream has real data before resolving class names
                // This prevents class UIDs from flashing before stream loads
                final bool classesReady = classesSnap.hasData;
                final classes = classesSnap.data ?? [];
                final subjects = subjectsSnap.data ?? [];
                final teachers = teachersSnap.data ?? [];

                // Group timetable entries by subjectId
                // Only resolve class names when classes data is available
                final Map<String, Map<String, dynamic>> groupedTimetable = {};
                if (classesReady) {
                  for (var entry in _timetable) {
                    final subId = entry['subjectId'] as String;
                    if (!groupedTimetable.containsKey(subId)) {
                      groupedTimetable[subId] = {
                        'subjectId': subId,
                        'subjectName': entry['subjectName'],
                        'teacherName': entry['teacherName'],
                        'classes': <String>[],
                      };
                    }
                    final cid = entry['classId'] as String;
                    final classDoc = classes.firstWhere((c) => c['id'] == cid, orElse: () => {});
                    final className = classDoc['name'] as String? ?? cid;
                    groupedTimetable[subId]!['classes'].add(className);
                  }
                }
                final groupedList = groupedTimetable.values.toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Langkah 3: Jadwal Mapel per Kelas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Input Settings
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                    value: _selectedSubjectId,
                                    decoration: const InputDecoration(labelText: 'Pilih Mata Pelajaran', border: OutlineInputBorder()),
                                    items: subjects.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String))).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedSubjectId = val;
                                        _selectedTeacherId = null; // Reset teacher selection since subject changed
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Pilih Kelas (Bisa pilih lebih dari satu):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                                      if (classes.isNotEmpty)
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              final allIds = classes.map((c) => c['id'] as String).toList();
                                              final allSelected = allIds.every((id) => _selectedClassIds.contains(id));
                                              if (allSelected) {
                                                _selectedClassIds.clear();
                                              } else {
                                                _selectedClassIds.clear();
                                                _selectedClassIds.addAll(allIds);
                                              }
                                            });
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Checkbox(
                                                  value: classes.isNotEmpty && classes.every((c) => _selectedClassIds.contains(c['id'])),
                                                  activeColor: const Color(0xFF4F46E5),
                                                  onChanged: (val) {
                                                    setState(() {
                                                      final allIds = classes.map((c) => c['id'] as String).toList();
                                                      if (val == true) {
                                                        _selectedClassIds.clear();
                                                        _selectedClassIds.addAll(allIds);
                                                      } else {
                                                        _selectedClassIds.clear();
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Text(
                                                'Pilih Semua Kelas',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  classes.isEmpty
                                      ? const Text('Belum ada kelas terdaftar.', style: TextStyle(color: Colors.red))
                                      : Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: classes.map((c) {
                                              final cid = c['id'] as String;
                                              final name = c['name'] as String;
                                              final isSelected = _selectedClassIds.contains(cid);
                                              return FilterChip(
                                                label: Text(name),
                                                selected: isSelected,
                                                selectedColor: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                                                checkmarkColor: const Color(0xFF4F46E5),
                                                labelStyle: TextStyle(
                                                  color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                ),
                                                onSelected: (selected) {
                                                  setState(() {
                                                    if (selected) {
                                                      _selectedClassIds.add(cid);
                                                    } else {
                                                      _selectedClassIds.remove(cid);
                                                    }
                                                  });
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String?>(
                                    value: _selectedTeacherId,
                                    decoration: const InputDecoration(labelText: 'Guru Pembuat Soal', border: OutlineInputBorder()),
                                    items: () {
                                      if (_selectedSubjectId == null) {
                                        return [
                                          const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('Pilih mata pelajaran dahulu'),
                                          )
                                        ];
                                      }
                                      final selectedSub = subjects.firstWhere((s) => s['id'] == _selectedSubjectId, orElse: () => {});
                                      final subName = selectedSub['name'] as String?;
                                      if (subName == null) {
                                        return [
                                          const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('Mapel tidak ditemukan'),
                                          )
                                        ];
                                      }
                                      final filtered = teachers.where((t) => t.subjects.contains(subName)).toList();
                                      if (filtered.isEmpty) {
                                        return [
                                          const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('Tidak ada guru pengampu mapel ini'),
                                          )
                                        ];
                                      }
                                      return filtered.map((t) => DropdownMenuItem<String?>(value: t.id, child: Text(t.displayName))).toList();
                                    }(),
                                    onChanged: (val) => setState(() => _selectedTeacherId = val),
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _addTimetableEntry(subjects, teachers, classes),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Tambah Jadwal Mapel', style: TextStyle(fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4F46E5),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const VerticalDivider(width: 32, thickness: 1, color: Color(0xFFE2E8F0)),
                          // Right Column: Grouped Timetable List
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Jadwal Terdaftar:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: groupedList.isEmpty
                                      ? const Center(child: Text('Belum ada jadwal mapel yang ditambahkan.'))
                                      : ListView.builder(
                                          itemCount: groupedList.length,
                                          itemBuilder: (ctx, idx) {
                                            final item = groupedList[idx];
                                            final classesList = (item['classes'] as List<String>)..sort();
                                            return Card(
                                              margin: const EdgeInsets.only(bottom: 8),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                              ),
                                              child: ListTile(
                                                title: Text(
                                                  item['subjectName'] as String,
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                subtitle: Padding(
                                                  padding: const EdgeInsets.only(top: 4.0),
                                                  child: Text(
                                                    'Guru: ${item['teacherName']}\nKelas: ${classesList.join(', ')}',
                                                    style: const TextStyle(height: 1.3),
                                                  ),
                                                ),
                                                trailing: IconButton(
                                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                                  onPressed: () {
                                                    setState(() {
                                                      _timetable.removeWhere((t) => t['subjectId'] == item['subjectId']);
                                                    });
                                                  },
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // Step 4: Ruangan
  Widget _buildStep4() {
    void showRoomDialog({Map<String, dynamic>? existing, int? index}) {
      final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
      final capCtrl = TextEditingController(text: existing != null ? '${(existing['capacity'] as num?)?.toInt() ?? ''}' : '');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(existing == null ? 'Tambah Ruangan' : 'Edit Ruangan',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Ruangan',
                  hintText: 'Contoh: Ruang A1',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: capCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kapasitas Kursi',
                  hintText: 'Contoh: 30',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event_seat_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final cap = int.tryParse(capCtrl.text.trim());
                if (name.isEmpty || cap == null || cap <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Nama dan kapasitas harus diisi dengan benar!'), backgroundColor: Colors.red),
                  );
                  return;
                }
                setState(() {
                  if (existing == null) {
                    _rooms.add({'id': 'local_${DateTime.now().millisecondsSinceEpoch}', 'name': name, 'capacity': cap});
                  } else {
                    _rooms[index!] = {...existing, 'name': name, 'capacity': cap};
                  }
                });
                Navigator.pop(ctx);
                _autoSaveDraft();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(existing == null ? 'Tambah' : 'Simpan'),
            ),
          ],
        ),
      );
    }

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final total = _rooms.fold<int>(0, (sum, r) => sum + ((r['capacity'] as num?)?.toInt() ?? 0));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Langkah 4: Ruangan Ujian',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Tambahkan ruangan yang akan digunakan untuk ujian ini.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => showRoomDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tambah Ruangan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_rooms.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_seat_rounded, color: Color(0xFF4F46E5), size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Total ${_rooms.length} ruangan  •  $total kursi tersedia',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4F46E5),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _rooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.meeting_room_outlined,
                              size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text('Belum ada ruangan ditambahkan.',
                              style: TextStyle(color: Color(0xFF94A3B8))),
                          const SizedBox(height: 4),
                          const Text('Klik "Tambah Ruangan" untuk mulai.',
                              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _rooms.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final r = _rooms[idx];
                        final cap = (r['capacity'] as num?)?.toInt() ?? 0;
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.meeting_room_outlined,
                                  color: Color(0xFF4F46E5), size: 20),
                            ),
                            title: Text(
                              r['name'] as String? ?? '-',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '$cap kursi',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      color: Color(0xFF4F46E5), size: 20),
                                  tooltip: 'Edit',
                                  onPressed: () => showRoomDialog(existing: r, index: idx),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: Colors.red, size: 20),
                                  tooltip: 'Hapus',
                                  onPressed: () {
                                    setState(() => _rooms.removeAt(idx));
                                    _autoSaveDraft();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // Step 5: Alokasi Murid ke Ruangan
  // studentIds are stored as an array field in each class document.
  // Helper reads it directly from the class data already fetched in the StreamBuilder.
  int _studentCountForClass(Map<String, dynamic> classData) {
    final raw = classData['studentIds'];
    if (raw is List) return raw.length;
    return 0;
  }

  Widget _buildStep5() {
    const classColors = [
      Color(0xFF4F46E5), Color(0xFF10B981), Color(0xFFF59E0B),
      Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF06B6D4),
      Color(0xFFEC4899), Color(0xFF14B8A6),
    ];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('classes')
          .orderBy('name')
          .snapshots(),
      builder: (context, classSnap) {
        final classes = classSnap.data?.docs
                .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
                .toList() ??
            [];

        return StatefulBuilder(
          builder: (context, setLocal) {
            final selectedRoom = _rooms.isEmpty
                ? null
                : _rooms.firstWhere(
                    (r) => r['id'] == _selectedRoomId,
                    orElse: () => {},
                  );
                final roomCapacity =
                    (selectedRoom?['capacity'] as num?)?.toInt() ?? 0;
                final assignments =
                    _selectedRoomId != null ? (_roomAssignments[_selectedRoomId!] ?? []) : <Map<String, dynamic>>[];
                final totalAssigned =
                    assignments.fold<int>(0, (s, a) => s + ((a['count'] as num?)?.toInt() ?? 0));

                // Per-class local add state
                // classId -> { 'mode': 'all'|'count', 'count': int }
                for (final c in classes) {
                  _addState.putIfAbsent(
                    c['id'] as String,
                    () => {'mode': 'all', 'count': 1},
                  );
                }

                // ── Mini seating chart ──
                Widget buildMiniChart() {
                  if (selectedRoom == null || selectedRoom.isEmpty) {
                    return Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Text('Pilih ruangan untuk melihat denah',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      ),
                    );
                  }
                  // Retrieve or set default layout parameters for the selected room
                  final layoutState = _addState.putIfAbsent(
                    'layout_${selectedRoom['id']}',
                    // Defaults: 2 columns per group (Meja Rapat), 4 total columns (Total Kolom)
                    () => {'deskPairs': 2, 'colsPerPair': 4, 'arrange': 'normal'},
                  );
                  layoutState.putIfAbsent('arrange', () => 'normal');
                  final int deskPairs = layoutState['deskPairs'] as int;
                  final int colsPerPair = layoutState['colsPerPair'] as int;
                  final String arrangeMode = layoutState['arrange'] as String;

                  final int totalColumns = colsPerPair;
                  final int calculatedRows = (roomCapacity / totalColumns).ceil();

                  // Build flat list of colored tokens from assignments
                  final List<Color?> classTokens = [];
                  for (int i = 0; i < assignments.length; i++) {
                    final cnt = (assignments[i]['count'] as num?)?.toInt() ?? 0;
                    final color = classColors[i % classColors.length];
                    for (int j = 0; j < cnt; j++) {
                      classTokens.add(color);
                    }
                  }

                  // Build seats based on arrangement mode
                  final seats = List<Color?>.filled(roomCapacity, null);
                  if (arrangeMode == 'acak') {
                    // Shuffle randomly
                    final shuffled = List<Color?>.from(classTokens)..shuffle();
                    for (int i = 0; i < shuffled.length && i < roomCapacity; i++) {
                      seats[i] = shuffled[i];
                    }
                  } else if (arrangeMode == 'zigzag') {
                    // Zigzag: interleave students from each class column by column across rows
                    // Build per-class queues
                    final List<List<Color>> queues = [];
                    for (int i = 0; i < assignments.length; i++) {
                      final cnt = (assignments[i]['count'] as num?)?.toInt() ?? 0;
                      final color = classColors[i % classColors.length];
                      queues.add(List.filled(cnt, color));
                    }
                    // Flatten queues in round-robin per column
                    // Each column gets one student per class cycle
                    int qi = 0;
                    final List<int> qIdx = List.filled(queues.length, 0);
                    for (int seat = 0; seat < roomCapacity; seat++) {
                      // Find next class with remaining students
                      int tried = 0;
                      while (tried < queues.length) {
                        final q = qi % queues.length;
                        if (qIdx[q] < queues[q].length) {
                          seats[seat] = queues[q][qIdx[q]++];
                          qi = q + 1;
                          break;
                        }
                        qi++;
                        tried++;
                      }
                      if (tried == queues.length) break; // all queues exhausted
                    }
                  } else {
                    // Normal: sequential fill
                    int seatIdx = 0;
                    for (int i = 0; i < assignments.length && seatIdx < roomCapacity; i++) {
                      final cnt = (assignments[i]['count'] as num?)?.toInt() ?? 0;
                      final color = classColors[i % classColors.length];
                      for (int j = 0; j < cnt && seatIdx < roomCapacity; j++) {
                        seats[seatIdx++] = color;
                      }
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selectedRoom['name'] as String? ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4F46E5)),
                          ),
                          Text(
                            '$totalAssigned / $roomCapacity kursi',
                            style: TextStyle(
                              fontSize: 11,
                              color: totalAssigned > roomCapacity
                                  ? Colors.red
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Layout Controls
                      Row(
                        children: [
                          Expanded(
                             child: DropdownButtonFormField<int>(
                              value: deskPairs,
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: 'Pasang',
                                labelStyle: TextStyle(fontSize: 9),
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontSize: 11, color: Colors.black),
                              items: List.generate(3, (i) => i + 1).map((val) {
                                return DropdownMenuItem(value: val, child: Text('$val Pasang', style: const TextStyle(fontSize: 11)));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setLocal(() {
                                    layoutState['deskPairs'] = val;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: colsPerPair,
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: 'Total Kolom',
                                labelStyle: TextStyle(fontSize: 9),
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontSize: 11, color: Colors.black),
                              items: List.generate(10, (i) => i + 1).map((val) {
                                return DropdownMenuItem(value: val, child: Text('$val Kolom', style: const TextStyle(fontSize: 11)));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setLocal(() {
                                    layoutState['colsPerPair'] = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Arrangement Mode Toggle
                      Row(
                        children: [
                          _arrangeToggleBtn(
                            label: 'Normal',
                            icon: Icons.format_list_numbered_rounded,
                            active: arrangeMode == 'normal',
                            onTap: () => setLocal(() => layoutState['arrange'] = 'normal'),
                          ),
                          const SizedBox(width: 6),
                          _arrangeToggleBtn(
                            label: 'Zigzag',
                            icon: Icons.swap_horiz_rounded,
                            active: arrangeMode == 'zigzag',
                            onTap: () => setLocal(() => layoutState['arrange'] = 'zigzag'),
                          ),
                          const SizedBox(width: 6),
                          _arrangeToggleBtn(
                            label: 'Acak',
                            icon: Icons.shuffle_rounded,
                            active: arrangeMode == 'acak',
                            onTap: () => setLocal(() => layoutState['arrange'] = 'acak'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pola Grid: $totalColumns Kolom  •  Baris: $calculatedRows  •  Urutan: ${arrangeMode[0].toUpperCase()}${arrangeMode.substring(1)}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      if (totalAssigned > roomCapacity)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: const Text(
                            '⚠️ Murid melebihi kapasitas!',
                            style: TextStyle(color: Color(0xFFB91C1C), fontSize: 10),
                          ),
                        ),
                      // Interactive Seat Map Grid with Scrolling
                      // Seat Map Grid fitted inside the white background container
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Total width inside the container padding is constraints.maxWidth
                              final double availableWidth = constraints.maxWidth;
                              // Calculate how many gap spacers we will have in a row
                              final int totalGaps = (totalColumns / deskPairs).floor();
                              // availableWidth = (totalColumns * seatWidth) + (totalColumns * 4px seatMargin) + (totalGaps * 14px gapSize)
                              // Solve for seatWidth:
                              final double totalGapWidth = totalGaps * 14.0;
                              final double remainingWidth = availableWidth - totalGapWidth - 8.0; // 8px safety padding
                              // Each seat has 4px margin total (2px left, 2px right)
                              final double seatWidth = (remainingWidth / totalColumns) - 4.0;
                              // Clamp seat width with no upper limit (up to 72.0) to fill the width
                              final double dynamicSeatSize = seatWidth.clamp(16.0, 72.0);

                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const ClampingScrollPhysics(),
                                itemCount: calculatedRows,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, rowIdx) {
                                  final rowChildren = <Widget>[];
                                  for (int colIdx = 0; colIdx < totalColumns; colIdx++) {
                                    if (colIdx > 0 && colIdx % deskPairs == 0) {
                                      rowChildren.add(const SizedBox(width: 14));
                                    }

                                    final seatIndex = (rowIdx * totalColumns) + colIdx;
                                    if (seatIndex >= roomCapacity) {
                                      rowChildren.add(
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 2),
                                          child: SizedBox(width: dynamicSeatSize, height: dynamicSeatSize),
                                        ),
                                      );
                                      continue;
                                    }

                                    final seatColor = seats[seatIndex];
                                    rowChildren.add(
                                      Container(
                                        width: dynamicSeatSize,
                                        height: dynamicSeatSize,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: seatColor != null
                                              ? seatColor.withValues(alpha: 0.85)
                                              : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: seatColor != null
                                                ? seatColor.withValues(alpha: 0.95)
                                                : const Color(0xFFCBD5E1),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(
                                          '${seatIndex + 1}',
                                          style: TextStyle(
                                            fontSize: (dynamicSeatSize * 0.32).clamp(7.0, 15.0),
                                            fontWeight: FontWeight.bold,
                                            color: seatColor != null ? Colors.white : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: rowChildren,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      // Legend
                      if (assignments.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: assignments.asMap().entries.map((e) {
                            final color = classColors[e.key % classColors.length];
                            final cnt = (e.value['count'] as num?)?.toInt() ?? 0;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                                const SizedBox(width: 4),
                                Text('${e.value['className']} ($cnt)', style: const TextStyle(fontSize: 9, color: Color(0xFF475569))),
                              ],
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Column 1: Room List ──
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Langkah 5: Alokasi Murid',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Pilih ruangan untuk alokasi.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          const SizedBox(height: 16),
                          if (_rooms.isEmpty)
                            const Center(
                              child: Text('Belum ada ruangan.\nTambah di Langkah 4.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                            )
                          else
                            Expanded(
                              child: ListView.separated(
                                itemCount: _rooms.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (_, idx) {
                                  final r = _rooms[idx];
                                  final rid = r['id'] as String;
                                  final isSelected = _selectedRoomId == rid;
                                  final asgn = _roomAssignments[rid] ?? [];
                                  final total = asgn.fold<int>(0, (s, a) => s + ((a['count'] as num?)?.toInt() ?? 0));
                                  final cap = (r['capacity'] as num?)?.toInt() ?? 0;
                                  return GestureDetector(
                                    onTap: () => setState(() => _selectedRoomId = rid),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                          width: isSelected ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.meeting_room_outlined,
                                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                                              size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(r['name'] as String? ?? '-',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                        color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF0F172A))),
                                                Text('$total / $cap kursi', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                              ],
                                            ),
                                          ),
                                          // Filled indicator
                                          Container(
                                            width: 24,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(2),
                                              color: const Color(0xFFE2E8F0),
                                            ),
                                            child: FractionallySizedBox(
                                              alignment: Alignment.centerLeft,
                                              widthFactor: cap > 0 ? (total / cap).clamp(0.0, 1.0) : 0,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(2),
                                                  color: total > cap ? Colors.red : const Color(0xFF4F46E5),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Divider 1
                    Container(width: 1, color: const Color(0xFFE2E8F0)),
                    const SizedBox(width: 16),

                    // ── Column 2: Seating Chart ──
                    SizedBox(
                      width: 380,
                      child: buildMiniChart(),
                    ),
                    const SizedBox(width: 16),
                    // Divider 2
                    Container(width: 1, color: const Color(0xFFE2E8F0)),
                    const SizedBox(width: 16),
                    // ── Right: Class Assignment ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedRoomId == null
                                ? 'Pilih ruangan terlebih dahulu'
                                : 'Tetapkan kelas ke "${selectedRoom?['name'] ?? ''}"',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _selectedRoomId == null
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_back_rounded, color: Color(0xFFCBD5E1), size: 40),
                                        SizedBox(height: 8),
                                        Text('Pilih ruangan di sebelah kiri\nuntuk mulai mengalokasikan murid.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                                      ],
                                    ),
                                  )
                                : classes.isEmpty
                                    ? const Center(child: Text('Belum ada kelas terdaftar.', style: TextStyle(color: Color(0xFF94A3B8))))
                                    : ListView.separated(
                                        itemCount: classes.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        itemBuilder: (_, ci) {
                                          final cls = classes[ci];
                                          final cid = cls['id'] as String;
                                          final cname = cls['name'] as String? ?? '-';
                                          final totalStudents = _studentCountForClass(cls);
                                          final existingIdx = _roomAssignments[_selectedRoomId]?.indexWhere((a) => a['classId'] == cid) ?? -1;
                                          final existing = existingIdx >= 0 ? _roomAssignments[_selectedRoomId]![existingIdx] : null;

                                          // Calculate total students allocated to OTHER rooms
                                          int allocatedElsewhere = 0;
                                          _roomAssignments.forEach((roomId, list) {
                                            if (roomId != _selectedRoomId) {
                                              final found = list.firstWhere((a) => a['classId'] == cid, orElse: () => {});
                                              if (found.isNotEmpty) {
                                                allocatedElsewhere += (found['count'] as num).toInt();
                                              }
                                            }
                                          });

                                          // Active count allocated in THIS selected room
                                          final int currentAssignedCount = existing != null ? (existing['count'] as num).toInt() : 0;

                                          // remainingAvailable is what is left from total students after subtracting other rooms AND this room's count
                                          final int remainingAvailable = (totalStudents - allocatedElsewhere - currentAssignedCount).clamp(0, totalStudents);

                                          return Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: currentAssignedCount > 0 ? const Color(0xFFF0FDF4) : Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: currentAssignedCount > 0 ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(7),
                                                      decoration: BoxDecoration(
                                                        color: classColors[ci % classColors.length].withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Icon(Icons.class_outlined, color: classColors[ci % classColors.length], size: 16),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(cname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                                          Text(
                                                            'Tersedia: $remainingAvailable dari $totalStudents murid terdaftar',
                                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (currentAssignedCount > 0) ...[
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFDCFCE7),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          '$currentAssignedCount murid dialokasikan',
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      IconButton(
                                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                                        tooltip: 'Hapus alokasi',
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(),
                                                        onPressed: () {
                                                          setState(() {
                                                            _roomAssignments[_selectedRoomId!]!.removeAt(existingIdx);
                                                            if (_roomAssignments[_selectedRoomId!]!.isEmpty) {
                                                              _roomAssignments.remove(_selectedRoomId!);
                                                            }
                                                          });
                                                          _autoSaveDraft();
                                                        },
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                // Mode selector + action
                                                Row(
                                                  children: [
                                                    // Toggle: Semua Murid
                                                    GestureDetector(
                                                      onTap: () {
                                                        final totalToAdd = remainingAvailable + currentAssignedCount;
                                                        if (totalToAdd <= 0) return;
                                                        setState(() {
                                                          _roomAssignments.putIfAbsent(_selectedRoomId!, () => []);
                                                          final list = _roomAssignments[_selectedRoomId!]!;
                                                          final idx = list.indexWhere((a) => a['classId'] == cid);
                                                          final entry = {
                                                            'classId': cid,
                                                            'className': cname,
                                                            'count': totalToAdd,
                                                            'isAll': true,
                                                          };
                                                          if (idx >= 0) {
                                                            list[idx] = entry;
                                                          } else {
                                                            list.add(entry);
                                                          }
                                                        });
                                                        _autoSaveDraft();
                                                      },
                                                      child: AnimatedContainer(
                                                        duration: const Duration(milliseconds: 150),
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                        decoration: BoxDecoration(
                                                          color: (existing != null && existing['isAll'] == true)
                                                              ? const Color(0xFF4F46E5)
                                                              : const Color(0xFFF1F5F9),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          'Semua Murid',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                            color: (existing != null && existing['isAll'] == true)
                                                                ? Colors.white
                                                                : const Color(0xFF64748B),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Decrement Counter Button
                                                    InkWell(
                                                      onTap: () {
                                                        if (currentAssignedCount <= 0) return;
                                                        setState(() {
                                                          final list = _roomAssignments[_selectedRoomId!]!;
                                                          final newCount = currentAssignedCount - 1;
                                                          if (newCount <= 0) {
                                                            list.removeAt(existingIdx);
                                                            if (list.isEmpty) {
                                                              _roomAssignments.remove(_selectedRoomId!);
                                                            }
                                                          } else {
                                                            list[existingIdx] = {
                                                              'classId': cid,
                                                              'className': cname,
                                                              'count': newCount,
                                                              'isAll': false,
                                                            };
                                                          }
                                                        });
                                                        _autoSaveDraft();
                                                      },
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Container(
                                                        width: 28, height: 28,
                                                        decoration: BoxDecoration(
                                                          color: currentAssignedCount > 0 ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
                                                          border: Border.all(color: currentAssignedCount > 0 ? const Color(0xFFC7D2FE) : Colors.transparent),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Icon(
                                                          Icons.remove_rounded,
                                                          size: 14,
                                                          color: currentAssignedCount > 0 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 40,
                                                      child: Text(
                                                        '$currentAssignedCount',
                                                        textAlign: TextAlign.center,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                          color: Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                    ),
                                                    // Increment Counter Button
                                                    InkWell(
                                                      onTap: () {
                                                        if (remainingAvailable <= 0) return;
                                                        setState(() {
                                                          _roomAssignments.putIfAbsent(_selectedRoomId!, () => []);
                                                          final list = _roomAssignments[_selectedRoomId!]!;
                                                          final idx = list.indexWhere((a) => a['classId'] == cid);
                                                          final newCount = currentAssignedCount + 1;
                                                          final entry = {
                                                            'classId': cid,
                                                            'className': cname,
                                                            'count': newCount,
                                                            'isAll': false,
                                                          };
                                                          if (idx >= 0) {
                                                            list[idx] = entry;
                                                          } else {
                                                            list.add(entry);
                                                          }
                                                        });
                                                        _autoSaveDraft();
                                                      },
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Container(
                                                        width: 28, height: 28,
                                                        decoration: BoxDecoration(
                                                          color: remainingAvailable > 0
                                                              ? const Color(0xFFEEF2FF)
                                                              : const Color(0xFFF1F5F9),
                                                          border: Border.all(
                                                            color: remainingAvailable > 0
                                                                ? const Color(0xFFC7D2FE)
                                                                : Colors.transparent,
                                                          ),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Icon(
                                                          Icons.add_rounded,
                                                          size: 14,
                                                          color: remainingAvailable > 0
                                                              ? const Color(0xFF4F46E5)
                                                              : const Color(0xFF94A3B8),
                                                        ),
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
                    ),
                  ],
                );
              },
            );
          },
        );
      }

  // ── Helpers for Step 6 ──────────────────────────────────────────────────

  /// Returns a list of exam dates between _startDate and _endDate inclusive.
  List<DateTime> _examDays() {
    if (_startDate == null || _endDate == null) return [];
    final days = <DateTime>[];
    DateTime cur = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
    while (!cur.isAfter(end)) {
      days.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return days;
  }

  /// Unique subjects from _timetable
  List<Map<String, String>> _uniqueSubjects() {
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final t in _timetable) {
      final sid = t['subjectId'] as String? ?? '';
      if (seen.add(sid)) {
        result.add({'id': sid, 'name': t['subjectName'] as String? ?? sid});
      }
    }
    return result;
  }

  /// Auto-generate: scatter all subjects randomly across (day × session) slots
  void _autoGenerateSchedule() {
    final days = _examDays();
    if (days.isEmpty || _sessions.isEmpty) return;
    final subjects = _uniqueSubjects();
    // Use a new Random each call so re-clicking always produces a different order
    final rng = Random();
    final subsCopy = List<Map<String, String>>.from(subjects)..shuffle(rng);
    _scheduleGrid.clear();
    int idx = 0;
    outer:
    for (int d = 0; d < days.length; d++) {
      for (int s = 0; s < _sessions.length; s++) {
        if (idx >= subsCopy.length) break outer;
        _scheduleGrid['day_${d}_session_$s'] = subsCopy[idx]['id']!;
        idx++;
      }
    }
    setState(() {});
    _autoSaveDraft();
  }

  // Step 6: Jadwal Mapel per Sesi per Hari
  Widget _buildStep6() {
    final days = _examDays();
    final subjects = _uniqueSubjects();
    // Which subjectIds are already placed in schedule
    final placedIds = _scheduleGrid.values.toSet();
    final unplaced = subjects.where((s) => !placedIds.contains(s['id'])).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Langkah 6: Jadwal Ujian per Sesi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Tentukan mapel yang diujikan di setiap sesi dan hari.', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: subjects.isEmpty
                  ? null
                  : () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Generate Otomatis?'),
                          content: const Text(
                            'Semua mapel akan diacak dan dimasukkan ke sesi secara otomatis. Jadwal yang sudah ada akan ditimpa.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _autoGenerateSchedule();
                              },
                              child: const Text('Generate'),
                            ),
                          ],
                        ),
                      );
                    },
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: const Text('Generate Otomatis', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Unplaced mapel chips row
        if (subjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9C3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE047)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFCA8A04)),
                SizedBox(width: 8),
                Expanded(child: Text('Belum ada mapel. Kembali ke Step 3 dan tambahkan jadwal mapel.', style: TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unplaced.isEmpty ? '✅ Semua mapel sudah terjadwal' : '📚 Mapel belum dijadwalkan (${unplaced.length}):',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: unplaced.isEmpty ? const Color(0xFF059669) : const Color(0xFF475569),
                  ),
                ),
                if (unplaced.isNotEmpty) ...
                  [
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: unplaced.map((s) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Text(s['name']!, style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8), fontWeight: FontWeight.w600)),
                        );
                      }).toList(),
                    ),
                  ]
              ],
            ),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: days.isEmpty
              ? const Center(child: Text('Belum ada tanggal pelaksanaan. Kembali ke Step 1.'))
              : _sessions.isEmpty
                  ? const Center(child: Text('Belum ada sesi. Kembali ke Step 2.'))
                  : ListView.builder(
                      itemCount: days.length,
                      itemBuilder: (ctx, dayIdx) {
                        final day = days[dayIdx];
                        final dayLabel = ExamPdfGenerator.formatIndonesianDate(day);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4F46E5).withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Day header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4F46E5),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white70),
                                    const SizedBox(width: 8),
                                    Text(
                                      dayLabel,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              // Sessions rows
                              ...List.generate(_sessions.length, (sIdx) {
                                final session = _sessions[sIdx];
                                final gridKey = 'day_${dayIdx}_session_$sIdx';
                                final assignedId = _scheduleGrid[gridKey];
                                final assignedSub = assignedId != null
                                    ? subjects.firstWhere((s) => s['id'] == assignedId, orElse: () => {'id': '', 'name': '?'})
                                    : null;
                                // Available: all subjects NOT placed elsewhere except the one assigned here
                                final availableSubs = subjects.where((s) {
                                  if (s['id'] == assignedId) return true; // keep current
                                  return !placedIds.contains(s['id']); // only unplaced
                                }).toList();

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: sIdx < _sessions.length - 1
                                          ? const BorderSide(color: Color(0xFFF1F5F9))
                                          : BorderSide.none,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Session info
                                      SizedBox(
                                        width: 140,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              session['name'] as String? ?? 'Sesi ${sIdx + 1}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                            Text(
                                              '${session['startTime']} - ${session['endTime']}',
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Assigned subject chip or dropdown
                                      Expanded(
                                        child: assignedSub != null
                                            ? Row(
                                                children: [
                                                  Expanded(
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFECFDF5),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFF6EE7B7)),
                                                      ),
                                                      child: Text(
                                                        assignedSub['name']!,
                                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  GestureDetector(
                                                    onTap: () {
                                                      setState(() => _scheduleGrid.remove(gridKey));
                                                      _autoSaveDraft();
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFEE2E2),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : DropdownButtonHideUnderline(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF8FAFC),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                                  ),
                                                  child: DropdownButton<String>(
                                                    value: null,
                                                    isExpanded: true,
                                                    hint: Row(
                                                      children: [
                                                        Icon(Icons.add_circle_outline_rounded, size: 14, color: availableSubs.isEmpty ? Colors.grey : const Color(0xFF4F46E5)),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          availableSubs.isEmpty ? 'Semua mapel sudah terjadwal' : 'Pilih Mapel',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: availableSubs.isEmpty ? Colors.grey : const Color(0xFF4F46E5),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    items: availableSubs.map((s) {
                                                      return DropdownMenuItem<String>(
                                                        value: s['id'],
                                                        child: Text(s['name']!, style: const TextStyle(fontSize: 12)),
                                                      );
                                                    }).toList(),
                                                    onChanged: availableSubs.isEmpty
                                                        ? null
                                                        : (val) {
                                                            if (val != null) {
                                                              setState(() => _scheduleGrid[gridKey] = val);
                                                              _autoSaveDraft();
                                                            }
                                                          },
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // Step 7: Pengawas Ruangan per Sesi per Hari
  Widget _buildStep7() {
    return StreamBuilder<List<Teacher>>(
      stream: _adminUserService.streamTeachers(widget.schoolId),
      builder: (context, teachersSnap) {
        final teachers = teachersSnap.data ?? [];
        final days = _examDays();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Langkah 7: Pengawas Ruangan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Tentukan pengawas untuk setiap sesi per hari.', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: teachers.isEmpty || days.isEmpty || _sessions.isEmpty
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Generate Otomatis?'),
                              content: const Text(
                                'Pengawas akan diacak dan ditugaskan ke setiap sesi secara otomatis. Penugasan yang sudah ada akan ditimpa.',
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _autoGenerateProctors(teachers);
                                  },
                                  child: const Text('Generate'),
                                ),
                              ],
                            ),
                          );
                        },
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Generate Otomatis', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Summary bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.supervisor_account_rounded, size: 16, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 8),
                  Text(
                    teachers.isEmpty
                        ? 'Belum ada guru terdaftar.'
                        : '${teachers.length} guru tersedia  •  ${_proctorGrid.length} sesi sudah ada pengawas  •  ${days.length * _sessions.length} total sesi',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: days.isEmpty
                  ? const Center(child: Text('Belum ada tanggal pelaksanaan. Kembali ke Step 1.'))
                  : _sessions.isEmpty
                      ? const Center(child: Text('Belum ada sesi. Kembali ke Step 2.'))
                      : teachers.isEmpty
                          ? const Center(child: Text('Belum ada guru terdaftar di sekolah ini.'))
                          : ListView.builder(
                              itemCount: days.length,
                              itemBuilder: (ctx, dayIdx) {
                                final day = days[dayIdx];
                                final dayLabel = ExamPdfGenerator.formatIndonesianDate(day);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF7C3AED).withValues(alpha: 0.04),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Day header
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF7C3AED),
                                          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white70),
                                            const SizedBox(width: 8),
                                            Text(
                                              dayLabel,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Session rows
                                      ...List.generate(_sessions.length, (sIdx) {
                                        final session = _sessions[sIdx];
                                        final gridKey = 'day_${dayIdx}_session_$sIdx';
                                        final assignedTeacherId = _proctorGrid[gridKey];
                                        final assignedTeacher = assignedTeacherId != null
                                            ? teachers.firstWhere((t) => t.id == assignedTeacherId, orElse: () => Teacher(id: '', displayName: '?', subjects: [], schoolId: '', gender: 'M', nip: '', disabled: false, archived: false, createdAt: DateTime.now(), updatedAt: DateTime.now()))
                                            : null;
                                        // Subject scheduled for this slot (from step 6)
                                        final scheduledSubjectId = _scheduleGrid[gridKey];
                                        final scheduledSubjectName = scheduledSubjectId != null
                                            ? (_timetable.firstWhere(
                                                (t) => t['subjectId'] == scheduledSubjectId,
                                                orElse: () => {'subjectName': scheduledSubjectId},
                                              )['subjectName'] as String?)
                                            : null;

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: sIdx < _sessions.length - 1
                                                  ? const BorderSide(color: Color(0xFFF1F5F9))
                                                  : BorderSide.none,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              // Session info
                                              SizedBox(
                                                width: 160,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      session['name'] as String? ?? 'Sesi ${sIdx + 1}',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                    ),
                                                    Text(
                                                      '${session['startTime']} - ${session['endTime']}',
                                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                                    ),
                                                    if (scheduledSubjectName != null)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 3),
                                                        child: Text(
                                                          '📖 $scheduledSubjectName',
                                                          style: const TextStyle(fontSize: 10, color: Color(0xFF4F46E5), fontStyle: FontStyle.italic),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // Proctor assignment
                                              Expanded(
                                                child: assignedTeacher != null && assignedTeacher.id.isNotEmpty
                                                    ? Row(
                                                        children: [
                                                          const Icon(Icons.person_rounded, size: 16, color: Color(0xFF7C3AED)),
                                                          const SizedBox(width: 6),
                                                          Expanded(
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFF5F3FF),
                                                                borderRadius: BorderRadius.circular(6),
                                                                border: Border.all(color: const Color(0xFFC4B5FD)),
                                                              ),
                                                              child: Text(
                                                                assignedTeacher.displayName,
                                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5B21B6)),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 6),
                                                          GestureDetector(
                                                            onTap: () {
                                                              setState(() => _proctorGrid.remove(gridKey));
                                                              _autoSaveDraft();
                                                            },
                                                            child: Container(
                                                              padding: const EdgeInsets.all(4),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFFEE2E2),
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    : DropdownButtonHideUnderline(
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFF8FAFC),
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                                          ),
                                                          child: DropdownButton<String>(
                                                            value: null,
                                                            isExpanded: true,
                                                            hint: const Row(
                                                              children: [
                                                                Icon(Icons.person_add_rounded, size: 14, color: Color(0xFF7C3AED)),
                                                                SizedBox(width: 6),
                                                                Text('Pilih Pengawas', style: TextStyle(fontSize: 12, color: Color(0xFF7C3AED))),
                                                              ],
                                                            ),
                                                            items: teachers.map((t) {
                                                              return DropdownMenuItem<String>(
                                                                value: t.id,
                                                                child: Text(t.displayName, style: const TextStyle(fontSize: 12)),
                                                              );
                                                            }).toList(),
                                                            onChanged: (val) {
                                                              if (val != null) {
                                                                setState(() => _proctorGrid[gridKey] = val);
                                                                _autoSaveDraft();
                                                              }
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }

  void _autoGenerateProctors(List<Teacher> teachers) {
    if (teachers.isEmpty) return;
    final days = _examDays();
    // Shuffle a copy of the teacher list with a fresh Random each call
    final rng = Random();
    final shuffled = List<Teacher>.from(teachers)..shuffle(rng);
    _proctorGrid.clear();
    int tIdx = 0;
    for (int d = 0; d < days.length; d++) {
      for (int s = 0; s < _sessions.length; s++) {
        // Cycle through the shuffled list if there are more slots than teachers
        _proctorGrid['day_${d}_session_$s'] = shuffled[tIdx % shuffled.length].id;
        tIdx++;
      }
    }
    setState(() {});
    _autoSaveDraft();
  }

  // Step 8: Review & Finalisasi
  Widget _buildStep8() {
    return StreamBuilder<List<Teacher>>(
      stream: _adminUserService.streamTeachers(widget.schoolId),
      builder: (context, teachersSnap) {
        final teachers = teachersSnap.data ?? [];
        final days = _examDays();
        final uniqueSubjects = _uniqueSubjects();

        // PDF: convert teachers to simple map list
        final teacherMaps = teachers.map((t) => {'id': t.id, 'displayName': t.displayName}).toList();

        Widget _reviewCard({
          required String title,
          required IconData icon,
          required Color iconColor,
          required List<Widget> children,
        }) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    border: Border(bottom: BorderSide(color: iconColor.withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: iconColor),
                      const SizedBox(width: 8),
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: iconColor)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                ),
              ],
            ),
          );
        }

        Widget _infoRow(String label, String value) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 160, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + Download buttons
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Langkah 8: Review & Finalisasi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Periksa semua pengaturan sebelum menyimpan event ujian.', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                // Download buttons
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ExamPdfGenerator.downloadSchedulePerClass(
                          eventName: _nameController.text,
                          examType: _examType,
                          startDate: _startDate,
                          endDate: _endDate,
                          sessions: _sessions,
                          timetable: _timetable,
                          scheduleGrid: _scheduleGrid,
                          rooms: _rooms,
                          roomAssignments: _roomAssignments,
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                      label: const Text('Jadwal per Kelas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFF4F46E5)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await ExamPdfGenerator.downloadProctorSchedule(
                          eventName: _nameController.text,
                          examType: _examType,
                          startDate: _startDate,
                          endDate: _endDate,
                          sessions: _sessions,
                          timetable: _timetable,
                          scheduleGrid: _scheduleGrid,
                          proctorGrid: _proctorGrid,
                          teachers: teacherMaps,
                        );
                      },
                      icon: const Icon(Icons.supervisor_account_rounded, size: 16),
                      label: const Text('Jadwal Pengawas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Review cards
            Expanded(
              child: ListView(
                children: [
                  // Step 1: Info Dasar
                  _reviewCard(
                    title: 'Step 1 — Info Dasar Event',
                    icon: Icons.info_outline_rounded,
                    iconColor: const Color(0xFF4F46E5),
                    children: [
                      _infoRow('Nama Event', _nameController.text.isEmpty ? '-' : _nameController.text),
                      _infoRow('Tipe Ujian', _examType == 'UTS' ? 'UTS (Ujian Tengah Semester)' : 'UAS (Ujian Akhir Semester)'),
                      _infoRow('Tahun Ajaran', _academicYearController.text.isEmpty ? '-' : _academicYearController.text),
                      _infoRow(
                        'Rentang Tanggal',
                        _startDate != null && _endDate != null
                            ? '${ExamPdfGenerator.formatIndonesianDate(_startDate!, includeDayName: false)} – ${ExamPdfGenerator.formatIndonesianDate(_endDate!, includeDayName: false)}'
                            : '-',
                      ),
                      _infoRow('Durasi', days.isEmpty ? '-' : '${days.length} hari'),
                      if (_descController.text.isNotEmpty) _infoRow('Deskripsi', _descController.text),
                    ],
                  ),

                  // Step 2: Sesi
                  _reviewCard(
                    title: 'Step 2 — Sesi Ujian (${_sessions.length} Sesi)',
                    icon: Icons.schedule_rounded,
                    iconColor: const Color(0xFF0891B2),
                    children: _sessions.isEmpty
                        ? [const Text('Belum ada sesi.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : _sessions.map((s) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6, height: 6,
                                    decoration: const BoxDecoration(color: Color(0xFF0891B2), shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${s['name']}  •  ${s['startTime']} – ${s['endTime']}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            )).toList(),
                  ),

                  // Step 3: Jadwal Mapel
                  _reviewCard(
                    title: 'Step 3 — Jadwal Mapel (${uniqueSubjects.length} Mapel, ${_timetable.length} Entri)',
                    icon: Icons.menu_book_rounded,
                    iconColor: const Color(0xFF059669),
                    children: uniqueSubjects.isEmpty
                        ? [const Text('Belum ada jadwal mapel.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : uniqueSubjects.map((sub) {
                            final classes = _timetable
                                .where((t) => t['subjectId'] == sub['id'])
                                .map((t) => t['className'] as String? ?? '-')
                                .toSet()
                                .toList()..sort();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 5),
                                    decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(
                                    '${sub['name']}  →  ${classes.join(', ')}',
                                    style: const TextStyle(fontSize: 12),
                                  )),
                                ],
                              ),
                            );
                          }).toList(),
                  ),

                  // Step 4: Ruangan
                  _reviewCard(
                    title: 'Step 4 — Ruangan Ujian (${_rooms.length} Ruangan)',
                    icon: Icons.meeting_room_outlined,
                    iconColor: const Color(0xFFD97706),
                    children: _rooms.isEmpty
                        ? [const Text('Belum ada ruangan.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : [
                            _infoRow('Total Ruangan', '${_rooms.length} ruangan'),
                            _infoRow('Total Kapasitas', '${_rooms.fold<int>(0, (s, r) => s + ((r['capacity'] as num?)?.toInt() ?? 0))} kursi'),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _rooms.map((r) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Text(
                                  '${r['name'] ?? '-'}  (${r['capacity'] ?? 0} kursi)',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w500),
                                ),
                              )).toList(),
                            ),
                          ],
                  ),

                  // Step 5: Alokasi Murid
                  _reviewCard(
                    title: 'Step 5 — Alokasi Murid ke Ruangan',
                    icon: Icons.people_outline_rounded,
                    iconColor: const Color(0xFFDC2626),
                    children: _roomAssignments.isEmpty
                        ? [const Text('Belum ada alokasi murid.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : _roomAssignments.entries.map((e) {
                            final room = _rooms.firstWhere((r) => r['id'] == e.key, orElse: () => {'name': e.key});
                            final total = e.value.fold<int>(0, (s, a) => s + ((a['count'] as num?)?.toInt() ?? 0));
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(width: 6, height: 6,
                                    decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(
                                    '${room['name'] ?? e.key}  →  $total murid  (${e.value.map((a) => '${a['className']}: ${a['count']}').join(', ')})',
                                    style: const TextStyle(fontSize: 11),
                                  )),
                                ],
                              ),
                            );
                          }).toList(),
                  ),

                  // Step 6: Jadwal per Sesi
                  _reviewCard(
                    title: 'Step 6 — Jadwal Ujian per Sesi (${_scheduleGrid.length} Slot)',
                    icon: Icons.calendar_month_rounded,
                    iconColor: const Color(0xFF4F46E5),
                    children: days.isEmpty
                        ? [const Text('Belum ada hari pelaksanaan.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : days.asMap().entries.map((de) {
                            final dayLabel = ExamPdfGenerator.formatIndonesianDate(de.value);
                            final sessionTexts = List.generate(_sessions.length, (si) {
                              final key = 'day_${de.key}_session_$si';
                              final sid = _scheduleGrid[key];
                              final subName = sid != null
                                  ? (_timetable.firstWhere((t) => t['subjectId'] == sid, orElse: () => {'subjectName': sid})['subjectName'] as String? ?? sid)
                                  : '—';
                              return '${_sessions[si]['name']}: $subName';
                            });
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 140, child: Text(dayLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  Expanded(child: Text(sessionTexts.join('  |  '), style: const TextStyle(fontSize: 11))),
                                ],
                              ),
                            );
                          }).toList(),
                  ),

                  // Step 7: Pengawas
                  _reviewCard(
                    title: 'Step 7 — Pengawas Ruangan (${_proctorGrid.length} Penugasan)',
                    icon: Icons.supervisor_account_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    children: days.isEmpty || teachers.isEmpty
                        ? [const Text('Belum ada pengawas ditugaskan.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : days.asMap().entries.map((de) {
                            final dayLabel = ExamPdfGenerator.formatIndonesianDate(de.value);
                            final proctorTexts = List.generate(_sessions.length, (si) {
                              final key = 'day_${de.key}_session_$si';
                              final tid = _proctorGrid[key];
                              final tname = tid != null
                                  ? (teachers.firstWhere((t) => t.id == tid, orElse: () => Teacher(id: '', displayName: '?', subjects: [], schoolId: '', gender: 'M', nip: '', disabled: false, archived: false, createdAt: DateTime.now(), updatedAt: DateTime.now())).displayName)
                                  : '—';
                              return '${_sessions[si]['name']}: $tname';
                            });
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 140, child: Text(dayLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  Expanded(child: Text(proctorTexts.join('  |  '), style: const TextStyle(fontSize: 11))),
                                ],
                              ),
                            );
                          }).toList(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
