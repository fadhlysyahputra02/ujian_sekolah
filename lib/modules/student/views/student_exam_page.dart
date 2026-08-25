import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StudentExamPage extends StatefulWidget {
  final String schoolId;
  final String eventId;
  final String eventName;
  final String subjectId;
  final String subjectName;
  final String studentId;
  final String studentName;
  final String nis;
  final String className;
  final String sessionName;
  final String startTimeStr;
  final String endTimeStr;

  /// Angkatan siswa (misal '7', '8', '9') untuk filter soal
  final String angkatan;

  const StudentExamPage({
    super.key,
    required this.schoolId,
    required this.eventId,
    required this.eventName,
    required this.subjectId,
    required this.subjectName,
    required this.studentId,
    required this.studentName,
    required this.nis,
    required this.className,
    required this.sessionName,
    required this.startTimeStr,
    required this.endTimeStr,
    this.angkatan = '',
  });

  @override
  State<StudentExamPage> createState() => _StudentExamPageState();
}

class _StudentExamPageState extends State<StudentExamPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _questions = [];
  int _currentIndex = 0;

  // Student Multiple Choice Answers: questionId -> selectedOptionIndex (0 = A, 1 = B, 2 = C, etc.)
  final Map<String, int> _answers = {};

  // Student Essay Answers: questionId -> text answer
  final Map<String, String> _essayAnswers = {};

  // Controllers for Essay inputs
  final Map<String, TextEditingController> _essayControllers = {};

  // Doubts: questionId -> bool
  final Map<String, bool> _doubts = {};

  // Countdown Timer (ValueNotifier to avoid rebuilding the entire page every second!)
  Timer? _timer;
  late final ValueNotifier<int> _remainingSecondsNotifier = ValueNotifier<int>(3600);
  bool _isSubmitting = false;

  // Draft Debounce Timer
  Timer? _draftDebounceTimer;

  @override
  void initState() {
    super.initState();
    _calculateDurationAndStartTimer();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _draftDebounceTimer?.cancel();
    _remainingSecondsNotifier.dispose();
    for (var controller in _essayControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _lastSavedStateFingerprint = '';

  void _triggerDraftAutoSave() {
    _draftDebounceTimer?.cancel();
    // Debounce 3 seconds after user stops typing essay
    _draftDebounceTimer = Timer(const Duration(seconds: 3), () {
      _saveDraftToFirestore();
    });
  }

  String _getDraftFingerprint() {
    final answersForStorage = <String, dynamic>{};
    final essayAnswersForStorage = <String, String>{};

    for (var q in _questions) {
      final qId = q['id'].toString();
      final isEssay = _isEssayQuestion(q);
      if (isEssay) {
        final essayText = (_essayAnswers[qId] ?? '').trim();
        if (essayText.isNotEmpty) {
          answersForStorage[qId] = essayText;
          essayAnswersForStorage[qId] = essayText;
        }
      } else {
        final selectedIdx = _answers[qId];
        if (selectedIdx != null) {
          final label = String.fromCharCode(65 + selectedIdx);
          answersForStorage[qId] = label;
        }
      }
    }

    return jsonEncode({
      'answers': answersForStorage,
      'essayAnswers': essayAnswersForStorage,
      'doubts': _doubts,
    });
  }

  /// Saves current draft state to Firestore with isCompleted = false
  Future<void> _saveDraftToFirestore() async {
    if (widget.studentId.isEmpty || widget.schoolId.isEmpty || widget.eventId.isEmpty) {
      return;
    }
    if (_questions.isEmpty) {
      return;
    }

    final currentFingerprint = _getDraftFingerprint();
    if (currentFingerprint == _lastSavedStateFingerprint) {
      debugPrint('ℹ️ Draft state unchanged since last save. Skipping Firestore write.');
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final docId = '${widget.studentId}_${widget.subjectId}';
      final subRef = db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('submissions')
          .doc(docId);

      final answersForStorage = <String, dynamic>{};
      final essayAnswersForStorage = <String, String>{};

      for (var q in _questions) {
        final qId = q['id'].toString();
        final isEssay = _isEssayQuestion(q);
        if (isEssay) {
          final essayText = (_essayAnswers[qId] ?? '').trim();
          if (essayText.isNotEmpty) {
            answersForStorage[qId] = essayText;
            essayAnswersForStorage[qId] = essayText;
          }
        } else {
          final selectedIdx = _answers[qId];
          if (selectedIdx != null) {
            final label = String.fromCharCode(65 + selectedIdx);
            answersForStorage[qId] = label;
          }
        }
      }

      debugPrint('💾 Saving draft to submissions/$docId MC:${answersForStorage.length} Essay:${essayAnswersForStorage.length}');

      await subRef.set({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'nis': widget.nis,
        'className': widget.className,
        'angkatan': widget.angkatan,
        'subjectId': widget.subjectId,
        'subjectName': widget.subjectName,
        'answers': answersForStorage,
        'essayAnswers': essayAnswersForStorage,
        'doubts': Map<String, dynamic>.from(_doubts),
        'lastSavedAt': FieldValue.serverTimestamp(),
        'isCompleted': false,
      }, SetOptions(merge: true));

      _lastSavedStateFingerprint = currentFingerprint;
      debugPrint('✅ Draft saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving draft: $e');
    }
  }

  TextEditingController _getEssayController(String qId) {
    if (!_essayControllers.containsKey(qId)) {
      final initialText = _essayAnswers[qId] ?? '';
      final controller = TextEditingController(text: initialText);
      controller.addListener(() {
        final text = controller.text;
        if (_essayAnswers[qId] != text) {
          setState(() {
            _essayAnswers[qId] = text;
          });
          _triggerDraftAutoSave();
        }
      });
      _essayControllers[qId] = controller;
    }
    return _essayControllers[qId]!;
  }

  bool _isEssayQuestion(Map<String, dynamic> q) {
    final qType = (q['type'] ?? '').toString().toLowerCase().trim();
    if (qType == 'esai' || qType == 'essay' || qType == 'tertulis' || qType == 'uraian') {
      return true;
    }
    final rawOptions = q['options'];
    if ((qType.isEmpty) && (rawOptions == null || (rawOptions is Map && rawOptions.isEmpty) || (rawOptions is List && rawOptions.isEmpty))) {
      return true;
    }
    return false;
  }

  int get _answeredCount {
    int count = 0;
    for (var q in _questions) {
      final qId = q['id'].toString();
      if (_isEssayQuestion(q)) {
        if ((_essayAnswers[qId] ?? '').trim().isNotEmpty) {
          count++;
        }
      } else {
        if (_answers.containsKey(qId)) {
          count++;
        }
      }
    }
    return count;
  }

  /// Calculates remaining seconds from current time until endTimeStr (e.g. "14:30")
  void _calculateDurationAndStartTimer() {
    int totalSecs = 3600; // Default 60 mins fallback

    try {
      if (widget.endTimeStr.isNotEmpty) {
        final endParts = widget.endTimeStr.split(':');
        if (endParts.length >= 2) {
          final eh = int.parse(endParts[0].trim());
          final em = int.parse(endParts[1].trim());
          int es = 0;
          if (endParts.length >= 3) {
            es = int.tryParse(endParts[2].trim()) ?? 0;
          }

          final now = DateTime.now();
          final endDateTime = DateTime(now.year, now.month, now.day, eh, em, es);

          final remaining = endDateTime.difference(now).inSeconds;

          if (remaining > 0) {
            totalSecs = remaining;
          } else {
            totalSecs = 0; // Time has already expired
          }
        }
      }
    } catch (e) {
      debugPrint("Error calculating remaining time: $e");
      totalSecs = 3600;
    }

    _remainingSecondsNotifier.value = totalSecs;

    if (_remainingSecondsNotifier.value <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleTimeExpired();
      });
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSecondsNotifier.value > 0) {
        _remainingSecondsNotifier.value--;
      } else {
        _timer?.cancel();
        _handleTimeExpired();
      }
    });
  }

  bool _isAngkatanMatch(String qAngkatan, String studentAngkatan, String studentClass) {
    final qClean = qAngkatan.trim().toLowerCase();
    if (qClean.isEmpty || qClean == 'semua' || qClean == 'all' || qClean == '-') {
      return true; // Universal question for all grade levels
    }

    final sAngClean = studentAngkatan.trim().toLowerCase();
    final sClassClean = studentClass.trim().toLowerCase();

    // Exact match
    if (sAngClean.isNotEmpty && qClean == sAngClean) return true;
    if (sClassClean.isNotEmpty && qClean == sClassClean) return true;

    // Substring match
    if (sAngClean.isNotEmpty && (qClean.contains(sAngClean) || sAngClean.contains(qClean))) return true;
    if (sClassClean.isNotEmpty && (qClean.contains(sClassClean) || sClassClean.contains(qClean))) return true;

    // Extract numbers (e.g. '7' from '7-A' or 'kelas 7')
    final RegExp numReg = RegExp(r'\d+');
    final qNum = numReg.firstMatch(qClean)?.group(0);
    final sAngNum = numReg.firstMatch(sAngClean)?.group(0);
    final sClassNum = numReg.firstMatch(sClassClean)?.group(0);

    if (qNum != null && qNum.isNotEmpty) {
      if (sAngNum != null && sAngNum == qNum) return true;
      if (sClassNum != null && sClassNum == qNum) return true;
    }

    return false;
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      final eventRef = db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId);

      debugPrint('📚 Loading questions for student exam...');
      debugPrint('   schoolId   : ${widget.schoolId}');
      debugPrint('   eventId    : ${widget.eventId}');
      debugPrint('   subjectId  : "${widget.subjectId}"');
      debugPrint('   subjectName: "${widget.subjectName}"');
      debugPrint('   angkatan   : "${widget.angkatan}"');
      debugPrint('   className  : "${widget.className}"');

      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];

      // Path 1: events/{eventId}/subjects/{subjectId}/questions
      if (widget.subjectId.isNotEmpty) {
        try {
          final qSnap1 = await eventRef
              .collection('subjects')
              .doc(widget.subjectId)
              .collection('questions')
              .get();
          if (qSnap1.docs.isNotEmpty) {
            docs = qSnap1.docs;
            debugPrint('✅ Found ${docs.length} questions in subjects/${widget.subjectId}/questions');
          }
        } catch (e) {
          debugPrint('Path 1 failed: $e');
        }
      }

      // Path 2: events/{eventId}/subjects/{subjectName}/questions (if subjectName is different)
      if (docs.isEmpty && widget.subjectName.isNotEmpty) {
        try {
          final qSnap2 = await eventRef
              .collection('subjects')
              .doc(widget.subjectName)
              .collection('questions')
              .get();
          if (qSnap2.docs.isNotEmpty) {
            docs = qSnap2.docs;
            debugPrint('✅ Found ${docs.length} questions in subjects/${widget.subjectName}/questions');
          }
        } catch (e) {
          debugPrint('Path 2 failed: $e');
        }
      }

      // Path 3: Direct event subcollection events/{eventId}/questions with filters
      if (docs.isEmpty) {
        try {
          QuerySnapshot<Map<String, dynamic>> qSnap3;
          if (widget.angkatan.isNotEmpty) {
            qSnap3 = await eventRef
                .collection('questions')
                .where('subjectId', isEqualTo: widget.subjectId)
                .where('angkatan', isEqualTo: widget.angkatan)
                .get();

            if (qSnap3.docs.isEmpty) {
              qSnap3 = await eventRef
                  .collection('questions')
                  .where('subjectId', isEqualTo: widget.subjectId)
                  .get();
            }
          } else {
            qSnap3 = await eventRef
                .collection('questions')
                .where('subjectId', isEqualTo: widget.subjectId)
                .get();
          }

          if (qSnap3.docs.isNotEmpty) {
            docs = qSnap3.docs;
            debugPrint('✅ Found ${docs.length} questions in events/${widget.eventId}/questions (filtered)');
          }
        } catch (e) {
          debugPrint('Path 3 failed: $e');
        }
      }

      // Path 4: Unfiltered events/{eventId}/questions
      if (docs.isEmpty) {
        try {
          final qSnap4 = await eventRef.collection('questions').get();
          if (qSnap4.docs.isNotEmpty) {
            final matchedDocs = qSnap4.docs.where((d) {
              final data = d.data();
              final sId = (data['subjectId'] ?? data['subject'] ?? data['subjectName'] ?? '').toString();
              return sId == widget.subjectId || sId == widget.subjectName || sId.isEmpty;
            }).toList();

            docs = matchedDocs.isNotEmpty ? matchedDocs : qSnap4.docs;
            debugPrint('✅ Found ${docs.length} questions in events/${widget.eventId}/questions (unfiltered)');
          }
        } catch (e) {
          debugPrint('Path 4 failed: $e');
        }
      }

      // Path 5: Question banks fallback
      if (docs.isEmpty) {
        try {
          final evSnap = await eventRef.get();
          final evData = evSnap.data() ?? {};
          final subjectsList = evData['subjects'] as List? ?? [];
          String matchedBankId = '';

          for (var s in subjectsList) {
            if (s is Map && (s['id'] == widget.subjectId || s['name'] == widget.subjectName || s['subjectName'] == widget.subjectName)) {
              matchedBankId = (s['questionBankId'] ?? s['bankId'] ?? '').toString();
              break;
            }
          }

          if (matchedBankId.isNotEmpty) {
            final bankSnap = await db
                .collection('schools')
                .doc(widget.schoolId)
                .collection('question_banks')
                .doc(matchedBankId)
                .collection('items')
                .get();

            docs = bankSnap.docs;
            debugPrint('✅ Found ${docs.length} questions in question_banks/$matchedBankId/items');
          }
        } catch (e) {
          debugPrint('Path 5 failed: $e');
        }
      }

      final allQuestions = <Map<String, dynamic>>[];
      for (var d in docs) {
        final data = d.data();
        data['id'] = d.id;
        allQuestions.add(data);
      }

      // Filter strictly by student's angkatan & className
      List<Map<String, dynamic>> filteredQuestions = allQuestions.where((q) {
        final qAng = (q['angkatan'] ?? q['grade'] ?? q['targetAngkatan'] ?? '').toString();
        return _isAngkatanMatch(qAng, widget.angkatan, widget.className);
      }).toList();

      if (filteredQuestions.isNotEmpty) {
        debugPrint('🎯 Filtered ${filteredQuestions.length} / ${allQuestions.length} questions matching angkatan "${widget.angkatan}" / class "${widget.className}"');
      } else {
        debugPrint('⚠️ No questions matched angkatan filter strictly. Using all ${allQuestions.length} questions as fallback.');
        filteredQuestions = allQuestions;
      }

      // Sort by urutan/order/index
      filteredQuestions.sort((a, b) {
        final orderA = (a['urutan'] as num?) ?? (a['order'] as num?) ?? (a['index'] as num?) ?? 999;
        final orderB = (b['urutan'] as num?) ?? (b['order'] as num?) ?? (b['index'] as num?) ?? 999;
        return orderA.compareTo(orderB);
      });

      _questions = filteredQuestions;

      // Load draft submission if exists
      if (widget.studentId.isNotEmpty) {
        final docId = '${widget.studentId}_${widget.subjectId}';
        final subSnap = await db
            .collection('schools')
            .doc(widget.schoolId)
            .collection('events')
            .doc(widget.eventId)
            .collection('submissions')
            .doc(docId)
            .get();

        if (subSnap.exists) {
          final subData = subSnap.data() ?? {};
          final rawAnswers = subData['answers'] as Map<String, dynamic>? ?? {};
          final rawEssayAnswers = subData['essayAnswers'] as Map<String, dynamic>? ?? {};
          final rawDoubts = subData['doubts'] as Map<String, dynamic>? ?? {};

          for (var entry in rawAnswers.entries) {
            final qId = entry.key;
            final val = entry.value;

            // Find question to check type
            final qMatch = _questions.firstWhere((q) => q['id'].toString() == qId, orElse: () => {});
            if (qMatch.isNotEmpty && _isEssayQuestion(qMatch)) {
              _essayAnswers[qId] = val.toString();
            } else if (val is String && val.length == 1) {
              final code = val.codeUnitAt(0);
              if (code >= 65 && code <= 90) { // A-Z
                _answers[qId] = code - 65;
              } else if (code >= 97 && code <= 122) { // a-z
                _answers[qId] = code - 97;
              }
            } else if (val is num) {
              _answers[qId] = val.toInt();
            }
          }

          for (var entry in rawEssayAnswers.entries) {
            _essayAnswers[entry.key] = entry.value.toString();
          }

          for (var entry in rawDoubts.entries) {
            _doubts[entry.key] = entry.value == true;
          }
        }
      }

      _lastSavedStateFingerprint = _getDraftFingerprint();
      debugPrint('✅ Loaded ${_questions.length} questions successfully!');
    } catch (e) {
      debugPrint('❌ Error loading questions: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleTimeExpired() {
    if (_isSubmitting) return;
    _timer?.cancel();
    _saveAnswersToFirestore(autoSubmitted: true);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.timer_off_rounded, color: Color(0xFFDC2626), size: 28),
              const SizedBox(width: 10),
              Text('Waktu Ujian Habis', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            'Waktu pengerjaan mata pelajaran ${widget.subjectName} telah selesai. Jawaban Anda telah tersimpan otomatis oleh sistem.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Kembali ke Dashboard'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _saveAnswersToFirestore({bool autoSubmitted = false}) async {
    _isSubmitting = true;
    _timer?.cancel();
    _draftDebounceTimer?.cancel();

    try {
      final db = FirebaseFirestore.instance;
      final docId = '${widget.studentId}_${widget.subjectId}';

      final answersForStorage = <String, dynamic>{};
      final essayAnswersForStorage = <String, String>{};

      for (var q in _questions) {
        final qId = q['id'].toString();
        final isEssay = _isEssayQuestion(q);

        if (isEssay) {
          final essayText = (_essayAnswers[qId] ?? '').trim();
          if (essayText.isNotEmpty) {
            answersForStorage[qId] = essayText;
            essayAnswersForStorage[qId] = essayText;
          }
        } else {
          final selectedIdx = _answers[qId];
          if (selectedIdx != null) {
            final label = String.fromCharCode(65 + selectedIdx);
            answersForStorage[qId] = label;
          }
        }
      }

      await db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('submissions')
          .doc(docId)
          .set({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'nis': widget.nis,
        'className': widget.className,
        'angkatan': widget.angkatan,
        'subjectId': widget.subjectId,
        'subjectName': widget.subjectName,
        'answers': answersForStorage,
        'essayAnswers': essayAnswersForStorage,
        'doubts': Map<String, dynamic>.from(_doubts),
        'submittedAt': FieldValue.serverTimestamp(),
        'isCompleted': true,
        'autoSubmitted': autoSubmitted,
      }, SetOptions(merge: true));

      debugPrint('✅ Final submission saved to Firestore!');
    } catch (e) {
      debugPrint('❌ Error saving final submission: $e');
    }
  }

  Future<void> _showSubmitConfirmationDialog() async {
    final unansweredCount = _questions.length - _answeredCount;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF059669), size: 24),
            ),
            const SizedBox(width: 12),
            Text('Kumpulkan Ujian?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apakah Anda yakin ingin mengakhiri dan mengumpulkan jawaban mata pelajaran ${widget.subjectName}?',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF334155), height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Soal:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                      Text('${_questions.length} Soal', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Telah Dijawab:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                      Text('$_answeredCount Soal', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF059669))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Belum Dijawab:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                      Text('$unansweredCount Soal', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: unansweredCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),
            if (unansweredCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Masih ada $unansweredCount soal yang belum Anda jawab!',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Periksa Kembali', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Ya, Kumpulkan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSubmitting = true);
      await _saveAnswersToFirestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ujian berhasil dikumpulkan! Terima kasih.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _showBackNavigationWarningDialog() async {
    if (_isSubmitting) return;

    final unansweredCount = _questions.length - _answeredCount;
    final timeFormatted = _formatRemainingTime(_remainingSecondsNotifier.value);

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Peringatan Keluar Ujian',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subjectName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFFFCA5A5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apakah Anda yakin ingin keluar?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Jika Anda keluar dari halaman ini sekarang, sistem akan otomatis mengumpulkan jawaban Anda dan mengunci mata pelajaran ini.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text('Sisa Waktu:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                                ],
                              ),
                              Text(timeFormatted, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                            ],
                          ),
                          const Divider(height: 20, color: Color(0xFFE2E8F0)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.help_outline_rounded, size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text('Belum Dijawab:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: unansweredCount > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$unansweredCount dari ${_questions.length}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: unansweredCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              'Lanjutkan Ujian',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              'Keluar & Kumpulkan',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      await _saveAnswersToFirestore(autoSubmitted: true);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showQuestionGridBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Navigasi Nomor Soal',
                      style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_answeredCount / ${_questions.length} Terisi',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF047857)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Legend
                Row(
                  children: [
                    _buildLegendItem('Sudah Diisi', const Color(0xFFD1FAE5), const Color(0xFF34D399), const Color(0xFF047857)),
                    const SizedBox(width: 12),
                    _buildLegendItem('Ragu-ragu', const Color(0xFFFEF3C7), const Color(0xFFFBBF24), const Color(0xFFD97706)),
                    const SizedBox(width: 12),
                    _buildLegendItem('Belum Diisi', const Color(0xFFF1F5F9), const Color(0xFFCBD5E1), const Color(0xFF64748B)),
                  ],
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    itemCount: _questions.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.0,
                    ),
                    itemBuilder: (context, idx) {
                      final itemQ = _questions[idx];
                      final itemQId = itemQ['id'].toString();
                      final itemIsEssay = _isEssayQuestion(itemQ);

                      final isAnswered = itemIsEssay
                          ? (_essayAnswers[itemQId] ?? '').trim().isNotEmpty
                          : _answers.containsKey(itemQId);

                      final isDoubt = _doubts[itemQId] == true;
                      final isCurrent = idx == _currentIndex;

                      Color boxColor = const Color(0xFFF1F5F9);
                      Color textColor = const Color(0xFF475569);
                      Border border = Border.all(color: const Color(0xFFCBD5E1));

                      if (isDoubt) {
                        boxColor = const Color(0xFFFEF3C7);
                        textColor = const Color(0xFFD97706);
                        border = Border.all(color: const Color(0xFFFBBF24), width: 1.5);
                      } else if (isAnswered) {
                        boxColor = const Color(0xFFD1FAE5);
                        textColor = const Color(0xFF047857);
                        border = Border.all(color: const Color(0xFF34D399), width: 1.5);
                      }

                      if (isCurrent) {
                        boxColor = const Color(0xFF0F172A);
                        textColor = Colors.white;
                        border = Border.all(color: const Color(0xFF0F172A), width: 2);
                      }

                      return InkWell(
                        onTap: () {
                          setState(() => _currentIndex = idx);
                          Navigator.of(context).pop();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: boxColor,
                            borderRadius: BorderRadius.circular(12),
                            border: border,
                          ),
                          child: Center(
                            child: Text(
                              '${idx + 1}',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                            ),
                          ),
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

  Widget _buildLegendItem(String label, Color bg, Color borderColor, Color textColor) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, color: textColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  List<String> _parseOptions(dynamic rawOptions) {
    final List<String> list = [];
    if (rawOptions is List) {
      for (var item in rawOptions) {
        list.add(item.toString());
      }
    } else if (rawOptions is Map) {
      final sortedKeys = rawOptions.keys.map((k) => k.toString()).toList()..sort();
      for (var k in sortedKeys) {
        list.add(rawOptions[k].toString());
      }
    }
    return list;
  }

  Widget _buildImageWidget(String urlStr, {double? height, BoxFit fit = BoxFit.contain}) {
    final clean = urlStr.trim();
    if (clean.isEmpty) return const SizedBox();

    if (clean.startsWith('data:image')) {
      try {
        final commaIdx = clean.indexOf(',');
        if (commaIdx != -1) {
          final base64Str = clean.substring(commaIdx + 1);
          final bytes = base64Decode(base64Str);
          return Image.memory(bytes, height: height, fit: fit);
        }
      } catch (e) {
        debugPrint("Error decoding base64 image: $e");
      }
    }

    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return Image.network(
        clean,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey),
      );
    }

    return const SizedBox();
  }

  String _formatRemainingTime(int seconds) {
    if (seconds <= 0) return '00:00:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;

    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');

    if (h > 0) {
      return '$hh:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text('Memuat Soal Ujian...', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 3.5),
                ),
                const SizedBox(height: 20),
                Text('Menyiapkan Butir Soal', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF0F172A))),
                const SizedBox(height: 6),
                Text('Mohon tunggu sebentar...', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
              ],
            ),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(widget.subjectName, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_late_rounded, size: 56, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),
                Text('Belum Ada Soal', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Text(
                  'Guru pengampu belum mengunggah butir soal yang sesuai untuk mata pelajaran ini.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Kembali'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentQuestion = _questions[_currentIndex];
    final qId = currentQuestion['id'].toString();
    final isEssay = _isEssayQuestion(currentQuestion);
    final options = _parseOptions(currentQuestion['options']);
    final progressPercent = _questions.isNotEmpty ? (_answeredCount / _questions.length) : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _showBackNavigationWarningDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          toolbarHeight: 64,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_rounded, size: 20, color: Color(0xFF34D399)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.subjectName,
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${widget.studentName} (${widget.className})',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            // Live Timer Badge (Wrapped in ValueListenableBuilder so only THIS widget rebuilds every second!)
            ValueListenableBuilder<int>(
              valueListenable: _remainingSecondsNotifier,
              builder: (context, remainingSecs, child) {
                final isUrgent = remainingSecs < 300; // Less than 5 mins
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF064E3B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isUrgent ? Colors.redAccent : const Color(0xFF34D399), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: (isUrgent ? Colors.red : const Color(0xFF10B981)).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUrgent ? Icons.timer_outlined : Icons.timer_rounded,
                        size: 16,
                        color: isUrgent ? Colors.white : const Color(0xFFA7F3D0),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatRemainingTime(remainingSecs),
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Column(
          children: [
            // Thin Linear Progress Indicator Bar
            LinearProgressIndicator(
              value: progressPercent,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              minHeight: 3.5,
            ),

            // Question Navigation Bar (Scrollable Number Bar)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_questions.length, (idx) {
                          final itemQ = _questions[idx];
                          final itemQId = itemQ['id'].toString();
                          final itemIsEssay = _isEssayQuestion(itemQ);

                          final isAnswered = itemIsEssay
                              ? (_essayAnswers[itemQId] ?? '').trim().isNotEmpty
                              : _answers.containsKey(itemQId);

                          final isDoubt = _doubts[itemQId] == true;
                          final isCurrent = idx == _currentIndex;

                          Color boxColor = const Color(0xFFF1F5F9);
                          Color textColor = const Color(0xFF475569);
                          Border border = Border.all(color: const Color(0xFFCBD5E1));

                          if (isDoubt) {
                            boxColor = const Color(0xFFFEF3C7);
                            textColor = const Color(0xFFD97706);
                            border = Border.all(color: const Color(0xFFFBBF24), width: 1.5);
                          } else if (isAnswered) {
                            boxColor = const Color(0xFFD1FAE5);
                            textColor = const Color(0xFF047857);
                            border = Border.all(color: const Color(0xFF34D399), width: 1.5);
                          }

                          if (isCurrent) {
                            boxColor = const Color(0xFF0F172A);
                            textColor = Colors.white;
                            border = Border.all(color: const Color(0xFF0F172A), width: 2);
                          }

                          return InkWell(
                            onTap: () {
                              setState(() => _currentIndex = idx);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 40,
                              height: 40,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: boxColor,
                                borderRadius: BorderRadius.circular(10),
                                border: border,
                              ),
                              child: Center(
                                child: Text(
                                  '${idx + 1}',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  // Quick Grid Button
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _showQuestionGridBottomSheet,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Icon(Icons.grid_view_rounded, size: 18, color: Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
            ),

            // Main Question Content Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question Box Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Chips Row (Soal #N & Badge Type)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF047857), Color(0xFF0F766E)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Soal Nomor ${_currentIndex + 1}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isEssay ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isEssay ? const Color(0xFFC7D2FE) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Text(
                                  isEssay ? 'Esai / Uraian' : 'Pilihan Ganda',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isEssay ? const Color(0xFF4338CA) : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            (currentQuestion['text'] ?? currentQuestion['questionText'] ?? currentQuestion['soal'] ?? '').toString().trim().isEmpty
                                ? 'Soal Ujian'
                                : (currentQuestion['text'] ?? currentQuestion['questionText'] ?? currentQuestion['soal']).toString(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0F172A),
                              height: 1.65,
                            ),
                          ),
                          // Question Image if available
                          if ((currentQuestion['imageUrl'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: _buildImageWidget(
                                  currentQuestion['imageUrl'].toString(),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Dynamic Answer Section (Essay vs Multiple Choice)
                    if (isEssay) ...[
                      // Essay Input Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
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
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.edit_note_rounded, color: Color(0xFF4338CA), size: 20),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Lembar Jawaban Esai',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Tuliskan jawaban Anda secara rinci dan jelas pada kolom di bawah ini:',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _getEssayController(qId),
                              maxLines: 8,
                              minLines: 5,
                              keyboardType: TextInputType.multiline,
                              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A), height: 1.6),
                              decoration: InputDecoration(
                                hintText: 'Ketik jawaban Anda di sini...',
                                hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.all(18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Color(0xFF4338CA), width: 1.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Options Cards (A, B, C, D, E)
                      ...options.asMap().entries.map((optEntry) {
                        final optIdx = optEntry.key;
                        final optText = optEntry.value;
                        final optionLabel = String.fromCharCode(65 + optIdx); // A, B, C, D, E
                        final isSelected = _answers[qId] == optIdx;

                        // Check for option image
                        final optionImages = currentQuestion['optionImages'] as Map?;
                        final optionImgUrl = optionImages?[optionLabel]?.toString();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _answers[qId] = optIdx;
                              });
                              _saveDraftToFirestore();
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFECFDF5) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.015),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                              ),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF10B981) : const Color(0xFFF1F5F9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        optionLabel,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isSelected ? Colors.white : const Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (optText.isNotEmpty)
                                          Text(
                                            optText,
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              color: isSelected ? const Color(0xFF065F46) : const Color(0xFF334155),
                                              height: 1.4,
                                            ),
                                          ),
                                        if (optionImgUrl != null && optionImgUrl.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: _buildImageWidget(
                                              optionImgUrl,
                                              height: 140,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom Bar Navigation Dock (Sebelumnya, Ragu-Ragu, Selanjutnya)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 1. Previous Question Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentIndex > 0
                          ? () {
                              setState(() => _currentIndex--);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Sebelumnya', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Ragu-Ragu Toggle Button
                  Expanded(
                    child: FilterChip(
                      selected: _doubts[qId] == true,
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Ragu-Ragu',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _doubts[qId] == true ? const Color(0xFFD97706) : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      avatar: Icon(
                        _doubts[qId] == true ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        size: 16,
                        color: _doubts[qId] == true ? const Color(0xFFD97706) : const Color(0xFF64748B),
                      ),
                      backgroundColor: const Color(0xFFF1F5F9),
                      selectedColor: const Color(0xFFFEF3C7),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _doubts[qId] == true ? const Color(0xFFFBBF24) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      onSelected: (val) {
                        setState(() {
                          _doubts[qId] = val;
                        });
                        _saveDraftToFirestore();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Next Question Button (or Selesai on last question)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _currentIndex < _questions.length - 1
                          ? () {
                              setState(() => _currentIndex++);
                            }
                          : _showSubmitConfirmationDialog,
                      icon: Icon(
                        _currentIndex < _questions.length - 1 ? Icons.arrow_forward_ios_rounded : Icons.check_circle_outline_rounded,
                        size: 14,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _currentIndex < _questions.length - 1 ? 'Selanjutnya' : 'Selesai',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
