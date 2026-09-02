import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentExamCacheService {
  static String _draftKey(String studentId, String subjectId) =>
      'exam_draft_${studentId}_$subjectId';
  static String _syncKey(String studentId, String subjectId) =>
      'exam_draft_synced_${studentId}_$subjectId';
  static String _questionsKey(String studentId, String subjectId) =>
      'exam_questions_${studentId}_$subjectId';
  static String _finalCompletedKey(String studentId, String subjectId) =>
      'exam_final_completed_${studentId}_$subjectId';

  /// Save questions list locally so exam can be reloaded even if internet dies
  static Future<void> saveQuestionsLocally({
    required String studentId,
    required String subjectId,
    required List<Map<String, dynamic>> questions,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(questions);
      await prefs.setString(_questionsKey(studentId, subjectId), jsonStr);
      debugPrint('💾 LocalCache: Saved ${questions.length} questions to offline storage.');
    } catch (e) {
      debugPrint('❌ LocalCache: Error saving questions locally: $e');
    }
  }

  /// Load cached questions if Firestore fails or network is offline
  static Future<List<Map<String, dynamic>>> loadQuestionsLocally({
    required String studentId,
    required String subjectId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_questionsKey(studentId, subjectId));
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List dynamicList = jsonDecode(jsonStr);
        final list = dynamicList.map((e) => Map<String, dynamic>.from(e)).toList();
        debugPrint('📦 LocalCache: Loaded ${list.length} questions from offline cache.');
        return list;
      }
    } catch (e) {
      debugPrint('❌ LocalCache: Error loading cached questions: $e');
    }
    return [];
  }

  /// Save draft state instantly to local device storage (SharedPreferences)
  static Future<void> saveDraftLocally({
    required String studentId,
    required String subjectId,
    required Map<String, int> answers,
    required Map<String, String> essayAnswers,
    required Map<String, bool> doubts,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final data = {
        'answers': answers.map((k, v) => MapEntry(k, v)),
        'essayAnswers': essayAnswers,
        'doubts': doubts,
        'lastSavedAt': DateTime.now().toIso8601String(),
      };

      await prefs.setString(_draftKey(studentId, subjectId), jsonEncode(data));
      // Mark local draft as not synced yet to Firestore
      await prefs.setBool(_syncKey(studentId, subjectId), false);

      debugPrint('⚡ LocalCache: Instantly saved draft locally (MC:${answers.length}, Essay:${essayAnswers.length}). Marked for sync.');
    } catch (e) {
      debugPrint('❌ LocalCache: Error saving draft locally: $e');
    }
  }

  /// Load draft state from local storage
  static Future<Map<String, dynamic>?> loadDraftLocally({
    required String studentId,
    required String subjectId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_draftKey(studentId, subjectId));
      if (jsonStr == null || jsonStr.isEmpty) return null;

      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      final isSynced = prefs.getBool(_syncKey(studentId, subjectId)) ?? false;
      final isFinalCompleted = prefs.getBool(_finalCompletedKey(studentId, subjectId)) ?? false;

      final rawAnswers = decoded['answers'] as Map<String, dynamic>? ?? {};
      final answers = <String, int>{};
      for (var entry in rawAnswers.entries) {
        if (entry.value is num) {
          answers[entry.key] = (entry.value as num).toInt();
        }
      }

      final rawEssayAnswers = decoded['essayAnswers'] as Map<String, dynamic>? ?? {};
      final essayAnswers = <String, String>{};
      for (var entry in rawEssayAnswers.entries) {
        essayAnswers[entry.key] = entry.value.toString();
      }

      final rawDoubts = decoded['doubts'] as Map<String, dynamic>? ?? {};
      final doubts = <String, bool>{};
      for (var entry in rawDoubts.entries) {
        doubts[entry.key] = entry.value == true;
      }

      debugPrint('📂 LocalCache: Loaded draft from local storage (isSynced: $isSynced, isFinalCompleted: $isFinalCompleted).');

      return {
        'answers': answers,
        'essayAnswers': essayAnswers,
        'doubts': doubts,
        'isSynced': isSynced,
        'isFinalCompleted': isFinalCompleted,
        'lastSavedAt': decoded['lastSavedAt'],
      };
    } catch (e) {
      debugPrint('❌ LocalCache: Error loading local draft: $e');
      return null;
    }
  }

  /// Periodic background sync: Syncs unsynced local draft to Firestore batch
  static Future<bool> syncDraftToServer({
    required String schoolId,
    required String eventId,
    required String subjectId,
    required String subjectName,
    required String studentId,
    required String studentName,
    required String nis,
    required String className,
    required String angkatan,
    required List<Map<String, dynamic>> questions,
  }) async {
    if (studentId.isEmpty || schoolId.isEmpty || eventId.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final isSynced = prefs.getBool(_syncKey(studentId, subjectId)) ?? true;

      // If already synced, no need to touch Firestore
      if (isSynced) {
        debugPrint('ℹ️ SyncServer: Local draft already synced. Skipping Firestore write.');
        return true;
      }

      final localDraft = await loadDraftLocally(studentId: studentId, subjectId: subjectId);
      if (localDraft == null) return false;

      final answersMap = localDraft['answers'] as Map<String, int>? ?? {};
      final essayAnswersMap = localDraft['essayAnswers'] as Map<String, String>? ?? {};
      final doubtsMap = localDraft['doubts'] as Map<String, bool>? ?? {};

      final answersForStorage = <String, dynamic>{};
      final essayAnswersForStorage = <String, String>{};

      for (var q in questions) {
        final qId = q['id'].toString();
        final qType = (q['type'] ?? '').toString().toLowerCase().trim();
        final isEssay = qType == 'esai' || qType == 'essay' || qType == 'tertulis' || qType == 'uraian';

        if (isEssay) {
          final essayText = (essayAnswersMap[qId] ?? '').trim();
          if (essayText.isNotEmpty) {
            answersForStorage[qId] = essayText;
            essayAnswersForStorage[qId] = essayText;
          }
        } else {
          final selectedIdx = answersMap[qId];
          if (selectedIdx != null) {
            final label = String.fromCharCode(65 + selectedIdx);
            answersForStorage[qId] = label;
          }
        }
      }

      final db = FirebaseFirestore.instance;
      final docId = '${studentId}_$subjectId';
      final subRef = db
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId)
          .collection('submissions')
          .doc(docId);

      debugPrint('🌐 SyncServer: Batch syncing draft to Firestore (MC:${answersForStorage.length}, Essay:${essayAnswersForStorage.length})...');

      await subRef.set({
        'studentId': studentId,
        'studentName': studentName,
        'nis': nis,
        'className': className,
        'angkatan': angkatan,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'answers': answersForStorage,
        'essayAnswers': essayAnswersForStorage,
        'doubts': Map<String, dynamic>.from(doubtsMap),
        'lastSavedAt': FieldValue.serverTimestamp(),
        'isCompleted': false,
      }, SetOptions(merge: true));

      // Mark as synced locally
      await prefs.setBool(_syncKey(studentId, subjectId), true);
      debugPrint('✅ SyncServer: Draft successfully synced to Firestore!');
      return true;
    } catch (e) {
      debugPrint('⚠️ SyncServer: Failed to sync draft to Firestore (offline or busy): $e');
      return false;
    }
  }

  /// Sync final exam submission (Submit Button / Time Expired)
  static Future<bool> syncFinalSubmissionToServer({
    required String schoolId,
    required String eventId,
    required String subjectId,
    required String subjectName,
    required String studentId,
    required String studentName,
    required String nis,
    required String className,
    required String angkatan,
    required Map<String, int> answers,
    required Map<String, String> essayAnswers,
    required Map<String, bool> doubts,
    required List<Map<String, dynamic>> questions,
    bool autoSubmitted = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Mark final completion locally first!
    await saveDraftLocally(
      studentId: studentId,
      subjectId: subjectId,
      answers: answers,
      essayAnswers: essayAnswers,
      doubts: doubts,
    );
    await prefs.setBool(_finalCompletedKey(studentId, subjectId), true);

    // 2. Try submitting to Firestore
    try {
      final db = FirebaseFirestore.instance;
      final docId = '${studentId}_$subjectId';

      final answersForStorage = <String, dynamic>{};
      final essayAnswersForStorage = <String, String>{};

      for (var q in questions) {
        final qId = q['id'].toString();
        final qType = (q['type'] ?? '').toString().toLowerCase().trim();
        final isEssay = qType == 'esai' || qType == 'essay' || qType == 'tertulis' || qType == 'uraian';

        if (isEssay) {
          final essayText = (essayAnswers[qId] ?? '').trim();
          if (essayText.isNotEmpty) {
            answersForStorage[qId] = essayText;
            essayAnswersForStorage[qId] = essayText;
          }
        } else {
          final selectedIdx = answers[qId];
          if (selectedIdx != null) {
            final label = String.fromCharCode(65 + selectedIdx);
            answersForStorage[qId] = label;
          }
        }
      }

      await db
          .collection('schools')
          .doc(schoolId)
          .collection('events')
          .doc(eventId)
          .collection('submissions')
          .doc(docId)
          .set({
        'studentId': studentId,
        'studentName': studentName,
        'nis': nis,
        'className': className,
        'angkatan': angkatan,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'answers': answersForStorage,
        'essayAnswers': essayAnswersForStorage,
        'doubts': Map<String, dynamic>.from(doubts),
        'submittedAt': FieldValue.serverTimestamp(),
        'isCompleted': true,
        'autoSubmitted': autoSubmitted,
      }, SetOptions(merge: true));

      await prefs.setBool(_syncKey(studentId, subjectId), true);
      debugPrint('🎉 Final submission successfully saved to Firestore!');
      return true;
    } catch (e) {
      debugPrint('❌ Error sending final submission to Firestore (saved locally for retry): $e');
      return false;
    }
  }

  /// Check if local draft is pending sync
  static Future<bool> isSyncPending(String studentId, String subjectId) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_syncKey(studentId, subjectId)) ?? true);
  }

  /// Clear cache after exam is confirmed
  static Future<void> clearExamCache(String studentId, String subjectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey(studentId, subjectId));
      await prefs.remove(_syncKey(studentId, subjectId));
      await prefs.remove(_questionsKey(studentId, subjectId));
      await prefs.remove(_finalCompletedKey(studentId, subjectId));
      debugPrint('🧹 LocalCache: Cleared cache for student $studentId subject $subjectId');
    } catch (e) {
      debugPrint('Error clearing exam cache: $e');
    }
  }
}
