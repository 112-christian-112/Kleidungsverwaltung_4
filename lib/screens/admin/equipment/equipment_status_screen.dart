// screens/equipment_status_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../Lists/fire_stations.dart';
import '../../../models/equipment_model.dart';
import '../../../services/equipment_service.dart';
import '../../../services/permission_service.dart';

import 'equipment_detail_screen.dart';
import 'equipment_list_screen.dart';

class EquipmentStatusScreen extends StatefulWidget {
  const EquipmentStatusScreen({Key? key}) : super(key: key);

  @override
  State<EquipmentStatusScreen> createState() => _EquipmentStatusScreenState();
}

class _EquipmentStatusScreenState extends State<EquipmentStatusScreen> with SingleTickerProviderStateMixin {
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();
  bool _isAdmin = false;
  bool _isLoading = true;
  String _userFireStation = '';
  late TabController _tabController;

  // Filter
  String _selectedFireStation = 'Alle';
  String _selectedType = 'Alle';

  // Ortswehren aus Konstanten-Klasse
  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];
  final List<String> _types = ['Alle', 'Jacke', 'Hose'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAdmin = await _permissionService.isAdmin();
      final userFireStation = await _permissionService.getUserFireStation();

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _userFireStation = userFireStation;

          // Für Nicht-Admins immer die eigene Feuerwehrstation verwenden
          if (!isAdmin && userFireStation.isNotEmpty) {
            _selectedFireStation = userFireStation;
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Benutzerinformationen: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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

  Widget _buildStatusTab() {
    return StreamBuilder<List<EquipmentModel>>(
      stream: _isAdmin && _selectedFireStation == 'Alle'
          ? _equipmentService.getAllEquipment()
          : _equipmentService.getEquipmentByFireStation(
          _selectedFireStation == 'Alle' ? _userFireStation : _selectedFireStation),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Fehler beim Laden der Daten: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final equipmentList = snapshot.data ?? [];

        // Nach Typ filtern
        final filteredList = _selectedType == 'Alle'
            ? equipmentList
            : equipmentList.where((item) => item.type == _selectedType).toList();

        if (filteredList.isEmpty) {
          return const Center(
            child: Text('Keine Einsatzkleidung gefunden'),
          );
        }

        // Gruppierung nach Status
        final Map<String, List<EquipmentModel>> groupedByStatus = {};
        for (final status in EquipmentStatus.values) {
          groupedByStatus[status] = [];
        }

        for (final item in filteredList) {
          if (groupedByStatus.containsKey(item.status)) {
            groupedByStatus[item.status]!.add(item);
          }
        }

        // Nur Status mit Inhalten anzeigen
        final nonEmptyStatuses = groupedByStatus.entries
            .where((entry) => entry.value.isNotEmpty)
            .toList();

        return ListView.builder(
          itemCount: nonEmptyStatuses.length,
          itemBuilder: (context, index) {
            final statusEntry = nonEmptyStatuses[index];
            final status = statusEntry.key;
            final itemsWithStatus = statusEntry.value;

            return Card(
              margin: const EdgeInsets.all(8.0),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: EquipmentStatus.getStatusColor(status).withOpacity(0.2),
                    child: Icon(
                      EquipmentStatus.getStatusIcon(status),
                      color: EquipmentStatus.getStatusColor(status),
                    ),
                  ),
                  title: Text(
                    status,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${itemsWithStatus.length} Artikel'),
                  initiallyExpanded: false,
                  children: itemsWithStatus.map((item) => ListTile(
                    leading: Icon(
                      item.type == 'Jacke'
                          ? Icons.accessibility_new
                          : Icons.airline_seat_legroom_normal,
                      color: item.type == 'Jacke' ? Colors.blue : Colors.orange,
                    ),
                    title: Text(item.article),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Besitzer: ${item.owner} | Größe: ${item.size}'),
                        Text(
                          'Ortswehr: ${FireStations.getFullName(item.fireStation)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EquipmentDetailScreen(equipment: item),
                        ),
                      );
                    },
                  )).toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatisticsTab() {
    return StreamBuilder<List<EquipmentModel>>(
      stream: _isAdmin && _selectedFireStation == 'Alle'
          ? _equipmentService.getAllEquipment()
          : _equipmentService.getEquipmentByFireStation(
          _selectedFireStation == 'Alle' ? _userFireStation : _selectedFireStation),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Fehler beim Laden der Daten: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final equipmentList = snapshot.data ?? [];

        // Nach Typ filtern
        final filteredList = _selectedType == 'Alle'
            ? equipmentList
            : equipmentList.where((item) => item.type == _selectedType).toList();

        if (filteredList.isEmpty) {
          return const Center(
            child: Text('Keine Einsatzkleidung gefunden'),
          );
        }

        // Statistiken berechnen
        final statusStats = _calculateStatusStats(filteredList);
        final typeStats = _calculateTypeStats(filteredList);
        final stationStats = _isAdmin ? _calculateStationStats(filteredList) : null;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusStatisticsCard(context, statusStats),
              const SizedBox(height: 16),
              _buildTypeStatisticsCard(context, typeStats),
              if (_isAdmin && stationStats != null) ...[
                const SizedBox(height: 16),
                _buildStationStatisticsCard(context, stationStats),
              ],
              const SizedBox(height: 24),
              _buildSummaryCard(context, filteredList),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInspectionsTab() {
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));

    return StreamBuilder<List<EquipmentModel>>(
      stream: _isAdmin && _selectedFireStation == 'Alle'
          ? _equipmentService.getAllEquipment()
          : _equipmentService.getEquipmentByFireStation(
          _selectedFireStation == 'Alle' ? _userFireStation : _selectedFireStation),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Fehler beim Laden der Daten: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final equipmentList = snapshot.data ?? [];

        // Nach Typ filtern
        final filteredList = _selectedType == 'Alle'
            ? equipmentList
            : equipmentList.where((item) => item.type == _selectedType).toList();

        if (filteredList.isEmpty) {
          return const Center(
            child: Text('Keine Einsatzkleidung gefunden'),
          );
        }

        // Überfällige Prüfungen
        final overdueInspections = filteredList
            .where((item) => item.checkDate.isBefore(now))
            .toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

        // Anstehende Prüfungen (nächste 30 Tage)
        final upcomingInspections = filteredList
            .where((item) =>
        item.checkDate.isAfter(now) &&
            item.checkDate.isBefore(thirtyDaysFromNow))
            .toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

        // Prüfungen OK (älter als 30 Tage, aber nicht überfällig)
        final okInspections = filteredList
            .where((item) =>
        item.checkDate.isAfter(now) &&
            item.checkDate.isAfter(thirtyDaysFromNow))
            .toList()
          ..sort((a, b) => a.checkDate.compareTo(b.checkDate));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Prüfstatistik-Karte
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prüfstatistik',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            context,
                            count: overdueInspections.length,
                            label: 'Überfällig',
                            color: Colors.red,
                            icon: Icons.warning,
                          ),
                          _buildStatItem(
                            context,
                            count: upcomingInspections.length,
                            label: 'In 30 Tagen',
                            color: Colors.orange,
                            icon: Icons.event,
                          ),
                          _buildStatItem(
                            context,
                            count: okInspections.length,
                            label: 'Aktuell',
                            color: Colors.green,
                            icon: Icons.check_circle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Überfällige Prüfungen
              if (overdueInspections.isNotEmpty) ...[
                _buildSectionHeader(
                  'Überfällige Prüfungen',
                  Colors.red,
                  Icons.warning,
                ),
                ...overdueInspections.map((equipment) => _buildInspectionItem(context, equipment, true)),
                const SizedBox(height: 16),
              ],

              // Anstehende Prüfungen
              if (upcomingInspections.isNotEmpty) ...[
                _buildSectionHeader(
                  'Anstehende Prüfungen (30 Tage)',
                  Colors.orange,
                  Icons.event,
                ),
                ...upcomingInspections.map((equipment) => _buildInspectionItem(context, equipment, false)),
              ],

              if (overdueInspections.isEmpty && upcomingInspections.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text('Keine überfälligen oder anstehenden Prüfungen'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusStatisticsCard(BuildContext context, Map<String, int> statusStats) {
    final totalItems = statusStats.values.fold(0, (sum, item) => sum + item);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status der Einsatzkleidung',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: statusStats.entries.map((entry) {
                          final percent = totalItems > 0
                              ? (entry.value / totalItems * 100).toStringAsFixed(1)
                              : '0.0';

                          return PieChartSectionData(
                            color: EquipmentStatus.getStatusColor(entry.key),
                            value: entry.value.toDouble(),
                            title: '$percent%',
                            radius: 80,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: statusStats.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Icon(
                                EquipmentStatus.getStatusIcon(entry.key),
                                color: EquipmentStatus.getStatusColor(entry.key),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${entry.key} (${entry.value})',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeStatisticsCard(BuildContext context, Map<String, int> typeStats) {
    final totalItems = typeStats.values.fold(0, (sum, item) => sum + item);
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Arten der Einsatzkleidung',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: typeStats.entries.map((entry) {
                          final index = typeStats.keys.toList().indexOf(entry.key);
                          final percent = totalItems > 0
                              ? (entry.value / totalItems * 100).toStringAsFixed(1)
                              : '0.0';

                          return PieChartSectionData(
                            color: colors[index % colors.length],
                            value: entry.value.toDouble(),
                            title: '$percent%',
                            radius: 80,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: typeStats.entries.map((entry) {
                        final index = typeStats.keys.toList().indexOf(entry.key);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                color: colors[index % colors.length],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${entry.key} (${entry.value})',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationStatisticsCard(BuildContext context, Map<String, int> stationStats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verteilung nach Ortswehren',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: stationStats.entries
                      .map((e) => e.value.toDouble())
                      .fold(0.0, (a, b) => a > b ? a : b) * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value >= stationStats.length) {
                            return const SizedBox.shrink();
                          }
                          final stations = stationStats.keys.toList();
                          final station = stations[value.toInt()];
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: RotatedBox(
                              quarterTurns: 1,
                              child: Text(
                                station,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    stationStats.length,
                        (index) {
                      final entry = stationStats.entries.elementAt(index);
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: entry.value.toDouble(),
                            color: Theme.of(context).colorScheme.primary,
                            width: 20,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(6),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, List<EquipmentModel> equipmentList) {
    // Prüfzustand
    final now = DateTime.now();
    final overdueCount = equipmentList.where((item) => item.checkDate.isBefore(now)).length;
    final upcomingCount = equipmentList
        .where((item) =>
    item.checkDate.isAfter(now) &&
        item.checkDate.isBefore(now.add(const Duration(days: 30))))
        .length;

    // Durchschnittliche Waschzyklen
    final totalWashCycles = equipmentList.fold(0, (sum, item) => sum + item.washCycles);
    final avgWashCycles = equipmentList.isNotEmpty
        ? (totalWashCycles / equipmentList.length).toStringAsFixed(1)
        : '0.0';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Zusammenfassung',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSummaryItem(
                'Gesamtanzahl',
                '${equipmentList.length} Artikel',
                icon: Icons.inventory
            ),
            _buildSummaryItem(
                'Einsatzbereit',
                '${equipmentList.where((item) => item.status == EquipmentStatus.ready).length} Artikel',
                icon: Icons.check_circle,
                iconColor: Colors.green
            ),
            _buildSummaryItem(
                'Überfällige Prüfungen',
                '$overdueCount Artikel',
                icon: Icons.warning,
                iconColor: Colors.red
            ),
            _buildSummaryItem(
                'Anstehende Prüfungen',
                '$upcomingCount Artikel',
                icon: Icons.event,
                iconColor: Colors.orange
            ),
            _buildSummaryItem(
                '∅ Waschzyklen',
                avgWashCycles,
                icon: Icons.local_laundry_service
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, {IconData? icon, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          if (icon != null) Icon(icon, color: iconColor, size: 20),
          if (icon != null) const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      BuildContext context, {
        required int count,
        required String label,
        required Color color,
        required IconData icon,
      }) {
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: color.withOpacity(0.2),
          child: Icon(
            icon,
            color: color,
            size: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionItem(BuildContext context, EquipmentModel equipment, bool isOverdue) {
    final daysDifference = equipment.checkDate.difference(DateTime.now()).inDays;
    String timeDescription;
    Color timeColor;

    if (isOverdue) {
      timeDescription = 'Überfällig seit ${-daysDifference} Tagen';
      timeColor = Colors.red;
    } else {
      timeDescription = 'In $daysDifference Tagen';
      timeColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: equipment.type == 'Jacke' ? Colors.blue : Colors.orange,
          child: Icon(
            equipment.type == 'Jacke'
                ? Icons.accessibility_new
                : Icons.airline_seat_legroom_normal,
            color: Colors.white,
          ),
        ),
        title: Text(
          equipment.article,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Besitzer: ${equipment.owner}'),
            Text(
              'Prüfdatum: ${DateFormat('dd.MM.yyyy').format(equipment.checkDate)}',
              style: TextStyle(color: timeColor, fontWeight: FontWeight.bold),
            ),
            Text(
              'Ortswehr: ${FireStations.getFullName(equipment.fireStation)}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        trailing: Text(
          timeDescription,
          style: TextStyle(
            color: timeColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EquipmentDetailScreen(
                equipment: equipment,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Filter'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Feuerwehrstation-Filter (nur für Admins)
                if (_isAdmin) ...[
                  const Text('Ortswehr'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedFireStation,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _fireStations.map((String station) {
                      return DropdownMenuItem<String>(
                        value: station,
                        child: Row(
                          children: [
                            if (station != 'Alle') ...[
                              Icon(
                                FireStations.getIcon(station),
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                station == 'Alle'
                                    ? station
                                    : station,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedFireStation = newValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Typ-Filter
                const Text('Typ'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _types.map((String type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedType = newValue;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  if (_isAdmin) {
                    _selectedFireStation = 'Alle';
                  } else {
                    _selectedFireStation = _userFireStation;
                  }
                  _selectedType = 'Alle';
                });
              },
              child: const Text('Zurücksetzen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                this.setState(() {});
              },
              child: const Text('Anwenden'),
            ),
          ],
        ),
      ),
    );
  }

  // Hilfsfunktionen zur Statistikberechnung
  Map<String, int> _calculateStatusStats(List<EquipmentModel> equipment) {
    final Map<String, int> stats = {};
    for (final status in EquipmentStatus.values) {
      stats[status] = 0;
    }

    for (final item in equipment) {
      stats[item.status] = (stats[item.status] ?? 0) + 1;
    }

    // Leere Einträge entfernen
    stats.removeWhere((key, value) => value == 0);

    return stats;
  }

  Map<String, int> _calculateTypeStats(List<EquipmentModel> equipment) {
    final Map<String, int> stats = {};

    for (final item in equipment) {
      stats[item.type] = (stats[item.type] ?? 0) + 1;
    }

    return stats;
  }

  Map<String, int> _calculateStationStats(List<EquipmentModel> equipment) {
    final Map<String, int> stats = {};

    for (final item in equipment) {
      stats[item.fireStation] = (stats[item.fireStation] ?? 0) + 1;
    }

    return stats;
  }
}