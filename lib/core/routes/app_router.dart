import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../../modules/auth/views/login_page.dart';
import '../../modules/super_admin/views/dashboard_page.dart';
import '../../modules/admin/views/admin_school_dashboard_page.dart';
import '../../modules/teacher/views/teacher_dashboard_page.dart';
import '../../modules/teacher/views/teacher_event_detail_page.dart';
import '../../modules/teacher/views/teacher_proctor_room_page.dart';
import '../../modules/student/views/student_dashboard_page.dart';
import '../../modules/student/views/student_event_detail_page.dart';
import '../../modules/subscription/views/subscription_blocked_page.dart';
import '../constants/app_version.dart';
import '../widgets/app_splash_loader.dart';

class AppRouter {
  static GoRouter createRouter(AuthService authService) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: authService,
      redirect: (context, state) {
        if (authService.isLoading) return null;
        final loggedIn = authService.user != null;
        final isLoginRoute = state.matchedLocation == '/login';
        final loc = state.matchedLocation;
        final role = authService.role;

        // 1. Jika belum login -> paksa ke /login untuk semua rute terproteksi
        if (!loggedIn) {
          return isLoginRoute ? null : '/login';
        }

        // 2. Jika sudah login dan mencoba ke /login -> redirect ke / (yang akan memicu guard role)
        if (isLoginRoute) {
          return '/';
        }

        // 3. Cek status blokir langganan sekolah
        if (authService.isBlocked && loc != '/blocked') {
          return '/blocked';
        }

        if (!authService.isBlocked && loc == '/blocked') {
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
          // Student HANYA boleh mengakses rute /student
          if (loc == '/' || loc == '/student' || !loc.startsWith('/student')) {
            return '/student/ringkasan';
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
          builder: (context, state) => const AppSplashScreen(
            title: 'SesiCermat',
            subtitle: 'Memuat sistem & memverifikasi sesi...',
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
          routes: [
            GoRoute(
              path: 'event/:eventId',
              builder: (context, state) {
                final eventId = state.pathParameters['eventId']!;
                final eventName = state.uri.queryParameters['name'] ?? 'Event Ujian';
                return StudentEventDetailPage(eventId: eventId, eventName: eventName);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/student/event/:eventId',
          builder: (context, state) {
            final eventId = state.pathParameters['eventId']!;
            final eventName = state.uri.queryParameters['name'] ?? 'Event Ujian';
            return StudentEventDetailPage(eventId: eventId, eventName: eventName);
          },
        ),
        GoRoute(
          path: '/student/:tab',
          builder: (context, state) => const StudentDashboardPage(),
          routes: [
            GoRoute(
              path: 'event/:eventId',
              builder: (context, state) {
                final eventId = state.pathParameters['eventId']!;
                final eventName = state.uri.queryParameters['name'] ?? 'Event Ujian';
                return StudentEventDetailPage(eventId: eventId, eventName: eventName);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/placeholder',
          builder: (context, state) {
            final role = authService.role;
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
                    const SizedBox(height: 8),
                    Text(
                      AppVersion.version,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
}
