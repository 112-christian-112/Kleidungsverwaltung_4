// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Lists/fire_stations.dart';
import '../models/equipment_model.dart';
import '../models/mission_model.dart';
import '../models/user_models.dart';
import '../services/auth_service.dart';
import '../services/equipment_service.dart';
import '../services/mission_service.dart';
import '../services/permission_service.dart';
import '../widgets/navigation_drawer.dart';
import '../widgets/recent_activities_widget.dart';
import 'admin/equipment/equipment_scan_screen.dart';
import 'admin/equipment/equipment_list_screen.dart';
import 'admin/equipment/equipment_status_screen.dart';
import 'admin/equipment/upcoming_inspections_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'missions/add_missions_screen.dart';
import 'missions/mission_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final EquipmentService _equipmentService = EquipmentService();
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  // Einmal laden — Quelle der Wahrheit
  UserModel? _currentUser;
  bool _isLoading = true;

  // Statistiken
  int _overdueCount = 0;
  int _cleaningCount = 0;
  int _repairCount = 0;
  int _totalEquipment = 0;
  int _recentMissionsCount = 0;

  // Berechtigungen aus UserModel
  bool get _canAddMission =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.missionAdd == true;
  bool get _canEditEquipment =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentEdit == true;
  bool get _canViewDashboard => _currentUser?.isAdmin == true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (mounted) {
        setState(() => _currentUser = user);
        await _loadStatistics(user);
      }
    } catch (e) {
      print('HomeScreen._loadAll: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStatistics(UserModel? user) async {
    if (user == null) return;
    try {
      final now = DateTime.now();
      final oneMonthAgo = DateTime(now.year, now.month - 1, now.day);

      // Ausrüstung laden
      final equipment =
          await _equipmentService.getEquipmentByUserAccess().first;

      // Einsätze laden
      final missions =
          await _missionService.getMissionsForCurrentUser(user).first;

      int overdue = 0, cleaning = 0, repair = 0;
      for (final e in equipment) {
        if (e.checkDate.isBefore(now)) overdue++;
        if (e.status == EquipmentStatus.cleaning) cleaning++;
        if (e.status == EquipmentStatus.repair) repair++;
      }

      final recentMissions =
          missions.where((m) => m.startTime.isAfter(oneMonthAgo)).length;

      if (mounted) {
        setState(() {
          _overdueCount = overdue;
          _cleaningCount = cleaning;
          _repairCount = repair;
          _totalEquipment = equipment.length;
          _recentMissionsCount = recentMissions;
        });
      }
    } catch (e) {
      print('HomeScreen._loadStatistics: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatzkleidung'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _authService.signOut,
            tooltip: 'Abmelden',
          ),
        ],
      ),
      drawer: const AppNavigationDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Begrüßungs-Header ──────────────────────────────────
                    _buildHeader(),

                    const SizedBox(height: 16),

                    // ── NFC-Scan — prominent in der Mitte ─────────────────
                    _buildNfcHero(),

                    const SizedBox(height: 20),

                    // ── Statistiken ────────────────────────────────────────
                    _buildSectionTitle('Übersicht', onMore: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const EquipmentStatusScreen()));
                    }),
                    _buildStatisticsRow(),

                    const SizedBox(height: 20),

                    // ── Schnellzugriff ─────────────────────────────────────
                    _buildSectionTitle('Schnellzugriff'),
                    _buildQuickActions(),

                    const SizedBox(height: 20),

                    // ── Aktivitäten ────────────────────────────────────────
                    _buildSectionTitle('Letzte Aktivitäten', onMore: () {
                      Navigator.pushNamed(context, '/all-activities');
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: RecentActivitiesWidget(limit: 3),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Guten Morgen'
        : hour < 18
            ? 'Guten Tag'
            : 'Guten Abend';

    final name = _currentUser?.name ?? '';
    final station = _currentUser?.fireStation ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.75),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white.withOpacity(0.9),
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Begrüßung
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting,',
                  style: const TextStyle(
                      fontSize: 14, color: Colors.white70),
                ),
                Text(
                  name.isNotEmpty ? name : 'Willkommen',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (station.isNotEmpty)
                  Row(
                    children: [
                      Icon(FireStations.getIcon(station),
                          size: 13, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text(
                        station,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Datum
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DateFormat('EEE', 'de_DE').format(DateTime.now()),
                style: const TextStyle(
                    fontSize: 12, color: Colors.white60),
              ),
              Text(
                DateFormat('dd. MMM', 'de_DE').format(DateTime.now()),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── NFC Hero ──────────────────────────────────────────────────────────────

  Widget _buildNfcHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EquipmentScanScreen()),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.indigo.shade700,
                Colors.indigo.shade500,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // Animiertes NFC-Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.nfc, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 20),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kleidung scannen',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NFC-Tag oder Barcode einer Einsatzkleidung scannen',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // Pfeil
              Icon(Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.7), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Statistiken ───────────────────────────────────────────────────────────

  Widget _buildStatisticsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              label: 'Gesamt',
              value: _totalEquipment,
              icon: Icons.inventory_2_outlined,
              color: Theme.of(context).colorScheme.primary,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EquipmentListScreen())),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              label: 'Überfällig',
              value: _overdueCount,
              icon: Icons.warning_amber_rounded,
              color: _overdueCount > 0 ? Colors.red : Colors.grey,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const UpcomingInspectionsScreen())),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              label: 'Reinigung',
              value: _cleaningCount,
              icon: Icons.local_laundry_service,
              color: _cleaningCount > 0 ? Colors.blue : Colors.grey,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EquipmentStatusScreen())),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              label: 'Einsätze',
              value: _recentMissionsCount,
              icon: Icons.local_fire_department,
              color: Colors.deepOrange,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MissionListScreen())),
              subtitle: '30 Tage',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: value > 0 && (label == 'Überfällig')
                      ? Colors.red
                      : color,
                ),
              ),
              Text(
                label,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey[400]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Schnellzugriff ────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    // Aktionen dynamisch nach Berechtigungen aufbauen
    final actions = <_QuickAction>[
      _QuickAction(
        label: 'Einsatzliste',
        icon: Icons.local_fire_department,
        color: Colors.red,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MissionListScreen())),
      ),
      _QuickAction(
        label: 'Ausrüstung',
        icon: Icons.inventory_2,
        color: Colors.green,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EquipmentListScreen())),
      ),
      _QuickAction(
        label: 'Statusübersicht',
        icon: Icons.bar_chart,
        color: Colors.blue,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EquipmentStatusScreen())),
      ),
      _QuickAction(
        label: 'Prüfungen',
        icon: Icons.fact_check_outlined,
        color: Colors.orange,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => const UpcomingInspectionsScreen())),
      ),
      if (_canAddMission)
        _QuickAction(
          label: 'Einsatz\nerfassen',
          icon: Icons.add_circle_outline,
          color: Colors.red.shade700,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddMissionScreen())),
        ),
      if (_canViewDashboard)
        _QuickAction(
          label: 'Dashboard',
          icon: Icons.dashboard,
          color: Colors.purple,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.0,
        ),
        itemCount: actions.length,
        itemBuilder: (_, i) => _buildActionTile(actions[i]),
      ),
    );
  }

  Widget _buildActionTile(_QuickAction action) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: action.color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(action.icon, color: action.color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hilfsmethode ─────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, {VoidCallback? onMore}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Mehr', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ── Daten-Klasse für Quick Actions ────────────────────────────────────────────

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});
}
