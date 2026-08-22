import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/services/auth_service.dart';
import 'firebase_options.dart';
import 'modules/auth/views/login_page.dart';
import 'modules/super_admin/views/dashboard_page.dart';
import 'modules/admin/views/admin_school_dashboard_page.dart';
import 'modules/teacher/views/teacher_dashboard_page.dart';
import 'modules/teacher/views/teacher_event_detail_page.dart';
import 'modules/teacher/views/teacher_proctor_room_page.dart';
import 'modules/student/views/student_dashboard_page.dart';
import 'modules/subscription/views/subscription_blocked_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Indonesian date formatting symbols
  try {
    await initializeDateFormatting('id_ID', null);
  } catch (_) {}

  // Suppress Flutter Web DDC WidgetInspector crash loop completely
  FlutterError.onError = (FlutterErrorDetails details) {
    // Empty handler prevents dumpErrorToConsole from triggering LegacyJavaScriptObject crash loop
  };

  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    return true; // Silence uncaught platform errors on web dev compiler
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthService _authService = AuthService();
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: _authService,
      redirect: (context, state) {
        if (_authService.isLoading) return null;
        final loggedIn = _authService.user != null;
        final isLoginRoute = state.matchedLocation == '/login';
        final loc = state.matchedLocation;
        final role = _authService.role;

        // 1. Jika belum login -> paksa ke /login untuk semua rute terproteksi
        if (!loggedIn) {
          return isLoginRoute ? null : '/login';
        }

        // 2. Jika sudah login dan mencoba ke /login -> redirect ke / (yang akan memicu guard role)
        if (isLoginRoute) {
          return '/';
        }

        // 3. Cek status blokir langganan sekolah
        if (_authService.isBlocked && loc != '/blocked') {
          return '/blocked';
        }

        if (!_authService.isBlocked && loc == '/blocked') {
          return '/';
        }

        // 4. Strict Role-Based Route Guard (Cegah pembobolan via URL)
        if (role == 'super_admin') {
          if (loc == '/' || loc.startsWith('/teacher')) {
            return '/superadmin';
          }
        } else if (role == 'school_admin') {
          if (loc == '/' || loc == '/admin' || loc.startsWith('/teacher') || loc.startsWith('/superadmin')) {
            return '/admin/ringkasan';
          }
        } else if (role == 'teacher') {
          // Guru HANYA boleh mengakses rute /teacher dan sub-rutenya
          if (loc == '/' || loc == '/teacher' || !loc.startsWith('/teacher')) {
            return '/teacher/ringkasan';
          }
        } else if (role == 'student') {
          // Student TIDAK diizinkan mengakses via Web Browser
          if (kIsWeb) {
            _authService.signOut();
            return '/login';
          }
          // Student HANYA boleh mengakses rute /student
          if (!loc.startsWith('/student')) {
            return '/placeholder';
          }
        } else {
          if (loc != '/placeholder') {
            return '/placeholder';
          }
        }

        if (loc == '/admin') {
          return '/admin/ringkasan';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/blocked',
          builder: (context, state) => const SubscriptionBlockedPage(),
        ),
        GoRoute(
          path: '/superadmin',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: '/admin/:tab',
          builder: (context, state) {
            final tab = state.pathParameters['tab'];
            return AdminSchoolDashboardPage(tabName: tab);
          },
        ),
        GoRoute(
          path: '/teacher/:tab',
          builder: (context, state) {
            final tab = state.pathParameters['tab'];
            return TeacherDashboardPage(tabName: tab);
          },
        ),
        GoRoute(
          path: '/teacher/event/:eventId/:tab',
          builder: (context, state) {
            final eventId = state.pathParameters['eventId']!;
            final tabName = state.pathParameters['tab'];
            final eventName = state.uri.queryParameters['name'] ?? 'Event Ujian';
            return TeacherEventDetailPage(eventId: eventId, eventName: eventName, tabName: tabName);
          },
        ),
        GoRoute(
          path: '/teacher/event/:eventId/proctor-room/:roomId',
          builder: (context, state) {
            final eventId = state.pathParameters['eventId']!;
            final roomId = state.pathParameters['roomId']!;
            final dayIndex = int.tryParse(state.uri.queryParameters['dayIndex'] ?? '0') ?? 0;
            final sessionIndex = int.tryParse(state.uri.queryParameters['sessionIndex'] ?? '0') ?? 0;
            final docId = state.uri.queryParameters['docId'] ?? '';
            return TeacherProctorRoomPage(
              eventId: eventId,
              roomId: roomId,
              dayIndex: dayIndex,
              sessionIndex: sessionIndex,
              docId: docId,
            );
          },
        ),
        GoRoute(
          path: '/student',
          builder: (context, state) => const StudentDashboardPage(),
        ),
        GoRoute(
          path: '/placeholder',
          builder: (context, state) {
            final role = _authService.role;
            return Scaffold(
              appBar: AppBar(
                title: Text('Dashboard ${role?.replaceAll('_', ' ').toUpperCase() ?? "PENGGUNA"}'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout_rounded),
                    onPressed: () => _authService.signOut(),
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
                      onPressed: () => _authService.signOut(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Keluar'),
                    ),
                  ],
                ),
              ),
            );
          },
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthService>.value(
      value: _authService,
      child: MaterialApp.router(
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
        routerConfig: _router,
      ),
    );
  }
}
