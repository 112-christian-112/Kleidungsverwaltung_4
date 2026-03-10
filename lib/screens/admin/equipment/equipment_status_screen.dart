// screens/admin/equipment/equipment_status_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Lists/fire_stations.dart';
import '../../../models/equipment_model.dart';
import '../../../models/user_models.dart';
import '../../../services/equipment_service.dart';
import '../../../services/permission_service.dart';
import 'equipment_detail_screen.dart';

class EquipmentStatusScreen extends StatefulWidget {
  const EquipmentStatusScreen({Key? key}) : super(key: key);

  @override
  State<EquipmentStatusScreen> createState() => _EquipmentStatusScreenState();
}

class _EquipmentStatusScreenState extends State<EquipmentStatusScreen>
    with SingleTickerProviderStateMixin {
  final EquipmentService   _equipmentService  = EquipmentService();
  final PermissionService  _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;
  late TabController _tabController;

  // Rohdaten — einmalig geladen, Tabs filtern synchron darauf
  List<EquipmentModel> _allEquipment = [];
  bool _dataLoaded = false;

  String _selectedFireStation = 'Alle';
  String _selectedType        = 'Alle';

  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];
  final List<String> _types = ['Alle', 'Jacke', 'Hose'];

  bool get _canSeeAllStations =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.visibleFireStations.contains('*') == true ||
      (_currentUser?.permissions.visibleFireStations.isNotEmpty == true);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    final user = await _permissionService.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
        if (user != null &&
            !user.isAdmin &&
            !user.permissions.visibleFireStations.contains('*')) {
          _selectedFireStation = user.fireStation;
        }
        _isLoading = false;
      });
      _loadEquipment();
    }
  }

  /// Lädt alle Kleidungsstücke einmalig in _allEquipment.
  /// Tabs filtern synchron auf dieser Liste — kein Stream-Problem möglich.
  Future<void> _loadEquipment() async {
    final list = await _equipmentService.getEquipmentByUserAccess().first;
    if (mounted) setState(() { _allEquipment = list; _dataLoaded = true; });
  }

  List<EquipmentModel> get _filtered {
    var r = _allEquipment;
    if (_selectedFireStation != 'Alle') {
      r = r.where((e) => e.fireStation == _selectedFireStation).toList();
    }
    if (_selectedType != 'Alle') {
      r = r.where((e) => e.type == _selectedType).toList();
    }
    return r;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statusübersicht'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Status'),
            Tab(text: 'Statistik'),
            Tab(text: 'Prüfungen'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: 'Filter',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStatusTab(),
                _buildStatisticsTab(),
                _buildInspectionsTab(),
              ],
            ),
    );
  }

  // ── Tab 1: Status ─────────────────────────────────────────────────────────

  Widget _buildStatusTab() {
    if (!_dataLoaded) return const Center(child: CircularProgressIndicator());
    final list = _filtered;
    if (list.isEmpty) return _empty('Keine Einsatzkleidung gefunden');

    final Map<String, List<EquipmentModel>> grouped = {
      for (final s in EquipmentStatus.values) s: [],
    };
    for (final e in list) {
      grouped[e.status]?.add(e);
    }
    final nonEmpty = grouped.entries
        .where((e) => e.value.isNotEmpty)
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: nonEmpty.length,
      itemBuilder: (_, i) => _statusGroup(nonEmpty[i]),
    );
  }

  Widget _statusGroup(MapEntry<String, List<EquipmentModel>> entry) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color  = EquipmentStatus.getStatusColor(entry.key);
    final icon   = EquipmentStatus.getStatusIcon(entry.key);

    return Card(
      elevation: isDark ? 0 : 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(entry.key,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text('${entry.value.length} Artikel',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${entry.value.length}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more),
            ],
          ),
          children: entry.value
              .map((item) => _equipmentTile(item))
              .toList(),
        ),
      ),
    );
  }

  Widget _equipmentTile(EquipmentModel item) {
    final cs   = Theme.of(context).colorScheme;
    final icon = item.type == 'Jacke'
        ? Icons.accessibility_new
        : Icons.airline_seat_legroom_normal;

    return InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(
              builder: (_) => EquipmentDetailScreen(equipment: item))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.article,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${item.owner}  ·  Gr. ${item.size}'
                    '${_canSeeAllStations ? "  ·  ${item.fireStation}" : ""}',
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ── Tab 2: Statistik ──────────────────────────────────────────────────────

  Widget _buildStatisticsTab() {
    if (!_dataLoaded) return const Center(child: CircularProgressIndicator());
    final list = _filtered;
    if (list.isEmpty) return _empty('Keine Einsatzkleidung gefunden');

    final statusStats  = _calcBy(list, (e) => e.status);
    final typeStats    = _calcBy(list, (e) => e.type);
    final stationStats = _canSeeAllStations
        ? _calcBy(list, (e) => e.fireStation) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _summaryRow(list),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _distCard('Nach Typ', typeStats,
                  (k) => k == 'Jacke'
                      ? Icons.accessibility_new
                      : Icons.airline_seat_legroom_normal,
                  (k) => k == 'Jacke'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary)),
              const SizedBox(width: 10),
              Expanded(child: _distCard('Nach Status', statusStats,
                  (k) => EquipmentStatus.getStatusIcon(k),
                  (k) => EquipmentStatus.getStatusColor(k))),
            ],
          ),
          if (stationStats != null) ...[
            const SizedBox(height: 10),
            _stationCard(stationStats),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(List<EquipmentModel> list) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now    = DateTime.now();

    final ready   = list.where((e) => e.status == EquipmentStatus.ready).length;
    final overdue = list.where((e) => e.checkDate.isBefore(now)).length;
    final totalW  = list.fold(0, (s, e) => s + e.washCycles);
    final avgW    = list.isNotEmpty
        ? (totalW / list.length).toStringAsFixed(1) : '0';

    Widget tile(String val, String lbl, IconData icon, Color color) {
      return Expanded(
        child: Card(
          elevation: isDark ? 0 : 1,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isDark
                ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 5),
              Text(val,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
              Text(lbl,
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('${list.length}', 'Gesamt',
            Icons.inventory_2_outlined, cs.primary),
        const SizedBox(width: 8),
        tile('$ready', 'Bereit',
            Icons.check_circle_outline, Colors.green),
        const SizedBox(width: 8),
        tile('$overdue', 'Überfällig',
            Icons.warning_amber_rounded,
            overdue > 0 ? cs.error : cs.onSurfaceVariant),
        const SizedBox(width: 8),
        tile(avgW, 'Ø Wäschen',
            Icons.local_laundry_service, Colors.blue),
      ],
    );
  }

  Widget _distCard(
    String title,
    Map<String, int> stats,
    IconData Function(String) iconFn,
    Color Function(String) colorFn,
  ) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total  = stats.values.fold(0, (s, v) => s + v);
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 10),
            ...sorted.map((e) {
              final pct   = total > 0 ? e.value / total : 0.0;
              final color = colorFn(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(iconFn(e.key), size: 13, color: color),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(e.key,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurface),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${e.value}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface)),
                    ]),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: color.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _stationCard(Map<String, int> stats) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = sorted.isEmpty ? 1 : sorted.first.value;

    return Card(
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nach Ortswehr',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 10),
            ...sorted.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(FireStations.getIcon(e.key),
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                SizedBox(
                  width: 90,
                  child: Text(e.key,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value / max,
                      minHeight: 8,
                      backgroundColor: cs.primary.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${e.value}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
              ]),
            )),
          ],
        ),
      ),
    );
  }

  // ── Tab 3: Prüfungen ──────────────────────────────────────────────────────

  Widget _buildInspectionsTab() {
    if (!_dataLoaded) return const Center(child: CircularProgressIndicator());
    final now  = DateTime.now();
    final in30 = now.add(const Duration(days: 30));
    final list = _filtered;

    final overdue = list.where((e) => e.checkDate.isBefore(now)).toList()
      ..sort((a, b) => a.checkDate.compareTo(b.checkDate));
    final upcoming = list
        .where((e) =>
            e.checkDate.isAfter(now) && e.checkDate.isBefore(in30))
        .toList()
      ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

    if (overdue.isEmpty && upcoming.isEmpty) {
      return _empty('Keine überfälligen oder bald fälligen Prüfungen');
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (overdue.isNotEmpty) ...[
          _sectionChip(
              '${overdue.length} überfällige Prüfungen',
              Theme.of(context).colorScheme.error),
          const SizedBox(height: 6),
          ...overdue.map((e) =>
              _inspectionTile(e, now, Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
        ],
        if (upcoming.isNotEmpty) ...[
          _sectionChip(
              '${upcoming.length} Prüfungen in 30 Tagen',
              Colors.orange),
          const SizedBox(height: 6),
          ...upcoming.map((e) => _inspectionTile(e, now, Colors.orange)),
        ],
      ],
    );
  }

  Widget _sectionChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }

  Widget _inspectionTile(EquipmentModel item, DateTime now, Color color) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days   = item.checkDate.difference(now).inDays;
    final label  = days < 0
        ? '${-days} Tage überfällig'
        : 'In $days Tagen';

    return Card(
      elevation: isDark ? 0 : 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark
            ? BorderSide(color: cs.outlineVariant)
            : BorderSide(color: color.withOpacity(0.2), width: 1),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => EquipmentDetailScreen(equipment: item))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.18 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                item.type == 'Jacke'
                    ? Icons.accessibility_new
                    : Icons.airline_seat_legroom_normal,
                color: color,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.article,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${item.owner}'
                    '${_canSeeAllStations ? "  ·  ${item.fireStation}" : ""}',
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    DateFormat('dd.MM.yyyy').format(item.checkDate),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: color),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Filter ────────────────────────────────────────────────────────────────

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                    child: Text('Filter',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedFireStation = _canSeeAllStations
                            ? 'Alle'
                            : (_currentUser?.fireStation ?? 'Alle');
                        _selectedType = 'Alle';
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Zurücksetzen'),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_canSeeAllStations) ...[
                  const Text('Ortswehr',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedFireStation,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder()),
                    items: _fireStations
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedFireStation = v ?? 'Alle';
                      });
                      setSS(() {});
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                const Text('Typ',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  items: _types
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                        _selectedType = v ?? 'Alle';
                      });
                    setSS(() {});
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Anwenden'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _empty(String msg) => Center(
      child: Text(msg,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant)));

  Map<String, int> _calcBy(
      List<EquipmentModel> list, String Function(EquipmentModel) key) {
    final m = <String, int>{};
    for (final e in list) {
      m[key(e)] = (m[key(e)] ?? 0) + 1;
    }
    return m;
  }
}
