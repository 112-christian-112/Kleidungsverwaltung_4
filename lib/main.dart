// Aktualisierte main.dart
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
import 'services/firestore_service.dart';

void main() async {
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);
// Theme Service initialisieren
final themeService = ThemeService();
await themeService.initialize();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisiere die Datums-Formatierung für Deutsch
  await initializeDateFormatting('de_DE', '');

  // Optional: Setze Deutsch als Standardsprache für die App
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
title: 'Firebase App',
debugShowCheckedModeBanner: false,
theme: themeService.getLightTheme(),
darkTheme: themeService.getDarkTheme(),
themeMode: themeService.getThemeMode(),
home: StreamBuilder<User?>(
  stream: FirebaseAuth.instance.authStateChanges(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasData) {
      // Wenn der Benutzer angemeldet ist, prüfen wir seinen Status
      return FutureBuilder<Map<String, dynamic>>(
        future: AuthService().checkUserStatus(snapshot.data!.uid),
        builder: (context, statusSnapshot) {
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

          // Wenn der Benutzer nicht existiert oder das Profil nicht vollständig ist
          if (!statusSnapshot.data?['exists'] || !statusSnapshot.data?['isProfileComplete']) {
            return const ProfileCompletionScreen();
          }

          // Wenn der Benutzer nicht freigegeben ist
          if (!statusSnapshot.data?['isApproved']) {
            return const PendingApprovalScreen();
          }

          // Wenn der Benutzer existiert und freigegeben ist
          return const HomeScreen();
        },
      );
    }

    // Wenn kein Benutzer angemeldet ist
    return const LoginScreen();
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
  '/equipment-scan': (context) => const EquipmentScanScreen(), // Diese Seite müsste noch erstellt werden
  '/overdue-inspections': (context) => const UpcomingInspectionsScreen(),
  '/equipment-status': (context) => const EquipmentStatusScreen(),
  '/missions': (context) => const MissionListScreen(),
  '/add-mission': (context) => const AddMissionScreen(),
  '/privacy-policy': (context) => const PrivacyPolicyScreen(),
  '/help-support': (context) => const HelpSupportScreen(),
  '/about': (context) => const AboutScreen(), // Neue Route für die Über-Seite
  '/all-activities': (context) => const AllActivitiesScreen(),
'/dashboard': (context) => const DashboardScreen(),
  },
);
}
}
