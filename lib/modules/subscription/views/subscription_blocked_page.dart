import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/auth_service.dart';

class SubscriptionBlockedPage extends StatefulWidget {
  const SubscriptionBlockedPage({super.key});

  @override
  State<SubscriptionBlockedPage> createState() => _SubscriptionBlockedPageState();
}

class _SubscriptionBlockedPageState extends State<SubscriptionBlockedPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnim = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final isStudentInactive = authService.isStudentInactive;

    final String titleText = isStudentInactive ? 'Akun Siswa Non-Aktif' : 'Akses Sekolah Ditangguhkan';
    final String subtitleText = isStudentInactive
        ? 'Mohon maaf, akun siswa Anda saat ini dalam status Non-Aktif. Anda tidak dapat mengakses fitur ujian SesiCermat.'
        : 'Layanan langganan sekolah Anda perlu diperpanjang oleh Administrator.';

    final IconData headerIcon = isStudentInactive ? Icons.person_off_rounded : Icons.lock_clock_rounded;
    final Color themeColor = isStudentInactive ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    final List<Color> gradientColors = isStudentInactive
        ? [const Color(0xFFD97706), const Color(0xFFF59E0B)]
        : [const Color(0xFFDC2626), const Color(0xFFEF4444)];

    final String statusDetail = isStudentInactive
        ? 'Non-Aktif (Dinonaktifkan oleh Admin Sekolah)'
        : 'Ditangguhkan (Perlu perpanjangan langganan)';

    final String helpDetail = isStudentInactive
        ? 'Silakan hubungi Wali Kelas atau Admin Sekolah Anda untuk mengaktifkan kembali akun Anda.'
        : 'Hubungi Admin Sekolah atau Tim Dukungan SesiCermat untuk verifikasi status langganan.';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Stack(
          children: [
            // Background ambient gradients
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF1E1035),
                      Color(0xFF0F172A),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Top decorative glowing orb
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      themeColor.withValues(alpha: 0.2),
                      themeColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom decorative glowing orb
            Positioned(
              bottom: -40,
              left: -40,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6366F1).withValues(alpha: 0.15),
                      const Color(0xFF6366F1).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Main Content
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated Pulsing Icon Header
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer pulse ring
                              Transform.scale(
                                scale: _pulseAnim.value,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: themeColor.withValues(alpha: 0.12 * _fadeAnim.value),
                                  ),
                                ),
                              ),
                              // Middle ring
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: themeColor.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: themeColor.withValues(alpha: 0.25),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              // Core icon container
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: gradientColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: themeColor.withValues(alpha: 0.45),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  headerIcon,
                                  size: 36,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),

                      // Title
                      Text(
                        titleText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitleText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF94A3B8),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Details Card (Glassmorphic)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              Icons.error_outline_rounded,
                              'Status Akun',
                              statusDetail,
                              themeColor,
                            ),
                            const SizedBox(height: 14),
                            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                            const SizedBox(height: 14),
                            _buildInfoRow(
                              Icons.support_agent_rounded,
                              'Petunjuk Pendaftaran',
                              helpDetail,
                              const Color(0xFF818CF8),
                            ),
                            const SizedBox(height: 14),
                            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                            const SizedBox(height: 14),
                            _buildInfoRow(
                              Icons.shield_outlined,
                              'Keamanan Data',
                              'Data dan riwayat akun Anda tetap tersimpan dengan aman di sistem sekolah.',
                              const Color(0xFF34D399),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Primary Action Button: "Kembali ke Halaman Login"
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await authService.signOut();
                            if (context.mounted) {
                              context.go('/login');
                            }
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          label: Text(
                            'Kembali ke Halaman Login',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0F172A),
                            elevation: 4,
                            shadowColor: Colors.black.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      Text(
                        'Portal Ujian SesiCermat',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon, String title, String subtitle, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
