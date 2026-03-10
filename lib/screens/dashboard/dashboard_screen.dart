// screens/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../Lists/fire_stations.dart';
import '../../models/equipment_model.dart';
import '../../models/mission_model.dart';
import '../../models/user_models.dart';
import '../../services/equipment_service.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';
import '../admin/equipment/equipment_detail_screen.dart';
import '../admin/equipment/equipment_inspection_form_screen.dart';
import '../admin/equipment/equipment_list_screen.dart';
import '../admin/equipment/equipment_status_screen.dart';
import '../admin/equipment/upcoming_inspections_screen.dart';
import '../missions/mission_detail_screen.dart';
import 'dashboard_widgets/inspection_calender_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final PermissionService _permissionService = PermissionService();
  final EquipmentService  _equipmentService  = EquipmentService();
  final MissionService    _missionService    = MissionService();

  UserModel? _currentUser;
  bool _isLoading = true;

  // Rohdaten
  List<EquipmentModel>  _allEquipment = [];
  List<MissionModel>    _allMissions  = [];

  // Kennzahlen
  int _totalEquipment = 0;
  int _totalReady     = 0;
  int _totalOverdue   = 0;
  int _totalCleaning  = 0;
  int _totalRepair    = 0;

  // Stationsaufschlüsselung
  Map<String, Map<String, int>> _stationStats = {};

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Daten laden ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (!mounted) return;
      setState(() => _currentUser = user);

      // Missions immer laden wenn equipmentView — wird als Kontext für
      // "Kleidung noch im Einsatz" benötigt, unabhängig von missionView.
      final canLoadMissions = user?.isAdmin == true ||
          user?.permissions.equipmentView == true ||
          user?.permissions.missionView == true;

      final futures = <Future>[
        _equipmentService.getEquipmentByUserAccess().first,
        if (canLoadMissions)
          _missionService.getMissionsForCurrentUser(user).first,
      ];
      final results = await Future.wait(futures);

      if (!mounted) return;

      final equipment = results[0] as List<EquipmentModel>;
      final missions  = canLoadMissions
          ? results[1] as List<MissionModel>
          : <MissionModel>[];
      final now = DateTime.now();

      int total = equipment.length, ready = 0, overdue = 0, cleaning = 0, repair = 0;
      final Map<String, Map<String, int>> byStation = {};

      for (final e in equipment) {
        final st = e.fireStation;
        byStation.putIfAbsent(st, () =>
            {'total': 0, 'overdue': 0, 'cleaning': 0, 'repair': 0});
        byStation[st]!['total'] = byStation[st]!['total']! + 1;

        if (e.status == EquipmentStatus.ready) ready++;
        if (e.checkDate.isBefore(now)) {
          overdue++;
          byStation[st]!['overdue'] = byStation[st]!['overdue']! + 1;
        }
        if (e.status == EquipmentStatus.cleaning) {
          cleaning++;
          byStation[st]!['cleaning'] = byStation[st]!['cleaning']! + 1;
        }
        if (e.status == EquipmentStatus.repair) {
          repair++;
          byStation[st]!['repair'] = byStation[st]!['repair']! + 1;
        }
      }


      setState(() {
        _allEquipment   = equipment;
        _allMissions    = missions;
        _totalEquipment = total;
        _totalReady     = ready;
        _totalOverdue   = overdue;
        _totalCleaning  = cleaning;
        _totalRepair    = repair;
        _stationStats   = byStation;
        _isLoading      = false;
      });
    } catch (e) {
      assert(() { debugPrint('DashboardScreen._loadData: $e'); return true; }());
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get _showStationBreakdown {
    final u = _currentUser;
    if (u == null) return false;
    return u.isAdmin ||
        u.permissions.visibleFireStations.contains('*') ||
        u.permissions.visibleFireStations.length > 1;
  }

  /// Einsätze bei denen noch mind. 1 Artikel nicht auf "ready" ist
  List<MissionModel> get _openMissions {
    final nonReadyIds = _allEquipment
        .where((e) => e.status != EquipmentStatus.ready)
        .map((e) => e.id)
        .toSet();
    return _allMissions
        .where((m) => m.equipmentIds.any((id) => nonReadyIds.contains(id)))
        .toList();
  }

  List<EquipmentModel> get _overdueList =>
      _allEquipment.where((e) => e.checkDate.isBefore(DateTime.now())).toList()
        ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

  List<EquipmentModel> get _upcomingList {
    final now  = DateTime.now();
    final soon = now.add(const Duration(days: 30));
    return _allEquipment
        .where((e) => e.checkDate.isAfter(now) && e.checkDate.isBefore(soon))
        .toList()
      ..sort((a, b) => a.checkDate.compareTo(b.checkDate));
  }

  bool get _canEquipment =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentView == true;

  bool get _canMissions =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.missionView == true;

  bool get _canInspection =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.inspectionView == true ||
      _currentUser?.permissions.inspectionPerform == true;

  bool get _canCleaning =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.cleaningView == true ||
      _currentUser?.permissions.cleaningCreate == true;

  bool get _allClear {
    // Nur true wenn der User mindestens eine relevante Berechtigung hat
    // UND in all seinen sichtbaren Bereichen nichts offen ist.
    if (!_canEquipment && !_canMissions) return false;
    final equipmentOk = !_canEquipment ||
        (_totalOverdue == 0 && _totalCleaning == 0 && _totalRepair == 0);
    // Offene Einsätze sind relevant wenn equipmentView oder missionView
    final canSeeMissions = _canEquipment || _canMissions;
    final missionsOk = !canSeeMissions || _openMissions.isEmpty;
    return equipmentOk && missionsOk;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Übersicht'),
                if (!_isLoading && _totalOverdue > 0) ...[
                  const SizedBox(width: 6),
                  _badge(_totalOverdue),
                ],
              ]),
            ),
            const Tab(text: 'Kalender'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildCalendarTab(),
              ],
            ),
    );
  }

  // ── Tab 1: Übersicht ───────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    final noRights = _currentUser != null &&
        !_currentUser!.isAdmin &&
        !_currentUser!.permissions.equipmentView &&
        !_currentUser!.permissions.inspectionView &&
        !_currentUser!.permissions.inspectionPerform &&
        !_currentUser!.permissions.missionView &&
        !_currentUser!.permissions.cleaningView;
    if (noRights) return _buildNoRights();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // ── Kennzahlen (nur mit equipmentView) ─────────────────────
          if (_canEquipment) ...[
            _buildKennzahlenRow(),
            const SizedBox(height: 20),
          ],

          // ── Alles-in-Ordnung oder Warnungs-Sektionen ───────────────
          if (_allClear) ...[
            _buildAllClearCard(),
            const SizedBox(height: 20),
          ] else ...[
            // ── Warnungen (equipmentView oder inspectionView) ──────────
            if ((_canEquipment || _canInspection) &&
                (_totalOverdue > 0 || _upcomingList.isNotEmpty)) ...[
              _buildSectionTitle('Warnungen',
                  onMore: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const UpcomingInspectionsScreen()))),
              _buildWarningsSection(),
              const SizedBox(height: 20),
            ],

            // ── Kleidung im Einsatz (equipmentView reicht) ───────────
            if ((_canEquipment || _canMissions) && _openMissions.isNotEmpty) ...[
              _buildSectionTitle('Kleidung noch im Einsatz',
                  badge: _openMissions.length),
              _buildOpenMissionsSection(),
              const SizedBox(height: 20),
            ],

            // ── Nicht einsatzbereit (equipmentView oder cleaningView) ───
            if ((_canEquipment || _canCleaning) &&
                (_totalCleaning > 0 || _totalRepair > 0)) ...[
              _buildSectionTitle('Nicht einsatzbereit',
                  onMore: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const EquipmentStatusScreen()))),
              _buildNotReadyList(),
              const SizedBox(height: 20),
            ],
          ],

          // ── Stationstabelle (Admin/Multi-Station) ───────────────────
          if (_showStationBreakdown) ...[
            _buildSectionTitle('Kennzahlen nach Ortswehr',
                onMore: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const EquipmentStatusScreen()))),
            _buildStationTable(),
          ],
        ],
      ),
    );
  }

  // ── Tab 2: Kalender ────────────────────────────────────────────────────────

  Widget _buildCalendarTab() {
    if (!_canInspection) {
      return _buildNoRights();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        InspectionCalendarWidget(
          isAdmin: _currentUser?.isAdmin ?? false,
          userFireStation: _currentUser?.fireStation ?? '',
        ),
      ],
    );
  }

  // ── Kennzahlen-Kacheln ─────────────────────────────────────────────────────

  Widget _buildKennzahlenRow() {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Row(children: [
        _statTile('$_totalEquipment', 'Gesamt',
            Icons.inventory_2_outlined, cs.primary,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const EquipmentListScreen()))),
        const SizedBox(width: 10),
        _statTile('$_totalReady', 'Einsatzbereit',
            Icons.check_circle_outline, Colors.green),
        const SizedBox(width: 10),
        _statTile('$_totalOverdue', 'Überfällig',
            Icons.warning_amber_rounded,
            _totalOverdue > 0 ? cs.error : Colors.grey,
            highlight: _totalOverdue > 0,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const UpcomingInspectionsScreen()))),
        const SizedBox(width: 10),
        _statTile('$_totalCleaning', 'Reinigung',
            Icons.local_laundry_service,
            _totalCleaning > 0 ? Colors.blue : Colors.grey,
            onTap: _totalCleaning > 0 ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EquipmentStatusScreen())) : null),
      ]),
      if (_totalRepair > 0) ...[
        const SizedBox(height: 10),
        Row(children: [
          _statTile('$_totalRepair', 'Reparatur',
              Icons.build_outlined, Colors.orange,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const EquipmentStatusScreen()))),
          const SizedBox(width: 10),
          Expanded(child: const SizedBox()),
          const SizedBox(width: 10),
          Expanded(child: const SizedBox()),
          const SizedBox(width: 10),
          Expanded(child: const SizedBox()),
        ]),
      ],
    ]);
  }

  Widget _statTile(String value, String label, IconData icon, Color color,
      {bool highlight = false, VoidCallback? onTap}) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold,
            color: highlight ? color : cs.onSurface)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center, maxLines: 1,
            overflow: TextOverflow.ellipsis),
        // Tipp-Indikator wenn navigierbar
        if (onTap != null) ...[
          const SizedBox(height: 4),
          Icon(Icons.arrow_forward_ios,
              size: 9, color: cs.onSurfaceVariant.withOpacity(0.5)),
        ],
      ]),
    );

    return Expanded(
      child: Card(
        elevation: isDark ? 0 : (highlight ? 2 : 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: highlight
              ? BorderSide(color: color.withOpacity(0.4), width: 1.5)
              : isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
        ),
        child: onTap != null
            ? InkWell(onTap: onTap,
                borderRadius: BorderRadius.circular(12), child: content)
            : content,
      ),
    );
  }

  // ── Alles-in-Ordnung Card ──────────────────────────────────────────────────

  Widget _buildAllClearCard() {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: Colors.green.withOpacity(isDark ? 0.35 : 0.25), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(isDark ? 0.18 : 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_outlined,
                color: Colors.green, size: 28),
          ),
          const SizedBox(height: 14),
          Text('Alles in Ordnung',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text(
            'Keine überfälligen Prüfungen, keine offenen Einsätze\nund alle Ausrüstung einsatzbereit.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  // ── Warnungen ──────────────────────────────────────────────────────────────

  Widget _buildWarningsSection() {
    final overdue  = _overdueList;
    final upcoming = _upcomingList;

    return Column(children: [
      if (overdue.isNotEmpty)
        _warningGroup(
          title: '${overdue.length} überfällige Prüfungen',
          items: overdue,
          color: Theme.of(context).colorScheme.error,
          icon: Icons.warning_amber_rounded,
          trailingLabel: (e) => DateFormat('dd.MM.yy').format(e.checkDate),
          showQuickAction: _currentUser?.isAdmin == true ||
              _currentUser?.permissions.inspectionPerform == true,
        ),
      if (upcoming.isNotEmpty) ...[
        if (overdue.isNotEmpty) const SizedBox(height: 8),
        _warningGroup(
          title: '${upcoming.length} Prüfungen in 30 Tagen',
          items: upcoming,
          color: Colors.orange,
          icon: Icons.event_outlined,
          trailingLabel: (e) => DateFormat('dd.MM.yy').format(e.checkDate),
          showQuickAction: false,
        ),
      ],
    ]);
  }

  Widget _warningGroup({
    required String title,
    required List<EquipmentModel> items,
    required Color color,
    required IconData icon,
    required String Function(EquipmentModel) trailingLabel,
    required bool showQuickAction,
  }) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shown  = items.take(3).toList();

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(isDark ? 0.3 : 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.15 : 0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color))),
          ]),
        ),
        // Einträge
        ...shown.map((e) => _warningRow(e, color, trailingLabel(e),
            showQuickAction: showQuickAction)),
        if (items.length > 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text('+ ${items.length - 3} weitere',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          )
        else
          const SizedBox(height: 6),
      ]),
    );
  }

  Widget _warningRow(EquipmentModel e, Color color, String trailing,
      {required bool showQuickAction}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => EquipmentDetailScreen(equipment: e))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              e.type == 'Jacke'
                  ? Icons.accessibility_new
                  : Icons.airline_seat_legroom_normal,
              color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.article, style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w500, color: cs.onSurface),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(e.owner, style: TextStyle(
                  fontSize: 11, color: cs.onSurfaceVariant),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )),
          const SizedBox(width: 8),
          Text(trailing, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: color)),
          // Schnellaktion: direkt zur Prüfung
          if (showQuickAction) ...[
            const SizedBox(width: 6),
            FilledButton.tonal(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) =>
                      EquipmentInspectionFormScreen(equipment: e))),
              style: FilledButton.styleFrom(
                backgroundColor: color.withOpacity(0.12),
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(64, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Prüfen', style: TextStyle(fontSize: 12)),
            ),
          ] else ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 14, color: cs.onSurfaceVariant),
          ],
        ]),
      ),
    );
  }

  // ── Offene Einsätze ────────────────────────────────────────────────────────

  Widget _buildOpenMissionsSection() {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final missions = _openMissions;

    final nonReadyById = {
      for (final e in _allEquipment
          .where((e) => e.status != EquipmentStatus.ready))
        e.id: e,
    };

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark
            ? BorderSide(color: cs.outlineVariant)
            : BorderSide(color: Colors.deepOrange.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          decoration: BoxDecoration(
            color: Colors.deepOrange.withOpacity(isDark ? 0.15 : 0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(Icons.local_fire_department,
                color: Colors.deepOrange, size: 16),
            const SizedBox(width: 8),
            Text('Ausrüstung noch nicht zurück',
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: Colors.deepOrange)),
          ]),
        ),
        // Einsätze
        ...missions.take(3).map((mission) {
          final notBack = mission.equipmentIds
              .where((id) => nonReadyById.containsKey(id))
              .map((id) => nonReadyById[id]!)
              .toList();
          final cleaningCount = notBack
              .where((e) => e.status == EquipmentStatus.cleaning).length;
          final repairCount   = notBack
              .where((e) => e.status == EquipmentStatus.repair).length;

          final canNavToMission = _canMissions;
          return InkWell(
            onTap: canNavToMission ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) =>
                    MissionDetailScreen(missionId: mission.id))) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_fire_department,
                      color: Colors.deepOrange, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mission.name,
                        style: TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w500, color: cs.onSurface),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(children: [
                      Text(
                        DateFormat('dd.MM.yy', 'de_DE')
                            .format(mission.startTime),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                      if (cleaningCount > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.local_laundry_service,
                            size: 11, color: Colors.blue),
                        const SizedBox(width: 2),
                        Text('$cleaningCount',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.blue)),
                      ],
                      if (repairCount > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.build_outlined,
                            size: 11, color: Colors.orange),
                        const SizedBox(width: 2),
                        Text('$repairCount',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.orange)),
                      ],
                    ]),
                  ],
                )),
                Icon(Icons.chevron_right, size: 14, color: cs.onSurfaceVariant),
              ]),
            ),
          );
        }),
        if (missions.length > 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text('+ ${missions.length - 3} weitere',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          )
        else
          const SizedBox(height: 6),
      ]),
    );
  }

  // ── Nicht einsatzbereit ────────────────────────────────────────────────────

  Widget _buildNotReadyList() {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items  = _allEquipment
        .where((e) => e.status == EquipmentStatus.cleaning ||
                      e.status == EquipmentStatus.repair)
        .toList()
      ..sort((a, b) => a.status.compareTo(b.status));

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => Divider(
            height: 1, indent: 56,
            color: cs.outlineVariant.withOpacity(0.5)),
        itemBuilder: (_, i) {
          final e          = items[i];
          final isCleaning = e.status == EquipmentStatus.cleaning;
          final color      = isCleaning ? Colors.blue : Colors.orange;
          final icon       = isCleaning
              ? Icons.local_laundry_service : Icons.build_outlined;
          final isFirst = i == 0;
          final isLast  = i == items.length - 1;

          return InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => EquipmentDetailScreen(equipment: e))),
            borderRadius: BorderRadius.vertical(
              top:    isFirst ? const Radius.circular(12) : Radius.zero,
              bottom: isLast  ? const Radius.circular(12) : Radius.zero,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.article, style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w500, color: cs.onSurface),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${e.owner}  ·  ${e.status}',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                )),
                Icon(Icons.chevron_right,
                    size: 14, color: cs.onSurfaceVariant),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Stationstabelle ────────────────────────────────────────────────────────

  Widget _buildStationTable() {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sorted = _stationStats.entries.toList()
      ..sort((a, b) =>
          (b.value['overdue'] ?? 0).compareTo(a.value['overdue'] ?? 0));

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text('Ortswehr',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: cs.onSurface))),
            _th(Icons.inventory_2_outlined, cs.primary),
            _th(Icons.warning_amber_rounded, cs.error),
            _th(Icons.local_laundry_service, Colors.blue),
            _th(Icons.build_outlined, Colors.orange),
          ]),
          Divider(height: 14, color: cs.outlineVariant),
          ...sorted.map((entry) {
            final s          = entry.value;
            final hasWarning = (s['overdue'] ?? 0) > 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Row(children: [
                  Icon(FireStations.getIcon(entry.key),
                      size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(child: Text(entry.key,
                      style: TextStyle(fontSize: 12, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis)),
                ])),
                _td('${s['total']}', cs.onSurface),
                _td('${s['overdue']}',
                    hasWarning ? cs.error : cs.onSurfaceVariant,
                    bold: hasWarning),
                _td('${s['cleaning']}', cs.onSurfaceVariant),
                _td('${s['repair']}', cs.onSurfaceVariant),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _th(IconData icon, Color color) => SizedBox(
      width: 44,
      child: Center(child: Icon(icon, size: 14, color: color)));

  Widget _td(String v, Color color, {bool bold = false}) => SizedBox(
      width: 44,
      child: Center(child: Text(v, style: TextStyle(
          fontSize: 12, color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal))));

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title,
      {VoidCallback? onMore, int? badge}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
            if (badge != null) ...[
              const SizedBox(width: 8),
              _badge(badge),
            ],
          ]),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Alle anzeigen',
                  style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _badge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count', style: const TextStyle(
          color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildNoRights() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 52, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'Keine Berechtigungen zugewiesen.\nBitte wende dich an deinen Administrator.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}
