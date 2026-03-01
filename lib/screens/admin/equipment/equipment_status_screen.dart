// screens/admin/equipment/equipment_status_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
  State<EquipmentStatusScreen> createState() =>
      _EquipmentStatusScreenState();
}

class _EquipmentStatusScreenState extends State<EquipmentStatusScreen>
    with SingleTickerProviderStateMixin {
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;
  late TabController _tabController;

  String _selectedFireStation = 'Alle';
  String _selectedType = 'Alle';

  List<String> get _fireStations =>
      ['Alle', ...FireStations.getAllStations()];
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
        // Nicht-Admins mit nur einer Station → direkt filtern
        if (user != null &&
            !user.isAdmin &&
            !user.permissions.visibleFireStations.contains('*')) {
          _selectedFireStation = user.fireStation;
        }
        _isLoading = false;
      });
    }
  }

  // Einheitlicher Stream — nutzt getEquipmentByUserAccess()
  // und filtert dann clientseitig nach Ortswehr/Typ
  Stream<List<EquipmentModel>> get _filteredStream {
    return _equipmentService.getEquipmentByUserAccess().map((list) {
      var result = list;
      if (_selectedFireStation != 'Alle') {
        result =
            result.where((e) => e.fireStation == _selectedFireStation).toList();
      }
      if (_selectedType != 'Alle') {
        result = result.where((e) => e.type == _selectedType).toList();
      }
      return result;
    });
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: _showFilterDialog,
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

  // ── Status-Tab ────────────────────────────────────────────────────────────

  Widget _buildStatusTab() {
    return StreamBuilder<List<EquipmentModel>>(
      stream: _filteredStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Fehler: ${snapshot.error}'));
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('Keine Einsatzkleidung gefunden'));
        }

        // Nach Status gruppieren
        final Map<String, List<EquipmentModel>> grouped = {};
        for (final s in EquipmentStatus.values) {
          grouped[s] = [];
        }
        for (final item in list) {
          grouped[item.status]?.add(item);
        }
        final nonEmpty =
            grouped.entries.where((e) => e.value.isNotEmpty).toList();

        return ListView.builder(
          itemCount: nonEmpty.length,
          itemBuilder: (_, i) {
            final entry = nonEmpty[i];
            return Card(
              margin: const EdgeInsets.all(8),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: EquipmentStatus.getStatusColor(entry.key)
                        .withOpacity(0.2),
                    child: Icon(EquipmentStatus.getStatusIcon(entry.key),
                        color: EquipmentStatus.getStatusColor(entry.key)),
                  ),
                  title: Text(entry.key,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${entry.value.length} Artikel'),
                  children: entry.value
                      .map((item) => _buildEquipmentListTile(item))
                      .toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEquipmentListTile(EquipmentModel item) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            item.type == 'Jacke' ? Colors.blue : Colors.orange,
        child: Icon(
            item.type == 'Jacke'
                ? Icons.accessibility_new
                : Icons.airline_seat_legroom_normal,
            color: Colors.white,
            size: 18),
      ),
      title: Text(item.article),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Besitzer: ${item.owner} | Gr. ${item.size}'),
          if (_canSeeAllStations)
            Text('Ortswehr: ${FireStations.getFullName(item.fireStation)}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  EquipmentDetailScreen(equipment: item))),
    );
  }

  // ── Statistik-Tab ─────────────────────────────────────────────────────────

  Widget _buildStatisticsTab() {
    return StreamBuilder<List<EquipmentModel>>(
      stream: _filteredStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('Keine Einsatzkleidung gefunden'));
        }

        final statusStats = _calcStatusStats(list);
        final typeStats = _calcTypeStats(list);
        final stationStats =
            _canSeeAllStations ? _calcStationStats(list) : null;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildStatusStatCard(statusStats),
              const SizedBox(height: 16),
              _buildTypeStatCard(typeStats),
              if (stationStats != null) ...[
                const SizedBox(height: 16),
                _buildStationStatCard(stationStats),
              ],
              const SizedBox(height: 16),
              _buildSummaryCard(list),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusStatCard(Map<String, int> stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Status-Verteilung',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...stats.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(EquipmentStatus.getStatusIcon(e.key),
                          color: EquipmentStatus.getStatusColor(e.key),
                          size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.key)),
                      Text('${e.value}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeStatCard(Map<String, int> stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Typ-Verteilung',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...stats.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                          e.key == 'Jacke'
                              ? Icons.accessibility_new
                              : Icons.airline_seat_legroom_normal,
                          size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.key)),
                      Text('${e.value}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildStationStatCard(Map<String, int> stats) {
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verteilung nach Ortswehr',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...sorted.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(FireStations.getIcon(e.key),
                          size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.key)),
                      Text('${e.value}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(List<EquipmentModel> list) {
    final now = DateTime.now();
    final overdue = list.where((e) => e.checkDate.isBefore(now)).length;
    final upcoming = list
        .where((e) =>
            e.checkDate.isAfter(now) &&
            e.checkDate.isBefore(now.add(const Duration(days: 30))))
        .length;
    final totalWash = list.fold(0, (s, e) => s + e.washCycles);
    final avgWash =
        list.isNotEmpty ? (totalWash / list.length).toStringAsFixed(1) : '0';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Zusammenfassung',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _summaryRow(Icons.inventory, 'Gesamt', '${list.length} Artikel'),
            _summaryRow(Icons.check_circle, 'Einsatzbereit',
                '${list.where((e) => e.status == EquipmentStatus.ready).length} Artikel',
                color: Colors.green),
            _summaryRow(Icons.warning, 'Überfällige Prüfungen',
                '$overdue Artikel',
                color: overdue > 0 ? Colors.red : null),
            _summaryRow(Icons.event, 'Prüfung in 30 Tagen',
                '$upcoming Artikel',
                color: upcoming > 0 ? Colors.orange : null),
            _summaryRow(Icons.local_laundry_service, 'Ø Waschzyklen',
                avgWash),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ── Prüfungs-Tab ──────────────────────────────────────────────────────────

  Widget _buildInspectionsTab() {
    final now = DateTime.now();
    final in30Days = now.add(const Duration(days: 30));

    return StreamBuilder<List<EquipmentModel>>(
      stream: _filteredStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];

        final overdue = list.where((e) => e.checkDate.isBefore(now)).toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate));
        final upcoming = list
            .where((e) =>
                e.checkDate.isAfter(now) && e.checkDate.isBefore(in30Days))
            .toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

        if (overdue.isEmpty && upcoming.isEmpty) {
          return const Center(
              child: Text('Keine überfälligen oder bald fälligen Prüfungen'));
        }

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (overdue.isNotEmpty) ...[
              _sectionHeader(
                  '${overdue.length} überfällige Prüfungen', Colors.red),
              ...overdue.map((e) => _inspectionTile(e, now, Colors.red)),
            ],
            if (upcoming.isNotEmpty) ...[
              _sectionHeader(
                  '${upcoming.length} Prüfungen in 30 Tagen', Colors.orange),
              ...upcoming.map((e) => _inspectionTile(e, now, Colors.orange)),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _inspectionTile(
      EquipmentModel item, DateTime now, Color color) {
    final days = item.checkDate.difference(now).inDays;
    final timeDesc = days < 0
        ? '${-days} Tage überfällig'
        : 'In $days Tagen fällig';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              item.type == 'Jacke' ? Colors.blue : Colors.orange,
          child: Icon(
              item.type == 'Jacke'
                  ? Icons.accessibility_new
                  : Icons.airline_seat_legroom_normal,
              color: Colors.white,
              size: 18),
        ),
        title: Text(item.article),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Besitzer: ${item.owner}'),
            Text(
                'Prüfdatum: ${DateFormat('dd.MM.yyyy').format(item.checkDate)}',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold)),
            if (_canSeeAllStations)
              Text(
                  'Ortswehr: ${FireStations.getFullName(item.fireStation)}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: Text(timeDesc,
            style:
                TextStyle(color: color, fontWeight: FontWeight.bold)),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    EquipmentDetailScreen(equipment: item))),
      ),
    );
  }

  // ── Filter-Dialog ─────────────────────────────────────────────────────────

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Filter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canSeeAllStations) ...[
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Ortswehr',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedFireStation,
                isExpanded: true,
                decoration: const InputDecoration(
                    border: OutlineInputBorder()),
                items: _fireStations
                    .map((s) => DropdownMenuItem(
                        value: s,
                        child: Row(children: [
                          if (s != 'Alle') ...[
                            Icon(FireStations.getIcon(s),
                                size: 16,
                                color: Colors.grey[600]),
                            const SizedBox(width: 8),
                          ],
                          Text(s),
                        ])))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedFireStation = v ?? 'Alle'),
              ),
              const SizedBox(height: 16),
            ],
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Typ',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedType,
              isExpanded: true,
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
              items: _types
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _selectedType = v ?? 'Alle'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedFireStation = _canSeeAllStations
                    ? 'Alle'
                    : (_currentUser?.fireStation ?? 'Alle');
                _selectedType = 'Alle';
              });
              Navigator.pop(context);
            },
            child: const Text('Zurücksetzen'),
          ),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anwenden')),
        ],
      ),
    );
  }

  // ── Statistik-Hilfsmethoden ───────────────────────────────────────────────

  Map<String, int> _calcStatusStats(List<EquipmentModel> list) {
    final stats = <String, int>{};
    for (final e in list) {
      stats[e.status] = (stats[e.status] ?? 0) + 1;
    }
    return stats;
  }

  Map<String, int> _calcTypeStats(List<EquipmentModel> list) {
    final stats = <String, int>{};
    for (final e in list) {
      stats[e.type] = (stats[e.type] ?? 0) + 1;
    }
    return stats;
  }

  Map<String, int> _calcStationStats(List<EquipmentModel> list) {
    final stats = <String, int>{};
    for (final e in list) {
      stats[e.fireStation] = (stats[e.fireStation] ?? 0) + 1;
    }
    return stats;
  }
}
