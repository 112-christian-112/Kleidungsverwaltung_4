// screens/home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/navigation_drawer.dart';
import '../widgets/recent_activities_widget.dart';
import '../services/auth_service.dart';
import '../services/equipment_service.dart';
import '../services/permission_service.dart';
import '../services/mission_service.dart';
import '../models/equipment_model.dart';
import '../models/mission_model.dart';
import 'dashboard/dashboard_tiles_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();
  final MissionService _missionService = MissionService();

  String _userName = '';
  String _userFireStation = '';
  String _userRole = '';
  bool _isAdmin = false;
  bool _isLoading = true;

  // Statistikwerte
  int _overdueCount = 0;
  int _cleaningCount = 0;
  int _repairCount = 0;
  int _totalEquipment = 0;
  int _recentMissionsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Benutzerdaten laden
        var userData = await _authService.checkUserStatus(user.uid);
        final isAdmin = await _permissionService.isAdmin();
        final userFireStation = await _permissionService.getUserFireStation();

        // Benutzerrolle aus Firestore abrufen
        var userDoc = await FirebaseFirestore.instance.collection('users').doc(
            user.uid).get();
        String role = userDoc.exists ? (userDoc.data()?['role'] ?? '') : '';
        String name = userDoc.exists ? (userDoc.data()?['name'] ?? '') : '';

        // Statistikdaten laden
        await _loadStatistics(isAdmin, userFireStation);

        setState(() {
          _userName = name;
          _userRole = role;
          _isAdmin = isAdmin;
          _userFireStation = userFireStation;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Benutzerdaten: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStatistics(bool isAdmin, String fireStation) async {
    try {
      final now = DateTime.now();
      final oneMonthAgo = DateTime(now.year, now.month - 1, now.day);

      // Ausrüstungsdaten laden
      Stream<List<EquipmentModel>> equipmentStream = isAdmin
          ? _equipmentService.getAllEquipment()
          : _equipmentService.getEquipmentByFireStation(fireStation);

      final equipment = await equipmentStream.first;

      // Einsatzdaten laden
      Stream<List<MissionModel>> missionsStream = isAdmin
          ? _missionService.getAllMissions()
          : _missionService.getMissionsByFireStation(fireStation);

      final missions = await missionsStream.first;

      // Aktuelle Einsätze der letzten 30 Tage zählen
      final recentMissions = missions.where((mission) =>
          mission.startTime.isAfter(oneMonthAgo)
      ).toList();

      int overdue = 0;
      int cleaning = 0;
      int repair = 0;

      for (var item in equipment) {
        // Überfällige Prüfungen zählen
        if (item.checkDate.isBefore(now)) {
          overdue++;
        }

        // Nach Status zählen
        if (item.status == EquipmentStatus.cleaning) {
          cleaning++;
        } else if (item.status == EquipmentStatus.repair) {
          repair++;
        }
      }

      setState(() {
        _overdueCount = overdue;
        _cleaningCount = cleaning;
        _repairCount = repair;
        _totalEquipment = equipment.length;
        _recentMissionsCount = recentMissions.length;
      });
    } catch (e) {
      print('Fehler beim Laden der Statistikdaten: $e');
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatzkleidung'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              // Benachrichtigungen anzeigen
            },
            tooltip: 'Benachrichtigungen',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Abmelden',
          ),
        ],
      ),
      drawer: const AppNavigationDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Begrüßungskarte mit verbessertem Design
              _buildWelcomeCard(),

              const SizedBox(height: 24),

              // Statistik-Karten in horizontalem Scroll
              _buildStatisticsCarousel(),

              const SizedBox(height: 24),

              // Hauptaktionen als Grid
              _buildActionGrid(),

              const SizedBox(height: 24),

              // Kürzliche Aktivitäten - ersetzt durch das neue Widget
              _buildRecentActivitiesSection(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    // Aktuelle Tageszeit ermitteln
    final hour = DateTime
        .now()
        .hour;
    String greeting;

    if (hour < 12) {
      greeting = 'Guten Morgen';
    } else if (hour < 18) {
      greeting = 'Guten Tag';
    } else {
      greeting = 'Guten Abend';
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme
                  .of(context)
                  .colorScheme
                  .primary,
              Theme
                  .of(context)
                  .colorScheme
                  .primary
                  .withOpacity(0.7),
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting,',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_city,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Feuerwehr $_userFireStation',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(
                        DateTime.now()),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white.withOpacity(0.9),
              child: Text(
                _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Theme
                      .of(context)
                      .colorScheme
                      .primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Statistik & Übersicht',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/equipment-status');
              },
              child: const Text('Mehr anzeigen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Noch größere Höhe für den Container
        SizedBox(
          height: 180, // Erhöhte Höhe für Statistikkarten
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildSimpleStatCard(
                title: 'Überfällige\nPrüfungen',
                // Zeilenumbruch für lange Wörter
                value: _overdueCount.toString(),
                icon: Icons.warning,
                iconColor: Colors.red,
                onTap: () =>
                    Navigator.pushNamed(context, '/overdue-inspections'),
              ),
              _buildSimpleStatCard(
                title: 'Ausrüstungsteile',
                value: _totalEquipment.toString(),
                icon: Icons.inventory_2,
                iconColor: Theme
                    .of(context)
                    .colorScheme
                    .primary,
                onTap: () => Navigator.pushNamed(context, '/admin-equipment'),
              ),
              _buildSimpleStatCard(
                title: 'In Reinigung',
                value: _cleaningCount.toString(),
                icon: Icons.local_laundry_service,
                iconColor: Colors.blue,
                onTap: () {
                  // Filter für Reinigung setzen
                },
              ),
              _buildSimpleStatCard(
                title: 'In Reparatur',
                value: _repairCount.toString(),
                icon: Icons.build,
                iconColor: Colors.orange,
                onTap: () {
                  // Filter für Reparatur setzen
                },
              ),
              _buildSimpleStatCard(
                title: 'Einsätze\n(30 Tage)',
                // Zeilenumbruch für besseres Layout
                value: _recentMissionsCount.toString(),
                icon: Icons.local_fire_department,
                iconColor: Colors.deepOrange,
                onTap: () => Navigator.pushNamed(context, '/missions'),
              ),
            ],
          ),
        ),
      ],
    );
  }

// Stark vereinfachtes und robusteres Stat-Card-Design
  Widget _buildSimpleStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 140, // Schmalere Karten
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // Wichtig für korrekte Größenanpassung
              children: [
                Icon(
                  icon,
                  color: iconColor,
                  size: 28,
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme
                        .of(context)
                        .colorScheme
                        .secondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Schnellzugriff',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        // Anstatt GridView ein flexibleres Layout verwenden
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildSimpleActionButton(
                    title: 'Ausrüstung\nscannen', // Zeilenumbruch
                    icon: Icons.qr_code_scanner,
                    color: Colors.purple,
                    onTap: () =>
                        Navigator.pushNamed(context, '/equipment-scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSimpleActionButton(
                    title: 'Einsatz\nerstellen', // Zeilenumbruch
                    icon: Icons.local_fire_department,
                    color: Colors.red,
                    onTap: () => Navigator.pushNamed(context, '/add-mission'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSimpleActionButton(
                    title: 'Ausrüstungs-\nliste',
                    // Zeilenumbruch mit Bindestrich
                    icon: Icons.list,
                    color: Colors.green,
                    onTap: () =>
                        Navigator.pushNamed(context, '/admin-equipment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSimpleActionButton(
                    title: 'Dashboard',
                    icon: Icons.dashboard,
                    color: Colors.blue,
                    onTap: () => Navigator.pushNamed(context, '/dashboard'),
                  ),
                ),

              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSimpleActionButton(
                    title: 'Überfällige-\nPrüfungen',
                    // Zeilenumbruch mit Bindestrich
                    icon: Icons.list,
                    color: Colors.green,
                    onTap: () =>
                        Navigator.pushNamed(context, '/admin-equipment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSimpleActionButton(
                    title: 'Statusübersicht',
                    icon: Icons.dashboard,
                    color: Colors.blue,
                    onTap: () => Navigator.pushNamed(context, '/equipment-status'),
                  ),
                ),

              ],
            ),
          ],
        ),
      ],
    );
  }

// Vereinfachtes und robusteres Action-Button-Design
  Widget _buildSimpleActionButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // Wichtig für korrekte Größenanpassung
            children: [
              Icon(
                icon,
                color: color,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2, // Erlaubt Zeilenumbrüche
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivitiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Letzte Aktivitäten',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/all-activities');
              },
              child: const Text('Alle anzeigen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Das finale RecentActivitiesWidget verwenden
        const RecentActivitiesWidget(
          limit: 3,
        ),
      ],
    );
  }
}