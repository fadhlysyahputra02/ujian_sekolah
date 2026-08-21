import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _role;
  String? _schoolId;
  bool _isSchoolDisabled = false;
  bool _isLoading = true;

  User? get user => _user;
  String? get role => _role;
  String? get schoolId => _schoolId;
  bool get isSchoolDisabled => _isSchoolDisabled;
  bool get isLoading => _isLoading;

  bool get isBlocked => _user != null && _role != 'super_admin' && _isSchoolDisabled;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _schoolSubscription;

  AuthService() {
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _schoolSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _isLoading = true;
    notifyListeners();

    _user = user;
    _schoolSubscription?.cancel();
    _schoolSubscription = null;

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
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Fallback: Jika custom claim role tidak ada, cek dokumen koleksi teachers dan students di Firestore
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

      // 2. If it's a school-related user, check and listen to school status in real-time
      if (_schoolId != null) {
        _schoolSubscription = _firestore
            .collection('schools')
            .doc(_schoolId)
            .snapshots()
            .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data();
            _isSchoolDisabled = data?['disabled'] == true;
          } else {
            _isSchoolDisabled = true; // school doesn't exist anymore, treat as blocked
          }
          _isLoading = false;
          notifyListeners();
        }, onError: (e) {
          // If security rules block read, we treat as disabled/blocked
          _isSchoolDisabled = true;
          _isLoading = false;
          notifyListeners();
        });
      } else {
        // Logged in user with no school ID
        _isSchoolDisabled = false;
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading auth details: $e");
      _role = null;
      _schoolId = null;
      _isSchoolDisabled = false;
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
