import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  @override
  void dispose() {
    _passwordController.dispose();
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

    // Get the typed text from the search field
    final typedText = _schoolSearchController?.text.trim() ?? '';
    final password = _passwordController.text;

    String emailOrUsername = '';

    // Check if the typed text is exactly "sadmin" to trigger Super Admin login
    if (typedText.toLowerCase() == 'sadmin') {
      emailOrUsername = 'sadmin@sesicermat.com';
    } else {
      // Validate that a school has been selected and the text matches the school name
      if (_selectedSchool == null || _selectedSchool!['name'] != typedText) {
        setState(() {
          _isLoggingIn = false;
          _errorMessage = 'Silakan pilih sekolah yang valid dari daftar pencarian';
        });
        return;
      }

      final schoolId = _selectedSchool!['id'] as String;

      try {
        // Panggil secure Cloud Function untuk mencocokkan password tanpa melanggar Security Rules
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
          // 3. Fallback ke email admin sekolah jika tidak cocok dengan password guru/murid
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
      await authService.signIn(
        emailOrUsername,
        password,
      );
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

      // Tampilkan notifikasi SnackBar melayang
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Row(
          children: [
            // Left Panel (Branding)
            Expanded(
              flex: 11,
              child: Container(
                color: const Color(0xFF0F172A), // Slate 900
                padding: const EdgeInsets.all(64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: Color(0xFF818CF8),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'SesiCermat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF312E81), // Indigo 900
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF4338CA)), // Indigo 700
                          ),
                          child: const Text(
                            'SISTEM UJIAN SEKOLAH',
                            style: TextStyle(
                              color: Color(0xFFC7D2FE), // Indigo 200
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Portal Ujian Digital\nModern & Praktis.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'SesiCermat menghadirkan kenyamanan ujian tanpa kertas bagi murid, guru, dan admin sekolah dalam satu ekosistem cloud yang cepat dan aman.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8), // Slate 400
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 40),
                        _buildFeatureRow('Manajemen Guru & Murid Real-time'),
                        const SizedBox(height: 16),
                        _buildFeatureRow('Integrasi Ujian & Penilaian Otomatis'),
                        const SizedBox(height: 16),
                        _buildFeatureRow('Keamanan Firebase Terproteksi'),
                      ],
                    ),
                    const Text(
                      '© 2026 SesiCermat. Hak Cipta Dilindungi.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Right Panel (Form)
            Expanded(
              flex: 9,
              child: Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: Center(
                  child: SingleChildScrollView(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildLoginForm(context, size, true),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Mobile/Tablet Layout
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0F172A), // Slate 900
              Color(0xFF1E1B4B), // Indigo 955
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF818CF8).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: Color(0xFF818CF8),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'SesiCermat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildLoginForm(context, size, false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Color(0xFF064E3B), // Emerald 900
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF34D399), // Emerald 400
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFFE2E8F0),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context, Size size, bool isDesktop) {
    final isDark = !isDesktop;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final inputBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x1F000000) : const Color(0x08000000),
            blurRadius: 24,
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
            Text(
              'Portal Masuk',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Masukkan kredensial sekolah Anda untuk melanjutkan.',
              style: TextStyle(
                fontSize: 14,
                color: subtitleColor,
              ),
            ),
            const SizedBox(height: 32),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.3) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? const Color(0xFFEF4444) : const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFEF4444), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
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

            // Searchable Autocomplete School Selection
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                final term = textEditingValue.text.trim().toLowerCase();
                if (term.isEmpty) {
                  return _schools.take(3);
                }
                if (term == 'sadmin') {
                  return const Iterable<Map<String, dynamic>>.empty();
                }
                final filtered = _schools.where((school) {
                  final name = school['name'].toString().toLowerCase();
                  final code = school['code'].toString().toLowerCase();
                  return name.contains(term) || code.contains(term);
                });
                return filtered.take(3);
              },
              displayStringForOption: (Map<String, dynamic> option) => option['name'],
              onSelected: (Map<String, dynamic> selection) {
                setState(() {
                  _selectedSchool = selection;
                });
              },
              fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                _schoolSearchController = textEditingController;

                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  style: TextStyle(color: inputTextColor),
                  decoration: InputDecoration(
                    labelText: 'Cari & Pilih Sekolah',
                    labelStyle: TextStyle(color: subtitleColor),
                    hintText: _isLoadingSchools ? 'Memuat...' : 'Ketik nama sekolah...',
                    hintStyle: TextStyle(color: subtitleColor.withValues(alpha: 0.6)),
                    prefixIcon: Icon(Icons.search_rounded, color: subtitleColor),
                    suffixIcon: textEditingController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 18, color: subtitleColor),
                            onPressed: () {
                              textEditingController.clear();
                              setState(() {
                                _selectedSchool = null;
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: inputBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF818CF8),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Silakan masukkan nama sekolah atau sadmin';
                    }
                    return null;
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 8.0,
                    borderRadius: BorderRadius.circular(12),
                    color: cardBg,
                    child: Container(
                      width: isDesktop ? 356 : size.width * 0.9 - 64 - 64, // adjusted width
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: index < options.length - 1
                                    ? Border(bottom: BorderSide(color: cardBorder))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.business_rounded, color: subtitleColor, size: 18),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          option['name'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: titleColor,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "Kode: ${option['code']}",
                                          style: TextStyle(
                                            color: subtitleColor,
                                            fontSize: 12,
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
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // Password Input
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleLogin(),
              style: TextStyle(color: inputTextColor),
              decoration: InputDecoration(
                labelText: 'Kata Sandi',
                labelStyle: TextStyle(color: subtitleColor),
                prefixIcon: Icon(Icons.lock_outline_rounded, color: subtitleColor),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: subtitleColor,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: inputBorderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF818CF8),
                    width: 2,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Kata sandi tidak boleh kosong';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),

            // Submit Button
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF4F46E5),
                    Color(0xFF6366F1),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: _isLoggingIn ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoggingIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Masuk',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
