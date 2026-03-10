// screens/dashboard/dashboard_widgets/dashboard_metrics_widget.dart
import 'package:flutter/material.dart';
import '../../../models/equipment_model.dart';
import '../../../models/user_models.dart';
import '../../../services/equipment_service.dart';
import '../../../services/permission_service.dart';

class DashboardMetricsWidget extends StatefulWidget {
  const DashboardMetricsWidget({Key? key}) : super(key: key);

  @override
  State<DashboardMetricsWidget> createState() => _DashboardMetricsWidgetState();
}

class _DashboardMetricsWidgetState extends State<DashboardMetricsWidget> {
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;

  int _totalEquipment = 0;
  int _totalOverdue   = 0;
  int _totalCleaning  = 0;
  int _totalRepair    = 0;
  int _totalReady     = 0;
  double _overallAvgAge = 0.0;

  Map<String, int> _overdueCounts  = {};
  Map<String, int> _cleaningCounts = {};
  Map<String, int> _repairCounts   = {};

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

      final equipment = await _equipmentService.getEquipmentByUserAccess().first;
      final now = DateTime.now();
      int overdue = 0, cleaning = 0, repair = 0, ready = 0, totalAgeInDays = 0;
      final Map<String, int> overdueByStation  = {};
      final Map<String, int> cleaningByStation = {};
      final Map<String, int> repairByStation   = {};

      for (final e in equipment) {
        final st = e.fireStation;
        if (e.checkDate.isBefore(now)) {
          overdue++;
          overdueByStation[st] = (overdueByStation[st] ?? 0) + 1;
        }
        if (e.status == EquipmentStatus.cleaning) {
          cleaning++;
          cleaningByStation[st] = (cleaningByStation[st] ?? 0) + 1;
        }
        if (e.status == EquipmentStatus.repair) {
          repair++;
          repairByStation[st] = (repairByStation[st] ?? 0) + 1;
        }
        if (e.status == EquipmentStatus.ready) ready++;
        totalAgeInDays += now.difference(e.createdAt).inDays;
      }

      if (mounted) {
        setState(() {
          _totalEquipment = equipment.length;
          _totalOverdue   = overdue;
          _totalCleaning  = cleaning;
          _totalRepair    = repair;
          _totalReady     = ready;
          _overallAvgAge  = equipment.isNotEmpty
              ? totalAgeInDays / equipment.length / 365.25 : 0.0;
          _overdueCounts  = overdueByStation;
          _cleaningCounts = cleaningByStation;
          _repairCounts   = repairByStation;
          _isLoading      = false;
        });
      }
    } catch (e) {
      assert(() { debugPrint('DashboardMetrics: $e'); return true; }());
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _showStationBreakdown {
    final u = _currentUser;
    if (u == null) return false;
    return u.isAdmin ||
        u.permissions.visibleFireStations.contains('*') ||
        u.permissions.visibleFireStations.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 130,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final cs    = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Erste Reihe ──────────────────────────────────────────────────
        Row(
          children: [
            _statCard(context, 'Gesamt', '$_totalEquipment',
                Icons.inventory_2_outlined, cs.primary),
            const SizedBox(width: 10),
            _statCard(context, 'Einsatzbereit', '$_totalReady',
                Icons.check_circle_outline, Colors.green),
            const SizedBox(width: 10),
            _statCard(context, 'Überfällig', '$_totalOverdue',
                Icons.warning_amber_rounded,
                _totalOverdue > 0 ? cs.error : cs.onSurfaceVariant,
                highlight: _totalOverdue > 0),
            const SizedBox(width: 10),
            _statCard(context, 'Reinigung', '$_totalCleaning',
                Icons.local_laundry_service,
                _totalCleaning > 0 ? Colors.blue : cs.onSurfaceVariant),
          ],
        ),

        // ── Zweite Reihe: nur wenn Daten vorhanden ───────────────────────
        if (_totalRepair > 0 || _overallAvgAge > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _statCard(context, 'Reparatur', '$_totalRepair',
                  Icons.build_outlined,
                  _totalRepair > 0 ? Colors.orange : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              _statCard(context, 'Ø Alter (J)',
                  _overallAvgAge.toStringAsFixed(1),
                  Icons.access_time_outlined, cs.secondary),
              const SizedBox(width: 10),
              Expanded(child: SizedBox()),
              const SizedBox(width: 10),
              Expanded(child: SizedBox()),
            ],
          ),
        ],

        // ── Stationsaufschlüsselung ───────────────────────────────────────
        if (_showStationBreakdown && _overdueCounts.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Kennzahlen nach Ortswehr',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: isDark ? 0 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isDark
                  ? BorderSide(color: cs.outlineVariant)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Ortswehr',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: cs.onSurface)),
                      ),
                      _colHeader(Icons.warning_amber_rounded, cs.error),
                      _colHeader(Icons.local_laundry_service, Colors.blue),
                      _colHeader(Icons.build_outlined, Colors.orange),
                    ],
                  ),
                  Divider(height: 16, color: cs.outlineVariant),
                  ..._overdueCounts.keys.map((station) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(station,
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurface),
                              overflow: TextOverflow.ellipsis),
                        ),
                        _colCell('${_overdueCounts[station] ?? 0}',
                            (_overdueCounts[station] ?? 0) > 0
                                ? cs.error : cs.onSurfaceVariant,
                            bold: (_overdueCounts[station] ?? 0) > 0),
                        _colCell('${_cleaningCounts[station] ?? 0}',
                            cs.onSurfaceVariant),
                        _colCell('${_repairCounts[station] ?? 0}',
                            cs.onSurfaceVariant),
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

  Widget _statCard(BuildContext context, String label, String value,
      IconData icon, Color color, {bool highlight = false}) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Card(
        elevation: isDark ? 0 : (highlight ? 2 : 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: highlight
              ? BorderSide(color: color.withOpacity(0.4), width: 1.5)
              : (isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: highlight ? color : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colHeader(IconData icon, Color color) => SizedBox(
        width: 52,
        child: Center(child: Icon(icon, size: 16, color: color)),
      );

  Widget _colCell(String value, Color color, {bool bold = false}) => SizedBox(
        width: 52,
        child: Center(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: color)),
        ),
      );
}
