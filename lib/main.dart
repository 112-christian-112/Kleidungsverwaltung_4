// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:kleidungsverwaltung_2/screens/about_screen.dart';
import 'package:kleidungsverwaltung_2/screens/admin/equipment/equipment_list_screen.dart';
import 'package:kleidungsverwaltung_2/screens/admin/equipment/equipment_scan_screen.dart';
import 'package:kleidungsverwaltung_2/screens/admin/equipment/equipment_status_screen.dart';
import 'package:kleidungsverwaltung_2/screens/admin/equipment/upcoming_inspections_screen.dart';
import 'package:kleidungsverwaltung_2/screens/all_activities_screen.dart';
import 'package:kleidungsverwaltung_2/screens/dashboard/dashboard_screen.dart';
import 'package:kleidungsverwaltung_2/screens/help_support_screen.dart';
import 'package:kleidungsverwaltung_2/screens/missions/add_missions_screen.dart';
import 'package:kleidungsverwaltung_2/screens/missions/mission_list_screen.dart';
import 'package:kleidungsverwaltung_2/screens/privacy_policy_sreen.dart';
import 'package:kleidungsverwaltung_2/screens/admin_user_approval_screen.dart';
import 'package:kleidungsverwaltung_2/services/pending_approval_screen.dart';
import 'package:kleidungsverwaltung_2/services/profile_completetion_screen.dart';
import 'package:kleidungsverwaltung_2/services/settings_screen.dart';
import 'package:kleidungsverwaltung_2/services/theme_services.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'services/auth_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX: immersiveSticky → edgeToEdge
  //
  // immersiveSticky versteckt Statusbar und Navigationleiste komplett.
  // Das ist problematisch für eine Feuerwehr-App: eingehende Anrufe,
  // Benachrichtigungen und die Uhr sind während des Einsatzes nicht sichtbar.
  //
  // edgeToEdge zeigt Statusbar und Navigationsleiste weiterhin an,
  // rendert den App-Inhalt aber dahinter (modernes Android-Verhalten).
  // Transparente Bars lassen Inhalte durchscheinen ohne sie zu verstecken.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final themeService = ThemeService();
  await themeService.initialize();

  await initializeDateFormatting('de_DE', '');
  Intl.defaultLocale = 'de_DE';

  runApp(
    ChangeNotifierProvider.value(
      value: themeService,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    return MaterialApp(
      title: 'Einsatzkleidung',
      debugShowCheckedModeBanner: false,
      theme: themeService.getLightTheme(),
      darkTheme: themeService.getDarkTheme(),
      themeMode: themeService.getThemeMode(),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de', 'DE'),
        Locale('en', 'US'),
      ],

      // ── Auth-Gate ────────────────────────────────────────────────────────
      // Äußerer StreamBuilder: reagiert auf Login/Logout (Firebase Auth)
      // Innerer StreamBuilder: reagiert auf Firestore-Änderungen (isApproved etc.)
      // Durch ValueKey(uid) wird der innere Stream bei jedem neuen Login
      // komplett neu aufgebaut → kein gecachter Zustand.
      home: StreamBuilder<User?>(
        stream: AuthService().user,
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final user = authSnapshot.data;
          if (user == null) return const LoginScreen();

          return StreamBuilder<Map<String, dynamic>>(
            key: ValueKey(user.uid),
            stream: AuthService().watchUserStatus(user.uid),
            builder: (context, statusSnapshot) {
              if (statusSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final status = statusSnapshot.data ?? {
                'exists': false,
                'isApproved': false,
                'isProfileComplete': false,
              };

              if (!status['exists'] || !status['isProfileComplete']) {
                return const ProfileCompletionScreen();
              }

              if (!status['isApproved']) {
                return const PendingApprovalScreen();
              }

              return const HomeScreen();
            },
          );
        },
      ),

      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/profile-completion': (context) => const ProfileCompletionScreen(),
        '/pending-approval': (context) => const PendingApprovalScreen(),
        '/admin-users': (context) => const AdminUserApprovalScreen(),
        '/admin-equipment': (context) => const EquipmentListScreen(),
        '/equipment-scan': (context) => const EquipmentScanScreen(),
        '/overdue-inspections': (context) => const UpcomingInspectionsScreen(),
        '/equipment-status': (context) => const EquipmentStatusScreen(),
        '/missions': (context) => const MissionListScreen(),
        '/add-mission': (context) => const AddMissionScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
        '/help-support': (context) => const HelpSupportScreen(),
        '/about': (context) => const AboutScreen(),
        '/all-activities': (context) => const AllActivitiesScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
