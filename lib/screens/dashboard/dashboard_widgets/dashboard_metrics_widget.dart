// screens/dashboard/dashboard_widgets/dashboard_metrics_widget.dart
import 'package:flutter/material.dart';
import '../../../models/equipment_model.dart';
import '../../../models/user_models.dart';
import '../../../services/equipment_service.dart';
import '../../../services/permission_service.dart';

class DashboardMetricsWidget extends StatefulWidget {
  const DashboardMetricsWidget({Key? key}) : super(key: key);

  @override
  State<DashboardMetricsWidget> createState() =>
      _DashboardMetricsWidgetState();
}

class _DashboardMetricsWidgetState extends State<DashboardMetricsWidget> {
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;

  // Gesamtkennzahlen
  int _totalEquipment = 0;
  int _totalOverdue = 0;
  int _totalInCleaning = 0;
  int _totalInRepair = 0;
  double _overallAvgAge = 0.0;

  // Aufschlüsselung nach Station (nur wenn mehrere sichtbar)
  Map<String, int> _overdueCounts = {};
  Map<String, int> _cleaningCounts = {};
  Map<String, int> _repairCounts = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      _currentUser = user;

      // Einheitlich über getEquipmentByUserAccess() — kein isAdmin-Flag mehr nötig
      final equipment =
          await _equipmentService.getEquipmentByUserAccess().first;

      final now = DateTime.now();
      int overdue = 0, cleaning = 0, repair = 0;
      int totalAgeInDays = 0;
      final Map<String, int> overdueByStation = {};
      final Map<String, int> cleaningByStation = {};
      final Map<String, int> repairByStation = {};

      for (final e in equipment) {
        final station = e.fireStation;

        if (e.checkDate.isBefore(now)) {
          overdue++;
          overdueByStation[station] =
              (overdueByStation[station] ?? 0) + 1;
        }
        if (e.status == EquipmentStatus.cleaning) {
          cleaning++;
          cleaningByStation[station] =
              (cleaningByStation[station] ?? 0) + 1;
        }
        if (e.status == EquipmentStatus.repair) {
          repair++;
          repairByStation[station] =
              (repairByStation[station] ?? 0) + 1;
        }

        totalAgeInDays += now.difference(e.createdAt).inDays;
      }

      if (mounted) {
        setState(() {
          _totalEquipment = equipment.length;
          _totalOverdue = overdue;
          _totalInCleaning = cleaning;
          _totalInRepair = repair;
          _overallAvgAge = equipment.isNotEmpty
              ? totalAgeInDays / equipment.length / 365.25
              : 0.0;
          _overdueCounts = overdueByStation;
          _cleaningCounts = cleaningByStation;
          _repairCounts = repairByStation;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Dashboard-Daten: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _showStationBreakdown {
    final user = _currentUser;
    if (user == null) return false;
    return user.isAdmin ||
        user.permissions.visibleFireStations.contains('*') ||
        user.permissions.visibleFireStations.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Gesamtübersicht ────────────────────────────────────────────────
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Übersicht',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricTile(
                      icon: Icons.inventory_2,
                      iconColor: Theme.of(context).colorScheme.primary,
                      value: '$_totalEquipment',
                      label: 'Gesamt',
                    ),
                    _metricTile(
                      icon: Icons.warning,
                      iconColor: Colors.red,
                      value: '$_totalOverdue',
                      label: 'Überfällig',
                    ),
                    _metricTile(
                      icon: Icons.local_laundry_service,
                      iconColor: Colors.blue,
                      value: '$_totalInCleaning',
                      label: 'Reinigung',
                    ),
                    _metricTile(
                      icon: Icons.build,
                      iconColor: Colors.orange,
                      value: '$_totalInRepair',
                      label: 'Reparatur',
                    ),
                    _metricTile(
                      icon: Icons.access_time,
                      iconColor: Colors.green,
                      value: '${_overallAvgAge.toStringAsFixed(1)} J',
                      label: 'Ø Alter',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── Aufschlüsselung nach Station (nur wenn sinnvoll) ───────────────
        if (_showStationBreakdown && _overdueCounts.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Kennzahlen nach Ortswehr',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Row(
                    children: const [
                      Expanded(
                          child: Text('Ortswehr',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold))),
                      SizedBox(
                          width: 60,
                          child: Center(
                              child: Icon(Icons.warning,
                                  color: Colors.red, size: 18))),
                      SizedBox(
                          width: 60,
                          child: Center(
                              child: Icon(Icons.local_laundry_service,
                                  color: Colors.blue, size: 18))),
                      SizedBox(
                          width: 60,
                          child: Center(
                              child: Icon(Icons.build,
                                  color: Colors.orange, size: 18))),
                    ],
                  ),
                  const Divider(),
                  // Alle sichtbaren Stationen
                  ..._overdueCounts.keys
                      .toList()
                      .map((station) => Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(station)),
                                SizedBox(
                                    width: 60,
                                    child: Center(
                                        child: Text(
                                            '${_overdueCounts[station] ?? 0}',
                                            style: TextStyle(
                                                color: (_overdueCounts[
                                                            station] ??
                                                        0) >
                                                    0
                                                    ? Colors.red
                                                    : null,
                                                fontWeight:
                                                    FontWeight.bold)))),
                                SizedBox(
                                    width: 60,
                                    child: Center(
                                        child: Text(
                                            '${_cleaningCounts[station] ?? 0}',
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.bold)))),
                                SizedBox(
                                    width: 60,
                                    child: Center(
                                        child: Text(
                                            '${_repairCounts[station] ?? 0}',
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.bold)))),
                              ],
                            ),
                          )),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricTile({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: iconColor.withOpacity(0.2),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.secondary),
            textAlign: TextAlign.center),
      ],
    );
  }
}
