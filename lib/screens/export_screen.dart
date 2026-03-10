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

  List<EquipmentModel> _allEquipment = [];
  List<MissionModel> _allMissions = [];
  List<EquipmentInspectionModel> _allInspections = [];
  Map<String, EquipmentModel> _equipmentById = {};
  bool _isLoading = true;
  bool _isExporting = false; // Guard: verhindert doppelten Dialog-Aufruf

  // ── Pro-Tab eigene Filter ─────────────────────────────────────────────────

  // Vorschau aufgeklappt?
  bool _eqPreviewExpanded = false;
  bool _mPreviewExpanded  = false;
  bool _iPreviewExpanded  = false;

  // Spezial-Tab
  int  _dueDays           = 30;
  bool _dueExpanded       = false;
  bool _ownerExpanded     = false;
  bool _yearlyExpanded    = false;
  bool _labelExpanded       = false;
  int  _labelYear           = DateTime.now().year;

  // Kleidung
  String _eqFireStation = 'Alle';
  String _eqType        = 'Alle';
  String _eqStatus      = 'Alle';
  DateTime? _eqDateFrom;
  DateTime? _eqDateTo;
  bool _eqWithStats     = false;

  // Einsätze
  String _mFireStation  = 'Alle';
  String _mType         = 'Alle';
  DateTime? _mDateFrom;
  DateTime? _mDateTo;
  bool _mWithStats      = false;

  // Prüfungen
  String _iFireStation  = 'Alle';
  String _iResult       = 'Alle';
  DateTime? _iDateFrom;
  DateTime? _iDateTo;
  bool _iWithStats      = false;

  // ── Listen ────────────────────────────────────────────────────────────────
  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];
  final List<String> _types        = ['Alle', 'Jacke', 'Hose'];
  final List<String> _statusOpts   = ['Alle', ...EquipmentStatus.values];
  final List<String> _missionTypes = [
    'Alle', 'fire', 'technical', 'hazmat', 'water', 'training', 'other'
  ];
  final List<String> _inspResults  = [
    'Alle', 'passed', 'conditionalPass', 'failed'
  ];

  bool get _canSeeAllStations =>
      _currentUser?.isAdmin == true ||
      (_currentUser?.permissions.visibleFireStations.contains('*') == true);

  // ── Filter-Logik ──────────────────────────────────────────────────────────

  List<EquipmentModel> get _filteredEquipment => _allEquipment.where((e) {
        if (_eqFireStation != 'Alle' && e.fireStation != _eqFireStation) return false;
        if (_eqType != 'Alle' && e.type != _eqType) return false;
        if (_eqStatus != 'Alle' && e.status != _eqStatus) return false;
        if (_eqDateFrom != null && e.createdAt.isBefore(_eqDateFrom!)) return false;
        if (_eqDateTo != null && e.createdAt.isAfter(_eqDateTo!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();

  List<MissionModel> get _filteredMissions => _allMissions.where((m) {
        if (_mFireStation != 'Alle' &&
            m.fireStation != _mFireStation &&
            !m.involvedFireStations.contains(_mFireStation)) return false;
        if (_mType != 'Alle' && m.type != _mType) return false;
        if (_mDateFrom != null && m.startTime.isBefore(_mDateFrom!)) return false;
        if (_mDateTo != null && m.startTime.isAfter(_mDateTo!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();

  List<EquipmentInspectionModel> get _filteredInspections =>
      _allInspections.where((i) {
        if (_iFireStation != 'Alle' && _equipmentById.isNotEmpty) {
          final eq = _equipmentById[i.equipmentId];
          if (eq != null && eq.fireStation != _iFireStation) return false;
        }
        if (_iResult != 'Alle') {
          if (i.result.toString().split('.').last != _iResult) return false;
        }
        if (_iDateFrom != null && i.inspectionDate.isBefore(_iDateFrom!)) return false;
        if (_iDateTo != null && i.inspectionDate.isAfter(_iDateTo!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Wrapper für alle Export-Aufrufe.
  /// Verhindert mit [_isExporting] dass ein zweiter Dialog geöffnet wird
  /// während der erste noch läuft (PDF-Generierung + BottomSheet).
  Future<void> _runExport(Future<void> Function(BuildContext ctx) fn) async {
    if (_isExporting) return;
    if (!mounted) return;
    setState(() => _isExporting = true);
    try {
      await fn(context);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final user       = await _permissionService.getCurrentUser();
      final equipment  = await _equipmentService.getEquipmentByUserAccess().first;
      final missions   = await _missionService.getMissionsForCurrentUser().first;
      final inspections = await _inspectionService.getAllInspectionsFuture();
      if (mounted) {
        setState(() {
          _currentUser    = user;
          _allEquipment   = equipment;
          _allMissions    = missions;
          _allInspections = inspections;
          _equipmentById  = {for (final e in equipment) e.id: e};
          _isLoading      = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.security, size: 18),    text: 'Kleidung'),
            Tab(icon: Icon(Icons.assignment, size: 18),  text: 'Einsätze'),
            Tab(icon: Icon(Icons.fact_check, size: 18),  text: 'Prüfungen'),
            Tab(icon: Icon(Icons.auto_awesome, size: 18), text: 'Spezial'),
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
                _buildSpecialTab(),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 – EINSATZKLEIDUNG
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEquipmentTab() {
    final filtered = _filteredEquipment;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final cs       = Theme.of(context).colorScheme;

    // Aktive Filter als Chips
    final chips = <_FilterChip>[
      if (_eqFireStation != 'Alle')
        _FilterChip(_eqFireStation, () => setState(() => _eqFireStation = 'Alle')),
      if (_eqType != 'Alle')
        _FilterChip(_eqType, () => setState(() => _eqType = 'Alle')),
      if (_eqStatus != 'Alle')
        _FilterChip(_eqStatus, () => setState(() => _eqStatus = 'Alle')),
      if (_eqDateFrom != null || _eqDateTo != null)
        _FilterChip(_dateRangeLabel(_eqDateFrom, _eqDateTo),
            () => setState(() { _eqDateFrom = null; _eqDateTo = null; })),
    ];

    return _tabLayout(
      isDark: isDark,
      cs: cs,
      summaryIcon: Icons.security,
      summaryColor: cs.primary,
      count: filtered.length,
      totalCount: _allEquipment.length,
      summaryLines: _equipmentSummaryLines(filtered),
      chips: chips,
      onFilterTap: () => _showEquipmentFilterSheet(),
      withStats: _eqWithStats,
      onWithStatsChanged: (v) => setState(() => _eqWithStats = v),
      previewExpanded: _eqPreviewExpanded,
      onPreviewToggle: () => setState(() => _eqPreviewExpanded = !_eqPreviewExpanded),
      previewItems: filtered.map((e) => _PreviewItem(
        title: e.article,
        subtitle: '${e.owner} · ${e.size}',
        meta: e.fireStation,
        statusLabel: e.status,
        statusColor: EquipmentStatus.getStatusColor(e.status),
        statusIcon: EquipmentStatus.getStatusIcon(e.status),
      )).toList(),
      onExcel: () => _runExport((ctx) => ExportService.exportToExcel(
          ctx, filtered, title: _equipmentTitle())),
      onPdf: () => _runExport((ctx) => ExportService.exportEquipmentPdf(
          ctx, filtered,
          title: _equipmentTitle(),
          withStatsSummary: _eqWithStats)),
    );
  }

  List<String> _equipmentSummaryLines(List<EquipmentModel> list) {
    if (list.isEmpty) return ['Keine Einträge'];
    final stations = list.map((e) => e.fireStation).toSet().length;
    final jacken   = list.where((e) => e.type == 'Jacke').length;
    final hosen    = list.where((e) => e.type == 'Hose').length;
    final faellig  = list.where((e) =>
        e.checkDate.isBefore(DateTime.now())).length;
    return [
      '$jacken Jacken · $hosen Hosen',
      '$stations Ortswehr${stations != 1 ? 'en' : ''}',
      if (faellig > 0) '$faellig Prüfung${faellig != 1 ? 'en' : ''} überfällig',
    ];
  }

  String _equipmentTitle() {
    final parts = <String>['Einsatzkleidung'];
    if (_eqFireStation != 'Alle') parts.add(_eqFireStation);
    if (_eqType != 'Alle') parts.add(_eqType);
    return parts.join(' – ');
  }

  Future<void> _showEquipmentFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSS) => _filterSheet(
          ctx: ctx,
          setSS: setSS,
          children: [
            if (_canSeeAllStations) ...[
              _sheetDropdown('Ortswehr', _eqFireStation, _fireStations,
                  (v) => setSS(() => _eqFireStation = v)),
              const SizedBox(height: 12),
            ],
            _sheetDropdown('Typ', _eqType, _types,
                (v) => setSS(() => _eqType = v)),
            const SizedBox(height: 12),
            _sheetDropdown('Status', _eqStatus, _statusOpts,
                (v) => setSS(() => _eqStatus = v),
                displayNames: {for (final s in _statusOpts) s: s}),
            const SizedBox(height: 12),
            _sheetDateRange(
              from: _eqDateFrom,
              to:   _eqDateTo,
              label: 'Angelegt im Zeitraum',
              onPick: (f, t) => setSS(() { _eqDateFrom = f; _eqDateTo = t; }),
            ),
          ],
          onApply: () {
            setState(() {});
            Navigator.pop(ctx);
          },
          onReset: () => setSS(() {
            _eqFireStation = 'Alle';
            _eqType        = 'Alle';
            _eqStatus      = 'Alle';
            _eqDateFrom    = null;
            _eqDateTo      = null;
          }),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 – EINSÄTZE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMissionsTab() {
    final filtered = _filteredMissions;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final cs       = Theme.of(context).colorScheme;

    final chips = <_FilterChip>[
      if (_mFireStation != 'Alle')
        _FilterChip(_mFireStation, () => setState(() => _mFireStation = 'Alle')),
      if (_mType != 'Alle')
        _FilterChip(_missionTypeName(_mType), () => setState(() => _mType = 'Alle')),
      if (_mDateFrom != null || _mDateTo != null)
        _FilterChip(_dateRangeLabel(_mDateFrom, _mDateTo),
            () => setState(() { _mDateFrom = null; _mDateTo = null; })),
    ];

    return _tabLayout(
      isDark: isDark,
      cs: cs,
      summaryIcon: Icons.assignment,
      summaryColor: Colors.deepOrange,
      count: filtered.length,
      totalCount: _allMissions.length,
      summaryLines: _missionSummaryLines(filtered),
      chips: chips,
      onFilterTap: () => _showMissionsFilterSheet(),
      withStats: _mWithStats,
      onWithStatsChanged: (v) => setState(() => _mWithStats = v),
      previewExpanded: _mPreviewExpanded,
      onPreviewToggle: () => setState(() => _mPreviewExpanded = !_mPreviewExpanded),
      previewItems: filtered.map((m) => _PreviewItem(
        title: m.name,
        subtitle: '${m.location} · ${_dateFmt.format(m.startTime)}',
        meta: m.fireStation,
        statusLabel: _missionTypeName(m.type),
        statusColor: Colors.deepOrange,
        statusIcon: _missionIcon(m.type),
      )).toList(),
      onExcel: () => _runExport((ctx) => ExportService.exportMissionsExcel(
          ctx, filtered,
          equipmentById: _equipmentById,
          title: _missionTitle())),
      onPdf: () => _runExport((ctx) => ExportService.exportMissionsPdf(
          ctx, filtered,
          equipmentById: _equipmentById,
          title: _missionTitle(),
          withStatsSummary: _mWithStats)),
    );
  }

  List<String> _missionSummaryLines(List<MissionModel> list) {
    if (list.isEmpty) return ['Keine Einträge'];
    final types   = <String, int>{};
    int totalEq   = 0;
    for (final m in list) {
      types[_missionTypeName(m.type)] = (types[_missionTypeName(m.type)] ?? 0) + 1;
      totalEq += m.equipmentIds.length;
    }
    final topType = types.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      topType.take(2).map((e) => '${e.value}× ${e.key}').join(' · '),
      '$totalEq Kleidungsstücke eingesetzt',
    ];
  }

  String _missionTitle() {
    final parts = <String>['Einsätze'];
    if (_mFireStation != 'Alle') parts.add(_mFireStation);
    if (_mType != 'Alle') parts.add(_missionTypeName(_mType));
    if (_mDateFrom != null) parts.add(_dateFmt.format(_mDateFrom!));
    return parts.join(' – ');
  }

  Future<void> _showMissionsFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSS) => _filterSheet(
          ctx: ctx,
          setSS: setSS,
          children: [
            if (_canSeeAllStations) ...[
              _sheetDropdown('Ortswehr', _mFireStation, _fireStations,
                  (v) => setSS(() => _mFireStation = v)),
              const SizedBox(height: 12),
            ],
            _sheetDropdown(
              'Einsatztyp', _mType, _missionTypes,
              (v) => setSS(() => _mType = v),
              displayNames: {
                for (final t in _missionTypes)
                  t: t == 'Alle' ? 'Alle' : _missionTypeName(t)
              },
            ),
            const SizedBox(height: 12),
            _sheetDateRange(
              from: _mDateFrom,
              to:   _mDateTo,
              label: 'Zeitraum',
              onPick: (f, t) => setSS(() { _mDateFrom = f; _mDateTo = t; }),
            ),
          ],
          onApply: () {
            setState(() {});
            Navigator.pop(ctx);
          },
          onReset: () => setSS(() {
            _mFireStation = 'Alle';
            _mType        = 'Alle';
            _mDateFrom    = null;
            _mDateTo      = null;
          }),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 – PRÜFUNGEN
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildInspectionsTab() {
    final filtered = _filteredInspections;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final cs       = Theme.of(context).colorScheme;

    final chips = <_FilterChip>[
      if (_iFireStation != 'Alle')
        _FilterChip(_iFireStation, () => setState(() => _iFireStation = 'Alle')),
      if (_iResult != 'Alle')
        _FilterChip(_inspectionResultName(_iResult),
            () => setState(() => _iResult = 'Alle')),
      if (_iDateFrom != null || _iDateTo != null)
        _FilterChip(_dateRangeLabel(_iDateFrom, _iDateTo),
            () => setState(() { _iDateFrom = null; _iDateTo = null; })),
    ];

    return _tabLayout(
      isDark: isDark,
      cs: cs,
      summaryIcon: Icons.fact_check,
      summaryColor: Colors.teal,
      count: filtered.length,
      totalCount: _allInspections.length,
      summaryLines: _inspectionSummaryLines(filtered),
      chips: chips,
      onFilterTap: () => _showInspectionsFilterSheet(),
      withStats: _iWithStats,
      onWithStatsChanged: (v) => setState(() => _iWithStats = v),
      previewExpanded: _iPreviewExpanded,
      onPreviewToggle: () => setState(() => _iPreviewExpanded = !_iPreviewExpanded),
      previewItems: filtered.map((ins) {
        final eq = _equipmentById[ins.equipmentId];
        final resultKey = ins.result.toString().split('.').last;
        final color = ins.result == InspectionResult.passed
            ? Colors.green
            : ins.result == InspectionResult.conditionalPass
                ? Colors.orange
                : Colors.red;
        return _PreviewItem(
          title: eq != null ? '${eq.article} – ${eq.owner}' : ins.equipmentId,
          subtitle: '${ins.inspector} · ${_dateFmt.format(ins.inspectionDate)}',
          meta: eq?.fireStation ?? '',
          statusLabel: _inspectionResultName(resultKey),
          statusColor: color,
          statusIcon: Icons.fact_check,
        );
      }).toList(),
      onExcel: () => _runExport((ctx) => ExportService.exportInspectionsExcel(
          ctx, filtered,
          title: _inspectionTitle(),
          equipmentById: _equipmentById)),
      onPdf: () => _runExport((ctx) => ExportService.exportInspectionsPdf(
          ctx, filtered,
          title: _inspectionTitle(),
          withStatsSummary: _iWithStats,
          equipmentById: _equipmentById)),
    );
  }

  List<String> _inspectionSummaryLines(List<EquipmentInspectionModel> list) {
    if (list.isEmpty) return ['Keine Einträge'];
    final passed  = list.where((i) => i.result == InspectionResult.passed).length;
    final failed  = list.where((i) => i.result == InspectionResult.failed).length;
    final rate    = list.isNotEmpty
        ? (passed / list.length * 100).toStringAsFixed(0)
        : '0';
    return [
      '$passed bestanden · $failed nicht bestanden',
      'Bestandsquote $rate%',
    ];
  }

  String _inspectionTitle() {
    final parts = <String>['Prüfungshistorie'];
    if (_iFireStation != 'Alle') parts.add(_iFireStation);
    if (_iResult != 'Alle') parts.add(_inspectionResultName(_iResult));
    return parts.join(' – ');
  }

  Future<void> _showInspectionsFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSS) => _filterSheet(
          ctx: ctx,
          setSS: setSS,
          children: [
            if (_canSeeAllStations) ...[
              _sheetDropdown('Ortswehr', _iFireStation, _fireStations,
                  (v) => setSS(() => _iFireStation = v)),
              const SizedBox(height: 12),
            ],
            _sheetDropdown(
              'Ergebnis', _iResult, _inspResults,
              (v) => setSS(() => _iResult = v),
              displayNames: {
                for (final r in _inspResults)
                  r: r == 'Alle' ? 'Alle' : _inspectionResultName(r)
              },
            ),
            const SizedBox(height: 12),
            _sheetDateRange(
              from: _iDateFrom,
              to:   _iDateTo,
              label: 'Zeitraum',
              onPick: (f, t) => setSS(() { _iDateFrom = f; _iDateTo = t; }),
            ),
          ],
          onApply: () {
            setState(() {});
            Navigator.pop(ctx);
          },
          onReset: () => setSS(() {
            _iFireStation = 'Alle';
            _iResult      = 'Alle';
            _iDateFrom    = null;
            _iDateTo      = null;
          }),
        ),
      ),
    );
  }


  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 – SPEZIAL-EXPORTE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSpecialTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Prüfungs-Fälligkeit ────────────────────────────────────────
          _specialCard(
            isDark: isDark,
            cs: cs,
            icon: Icons.event_busy,
            color: Colors.orange,
            title: 'Prüfungs-Fälligkeitsliste',
            description: 'Alle Kleidungsstücke, deren Prüfung in den nächsten X Tagen fällig oder bereits überfällig ist.',
            expanded: _dueExpanded,
            onToggle: () => setState(() => _dueExpanded = !_dueExpanded),
            controls: _dueExpanded ? _buildDueControls(isDark, cs) : null,
            onExcel: () => _runExport((ctx) async {
              final due = _getDueItems();
              if (due.isEmpty) { _snackEmpty(); return; }
              await ExportService.exportDueInspectionsPdf(
                ctx, due, _equipmentById,
                title: 'Prüfungs-Fälligkeit',
                asExcel: true,
              );
            }),
            onPdf: () => _runExport((ctx) async {
              final due = _getDueItems();
              if (due.isEmpty) { _snackEmpty(); return; }
              await ExportService.exportDueInspectionsPdf(
                ctx, due, _equipmentById,
                title: 'Prüfungs-Fälligkeit – nächste \$_dueDays Tage',
              );
            }),
            badgeText: () {
              final c = _getDueItems().length;
              return c == 0 ? null : '$c fällig';
            }(),
            badgeColor: Colors.orange,
          ),
          const SizedBox(height: 14),

          // ── 2. Besitzer-Übersicht ─────────────────────────────────────────
          _specialCard(
            isDark: isDark,
            cs: cs,
            icon: Icons.people_outline,
            color: Colors.indigo,
            title: 'Besitzer-Übersicht',
            description: 'Pro Person: alle zugewiesenen Kleidungsstücke, Status und letzte Prüfung.',
            expanded: _ownerExpanded,
            onToggle: () => setState(() => _ownerExpanded = !_ownerExpanded),
            controls: null,
            onExcel: () => _runExport((ctx) => ExportService.exportOwnerOverviewExcel(
                ctx, _allEquipment, _equipmentById,
                title: 'Besitzer-Übersicht')),
            onPdf: () => _runExport((ctx) => ExportService.exportOwnerOverviewPdf(
                ctx, _allEquipment, _equipmentById,
                title: 'Besitzer-Übersicht')),
            badgeText: () {
              final owners = _allEquipment.map((e) => e.owner)
                  .where((o) => o.isNotEmpty).toSet().length;
              return owners == 0 ? null : '$owners Personen';
            }(),
            badgeColor: Colors.indigo,
          ),
          const SizedBox(height: 14),

          // ── 3. Jahresbericht ──────────────────────────────────────────────
          _specialCard(
            isDark: isDark,
            cs: cs,
            icon: Icons.summarize_outlined,
            color: Colors.teal,
            title: 'Jahresbericht',
            description: 'Vollständiger Jahresbericht: Kleidungsbestand, Prüfungsquote, Einsatzstatistik und überfällige Prüfungen in einem PDF.',
            expanded: _yearlyExpanded,
            onToggle: () => setState(() => _yearlyExpanded = !_yearlyExpanded),
            controls: _yearlyExpanded ? _buildYearlyControls(isDark, cs) : null,
            onExcel: null,
            onPdf: () => _runExport((ctx) => ExportService.exportYearlyReportPdf(
              ctx,
              equipment:   _allEquipment,
              missions:    _allMissions,
              inspections: _allInspections,
              equipmentById: _equipmentById,
              year: _labelYear,
            )),
            badgeText: '${_labelYear}',
            badgeColor: Colors.teal,
          ),
          const SizedBox(height: 14),

          // ── 4. Etiketten-PDF ──────────────────────────────────────────────
          _specialCard(
            isDark: isDark,
            cs: cs,
            icon: Icons.label_outline,
            color: Colors.deepPurple,
            title: 'Etiketten-PDF',
            description: 'Pro Kleidungsstück ein Etikett mit NFC-Tag als QR-Code, Artikel, Besitzer und Größe — zum Ausdrucken.',
            expanded: _labelExpanded,
            onToggle: () => setState(() => _labelExpanded = !_labelExpanded),
            controls: _labelExpanded ? _buildLabelControls(isDark, cs) : null,
            onExcel: null,
            onPdf: () => _runExport((ctx) => ExportService.exportLabelsPdf(
              ctx,
              _allEquipment,
              title: 'Etiketten',
            )),
            badgeText: '${_allEquipment.length} Etiketten',
            badgeColor: Colors.deepPurple,
          ),

        ],
      ),
    );
  }

  List<EquipmentModel> _getDueItems() {
    final cutoff = DateTime.now().add(Duration(days: _dueDays));
    return _allEquipment
        .where((e) => e.checkDate.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.checkDate.compareTo(b.checkDate));
  }

  Widget _buildYearlyControls(bool isDark, ColorScheme cs) {
    final currentYear = DateTime.now().year;
    final years = List.generate(5, (i) => currentYear - i);
    final missionsInYear = _allMissions.where(
        (m) => m.startTime.year == _labelYear).length;
    final inspInYear = _allInspections.where(
        (i) => i.inspectionDate.year == _labelYear).length;
    final eqCount = _allEquipment.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Jahr', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: years.map((y) {
              final sel = _labelYear == y;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _labelYear = y),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? Colors.teal.withOpacity(isDark ? 0.25 : 0.12)
                          : (isDark ? cs.surfaceContainerHigh : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? Colors.teal : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text('$y',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                          color: sel ? Colors.teal : cs.onSurfaceVariant,
                        )),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _miniStat('Kleidung',  '$eqCount',          Colors.teal,   isDark, cs),
            const SizedBox(width: 8),
            _miniStat('Einsätze',  '$missionsInYear',   Colors.deepOrange, isDark, cs),
            const SizedBox(width: 8),
            _miniStat('Prüfungen', '$inspInYear',       Colors.indigo, isDark, cs),
          ],
        ),
      ],
    );
  }

  Widget _buildLabelControls(bool isDark, ColorScheme cs) {
    // Filter: nur bestimmte Ortswehr
    final stations = ['Alle', ...FireStations.getAllStations()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Alle ${_allEquipment.length} Kleidungsstücke werden als Etiketten exportiert.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('Format: 4 Etiketten pro Seite (A4), QR-Code + Artikel + Besitzer + Größe.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildDueControls(bool isDark, ColorScheme cs) {
    final due      = _getDueItems();
    final overdue  = due.where((e) => e.checkDate.isBefore(DateTime.now())).length;
    final upcoming = due.length - overdue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Zeitraum', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Row(
          children: [30, 60, 90].map((days) {
            final sel = _dueDays == days;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _dueDays = days),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? Colors.orange.withOpacity(isDark ? 0.25 : 0.12)
                        : (isDark ? cs.surfaceContainerHigh : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? Colors.orange : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '$days Tage',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                      color: sel ? Colors.orange : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Mini-Statistik
        Row(
          children: [
            _miniStat('Überfällig', '$overdue', Colors.red, isDark, cs),
            const SizedBox(width: 8),
            _miniStat('Bald fällig', '$upcoming', Colors.orange, isDark, cs),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, Color color,
      bool isDark, ColorScheme cs) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _specialCard({
    required bool isDark,
    required ColorScheme cs,
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget? controls,
    required VoidCallback? onExcel,
    required VoidCallback? onPdf,
    required String? badgeText,
    required Color badgeColor,
  }) {
    return Material(
      color: isDark ? cs.surfaceContainer : Colors.white,
      elevation: isDark ? 0 : 2,
      shadowColor: cs.shadow.withOpacity(0.07),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface)),
                            ),
                            if (badgeText != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor
                                      .withOpacity(isDark ? 0.2 : 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: badgeColor.withOpacity(0.4)),
                                ),
                                child: Text(badgeText,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: badgeColor)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(description,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 20, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          // Aufklappbarer Bereich
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    children: [
                      if (controls != null) controls,
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onExcel == null ? null : onExcel,
                              icon: const Icon(
                                  Icons.table_chart_outlined, size: 16),
                              label: const Text('Excel'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 11),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: onPdf,
                              icon: const Icon(
                                  Icons.picture_as_pdf, size: 16),
                              label: const Text('Als PDF'),
                              style: FilledButton.styleFrom(
                                backgroundColor: color,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 11),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _snackEmpty() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Keine Einträge für diesen Export'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // KERN-LAYOUT PRO TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _tabLayout({
    required bool isDark,
    required ColorScheme cs,
    required IconData summaryIcon,
    required Color summaryColor,
    required int count,
    required int totalCount,
    required List<String> summaryLines,
    required List<_FilterChip> chips,
    required VoidCallback onFilterTap,
    required bool withStats,
    required ValueChanged<bool> onWithStatsChanged,
    required bool previewExpanded,
    required VoidCallback onPreviewToggle,
    required List<_PreviewItem> previewItems,
    required VoidCallback? onExcel,
    required VoidCallback? onPdf,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Zusammenfassungs-Karte ────────────────────────────────────────
          _summaryCard(
            isDark: isDark,
            cs: cs,
            icon: summaryIcon,
            color: summaryColor,
            count: count,
            totalCount: totalCount,
            lines: summaryLines,
          ),
          const SizedBox(height: 12),

          // ── Filter-Zeile ──────────────────────────────────────────────────
          _filterRow(chips: chips, onFilterTap: onFilterTap, cs: cs, isDark: isDark),
          const SizedBox(height: 12),

          // ── Aufklappbare Vorschau ─────────────────────────────────────────
          if (count > 0)
            _previewCard(
              isDark: isDark,
              cs: cs,
              expanded: previewExpanded,
              onToggle: onPreviewToggle,
              items: previewItems,
            ),
          const SizedBox(height: 12),

          // ── Export-Optionen ───────────────────────────────────────────────
          _exportCard(
            isDark: isDark,
            cs: cs,
            count: count,
            withStats: withStats,
            onWithStatsChanged: onWithStatsChanged,
            onExcel: count == 0 ? null : onExcel,
            onPdf:   count == 0 ? null : onPdf,
          ),
        ],
      ),
    );
  }

  // ── Zusammenfassungs-Karte ────────────────────────────────────────────────

  Widget _summaryCard({
    required bool isDark,
    required ColorScheme cs,
    required IconData icon,
    required Color color,
    required int count,
    required int totalCount,
    required List<String> lines,
  }) {
    return Material(
      color: isDark ? cs.surfaceContainer : Colors.white,
      elevation: isDark ? 0 : 2,
      shadowColor: cs.shadow.withOpacity(0.07),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isDark
            ? BorderSide(color: cs.outlineVariant)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            // Zahlen + Beschreibung
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: count == 0 ? cs.outlineVariant : cs.onSurface,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (count != totalCount)
                        Text(
                          'von $totalCount',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...lines.map((l) => Text(
                        l,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter-Zeile mit Chips ────────────────────────────────────────────────

  Widget _filterRow({
    required List<_FilterChip> chips,
    required VoidCallback onFilterTap,
    required ColorScheme cs,
    required bool isDark,
  }) {
    return Row(
      children: [
        // Filter-Button
        InkWell(
          onTap: onFilterTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: chips.isNotEmpty
                  ? cs.primaryContainer
                  : (isDark ? cs.surfaceContainerHigh : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: chips.isNotEmpty ? cs.primary : cs.outlineVariant,
                width: chips.isNotEmpty ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune,
                    size: 16,
                    color: chips.isNotEmpty ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Filter',
                  style: TextStyle(
                    fontSize: 13,
                    color: chips.isNotEmpty ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: chips.isNotEmpty
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Aktive Filter als Chips
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chips
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          label: Text(c.label,
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: c.onRemove,
                          deleteIconColor: cs.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: isDark
                              ? cs.surfaceContainerHigh
                              : Colors.grey.shade100,
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── Export-Karte ──────────────────────────────────────────────────────────

  Widget _exportCard({
    required bool isDark,
    required ColorScheme cs,
    required int count,
    required bool withStats,
    required ValueChanged<bool> onWithStatsChanged,
    required VoidCallback? onExcel,
    required VoidCallback? onPdf,
  }) {
    final empty = count == 0;
    return Material(
      color: isDark ? cs.surfaceContainer : Colors.white,
      elevation: isDark ? 0 : 2,
      shadowColor: cs.shadow.withOpacity(0.07),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isDark
            ? BorderSide(color: cs.outlineVariant)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.upload_file,
                      size: 16, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('Exportieren',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                if (!empty) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count Einträge',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),

            if (empty) ...[
              const SizedBox(height: 12),
              Text('Keine Einträge – Filter anpassen',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13)),
            ] else ...[

              const SizedBox(height: 14),

              // Statistik-Toggle
              InkWell(
                onTap: () => onWithStatsChanged(!withStats),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 20,
                        child: Switch.adaptive(
                          value: withStats,
                          onChanged: onWithStatsChanged,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Statistik-Auswertung im PDF',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface)),
                            Text(
                              'Fügt eine Seite mit Auswertungen vorne an',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Export-Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onExcel,
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: const Text('Excel'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('Als PDF exportieren'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FILTER BOTTOM SHEET
  // ══════════════════════════════════════════════════════════════════════════

  Widget _filterSheet({
    required BuildContext ctx,
    required StateSetter setSS,
    required List<Widget> children,
    required VoidCallback onApply,
    required VoidCallback onReset,
  }) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Filter',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                TextButton(
                    onPressed: onReset,
                    child: const Text('Zurücksetzen')),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onApply,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Anwenden'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetDropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> onChanged, {
    Map<String, String>? displayNames,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
      items: items
          .map((i) => DropdownMenuItem(
                value: i,
                child: Text(displayNames?[i] ?? i),
              ))
          .toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }

  Widget _sheetDateRange({
    required DateTime? from,
    required DateTime? to,
    required String label,
    required void Function(DateTime?, DateTime?) onPick,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasDate = from != null || to != null;

    return InkWell(
      onTap: () async {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: (from != null && to != null)
              ? DateTimeRange(start: from, end: to)
              : null,
        );
        if (range != null) {
          onPick(range.start, range.end);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
              color: hasDate ? cs.primary : cs.outline,
              width: hasDate ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range,
                size: 18,
                color: hasDate ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasDate
                    ? '${from != null ? _dateFmt.format(from) : '…'}  –  ${to != null ? _dateFmt.format(to) : '…'}'
                    : label,
                style: TextStyle(
                  fontSize: 14,
                  color: hasDate ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ),
            if (hasDate)
              GestureDetector(
                onTap: () => onPick(null, null),
                child: Icon(Icons.clear,
                    size: 16, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HILFSMETHODEN
  // ══════════════════════════════════════════════════════════════════════════

  String _dateRangeLabel(DateTime? from, DateTime? to) {
    if (from != null && to != null) {
      return '${_dateFmt.format(from)} – ${_dateFmt.format(to)}';
    } else if (from != null) {
      return 'ab ${_dateFmt.format(from)}';
    } else if (to != null) {
      return 'bis ${_dateFmt.format(to)}';
    }
    return '';
  }

  String _missionTypeName(String type) {
    const names = {
      'fire': 'Brandeinsatz', 'technical': 'Techn. Hilfeleistung',
      'hazmat': 'Gefahrgut',  'water': 'Wasser/Sturm',
      'training': 'Übung',    'other': 'Sonstige',
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
}


  // ── Aufklappbare Vorschau-Karte ───────────────────────────────────────────

  Widget _previewCard({
    required bool isDark,
    required ColorScheme cs,
    required bool expanded,
    required VoidCallback onToggle,
    required List<_PreviewItem> items,
  }) {
    const previewMax = 5;

    return Material(
      color: isDark ? cs.surfaceContainer : Colors.white,
      elevation: isDark ? 0 : 2,
      shadowColor: cs.shadow.withOpacity(0.07),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isDark ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      child: Column(
        children: [
          // Header-Zeile (immer sichtbar)
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.list_alt,
                        size: 16, color: cs.onSecondaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Vorschau',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${items.length} Einträge',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 20, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          // Aufklappbarer Inhalt
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
                ...items.take(previewMax).toList().asMap().entries.map((e) {
                  final idx  = e.key;
                  final item = e.value;
                  final isLast = idx == (items.length > previewMax
                      ? previewMax - 1
                      : items.length - 1);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: item.statusColor
                                    .withOpacity(isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(item.statusIcon,
                                  size: 17, color: item.statusColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    item.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: item.statusColor
                                        .withOpacity(isDark ? 0.2 : 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.statusLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: item.statusColor,
                                    ),
                                  ),
                                ),
                                if (item.meta.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(item.meta,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        Divider(
                          height: 1,
                          indent: 62,
                          color: cs.outlineVariant.withOpacity(0.3),
                        ),
                    ],
                  );
                }),
                if (items.length > previewMax) ...[
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '... und ${items.length - previewMax} weitere',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _missionIcon(String type) {
    switch (type) {
      case 'fire':      return Icons.local_fire_department;
      case 'technical': return Icons.build;
      case 'hazmat':    return Icons.dangerous;
      case 'water':     return Icons.water;
      case 'training':  return Icons.school;
      default:          return Icons.assignment;
    }
  }

// ── Hilfsklasse für Filter-Chips ──────────────────────────────────────────────

class _FilterChip {
  final String label;
  final VoidCallback onRemove;
  const _FilterChip(this.label, this.onRemove);
}

class _PreviewItem {
  final String title;
  final String subtitle;
  final String meta;
  final String statusLabel;
  final Color statusColor;
  final IconData statusIcon;
  const _PreviewItem({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
  });
}
