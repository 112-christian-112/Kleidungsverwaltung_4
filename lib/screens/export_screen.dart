// lib/screens/export_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Lists/fire_stations.dart';
import '../models/equipment_inspection_model.dart';
import '../models/equipment_model.dart';
import '../models/mission_model.dart';
import '../models/user_models.dart';
import '../services/equipment_inspection_service.dart';
import '../services/equipment_service.dart';
import '../services/export_service.dart';
import '../services/mission_service.dart';
import '../services/permission_service.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({Key? key}) : super(key: key);

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen>
    with SingleTickerProviderStateMixin {
  final EquipmentService _equipmentService = EquipmentService();
  final MissionService _missionService = MissionService();
  final EquipmentInspectionService _inspectionService =
      EquipmentInspectionService();
  final PermissionService _permissionService = PermissionService();

  static final DateFormat _dateFmt = DateFormat('dd.MM.yyyy');

  late TabController _tabController;
  UserModel? _currentUser;

  // Daten — einmalig geladen, nicht per Stream pro Tab
  List<EquipmentModel> _allEquipment = [];
  List<MissionModel> _allMissions = [];
  List<EquipmentInspectionModel> _allInspections = [];
  // Lookup-Map: equipmentId → EquipmentModel (für Prüfungsexport)
  Map<String, EquipmentModel> _equipmentById = {};
  bool _isLoading = true;

  // Filter
  String _filterFireStation = 'Alle';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _filterType = 'Alle';
  String _filterStatus = 'Alle';
  String _filterMissionType = 'Alle';
  String _filterInspectionResult = 'Alle';

  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];
  final List<String> _types = ['Alle', 'Jacke', 'Hose'];
  final List<String> _statusOptions = ['Alle', ...EquipmentStatus.values];
  final List<String> _missionTypes = [
    'Alle', 'fire', 'technical', 'hazmat', 'water', 'training', 'other'
  ];
  final List<String> _inspectionResults = [
    'Alle', 'passed', 'conditionalPass', 'failed'
  ];

  bool get _canSeeAllStations =>
      _currentUser?.isAdmin == true ||
      (_currentUser?.permissions.visibleFireStations.contains('*') == true);

  bool get _hasDateFilter => _dateFrom != null || _dateTo != null;

  bool get _hasAnyFilter =>
      _filterFireStation != 'Alle' ||
      _filterType != 'Alle' ||
      _filterStatus != 'Alle' ||
      _filterMissionType != 'Alle' ||
      _filterInspectionResult != 'Alle' ||
      _hasDateFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Daten einmalig laden ─────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final user = await _permissionService.getCurrentUser();
      final equipment =
          await _equipmentService.getEquipmentByUserAccess().first;
      final missions =
          await _missionService.getMissionsForCurrentUser().first;
      // Future statt Stream → liefert wirklich ALLE Dokumente auf einmal
      final inspections =
          await _inspectionService.getAllInspectionsFuture();

      if (mounted) {
        setState(() {
          _currentUser = user;
          _allEquipment = equipment;
          _allMissions = missions;
          _allInspections = inspections;
          _equipmentById = {for (final e in equipment) e.id: e};
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Filter-Logik ─────────────────────────────────────────────────────────

  List<EquipmentModel> get _filteredEquipment =>
      _allEquipment.where((e) {
        if (_filterFireStation != 'Alle' &&
            e.fireStation != _filterFireStation) return false;
        if (_filterType != 'Alle' && e.type != _filterType) return false;
        if (_filterStatus != 'Alle' && e.status != _filterStatus) return false;
        return true;
      }).toList();

  List<MissionModel> get _filteredMissions =>
      _allMissions.where((m) {
        if (_filterFireStation != 'Alle' &&
            m.fireStation != _filterFireStation &&
            !m.involvedFireStations.contains(_filterFireStation)) return false;
        if (_filterMissionType != 'Alle' && m.type != _filterMissionType)
          return false;
        if (_dateFrom != null && m.startTime.isBefore(_dateFrom!)) return false;
        if (_dateTo != null &&
            m.startTime.isAfter(_dateTo!.add(const Duration(days: 1))))
          return false;
        return true;
      }).toList();

  List<EquipmentInspectionModel> get _filteredInspections =>
      _allInspections.where((i) {
        // Ortswehr-Filter nur anwenden wenn Equipment-Map befüllt ist
        if (_filterFireStation != 'Alle' && _equipmentById.isNotEmpty) {
          final eq = _equipmentById[i.equipmentId];
          // Prüfung einschließen wenn Equipment nicht gefunden (kein false-negative)
          if (eq != null && eq.fireStation != _filterFireStation) return false;
        }
        if (_filterInspectionResult != 'Alle') {
          final r = i.result.toString().split('.').last;
          if (r != _filterInspectionResult) return false;
        }
        if (_dateFrom != null && i.inspectionDate.isBefore(_dateFrom!))
          return false;
        if (_dateTo != null &&
            i.inspectionDate
                .isAfter(_dateTo!.add(const Duration(days: 1))))
          return false;
        return true;
      }).toList();

  void _resetFilters() => setState(() {
        _filterFireStation = 'Alle';
        _filterType = 'Alle';
        _filterStatus = 'Alle';
        _filterMissionType = 'Alle';
        _filterInspectionResult = 'Alle';
        _dateFrom = null;
        _dateTo = null;
      });

  // ── Datum-Picker ─────────────────────────────────────────────────────────
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      // Nur vorausfüllen wenn bereits ein Zeitraum gewählt wurde
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
      locale: const Locale('de', 'DE'),
      builder: (context, child) => child!,
    );
    if (picked != null && mounted) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
    }
  }

  // ── Export-Titel ─────────────────────────────────────────────────────────

  String _equipmentTitle() {
    final parts = <String>['Einsatzkleidung'];
    if (_filterFireStation != 'Alle') parts.add(_filterFireStation);
    if (_filterType != 'Alle') parts.add(_filterType);
    if (_filterStatus != 'Alle') parts.add(_filterStatus);
    return parts.join(' – ');
  }

  String _missionTitle() {
    final parts = <String>['Einsätze'];
    if (_filterFireStation != 'Alle') parts.add(_filterFireStation);
    if (_filterMissionType != 'Alle')
      parts.add(_missionTypeName(_filterMissionType));
    if (_hasDateFilter) {
      final from = _dateFrom != null ? _dateFmt.format(_dateFrom!) : '…';
      final to = _dateTo != null ? _dateFmt.format(_dateTo!) : '…';
      parts.add('$from – $to');
    }
    return parts.join(' – ');
  }

  String _inspectionTitle() {
    final parts = <String>['Prüfungshistorie'];
    if (_filterInspectionResult != 'Alle')
      parts.add(_inspectionResultName(_filterInspectionResult));
    if (_hasDateFilter) {
      final from = _dateFrom != null ? _dateFmt.format(_dateFrom!) : '…';
      final to = _dateTo != null ? _dateFmt.format(_dateTo!) : '…';
      parts.add('$from – $to');
    }
    return parts.join(' – ');
  }

  // ── Hilfsnamen ───────────────────────────────────────────────────────────

  String _missionTypeName(String type) {
    const names = {
      'fire': 'Brandeinsatz',
      'technical': 'Techn. Hilfeleistung',
      'hazmat': 'Gefahrgut',
      'water': 'Wasser/Sturm',
      'training': 'Übung',
      'other': 'Sonstige',
    };
    return names[type] ?? type;
  }

  String _inspectionResultName(String result) {
    const names = {
      'passed': 'Bestanden',
      'conditionalPass': 'Bedingt bestanden',
      'failed': 'Nicht bestanden',
    };
    return names[result] ?? result;
  }

  IconData _missionIcon(String type) {
    switch (type) {
      case 'fire': return Icons.local_fire_department;
      case 'technical': return Icons.build;
      case 'hazmat': return Icons.dangerous;
      case 'water': return Icons.water;
      case 'training': return Icons.school;
      default: return Icons.assignment;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Daten aktualisieren',
            onPressed: _loadAll,
          ),
          if (_hasAnyFilter)
            IconButton(
              icon: const Icon(Icons.filter_list_off),
              tooltip: 'Filter zurücksetzen',
              onPressed: _resetFilters,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.security, size: 18), text: 'Kleidung'),
            Tab(icon: Icon(Icons.assignment, size: 18), text: 'Einsätze'),
            Tab(icon: Icon(Icons.fact_check, size: 18), text: 'Prüfungen'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildEquipmentTab(),
                _buildMissionsTab(),
                _buildInspectionsTab(),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 – EINSATZKLEIDUNG
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEquipmentTab() {
    final filtered = _filteredEquipment;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_canSeeAllStations) ...[
                    Expanded(
                      child: _dropdown(
                        label: 'Ortswehr',
                        value: _filterFireStation,
                        items: _fireStations,
                        onChanged: (v) =>
                            setState(() => _filterFireStation = v!),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _dropdown(
                      label: 'Typ',
                      value: _filterType,
                      items: _types,
                      onChanged: (v) => setState(() => _filterType = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dropdown(
                      label: 'Status',
                      value: _filterStatus,
                      items: _statusOptions,
                      onChanged: (v) =>
                          setState(() => _filterStatus = v!),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _countBadge(filtered.length),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState()
              : _equipmentList(filtered),
        ),
        _exportButtons(
          isEmpty: filtered.isEmpty,
          label: 'Einsatzkleidung',
          onExcel: (_) => ExportService.exportToExcel(
              context, filtered, title: _equipmentTitle()),
          onPdf: (withStats) => ExportService.exportEquipmentPdf(
              context, filtered,
              title: _equipmentTitle(),
              withStatsSummary: withStats),
          onEmail: (withStats) => ExportService.exportEquipmentPdf(
              context, filtered,
              title: _equipmentTitle(),
              withStatsSummary: withStats),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 – EINSÄTZE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMissionsTab() {
    final filtered = _filteredMissions;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (_canSeeAllStations) ...[
                        Expanded(
                          child: _dropdown(
                            label: 'Ortswehr',
                            value: _filterFireStation,
                            items: _fireStations,
                            onChanged: (v) =>
                                setState(() => _filterFireStation = v!),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _dropdown(
                          label: 'Typ',
                          value: _filterMissionType,
                          items: _missionTypes,
                          displayNames: {
                            for (final t in _missionTypes)
                              t: t == 'Alle' ? 'Alle' : _missionTypeName(t)
                          },
                          onChanged: (v) =>
                              setState(() => _filterMissionType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _dateRangeRow(),
                ],
              ),
            ),
          ),
        ),
        _countBadge(filtered.length),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty ? _emptyState() : _missionList(filtered),
        ),
        _exportButtons(
          isEmpty: filtered.isEmpty,
          label: 'Einsätze',
          onExcel: (_) => ExportService.exportMissionsExcel(
              context, filtered,
              equipmentById: _equipmentById,
              title: _missionTitle()),
          onPdf: (withStats) => ExportService.exportMissionsPdf(
              context, filtered,
              equipmentById: _equipmentById,
              title: _missionTitle(),
              withStatsSummary: withStats),
          onEmail: (withStats) => ExportService.exportMissionsPdf(
              context, filtered,
              equipmentById: _equipmentById,
              title: _missionTitle(),
              withStatsSummary: withStats),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 – PRÜFUNGEN
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildInspectionsTab() {
    final filtered = _filteredInspections;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (_canSeeAllStations) ...[
                        Expanded(
                          child: _dropdown(
                            label: 'Ortswehr',
                            value: _filterFireStation,
                            items: _fireStations,
                            onChanged: (v) =>
                                setState(() => _filterFireStation = v!),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _dropdown(
                          label: 'Ergebnis',
                          value: _filterInspectionResult,
                          items: _inspectionResults,
                          displayNames: {
                            for (final r in _inspectionResults)
                              r: r == 'Alle' ? 'Alle' : _inspectionResultName(r)
                          },
                          onChanged: (v) =>
                              setState(() => _filterInspectionResult = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _dateRangeRow(),
                ],
              ),
            ),
          ),
        ),
        _countBadge(filtered.length),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState()
              : _inspectionList(filtered),
        ),
        _exportButtons(
          isEmpty: filtered.isEmpty,
          label: 'Prüfungshistorie',
          onExcel: (_) => ExportService.exportInspectionsExcel(
              context, filtered,
              title: _inspectionTitle(),
              equipmentById: _equipmentById),
          onPdf: (withStats) => ExportService.exportInspectionsPdf(
              context, filtered,
              title: _inspectionTitle(),
              withStatsSummary: withStats,
              equipmentById: _equipmentById),
          onEmail: (withStats) => ExportService.exportInspectionsPdf(
              context, filtered,
              title: _inspectionTitle(),
              withStatsSummary: withStats,
              equipmentById: _equipmentById),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _dateRangeRow() {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickDateRange,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _hasDateFilter
                    ? '${_dateFrom != null ? _dateFmt.format(_dateFrom!) : '…'}'
                        '  –  '
                        '${_dateTo != null ? _dateFmt.format(_dateTo!) : '…'}'
                    : 'Zeitraum wählen',
                style: TextStyle(
                  fontSize: 13,
                  color: _hasDateFilter
                      ? cs.onSurface
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
            if (_hasDateFilter)
              GestureDetector(
                onTap: () => setState(() {
                  _dateFrom = null;
                  _dateTo = null;
                }),
                child: Icon(Icons.clear,
                    size: 16, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _countBadge(int count) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count Einträge',
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('werden exportiert',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  // Zeigt ein Bottom Sheet mit Zusammenfassung-Checkbox, dann exportiert
  Future<void> _showExportSheet({
    required bool isEmpty,
    required String label,
    required Future<void> Function(bool withStats) onExcel,
    required Future<void> Function(bool withStats) onPdf,
    required Future<void> Function(bool withStats) onEmail,
  }) async {
    if (isEmpty) return;
    bool withStats = false;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text('Exportieren: $label',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              // Zusammenfassung-Checkbox
              CheckboxListTile(
                value: withStats,
                onChanged: (v) => setSheetState(() => withStats = v ?? false),
                title: const Text('Statistik-Zusammenfassung'),
                subtitle: const Text('Extra Seite mit Auswertung vorne'),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('Als Excel speichern'),
                onTap: () {
                  Navigator.pop(ctx);
                  onExcel(withStats);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Als PDF speichern'),
                onTap: () {
                  Navigator.pop(ctx);
                  onPdf(withStats);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Per E-Mail / Teilen'),
                onTap: () {
                  Navigator.pop(ctx);
                  onEmail(withStats);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exportButtons({
    required bool isEmpty,
    required String label,
    required Future<void> Function(bool withStats) onExcel,
    required Future<void> Function(bool withStats) onPdf,
    required Future<void> Function(bool withStats) onEmail,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
            top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isEmpty
                    ? null
                    : () => _showExportSheet(
                          isEmpty: isEmpty,
                          label: label,
                          onExcel: onExcel,
                          onPdf: onPdf,
                          onEmail: onEmail,
                        ),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Exportieren…'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text('Keine Einträge gefunden',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextButton(
              onPressed: _resetFilters,
              child: const Text('Filter zurücksetzen')),
        ],
      ),
    );
  }

  // ── Listen ────────────────────────────────────────────────────────────────

  Widget _equipmentList(List<EquipmentModel> list) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        final e = list[i];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor:
                EquipmentStatus.getStatusColor(e.status).withOpacity(0.15),
            child: Icon(EquipmentStatus.getStatusIcon(e.status),
                size: 18,
                color: EquipmentStatus.getStatusColor(e.status)),
          ),
          title: Text(e.article,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          subtitle: Text('${e.owner} · ${e.fireStation} · ${e.size}',
              style: const TextStyle(fontSize: 12)),
          trailing: Text(e.status,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: EquipmentStatus.getStatusColor(e.status))),
        );
      },
    );
  }

  Widget _missionList(List<MissionModel> list) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        final m = list[i];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: cs.primaryContainer,
            child: Icon(_missionIcon(m.type),
                size: 18, color: cs.onPrimaryContainer),
          ),
          title: Text(m.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          subtitle: Text(
              '${m.location} · ${_dateFmt.format(m.startTime)}',
              style: const TextStyle(fontSize: 12)),
          trailing: Text(_missionTypeName(m.type),
              style: const TextStyle(fontSize: 11)),
        );
      },
    );
  }

  Widget _inspectionList(List<EquipmentInspectionModel> list) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        final ins = list[i];
        final eq = _equipmentById[ins.equipmentId];
        final resultKey = ins.result.toString().split('.').last;
        final resultName = _inspectionResultName(resultKey);
        final resultColor = ins.result == InspectionResult.passed
            ? Colors.green
            : ins.result == InspectionResult.conditionalPass
                ? Colors.orange
                : Colors.red;
        final hasIssues = ins.issues != null && ins.issues!.isNotEmpty;

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: resultColor.withOpacity(0.15),
            child: Icon(Icons.fact_check, size: 18, color: resultColor),
          ),
          title: Text(
            eq != null
                ? '${eq.article} – ${eq.owner}'
                : ins.equipmentId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            [
              if (eq != null) eq.fireStation,
              ins.inspector,
              _dateFmt.format(ins.inspectionDate),
              if (hasIssues) '${ins.issues!.length} Mängel',
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(resultName,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: resultColor)),
        );
      },
    );
  }

  // ── Dropdown ──────────────────────────────────────────────────────────────

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? displayNames,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
      items: items
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(
                  displayNames?[s] ?? s,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
