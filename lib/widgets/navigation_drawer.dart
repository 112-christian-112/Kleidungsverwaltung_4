// widgets/navigation_drawer.dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/admin/debug_permissions_screen.dart';
import '../screens/admin/equipment/upcoming_inspections_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/export_screen.dart';
import '../services/auth_service.dart';
import '../services/permission_service.dart';
import '../screens/admin/equipment/equipment_list_screen.dart';

class AppNavigationDrawer extends StatefulWidget {
  const AppNavigationDrawer({Key? key}) : super(key: key);

  @override
  State<AppNavigationDrawer> createState() => _AppNavigationDrawerState();
}

class _AppNavigationDrawerState extends State<AppNavigationDrawer> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PermissionService _permissionService = PermissionService();

  String _userName = '';
  String _userRole = '';
  String _userFireStation = '';
  bool _isAdmin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final isAdmin = await _permissionService.isAdmin();

          setState(() {
            _userName = userData['name'] ?? '';
            _userRole = userData['role'] ?? '';
            _userFireStation = userData['fireStation'] ?? '';
            _isAdmin = isAdmin;
          });
        }
      }
    } catch (e) {
      // Fehler beim Laden der Benutzerdaten — Drawer zeigt trotzdem Basis-Menü
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = _auth.currentUser;
    final String userEmail = currentUser?.email ?? 'Nicht angemeldet';
    final String userInitial = _userName.isNotEmpty
        ? _userName[0].toUpperCase()
        : (userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'U');

    return Drawer(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                // ── Header ──────────────────────────────────────────────────
                UserAccountsDrawerHeader(
                  accountName: Text(_userName.isNotEmpty ? _userName : '—'),
                  accountEmail: Text(userEmail),
                  currentAccountPicture: CircleAvatar(
                    child: Text(
                      userInitial,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),

                // ── Navigation ───────────────────────────────────────────────
                ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text('Startseite'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/home');
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.dashboard),
                  title: const Text('Dashboard'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const DashboardScreen()),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.checkroom),
                  title: const Text('Einsatzkleidung'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const EquipmentListScreen()),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.assignment),
                  title: const Text('Einsätze'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/missions');
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Anstehende Prüfungen'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const UpcomingInspectionsScreen()),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.file_download),
                  title: const Text('Export'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ExportScreen()),
                    );
                  },
                ),

                // ── Admin-Bereich ────────────────────────────────────────────
                if (_isAdmin) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: const [
                        Icon(Icons.admin_panel_settings,
                            size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Administration',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.people, color: Colors.orange),
                    title: const Text('Benutzer-Verwaltung'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/admin-users');
                    },
                  ),

                  // FIX: Debug-Screen nur in Debug-Builds sichtbar
                  if (kDebugMode)
                    ListTile(
                      leading: const Icon(Icons.bug_report, color: Colors.red),
                      title: const Text('Debug: Berechtigungen'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const DebugPermissionsScreen()),
                        );
                      },
                    ),
                ],

                // ── Debug-Info-Sektion (nur in Debug-Builds) ─────────────────
                if (kDebugMode && _isAdmin) ...[
                  const Divider(),
                  ExpansionTile(
                    leading: const Icon(Icons.bug_report, size: 20),
                    title: const Text(
                      'Debug-Info',
                      style: TextStyle(fontSize: 14),
                    ),
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Name: $_userName',
                                style: const TextStyle(fontSize: 12)),
                            Text('Rolle: $_userRole',
                                style: const TextStyle(fontSize: 12)),
                            Text('Feuerwehr: $_userFireStation',
                                style: const TextStyle(fontSize: 12)),
                            Text('Admin: $_isAdmin',
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _loadUserData,
                              child: const Text('Daten neu laden'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                const Divider(),

                // ── Einstellungen & Sonstiges ────────────────────────────────
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Einstellungen'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/settings');
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('Über'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/about');
                  },
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Abmelden'),
                  onTap: () async {
                    Navigator.pop(context);
                    await AuthService().signOut();
                    // StreamBuilder übernimmt automatisch → LoginScreen
                  },
                ),
              ],
            ),
    );
  }
}
