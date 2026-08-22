library event_editor_wizard;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/services/event_exam_service.dart';
import '../../../core/models/teacher.dart';
import '../../../core/utils/natural_sort.dart';
import 'exam_pdf_generator.dart';

part 'event_editor_wizard_mobile.dart';
part 'event_editor_wizard_web.dart';

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

  void updateState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  int _studentCountForClass(Map<String, dynamic> cls) {
    if (cls['studentIds'] is List) {
      return (cls['studentIds'] as List).length;
    }
    if (cls['studentCount'] != null) {
      return (cls['studentCount'] as num).toInt();
    }
    if (cls['meta'] is Map && cls['meta']['studentCount'] != null) {
      return (cls['meta']['studentCount'] as num).toInt();
    }
    return 0;
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
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return isDesktop ? buildWeb(context) : buildMobile(context);
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
