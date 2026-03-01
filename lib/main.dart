// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

      // ── Auth-Gate ────────────────────────────────────────────────────────
      // Äußerer StreamBuilder: reagiert auf Login/Logout (Firebase Auth)
      // Innerer StreamBuilder: reagiert auf Firestore-Änderungen (isApproved etc.)
      // Durch ValueKey(uid) wird der innere Stream bei jedem neuen Login
      // komplett neu aufgebaut → kein gecachter Zustand.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          // Firebase noch nicht bereit
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Nicht eingeloggt → Login
          if (!authSnapshot.hasData) {
            return const LoginScreen();
          }

          final uid = authSnapshot.data!.uid;

          // Eingeloggt → Live-Listener auf Firestore
          return StreamBuilder<Map<String, dynamic>>(
            key: ValueKey(uid),
            stream: AuthService().watchUserStatus(uid),
            builder: (context, statusSnapshot) {
              // Firestore noch nicht geantwortet
              if (statusSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 24),
                        Text('Benutzerstatus wird geprüft...'),
                      ],
                    ),
                  ),
                );
              }

              // Verbindungsfehler
              if (statusSnapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wifi_off,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('Verbindungsfehler',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => AuthService().signOut(),
                            child: const Text('Abmelden'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final status = statusSnapshot.data ?? {
                'exists': false,
                'isApproved': false,
                'isProfileComplete': false,
              };

              // Profil unvollständig
              if (!status['exists'] || !status['isProfileComplete']) {
                return const ProfileCompletionScreen();
              }

              // Warten auf Admin-Freigabe
              // Sobald Admin freigibt, feuert watchUserStatus erneut
              // → dieser StreamBuilder baut automatisch HomeScreen
              if (!status['isApproved']) {
                return const PendingApprovalScreen();
              }

              // Alles OK
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
