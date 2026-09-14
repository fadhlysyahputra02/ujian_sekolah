import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _role;
  String? _schoolId;
  bool _isSchoolDisabled = false;
  bool _isStudentInactive = false;
  bool _isLoading = true;

  User? get user => _user;
  String? get role => _role;
  String? get schoolId => _schoolId;
  bool get isSchoolDisabled => _isSchoolDisabled;
  bool get isStudentInactive => _isStudentInactive;
  bool get isLoading => _isLoading;

  bool get isBlocked => _user != null && _role != 'super_admin' && (_isSchoolDisabled || _isStudentInactive);

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _schoolSubscription;
  StreamSubscription<QuerySnapshot>? _studentSubscription;

  AuthService() {
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _schoolSubscription?.cancel();
    _studentSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _isLoading = true;
    _user = user;
    _isStudentInactive = false;
    _schoolSubscription?.cancel();
    _studentSubscription?.cancel();

    if (user == null) {
      _role = null;
      _schoolId = null;
      _isSchoolDisabled = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      // 1. Force refresh token and check Custom Claims
      final tokenResult = await user.getIdTokenResult(true);
      _role = tokenResult.claims?['role'] as String?;
      _schoolId = tokenResult.claims?['schoolId'] as String?;

      // Fallback manual testing untuk mempermudah pembuatan akun manual
      if (user.email == 'sadmin@sesicermat.com') {
        _role = 'super_admin';
      }

      if (_role == 'super_admin') {
        _isSchoolDisabled = false;
        _isStudentInactive = false;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Fallback: Jika custom claim role atau schoolId belum terkonfigurasi di token
      if ((_role == null || _schoolId == null) && user.uid.isNotEmpty) {
        try {
          final userDoc = await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists) {
            final uData = userDoc.data();
            _role ??= uData?['role'] as String?;
            _schoolId ??= uData?['schoolId'] as String?;
          }
        } catch (e) {
          debugPrint("Error reading users/{uid}: $e");
        }
      }

      if (_role == null && user.email != null) {
        try {
          final studentQuery = await _firestore
              .collectionGroup('students')
              .where('email', isEqualTo: user.email)
              .limit(1)
              .get();
          if (studentQuery.docs.isNotEmpty) {
            _role = 'student';
            final pathSegments = studentQuery.docs.first.reference.path.split('/');
            if (pathSegments.length >= 2 && pathSegments[0] == 'schools') {
              _schoolId ??= pathSegments[1];
            }
          } else {
            final teacherQuery = await _firestore
                .collectionGroup('teachers')
                .where('email', isEqualTo: user.email)
                .limit(1)
                .get();
            if (teacherQuery.docs.isNotEmpty) {
              _role = 'teacher';
              final pathSegments = teacherQuery.docs.first.reference.path.split('/');
              if (pathSegments.length >= 2 && pathSegments[0] == 'schools') {
                _schoolId ??= pathSegments[1];
              }
            }
          }
        } catch (e) {
          debugPrint("Error resolving fallback role: $e");
        }
      }

      // 2. Listen to student status in real-time if role is student
      if (_role == 'student') {
        final Stream<QuerySnapshot> studentStream;
        if (_schoolId != null && _schoolId!.isNotEmpty) {
          studentStream = _firestore
              .collection('schools')
              .doc(_schoolId)
              .collection('students')
              .where('uid', isEqualTo: user.uid)
              .snapshots();
        } else {
          studentStream = _firestore
              .collectionGroup('students')
              .where('email', isEqualTo: user.email)
              .limit(1)
              .snapshots();
        }

        _studentSubscription = studentStream.listen((snapshot) async {
          bool newInactive = false;
          if (snapshot.docs.isNotEmpty) {
            final data = snapshot.docs.first.data() as Map<String, dynamic>?;
            newInactive = data?['status'] == 'inactive' || data?['disabled'] == true;
          } else if (_schoolId != null && user.email != null) {
            // Fallback check by email if uid query returned empty
            try {
              final emailSnap = await _firestore
                  .collection('schools')
                  .doc(_schoolId)
                  .collection('students')
                  .where('email', isEqualTo: user.email)
                  .limit(1)
                  .get();
              if (emailSnap.docs.isNotEmpty) {
                final data = emailSnap.docs.first.data();
                newInactive = data['status'] == 'inactive' || data['disabled'] == true;
              }
            } catch (_) {}
          }

          final bool wasLoading = _isLoading;
          if (wasLoading || newInactive != _isStudentInactive) {
            _isStudentInactive = newInactive;
            _isLoading = false;
            notifyListeners();
          }
        }, onError: (e) {
          debugPrint("Error in student status subscription: $e");
          _isLoading = false;
          notifyListeners();
        });
      }

      // 3. If it's a school-related user, check and listen to school status in real-time
      if (_schoolId != null) {
        _schoolSubscription = _firestore
            .collection('schools')
            .doc(_schoolId)
            .snapshots()
            .listen((snapshot) {
          bool newDisabled;
          if (snapshot.exists) {
            final data = snapshot.data();
            newDisabled = data?['disabled'] == true;
          } else {
            newDisabled = true; // school doesn't exist anymore, treat as blocked
          }
          final bool wasLoading = _isLoading;
          if (wasLoading || newDisabled != _isSchoolDisabled) {
            _isSchoolDisabled = newDisabled;
            _isLoading = false;
            notifyListeners();
          }
        }, onError: (e) {
          // If security rules block read, we treat as disabled/blocked
          _isSchoolDisabled = true;
          _isLoading = false;
          notifyListeners();
        });
      }

      // If no subscription was registered, complete loading state
      if (_studentSubscription == null && _schoolSubscription == null) {
        _isSchoolDisabled = false;
        _isStudentInactive = false;
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading auth details: $e");
      _role = null;
      _schoolId = null;
      _isSchoolDisabled = false;
      _isStudentInactive = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in helper that maps "sadmin" to "sadmin@sesicermat.com"
  Future<UserCredential> signIn(String usernameOrEmail, String password) async {
    String email = usernameOrEmail.trim();
    if (email.toLowerCase() == 'sadmin') {
      email = 'sadmin@sesicermat.com';
    }
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Sign out helper
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Menampilkan modal konfirmasi sebelum keluar (sign out)
  Future<bool> confirmAndSignOut(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFEF4444),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Konfirmasi Keluar',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Apakah Anda yakin ingin keluar dari akun Anda?',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF475569),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Text(
                'Batal',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Ya, Keluar',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await signOut();
      return true;
    }
    return false;
  }

  /// Mengubah password pengguna saat ini via Cloud Function
  Future<void> changeOwnPassword(String newPassword) async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('changeOwnPassword');
      await callable.call({
        'newPassword': newPassword,
      });
    } catch (e) {
      debugPrint("Error in changeOwnPassword: $e");
      rethrow;
    }
  }
}

