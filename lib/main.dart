import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/services/auth_service.dart';
import 'core/services/network_service.dart';
import 'core/widgets/global_network_status_overlay.dart';
import 'core/routes/app_router.dart';
import 'firebase_options.dart';

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
    _router = AppRouter.createRouter(_authService);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: _authService),
        ChangeNotifierProvider<NetworkService>(create: (_) => NetworkService()),
      ],
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
        builder: (context, child) {
          return GlobalNetworkStatusOverlay(child: child ?? const SizedBox());
        },
        routerConfig: _router,
      ),
    );
  }
}
