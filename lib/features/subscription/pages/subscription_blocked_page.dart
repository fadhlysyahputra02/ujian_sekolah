import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';

class SubscriptionBlockedPage extends StatelessWidget {
  const SubscriptionBlockedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Blocked Icon Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2), // Red 100
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_clock_rounded,
                    size: 64,
                    color: Color(0xFFEF4444), // Red 500
                  ),
                ),
                const SizedBox(height: 32),

                // Main Header
                const Text(
                  'Perlu Perpanjang Langganan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B), // Slate 800
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),

                // Description Card
                Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Akses untuk sekolah Anda telah dinonaktifkan sementara oleh administrator sistem. '
                    'Silakan hubungi pihak sekolah atau administrator pusat SesiCermat untuk melakukan perpanjangan atau verifikasi status langganan Anda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: Color(0xFF475569), // Slate 600
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Action Buttons
                SizedBox(
                  width: 200,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await authService.signOut();
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text(
                      'Keluar Akun',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
