import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  // Autocomplete controller reference
  TextEditingController? _schoolSearchController;

  // School selection states
  List<Map<String, dynamic>> _schools = [];
  Map<String, dynamic>? _selectedSchool;
  bool _isLoadingSchools = true;
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
    _fetchSchools();
    _initAnimations();
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
          .orderBy('name')
          .get();
      if (mounted) {
        setState(() {
          _schools = snapshot.docs.map((doc) => {
            'id': doc.id,
            'name': doc.data()['name'],
            'adminEmail': doc.data()['adminEmail'],
            'code': doc.data()['code'],
          }).toList();
          _isLoadingSchools = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal mengambil daftar sekolah: $e");
      if (mounted) {
        setState(() {
          _isLoadingSchools = false;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoggingIn = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    final typedText = _schoolSearchController?.text.trim() ?? '';
    final password = _passwordController.text;

    String emailOrUsername = '';

    if (typedText.toLowerCase() == 'sadmin') {
      emailOrUsername = 'sadmin@sesicermat.com';
    } else {
      if (_selectedSchool == null || _selectedSchool!['name'] != typedText) {
        setState(() {
          _isLoggingIn = false;
          _errorMessage = 'Silakan pilih sekolah yang valid dari daftar pencarian';
        });
        return;
      }

      final schoolId = _selectedSchool!['id'] as String;

      try {
        final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('resolveEmailByPassword');
        final response = await callable.call({
          'schoolId': schoolId,
          'password': password,
        });

        final resData = response.data as Map?;
        final bool success = resData?['success'] == true;

        if (success) {
          final resolvedEmail = resData?['email'] as String?;
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
              color: const Color(0xFFF8FAFC),
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
                // Decorative orbs
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
                // Content
                SafeArea(
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
                        Text(
                          'Portal Ujian\nDigital Modern\n& Praktis.',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'SesiCermat menghadirkan kenyamanan ujian tanpa kertas bagi murid, guru, dan admin sekolah dalam satu ekosistem cloud yang cepat dan aman.',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF94A3B8),
                            fontSize: 15,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: 40),
                        _buildFeatureRow(Icons.people_alt_rounded, 'Manajemen Guru & Murid Real-time'),
                        const SizedBox(height: 14),
                        _buildFeatureRow(Icons.assignment_turned_in_rounded, 'Integrasi Ujian & Penilaian Otomatis'),
                        const SizedBox(height: 14),
                        _buildFeatureRow(Icons.shield_rounded, 'Keamanan Firebase Terproteksi'),
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.school_rounded, color: Colors.white, size: 24),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.5),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.school_rounded, color: Colors.white, size: 32),
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
            'Sistem Ujian Sekolah Digital',
            style: GoogleFonts.inter(
              color: const Color(0xFF94A3B8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF065F46), Color(0xFF047857)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF34D399), size: 14),
        ),
        const SizedBox(width: 12),
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
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorder),
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
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              'Selamat Datang 👋',
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: titleColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Masuk ke portal sekolah Anda untuk melanjutkan.',
              style: GoogleFonts.inter(
                fontSize: 14,
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

            // School Autocomplete
            _buildLabel('Nama Sekolah', isDark),
            const SizedBox(height: 8),
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                final term = textEditingValue.text.trim().toLowerCase();
                if (term.isEmpty) return _schools.take(3);
                if (term == 'sadmin') return const Iterable<Map<String, dynamic>>.empty();
                final filtered = _schools.where((school) {
                  final name = school['name'].toString().toLowerCase();
                  final code = school['code'].toString().toLowerCase();
                  return name.contains(term) || code.contains(term);
                });
                return filtered.take(5);
              },
              displayStringForOption: (Map<String, dynamic> option) => option['name'],
              onSelected: (Map<String, dynamic> selection) {
                setState(() {
                  _selectedSchool = selection;
                });
              },
              fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                _schoolSearchController = textEditingController;
                return _buildInputField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  hintText: _isLoadingSchools ? 'Memuat daftar sekolah...' : 'Ketik nama sekolah...',
                  prefixIcon: Icons.search_rounded,
                  isDark: isDark,
                  inputTextColor: inputTextColor,
                  subtitleColor: subtitleColor,
                  inputBorderColor: inputBorderColor,
                  suffixIcon: textEditingController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, size: 18, color: subtitleColor),
                          onPressed: () {
                            textEditingController.clear();
                            setState(() {
                              _selectedSchool = null;
                            });
                          },
                        )
                      : null,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Silakan masukkan nama sekolah atau sadmin';
                    }
                    return null;
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final size = MediaQuery.of(context).size;
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 0,
                    color: Colors.transparent,
                    child: Container(
                      width: size.width > 900 ? 348 : size.width - 80,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final Map<String, dynamic> option = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(option),
                              hoverColor: isDark
                                  ? const Color(0xFF4F46E5).withValues(alpha: 0.08)
                                  : const Color(0xFFF5F3FF),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                decoration: BoxDecoration(
                                  border: index < options.length - 1
                                      ? Border(
                                          bottom: BorderSide(
                                            color: isDark
                                                ? const Color(0xFF334155)
                                                : const Color(0xFFF1F5F9),
                                          ),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.business_rounded,
                                          color: Color(0xFF4F46E5), size: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option['name'],
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "Kode: ${option['code']}",
                                            style: GoogleFonts.inter(
                                              color: subtitleColor,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios_rounded,
                                        size: 12, color: subtitleColor),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: GoogleFonts.inter(color: inputTextColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.inter(
          color: subtitleColor.withValues(alpha: 0.5),
          fontSize: 14,
        ),
        prefixIcon: Icon(prefixIcon, color: subtitleColor, size: 20),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
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
