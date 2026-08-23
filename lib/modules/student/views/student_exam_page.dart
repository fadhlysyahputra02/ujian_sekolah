import 'dart:async';
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

  // Countdown Timer
  Timer? _timer;
  int _remainingSeconds = 3600; // Default 60 minutes
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
    for (var controller in _essayControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _triggerDraftAutoSave() {
    _draftDebounceTimer?.cancel();
    _draftDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      _saveDraftToFirestore();
    });
  }

  /// Saves current draft state to Firestore with isCompleted = false
  Future<void> _saveDraftToFirestore() async {
    if (widget.studentId.isEmpty || widget.schoolId.isEmpty || widget.eventId.isEmpty) {
      debugPrint('⚠️ Draft save skipped: studentId/schoolId/eventId is empty');
      return;
    }
    if (_questions.isEmpty) {
      debugPrint('⚠️ Draft save skipped: questions not loaded yet');
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
            final label = String.fromCharCode(65 + selectedIdx); // 0->A, 1->B
            answersForStorage[qId] = label;
          }
        }
      }

      debugPrint('💾 Saving draft to submissions/$docId  MC:${answersForStorage.length}  Essay:${essayAnswersForStorage.length}');

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

    _remainingSeconds = totalSecs;

    if (_remainingSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleTimeExpired();
      });
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _handleTimeExpired();
      }
    });
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final db = FirebaseFirestore.instance;

      debugPrint('📚 Loading questions...');
      debugPrint('   schoolId  : ${widget.schoolId}');
      debugPrint('   eventId   : ${widget.eventId}');
      debugPrint('   subjectId : ${widget.subjectId}');
      debugPrint('   angkatan  : "${widget.angkatan}"');

      final qSnap = await db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('subjects')
          .doc(widget.subjectId)
          .collection('questions')
          .get();

      debugPrint('   total docs in Firestore: ${qSnap.docs.length}');

      if (qSnap.docs.isNotEmpty) {
        final allDocs = qSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();

        // Filter by angkatan: include soal with no angkatan field OR matching student's angkatan
        final filtered = widget.angkatan.isEmpty
            ? allDocs
            : allDocs.where((q) {
                final qAng = (q['angkatan'] ?? '').toString().trim();
                final match = qAng.isEmpty || qAng == widget.angkatan.trim();
                return match;
              }).toList();

        // Sort by urutan or index
        filtered.sort((a, b) {
          final aIdx = (a['urutan'] ?? a['index'] ?? 9999) as num;
          final bIdx = (b['urutan'] ?? b['index'] ?? 9999) as num;
          return aIdx.compareTo(bIdx);
        });

        _questions = filtered;

        // --- Restore saved draft answers from Firestore ---
        await _restoreDraftFromFirestore(db);

      } else {
        debugPrint('   ⚠️ No questions found at this path!');
      }
    } catch (e) {
      debugPrint('❌ Error loading questions: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);

        // SnackBar must run after the new exam Scaffold has been built
        // (cannot call ScaffoldMessenger on the loading Scaffold's context)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final restoredCount = _answeredCount;
          if (restoredCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text('Draf dipulihkan: $restoredCount soal terjawab'),
                  ],
                ),
                backgroundColor: const Color(0xFF059669),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        });
      }
    }
  }

  /// Fetches and restores draft data from Firestore submissions collection.
  Future<void> _restoreDraftFromFirestore(FirebaseFirestore db) async {
    if (widget.studentId.isEmpty || widget.schoolId.isEmpty) {
      debugPrint('⚠️ Draft restore skipped: studentId or schoolId is empty');
      return;
    }

    final docId = '${widget.studentId}_${widget.subjectId}';
    debugPrint('📥 Looking for draft at: schools/${widget.schoolId}/events/${widget.eventId}/submissions/$docId');

    try {
      final subDoc = await db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('submissions')
          .doc(docId)
          .get();

      if (!subDoc.exists) {
        debugPrint('   ℹ️ No draft found – fresh exam');
        return;
      }

      final subData = subDoc.data();
      if (subData == null) {
        debugPrint('   ⚠️ Draft doc exists but data is null');
        return;
      }

      final isCompleted = subData['isCompleted'] == true;
      debugPrint('   📄 Draft found (isCompleted=$isCompleted)');

      // Restore multiple-choice answers (stored as single letter: "A", "B", etc.)
      final rawAnswers = subData['answers'];
      if (rawAnswers is Map) {
        rawAnswers.forEach((k, v) {
          final qIdStr = k.toString();
          if (v is String && v.length == 1) {
            final charCode = v.toUpperCase().codeUnitAt(0);
            if (charCode >= 65 && charCode <= 90) {
              _answers[qIdStr] = charCode - 65; // "A"->0, "B"->1 ...
            }
          } else if (v is num) {
            _answers[qIdStr] = v.toInt();
          }
        });
      }

      // Restore essay answers
      final rawEssay = subData['essayAnswers'];
      if (rawEssay is Map) {
        rawEssay.forEach((k, v) {
          _essayAnswers[k.toString()] = v.toString();
        });
      }

      // Restore doubt flags
      final rawDoubts = subData['doubts'];
      if (rawDoubts is Map) {
        rawDoubts.forEach((k, v) {
          _doubts[k.toString()] = v == true;
        });
      }

      // Sync any already-created essay controllers with restored text
      _essayAnswers.forEach((qId, restoredText) {
        final ctrl = _essayControllers[qId];
        if (ctrl != null && ctrl.text != restoredText) {
          ctrl.text = restoredText;
        }
      });

      debugPrint('✅ Draft restored: ${_answers.length} MC, ${_essayAnswers.length} Essay, ${_doubts.length} Doubts');
    } catch (e) {
      debugPrint('❌ Error restoring draft: $e');
    }
  }


  /// Triggered automatically when countdown timer reaches 00:00
  Future<void> _handleTimeExpired() async {
    if (_isSubmitting) return;
    _isSubmitting = true;

    await _saveAnswersToFirestore();

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.timer_off_rounded, color: Color(0xFFEF4444), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Waktu Ujian Habis!', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A))),
              ),
            ],
          ),
          content: Text(
            'Durasi pengerjaan ujian untuk mata pelajaran ${widget.subjectName} telah selesai. Seluruh jawaban Anda telah tersimpan secara otomatis.',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Kembali ke Dashboard', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  /// Saves student submission to Firestore
  Future<void> _saveAnswersToFirestore() async {
    try {
      final db = FirebaseFirestore.instance;
      final subRef = db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('events')
          .doc(widget.eventId)
          .collection('submissions')
          .doc('${widget.studentId}_${widget.subjectId}');

      int totalPoints = 0;
      int earnedPoints = 0;

      final answersForStorage = <String, dynamic>{};
      final essayAnswersForStorage = <String, String>{};

      for (var q in _questions) {
        final qId = q['id'].toString();
        final points = (q['points'] as num?)?.toInt() ?? 10;
        totalPoints += points;

        final isEssay = _isEssayQuestion(q);
        if (isEssay) {
          final essayText = (_essayAnswers[qId] ?? '').trim();
          if (essayText.isNotEmpty) {
            answersForStorage[qId] = essayText;
            essayAnswersForStorage[qId] = essayText;
          }
        } else {
          final correctOptionLabel = (q['correctOption'] ?? '').toString().trim().toUpperCase();
          final selectedOptionIdx = _answers[qId];

          if (selectedOptionIdx != null) {
            final label = String.fromCharCode(65 + selectedOptionIdx); // 0->A, 1->B
            answersForStorage[qId] = label;

            if (correctOptionLabel.isNotEmpty) {
              final opts = _parseOptions(q['options']);
              final correctIdx = correctOptionLabel.codeUnitAt(0) - 'A'.codeUnitAt(0);
              if (correctIdx >= 0 && correctIdx < opts.length && selectedOptionIdx == correctIdx) {
                earnedPoints += points;
              }
            }
          }
        }
      }

      final scorePercent = totalPoints > 0 ? ((earnedPoints / totalPoints) * 100).round() : 0;

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
        'doubts': _doubts.map((k, v) => MapEntry(k, v)),
        'earnedPoints': earnedPoints,
        'totalPoints': totalPoints,
        'score': scorePercent,
        'submittedAt': FieldValue.serverTimestamp(),
        'isCompleted': true,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving answers: $e");
    }
  }

  /// Manual Submit Dialog
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
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.task_alt_rounded, color: Color(0xFF10B981), size: 26),
            ),
            const SizedBox(width: 12),
            Text('Kumpulkan Ujian?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apakah Anda yakin ingin mengumpulkan lembar jawaban ujian ${widget.subjectName}?',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.5),
            ),
            const SizedBox(height: 14),
            if (unansweredCount > 0)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Masih ada $unansweredCount soal yang belum dijawab!',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF6EE7B7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Semua ${_questions.length} soal telah dijawab dengan lengkap.',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF065F46)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
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

  /// Opens bottom sheet with grid view of all questions
  void _showQuestionGridBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daftar Lembar Soal',
                        style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Progres: $_answeredCount dari ${_questions.length} Soal Terjawab',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            // Legend Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFF8FAFC),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildLegendItem(const Color(0xFFD1FAE5), const Color(0xFF34D399), 'Terjawab'),
                  _buildLegendItem(const Color(0xFFFEF3C7), const Color(0xFFFBBF24), 'Ragu-Ragu'),
                  _buildLegendItem(const Color(0xFFF1F5F9), const Color(0xFFCBD5E1), 'Belum Diisi'),
                  _buildLegendItem(const Color(0xFF0F172A), const Color(0xFF0F172A), 'Sedang Dibuka'),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            // Grid View
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: _questions.length,
                itemBuilder: (context, idx) {
                  final itemQ = _questions[idx];
                  final itemQId = itemQ['id'].toString();
                  final isEssay = _isEssayQuestion(itemQ);

                  final isAnswered = isEssay
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
                      Navigator.pop(ctx);
                      setState(() => _currentIndex = idx);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: boxColor,
                        borderRadius: BorderRadius.circular(14),
                        border: border,
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${idx + 1}',
                                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                              ),
                              if (isEssay)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isCurrent ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'ESAI',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 8,
                                      color: isCurrent ? Colors.white : const Color(0xFF4338CA),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (isDoubt)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(Icons.bookmark_rounded, size: 14, color: isCurrent ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
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
    );
  }

  Widget _buildLegendItem(Color bg, Color border, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
      ],
    );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  List<String> _parseOptions(dynamic raw) {
    if (raw == null) return ['Pilihan A', 'Pilihan B', 'Pilihan C', 'Pilihan D'];

    if (raw is List) {
      return raw.map((o) => o.toString()).toList();
    }

    if (raw is Map) {
      final sortedEntries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return sortedEntries.map((e) => e.value.toString()).toList();
    }

    return ['Pilihan A', 'Pilihan B', 'Pilihan C', 'Pilihan D'];
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
    final isUrgent = _remainingSeconds < 300; // Less than 5 mins
    final progressPercent = _questions.isNotEmpty ? (_answeredCount / _questions.length) : 0.0;

    return Scaffold(
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
              child: Text(
                widget.subjectName,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Live Timer Badge
          AnimatedContainer(
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
              children: [
                Icon(Icons.timer_outlined, size: 16, color: isUrgent ? Colors.white : const Color(0xFFA7F3D0)),
                const SizedBox(width: 6),
                Text(
                  _formatTime(_remainingSeconds),
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white, letterSpacing: 0.5),
                ),
              ],
            ),
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
            minHeight: 3,
          ),

          // Question Navigation Grid Bar
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
                            _saveDraftToFirestore();
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
                        Text(
                          (currentQuestion['text'] ?? currentQuestion['questionText'] ?? currentQuestion['soal'] ?? '').toString().trim().isEmpty
                              ? 'Soal Ujian'
                              : (currentQuestion['text'] ?? currentQuestion['questionText'] ?? currentQuestion['soal']).toString(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
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
                              child: Image.network(
                                currentQuestion['imageUrl'].toString(),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox(),
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
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    (_essayAnswers[qId] ?? '').trim().isNotEmpty ? Icons.cloud_done_rounded : Icons.edit_off_rounded,
                                    size: 15,
                                    color: (_essayAnswers[qId] ?? '').trim().isNotEmpty ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    (_essayAnswers[qId] ?? '').trim().isNotEmpty ? 'Tersimpan otomatis' : 'Belum diisi',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: (_essayAnswers[qId] ?? '').trim().isNotEmpty ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${(_essayAnswers[qId] ?? '').length} Karakter',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                ),
                              ),
                            ],
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
                                          child: Image.network(
                                            optionImgUrl,
                                            height: 110,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => const SizedBox(),
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
                            _saveDraftToFirestore();
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
                            _saveDraftToFirestore();
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
    );
  }
}
