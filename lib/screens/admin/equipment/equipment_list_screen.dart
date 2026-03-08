// screens/admin/equipment/equipment_list_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Lists/fire_stations.dart';
import '../../../models/equipment_model.dart';
import '../../../models/user_models.dart';
import '../../../services/equipment_service.dart';
import '../../../services/permission_service.dart';
import '../../add_equipment_screen.dart';
import 'equipment_detail_screen.dart';
import '../../../services/export_service.dart';

// ── Gruppierungsmodus ─────────────────────────────────────────────────────────
enum _GroupMode { owner, status, station }

class EquipmentListScreen extends StatefulWidget {
  const EquipmentListScreen({Key? key}) : super(key: key);

  @override
  State<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;

  String _searchQuery = '';
  String _filterFireStation = 'Alle';
  String _filterType = 'Alle';
  String _filterStatus = 'Alle';
  _GroupMode _groupMode = _GroupMode.owner;
  bool _selectionMode = false;
  final Set<String> _selectedEquipmentIds = {};
  bool _isProcessingBatch = false;
  List<EquipmentModel> _lastEquipmentSnapshot = [];

  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];
  final List<String> _types = ['Alle', 'Jacke', 'Hose'];
  final List<String> _statusOptions = ['Alle', ...EquipmentStatus.values];

  bool get _canEdit =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentEdit == true;
  bool get _canAdd =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentAdd == true;
  bool get _canDelete =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentDelete == true;
  bool get _canSeeAllStations =>
      _currentUser?.isAdmin == true ||
      (_currentUser?.permissions.visibleFireStations.contains('*') == true) ||
      (_currentUser?.permissions.visibleFireStations.isNotEmpty == true);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _permissionService.getCurrentUser();
    if (mounted) setState(() => _currentUser = user);
  }

  List<EquipmentModel> _getFilteredEquipment(List<EquipmentModel> list) {
    var filtered = List<EquipmentModel>.from(list);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((e) =>
              e.nfcTag.toLowerCase().contains(q) ||
              (e.barcode?.toLowerCase().contains(q) ?? false) ||
              e.owner.toLowerCase().contains(q) ||
              e.size.toLowerCase().contains(q) ||
              e.article.toLowerCase().contains(q))
          .toList();
    }

    if (_filterFireStation != 'Alle' && _canSeeAllStations) {
      filtered =
          filtered.where((e) => e.fireStation == _filterFireStation).toList();
    }
    if (_filterType != 'Alle') {
      filtered = filtered.where((e) => e.type == _filterType).toList();
    }
    if (_filterStatus != 'Alle') {
      filtered = filtered.where((e) => e.status == _filterStatus).toList();
    }

    return filtered;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_currentUser!.isAdmin && !_currentUser!.permissions.equipmentView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Einsatzkleidung')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('Keine Berechtigung für Einsatzkleidung',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatzkleidung'),
        actions: [
          if (_selectionMode && _canEdit) ...[
            if (_selectedEquipmentIds.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.local_laundry_service),
                onPressed: _showCleaningReceiptDialog,
                tooltip: 'Reinigungsschein',
              ),
            IconButton(
              icon: const Icon(Icons.change_circle),
              onPressed: _showBatchStatusUpdateDialog,
              tooltip: 'Status ändern',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedEquipmentIds.clear();
                _selectionMode = false;
              }),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _showFilterDialog,
              tooltip: 'Filter',
            ),
        ],
      ),
      body: _isProcessingBatch
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Suchfeld ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Suchen',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _searchQuery = ''),
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),

                // ── Aktive Filter Chips ────────────────────────────────
                if (_filterFireStation != 'Alle' ||
                    _filterType != 'Alle' ||
                    _filterStatus != 'Alle')
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        if (_filterFireStation != 'Alle')
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(_filterFireStation),
                              deleteIcon: const Icon(Icons.clear, size: 16),
                              onDeleted: () =>
                                  setState(() => _filterFireStation = 'Alle'),
                            ),
                          ),
                        if (_filterType != 'Alle')
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(_filterType),
                              deleteIcon: const Icon(Icons.clear, size: 16),
                              onDeleted: () =>
                                  setState(() => _filterType = 'Alle'),
                            ),
                          ),
                        if (_filterStatus != 'Alle')
                          Chip(
                            label: Text(_filterStatus),
                            deleteIcon: const Icon(Icons.clear, size: 16),
                            onDeleted: () =>
                                setState(() => _filterStatus = 'Alle'),
                          ),
                      ],
                    ),
                  ),

                // ── Gruppierungs-Toggle ────────────────────────────────
                _buildGroupToggle(),
                const SizedBox(height: 4),

                // ── Equipment-Liste ────────────────────────────────────
                Expanded(
                  child: StreamBuilder<List<EquipmentModel>>(
                    stream: _equipmentService.getEquipmentByUserAccess(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: Text('Fehler: ${snapshot.error}',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error)));
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                            child: Text('Keine Einsatzkleidung vorhanden'));
                      }

                      final filtered =
                          _getFilteredEquipment(snapshot.data!);
                      // Snapshot für Reinigungsschein-Zugriff zwischenspeichern
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _lastEquipmentSnapshot != snapshot.data!) {
                          setState(() => _lastEquipmentSnapshot = snapshot.data!);
                        }
                      });

                      if (filtered.isEmpty) {
                        return const Center(
                            child: Text(
                                'Keine Einsatzkleidung entspricht den Filterkriterien'));
                      }

                      return _buildGroupedList(filtered, _groupMode);
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _selectionMode && _canEdit
          ? (_selectedEquipmentIds.isNotEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'fab_cleaning',
                      onPressed: _showCleaningReceiptDialog,
                      label: const Text('Reinigungsschein'),
                      icon: const Icon(Icons.local_laundry_service),
                      backgroundColor: Colors.blue,
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.extended(
                      heroTag: 'fab_status',
                      onPressed: _showBatchStatusUpdateDialog,
                      label: const Text('Status ändern'),
                      icon: const Icon(Icons.change_circle),
                    ),
                  ],
                )
              : null)
          : (_canAdd
              ? FloatingActionButton(
                  heroTag: 'fab_add',
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const AddEquipmentScreen())),
                  tooltip: 'Einsatzkleidung hinzufügen',
                  child: const Icon(Icons.add),
                )
              : null),
    );
  }

  // ── Gruppierungs-Toggle ───────────────────────────────────────────────────

  Widget _buildGroupToggle() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _toggleBtn(_GroupMode.owner,   Icons.person_outline,                  'Besitzer'),
            _toggleBtn(_GroupMode.status,  Icons.swap_horiz,                      'Status'),
            _toggleBtn(_GroupMode.station, Icons.local_fire_department_outlined,  'Ortswehr'),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn(_GroupMode mode, IconData icon, String label) {
    final selected = _groupMode == mode;
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _groupMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.normal,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Haupt-List-Builder ────────────────────────────────────────────────────

  Widget _buildGroupedList(List<EquipmentModel> list, _GroupMode mode) {
    String Function(EquipmentModel) keyOf;
    switch (mode) {
      case _GroupMode.owner:   keyOf = (e) => e.owner;        break;
      case _GroupMode.status:  keyOf = (e) => e.status;       break;
      case _GroupMode.station: keyOf = (e) => e.fireStation;  break;
    }

    final Map<String, List<EquipmentModel>> groups = {};
    for (final e in list) {
      groups.putIfAbsent(keyOf(e), () => []).add(e);
    }

    // Sortierung: Status nach Priorität, sonst alphabetisch
    List<String> keys;
    if (mode == _GroupMode.status) {
      const order = [
        'Einsatzbereit', 'In der Reinigung', 'In Reparatur', 'Ausgemustert'
      ];
      keys = groups.keys.toList()
        ..sort((a, b) {
          final ai = order.indexOf(a);
          final bi = order.indexOf(b);
          if (ai == -1 && bi == -1) return a.compareTo(b);
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });
    } else {
      keys = groups.keys.toList()..sort();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key    = keys[i];
        final items  = groups[key]!;
        final cs     = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        // Header-Farben je nach Modus
        final Color hdrBg = mode == _GroupMode.status
            ? _statusChipColor(key, isDark)
            : (isDark
                ? cs.primaryContainer.withOpacity(0.25)
                : cs.primaryContainer);
        final Color hdrFg = mode == _GroupMode.status
            ? _statusChipTextColor(key, isDark)
            : (isDark ? cs.onSurface : cs.onPrimaryContainer);

        // Header-Icon
        Widget headerIcon;
        switch (mode) {
          case _GroupMode.owner:
            headerIcon = CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary,
              child: Text(
                key.isNotEmpty ? key[0].toUpperCase() : '?',
                style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            );
            break;
          case _GroupMode.status:
            headerIcon =
                Icon(_statusIcon(key), size: 18, color: hdrFg);
            break;
          case _GroupMode.station:
            headerIcon = Icon(Icons.local_fire_department,
                size: 18,
                color:
                    isDark ? cs.onSurface : cs.onPrimaryContainer);
            break;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: isDark ? cs.surfaceContainer : Colors.white,
            elevation: isDark ? 0 : 2,
            shadowColor: cs.shadow.withOpacity(0.08),
            clipBehavior: Clip.hardEdge,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isDark
                  ? BorderSide(color: cs.outlineVariant, width: 1)
                  : BorderSide.none,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Gruppen-Header ───────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: hdrBg,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? cs.outlineVariant.withOpacity(0.5)
                            : cs.primary.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      headerIcon,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          key,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: hdrFg,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: mode == _GroupMode.status
                              ? hdrFg.withOpacity(0.15)
                              : cs.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${items.length}',
                          style: TextStyle(
                            color: mode == _GroupMode.status
                                ? hdrFg
                                : cs.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Items ────────────────────────────────────────────
                ...items.asMap().entries.map((entry) {
                  final idx  = entry.key;
                  final item = entry.value;
                  return Column(
                    children: [
                      if (idx > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: 60,
                          color: cs.outlineVariant.withOpacity(0.4),
                        ),
                      _buildEquipmentTile(item, groupMode: mode),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // Originale Methode bleibt für etwaige externe Aufrufe erhalten
  Widget _buildEquipmentItem(EquipmentModel equipment) =>
      _buildEquipmentTile(equipment, groupMode: _groupMode);

  // ── Equipment-Tile ────────────────────────────────────────────────────────

  Widget _buildEquipmentTile(EquipmentModel equipment,
      {required _GroupMode groupMode}) {
    final isSelected = _selectedEquipmentIds.contains(equipment.id);
    final isOverdue  = equipment.checkDate.isBefore(DateTime.now());
    final cs         = Theme.of(context).colorScheme;
    final isDark     = Theme.of(context).brightness == Brightness.dark;

    final Color accentColor = isSelected
        ? cs.primary
        : isOverdue
            ? Colors.red
            : Colors.transparent;

    final String status    = equipment.status;
    final Color  chipColor = _statusChipColor(status, isDark);
    final Color  chipText  = _statusChipTextColor(status, isDark);

    final bool  isJacke = equipment.type == 'Jacke';
    final Color iconBg  = isJacke
        ? (isDark ? const Color(0xFF1A3A5C) : const Color(0xFFDBEAFB))
        : (isDark ? const Color(0xFF4D3000) : const Color(0xFFFFF0CC));
    final Color iconFg  = isJacke
        ? (isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0))
        : (isDark ? const Color(0xFFFFCC02) : const Color(0xFFE65100));

    // Redundante Infos je nach aktiver Gruppierung ausblenden
    final bool showOwner   = groupMode != _GroupMode.owner;
    final bool showStatus  = groupMode != _GroupMode.status;
    final bool showStation = groupMode != _GroupMode.station;

    return InkWell(
      onTap: () {
        if (_selectionMode && _canEdit) {
          setState(() {
            if (isSelected) {
              _selectedEquipmentIds.remove(equipment.id);
              if (_selectedEquipmentIds.isEmpty) _selectionMode = false;
            } else {
              _selectedEquipmentIds.add(equipment.id);
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EquipmentDetailScreen(equipment: equipment),
            ),
          );
        }
      },
      onLongPress: _canEdit
          ? () => setState(() {
                _selectionMode = true;
                _selectedEquipmentIds.add(equipment.id);
              })
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withOpacity(isDark ? 0.15 : 0.07)
              : null,
          border: Border(left: BorderSide(color: accentColor, width: 3)),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Typ-Icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                isJacke
                    ? Icons.accessibility_new
                    : Icons.airline_seat_legroom_normal,
                color: iconFg,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    equipment.article,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (showOwner) equipment.owner,
                      'Gr. ${equipment.size}',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showStation) ...[
                    const SizedBox(height: 1),
                    Text(
                      equipment.fireStation,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                  ],
                  if (showStatus) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: chipColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: chipText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_selectionMode)
              Icon(
                isSelected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
                size: 22,
              )
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: cs.onSurfaceVariant.withOpacity(0.5),
              ),
          ],
        ),
      ),
    );
  }

  // ── Filter-Dialog ─────────────────────────────────────────────────────────

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Filter'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_canSeeAllStations) ...[
                  const Text('Ortswehr',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _filterFireStation,
                    items: _fireStations
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _filterFireStation = v ?? 'Alle');
                      setDialogState(() {});
                    },
                    decoration: const InputDecoration(
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Typ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterType,
                  items: _types
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _filterType = v ?? 'Alle');
                    setDialogState(() {});
                  },
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('Status',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterStatus,
                  items: _statusOptions
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Row(children: [
                            if (s != 'Alle') ...[
                              Icon(EquipmentStatus.getStatusIcon(s),
                                  size: 16,
                                  color:
                                      EquipmentStatus.getStatusColor(s)),
                              const SizedBox(width: 8),
                            ],
                            Text(s),
                          ])))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _filterStatus = v ?? 'Alle');
                    setDialogState(() {});
                  },
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _filterFireStation = 'Alle';
                _filterType = 'Alle';
                _filterStatus = 'Alle';
              });
              Navigator.pop(context);
            },
            child: const Text('Zurücksetzen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  // ── Batch-Aktionen ────────────────────────────────────────────────────────

  void _showCleaningReceiptDialog() {
    if (_selectedEquipmentIds.isEmpty) return;

    // Snapshot der aktuell geladenen Daten holen — wird im StreamBuilder verwendet
    // Daher über separate Methode mit dem letzten bekannten Stream-Snapshot
    _generateCleaningReceiptForSelected();
  }

  Future<void> _generateCleaningReceiptForSelected() async {
    final items = _lastEquipmentSnapshot
        .where((e) => _selectedEquipmentIds.contains(e.id))
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Keine Kleidungsstücke gefunden'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isProcessingBatch = true);
    try {
      await ExportService.exportStandaloneCleaningReceiptPdf(
        context,
        items,
        title: 'Reinigungsschein',
      );
      if (mounted) {
        setState(() {
          _selectedEquipmentIds.clear();
          _selectionMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessingBatch = false);
    }
  }

  void _showBatchStatusUpdateDialog() {
    if (!_canEdit) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Status ändern'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Status für ${_selectedEquipmentIds.length} Ausrüstungsgegenstände ändern:'),
            const SizedBox(height: 16),
            ...EquipmentStatus.values.map((s) => ListTile(
                  leading: Icon(EquipmentStatus.getStatusIcon(s),
                      color: EquipmentStatus.getStatusColor(s)),
                  title: Text(s),
                  onTap: () {
                    Navigator.pop(context);
                    _updateStatusForSelected(s);
                  },
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
        ],
      ),
    );
  }

  Future<void> _updateStatusForSelected(String newStatus) async {
    setState(() => _isProcessingBatch = true);
    try {
      await _equipmentService.updateStatusBatch(
          _selectedEquipmentIds.toList(), newStatus);
      if (mounted) {
        setState(() {
          _selectedEquipmentIds.clear();
          _selectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Status erfolgreich aktualisiert'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessingBatch = false);
    }
  }

  // ── Status-Hilfsmethoden ──────────────────────────────────────────────────

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Einsatzbereit':    return Icons.check_circle_outline;
      case 'In der Reinigung': return Icons.local_laundry_service;
      case 'In Reparatur':     return Icons.build_outlined;
      case 'Ausgemustert':     return Icons.archive_outlined;
      default:                 return Icons.help_outline;
    }
  }

  Color _statusChipColor(String status, bool isDark) {
    switch (status) {
      case 'Einsatzbereit':
        return isDark ? const Color(0xFF1B3A2A) : const Color(0xFFDCF5E7);
      case 'In der Reinigung':
        return isDark ? const Color(0xFF1A2F4A) : const Color(0xFFDCEEFB);
      case 'In Reparatur':
        return isDark ? const Color(0xFF3D2800) : const Color(0xFFFFF3CC);
      case 'Ausgemustert':
        return isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFE5E5);
      default:
        return isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);
    }
  }

  Color _statusChipTextColor(String status, bool isDark) {
    switch (status) {
      case 'Einsatzbereit':
        return isDark ? const Color(0xFF6FCF97) : const Color(0xFF1B6B3A);
      case 'In der Reinigung':
        return isDark ? const Color(0xFF64B5F6) : const Color(0xFF0D5A8E);
      case 'In Reparatur':
        return isDark ? const Color(0xFFFFCC02) : const Color(0xFF7A4F00);
      case 'Ausgemustert':
        return isDark ? const Color(0xFFEF9A9A) : const Color(0xFF8B1A1A);
      default:
        return isDark ? const Color(0xFFAAAAAA) : const Color(0xFF555555);
    }
  }
}
