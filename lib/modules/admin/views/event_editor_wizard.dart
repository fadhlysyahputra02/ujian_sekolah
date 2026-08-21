import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/services/event_exam_service.dart';
import '../../../core/models/teacher.dart';
import '../../../core/utils/natural_sort.dart';
import 'exam_pdf_generator.dart';

class EventEditorWizard extends StatefulWidget {
  final String schoolId;
  final String? draftId;
  final String? eventId;

  const EventEditorWizard({super.key, required this.schoolId, this.draftId, this.eventId});

  @override
  State<EventEditorWizard> createState() => _EventEditorWizardState();
}

class _EventEditorWizardState extends State<EventEditorWizard> {
  final _formKey1 = GlobalKey<FormState>();
  final AdminUserService _adminUserService = AdminUserService();
  final EventExamService _eventService = EventExamService();

  int _currentStep = 0;
  int _maxStepReached = 0;
  bool _isLoading = false;

  void _setStep(int step) {
    if (mounted) {
      setState(() {
        _currentStep = step;
        if (step > _maxStepReached) {
          _maxStepReached = step;
        }
      });
    }
  }

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
  List<String> _selectedTeacherIds = [];
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
  // Key: 'day_$dayIndex_session_$sessionIdx' -> List of subjectIds assigned (parallel scheduling)
  final Map<String, List<String>> _scheduleGrid = {};
  int _selectedStep6DayIdx = 0;
  int _selectedStep7DayIdx = 0;

  // Step 7: Proctor Grid
  // Key: 'day_$dayIndex_session_$sessionIdx' -> teacherId assigned
  final Map<String, String> _proctorGrid = {};

  // Subject question status cache (subjectId -> hasQuestions)
  final Map<String, bool> _subjectHasQuestions = {};
  bool _isCheckingQuestions = false;

  // Draft auto-save
  String? _draftId;
  bool _isSavingDraft = false;
  String _draftStatus = ''; // 'saving', 'saved', ''

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initOrLoadDraft());
  }

  /// Check whether each unique subject in timetable has questions in DB.
  /// Results cached in [_subjectHasQuestions] to avoid repeated Firestore calls.
  Future<void> _checkSubjectsHaveQuestions() async {
    if (_isCheckingQuestions) return;
    final uniqueSubjectIds = _timetable
        .map((t) => t['subjectId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final unchecked = uniqueSubjectIds.where((id) => !_subjectHasQuestions.containsKey(id)).toList();
    if (unchecked.isEmpty) return;

    if (mounted) setState(() => _isCheckingQuestions = true);
    try {
      for (final subjectId in unchecked) {
        if (!mounted) return;
        try {
          final qSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('subjects')
              .doc(subjectId)
              .collection('questions')
              .limit(1)
              .get();
          if (qSnap.docs.isNotEmpty) {
            if (mounted) setState(() => _subjectHasQuestions[subjectId] = true);
            continue;
          }
          final qbSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('questionBanks')
              .where('subjectId', isEqualTo: subjectId)
              .limit(1)
              .get();
          if (mounted) setState(() => _subjectHasQuestions[subjectId] = qbSnap.docs.isNotEmpty);
        } catch (_) {
          if (mounted) setState(() => _subjectHasQuestions[subjectId] = false);
        }
      }
    } finally {
      if (mounted) setState(() => _isCheckingQuestions = false);
    }
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
    } else if (widget.eventId != null) {
      // Load the existing event data for editing
      setState(() {
        _isLoading = true;
      });
      try {
        final doc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolId)
            .collection('events')
            .doc(widget.eventId)
            .get();
        if (mounted && doc.exists) {
          final data = doc.data()!;
          final draftState = data['draftState'] as Map<String, dynamic>?;
          if (draftState != null) {
            _loadDraftData(draftState, doc.id);
            setState(() {
              _isLoading = false;
            });
            return;
          }

          // Fallback loader: Reconstruct draft state directly from event doc & subcollections
          final eventName = data['name'] as String? ?? '';
          final academicYear = data['academicYear'] as String? ?? '2026/2027';
          final description = data['description'] as String? ?? '';
          final examType = data['type'] as String? ?? 'UTS';
          DateTime? startDate;
          DateTime? endDate;
          if (data['startDate'] != null) {
            final sd = data['startDate'];
            startDate = sd is Timestamp ? sd.toDate() : (sd is String ? DateTime.tryParse(sd) : null);
          }
          if (data['endDate'] != null) {
            final ed = data['endDate'];
            endDate = ed is Timestamp ? ed.toDate() : (ed is String ? DateTime.tryParse(ed) : null);
          }

          // 1. Fetch sessions
          final sessionsSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('events')
              .doc(widget.eventId)
              .collection('sessions')
              .orderBy('order')
              .get();

          final List<Map<String, dynamic>> sessionsList = [];
          for (final sDoc in sessionsSnap.docs) {
            final sData = sDoc.data();
            sessionsList.add({
              'name': sData['name'] ?? '',
              'startTime': sData['startTime'] ?? '07:00',
              'endTime': sData['endTime'] ?? '08:00',
              'order': (sData['order'] as num?)?.toInt() ?? 0,
              'date': sData['date'] ?? '',
            });
          }

          // 2. Fetch timetable and resolve teacherNames if they are missing
          final teachersSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('teachers')
              .get();
          final Map<String, String> teacherIdToName = {};
          for (final doc in teachersSnap.docs) {
            final tData = doc.data();
            final name = tData['displayName'] as String? ?? tData['name'] as String? ?? '';
            if (name.isNotEmpty) {
              teacherIdToName[doc.id] = name;
            }
          }

          final timetableSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('events')
              .doc(widget.eventId)
              .collection('timetable')
              .get();

          final List<Map<String, dynamic>> timetableList = [];
          for (final tDoc in timetableSnap.docs) {
            final tData = tDoc.data();
            final tIds = tData['teacherId'] != null ? List<String>.from(tData['teacherId'] as List) : <String>[];
            
            String tName = tData['teacherName'] as String? ?? '';
            if (tName.isEmpty && tIds.isNotEmpty) {
              tName = tIds.map((id) => teacherIdToName[id] ?? id).join(', ');
            }

            timetableList.add({
              'classId': tData['classId'] ?? '',
              'className': tData['className'] ?? '',
              'subjectId': tData['subjectId'] ?? '',
              'subjectName': tData['subjectName'] ?? '',
              'teacherId': tIds,
              'teacherName': tName,
              'sessionId': tData['sessionId'],
              'sessionName': tData['sessionName'],
            });
          }

          // 3. Load rooms of school
          final roomsSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('rooms')
              .get();
          final roomsList = roomsSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

          // 3.5 Reconstruct Step 5: _roomAssignments from finalized allocation seats
          final allocationsSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('events')
              .doc(widget.eventId)
              .collection('allocations')
              .where('status', isEqualTo: 'finalized')
              .limit(1)
              .get();

          final Map<String, List<Map<String, dynamic>>> roomAssignments = {};
          if (allocationsSnap.docs.isNotEmpty) {
            final allocationId = allocationsSnap.docs.first.id;
            final seatsSnap = await FirebaseFirestore.instance
                .collection('schools')
                .doc(widget.schoolId)
                .collection('events')
                .doc(widget.eventId)
                .collection('allocations')
                .doc(allocationId)
                .collection('seats')
                .get();

            final Map<String, Map<String, Map<String, dynamic>>> tempAssignments = {};
            for (final seatDoc in seatsSnap.docs) {
              final seatData = seatDoc.data();
              final roomId = seatData['roomId'] as String? ?? '';
              final classId = seatData['classId'] as String? ?? '';
              final className = seatData['className'] as String? ?? '';

              if (roomId.isNotEmpty && classId.isNotEmpty) {
                tempAssignments.putIfAbsent(roomId, () => {});
                final classMap = tempAssignments[roomId]!.putIfAbsent(
                  classId,
                  () => {
                    'classId': classId,
                    'className': className,
                    'count': 0,
                    'isAll': true,
                  },
                );
                classMap['count'] = (classMap['count'] as int) + 1;
              }
            }

            tempAssignments.forEach((roomId, classMap) {
              roomAssignments[roomId] = classMap.values.map((v) => Map<String, dynamic>.from(v)).toList();
            });
          }

          // 4. Fetch proctors and reconstruct Step 6 (_scheduleGrid) & Step 7 (_proctorGrid)
          final proctorsSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolId)
              .collection('events')
              .doc(widget.eventId)
              .collection('proctors')
              .get();

          final Map<String, String> proctorGrid = {};
          final Map<String, List<String>> scheduleGrid = {};

          if (sessionsList.isNotEmpty) {
            // Create maps for quick lookup of session order
            final Map<String, int> sessionIdToOrder = {};
            for (int index = 0; index < sessionsSnap.docs.length; index++) {
              final doc = sessionsSnap.docs[index];
              final orderVal = doc.data()['order'] as num?;
              if (orderVal != null) {
                sessionIdToOrder[doc.id] = orderVal.toInt();
              }
            }

            // Find how many sessions per day config
            final Map<String, List<Map<String, dynamic>>> sessionsByDate = {};
            for (final s in sessionsList) {
              final d = s['date'] as String? ?? '';
              if (d.isNotEmpty) {
                sessionsByDate.putIfAbsent(d, () => []).add(s);
              }
            }
            final int sessionsPerDay = sessionsByDate.values.isNotEmpty 
                ? sessionsByDate.values.first.length 
                : 2; // Default to 2 if not found

            // Reconstruct Step 6 (_scheduleGrid) from scheduled timetable entries
            for (final tData in timetableList) {
              final sessionId = tData['sessionId'] as String? ?? '';
              final subjectId = tData['subjectId'] as String? ?? '';
              final order = sessionIdToOrder[sessionId];
              if (order != null && subjectId.isNotEmpty) {
                final dIdx = (order - 1) ~/ sessionsPerDay;
                final sIdx = (order - 1) % sessionsPerDay;
                final key = 'day_${dIdx}_session_${sIdx}';
                scheduleGrid.putIfAbsent(key, () => []);
                if (!scheduleGrid[key]!.contains(subjectId)) {
                  scheduleGrid[key]!.add(subjectId);
                }
              }
            }

            // Reconstruct Step 7 (_proctorGrid) from proctor assignments
            for (final pDoc in proctorsSnap.docs) {
              final pData = pDoc.data();
              final sessionId = pData['sessionId'] as String? ?? '';
              final roomId = pData['roomId'] as String? ?? '';
              final teacherId = pData['teacherId'] as String? ?? '';
              final order = sessionIdToOrder[sessionId];
              if (order != null && roomId.isNotEmpty && teacherId.isNotEmpty) {
                final dIdx = (order - 1) ~/ sessionsPerDay;
                final sIdx = (order - 1) % sessionsPerDay;
                proctorGrid['day_${dIdx}_session_${sIdx}_room_$roomId'] = teacherId;
              }
            }
          }

          setState(() {
            _nameController.text = eventName;
            _academicYearController.text = academicYear;
            _descController.text = description;
            _examType = examType;
            _startDate = startDate;
            _endDate = endDate;
            _sessions.clear();
            _sessions.addAll(sessionsList);
            _timetable.clear();
            _timetable.addAll(timetableList);
            _rooms.clear();
            _rooms.addAll(roomsList);
            _roomAssignments.clear();
            _roomAssignments.addAll(roomAssignments);
            _scheduleGrid.clear();
            _scheduleGrid.addAll(scheduleGrid);
            _proctorGrid.clear();
            _proctorGrid.addAll(proctorGrid);

            final roomLayoutsData = draftState?['roomLayouts'] as Map? ?? data['roomLayouts'] as Map? ?? {};
            _addState.clear();
            roomLayoutsData.forEach((k, v) {
              if (v is Map) {
                _addState[k as String] = Map<String, dynamic>.from(v);
              }
            });

            _isLoading = false;
          });

          // Persist reconstructed state into draftState so future auto-saves and reloads work
          // without needing to re-query all subcollections
          try {
            await FirebaseFirestore.instance
                .collection('schools')
                .doc(widget.schoolId)
                .collection('events')
                .doc(widget.eventId)
                .update({
              'draftState': {
                'step': 7,
                'eventName': eventName,
                'academicYear': academicYear,
                'description': description,
                'examType': examType,
                'startDate': startDate?.toIso8601String(),
                'endDate': endDate?.toIso8601String(),
                'sessions': sessionsList,
                'timetable': timetableList,
                'rooms': roomsList,
                'roomAssignments': roomAssignments.map((k, v) => MapEntry(k, v)),
                'scheduleGrid': scheduleGrid.map((k, v) => MapEntry(k, v)),
                'proctorGrid': proctorGrid,
              },
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}

          return;
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
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
      _maxStepReached = max(_maxStepReached, _currentStep);
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
          if (v is List) {
            _scheduleGrid[k as String] = List<String>.from(v);
          } else if (v is String) {
            _scheduleGrid[k as String] = [v];
          }
        });
      }
      _proctorGrid.clear();
      if (data['proctorGrid'] is Map) {
        (data['proctorGrid'] as Map).forEach((k, v) {
          _proctorGrid[k as String] = v as String;
        });
      }
      _addState.clear();
      if (data['roomLayouts'] is Map) {
        (data['roomLayouts'] as Map).forEach((k, v) {
          if (v is Map) {
            _addState[k as String] = Map<String, dynamic>.from(v);
          }
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
      'roomLayouts': _addState,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    try {
      if (widget.eventId != null) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolId)
            .collection('events')
            .doc(widget.eventId)
            .update({
          'draftState': draftData,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final draftsRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolId)
            .collection('eventDrafts');

        if (_draftId != null) {
          await draftsRef.doc(_draftId).update(draftData);
        } else {
          final doc = await draftsRef.add(draftData);
          if (mounted) setState(() => _draftId = doc.id);
        }
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

  Future<void> _showTeacherMultiSelectDialog(BuildContext context, String? subName, List<Teacher> teachers) async {
    List<String> tempSelected = List.from(_selectedTeacherIds);
    String searchQuery = '';
    
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredTeachers = teachers.where((t) => t.displayName.toLowerCase().contains(searchQuery.toLowerCase())).toList();
            
            List<Teacher> recommended = [];
            List<Teacher> others = [];
            if (subName != null) {
              recommended = filteredTeachers.where((t) => t.subjects.contains(subName)).toList();
              others = filteredTeachers.where((t) => !t.subjects.contains(subName)).toList();
            } else {
              others = filteredTeachers;
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Pilih Guru Pembuat Soal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              contentPadding: const EdgeInsets.only(top: 12),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Cari nama guru...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) => setDialogState(() => searchQuery = val),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (recommended.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text('Rekomendasi (Pengampu Mapel)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                            ),
                            ...recommended.map((t) => CheckboxListTile(
                              title: Text(t.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: const Text('Rekomendasi', style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
                              value: tempSelected.contains(t.id),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    tempSelected.add(t.id);
                                  } else {
                                    tempSelected.remove(t.id);
                                  }
                                });
                              },
                              activeColor: const Color(0xFF10B981),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            )),
                            const Divider(),
                          ],
                          if (others.isNotEmpty) ...[
                            if (subName != null && recommended.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Text('Guru Lainnya', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                              ),
                            ...others.map((t) => CheckboxListTile(
                              title: Text(t.displayName, style: const TextStyle(fontSize: 13)),
                              value: tempSelected.contains(t.id),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    tempSelected.add(t.id);
                                  } else {
                                    tempSelected.remove(t.id);
                                  }
                                });
                              },
                              activeColor: const Color(0xFF10B981),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            )),
                          ],
                          if (recommended.isEmpty && others.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Guru tidak ditemukan.', style: TextStyle(color: Colors.grey)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedTeacherIds = tempSelected);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  child: const Text('Pilih', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addTimetableEntry(List<Map<String, dynamic>> subjects, List<Teacher> teachers, List<Map<String, dynamic>> classes) {
    if (_selectedClassIds.isEmpty || _selectedSubjectId == null || _selectedTeacherIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi pilihan kelas, mapel & guru pembuat soal!'), backgroundColor: Colors.red),
      );
      return;
    }

    final sub = subjects.firstWhere((s) => s['id'] == _selectedSubjectId);
    final selectedTeachers = _selectedTeacherIds.map((id) => teachers.firstWhere((t) => t.id == id)).toList();
    final teacherNamesStr = selectedTeachers.map((t) => t.displayName).join(', ');

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
            'teacherId': _selectedTeacherIds,
            'teacherName': teacherNamesStr,
            'sessionId': null,
            'sessionName': null,
          });
        }
      }
      _selectedClassIds.clear();
      _selectedSubjectId = null;
      _selectedTeacherIds.clear();
      _selectedSessionIndex = null;
    });
    _autoSaveDraft();
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      // 1. Create Event
      final List<Map<String, dynamic>> expandedSessions = [];
      final days = _examDays();
      for (int d = 0; d < days.length; d++) {
        final day = days[d];
        for (int s = 0; s < _sessions.length; s++) {
          final sess = _sessions[s];
          
          expandedSessions.add({
            'name': sess['name'],
            'startTime': sess['startTime'],
            'endTime': sess['endTime'],
            'order': d * _sessions.length + s + 1,
            'date': day.toIso8601String(),
            'tempId': 'day_${d}_session_${s}',
          });
        }
      }

      final eventId = await _eventService.createEvent(
        schoolId: widget.schoolId,
        eventId: widget.eventId,
        eventInfo: {
          'name': _nameController.text.trim(),
          'type': _examType,
          'academicYear': _academicYearController.text.trim(),
          'startDate': _startDate!.toIso8601String(),
          'endDate': _endDate!.toIso8601String(),
          'description': _descController.text.trim(),
          'participantNumberFormat': '[angkatan][roomCode][seatNumber]',
          'seatNumberPadding': _seatPadding,
          'draftState': {
            'step': 7,
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
            'roomLayouts': _addState,
            'scheduleGrid': _scheduleGrid,
            'proctorGrid': _proctorGrid,
          },
          'roomAssignments': _roomAssignments,
          'roomLayouts': _addState,
        },
        sessions: expandedSessions,
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

      // 2.5 Save per-room allocation subcollections & documents with exact room layout modes & student data
      await _saveDetailedRoomsAndSeatsToFirestore(widget.schoolId, eventId, allocationId);

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

      // 3.5. Save Proctor Assignments
      if (_proctorGrid.isNotEmpty) {
        final sessionsSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolId)
            .collection('events')
            .doc(eventId)
            .collection('sessions')
            .get();

        final Map<String, String> orderToSessionId = {};
        for (final doc in sessionsSnap.docs) {
          final orderVal = doc.data()['order'];
          if (orderVal != null) {
            orderToSessionId[orderVal.toString()] = doc.id;
          }
        }

        final List<Map<String, dynamic>> proctorAssignments = [];
        _proctorGrid.forEach((key, teacherId) {
          final parts = key.split('_');
          if (parts.length >= 6 && parts[4] == 'room') {
            final d = int.tryParse(parts[1]) ?? 0;
            final s = int.tryParse(parts[3]) ?? 0;
            final roomId = parts.sublist(5).join('_');
            
            final order = d * _sessions.length + s + 1;
            final realSessionId = orderToSessionId[order.toString()];
            if (realSessionId != null && teacherId.isNotEmpty) {
              proctorAssignments.add({
                'sessionId': realSessionId,
                'roomId': roomId,
                'teacherId': teacherId,
                'role': 'main',
                'notes': 'Mengawas Sesi',
              });
            }
          }
        });

        if (proctorAssignments.isNotEmpty) {
          await _eventService.assignProctors(
            schoolId: widget.schoolId,
            eventId: eventId,
            assignments: proctorAssignments,
          );
        }
      }

      // 4. Delete draft on success if loaded as draft
      if (widget.draftId != null) {
        await _deleteDraft();
      }

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
                  Text('Memproses event...', style: TextStyle(color: Color(0xFF64748B))),
                ],
              ),
            )
          : Column(
              children: [
                // Modern Steps Indicator Header
                _buildStepperHeader(isDesktop),

                // Main Content Card
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                          child: _buildStepContent(),
                        ),
                      ),
                    ),
                  ),
                ),

                // Navigation buttons
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 28 : 16,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0)
                        OutlinedButton.icon(
                          onPressed: () => _setStep(_currentStep - 1),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Sebelumnya'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        )
                      else
                        const SizedBox(),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (_currentStep == 0) {
                            if (_formKey1.currentState!.validate() && _startDate != null && _endDate != null) {
                              _setStep(_currentStep + 1);
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
                              _setStep(_currentStep + 1);
                              _autoSaveDraft();
                            }
                          } else if (_currentStep == 2) {
                            if (_timetable.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tambahkan minimal 1 jadwal mata pelajaran!'), backgroundColor: Colors.red),
                              );
                            } else {
                              _setStep(_currentStep + 1);
                              _autoSaveDraft();
                            }
                          } else if (_currentStep == 7) {
                            _submit();
                          } else {
                            _setStep(_currentStep + 1);
                            _autoSaveDraft();
                          }
                        },
                        icon: Icon(_currentStep == 7 ? Icons.check_circle_rounded : Icons.arrow_forward_rounded, size: 16),
                        label: Text(_currentStep == 7 ? 'Eksekusi & Simpan' : 'Selanjutnya', style: const TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _currentStep == 7 ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── Modern Stepper Header ──────────────────────────────────────────────────
  Widget _buildStepperHeader(bool isDesktop) {
    final stepsMeta = [
      {'title': 'Info Dasar', 'icon': Icons.edit_note_rounded},
      {'title': 'Sesi Ujian', 'icon': Icons.access_time_filled_rounded},
      {'title': 'Jadwal Mapel', 'icon': Icons.menu_book_rounded},
      {'title': 'Ruangan', 'icon': Icons.meeting_room_rounded},
      {'title': 'Alokasi Murid', 'icon': Icons.groups_rounded},
      {'title': 'Jadwal Ruang', 'icon': Icons.calendar_month_rounded},
      {'title': 'Pengawas', 'icon': Icons.supervisor_account_rounded},
      {'title': 'Finalisasi', 'icon': Icons.verified_rounded},
    ];

    final progress = (_currentStep + 1) / 8.0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 28 : 12,
        vertical: 12,
      ),
      child: Column(
        children: [
          // Top Progress Bar & Percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Langkah ${_currentStep + 1} dari 8: ${stepsMeta[_currentStep]['title']}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                '${(progress * 100).toInt()}% Selesai',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
            ),
          ),
          const SizedBox(height: 12),

          // Horizontal Steps List
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(stepsMeta.length, (i) {
                final isActive = _currentStep == i;
                final isCompleted = i < _maxStepReached;
                final isClickable = i <= _maxStepReached;
                final meta = stepsMeta[i];

                return InkWell(
                  onTap: isClickable ? () => _setStep(i) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF4F46E5)
                          : isCompleted
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF4F46E5)
                            : isCompleted
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? Colors.white.withValues(alpha: 0.2)
                                : isCompleted
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFCBD5E1),
                          ),
                          alignment: Alignment.center,
                          child: isCompleted
                              ? const Icon(Icons.check, size: 12, color: Colors.white)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.white : const Color(0xFF475569),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          meta['title'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.w500,
                            color: isActive
                                ? Colors.white
                                : isCompleted
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header Banner Helper ───────────────────────────────────────────────────
  Widget _buildHeaderBanner({
    required String stepNumber,
    required String title,
    required String subtitle,
    required IconData icon,
    Color iconColor = const Color(0xFF4F46E5),
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stepNumber.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action,
          ],
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

  // ── Step 1: Info Dasar ─────────────────────────────────────────────────────
  Widget _buildStep1() {
    final examTypes = [
      {'key': 'UTS', 'label': 'UTS (Tengah Semester)', 'icon': Icons.hourglass_top_rounded},
      {'key': 'UAS', 'label': 'UAS (Akhir Semester)', 'icon': Icons.school_rounded},
      {'key': 'UH', 'label': 'UH (Ulangan Harian)', 'icon': Icons.assignment_turned_in_rounded},
      {'key': 'TO', 'label': 'Try Out (Simulasi)', 'icon': Icons.psychology_rounded},
      {'key': 'US', 'label': 'Ujian Sekolah (US)', 'icon': Icons.military_tech_rounded},
    ];

    final daysCount = _startDate != null && _endDate != null
        ? _endDate!.difference(_startDate!).inDays + 1
        : 0;

    return Form(
      key: _formKey1,
      child: ListView(
        children: [
          _buildHeaderBanner(
            stepNumber: 'Langkah 1',
            title: 'Informasi Dasar Event',
            subtitle: 'Lengkapi identitas ujian, tipe asesmen, tahun ajaran, dan rentang tanggal pelaksanaan.',
            icon: Icons.edit_note_rounded,
            iconColor: const Color(0xFF3B82F6),
          ),

          // Nama Event
          const Text('Nama Event Ujian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Contoh: Ujian Tengah Semester Ganjil 2026',
              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF3B82F6), size: 20),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
            validator: (v) => v!.trim().isEmpty ? 'Nama event harus diisi!' : null,
          ),
          const SizedBox(height: 18),

          // Tipe Ujian Choice Cards
          const Text('Tipe Ujian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: examTypes.map((et) {
              final isSelected = _examType == et['key'];
              return InkWell(
                onTap: () => setState(() => _examType = et['key'] as String),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF3B82F6).withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        et['icon'] as IconData,
                        size: 16,
                        color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        et['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Tahun Ajaran
          const Text('Tahun Ajaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _academicYearController,
            decoration: InputDecoration(
              hintText: 'Contoh: 2026/2027',
              prefixIcon: const Icon(Icons.calendar_today_rounded, color: Color(0xFF3B82F6), size: 20),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
            validator: (v) => v!.trim().isEmpty ? 'Tahun ajaran harus diisi!' : null,
          ),
          const SizedBox(height: 18),

          // Rentang Tanggal Ujian (Dual Calendar Card)
          const Text('Rentang Tanggal Pelaksanaan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          InkWell(
            onTap: _selectDateRange,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _startDate != null ? const Color(0xFF3B82F6).withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
                  width: _startDate != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.date_range_rounded, color: Color(0xFF3B82F6), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _startDate != null && _endDate != null
                              ? '${ExamPdfGenerator.formatIndonesianDate(_startDate!)}  —  ${ExamPdfGenerator.formatIndonesianDate(_endDate!)}'
                              : 'Klik untuk Memilih Rentang Tanggal Ujian',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _startDate != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _startDate != null && _endDate != null
                              ? 'Durasi: $daysCount hari ujian terdaftar'
                              : 'Tentukan tanggal mulai dan selesai ujian',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  if (_startDate != null && _endDate != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '$daysCount Hari',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Deskripsi / Petunjuk
          const Text('Deskripsi / Petunjuk Ujian (Opsional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Tuliskan catatan khusus atau tata tertib bagi pengawas dan peserta ujian...',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.notes_rounded, color: Color(0xFF3B82F6), size: 20),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ── Step 2: Sesi Ujian ─────────────────────────────────────────────────────
  Widget _buildStep2() {
    final quickPresets = [
      {'name': 'Sesi 1', 'start': const TimeOfDay(hour: 7, minute: 0), 'end': const TimeOfDay(hour: 8, minute: 30), 'label': '07:00 - 08:30'},
      {'name': 'Sesi 2', 'start': const TimeOfDay(hour: 8, minute: 45), 'end': const TimeOfDay(hour: 10, minute: 15), 'label': '08:45 - 10:15'},
      {'name': 'Sesi 3', 'start': const TimeOfDay(hour: 10, minute: 30), 'end': const TimeOfDay(hour: 12, minute: 0), 'label': '10:30 - 12:00'},
      {'name': 'Sesi 4', 'start': const TimeOfDay(hour: 13, minute: 0), 'end': const TimeOfDay(hour: 14, minute: 30), 'label': '13:00 - 14:30'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderBanner(
          stepNumber: 'Langkah 2',
          title: 'Konfigurasi Sesi Ujian',
          subtitle: 'Atur sesi waktu pelaksanaan ujian setiap harinya beserta durasi jam mulai dan selesai.',
          icon: Icons.access_time_filled_rounded,
          iconColor: const Color(0xFF06B6D4),
        ),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Form Tambah Sesi
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.add_circle_outline_rounded, size: 18, color: Color(0xFF06B6D4)),
                            SizedBox(width: 8),
                            Text('Tambah Sesi Baru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Nama Sesi
                        const Text('Nama Sesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _sessionNameController,
                          decoration: InputDecoration(
                            hintText: 'Contoh: Sesi ${_sessions.length + 1}',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Preset cepat
                        const Text('Preset Waktu Cepat:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: quickPresets.map((qp) {
                            return ActionChip(
                              avatar: const Icon(Icons.flash_on_rounded, size: 13, color: Color(0xFF0891B2)),
                              label: Text('${qp['name']} (${qp['label']})', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0E7490))),
                              backgroundColor: const Color(0xFFECFEFF),
                              side: const BorderSide(color: Color(0xFFA5F3FC)),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              onPressed: () {
                                setState(() {
                                  _sessionNameController.text = qp['name'] as String;
                                  _startTime = qp['start'] as TimeOfDay;
                                  _endTime = qp['end'] as TimeOfDay;
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Jam Mulai & Selesai
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Jam Mulai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () async {
                                      final t = await showTimePicker(context: context, initialTime: _startTime ?? const TimeOfDay(hour: 7, minute: 0));
                                      if (t != null) setState(() => _startTime = t);
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _startTime == null ? '--:--' : _startTime!.format(context),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: _startTime != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                          const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF06B6D4)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Jam Selesai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () async {
                                      final t = await showTimePicker(context: context, initialTime: _endTime ?? const TimeOfDay(hour: 8, minute: 30));
                                      if (t != null) setState(() => _endTime = t);
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _endTime == null ? '--:--' : _endTime!.format(context),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: _endTime != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                          const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF06B6D4)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Tombol Tambah Sesi
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _addSession,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Tambah ke Daftar Sesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0891B2),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Right: List Sesi Terdaftar
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.list_alt_rounded, size: 18, color: Color(0xFF06B6D4)),
                              const SizedBox(width: 8),
                              const Text('Sesi Terdaftar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFEFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFA5F3FC)),
                            ),
                            child: Text(
                              '${_sessions.length} Sesi',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0891B2)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Expanded(
                        child: _sessions.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.access_time_rounded, size: 32, color: Color(0xFF94A3B8)),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text('Belum ada sesi ujian ditambahkan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF475569))),
                                    const SizedBox(height: 4),
                                    const Text('Gunakan form di sebelah kiri untuk menambah sesi', style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _sessions.length,
                                itemBuilder: (ctx, idx) {
                                  final s = _sessions[idx];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0891B2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${idx + 1}',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s['name'] ?? 'Sesi ${idx + 1}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${s['startTime']} - ${s['endTime']}',
                                                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                          tooltip: 'Hapus Sesi',
                                          onPressed: () => setState(() => _sessions.removeAt(idx)),
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
              ),
            ],
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

  // ── Step 3: Timetable ──────────────────────────────────────────────────────
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
                final bool classesReady = classesSnap.hasData;
                final classes = classesSnap.data ?? [];
                final subjects = subjectsSnap.data ?? [];
                final teachers = teachersSnap.data ?? [];

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
                    _buildHeaderBanner(
                      stepNumber: 'Langkah 3',
                      title: 'Jadwal Mapel per Kelas',
                      subtitle: 'Pilih mata pelajaran, guru pembuat soal, dan kelas-kelas yang akan mengikuti ujian.',
                      icon: Icons.menu_book_rounded,
                      iconColor: const Color(0xFF10B981),
                    ),

                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Input Form
                          Expanded(
                            flex: 5,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.add_circle_outline_rounded, size: 18, color: Color(0xFF10B981)),
                                        SizedBox(width: 8),
                                        Text('Tambah Jadwal Mapel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                                      ],
                                    ),
                                    const SizedBox(height: 14),

                                    // Dropdown Mapel
                                    const Text('Pilih Mata Pelajaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      value: _selectedSubjectId,
                                      decoration: InputDecoration(
                                        hintText: 'Pilih mapel yang diujikan',
                                        prefixIcon: const Icon(Icons.book_rounded, color: Color(0xFF10B981), size: 18),
                                        filled: true,
                                        fillColor: Colors.white,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
                                      ),
                                      items: subjects.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String, style: const TextStyle(fontSize: 13)))).toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedSubjectId = val;
                                          _selectedTeacherIds.clear();
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 14),

                                    // Multi-select Kelas
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Pilih Kelas (${_selectedClassIds.length}/${classes.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                                        if (classes.isNotEmpty)
                                          InkWell(
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
                                                  width: 18,
                                                  height: 18,
                                                  child: Checkbox(
                                                    value: classes.isNotEmpty && classes.every((c) => _selectedClassIds.contains(c['id'])),
                                                    activeColor: const Color(0xFF10B981),
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
                                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    classes.isEmpty
                                        ? const Text('Belum ada kelas terdaftar.', style: TextStyle(color: Colors.red, fontSize: 12))
                                        : Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: classes.map((c) {
                                                final cid = c['id'] as String;
                                                final name = c['name'] as String;
                                                final isSelected = _selectedClassIds.contains(cid);
                                                return FilterChip(
                                                  label: Text(name, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                                  selected: isSelected,
                                                  selectedColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                  checkmarkColor: const Color(0xFF10B981),
                                                  backgroundColor: const Color(0xFFF1F5F9),
                                                  side: BorderSide(color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0)),
                                                  labelStyle: TextStyle(
                                                    color: isSelected ? const Color(0xFF065F46) : const Color(0xFF475569),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                                    const SizedBox(height: 14),

                                    // Dropdown Guru Custom Multi Select
                                    const Text('Guru Pembuat Soal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () {
                                        if (_selectedSubjectId == null) {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih mata pelajaran dahulu')));
                                          return;
                                        }
                                        final selectedSub = subjects.firstWhere((s) => s['id'] == _selectedSubjectId, orElse: () => {});
                                        _showTeacherMultiSelectDialog(context, selectedSub['name'] as String?, teachers);
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFCBD5E1)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.person_outline_rounded, color: Color(0xFF10B981), size: 18),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                _selectedTeacherIds.isEmpty
                                                    ? 'Pilih guru pembuat soal'
                                                    : teachers.where((t) => _selectedTeacherIds.contains(t.id)).map((t) => t.displayName).join(', '),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: _selectedTeacherIds.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),

                                    // Button Tambah
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _addTimetableEntry(subjects, teachers, classes),
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        label: const Text('Tambah ke Jadwal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF059669),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(vertical: 13),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Right: Grouped Timetable List
                          Expanded(
                            flex: 6,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.assignment_outlined, size: 18, color: Color(0xFF10B981)),
                                          SizedBox(width: 8),
                                          Text('Jadwal Mapel Terdaftar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFA7F3D0)),
                                        ),
                                        child: Text(
                                          '${groupedList.length} Mapel • ${_timetable.length} Entri',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF059669)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  Expanded(
                                    child: groupedList.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(14),
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFFF1F5F9),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(Icons.menu_book_rounded, size: 32, color: Color(0xFF94A3B8)),
                                                ),
                                                const SizedBox(height: 10),
                                                const Text('Belum ada jadwal mapel ditambahkan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF475569))),
                                                const SizedBox(height: 4),
                                                const Text('Pilih mapel, kelas, dan guru di panel kiri', style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
                                              ],
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: groupedList.length,
                                            itemBuilder: (ctx, idx) {
                                              final item = groupedList[idx];
                                              final classesList = (item['classes'] as List<String>)..sort();
                                              final isAll = classesList.length == classes.length && classes.isNotEmpty;
                                              final classesText = isAll ? 'Semua Kelas (${classesList.length} Kelas)' : classesList.join(', ');

                                              return Container(
                                                margin: const EdgeInsets.only(bottom: 8),
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8FAFC),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(Icons.menu_book_rounded, color: Color(0xFF10B981), size: 18),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            item['subjectName'] as String? ?? '-',
                                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                                                          ),
                                                          const SizedBox(height: 3),
                                                          Row(
                                                            children: [
                                                              const Icon(Icons.person_rounded, size: 13, color: Color(0xFF64748B)),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                'Guru: ${item['teacherName'] ?? '-'}',
                                                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(height: 3),
                                                          Row(
                                                            children: [
                                                              const Icon(Icons.group_rounded, size: 13, color: Color(0xFF64748B)),
                                                              const SizedBox(width: 4),
                                                              Expanded(
                                                                child: Text(
                                                                  'Kelas: $classesText',
                                                                  style: TextStyle(
                                                                    fontSize: 11.5,
                                                                    fontWeight: isAll ? FontWeight.bold : FontWeight.normal,
                                                                    color: isAll ? const Color(0xFF059669) : const Color(0xFF64748B),
                                                                  ),
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                                      tooltip: 'Hapus Mapel',
                                                      onPressed: () {
                                                        setState(() {
                                                          _timetable.removeWhere((t) => t['subjectId'] == item['subjectId']);
                                                        });
                                                      },
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

  // ── Step 4: Ruangan ────────────────────────────────────────────────────────
  Widget _buildStep4() {
    void showRoomDialog({Map<String, dynamic>? existing, int? index}) {
      final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
      final capCtrl = TextEditingController(text: existing != null ? '${(existing['capacity'] as num?)?.toInt() ?? ''}' : '');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.meeting_room_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 10),
              Text(existing == null ? 'Tambah Ruangan' : 'Edit Ruangan',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nama Ruangan',
                  hintText: 'Contoh: Ruang A1 / Lab Komputer',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.meeting_room_outlined, color: Color(0xFFD97706), size: 20),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: capCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Kapasitas Kursi',
                  hintText: 'Contoh: 30',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.event_seat_outlined, color: Color(0xFFD97706), size: 20),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
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
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              ),
              child: Text(existing == null ? 'Tambah Ruangan' : 'Simpan Perubahan', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final total = _rooms.fold<int>(0, (sum, r) => sum + ((r['capacity'] as num?)?.toInt() ?? 0));
        final avgCap = _rooms.isNotEmpty ? (total / _rooms.length).round() : 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderBanner(
              stepNumber: 'Langkah 4',
              title: 'Ruangan Ujian',
              subtitle: 'Kelola ruangan yang akan dipakai beserta kapasitas kursi masing-masing.',
              icon: Icons.meeting_room_rounded,
              iconColor: const Color(0xFFD97706),
              action: ElevatedButton.icon(
                onPressed: () => showRoomDialog(),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Tambah Ruangan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),

            // Summary Banner
            if (_rooms.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.meeting_room_rounded, color: Color(0xFFD97706), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_rooms.length} Ruangan',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E), fontSize: 13),
                        ),
                      ],
                    ),
                    Container(height: 16, width: 1, color: const Color(0xFFFDE68A)),
                    Row(
                      children: [
                        const Icon(Icons.event_seat_rounded, color: Color(0xFFD97706), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '$total Total Kursi',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E), fontSize: 13),
                        ),
                      ],
                    ),
                    Container(height: 16, width: 1, color: const Color(0xFFFDE68A)),
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined, color: Color(0xFFD97706), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Rata-rata $avgCap kursi/ruang',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF92400E), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _rooms.isEmpty
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
                            child: const Icon(Icons.meeting_room_outlined, size: 36, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 12),
                          const Text('Belum ada ruangan ujian ditambahkan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF475569))),
                          const SizedBox(height: 4),
                          const Text('Klik tombol "Tambah Ruangan" di atas untuk menambahkan ruangan', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: const Icon(Icons.meeting_room_rounded, color: Color(0xFFD97706), size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['name'] as String? ?? '-',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.event_seat_rounded, size: 13, color: Color(0xFF64748B)),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$cap Kursi Tersedia',
                                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Color(0xFFD97706), size: 19),
                                    tooltip: 'Edit Ruangan',
                                    onPressed: () => showRoomDialog(existing: r, index: idx),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 19),
                                    tooltip: 'Hapus Ruangan',
                                    onPressed: () {
                                      setState(() => _rooms.removeAt(idx));
                                      _autoSaveDraft();
                                    },
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
                    // Shuffle deterministically based on room seed
                    final seed = ((selectedRoom['id'] as String? ?? '').hashCode.abs() + 42) % 100000;
                    final shuffled = List<Color?>.from(classTokens)..shuffle(Random(seed));
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
                                    : (() {
                                          final sortedClasses = List<Map<String, dynamic>>.from(classes);
                                          sortedClasses.sort((a, b) {
                                            final aId = a['id'] as String;
                                            final bId = b['id'] as String;
                                            final aTotal = _studentCountForClass(a);
                                            final bTotal = _studentCountForClass(b);
                                            
                                            int aAllocElsewhere = 0;
                                            _roomAssignments.forEach((roomId, list) {
                                              if (roomId != _selectedRoomId) {
                                                final found = list.firstWhere((asgn) => asgn['classId'] == aId, orElse: () => {});
                                                if (found.isNotEmpty) aAllocElsewhere += (found['count'] as num).toInt();
                                              }
                                            });
                                            
                                            int bAllocElsewhere = 0;
                                            _roomAssignments.forEach((roomId, list) {
                                              if (roomId != _selectedRoomId) {
                                                final found = list.firstWhere((asgn) => asgn['classId'] == bId, orElse: () => {});
                                                if (found.isNotEmpty) bAllocElsewhere += (found['count'] as num).toInt();
                                              }
                                            });
                                            
                                            final aExistingIdx = _roomAssignments[_selectedRoomId]?.indexWhere((asgn) => asgn['classId'] == aId) ?? -1;
                                            final aCurrentAssigned = aExistingIdx >= 0 ? (_roomAssignments[_selectedRoomId]![aExistingIdx]['count'] as num).toInt() : 0;
                                            
                                            final bExistingIdx = _roomAssignments[_selectedRoomId]?.indexWhere((asgn) => asgn['classId'] == bId) ?? -1;
                                            final bCurrentAssigned = bExistingIdx >= 0 ? (_roomAssignments[_selectedRoomId]![bExistingIdx]['count'] as num).toInt() : 0;
                                            
                                            final aRemaining = (aTotal - aAllocElsewhere - aCurrentAssigned).clamp(0, aTotal);
                                            final bRemaining = (bTotal - bAllocElsewhere - bCurrentAssigned).clamp(0, bTotal);
                                            
                                            final aFully = aTotal > 0 && aRemaining == 0;
                                            final bFully = bTotal > 0 && bRemaining == 0;
                                            
                                            if (aFully && !bFully) return 1;
                                            if (!aFully && bFully) return -1;
                                            
                                            final aName = a['name'] as String? ?? '';
                                            final bName = b['name'] as String? ?? '';
                                            return aName.compareTo(bName);
                                          });

                                          return ListView.separated(
                                            itemCount: sortedClasses.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                                            itemBuilder: (_, ci) {
                                              final cls = sortedClasses[ci];
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

                                              final bool isFullyAllocated = totalStudents > 0 && remainingAvailable == 0;
                                              final originalIdx = classes.indexWhere((c) => c['id'] == cid);

                                              return Container(
                                                padding: const EdgeInsets.all(14),
                                                decoration: BoxDecoration(
                                                  color: isFullyAllocated
                                                      ? const Color(0xFFF1F5F9)
                                                      : (currentAssignedCount > 0 ? const Color(0xFFF0FDF4) : Colors.white),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: isFullyAllocated
                                                        ? const Color(0xFFCBD5E1)
                                                        : (currentAssignedCount > 0 ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
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
                                                            color: isFullyAllocated
                                                                ? const Color(0xFFE2E8F0)
                                                                : classColors[originalIdx % classColors.length].withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Icon(
                                                            Icons.class_outlined,
                                                            color: isFullyAllocated
                                                                ? const Color(0xFF64748B)
                                                                : classColors[originalIdx % classColors.length],
                                                            size: 16,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 10),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                cname,
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 14,
                                                                  color: isFullyAllocated ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                                                                ),
                                                              ),
                                                              Text(
                                                                'Tersedia: $remainingAvailable dari $totalStudents murid terdaftar',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: isFullyAllocated ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        if (currentAssignedCount > 0) ...[
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                            decoration: BoxDecoration(
                                                              color: isFullyAllocated ? const Color(0xFFE2E8F0) : const Color(0xFFDCFCE7),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Text(
                                                              '$currentAssignedCount murid dialokasikan',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.bold,
                                                                color: isFullyAllocated ? const Color(0xFF64748B) : const Color(0xFF166534),
                                                              ),
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
                                                        MouseRegion(
                                                          cursor: isFullyAllocated
                                                              ? SystemMouseCursors.basic
                                                              : SystemMouseCursors.click,
                                                          child: GestureDetector(
                                                            onTap: isFullyAllocated ? null : () {
                                                              if (remainingAvailable <= 0) return;
                                                              final remainingSeats = roomCapacity - totalAssigned;
                                                              if (remainingSeats <= 0) {
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  const SnackBar(
                                                                    content: Text('Kapasitas ruangan tidak cukup!'),
                                                                    backgroundColor: Colors.red,
                                                                  ),
                                                                );
                                                                return;
                                                              }
                                                              if (remainingAvailable > remainingSeats) {
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('Kapasitas ruangan tidak cukup! Tersisa $remainingSeats kursi, tetapi Anda mencoba memasukkan $remainingAvailable murid.'),
                                                                    backgroundColor: Colors.red,
                                                                  ),
                                                                );
                                                                return;
                                                              }
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
                                                                color: isFullyAllocated
                                                                    ? const Color(0xFFE2E8F0)
                                                                    : ((existing != null && existing['isAll'] == true)
                                                                        ? const Color(0xFFE2E8F0)
                                                                        : const Color(0xFF10B981)),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: Text(
                                                                'Semua Murid',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: isFullyAllocated
                                                                      ? const Color(0xFF94A3B8)
                                                                      : ((existing != null && existing['isAll'] == true)
                                                                          ? const Color(0xFF64748B)
                                                                          : Colors.white),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        // Decrement Counter Button
                                                        InkWell(
                                                          onTap: isFullyAllocated ? null : () {
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
                                                              color: isFullyAllocated
                                                                  ? const Color(0xFFE2E8F0)
                                                                  : (currentAssignedCount > 0 ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9)),
                                                              border: Border.all(
                                                                color: isFullyAllocated
                                                                    ? Colors.transparent
                                                                    : (currentAssignedCount > 0 ? const Color(0xFFC7D2FE) : Colors.transparent),
                                                              ),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Icon(
                                                              Icons.remove_rounded,
                                                              size: 14,
                                                              color: isFullyAllocated
                                                                  ? const Color(0xFF94A3B8)
                                                                  : (currentAssignedCount > 0 ? const Color(0xFF4F46E5) : const Color(0xFF64748B)),
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 40,
                                                          child: Text(
                                                            '$currentAssignedCount',
                                                            textAlign: TextAlign.center,
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 13,
                                                              color: isFullyAllocated ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                                            ),
                                                          ),
                                                        ),
                                                        // Increment Counter Button
                                                        InkWell(
                                                          onTap: isFullyAllocated ? null : () {
                                                            if (remainingAvailable <= 0) return;
                                                            final remainingSeats = roomCapacity - totalAssigned;
                                                            if (remainingSeats <= 0) {
                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                const SnackBar(
                                                                  content: Text('Kapasitas ruangan tidak cukup!'),
                                                                  backgroundColor: Colors.red,
                                                                ),
                                                              );
                                                              return;
                                                            }
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
                                                              color: isFullyAllocated
                                                                  ? const Color(0xFFE2E8F0)
                                                                  : (remainingAvailable > 0
                                                                      ? const Color(0xFFEEF2FF)
                                                                      : const Color(0xFFF1F5F9)),
                                                              border: Border.all(
                                                                color: isFullyAllocated
                                                                    ? Colors.transparent
                                                                    : (remainingAvailable > 0
                                                                        ? const Color(0xFFC7D2FE)
                                                                        : Colors.transparent),
                                                              ),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Icon(
                                                              Icons.add_rounded,
                                                              size: 14,
                                                              color: isFullyAllocated
                                                                  ? const Color(0xFF94A3B8)
                                                                  : (remainingAvailable > 0
                                                                      ? const Color(0xFF4F46E5)
                                                                      : const Color(0xFF94A3B8)),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          );
                                        })() as Widget,
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

    setState(() {
      // 1. Reset all assignments
      for (var t in _timetable) {
        t['sessionId'] = null;
        t['sessionName'] = null;
      }

      // 2. Map subjects to the classes that take them
      final Map<String, Set<String>> subjectClasses = {};
      for (var t in _timetable) {
        final sid = t['subjectId'] as String? ?? '';
        final cid = t['classId'] as String? ?? '';
        if (sid.isNotEmpty && cid.isNotEmpty) {
          subjectClasses.putIfAbsent(sid, () => {}).add(cid);
        }
      }

      // 3. Group subjects that can run in parallel (no class takes both)
      final List<List<String>> subjectGroups = [];
      for (final sid in subjectClasses.keys) {
        final classes = subjectClasses[sid]!;
        bool placed = false;
        for (final group in subjectGroups) {
          bool canAddToGroup = true;
          for (final groupSid in group) {
            final groupClasses = subjectClasses[groupSid]!;
            if (classes.intersection(groupClasses).isNotEmpty) {
              canAddToGroup = false;
              break;
            }
          }
          if (canAddToGroup) {
            group.add(sid);
            placed = true;
            break;
          }
        }
        if (!placed) {
          subjectGroups.add([sid]);
        }
      }

      // 4. Distribute the groups across the slots
      final totalSlots = days.length * _sessions.length;
      for (int i = 0; i < subjectGroups.length; i++) {
        final group = subjectGroups[i];
        final slotIdx = i % totalSlots;
        final d = slotIdx ~/ _sessions.length;
        final s = slotIdx % _sessions.length;
        
        for (final sid in group) {
          for (var t in _timetable) {
            if (t['subjectId'] == sid) {
              t['sessionId'] = 'day_${d}_session_$s';
              t['sessionName'] = _sessions[s]['name'];
            }
          }
        }
      }
    });

    _autoSaveDraft();
  }

  // Step 6: Jadwal Mapel per Sesi per Hari
  Widget _buildStep6() {
    final days = _examDays();

    // Compute status of all timetable entries
    final totalSubjectsCount = _timetable.length;
    final scheduledSubjectsCount = _timetable.where((t) => t['sessionId'] != null).length;
    final unscheduledSubjectsCount = totalSubjectsCount - scheduledSubjectsCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderBanner(
          stepNumber: 'Langkah 6',
          title: 'Jadwal Ruangan',
          subtitle: 'Tentukan mata pelajaran ujian untuk masing-masing kelas di setiap ruangan secara rinci per sesi dan hari.',
          icon: Icons.calendar_month_rounded,
          iconColor: const Color(0xFF6366F1),
          action: ElevatedButton.icon(
            onPressed: _timetable.isEmpty
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        title: const Row(
                          children: [
                            Icon(Icons.auto_fix_high_rounded, color: Color(0xFF6366F1)),
                            SizedBox(width: 8),
                            Text('Generate Jadwal Otomatis?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        content: const Text(
                          'Semua mapel akan didistribusikan ke sesi secara otomatis berdasarkan pemetaan kelas di Step 3. Jadwal yang sudah ada akan ditimpa.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _autoGenerateSchedule();
                            },
                            child: const Text('Generate Jadwal', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: const Text('Generate Otomatis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Status Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(
                unscheduledSubjectsCount == 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: unscheduledSubjectsCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  unscheduledSubjectsCount == 0
                      ? 'Semua mapel kelas sudah terjadwal!'
                      : 'Menjadwalkan mapel per kelas: $scheduledSubjectsCount dari $totalSubjectsCount slot mapel telah diatur ($unscheduledSubjectsCount belum dijadwalkan).',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: unscheduledSubjectsCount == 0 ? const Color(0xFF047857) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: days.isEmpty
              ? const Center(child: Text('Belum ada tanggal pelaksanaan. Kembali ke Step 1.'))
              : _sessions.isEmpty
                  ? const Center(child: Text('Belum ada sesi ditambahkan. Kembali ke Step 2.'))
                  : _rooms.isEmpty
                      ? const Center(child: Text('Belum ada ruangan ditambahkan. Kembali ke Step 4.'))
                      : Builder(
                          builder: (context) {
                            // Safe check if index is out of bounds
                            if (_selectedStep6DayIdx >= days.length) {
                              _selectedStep6DayIdx = 0;
                            }
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Horizontal tab/day selector
                                SizedBox(
                                  height: 60,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: days.length,
                                    itemBuilder: (ctx, idx) {
                                      final day = days[idx];
                                      final isSelected = idx == _selectedStep6DayIdx;
                                      final dayLabel = ExamPdfGenerator.formatIndonesianDate(day);
                                      final parts = dayLabel.split(',');
                                      final dayName = parts[0].trim();
                                      final dateStr = parts.length > 1 ? parts[1].replaceAll(' 2026', '').trim() : dayLabel;
                                      
                                      return MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedStep6DayIdx = idx;
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 150),
                                            margin: const EdgeInsets.only(right: 12, bottom: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                                width: 1.5,
                                              ),
                                              boxShadow: isSelected
                                                  ? [
                                                      BoxShadow(
                                                        color: const Color(0xFF4F46E5).withOpacity(0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 2),
                                                      )
                                                    ]
                                                  : [],
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Hari ${idx + 1}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$dayName, $dateStr',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Selected day room schedule
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Card(
                                      margin: const EdgeInsets.only(bottom: 24),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                                      ),
                                      elevation: 0,
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          // Day Header
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            color: const Color(0xFF4F46E5),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.calendar_today_rounded, size: 16, color: Colors.white),
                                                const SizedBox(width: 8),
                                                Text(
                                                  ExamPdfGenerator.formatIndonesianDate(days[_selectedStep6DayIdx]),
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Rooms within Day
                                          ..._rooms.map((room) {
                                            final rid = room['id'] as String;
                                            final rname = room['name'] as String? ?? room['code'] as String;
                                            final roomClasses = _roomAssignments[rid] ?? [];

                                            return Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: const BoxDecoration(
                                                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Room Title Header
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.meeting_room_rounded, size: 18, color: Color(0xFF4F46E5)),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Ruangan: $rname',
                                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '(${roomClasses.length} kelas dialokasikan)',
                                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  if (roomClasses.isEmpty)
                                                    const Padding(
                                                      padding: EdgeInsets.only(left: 26, top: 4, bottom: 8),
                                                      child: Text(
                                                        'Belum ada kelas yang dimasukkan ke ruangan ini di Langkah 5.',
                                                        style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                                                      ),
                                                    )
                                                  else
                                                    // Sessions grid for this room
                                                    Padding(
                                                      padding: const EdgeInsets.only(left: 12),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: List.generate(_sessions.length, (sIdx) {
                                                          final session = _sessions[sIdx];
                                                          final sessionKey = 'day_${_selectedStep6DayIdx}_session_$sIdx';

                                                          return Container(
                                                            margin: const EdgeInsets.only(bottom: 12),
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFFF8FAFC),
                                                              borderRadius: BorderRadius.circular(8),
                                                              border: Border.all(color: const Color(0xFFF1F5F9)),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                // Session Label
                                                                Row(
                                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                  children: [
                                                                    Text(
                                                                      '${session['name']} (${session['startTime']} - ${session['endTime']})',
                                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155)),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const Divider(height: 16, color: Color(0xFFE2E8F0)),
                                                                // List of classes in the room to schedule mapel
                                                                ...roomClasses.map((cls) {
                                                                  final cid = cls['classId'] as String;
                                                                  final cname = cls['className'] as String;

                                                                  // Filter subjects mapped to this class in step 3
                                                                  final classSubjects = _timetable.where((t) => t['classId'] == cid).toList();

                                                                  final Map<String, String> uniqueClassSubs = {};
                                                                  for (var t in classSubjects) {
                                                                    final sid = t['subjectId'] as String? ?? '';
                                                                    final sname = t['subjectName'] as String? ?? sid;
                                                                    if (sid.isNotEmpty) {
                                                                      uniqueClassSubs[sid] = sname;
                                                                    }
                                                                  }

                                                                  // Find currently scheduled subject in this Day+Session
                                                                  final currentScheduledEntry = _timetable.firstWhere(
                                                                    (t) => t['classId'] == cid && t['sessionId'] == sessionKey,
                                                                    orElse: () => {},
                                                                  );
                                                                  final currentSubjectId = currentScheduledEntry.isNotEmpty
                                                                      ? currentScheduledEntry['subjectId'] as String?
                                                                      : null;

                                                                  return Padding(
                                                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                                                    child: Row(
                                                                      children: [
                                                                        Expanded(
                                                                          flex: 2,
                                                                          child: Row(
                                                                            children: [
                                                                              const Icon(Icons.class_rounded, size: 14, color: Color(0xFF64748B)),
                                                                              const SizedBox(width: 8),
                                                                              Text(
                                                                                cname,
                                                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        const SizedBox(width: 12),
                                                                        Expanded(
                                                                          flex: 3,
                                                                          child: Container(
                                                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                                                                            decoration: BoxDecoration(
                                                                              color: Colors.white,
                                                                              borderRadius: BorderRadius.circular(8),
                                                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                                                            ),
                                                                            child: DropdownButtonHideUnderline(
                                                                              child: DropdownButton<String?>(
                                                                                value: currentSubjectId,
                                                                                isDense: true,
                                                                                isExpanded: true,
                                                                                icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                                                                                hint: const Text('Pilih Mapel Ujian', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                                                                items: [
                                                                                  const DropdownMenuItem<String?>(
                                                                                    value: null,
                                                                                    child: Text(
                                                                                      'Belum Dijadwalkan',
                                                                                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                                                                                    ),
                                                                                  ),
                                                                                  ...uniqueClassSubs.entries.map((e) {
                                                                                    return DropdownMenuItem<String?>(
                                                                                      value: e.key,
                                                                                      child: Text(e.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                                                                    );
                                                                                  }),
                                                                                ],
                                                                                onChanged: (val) {
                                                                                  setState(() {
                                                                                    // 1. Clear this class's subject currently scheduled in this day/session
                                                                                    for (var t in _timetable) {
                                                                                      if (t['classId'] == cid && t['sessionId'] == sessionKey) {
                                                                                        t['sessionId'] = null;
                                                                                        t['sessionName'] = null;
                                                                                      }
                                                                                    }
                                                                                    // 2. Set the new subject to this day/session
                                                                                    if (val != null) {
                                                                                      final target = _timetable.firstWhere((t) => t['classId'] == cid && t['subjectId'] == val);
                                                                                      target['sessionId'] = sessionKey;
                                                                                      target['sessionName'] = session['name'];
                                                                                    }
                                                                                  });
                                                                                  _autoSaveDraft();
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
                                                        }),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
            _buildHeaderBanner(
              stepNumber: 'Langkah 7',
              title: 'Pengawas Ruangan',
              subtitle: 'Tentukan pengawas untuk setiap ruangan pada masing-masing sesi dan hari ujian.',
              icon: Icons.supervisor_account_rounded,
              iconColor: const Color(0xFF8B5CF6),
              action: ElevatedButton.icon(
                onPressed: teachers.isEmpty || days.isEmpty || _sessions.isEmpty || _rooms.isEmpty
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            title: const Row(
                              children: [
                                Icon(Icons.auto_fix_high_rounded, color: Color(0xFF8B5CF6)),
                                SizedBox(width: 8),
                                Text('Generate Pengawas Otomatis?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            content: const Text(
                              'Pengawas akan diacak dan ditugaskan ke setiap ruangan per sesi secara otomatis. Penugasan yang sudah ada akan ditimpa.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B5CF6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _autoGenerateProctors(teachers);
                                },
                                child: const Text('Generate Pengawas', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                label: const Text('Generate Otomatis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
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
                        : '${teachers.length} guru tersedia  •  ${_proctorGrid.length} slot sudah ada pengawas  •  ${days.length * _sessions.length * _rooms.length} total slot',
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
                          : _rooms.isEmpty
                              ? const Center(child: Text('Belum ada ruangan. Kembali ke Step 4.'))
                              : Builder(
                                  builder: (context) {
                                    if (_selectedStep7DayIdx >= days.length) {
                                      _selectedStep7DayIdx = 0;
                                    }
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // Horizontal day tab selector
                                        SizedBox(
                                          height: 60,
                                          child: ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: days.length,
                                            itemBuilder: (ctx, idx) {
                                              final day = days[idx];
                                              final isSelected = idx == _selectedStep7DayIdx;
                                              final dayLabel = ExamPdfGenerator.formatIndonesianDate(day);
                                              final parts = dayLabel.split(',');
                                              final dayName = parts[0].trim();
                                              final dateStr = parts.length > 1 ? parts[1].replaceAll(' 2026', '').trim() : dayLabel;
                                              return MouseRegion(
                                                cursor: SystemMouseCursors.click,
                                                child: GestureDetector(
                                                  onTap: () => setState(() => _selectedStep7DayIdx = idx),
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 150),
                                                    margin: const EdgeInsets.only(right: 12, bottom: 4),
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFFF8FAFC),
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(
                                                        color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFFE2E8F0),
                                                        width: 1.5,
                                                      ),
                                                      boxShadow: isSelected
                                                          ? [
                                                              BoxShadow(
                                                                color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                                                                blurRadius: 4,
                                                                offset: const Offset(0, 2),
                                                              )
                                                            ]
                                                          : [],
                                                    ),
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          'Hari ${idx + 1}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          '$dayName, $dateStr',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // Selected day: rooms grouped, sessions inside each room
                                        Expanded(
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: _rooms.map((room) {
                                                final rid = room['id'] as String;
                                                final rname = room['name'] as String? ?? room['code'] as String? ?? 'Ruangan';
                                                final roomClasses = _roomAssignments[rid] ?? [];
                                                final classNames = roomClasses.map((c) => c['className'] as String? ?? '').where((s) => s.isNotEmpty).join(', ');

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
                                                      // Room header
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                        decoration: const BoxDecoration(
                                                          color: Color(0xFF7C3AED),
                                                          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.meeting_room_rounded, size: 15, color: Colors.white70),
                                                            const SizedBox(width: 8),
                                                            Text(
                                                              rname,
                                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                            ),
                                                            if (classNames.isNotEmpty) ...[
                                                              const SizedBox(width: 8),
                                                              Expanded(
                                                                child: Text(
                                                                  '($classNames)',
                                                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                      // Session rows for this room
                                                      ...List.generate(_sessions.length, (sIdx) {
                                                        final session = _sessions[sIdx];
                                                        final gridKey = 'day_${_selectedStep7DayIdx}_session_${sIdx}_room_$rid';
                                                        final assignedTeacherId = _proctorGrid[gridKey];
                                                        final assignedTeacher = assignedTeacherId != null
                                                            ? teachers.firstWhere(
                                                                (t) => t.id == assignedTeacherId,
                                                                orElse: () => Teacher(id: '', displayName: '?', subjects: [], schoolId: '', gender: 'M', nip: '', disabled: false, archived: false, createdAt: DateTime.now(), updatedAt: DateTime.now()),
                                                              )
                                                            : null;

                                                        // Subjects scheduled in this day+session that belong to classes in this room
                                                        final sessionKey = 'day_${_selectedStep7DayIdx}_session_$sIdx';
                                                        final scheduledSubjectNames = _timetable
                                                            .where((t) => t['sessionId'] == sessionKey && roomClasses.any((rc) => rc['classId'] == t['classId']))
                                                            .map((t) => t['subjectName'] as String? ?? '')
                                                            .where((s) => s.isNotEmpty)
                                                            .toSet()
                                                            .toList();

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
                                                                width: 170,
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
                                                                    if (scheduledSubjectNames.isNotEmpty)
                                                                      Padding(
                                                                        padding: const EdgeInsets.only(top: 3),
                                                                        child: Text(
                                                                          '📖 ${scheduledSubjectNames.join(' & ')}',
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
                                                                          MouseRegion(
                                                                            cursor: SystemMouseCursors.click,
                                                                            child: GestureDetector(
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
                                                                          ),
                                                                        ],
                                                                      )
                                                                    : Builder(
                                                                        builder: (context) {
                                                                          // Cari ID guru yang sudah bertugas di ruangan LAIN pada hari dan sesi yang SAMA
                                                                          final busyTeacherIds = <String>{};
                                                                          for (final rm in _rooms) {
                                                                            final otherRid = rm['id'] as String;
                                                                            if (otherRid == rid) continue;
                                                                            final otherKey = 'day_${_selectedStep7DayIdx}_session_${sIdx}_room_$otherRid';
                                                                            final assignedId = _proctorGrid[otherKey];
                                                                            if (assignedId != null && assignedId.isNotEmpty) {
                                                                              busyTeacherIds.add(assignedId);
                                                                            }
                                                                          }

                                                                          final availableTeachers = teachers
                                                                              .where((t) => !busyTeacherIds.contains(t.id))
                                                                              .toList();

                                                                          return DropdownButtonHideUnderline(
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
                                                                                    const Icon(Icons.person_add_rounded, size: 14, color: Color(0xFF7C3AED)),
                                                                                    const SizedBox(width: 6),
                                                                                    Expanded(
                                                                                      child: Text(
                                                                                        availableTeachers.isEmpty
                                                                                            ? 'Semua guru bertugas di sesi ini'
                                                                                            : 'Pilih Pengawas',
                                                                                        style: TextStyle(
                                                                                          fontSize: 12,
                                                                                          color: availableTeachers.isEmpty
                                                                                              ? const Color(0xFF94A3B8)
                                                                                              : const Color(0xFF7C3AED),
                                                                                        ),
                                                                                        overflow: TextOverflow.ellipsis,
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                                items: availableTeachers.map((t) {
                                                                                  return DropdownMenuItem<String>(
                                                                                    value: t.id,
                                                                                    child: Text(t.displayName, style: const TextStyle(fontSize: 12)),
                                                                                  );
                                                                                }).toList(),
                                                                                onChanged: availableTeachers.isEmpty
                                                                                    ? null
                                                                                    : (val) {
                                                                                        if (val != null) {
                                                                                          setState(() => _proctorGrid[gridKey] = val);
                                                                                          _autoSaveDraft();
                                                                                        }
                                                                                      },
                                                                              ),
                                                                            ),
                                                                          );
                                                                        },
                                                                      ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      }),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ],
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
      for (final room in _rooms) {
        final rid = room['id'] as String;
        for (int s = 0; s < _sessions.length; s++) {
          // Cycle through the shuffled list if there are more slots than teachers
          _proctorGrid['day_${d}_session_${s}_room_$rid'] = shuffled[tIdx % shuffled.length].id;
          tIdx++;
        }
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
            _buildHeaderBanner(
              stepNumber: 'Langkah 8',
              title: 'Review & Finalisasi',
              subtitle: 'Periksa seluruh ringkasan konfigurasi ujian sebelum disimpan dan unduh jadwal format PDF.',
              icon: Icons.verified_rounded,
              iconColor: const Color(0xFF059669),
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Menyiapkan file PDF Jadwal per Kelas...'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                        await ExamPdfGenerator.downloadSchedulePerClass(
                          eventName: _nameController.text,
                          examType: _examType,
                          startDate: _startDate,
                          endDate: _endDate,
                          sessions: _sessions,
                          timetable: _timetable,
                          rooms: _rooms,
                          roomAssignments: _roomAssignments,
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Gagal membuat PDF: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 15),
                    label: const Text('Jadwal per Kelas', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: const BorderSide(color: Color(0xFF10B981)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Menyiapkan file PDF Jadwal Pengawas...'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                        await ExamPdfGenerator.downloadProctorSchedule(
                          eventName: _nameController.text,
                          examType: _examType,
                          startDate: _startDate,
                          endDate: _endDate,
                          sessions: _sessions,
                          timetable: _timetable,
                          proctorGrid: _proctorGrid,
                          rooms: _rooms,
                          roomAssignments: _roomAssignments,
                          teachers: teacherMaps,
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Gagal membuat PDF Pengawas: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.supervisor_account_rounded, size: 15),
                    label: const Text('Jadwal Pengawas', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
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
                            final subClasses = _timetable
                                .where((t) => t['subjectId'] == sub['id'])
                                .map((t) => t['className'] as String? ?? '-')
                                .toSet()
                                .toList()..sort();
                            // Count total unique classes in the entire timetable to detect 'all classes'
                            final totalUniqueClasses = _timetable
                                .map((t) => t['classId'] as String? ?? '')
                                .where((id) => id.isNotEmpty)
                                .toSet()
                                .length;
                            final subClassIds = _timetable
                                .where((t) => t['subjectId'] == sub['id'])
                                .map((t) => t['classId'] as String? ?? '')
                                .where((id) => id.isNotEmpty)
                                .toSet()
                                .length;
                            final classesLabel = totalUniqueClasses > 0 && subClassIds == totalUniqueClasses
                                ? 'Semua Kelas'
                                : subClasses.join(', ');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 5),
                                    decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '${sub['name']}  →  $classesLabel',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        Builder(builder: (_) {
                                          final subjectId = sub['id'] as String? ?? '';
                                          // Not yet checked – trigger check
                                          if (!_subjectHasQuestions.containsKey(subjectId)) {
                                            WidgetsBinding.instance.addPostFrameCallback(
                                              (_) => _checkSubjectsHaveQuestions(),
                                            );
                                            return const SizedBox.shrink();
                                          }
                                          if (_subjectHasQuestions[subjectId] == true) {
                                            return const SizedBox.shrink();
                                          }
                                          return Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEE2E2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFFCA5A5)),
                                            ),
                                            child: const Text(
                                              'Belum ada soal',
                                              style: TextStyle(fontSize: 9, color: Color(0xFFB91C1C), fontWeight: FontWeight.bold),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
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
                    title: 'Step 6 — Jadwal Ujian per Sesi',
                    icon: Icons.calendar_month_rounded,
                    iconColor: const Color(0xFF4F46E5),
                    children: days.isEmpty
                        ? [const Text('Belum ada hari pelaksanaan.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : days.asMap().entries.map((de) {
                            final dayLabel = ExamPdfGenerator.formatIndonesianDate(de.value);
                            final sessionWidgets = List.generate(_sessions.length, (si) {
                              final session = _sessions[si];
                              return Padding(
                                padding: const EdgeInsets.only(left: 12, bottom: 2),
                                child: Text(
                                  '${session['name']}  •  ${session['startTime']} - ${session['endTime']}',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF475569)),
                                ),
                              );
                            });
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                                  child: Text(dayLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                ),
                                ...sessionWidgets,
                              ],
                            );
                          }).toList(),
                  ),

                  // Step 7: Pengawas
                  _reviewCard(
                    title: 'Step 7 — Pengawas Ruangan (${_proctorGrid.length} Penugasan)',
                    icon: Icons.supervisor_account_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    children: days.isEmpty || teachers.isEmpty || _rooms.isEmpty
                        ? [const Text('Belum ada pengawas ditugaskan.', style: TextStyle(fontSize: 12, color: Colors.red))]
                        : days.asMap().entries.map((de) {
                            final dayLabel = ExamPdfGenerator.formatIndonesianDate(de.value);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                                  child: Text(dayLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                ),
                                ..._rooms.map((room) {
                                  final rid = room['id'] as String;
                                  final rname = room['name'] as String? ?? room['code'] as String? ?? 'Ruangan';
                                  final proctorTexts = List.generate(_sessions.length, (si) {
                                    final key = 'day_${de.key}_session_${si}_room_$rid';
                                    final tid = _proctorGrid[key];
                                    final tname = tid != null
                                        ? (teachers.firstWhere((t) => t.id == tid, orElse: () => Teacher(id: '', displayName: '?', subjects: [], schoolId: '', gender: 'M', nip: '', disabled: false, archived: false, createdAt: DateTime.now(), updatedAt: DateTime.now())).displayName)
                                        : '—';
                                    return '${_sessions[si]['name']}: $tname';
                                  });
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 12, bottom: 2),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(width: 100, child: Text(rname, style: const TextStyle(fontSize: 10, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600))),
                                        Expanded(child: Text(proctorTexts.join('  |  '), style: const TextStyle(fontSize: 10, color: Color(0xFF475569)))),
                                      ],
                                    ),
                                  );
                                }),
                              ],
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

  /// Save detailed rooms and seats documents/subcollections to Firestore matching Step 5 roomAssignments & roomLayouts
  Future<void> _saveDetailedRoomsAndSeatsToFirestore(String schoolId, String eventId, String allocationId) async {
    try {
      final allocDocRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId)
          .collection('allocations')
          .doc(allocationId);

      // Fetch real active students
      final studentSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .where('archived', isEqualTo: false)
          .get();

      final Map<String, List<Map<String, dynamic>>> classRealStudents = {};
      for (var doc in studentSnap.docs) {
        final data = doc.data();
        if (data['disabled'] == true) continue;
        final sName = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final sNis = (data['nis'] ?? '').toString().trim();
        final sAngkatan = (data['angkatan'] ?? '').toString().trim();
        final sGender = (data['gender'] ?? 'M').toString().trim();
        final sClass = (data['className'] ?? data['classId'] ?? 'Siswa').toString().trim();

        if (sName.isNotEmpty) {
          classRealStudents.putIfAbsent(sClass, () => []).add({
            'studentId': doc.id,
            'studentName': sName,
            'displayName': sName,
            'nis': sNis,
            'angkatan': sAngkatan,
            'gender': sGender,
            'className': sClass,
            'classId': sClass,
            'participantNumber': sNis.isNotEmpty ? sNis : doc.id,
          });
        }
      }

      classRealStudents.forEach((cName, list) {
        list.sort((a, b) => naturalCompare(a['studentName'] as String, b['studentName'] as String));
      });

      final skipCountMap = <String, int>{};

      for (var rMap in _rooms) {
        final roomId = (rMap['id'] ?? rMap['code'] ?? rMap['name'] ?? '').toString();
        final roomName = (rMap['name'] ?? rMap['code'] ?? roomId).toString();
        final roomCode = (rMap['code'] ?? rMap['name'] ?? roomId).toString();
        final roomCapacity = (rMap['capacity'] as num?)?.toInt() ?? 30;

        final layoutState = (_addState['layout_$roomId'] as Map?) ??
            (_addState['layout_$roomName'] as Map?) ??
            (_addState['layout_$roomCode'] as Map?) ??
            {};
        final arrangeMode = (layoutState['arrange'] ?? _allocationMode ?? 'normal').toString();
        final cols = (layoutState['colsPerPair'] ?? layoutState['columns'] ?? 4 as num).toInt();

        final assignedClasses = (_roomAssignments[roomId] as List?) ??
            (_roomAssignments[roomName] as List?) ??
            (_roomAssignments[roomCode] as List?) ??
            [];

        final List<Map<String, dynamic>> typedAssignments = assignedClasses.map((c) => Map<String, dynamic>.from(c as Map)).toList();

        final roomSeats = _buildSeatsFromRoomAssignments(
          assignedClassesInRoom: typedAssignments,
          capacity: roomCapacity,
          patternMode: arrangeMode,
          classRealStudents: classRealStudents,
          skipCountMap: Map.from(skipCountMap),
          roomId: roomId,
        );

        for (var a in typedAssignments) {
          final cName = (a['className'] ?? a['classId'] ?? '').toString().trim();
          final cnt = (a['count'] as num?)?.toInt() ?? 0;
          if (cName.isNotEmpty && cnt > 0) {
            skipCountMap[cName] = (skipCountMap[cName] ?? 0) + cnt;
          }
        }

        // Save room document in subcollection rooms/
        final roomDocRef = allocDocRef.collection('rooms').doc(roomId);
        await roomDocRef.set({
          'roomId': roomId,
          'roomName': roomName,
          'roomCode': roomCode,
          'capacity': roomCapacity,
          'mode': arrangeMode,
          'arrange': arrangeMode,
          'columns': cols,
          'totalAssigned': roomSeats.length,
          'assignedClasses': typedAssignments,
          'seats': roomSeats,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Save seat documents in subcollection seats/
        for (var seat in roomSeats) {
          final sNum = seat['seatNumber'];
          final seatDocRef = allocDocRef.collection('seats').doc('${roomId}_seat_$sNum');
          await seatDocRef.set({
            ...seat,
            'roomId': roomId,
            'roomName': roomName,
            'roomCode': roomCode,
            'mode': arrangeMode,
            'arrange': arrangeMode,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await allocDocRef.set({
        'runId': allocationId,
        'mode': _allocationMode,
        'status': 'finalized',
        'roomAssignments': _roomAssignments,
        'roomLayouts': _addState,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving detailed room allocations: $e');
    }
  }

  List<Map<String, dynamic>> _buildSeatsFromRoomAssignments({
    required List<Map<String, dynamic>> assignedClassesInRoom,
    required int capacity,
    required String patternMode,
    required Map<String, List<Map<String, dynamic>>> classRealStudents,
    required Map<String, int> skipCountMap,
    String roomId = '',
  }) {
    final List<Map<String, dynamic>> studentPool = [];

    for (var classGroup in assignedClassesInRoom) {
      final className = (classGroup['className'] ?? classGroup['classId'] ?? 'Kelas').toString().trim();
      final count = (classGroup['count'] as num?)?.toInt() ?? 0;
      final realList = classRealStudents[className] ?? [];
      final skipIndex = skipCountMap[className] ?? 0;

      for (int i = 0; i < count; i++) {
        final targetIndex = skipIndex + i;
        final paddedIndex = (targetIndex + 1).toString().padLeft(2, '0');

        String studentName = '';
        String nis = '';
        String angkatan = '';
        String gender = 'M';
        String participantNumber = '2026-${className.replaceAll(' ', '')}-$paddedIndex';

        if (targetIndex < realList.length) {
          final r = realList[targetIndex];
          studentName = (r['displayName'] ?? r['studentName'] ?? '').toString();
          nis = (r['nis'] ?? '').toString();
          angkatan = (r['angkatan'] ?? '').toString();
          gender = (r['gender'] ?? 'M').toString();
          if (r['participantNumber'] != null && r['participantNumber'].toString().isNotEmpty) {
            participantNumber = r['participantNumber'].toString();
          } else if (nis.isNotEmpty) {
            participantNumber = nis;
          }
        } else {
          final authName = _getAuthenticStudentNameAZ(className, targetIndex);
          studentName = authName['displayName']!;
          nis = authName['nis']!;
          angkatan = authName['angkatan']!;
          gender = authName['gender']!;
        }

        studentPool.add({
          'studentName': studentName,
          'displayName': studentName,
          'nis': nis,
          'angkatan': angkatan,
          'gender': gender,
          'classId': className,
          'className': className,
          'participantNumber': participantNumber,
        });
      }
    }

    final List<Map<String, dynamic>> resultSeats = [];
    if (studentPool.isEmpty) return resultSeats;

    final modeLower = patternMode.toLowerCase();

    if (modeLower == 'zigzag') {
      final classGroups = <String, List<Map<String, dynamic>>>{};
      for (var s in studentPool) {
        final cName = s['className'] as String;
        classGroups.putIfAbsent(cName, () => []).add(s);
      }

      final keys = classGroups.keys.toList();
      int seatNum = 1;
      bool hasMore = true;
      int step = 0;

      while (hasMore && seatNum <= capacity) {
        hasMore = false;
        for (var k in keys) {
          final list = classGroups[k]!;
          if (step < list.length && seatNum <= capacity) {
            final s = Map<String, dynamic>.from(list[step]);
            s['seatNumber'] = seatNum;
            resultSeats.add(s);
            seatNum++;
            hasMore = true;
          }
        }
        step++;
      }
    } else if (modeLower == 'acak' || modeLower == 'random') {
      final seed = (roomId.hashCode.abs() + 42) % 100000;
      final shuffledPool = List<Map<String, dynamic>>.from(studentPool)..shuffle(Random(seed));

      for (int idx = 0; idx < shuffledPool.length && (idx + 1) <= capacity; idx++) {
        final s = Map<String, dynamic>.from(shuffledPool[idx]);
        s['seatNumber'] = idx + 1;
        resultSeats.add(s);
      }
    } else {
      for (int idx = 0; idx < studentPool.length && (idx + 1) <= capacity; idx++) {
        final s = Map<String, dynamic>.from(studentPool[idx]);
        s['seatNumber'] = idx + 1;
        resultSeats.add(s);
      }
    }

    return resultSeats;
  }

  Map<String, String> _getAuthenticStudentNameAZ(String className, int index) {
    final List<Map<String, String>> namesAZ = [
      {'displayName': 'Ahmad Pratama', 'nis': '1001', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Budi Santoso', 'nis': '1002', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Citra Dewi', 'nis': '1003', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Deni Kurniawan', 'nis': '1004', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Eka Wijaya', 'nis': '1005', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Fajar Hidayat', 'nis': '1006', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Gita Permata', 'nis': '1007', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Hadi Kusuma', 'nis': '1008', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Indah Lestari', 'nis': '1009', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Joko Susilo', 'nis': '1010', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Kiki Amalia', 'nis': '1011', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Lia Safitri', 'nis': '1012', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Muhammad Rizky', 'nis': '1013', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Nur Hidayah', 'nis': '1014', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Oki Setiawan', 'nis': '1015', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Putri Rahayu', 'nis': '1016', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Qori Anggraini', 'nis': '1017', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Rahmat Hidayat', 'nis': '1018', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Siti Nurhaliza', 'nis': '1019', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Taufik Hidayat', 'nis': '1020', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Utami Putri', 'nis': '1021', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Vina Panduwinata', 'nis': '1022', 'angkatan': '2026', 'gender': 'F'},
      {'displayName': 'Wawan Setiawan', 'nis': '1023', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Xavier Pratama', 'nis': '1024', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Yudi Pratama', 'nis': '1025', 'angkatan': '2026', 'gender': 'M'},
      {'displayName': 'Zahra Amalia', 'nis': '1026', 'angkatan': '2026', 'gender': 'F'},
    ];

    final item = namesAZ[index % namesAZ.length];
    return {
      'displayName': item['displayName']!,
      'nis': item['nis']!,
      'angkatan': item['angkatan']!,
      'gender': item['gender']!,
    };
  }
}
