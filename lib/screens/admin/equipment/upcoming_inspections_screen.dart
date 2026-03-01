// screens/admin/equipment/upcoming_inspections_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Lists/fire_stations.dart';
import '../../../models/equipment_model.dart';
import '../../../models/user_models.dart';
import '../../../services/equipment_service.dart';
import '../../../services/permission_service.dart';
import 'equipment_detail_screen.dart';
import 'equipment_inspection_form_screen.dart';

class UpcomingInspectionsScreen extends StatefulWidget {
  const UpcomingInspectionsScreen({Key? key}) : super(key: key);

  @override
  State<UpcomingInspectionsScreen> createState() =>
      _UpcomingInspectionsScreenState();
}

class _UpcomingInspectionsScreenState
    extends State<UpcomingInspectionsScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;

  // Filter & Gruppierung
  String _searchQuery = '';
  String _filterFireStation = 'Alle';
  String _filterType = 'Alle';
  bool _groupByOwner = false;
  bool _groupByStation = false;

  // Zeitraum: überfällig + 3 Monate voraus
  late final DateTime _today;
  late final DateTime _threeMonthsFromNow;

  List<String> get _fireStations =>
      ['Alle', ...FireStations.getAllStations()];
  final List<String> _types = ['Alle', 'Jacke', 'Hose'];

  bool get _canSeeAllStations =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.visibleFireStations.contains('*') == true ||
      (_currentUser?.permissions.visibleFireStations.isNotEmpty == true);

  bool get _canInspect =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.inspectionPerform == true;

  @override
  void initState() {
    super.initState();
    _today = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _threeMonthsFromNow = _today.add(const Duration(days: 90));
    _loadUser();
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
          _filterFireStation = user.fireStation;
        }
        _isLoading = false;
      });
    }
  }

  // ── Stream & Filter ───────────────────────────────────────────────────────

  Stream<List<EquipmentModel>> get _stream =>
      _equipmentService.getEquipmentByUserAccess().map((list) {
        // Nur Artikel mit Prüfdatum in der Vergangenheit oder bis 3 Monate voraus
        var result = list
            .where((e) => e.checkDate.isBefore(_threeMonthsFromNow))
            .toList();

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          result = result
              .where((e) =>
                  e.owner.toLowerCase().contains(q) ||
                  e.article.toLowerCase().contains(q) ||
                  e.size.toLowerCase().contains(q))
              .toList();
        }

        if (_filterFireStation != 'Alle') {
          result =
              result.where((e) => e.fireStation == _filterFireStation).toList();
        }

        if (_filterType != 'Alle') {
          result = result.where((e) => e.type == _filterType).toList();
        }

        // Sortierung: überfälligste zuerst
        result.sort((a, b) => a.checkDate.compareTo(b.checkDate));
        return result;
      });

  // ── Kategorisierung ───────────────────────────────────────────────────────

  _InspectionCategory _getCategory(EquipmentModel e) {
    final days = e.checkDate.difference(_today).inDays;
    if (days < 0) return _InspectionCategory.overdue;
    if (days <= 30) return _InspectionCategory.thisMonth;
    return _InspectionCategory.upcoming;
  }

  // ── Gruppierung ───────────────────────────────────────────────────────────

  Map<String, List<EquipmentModel>> _groupItems(
      List<EquipmentModel> list) {
    if (_groupByOwner) {
      final map = <String, List<EquipmentModel>>{};
      for (final e in list) {
        map.putIfAbsent(e.owner, () => []).add(e);
      }
      return map;
    }
    if (_groupByStation && _canSeeAllStations) {
      final map = <String, List<EquipmentModel>>{};
      for (final e in list) {
        map.putIfAbsent(e.fireStation, () => []).add(e);
      }
      return map;
    }
    // Keine Gruppierung → nach Dringlichkeit
    final overdue = list
        .where((e) => _getCategory(e) == _InspectionCategory.overdue)
        .toList();
    final thisMonth = list
        .where((e) => _getCategory(e) == _InspectionCategory.thisMonth)
        .toList();
    final upcoming = list
        .where((e) => _getCategory(e) == _InspectionCategory.upcoming)
        .toList();
    final map = <String, List<EquipmentModel>>{};
    if (overdue.isNotEmpty) map['Überfällig'] = overdue;
    if (thisMonth.isNotEmpty) map['Diesen Monat'] = thisMonth;
    if (upcoming.isNotEmpty) map['Nächste 3 Monate'] = upcoming;
    return map;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anstehende Prüfungen'),
        actions: [
          // Gruppierungs-Toggle
          IconButton(
            icon: Icon(
              _groupByOwner
                  ? Icons.person
                  : _groupByStation
                      ? Icons.local_fire_department
                      : Icons.view_list,
            ),
            tooltip: 'Gruppierung wechseln',
            onPressed: _cycleGrouping,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Suchfeld ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Suchen',
                      hintText: 'Besitzer, Artikel, Größe...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),

                // ── Aktive Filter als Chips ────────────────────────────────
                if (_filterFireStation != 'Alle' || _filterType != 'Alle')
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_filterFireStation != 'Alle')
                          Chip(
                            label: Text(_filterFireStation),
                            deleteIcon: const Icon(Icons.clear, size: 16),
                            onDeleted: () => setState(
                                () => _filterFireStation = 'Alle'),
                          ),
                        if (_filterType != 'Alle')
                          Chip(
                            label: Text(_filterType),
                            deleteIcon: const Icon(Icons.clear, size: 16),
                            onDeleted: () =>
                                setState(() => _filterType = 'Alle'),
                          ),
                      ],
                    ),
                  ),

                // ── Gruppierungshinweis ────────────────────────────────────
                if (_groupByOwner || _groupByStation)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          _groupByOwner
                              ? Icons.person
                              : Icons.local_fire_department,
                          size: 14,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _groupByOwner
                              ? 'Gruppiert nach Besitzer'
                              : 'Gruppiert nach Ortswehr',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            _groupByOwner = false;
                            _groupByStation = false;
                          }),
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap),
                          child: const Text('Zurücksetzen',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                // ── Liste ─────────────────────────────────────────────────
                Expanded(
                  child: StreamBuilder<List<EquipmentModel>>(
                    stream: _stream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: Text('Fehler: ${snapshot.error}'));
                      }

                      final list = snapshot.data ?? [];

                      if (list.isEmpty) {
                        return _buildEmptyState();
                      }

                      // Zusammenfassungs-Header
                      final overdueCount = list
                          .where((e) =>
                              _getCategory(e) ==
                              _InspectionCategory.overdue)
                          .length;

                      final grouped = _groupItems(list);

                      return ListView(
                        padding: const EdgeInsets.only(bottom: 80),
                        children: [
                          // Summary Banner
                          _buildSummaryBanner(list.length, overdueCount),

                          // Gruppen
                          ...grouped.entries.map((entry) =>
                              _buildGroup(entry.key, entry.value)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  // ── Summary Banner ────────────────────────────────────────────────────────

  Widget _buildSummaryBanner(int total, int overdue) {
    final thisMonth = total - overdue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Card(
        color: overdue > 0
            ? Colors.red.shade50
            : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                overdue > 0 ? Icons.warning_rounded : Icons.check_circle,
                color: overdue > 0 ? Colors.red : Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overdue > 0
                      ? '$overdue überfällig · ${total - overdue} anstehend'
                      : '$total anstehende Prüfungen in den nächsten 3 Monaten',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: overdue > 0 ? Colors.red.shade800 : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Gruppe (Header + Items) ───────────────────────────────────────────────

  Widget _buildGroup(String title, List<EquipmentModel> items) {
    // Farbe basierend auf Titel oder Kategorie der Items
    Color headerColor;
    IconData headerIcon;

    if (title == 'Überfällig') {
      headerColor = Colors.red;
      headerIcon = Icons.warning_rounded;
    } else if (title == 'Diesen Monat') {
      headerColor = Colors.orange;
      headerIcon = Icons.event;
    } else if (title == 'Nächste 3 Monate') {
      headerColor = Colors.blue;
      headerIcon = Icons.event_available;
    } else if (_groupByOwner) {
      // Gruppenfarbe nach Dringlichkeit der schlimmsten Items
      final hasOverdue =
          items.any((e) => _getCategory(e) == _InspectionCategory.overdue);
      final hasThisMonth = items
          .any((e) => _getCategory(e) == _InspectionCategory.thisMonth);
      headerColor = hasOverdue
          ? Colors.red
          : hasThisMonth
              ? Colors.orange
              : Colors.blue;
      headerIcon = Icons.person;
    } else {
      headerColor = Theme.of(context).colorScheme.primary;
      headerIcon = Icons.local_fire_department;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(
          backgroundColor: headerColor.withOpacity(0.15),
          radius: 18,
          child: Icon(headerIcon, color: headerColor, size: 18),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: headerColor,
          ),
        ),
        subtitle: Text(
          '${items.length} ${items.length == 1 ? 'Artikel' : 'Artikel'}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${items.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more),
          ],
        ),
        children: items.map((e) => _buildEquipmentTile(e)).toList(),
      ),
    );
  }

  // ── Equipment-Tile ────────────────────────────────────────────────────────

  Widget _buildEquipmentTile(EquipmentModel equipment) {
    final days = equipment.checkDate.difference(_today).inDays;
    final category = _getCategory(equipment);

    Color statusColor;
    String timeText;
    IconData statusIcon;

    switch (category) {
      case _InspectionCategory.overdue:
        statusColor = Colors.red;
        timeText = '${-days} Tage überfällig';
        statusIcon = Icons.warning_rounded;
        break;
      case _InspectionCategory.thisMonth:
        statusColor = Colors.orange;
        timeText = days == 0 ? 'Heute fällig' : 'In $days Tagen';
        statusIcon = Icons.schedule;
        break;
      case _InspectionCategory.upcoming:
        statusColor = Colors.blue;
        timeText = 'In $days Tagen';
        statusIcon = Icons.event_available;
        break;
    }

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor:
            equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
        radius: 20,
        child: Icon(
          equipment.type == 'Jacke'
              ? Icons.accessibility_new
              : Icons.airline_seat_legroom_normal,
          color: Colors.white,
          size: 18,
        ),
      ),
      title: Text(
        equipment.owner,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${equipment.article} · Gr. ${equipment.size}',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(statusIcon, size: 12, color: statusColor),
              const SizedBox(width: 4),
              Text(
                timeText,
                style: TextStyle(
                  fontSize: 12,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('dd.MM.yyyy').format(equipment.checkDate),
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          if (_canSeeAllStations && !_groupByStation)
            Text(
              equipment.fireStation,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: _canInspect
          ? IconButton(
              icon: Icon(Icons.fact_check,
                  color: statusColor, size: 22),
              tooltip: 'Prüfung durchführen',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      EquipmentInspectionFormScreen(equipment: equipment),
                ),
              ),
            )
          : Icon(statusIcon, color: statusColor, size: 20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EquipmentDetailScreen(equipment: equipment),
        ),
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 72, color: Colors.green.shade300),
          const SizedBox(height: 16),
          const Text(
            'Keine Prüfungen fällig',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'In den nächsten 3 Monaten stehen\nkeine Prüfungen an.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          if (_filterFireStation != 'Alle' || _filterType != 'Alle') ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() {
                _filterFireStation = 'Alle';
                _filterType = 'Alle';
              }),
              child: const Text('Filter zurücksetzen'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Gruppierungs-Toggle ───────────────────────────────────────────────────

  void _cycleGrouping() {
    setState(() {
      if (!_groupByOwner && !_groupByStation) {
        _groupByOwner = true;
        _groupByStation = false;
      } else if (_groupByOwner) {
        if (_canSeeAllStations) {
          _groupByOwner = false;
          _groupByStation = true;
        } else {
          _groupByOwner = false;
          _groupByStation = false;
        }
      } else {
        _groupByOwner = false;
        _groupByStation = false;
      }
    });
  }

  // ── Filter-Dialog ─────────────────────────────────────────────────────────

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Filter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ortswehr-Filter (nur für berechtigte User)
            if (_canSeeAllStations) ...[
              const Text('Ortswehr',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _filterFireStation,
                isExpanded: true,
                decoration: const InputDecoration(
                    border: OutlineInputBorder()),
                items: _fireStations
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _filterFireStation = v ?? 'Alle'),
              ),
              const SizedBox(height: 16),
            ],

            // Typ-Filter
            const Text('Typ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _filterType,
              isExpanded: true,
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
              items: _types
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _filterType = v ?? 'Alle'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _filterFireStation = _canSeeAllStations
                    ? 'Alle'
                    : _currentUser?.fireStation ?? 'Alle';
                _filterType = 'Alle';
              });
              Navigator.pop(context);
            },
            child: const Text('Zurücksetzen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anwenden'),
          ),
        ],
      ),
    );
  }
}

// ── Hilfsenums ────────────────────────────────────────────────────────────────

enum _InspectionCategory { overdue, thisMonth, upcoming }
