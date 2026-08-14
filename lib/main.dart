import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'core/services/auth_service.dart';
import 'firebase_options.dart';
import 'features/auth/pages/login_page.dart';
import 'features/dashboard/pages/admin_school_dashboard_page.dart';
import 'features/dashboard/pages/dashboard_page.dart';
import 'features/subscription/pages/subscription_blocked_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthService>(
      create: (_) => AuthService(),
      child: MaterialApp(
        title: 'SesiCermat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4F46E5),
            primary: const Color(0xFF4F46E5),
            secondary: const Color(0xFF06B6D4),
            brightness: Brightness.light,
          ),
          textTheme: GoogleFonts.interTextTheme(
            ThemeData.light().textTheme,
          ),
          appBarTheme: AppBarTheme(
            titleTextStyle: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}


class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    // 1. Show loading indicator while parsing auth state and custom claims
    if (authService.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF4F46E5),
          ),
        ),
      );
    }

    final user = authService.user;

    // 2. If not logged in, go to LoginPage
    if (user == null) {
      return const LoginPage();
    }

    // 3. Check if school is disabled (Subscription Block)
    if (authService.isBlocked) {
      return const SubscriptionBlockedPage();
    }

    // 4. Route based on role
    final role = authService.role;
    if (role == 'super_admin') {
      return const DashboardPage();
    } else if (role == 'school_admin') {
      return const AdminSchoolDashboardPage();
    } else {
      // Placeholder dashboard for school_admin, teacher, student when school is active
      return Scaffold(
        appBar: AppBar(
          title: Text('Dashboard ${role?.replaceAll('_', ' ').toUpperCase() ?? "PENGGUNA"}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => authService.signOut(),
            )
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 64,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Selamat Datang di Portal SesiCermat',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sekolah Anda aktif. Peran Anda: ${role ?? "Belum diatur"}',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => authService.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Keluar'),
              ),
            ],
          ),
        ),
      );
    }
  }
}
