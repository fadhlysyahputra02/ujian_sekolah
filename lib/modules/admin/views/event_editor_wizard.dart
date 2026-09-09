library event_editor_wizard;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  String _getInitials(String name) {
    if (name.isEmpty) return 'S';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
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
  // roomId -> [ { classId, className, count, isAll, studentIds } ]
  Map<String, List<Map<String, dynamic>>> _roomAssignments = {};
  // Persist local selection UI configurations for each class
  final Map<String, Map<String, dynamic>> _addState = {};
  final Map<String, List<Map<String, dynamic>>> _cachedClassStudents = {};

  Future<List<Map<String, dynamic>>> _loadStudentsForClass(Map<String, dynamic> cls) async {
    final cid = (cls['id'] ?? '').toString();
    final cname = (cls['name'] ?? '').toString().trim();
    final cacheKey = '$cid-$cname';

    if (_cachedClassStudents.containsKey(cacheKey)) {
      return _cachedClassStudents[cacheKey]!;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .get();

      final List<Map<String, dynamic>> list = [];
      final cleanCname = cname.toLowerCase().replaceAll(' ', '');
      final cleanCid = cid.toLowerCase().replaceAll(' ', '');

      for (var doc in snap.docs) {
        final data = doc.data();
        if (data['archived'] == true || data['disabled'] == true) continue;

        final sClass = (data['className'] ?? data['classId'] ?? '').toString().trim();
        final cleanSClass = sClass.toLowerCase().replaceAll(' ', '');
        final sDocId = doc.id;

        bool belongs = (cls['studentIds'] is List && (cls['studentIds'] as List).contains(sDocId)) ||
            cleanSClass == cleanCname ||
            cleanSClass == cleanCid ||
            (cleanCname.isNotEmpty && cleanSClass.contains(cleanCname));

        if (belongs) {
          final sName = (data['displayName'] ?? data['name'] ?? 'Siswa').toString().trim();
          final sNis = (data['nis'] ?? '').toString().trim();
          final sGender = (data['gender'] ?? 'M').toString().trim();

          list.add({
            'studentId': sDocId,
            'studentName': sName,
            'displayName': sName,
            'nis': sNis,
            'gender': sGender,
            'className': cname,
            'classId': cid,
          });
        }
      }

      list.sort((a, b) => naturalCompare(a['studentName'] as String, b['studentName'] as String));
      _cachedClassStudents[cacheKey] = list;
      return list;
    } catch (e) {
      debugPrint('Error loading class students: $e');
      return [];
    }
  }

  /// Returns the list of students for a class who have NOT yet been allocated to any room (excluding excludeRoomId)
  List<Map<String, dynamic>> _getUnallocatedStudentsForClass(
    String classId,
    String className, {
    String? excludeRoomId,
  }) {
    final cleanClass = className.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
    final cacheKey = '$classId-$className';
    List<Map<String, dynamic>> allStudents = [];
    for (var entry in _cachedClassStudents.entries) {
      final k = entry.key.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
      if (entry.key == cacheKey || entry.key == classId || entry.key == className || (cleanClass.isNotEmpty && k.contains(cleanClass))) {
        allStudents = entry.value;
        if (allStudents.isNotEmpty) break;
      }
    }

    final Set<String> allocatedStudentIds = {};

    _roomAssignments.forEach((rId, assignments) {
      if (excludeRoomId != null && rId == excludeRoomId) return;
      for (var a in assignments) {
        final aClassId = (a['classId'] ?? '').toString();
        final aClassName = (a['className'] ?? '').toString();
        if (aClassId == classId || aClassName == className || aClassId == className || aClassName == classId) {
          final sIds = a['studentIds'];
          if (sIds is List && sIds.isNotEmpty) {
            for (var id in sIds) {
              allocatedStudentIds.add(id.toString());
            }
          } else {
            // Infer from count if studentIds is missing
            final count = (a['count'] as num?)?.toInt() ?? 0;
            int taken = 0;
            for (var s in allStudents) {
              final sId = (s['studentId'] ?? s['id'] ?? '').toString();
              if (sId.isNotEmpty && !allocatedStudentIds.contains(sId)) {
                allocatedStudentIds.add(sId);
                taken++;
                if (taken >= count) break;
              }
            }
          }
        }
      }
    });

    return allStudents.where((s) {
      final sId = (s['studentId'] ?? s['id'] ?? '').toString();
      return sId.isNotEmpty && !allocatedStudentIds.contains(sId);
    }).toList();
  }

  /// Assigns a target count of students from a class to a room, updating studentIds automatically
  void _assignClassStudentsToRoom({
    required String roomId,
    required String classId,
    required String className,
    required int targetCount,
  }) {
    _roomAssignments.putIfAbsent(roomId, () => []);
    final list = _roomAssignments[roomId]!;
    final idx = list.indexWhere((a) => a['classId'] == classId || a['className'] == className);

    if (targetCount <= 0) {
      if (idx >= 0) {
        list.removeAt(idx);
        if (list.isEmpty) _roomAssignments.remove(roomId);
      }
      return;
    }

    List<String> currentSelectedIds = [];
    if (idx >= 0 && list[idx]['studentIds'] is List) {
      currentSelectedIds = (list[idx]['studentIds'] as List).map((e) => e.toString()).toList();
    }

    final unallocated = _getUnallocatedStudentsForClass(classId, className, excludeRoomId: roomId);

    List<String> finalStudentIds = [];
    // Retain existing valid IDs up to targetCount
    for (var id in currentSelectedIds) {
      if (finalStudentIds.length < targetCount) {
        finalStudentIds.add(id);
      }
    }

    // Add unallocated students up to targetCount
    for (var s in unallocated) {
      if (finalStudentIds.length >= targetCount) break;
      final sId = (s['studentId'] ?? s['id'] ?? '').toString();
      if (sId.isNotEmpty && !finalStudentIds.contains(sId)) {
        finalStudentIds.add(sId);
      }
    }

    final actualCount = finalStudentIds.length;
    final entry = {
      'classId': classId,
      'className': className,
      'count': actualCount,
      'studentIds': finalStudentIds,
      'isAll': unallocated.length <= targetCount,
    };

    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
  }

  void _showClassStudentSelectionDialog(
    BuildContext context,
    Map<String, dynamic> cls,
    Map<String, dynamic> selectedRoom,
  ) async {
    final cid = (cls['id'] ?? '').toString();
    final cname = (cls['name'] ?? cls['className'] ?? '').toString().trim();
    final selectedRoomId = (selectedRoom['id'] ?? '').toString();
    final roomName = (selectedRoom['name'] ?? '-').toString();
    final int roomCapacity = (selectedRoom['capacity'] as num?)?.toInt() ?? 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
      ),
    );

    final allClassStudents = await _loadStudentsForClass(cls);

    if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;

    final roomAssignmentsList = _roomAssignments[selectedRoomId] ?? [];
    final existingClassAssignIdx = roomAssignmentsList.indexWhere((a) => a['classId'] == cid);
    final existingAssign = existingClassAssignIdx >= 0 ? roomAssignmentsList[existingClassAssignIdx] : null;

    int totalOtherClassesInRoom = 0;
    for (var a in roomAssignmentsList) {
      if (a['classId'] != cid) {
        totalOtherClassesInRoom += (a['count'] as num?)?.toInt() ?? 0;
      }
    }
    final int roomAvailableSeatsForThisClass = (roomCapacity - totalOtherClassesInRoom).clamp(0, roomCapacity);

    final Map<String, String> studentRoomMap = {};
    final Map<String, String> studentRoomIdMap = {};
    _roomAssignments.forEach((rId, list) {
      final rObj = _rooms.firstWhere((r) => r['id'] == rId, orElse: () => {'name': rId});
      final rN = (rObj['name'] ?? rId).toString();
      for (var a in list) {
        if (a['classId'] == cid && a['studentIds'] is List) {
          for (var sId in (a['studentIds'] as List)) {
            studentRoomMap[sId.toString()] = rN;
            studentRoomIdMap[sId.toString()] = rId;
          }
        }
      }
    });

    final Set<String> selectedStudentIds = {};
    if (existingAssign != null && existingAssign['studentIds'] is List && (existingAssign['studentIds'] as List).isNotEmpty) {
      for (var sId in (existingAssign['studentIds'] as List)) {
        selectedStudentIds.add(sId.toString());
      }
    } else {
      final int currentAssignedCount = existingAssign != null ? (existingAssign['count'] as num).toInt() : 0;
      int added = 0;
      for (var s in allClassStudents) {
        final sId = s['studentId'].toString();
        final currentRoomId = studentRoomIdMap[sId];
        if (currentRoomId == selectedRoomId || (currentRoomId == null && added < currentAssignedCount)) {
          selectedStudentIds.add(sId);
          added++;
        }
      }
    }

    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final filteredStudents = allClassStudents.where((s) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase().trim();
              final name = s['studentName'].toString().toLowerCase();
              final nis = s['nis'].toString().toLowerCase();
              return name.contains(q) || nis.contains(q);
            }).toList();

            final int currentSelectedCount = selectedStudentIds.length;
            final int remainingRoomCapacity = (roomCapacity - totalOtherClassesInRoom - currentSelectedCount).clamp(0, roomCapacity);

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 580,
                constraints: const BoxConstraints(maxHeight: 700),
                color: Colors.white,
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pilih Murid - Kelas $cname',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Alokasi ke Ruangan: "$roomName"',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFFC7D2FE),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                                onPressed: () => Navigator.of(dialogCtx).pop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _buildWizardBadge(
                                icon: Icons.people_rounded,
                                label: 'Terpilih: $currentSelectedCount / ${allClassStudents.length} Murid',
                                color: const Color(0xFFEEF2FF),
                                textColor: const Color(0xFF3730A3),
                              ),
                              const SizedBox(width: 8),
                              _buildWizardBadge(
                                icon: Icons.event_seat_rounded,
                                label: 'Sisa Kursi Ruang: $remainingRoomCapacity',
                                color: remainingRoomCapacity > 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                textColor: remainingRoomCapacity > 0 ? const Color(0xFF047857) : const Color(0xFFDC2626),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Search & Controls Row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        children: [
                          TextField(
                            onChanged: (val) => setDialogState(() => searchQuery = val),
                            decoration: InputDecoration(
                              hintText: 'Cari nama murid atau NIS...',
                              hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  setDialogState(() {
                                    int availableSlots = roomAvailableSeatsForThisClass;
                                    selectedStudentIds.clear();
                                    for (var s in allClassStudents) {
                                      if (selectedStudentIds.length < availableSlots) {
                                        selectedStudentIds.add(s['studentId'].toString());
                                      }
                                    }
                                  });
                                },
                                icon: const Icon(Icons.select_all_rounded, size: 16),
                                label: const Text('Pilih Semua Sisa'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: const Color(0xFF4F46E5),
                                  side: const BorderSide(color: Color(0xFFC7D2FE)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setDialogState(() {
                                    selectedStudentIds.clear();
                                  });
                                },
                                icon: const Icon(Icons.deselect_rounded, size: 16),
                                label: const Text('Kosongkan'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: const Color(0xFFEF4444),
                                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Student List View
                    Expanded(
                      child: filteredStudents.isEmpty
                          ? Center(
                              child: Text(
                                searchQuery.isNotEmpty ? 'Tidak ada murid yang cocok dengan pencarian.' : 'Belum ada data murid di kelas ini.',
                                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: filteredStudents.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (lCtx, index) {
                                final s = filteredStudents[index];
                                final sId = s['studentId'].toString();
                                final sName = s['studentName'].toString();
                                final sNis = s['nis'].toString();
                                final sGender = s['gender'].toString();
                                final isSelected = selectedStudentIds.contains(sId);
                                final otherAssignedRoom = studentRoomMap[sId];

                                return InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      if (isSelected) {
                                        selectedStudentIds.remove(sId);
                                      } else {
                                        if (selectedStudentIds.length >= roomAvailableSeatsForThisClass) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Kapasitas ruangan "$roomName" sudah penuh ($roomCapacity kursi)!'),
                                              backgroundColor: Colors.red,
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                          return;
                                        }
                                        selectedStudentIds.add(sId);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: isSelected,
                                          activeColor: const Color(0xFF4F46E5),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          onChanged: (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                if (selectedStudentIds.length >= roomAvailableSeatsForThisClass) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Kapasitas ruangan "$roomName" sudah penuh ($roomCapacity kursi)!'),
                                                      backgroundColor: Colors.red,
                                                      duration: const Duration(seconds: 2),
                                                    ),
                                                  );
                                                  return;
                                                }
                                                selectedStudentIds.add(sId);
                                              } else {
                                                selectedStudentIds.remove(sId);
                                              }
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 6),
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                          child: Text(
                                            _getInitials(sName),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected ? Colors.white : const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                sName,
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                  color: const Color(0xFF0F172A),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'NIS: ${sNis.isNotEmpty ? sNis : "-"}   •   Gender: $sGender',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: const Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD1FAE5),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Di $roomName',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF047857),
                                              ),
                                            ),
                                          )
                                        else if (otherAssignedRoom != null && otherAssignedRoom.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Di $otherAssignedRoom',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFFD97706),
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Belum Dialokasikan',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                color: const Color(0xFF94A3B8),
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

                    // Footer Buttons
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('Batal'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              updateState(() {
                                _roomAssignments.putIfAbsent(selectedRoomId, () => []);
                                final list = _roomAssignments[selectedRoomId]!;
                                final idx = list.indexWhere((a) => a['classId'] == cid);

                                if (selectedStudentIds.isEmpty) {
                                  if (idx >= 0) {
                                    list.removeAt(idx);
                                    if (list.isEmpty) _roomAssignments.remove(selectedRoomId);
                                  }
                                } else {
                                  final newEntry = {
                                    'classId': cid,
                                    'className': cname,
                                    'count': selectedStudentIds.length,
                                    'studentIds': selectedStudentIds.toList(),
                                    'isAll': selectedStudentIds.length == allClassStudents.length,
                                  };
                                  if (idx >= 0) {
                                    list[idx] = newEntry;
                                  } else {
                                    list.add(newEntry);
                                  }
                                }

                                for (var sId in selectedStudentIds) {
                                  final prevRoomId = studentRoomIdMap[sId];
                                  if (prevRoomId != null && prevRoomId != selectedRoomId) {
                                    final prevList = _roomAssignments[prevRoomId];
                                    if (prevList != null) {
                                      final pIdx = prevList.indexWhere((a) => a['classId'] == cid);
                                      if (pIdx >= 0) {
                                        final pItem = prevList[pIdx];
                                        if (pItem['studentIds'] is List) {
                                          (pItem['studentIds'] as List).remove(sId);
                                          pItem['count'] = (pItem['studentIds'] as List).length;
                                          if ((pItem['count'] as int) <= 0) {
                                            prevList.removeAt(pIdx);
                                            if (prevList.isEmpty) _roomAssignments.remove(prevRoomId);
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              });

                              _autoSaveDraft();
                              Navigator.of(dialogCtx).pop();
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text('Simpan Alokasi (${selectedStudentIds.length} Murid)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWizardBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }


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

  // Real school students grouped by class name
  Map<String, List<Map<String, dynamic>>> _classRealStudentsMap = {};
  Map<String, List<Map<String, dynamic>>> get classRealStudentsMap => _classRealStudentsMap;
  List<Map<String, dynamic>> get rooms => _rooms;
  Map<String, List<Map<String, dynamic>>> get roomAssignments => _roomAssignments;

  Future<void> _loadRealSchoolStudents() async {
    if (_classRealStudentsMap.isNotEmpty) return;
    try {
      // 1. Fetch Classes mapping (studentIds -> className)
      final classSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('classes')
          .get();

      final Map<String, String> studentIdToClassName = {};
      for (var cDoc in classSnap.docs) {
        final cData = cDoc.data();
        final cName = (cData['name'] ?? cDoc.id).toString().trim();
        final sIds = cData['studentIds'];
        if (sIds is List) {
          for (var sId in sIds) {
            studentIdToClassName[sId.toString()] = cName;
          }
        }
      }

      // 2. Fetch Students
      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .get();

      final Map<String, List<Map<String, dynamic>>> map = {};
      for (var doc in snap.docs) {
        final data = doc.data();
        if (data['archived'] == true || data['disabled'] == true) continue;

        final sName = (data['displayName'] ?? data['name'] ?? data['fullName'] ?? '').toString().trim();
        final sNis = (data['nis'] ?? '').toString().trim();
        final sClass = (data['className'] ?? data['classId'] ?? studentIdToClassName[doc.id] ?? 'Siswa').toString().trim();

        if (sName.isNotEmpty) {
          final item = {
            'studentId': doc.id,
            'studentName': sName,
            'displayName': sName,
            'nis': sNis,
            'className': sClass,
          };
          map.putIfAbsent(sClass, () => []).add(item);

          final cleanKey = sClass.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
          if (cleanKey.isNotEmpty && cleanKey != sClass) {
            map.putIfAbsent(cleanKey, () => []).add(item);
          }
        }
      }

      map.forEach((cName, list) {
        list.sort((a, b) => naturalCompare(a['studentName'] as String, b['studentName'] as String));
      });

      _classRealStudentsMap = map;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('⚠️ Error loading real students for wizard denah: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initOrLoadDraft();
      _loadRealSchoolStudents();
    });
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

      final s1 = data['step1'] as Map<String, dynamic>? ?? data;
      final s2 = data['step2'] as Map<String, dynamic>? ?? data;
      final s3 = data['step3'] as Map<String, dynamic>? ?? data;
      final s4 = data['step4'] as Map<String, dynamic>? ?? data;
      final s5 = data['step5'] as Map<String, dynamic>? ?? data;
      final s6 = data['step6'] as Map<String, dynamic>? ?? data;
      final s7 = data['step7'] as Map<String, dynamic>? ?? data;

      _nameController.text = s1['eventName'] as String? ?? '';
      _academicYearController.text = s1['academicYear'] as String? ?? '2026/2027';
      _descController.text = s1['description'] as String? ?? '';
      _examType = s1['examType'] as String? ?? 'UTS';
      if (s1['startDate'] != null) _startDate = DateTime.tryParse(s1['startDate'] as String);
      if (s1['endDate'] != null) _endDate = DateTime.tryParse(s1['endDate'] as String);

      _sessions.clear();
      if (s2['sessions'] is List) {
        _sessions.addAll((s2['sessions'] as List).cast<Map<String, dynamic>>());
      }
      
      _timetable.clear();
      if (s3['timetable'] is List) {
        _timetable.addAll((s3['timetable'] as List).cast<Map<String, dynamic>>());
      }
      
      _rooms.clear();
      if (s4['rooms'] is List) {
        _rooms.addAll((s4['rooms'] as List).cast<Map<String, dynamic>>());
      }

      _addState.clear();
      if (s5['roomLayouts'] is Map) {
        (s5['roomLayouts'] as Map).forEach((k, v) {
          if (v is Map) {
            _addState[k as String] = Map<String, dynamic>.from(v);
          }
        });
      }

      _roomAssignments.clear();
      if (s6['roomAssignments'] is Map) {
        (s6['roomAssignments'] as Map).forEach((k, v) {
          if (v is List) {
            _roomAssignments[k as String] = v.cast<Map<String, dynamic>>();
          }
        });
      }
      
      _scheduleGrid.clear();
      if (s6['scheduleGrid'] is Map) {
        (s6['scheduleGrid'] as Map).forEach((k, v) {
          if (v is List) {
            _scheduleGrid[k as String] = List<String>.from(v);
          } else if (v is String) {
            _scheduleGrid[k as String] = [v];
          }
        });
      }
      
      _proctorGrid.clear();
      if (s7['proctorGrid'] is Map) {
        (s7['proctorGrid'] as Map).forEach((k, v) {
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
      'eventName': _nameController.text.trim(), // Kept at root for Event List screen
      'updatedAt': DateTime.now().toIso8601String(),
      'step1': {
        'eventName': _nameController.text.trim(),
        'academicYear': _academicYearController.text.trim(),
        'description': _descController.text.trim(),
        'examType': _examType,
        'startDate': _startDate?.toIso8601String(),
        'endDate': _endDate?.toIso8601String(),
      },
      'step2': {
        'sessions': _sessions,
      },
      'step3': {
        'timetable': _timetable,
      },
      'step4': {
        'rooms': _rooms,
      },
      'step5': {
        'roomLayouts': _addState,
      },
      'step6': {
        'roomAssignments': _roomAssignments,
        'scheduleGrid': _scheduleGrid,
      },
      'step7': {
        'proctorGrid': _proctorGrid,
      },
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

        final name = _nameController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
        final type = _examType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
        final year = _academicYearController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
        
        String customDraftId = '${name}_${type}_${year}'.replaceAll(RegExp(r'^-+|-+$|_+$|^_+'), '');
        if (customDraftId.isEmpty || customDraftId == '__') {
          customDraftId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
        }

        if (_draftId != null && _draftId != customDraftId) {
          try {
            await draftsRef.doc(_draftId).delete();
          } catch (_) {}
        }
        
        await draftsRef.doc(customDraftId).set(draftData, SetOptions(merge: true));
        if (mounted && _draftId != customDraftId) setState(() => _draftId = customDraftId);
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

  double _saveProgress = 0.0;
  String _saveStatusMessage = 'Memulai proses pembuatan event...';
  int _saveCurrentStepIndex = 1;

  void _updateSaveProgress(double progress, String statusMessage, int stepIndex) {
    if (!mounted) return;
    setState(() {
      _saveProgress = progress.clamp(0.0, 1.0);
      _saveStatusMessage = statusMessage;
      _saveCurrentStepIndex = stepIndex;
    });
  }

  Future<void> _submit() async {
    _updateSaveProgress(0.05, 'Inisialisasi dokumen event & jadwal sesi...', 1);
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

      final name = _nameController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      final type = _examType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      final year = _academicYearController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      
      String customEventId = '${name}_${type}_${year}'.replaceAll(RegExp(r'^-+|-+$|_+$|^_+'), '');
      if (customEventId.isEmpty || customEventId == '__') {
        customEventId = 'event_${DateTime.now().millisecondsSinceEpoch}';
      }

      final Set<String> targetClassesSet = {};
      for (var item in _timetable) {
        final cName = (item['className'] ?? item['classId'] ?? '').toString().trim();
        if (cName.isNotEmpty) targetClassesSet.add(cName);
      }

      final eventId = await _eventService.createEvent(
        schoolId: widget.schoolId,
        eventId: widget.eventId ?? _draftId ?? customEventId,
        eventInfo: {
          'name': _nameController.text.trim(),
          'type': _examType,
          'academicYear': _academicYearController.text.trim(),
          'startDate': _startDate!.toIso8601String(),
          'endDate': _endDate!.toIso8601String(),
          'description': _descController.text.trim(),
          'participantNumberFormat': '[angkatan][roomCode][seatNumber]',
          'seatNumberPadding': _seatPadding,
          'targetClasses': targetClassesSet.toList(),
          'draftState': {
            'step': 7,
            'eventName': _nameController.text.trim(),
            'step1': {
              'eventName': _nameController.text.trim(),
              'academicYear': _academicYearController.text.trim(),
              'description': _descController.text.trim(),
              'examType': _examType,
              'startDate': _startDate?.toIso8601String(),
              'endDate': _endDate?.toIso8601String(),
            },
            'step2': {
              'sessions': _sessions,
            },
            'step3': {
              'timetable': _timetable,
            },
            'step4': {
              'rooms': _rooms,
            },
            'step5': {
              'roomLayouts': _addState,
            },
            'step6': {
              'roomAssignments': _roomAssignments,
              'scheduleGrid': _scheduleGrid,
            },
            'step7': {
              'proctorGrid': _proctorGrid,
            },
          },
          'roomAssignments': _roomAssignments,
          'roomLayouts': _addState,
        },
        sessions: expandedSessions,
        timetable: _timetable,
      );

      _updateSaveProgress(0.38, 'Menjalankan algoritma alokasi denah tempat duduk...', 2);
      await Future.delayed(const Duration(milliseconds: 200));

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

      _updateSaveProgress(0.62, 'Menyimpan tata letak ruangan & denah kursi siswa...', 3);
      await Future.delayed(const Duration(milliseconds: 200));

      // 2.5 Save per-room allocation subcollections & documents with exact room layout modes & student data
      await _saveDetailedRoomsAndSeatsToFirestore(widget.schoolId, eventId, allocationId);

      _updateSaveProgress(0.82, 'Menjenerasikan nomor peserta & penugasan pengawas...', 4);
      await Future.delayed(const Duration(milliseconds: 200));

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
                'dayIndex': d,
                'sessionIndex': s,
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

      _updateSaveProgress(0.95, 'Membuat pembersihan draft & memfinalisasi event...', 5);
      await Future.delayed(const Duration(milliseconds: 200));

      // 4. Delete draft on success
      if (_draftId != null) {
        await _deleteDraft();
      }

      _updateSaveProgress(1.0, 'Pembuatan event ujian berhasil diselesaikan!', 5);
      await Future.delayed(const Duration(milliseconds: 300));

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

  Widget _buildEventProcessingOverlay() {
    final percentInt = (_saveProgress * 100).toInt();

    final steps = [
      {'step': 1, 'title': 'Inisialisasi & Konfigurasi Event', 'desc': 'Membuat dokumen event & jadwal sesi'},
      {'step': 2, 'title': 'Algoritma Alokasi Tempat Duduk', 'desc': 'Mengkalkulasi alokasi denah & ruangan'},
      {'step': 3, 'title': 'Penyimpanan Ruangan & Kursi', 'desc': 'Menyimpan layout & peta denah siswa'},
      {'step': 4, 'title': 'Nomor Peserta & Pengawas', 'desc': 'Menjenerasikan nomor ujian & pengawas'},
      {'step': 5, 'title': 'Finalisasi & Pembersihan Draft', 'desc': 'Menyelesaikan pembuatan event'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.95),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 520,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Circular progress with center percentage text
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: _saveProgress > 0 ? _saveProgress : null,
                        strokeWidth: 8,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$percentInt%',
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Proses',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Memproses Event Ujian',
                  style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey(_saveStatusMessage),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync_rounded, size: 15, color: Color(0xFF059669)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _saveStatusMessage,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF047857),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _saveProgress > 0 ? _saveProgress : null,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Checkpoint Steps
                Column(
                  children: steps.map((item) {
                    final stepNum = item['step'] as int;
                    final title = item['title'] as String;
                    final desc = item['desc'] as String;

                    final bool isDone = _saveCurrentStepIndex > stepNum || _saveProgress >= 1.0;
                    final bool isCurrent = _saveCurrentStepIndex == stepNum && _saveProgress < 1.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDone
                                  ? const Color(0xFF10B981)
                                  : isCurrent
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFFF1F5F9),
                              border: Border.all(
                                color: isDone
                                    ? const Color(0xFF059669)
                                    : isCurrent
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Center(
                              child: isDone
                                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                  : isCurrent
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(
                                          '$stepNum',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: isCurrent || isDone ? FontWeight.bold : FontWeight.w500,
                                    color: isDone
                                        ? const Color(0xFF059669)
                                        : isCurrent
                                            ? const Color(0xFF1E40AF)
                                            : const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  desc,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

  bool _isReligionSubject(String subjectName) {
    final s = subjectName.toLowerCase();
    final religionKeywords = [
      'agama', 'religion', 'religius', 'relig',
      'islam', 'kristen', 'protestan', 'katolik', 'hindu', 'buddha', 'budha', 'konghucu', 'khonghucu',
      'paibp', 'pakk', 'pabp', 'pake', 'pai'
    ];
    return religionKeywords.any((kw) => s.contains(kw));
  }

  /// Auto-generate: scatter all subjects across (day × session) slots
  /// - Priority 1: Subjects taken by all/more classes are scheduled in earlier days.
  /// - Priority 2: Subjects taken by specific/fewer classes are scheduled in later days.
  /// - Order within same class-count priority is randomized (shuffled) instead of alphabetical.
  void _autoGenerateSchedule() {
    final days = _examDays();
    if (days.isEmpty || _sessions.isEmpty) return;

    final rng = Random();

    setState(() {
      // 1. Reset all assignments
      for (var t in _timetable) {
        t['sessionId'] = null;
        t['sessionName'] = null;
      }

      // 2. Map subjects to the set of classes that take them
      final Map<String, Set<String>> subjectClasses = {};
      for (var t in _timetable) {
        final sid = (t['subjectId'] ?? '').toString();
        final cid = (t['classId'] ?? '').toString();
        if (sid.isNotEmpty && cid.isNotEmpty) {
          subjectClasses.putIfAbsent(sid, () => {}).add(cid);
        }
      }

      if (subjectClasses.isEmpty) return;

      // 3. Group subjects by their class count (how many classes take this subject)
      final Map<int, List<String>> byCount = {};
      for (final sid in subjectClasses.keys) {
        final count = subjectClasses[sid]!.length;
        byCount.putIfAbsent(count, () => []).add(sid);
      }

      // Sort class counts in descending order (highest count first = all-class subjects first)
      final countsDesc = byCount.keys.toList()..sort((a, b) => b.compareTo(a));

      // Build ordered list: highest class count first, randomly shuffled within each priority tier
      final List<String> orderedSubjectIds = [];
      for (final cnt in countsDesc) {
        final tier = List<String>.from(byCount[cnt]!)..shuffle(rng);
        orderedSubjectIds.addAll(tier);
      }

      // 4. Group subjects into parallel slots (religion subjects share the same slot)
      final List<List<String>> subjectGroups = [];
      for (final sid in orderedSubjectIds) {
        final sampleT = _timetable.firstWhere((t) => t['subjectId'] == sid, orElse: () => {});
        final sName = (sampleT['subjectName'] ?? '').toString();
        final isRel = _isReligionSubject(sName);
        final classes = subjectClasses[sid]!;

        bool placed = false;
        for (final group in subjectGroups) {
          bool canAddToGroup = true;
          for (final groupSid in group) {
            final groupSampleT = _timetable.firstWhere((t) => t['subjectId'] == groupSid, orElse: () => {});
            final groupSName = (groupSampleT['subjectName'] ?? '').toString();
            final groupIsRel = _isReligionSubject(groupSName);

            // Religion subjects for same/all classes can be scheduled in the SAME parallel session slot
            if (isRel && groupIsRel) {
              continue;
            }

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

      // 5. Distribute groups across available day & session slots
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
    if (days.isEmpty || _sessions.isEmpty || _rooms.isEmpty) return;
    final rng = Random();
    _proctorGrid.clear();
    for (int d = 0; d < days.length; d++) {
      for (int s = 0; s < _sessions.length; s++) {
        // Kocok ulang guru untuk setiap kombinasi hari+sesi
        final shuffled = List<Teacher>.from(teachers)..shuffle(rng);
        // Assign satu guru per ruangan — tanpa pengulangan dalam satu sesi
        for (int rIdx = 0; rIdx < _rooms.length; rIdx++) {
          if (rIdx >= shuffled.length) break; // Guru tidak cukup, lewati ruangan ini
          final rid = (_rooms[rIdx]['id'] ?? '').toString();
          if (rid.isEmpty) continue;
          _proctorGrid['day_${d}_session_${s}_room_$rid'] = shuffled[rIdx].id;
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

      // Fetch classes mapping
      List<QueryDocumentSnapshot> classDocs = [];
      try {
        final classSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .get();
        classDocs = classSnap.docs;
      } catch (e) {
        throw 'Gagal mengambil data Kelas (classes): $e';
      }

      final Map<String, String> studentIdToClassName = {};
      for (var cDoc in classDocs) {
        final cData = cDoc.data() as Map<String, dynamic>;
        final cName = (cData['name'] ?? cDoc.id).toString().trim();
        final sIds = cData['studentIds'];
        if (sIds is List) {
          for (var sId in sIds) {
            studentIdToClassName[sId.toString()] = cName;
          }
        }
      }

      // Fetch real active students
      List<QueryDocumentSnapshot> studentDocs = [];
      try {
        final studentSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .get();
        studentDocs = studentSnap.docs;
      } catch (e) {
        throw 'Gagal mengambil data Siswa (students): $e';
      }

      final Map<String, List<Map<String, dynamic>>> classRealStudents = {};
      for (var doc in studentDocs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['archived'] == true) continue;
        if (data['disabled'] == true) continue;
        final sName = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final sNis = (data['nis'] ?? '').toString().trim();
        final sAngkatan = (data['angkatan'] ?? '').toString().trim();
        final sGender = (data['gender'] ?? 'M').toString().trim();
        final sClass = (data['className'] ?? data['classId'] ?? studentIdToClassName[doc.id] ?? 'Siswa').toString().trim();

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
        final cleanCode = _cleanRoomCode(roomName.isNotEmpty ? roomName : roomCode);

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
        final layoutSeed = (layoutState['seed'] as num?)?.toInt();

        final roomSeats = _buildSeatsFromRoomAssignments(
          assignedClassesInRoom: typedAssignments,
          capacity: roomCapacity,
          patternMode: arrangeMode,
          classRealStudents: classRealStudents,
          skipCountMap: Map.from(skipCountMap),
          roomId: roomId,
          customSeed: layoutSeed,
        );

        for (var a in typedAssignments) {
          final cName = (a['className'] ?? a['classId'] ?? '').toString().trim();
          final cnt = (a['count'] as num?)?.toInt() ?? 0;
          if (cName.isNotEmpty && cnt > 0) {
            skipCountMap[cName] = (skipCountMap[cName] ?? 0) + cnt;
          }
        }

        // Skip rooms subcollection — seats subcollection is sufficient
        debugPrint('[Wizard] Room $roomName ($cleanCode): ${roomSeats.length} seats generated.');

        // Save seat documents in batches of 500
        var batch = FirebaseFirestore.instance.batch();
        int batchCount = 0;
        int totalWritten = 0;

        for (var seat in roomSeats) {
          final sNum = seat['seatNumber'];
          final seatNumStr = sNum.toString().padLeft(3, '0');
          final sAngk = (seat['angkatan'] ?? '').toString();
          final yearStr = sAngk.isNotEmpty ? sAngk : '2026';
          final formattedParticipantNum = '$yearStr-$cleanCode-$seatNumStr';

          final seatDocRef = allocDocRef.collection('seats').doc('${roomId}_seat_$sNum');
          batch.set(seatDocRef, {
            ...seat,
            'roomId': roomId,
            'roomName': roomName,
            'roomCode': cleanCode,
            'participantNumber': formattedParticipantNum,
            'mode': arrangeMode,
            'arrange': arrangeMode,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          batchCount++;
          totalWritten++;

          if (batchCount >= 400) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            batchCount = 0;
          }
        }

        if (batchCount > 0) {
          await batch.commit();
        }

        debugPrint('[Wizard] Room $roomName: $totalWritten seats written to Firestore.');
      }

      // Update totalAssigned on allocation doc
      int grandTotal = 0;
      for (var rMap in _rooms) {
        final rId = (rMap['id'] ?? rMap['code'] ?? rMap['name'] ?? '').toString();
        final rName = (rMap['name'] ?? rMap['code'] ?? rId).toString();
        final rCode = (rMap['code'] ?? rMap['name'] ?? rId).toString();
        final layoutS = (_addState['layout_$rId'] as Map?) ?? (_addState['layout_$rName'] as Map?) ?? (_addState['layout_$rCode'] as Map?) ?? {};
        final arr = (layoutS['arrange'] ?? _allocationMode ?? 'normal').toString();
        final assgn = (_roomAssignments[rId] as List?) ?? (_roomAssignments[rName] as List?) ?? (_roomAssignments[rCode] as List?) ?? [];
        final typed = assgn.map((c) => Map<String, dynamic>.from(c as Map)).toList();
        final seats = _buildSeatsFromRoomAssignments(
          assignedClassesInRoom: typed,
          capacity: (rMap['capacity'] as num?)?.toInt() ?? 30,
          patternMode: arr,
          classRealStudents: {},
          skipCountMap: {},
          roomId: rId,
        );
        grandTotal += seats.length;
      }

      // Save main allocation metadata
      try {
        await allocDocRef.set({
          'runId': allocationId,
          'mode': _allocationMode,
          'status': 'finalized',
          'roomAssignments': _roomAssignments,
          'roomLayouts': _addState,
          'totalAssigned': grandTotal,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        throw 'Gagal memperbarui metadata Alokasi: $e';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Alokasi berhasil disimpan! Total $grandTotal bangku ujian terdaftar.'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 5),
          ),
        );
      }

    } catch (e, stack) {
      debugPrint('Error saving detailed room allocations: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  String _cleanRoomCode(String raw) {
    if (raw.trim().isEmpty) return '00';
    String str = raw.trim();
    str = str.replaceAll(RegExp(r'^(ruangan|ruang|room|r\.?)\s+', caseSensitive: false), '');
    if (RegExp(r'^\d+$').hasMatch(str)) {
      return str.padLeft(2, '0');
    }
    return str;
  }

  List<Map<String, dynamic>> _buildSeatsFromRoomAssignments({
    required List<Map<String, dynamic>> assignedClassesInRoom,
    required int capacity,
    required String patternMode,
    required Map<String, List<Map<String, dynamic>>> classRealStudents,
    required Map<String, int> skipCountMap,
    String roomId = '',
    int? customSeed,
  }) {
    final List<Map<String, dynamic>> studentPool = [];

    for (var classGroup in assignedClassesInRoom) {
      final classId = (classGroup['classId'] ?? '').toString().trim();
      final className = (classGroup['className'] ?? classGroup['classId'] ?? 'Kelas').toString().trim();
      final count = (classGroup['count'] as num?)?.toInt() ?? 0;
      final cleanClass = className.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
      final realList = classRealStudents[className] ?? classRealStudents[cleanClass] ?? [];
      final studentIdsList = (classGroup['studentIds'] is List)
          ? (classGroup['studentIds'] as List).map((e) => e.toString()).toList()
          : <String>[];

      final unallocatedList = _getUnallocatedStudentsForClass(
        classId.isNotEmpty ? classId : className,
        className,
        excludeRoomId: roomId,
      );

      for (int i = 0; i < count; i++) {
        Map<String, dynamic>? matchStudent;

        if (studentIdsList.isNotEmpty && i < studentIdsList.length) {
          final targetSid = studentIdsList[i];
          final found = realList.firstWhere(
            (r) => (r['studentId'] ?? r['id'] ?? '').toString() == targetSid,
            orElse: () => {},
          );
          if (found.isNotEmpty) {
            matchStudent = found;
          }
        }

        if (matchStudent == null) {
          if (i < unallocatedList.length) {
            matchStudent = unallocatedList[i];
          } else {
            final skipIndex = skipCountMap[className] ?? skipCountMap[cleanClass] ?? 0;
            final targetIndex = skipIndex + i;
            if (targetIndex < realList.length) {
              matchStudent = realList[targetIndex];
            }
          }
        }

        final paddedIndex = (i + 1).toString().padLeft(2, '0');
        String studentName = '';
        String nis = '';
        String angkatan = '';
        String gender = 'M';
        String participantNumber = '2026-${className.replaceAll(' ', '')}-$paddedIndex';
        String studentId = '';

        if (matchStudent != null && matchStudent.isNotEmpty) {
          studentId = (matchStudent['studentId'] ?? matchStudent['id'] ?? '').toString();
          studentName = (matchStudent['displayName'] ?? matchStudent['studentName'] ?? '').toString();
          nis = (matchStudent['nis'] ?? '').toString();
          angkatan = (matchStudent['angkatan'] ?? '').toString();
          gender = (matchStudent['gender'] ?? 'M').toString();
          if (matchStudent['participantNumber'] != null && matchStudent['participantNumber'].toString().isNotEmpty) {
            participantNumber = matchStudent['participantNumber'].toString();
          } else if (nis.isNotEmpty) {
            participantNumber = nis;
          }
        } else {
          studentName = 'Siswa $className #${i + 1}';
          nis = paddedIndex;
        }

        studentPool.add({
          'studentId': studentId,
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
      final seed = customSeed ?? ((roomId.hashCode.abs() + 42) % 100000);
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


}
