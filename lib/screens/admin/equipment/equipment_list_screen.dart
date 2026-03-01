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
  bool _groupByOwner = true;
  bool _selectionMode = false;
  final Set<String> _selectedEquipmentIds = {};
  bool _isProcessingBatch = false;

  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];
  final List<String> _types = ['Alle', 'Jacke', 'Hose'];
  final List<String> _statusOptions = ['Alle', ...EquipmentStatus.values];

  // Abgeleitete Berechtigungen
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

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    if (!_currentUser!.isAdmin &&
        !_currentUser!.permissions.equipmentView) {
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
          IconButton(
            icon: Icon(_groupByOwner ? Icons.person : Icons.view_list),
            onPressed: () => setState(() => _groupByOwner = !_groupByOwner),
            tooltip: _groupByOwner ? 'Listenansicht' : 'Nach Besitzer gruppieren',
          ),
          if (_selectionMode && _canEdit) ...[
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
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Status wird aktualisiert...'),
                ],
              ),
            )
          : Column(
              children: [
                // Suchfeld
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Suchen',
                      hintText: 'Nach NFC, Barcode, Besitzer suchen...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),

                // Aktive Filter-Chips
                if (_filterFireStation != 'Alle' ||
                    _filterType != 'Alle' ||
                    _filterStatus != 'Alle')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_filterFireStation != 'Alle')
                          Chip(
                            label: Text(_filterFireStation),
                            avatar: Icon(FireStations.getIcon(_filterFireStation),
                                size: 16),
                            deleteIcon: const Icon(Icons.clear),
                            onDeleted: () =>
                                setState(() => _filterFireStation = 'Alle'),
                          ),
                        if (_filterType != 'Alle')
                          Chip(
                            label: Text(_filterType),
                            deleteIcon: const Icon(Icons.clear),
                            onDeleted: () =>
                                setState(() => _filterType = 'Alle'),
                          ),
                        if (_filterStatus != 'Alle')
                          Chip(
                            label: Text(_filterStatus),
                            avatar: Icon(
                                EquipmentStatus.getStatusIcon(_filterStatus),
                                size: 16,
                                color: EquipmentStatus.getStatusColor(
                                    _filterStatus)),
                            deleteIcon: const Icon(Icons.clear),
                            onDeleted: () =>
                                setState(() => _filterStatus = 'Alle'),
                          ),
                      ],
                    ),
                  ),

                // Equipment-Liste
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
                            child: Text(
                                'Fehler: ${snapshot.error}',
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

                      if (filtered.isEmpty) {
                        return const Center(
                            child: Text(
                                'Keine Einsatzkleidung entspricht den Filterkriterien'));
                      }

                      return _groupByOwner
                          ? _buildGroupedListView(filtered)
                          : _buildNormalListView(filtered);
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _selectionMode && _canEdit
          ? (_selectedEquipmentIds.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _showBatchStatusUpdateDialog,
                  label: const Text('Status ändern'),
                  icon: const Icon(Icons.change_circle),
                )
              : null)
          : (_canAdd
              ? FloatingActionButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const AddEquipmentScreen())),
                  tooltip: 'Einsatzkleidung hinzufügen',
                  child: const Icon(Icons.add),
                )
              : null),
    );
  }

  // ── Gruppierte Ansicht ────────────────────────────────────────────────────

  Widget _buildGroupedListView(List<EquipmentModel> list) {
    final Map<String, List<EquipmentModel>> groups = {};
    for (final e in list) {
      groups.putIfAbsent(e.owner, () => []).add(e);
    }
    final owners = groups.keys.toList()..sort();

    return ListView.separated(
      itemCount: owners.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final owner = owners[i];
        final items = groups[owner]!;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.15),
                      child: Text(
                        owner.isNotEmpty ? owner[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(owner,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${items.length}',
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
              ...items.map(_buildEquipmentItem),
            ],
          ),
        );
      },
    );
  }

  // ── Normale Listenansicht ─────────────────────────────────────────────────

  Widget _buildNormalListView(List<EquipmentModel> list) {
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) => _buildEquipmentItem(list[i]),
    );
  }

  // ── Equipment-Kachel ──────────────────────────────────────────────────────

  Widget _buildEquipmentItem(EquipmentModel equipment) {
    final isSelected = _selectedEquipmentIds.contains(equipment.id);
    final isOverdue = equipment.checkDate.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
          : null,
      child: InkWell(
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
                    builder: (_) =>
                        EquipmentDetailScreen(equipment: equipment)));
          }
        },
        onLongPress: _canEdit
            ? () => setState(() {
                  _selectionMode = true;
                  _selectedEquipmentIds.add(equipment.id);
                })
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (_selectionMode && _canEdit)
                Checkbox(
                  value: isSelected,
                  onChanged: (_) {
                    setState(() {
                      if (isSelected) {
                        _selectedEquipmentIds.remove(equipment.id);
                      } else {
                        _selectedEquipmentIds.add(equipment.id);
                      }
                    });
                  },
                ),
              CircleAvatar(
                backgroundColor:
                    equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
                child: Icon(
                  equipment.type == 'Jacke'
                      ? Icons.accessibility_new
                      : Icons.airline_seat_legroom_normal,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(equipment.article,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text('${equipment.owner} • Gr. ${equipment.size}',
                        style: const TextStyle(fontSize: 13)),
                    if (_canSeeAllStations)
                      Text('Ortswehr: ${equipment.fireStation}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EquipmentStatus.getStatusColor(
                                    equipment.status)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(equipment.status,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: EquipmentStatus.getStatusColor(
                                      equipment.status))),
                        ),
                        if (isOverdue) ...[
                          const SizedBox(width: 6),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Prüfung überfällig',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.red)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!_canEdit)
                const Icon(Icons.visibility, size: 16, color: Colors.grey),
            ],
          ),
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
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_canSeeAllStations) ...[
                  const Text('Ortsfeuerwehr',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _filterFireStation,
                    items: _fireStations
                        .map((s) => DropdownMenuItem(
                            value: s,
                            child: Row(children: [
                              if (s != 'Alle') ...[
                                Icon(FireStations.getIcon(s),
                                    size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 8),
                              ],
                              Text(s),
                            ])))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _filterFireStation = v ?? 'Alle'),
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
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _filterType = v ?? 'Alle'),
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
                                  color: EquipmentStatus.getStatusColor(s)),
                              const SizedBox(width: 8),
                            ],
                            Text(s),
                          ])))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _filterStatus = v ?? 'Alle'),
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
              child: const Text('Zurücksetzen')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen')),
        ],
      ),
    );
  }

  // ── Batch-Aktionen ────────────────────────────────────────────────────────

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
      final service = EquipmentService();
      await service.updateStatusBatch(
          _selectedEquipmentIds.toList(), newStatus);
      if (mounted) {
        setState(() {
          _selectedEquipmentIds.clear();
          _selectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Status erfolgreich aktualisiert'),
                backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessingBatch = false);
    }
  }
}
