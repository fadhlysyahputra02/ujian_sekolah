import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/student_session_service.dart';
import '../../../core/utils/platform_helper.dart';
import '../../../core/utils/web_reload.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _schoolCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  // School selection states
  List<Map<String, dynamic>> _schools = [];
  Map<String, dynamic>? _selectedSchool;
  bool _isLoggingIn = false;

  // Animation controllers
  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final AnimationController _logoController;
  late final AnimationController _orb1Controller;
  late final AnimationController _orb2Controller;

  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _logoScaleAnim;
  late final Animation<double> _orb1Anim;
  late final Animation<double> _orb2Anim;

  @override
  void initState() {
    super.initState();
    _loadLastSchoolCode();
    _fetchSchools();
    _initAnimations();
    _checkTerminatedSessionNotice();
  }

  void _checkTerminatedSessionNotice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.sessionTerminatedReason != null) {
        final msg = auth.sessionTerminatedReason!;
        auth.clearSessionTerminatedReason();
        _showSessionTerminatedDialog(msg);
      }
    });
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _orb1Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _orb2Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _logoScaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _orb1Anim = Tween<double>(begin: 0.0, end: 1.0).animate(_orb1Controller);
    _orb2Anim = Tween<double>(begin: 0.0, end: 1.0).animate(_orb2Controller);

    // Stagger animations
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _logoController.forward();
        _fadeController.forward();
        _slideController.forward();
      }
    });
  }

  @override
  void dispose() {
    _schoolCodeController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _logoController.dispose();
    _orb1Controller.dispose();
    _orb2Controller.dispose();
    super.dispose();
  }

  Future<void> _fetchSchools() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .get();

      final List<Map<String, dynamic>> loadedSchools = snapshot.docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
        final data = doc.data();

        // Read user count from meta.studentCount + meta.teacherCount (cached fields)
        // Fallback to other possible field names
        int activeUserCount = 0;
        final meta = data['meta'];
        if (meta is Map) {
          final sc = meta['studentCount'];
          final tc = meta['teacherCount'];
          activeUserCount = ((sc is num ? sc.toInt() : 0) + (tc is num ? tc.toInt() : 0));
        }
        // Fallback to top-level cached fields
        if (activeUserCount == 0) {
          for (final key in ['activeUserCount', 'userCount', 'totalUsers', 'activeUsers']) {
            if (data[key] is num) {
              activeUserCount = (data[key] as num).toInt();
              break;
            }
          }
        }

        return {
          'id': doc.id,
          'name': (data['name'] ?? '').toString(),
          'adminEmail': (data['adminEmail'] ?? '').toString(),
          'code': (data['code'] ?? '').toString(),
          'logoUrl': data['logoUrl'] ?? data['logoBase64'] ?? data['logo'],
          'activeUserCount': activeUserCount,
        };
      }).toList();

      // Sort: most active users first, then alphabetical
      loadedSchools.sort((a, b) {
        final int countA = (a['activeUserCount'] as num?)?.toInt() ?? 0;
        final int countB = (b['activeUserCount'] as num?)?.toInt() ?? 0;
        if (countB != countA) return countB.compareTo(countA);
        return (a['name'] ?? '').toString().toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase());
      });

      if (mounted) {
        setState(() {
          _schools = loadedSchools;
        });
        removeSessionItem('fs_reloaded');
        debugPrint('[LOGIN] Loaded ${_schools.length} schools (sorted by activeUserCount)');

        // Auto-match school if code was loaded from last login
        if (_schoolCodeController.text.trim().isNotEmpty && _selectedSchool == null) {
          _matchAndSelectSchool(_schoolCodeController.text.trim());
        }
      }
    } catch (e) {
      debugPrint('[LOGIN] Fetch gagal: $e');
      if (kIsWeb && getSessionItem('fs_reloaded') != 'true') {
        setSessionItem('fs_reloaded', 'true');
        debugPrint('[LOGIN] Auto reloading browser page due to web hot-restart Firestore corruption...');
        reloadPage();
      }
    }
  }

  Future<void> _loadLastSchoolCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCode = prefs.getString('last_school_code');
      if (lastCode != null && lastCode.trim().isNotEmpty && mounted) {
        final codeTrimmed = lastCode.trim();
        if (_schoolCodeController.text.trim().isEmpty) {
          setState(() {
            _schoolCodeController.text = codeTrimmed;
          });
          await _matchAndSelectSchool(codeTrimmed);
        }
      }
    } catch (e) {
      debugPrint('[LOGIN] Error loading last school code: $e');
    }
  }

  Future<void> _matchAndSelectSchool(String text) async {
    final term = text.trim().toLowerCase();
    if (term.isEmpty || term == 'sadmin') return;

    Map<String, dynamic>? found;
    if (_schools.isNotEmpty) {
      found = _schools.cast<Map<String, dynamic>?>().firstWhere(
        (s) =>
            (s?['code'] ?? '').toString().trim().toLowerCase() == term ||
            (s?['id'] ?? '').toString().trim().toLowerCase() == term,
        orElse: () => null,
      );
    }

    if (found == null) {
      try {
        final querySnap = await FirebaseFirestore.instance
            .collection('schools')
            .where('code', isEqualTo: text.trim())
            .limit(1)
            .get();
        if (querySnap.docs.isNotEmpty) {
          final doc = querySnap.docs.first;
          final data = doc.data();
          found = {
            'id': doc.id,
            'name': (data['name'] ?? '').toString(),
            'adminEmail': (data['adminEmail'] ?? '').toString(),
            'code': (data['code'] ?? '').toString(),
            'logoUrl': data['logoUrl'] ?? data['logoBase64'] ?? data['logo'],
          };
        } else {
          final docSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(text.trim())
              .get();
          if (docSnap.exists && docSnap.data()?['deleted'] != true) {
            final data = docSnap.data()!;
            found = {
              'id': docSnap.id,
              'name': (data['name'] ?? '').toString(),
              'adminEmail': (data['adminEmail'] ?? '').toString(),
              'code': (data['code'] ?? '').toString(),
              'logoUrl': data['logoUrl'] ?? data['logoBase64'] ?? data['logo'],
            };
          }
        }
      } catch (e) {
        debugPrint('[LOGIN] Direct school lookup error: $e');
      }
    }

    if (found != null && mounted) {
      setState(() {
        _selectedSchool = found;
      });
      _fetchSchoolLogoDirectly(found['id']);
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoggingIn = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    final typedText = _schoolCodeController.text.trim();
    final password = _passwordController.text;

    String emailOrUsername = '';
    String? resolvedStudentId;
    String? resolvedRole;

    final inputLower = typedText.toLowerCase();
    bool isSuperAdminLogin = inputLower == 'sadmin';
    debugPrint('[LOGIN] typedText="$typedText" initial isSuperAdminLogin=$isSuperAdminLogin');

    if (!isSuperAdminLogin && typedText.isNotEmpty) {
      // 1. Direct Firestore check from system_settings/super_admin (publicly readable)
      try {
        debugPrint('[LOGIN] Step1: Reading system_settings/super_admin...');
        final sysDoc = await FirebaseFirestore.instance
            .collection('system_settings')
            .doc('super_admin')
            .get();
        debugPrint('[LOGIN] Step1: doc.exists=${sysDoc.exists} data=${sysDoc.data()}');
        if (sysDoc.exists) {
          final storedUsername = (sysDoc.data()?['username'] as String?)?.toLowerCase();
          debugPrint('[LOGIN] Step1: storedUsername="$storedUsername" inputLower="$inputLower"');
          if (storedUsername != null && storedUsername == inputLower) {
            isSuperAdminLogin = true;
            debugPrint('[LOGIN] Step1: MATCH → SuperAdmin login confirmed');
          }
        }
      } catch (e) {
        debugPrint('[LOGIN] Step1: ERROR reading system_settings: $e');
      }

      // 2. Fallback: Cloud Function resolution (server-side, reads admin SDK)
      if (!isSuperAdminLogin) {
        try {
          debugPrint('[LOGIN] Step2: Calling resolveSuperAdminUsername Cloud Function...');
          final HttpsCallable sadminCallable = FirebaseFunctions.instance
              .httpsCallable('resolveSuperAdminUsername');
          final sadminRes = await sadminCallable.call({'username': typedText});
          debugPrint('[LOGIN] Step2: CF result=${sadminRes.data}');
          if (sadminRes.data != null && sadminRes.data['isSuperAdmin'] == true) {
            isSuperAdminLogin = true;
            debugPrint('[LOGIN] Step2: MATCH → SuperAdmin login confirmed via CF');
          }
        } catch (e) {
          debugPrint('[LOGIN] Step2: ERROR calling CF: $e');
        }
      }
    }
    debugPrint('[LOGIN] Final isSuperAdminLogin=$isSuperAdminLogin');

    if (isSuperAdminLogin) {
      emailOrUsername = 'sadmin@sesicermat.com';
    } else {
      Map<String, dynamic>? matchedSchool;

      // 1. Search in cached _schools by code, id, or name (case-insensitive)
      for (final s in _schools) {
        final code = (s['code'] ?? '').toString().trim().toLowerCase();
        final id = (s['id'] ?? '').toString().trim().toLowerCase();
        final name = (s['name'] ?? '').toString().trim().toLowerCase();
        if (code == inputLower || id == inputLower || name == inputLower) {
          matchedSchool = s;
          break;
        }
      }

      // 2. Direct Firestore fallback query if not found in memory
      if (matchedSchool == null) {
        try {
          final querySnap = await FirebaseFirestore.instance
              .collection('schools')
              .where('code', isEqualTo: typedText)
              .limit(1)
              .get();
          if (querySnap.docs.isNotEmpty) {
            final doc = querySnap.docs.first;
            final data = doc.data();
            matchedSchool = {
              'id': doc.id,
              'name': (data['name'] ?? '').toString(),
              'adminEmail': (data['adminEmail'] ?? '').toString(),
              'code': (data['code'] ?? '').toString(),
              'logoUrl': data['logoUrl'] ?? data['logoBase64'] ?? data['logo'],
            };
          } else {
            final docSnap = await FirebaseFirestore.instance
                .collection('schools')
                .doc(typedText)
                .get();
            if (docSnap.exists && docSnap.data()?['deleted'] != true) {
              final data = docSnap.data()!;
              matchedSchool = {
                'id': docSnap.id,
                'name': (data['name'] ?? '').toString(),
                'adminEmail': (data['adminEmail'] ?? '').toString(),
                'code': (data['code'] ?? '').toString(),
                'logoUrl': data['logoUrl'] ?? data['logoBase64'] ?? data['logo'],
              };
            }
          }
        } catch (e) {
          debugPrint('[LOGIN] Direct Firestore query error: $e');
        }
      }

      if (matchedSchool == null) {
        setState(() {
          _isLoggingIn = false;
          _errorMessage = 'Kode sekolah tidak ditemukan. Silakan periksa kembali kode sekolah Anda.';
        });
        return;
      }

      _selectedSchool = matchedSchool;
      final schoolId = _selectedSchool!['id'] as String;

      // 1. Cek langsung ke Firestore pada Web Mobile apakah password terdaftar milik siswa di sekolah ini
      if (isWebMobile()) {
        try {
          final studentSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('students')
              .where('tempPassword', isEqualTo: password)
              .limit(1)
              .get();

          if (studentSnap.docs.isNotEmpty) {
            if (mounted) {
              setState(() => _isLoggingIn = false);
              await _showStudentWebBlockedDialog();
            }
            return;
          }
        } catch (_) {}
      }

      try {
        final currentSessionId = await StudentSessionService.getCurrentSessionId();
        final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('resolveEmailByPassword');
        final response = await callable.call({
          'schoolId': schoolId,
          'password': password,
          'currentSessionId': currentSessionId,
        });

        final resData = response.data as Map?;
        final bool success = resData?['success'] == true;

        if (resData?['alreadyLoggedIn'] == true) {
          if (mounted) {
            setState(() => _isLoggingIn = false);
            final activeDevice = resData?['activeDevice'] as String? ?? 'Perangkat / Browser Lain';
            final studentName = resData?['studentName'] as String? ?? 'Siswa';
            await _showStudentAlreadyLoggedInDialog(
              studentName: studentName,
              activeDevice: activeDevice,
            );
          }
          return;
        }

        if (success) {
          final resolvedEmail = resData?['email'] as String?;
          resolvedRole = resData?['role'] as String?;
          resolvedStudentId = resData?['studentId'] as String?;

          // Penolakan siswa jika masuk dari Web Mobile
          if (isWebMobile() && resolvedRole == 'student') {
            if (mounted) {
              setState(() => _isLoggingIn = false);
              await _showStudentWebBlockedDialog();
            }
            return;
          }

          if (resolvedEmail != null && resolvedEmail.isNotEmpty) {
            emailOrUsername = resolvedEmail;
          } else {
            setState(() {
              _isLoggingIn = false;
              _errorMessage = 'Akun ditemukan tetapi email tidak valid';
            });
            return;
          }
        } else {
          emailOrUsername = _selectedSchool!['adminEmail'] as String;
        }
      } catch (e) {
        setState(() {
          _isLoggingIn = false;
          _errorMessage = 'Gagal memverifikasi akun sekolah: $e';
        });
        return;
      }
    }

    try {
      await authService.signIn(emailOrUsername, password);

      // Simpan kode sekolah terakhir login untuk otomatis terisi saat keluar akun
      if (!isSuperAdminLogin && typedText.isNotEmpty) {
        final codeToSave = (_selectedSchool?['code'] ?? typedText).toString().trim();
        if (codeToSave.isNotEmpty && codeToSave.toLowerCase() != 'sadmin') {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('last_school_code', codeToSave);
          } catch (_) {}
        }
      }

      // Auth state and GoRouter refreshListenable automatically handle redirect
      // to /blocked if student is inactive, or to /student/ringkasan if active.

      // 2. Pengecekan menyeluruh setelah signIn di Web Mobile: Cek apakah user login adalah siswa
      if (isWebMobile() && authService.user != null) {
        bool isStudentUser = authService.role == 'student';
        if (!isStudentUser) {
          try {
            final stdCheck = await FirebaseFirestore.instance
                .collectionGroup('students')
                .where('email', isEqualTo: authService.user!.email)
                .limit(1)
                .get();
            if (stdCheck.docs.isNotEmpty) {
              isStudentUser = true;
            }
          } catch (_) {}
        }

        if (isStudentUser) {
          // Sign out TERLEBIH DAHULU sebelum menampilkan dialog,
          // agar GoRouter tidak redirect ke halaman siswa saat dialog sedang terbuka.
          await authService.signOut();
          if (mounted) {
            setState(() => _isLoggingIn = false);
            await _showStudentWebBlockedDialog();
          }
          return;
        }
      }

      // 3. Daftarkan sesi unik siswa jika yang login adalah siswa
      if (resolvedRole == 'student' || authService.role == 'student') {
        try {
          final schoolId = _selectedSchool?['id'] as String? ?? authService.schoolId ?? '';
          if (schoolId.isNotEmpty) {
            await StudentSessionService.registerSession(
              schoolId: schoolId,
              studentId: resolvedStudentId,
              uid: authService.user?.uid,
            );
          }
        } catch (e) {
          debugPrint('[LOGIN] Error registering student session: $e');
        }
      }

      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      final isCredError = e.toString().contains('user-not-found') ||
          e.toString().contains('wrong-password') ||
          e.toString().contains('invalid-credential') ||
          e.toString().contains('invalid-email');

      final message = isCredError
          ? 'Kata sandi salah atau akun tidak ditemukan!'
          : 'Gagal masuk: $e';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );

      setState(() {
        _isLoggingIn = false;
        _errorMessage = message;
      });
    }
  }

  /// Menampilkan dialog peringatan bahwa akun siswa tidak boleh login via browser mobile (smartphone).
  /// Menggunakan [showDialog] (Navigator-level) agar tetap tampil meskipun
  /// GoRouter mencoba menavigasi halaman (dialog muncul di atas route manapun).
  Future<void> _showStudentWebBlockedDialog() async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 380,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header merah
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.smartphone_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Akses Ditolak',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Login Siswa via Web Mobile',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Akun siswa tidak dapat digunakan untuk login melalui Web Browser di Smartphone / Tablet.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Color(0xFFF97316), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Gunakan Aplikasi SesiCermat Exam pada smartphone Anda, atau buka Web melalui Komputer / Laptop (PC).',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: const Color(0xFF9A3412),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Mengerti',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
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
      },
    );
  }

  /// Menampilkan dialog peringatan bahwa akun siswa sedang aktif di perangkat lain.
  Future<void> _showStudentAlreadyLoggedInDialog({
    required String studentName,
    required String activeDevice,
  }) async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 400,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFEA580C), Color(0xFFDC2626)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phonelink_lock_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Akun Sedang Aktif',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Login Ganda Tidak Diizinkan',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Akun siswa "$studentName" saat ini sedang login di perangkat lain:',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          color: const Color(0xFF334155),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFEDD5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.devices_rounded, color: Color(0xFFEA580C), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                activeDevice,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF9A3412),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Untuk menjaga kepatuhan ujian, siswa hanya dapat login pada satu perangkat/browser dalam satu waktu.\n\nSilakan keluar (logout) dari perangkat tersebut terlebih dahulu, atau hubungi Pengawas Ujian / Admin Sekolah untuk mereset sesi login Anda.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: const Color(0xFF64748B),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Saya Mengerti',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
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
      },
    );
  }

  /// Menampilkan dialog bahwa sesi siswa diakhiri (misal di-reset oleh guru/admin).
  Future<void> _showSessionTerminatedDialog(String message) async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 380,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pemberitahuan Sesi',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          color: const Color(0xFF334155),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Tutup', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
  }

  @override
  Widget build(BuildContext context) {

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    if (isDesktop) {
      return _buildDesktopLayout(size);
    }
    return _buildMobileLayout(size);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DESKTOP LAYOUT
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(Size size) {
    return Scaffold(
      body: Row(
        children: [
          // Left branding panel
          Expanded(
            flex: 11,
            child: _buildBrandingPanel(size),
          ),
          // Right form panel
          Expanded(
            flex: 9,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                image: DecorationImage(
                  image: AssetImage('assets/images/batik.jpg'),
                  fit: BoxFit.none, // Retain original size and tile
                  repeat: ImageRepeat.repeat,
                  opacity: 0.04, // Very subtle opacity for elegant look
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: _buildLoginCard(isDesktop: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOBILE LAYOUT
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout(Size size) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_orb1Controller, _orb2Controller]),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildMobileLogo(),
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: _buildLoginCard(isDesktop: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0C0F2E), Color(0xFF1A1040), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                // Decorative orbs only rebuild on animation frames
                _buildOrb(
                  left: size.width * (0.1 + _orb1Anim.value * 0.15),
                  top: size.height * (0.05 + _orb1Anim.value * 0.05),
                  size: 200,
                  color: const Color(0xFF4F46E5),
                  opacity: 0.18,
                ),
                _buildOrb(
                  right: size.width * (0.05 + _orb2Anim.value * 0.1),
                  top: size.height * (0.35 + _orb2Anim.value * 0.1),
                  size: 160,
                  color: const Color(0xFF06B6D4),
                  opacity: 0.12,
                ),
                // Login card is passed as child and does NOT rebuild every frame
                if (child != null) child,
              ],
            ),
          );
        },
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  // BRANDING PANEL (LEFT)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBrandingPanel(Size size) {
    return AnimatedBuilder(
      animation: Listenable.merge([_orb1Controller, _orb2Controller]),
      builder: (context, child) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0C0F2E), Color(0xFF1A1040), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // Floating glowing orbs
              _buildOrb(
                left: -60,
                top: size.height * (0.08 + _orb1Anim.value * 0.04),
                size: 280,
                color: const Color(0xFF4F46E5),
                opacity: 0.15,
              ),
              _buildOrb(
                right: -40,
                bottom: size.height * (0.15 + _orb2Anim.value * 0.05),
                size: 220,
                color: const Color(0xFF06B6D4),
                opacity: 0.12,
              ),
              _buildOrb(
                left: size.width * 0.2,
                top: size.height * (0.55 + _orb1Anim.value * 0.03),
                size: 140,
                color: const Color(0xFF8B5CF6),
                opacity: 0.1,
              ),
              // Grid dot pattern overlay
              Positioned.fill(
                child: CustomPaint(painter: _DotGridPainter()),
              ),
              // Main content
              Padding(
                padding: const EdgeInsets.all(64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top logo
                    ScaleTransition(
                      scale: _logoScaleAnim,
                      child: _buildDesktopLogo(),
                    ),
                    // Center content
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4338CA).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34D399),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'SISTEM UJIAN SEKOLAH',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFC7D2FE),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Headline
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Colors.white, Color(0xFFE2E8F0)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ).createShader(bounds),
                          child: Text(
                            'Portal Ujian\nDigital Modern\n& Praktis.',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 46,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              letterSpacing: -1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'SesiCermat menghadirkan kenyamanan ujian tanpa kertas bagi murid, guru, dan admin sekolah dalam satu ekosistem cloud yang cepat dan aman.',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF94A3B8),
                            fontSize: 16,
                            height: 1.6,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 48),
                        _buildFeatureRow(
                          Icons.people_alt_rounded,
                          'Manajemen Guru & Murid Real-time',
                          gradient: const [Color(0xFF065F46), Color(0xFF047857)],
                          iconColor: const Color(0xFF34D399),
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          Icons.assignment_turned_in_rounded,
                          'Integrasi Ujian & Penilaian Otomatis',
                          gradient: const [Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
                          iconColor: const Color(0xFF60A5FA),
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          Icons.auto_awesome_rounded,
                          'Antarmuka Interaktif & Inovatif',
                          gradient: const [Color(0xFF701A75), Color(0xFF9D174D)],
                          iconColor: const Color(0xFFF472B6),
                        ),
                      ],
                    ),
                    // Footer
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 1,
                          color: const Color(0xFF334155),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '© 2026 SesiCermat. Hak Cipta Dilindungi.',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF475569),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopLogo() {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/images/Logo_SesiCermat.png', width: 40, height: 40, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'SesiCermat',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLogo() {
    return ScaleTransition(
      scale: _logoScaleAnim,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.45),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/images/Logo_SesiCermat.png', width: 76, height: 76, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'SesiCermat',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SesiCermat Exam',
            style: GoogleFonts.inter(
              color: const Color(0xFF94A3B8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text, {List<Color>? gradient, Color? iconColor}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient ?? [const Color(0xFF065F46), const Color(0xFF047857)],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: (gradient?.first ?? const Color(0xFF065F46)).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: iconColor ?? const Color(0xFF34D399), size: 16),
        ),
        const SizedBox(width: 14),
        Text(
          text,
          style: GoogleFonts.inter(
            color: const Color(0xFFCBD5E1),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIN CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLoginCard({required bool isDesktop}) {
    final isDark = !isDesktop;
    final cardBg = isDark
        ? const Color(0xFF1C2235).withValues(alpha: 0.85)
        : Colors.white;
    final cardBorder = isDark
        ? const Color(0xFF334155).withValues(alpha: 0.6)
        : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final inputBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cardBorder, width: 0.5),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                  blurRadius: 60,
                  offset: const Offset(0, 0),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedSchool != null) ...[
              (() {
                final logoUrlStr = _selectedSchool!['logoUrl']?.toString().trim() ?? '';
                debugPrint('[Login] logo check: id=${_selectedSchool!["id"]}, logoUrl length=${logoUrlStr.length}');
                if (logoUrlStr.isNotEmpty) {
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      width: 80,
                      height: 80,
                      child: _buildSchoolLogoImage(logoUrlStr),
                    ),
                  );
                }
                return const SizedBox.shrink();
              })(),
            ],
            // Header Title
            Text(
              _selectedSchool != null ? 'Selamat Datang' : 'Selamat Datang',
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: titleColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            // Header Subtitle
            Text(
              _selectedSchool != null
                  ? (_selectedSchool!['name'] ?? 'Masuk ke portal sekolah Anda untuk melanjutkan.')
                  : 'Masuk ke portal sekolah Anda untuk melanjutkan.',
              style: GoogleFonts.inter(
                fontSize: _selectedSchool != null ? 15 : 14,
                fontWeight: _selectedSchool != null ? FontWeight.w600 : FontWeight.normal,
                color: subtitleColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),

            // Error message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF7F1D1D).withValues(alpha: 0.25)
                      : const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                        : const Color(0xFFFCA5A5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFEF4444),
                        size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(
                          color: isDark
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFFB91C1C),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Kode Sekolah
            _buildLabel('Kode Sekolah', isDark),
            const SizedBox(height: 8),
            _buildInputField(
              controller: _schoolCodeController,
              hintText: 'Masukkan kode sekolah...',
              prefixIcon: Icons.apartment_rounded,
              isDark: isDark,
              inputTextColor: inputTextColor,
              subtitleColor: subtitleColor,
              inputBorderColor: inputBorderColor,
              onChanged: (text) {
                final term = text.trim().toLowerCase();
                if (term.isEmpty) {
                  if (_selectedSchool != null) {
                    setState(() {
                      _selectedSchool = null;
                    });
                  }
                } else {
                  final found = _schools.cast<Map<String, dynamic>?>().firstWhere(
                    (s) =>
                        (s?['code'] ?? '').toString().trim().toLowerCase() == term ||
                        (s?['id'] ?? '').toString().trim().toLowerCase() == term,
                    orElse: () => null,
                  );
                  if (found != _selectedSchool) {
                    setState(() {
                      _selectedSchool = found;
                    });
                    if (found != null) {
                      _fetchSchoolLogoDirectly(found['id']);
                    }
                  }
                }
              },
              suffixIcon: _schoolCodeController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: subtitleColor),
                      onPressed: () {
                        _schoolCodeController.clear();
                        setState(() {
                          _selectedSchool = null;
                        });
                      },
                    )
                  : null,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Silakan masukkan kode sekolah atau sadmin';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Password
            _buildLabel('Kata Sandi', isDark),
            const SizedBox(height: 8),
            _buildInputField(
              controller: _passwordController,
              hintText: 'Masukkan kata sandi',
              prefixIcon: Icons.lock_outline_rounded,
              isDark: isDark,
              inputTextColor: inputTextColor,
              subtitleColor: subtitleColor,
              inputBorderColor: inputBorderColor,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleLogin(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: subtitleColor,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Kata sandi tidak boleh kosong';
                }
                return null;
              },
            ),
            const SizedBox(height: 28),

            // Submit Button
            _buildSubmitButton(),

            const SizedBox(height: 20),
            // Footer note
            Center(
              child: Text(
                'Gunakan akun yang diberikan oleh admin sekolah Anda.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: subtitleColor.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF374151),
      ),
    );
  }

  Widget _buildInputField({
    TextEditingController? controller,
    FocusNode? focusNode,
    required String hintText,
    required IconData prefixIcon,
    required bool isDark,
    required Color inputTextColor,
    required Color subtitleColor,
    required Color inputBorderColor,
    Widget? suffixIcon,
    bool obscureText = false,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: inputTextColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.inter(
          color: subtitleColor.withValues(alpha: 0.5),
          fontSize: 14,
        ),
        prefixIcon: Icon(prefixIcon, color: subtitleColor, size: 20),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF1F5F9).withValues(alpha: 0.6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: inputBorderColor.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _isLoggingIn
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF4338CA), Color(0xFF4F46E5), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isLoggingIn
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: _isLoggingIn ? null : _handleLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _isLoggingIn
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Memverifikasi...',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Masuk ke Portal',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOrb({
    double? left,
    double? right,
    double? top,
    double? bottom,
    required double size,
    required Color color,
    required double opacity,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchSchoolLogoDirectly(String schoolId) async {
    try {
      final docSnap = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
      if (docSnap.exists && mounted) {
        final data = docSnap.data();
        if (data != null) {
          final logo = data['logoUrl'] ?? data['logoBase64'] ?? data['logo'];
          if (logo != null && logo.toString().isNotEmpty) {
            setState(() {
              if (_selectedSchool != null && _selectedSchool!['id'] == schoolId) {
                _selectedSchool = {
                  ..._selectedSchool!,
                  'logoUrl': logo.toString(),
                };
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching logo directly: $e");
    }
  }

  Widget _buildSchoolLogoImage(String logoUrl) {
    final trimmed = logoUrl.trim();
    if (trimmed.isEmpty) {
      return const Icon(Icons.school_rounded, color: Color(0xFF4F46E5), size: 48);
    }

    if (trimmed.contains('base64,')) {
      try {
        final base64Data = trimmed.split('base64,').last.replaceAll(RegExp(r'\s+'), '');
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, error, __) {
            debugPrint('[Login] Image.memory error: $error');
            return const Icon(Icons.school_rounded, color: Color(0xFF4F46E5), size: 48);
          },
        );
      } catch (e) {
        debugPrint('[Login] base64 decode error: $e');
      }
    } else if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: 80,
        height: 80,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: Color(0xFF4F46E5), size: 48),
      );
    }

    return const Icon(Icons.school_rounded, color: Color(0xFF4F46E5), size: 48);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOT GRID BACKGROUND PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
