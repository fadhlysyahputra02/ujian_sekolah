import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'student_session_service.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _role;
  String? _schoolId;
  String? _schoolCode;
  bool _isSchoolDisabled = false;
  bool _isStudentInactive = false;
  bool _isLoading = true;
  String? _sessionTerminatedReason;
  String? _establishedSessionId;

  User? get user => _user;
  String? get role => _role;
  String? get schoolId => _schoolId;
  String? get schoolCode => _schoolCode;
  bool get isSchoolDisabled => _isSchoolDisabled;
  bool get isStudentInactive => _isStudentInactive;
  bool get isLoading => _isLoading;
  String? get sessionTerminatedReason => _sessionTerminatedReason;

  void clearSessionTerminatedReason() {
    _sessionTerminatedReason = null;
  }

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
      _schoolCode = null;
      _isSchoolDisabled = false;
      _isLoading = false;
      _establishedSessionId = null;
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
          Map<String, dynamic>? studentData;
          if (snapshot.docs.isNotEmpty) {
            studentData = snapshot.docs.first.data() as Map<String, dynamic>?;
            newInactive = studentData?['status'] == 'inactive' || studentData?['disabled'] == true;
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
                studentData = emailSnap.docs.first.data();
                newInactive = studentData['status'] == 'inactive' || studentData['disabled'] == true;
              }
            } catch (_) {}
          }

          // Single device session enforcement for student
          if (studentData != null) {
            final activeSession = studentData['activeSession'] as Map<String, dynamic>?;
            final remoteSessionId = activeSession?['sessionId']?.toString();
            final localSessionId = await StudentSessionService.getCurrentSessionId();

            // Konfirmasi sesi aktif di perangkat ini jika remote session cocok dengan local session
            if (remoteSessionId != null && localSessionId != null && remoteSessionId == localSessionId) {
              _establishedSessionId = localSessionId;
            }

            // HANYA putuskan sesi jika perangkat ini sebelumnya sudah pernah berhasil membentuk sesi aktif (_establishedSessionId != null)
            // Ini mencegah pemutusan palsu saat murid baru pertama kali login atau saat activeSession masih kosong di database.
            if (_establishedSessionId != null) {
              if (activeSession == null || remoteSessionId == null) {
                // Sesi di-reset oleh pengawas atau admin sekolah di tengah aktivitas ujian/belajar
                debugPrint('[SESSION] Student activeSession was reset by admin/proctor.');
                _establishedSessionId = null;
                _sessionTerminatedReason = 'Sesi login Anda telah direset oleh Pengawas Ujian atau Admin Sekolah.';
                await signOut();
                return;
              } else if (remoteSessionId != _establishedSessionId) {
                // Sesi terdeteksi telah aktif di perangkat/browser lain
                final otherDevice = activeSession['deviceInfo']?.toString() ?? 'Perangkat Lain';
                debugPrint('[SESSION] Student active session mismatch ($otherDevice, remote=$remoteSessionId vs established=$_establishedSessionId).');
                _establishedSessionId = null;
                _sessionTerminatedReason = 'Sesi Anda telah berakhir karena akun ini telah login di perangkat lain ($otherDevice).';
                await signOut();
                return;
              }
            }
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
            final sc = (data?['code'] ?? '').toString().trim();
            if (sc.isNotEmpty) {
              _schoolCode = sc;
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString('last_school_code', sc);
              }).catchError((_) {});
            }
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
    _sessionTerminatedReason = null;
    _establishedSessionId = null;
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
    try {
      if (_role == 'student' && _schoolId != null) {
        await StudentSessionService.clearSession(
          schoolId: _schoolId!,
          uid: _user?.uid,
        );
      }
    } catch (e) {
      debugPrint("Error clearing student session on sign out: $e");
    }

    try {
      if (_schoolCode != null && _schoolCode!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_school_code', _schoolCode!);
      } else if (_schoolId != null && _schoolId!.isNotEmpty) {
        final snap = await _firestore.collection('schools').doc(_schoolId).get();
        final sc = (snap.data()?['code'] ?? '').toString().trim();
        if (sc.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_school_code', sc);
        }
      }
    } catch (e) {
      debugPrint("Error saving last school code on sign out: $e");
    }
    await _auth.signOut();
  }

  /// Menampilkan modal konfirmasi sebelum keluar (sign out)
  Future<bool> confirmAndSignOut(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 12,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon Header with glowing badge
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFEE2E2),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFEF4444),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    'Keluar dari Akun?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Description
                  Text(
                    'Sesi Anda akan diakhiri. Pastikan semua aktivitas ujian dan pekerjaan Anda telah tersimpan sebelum keluar.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF64748B),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color(0xFFF8FAFC),
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Batal',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          icon: const Icon(Icons.logout_rounded, size: 17),
                          label: Text(
                            'Ya, Keluar',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor: const Color(0xFFEF4444).withValues(alpha: 0.35),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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

