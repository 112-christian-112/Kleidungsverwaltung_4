// screens/missions/add_equipment_to_mission_nfc_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/equipment_model.dart';
import '../../models/user_models.dart';
import '../../services/equipment_service.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/nfc_scan_sheet.dart';

class AddEquipmentToMissionNfcScreen extends StatefulWidget {
  final String missionId;
  final List<String> alreadyAddedEquipmentIds;

  const AddEquipmentToMissionNfcScreen({
    Key? key,
    required this.missionId,
    required this.alreadyAddedEquipmentIds,
  }) : super(key: key);

  @override
  State<AddEquipmentToMissionNfcScreen> createState() =>
      _AddEquipmentToMissionNfcScreenState();
}

class _AddEquipmentToMissionNfcScreenState
    extends State<AddEquipmentToMissionNfcScreen>
    with SingleTickerProviderStateMixin {
  final EquipmentService _equipmentService = EquipmentService();
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  late TabController _tabController;

  UserModel? _currentUser;
  bool _isLoadingUser = true;
  List<String> _availableFireStations = [];

  // Filter (Hinzufügen-Tab)
  String _searchQuery = '';
  String _selectedFireStationFilter = 'Alle';
  String _selectedTypeFilter = 'Alle';
  String _selectedStatusFilter = 'Einsatzbereit';
  bool _showFilters = false;

  List<EquipmentModel> _allEquipment = [];
  List<EquipmentModel> _selectedEquipment = [];
  bool _isProcessing = false;

  bool get _canSeeAllStations =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.visibleFireStations.contains('*') == true ||
      (_currentUser?.permissions.visibleFireStations.isNotEmpty == true);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── User laden ────────────────────────────────────────────────────────────

  Future<void> _loadUser() async {
    setState(() => _isLoadingUser = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null || !mounted) return;

      List<String> stations = [user.fireStation];
      final canSeeAll = user.isAdmin ||
          user.permissions.visibleFireStations.contains('*');

      if (canSeeAll) {
        final mission = await _missionService.getMissionById(widget.missionId);
        if (mission != null) {
          final Set<String> s = {
            mission.fireStation,
            ...mission.involvedFireStations,
            user.fireStation,
          };
          stations = s.toList()..sort();
        }
      } else {
        stations = {
          user.fireStation,
          ...user.permissions.visibleFireStations,
        }.toList()..sort();
      }

      if (mounted) {
        setState(() {
          _currentUser = user;
          _availableFireStations = stations;
          _isLoadingUser = false;
        });
        _loadEquipment();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _loadEquipment() async {
    try {
      _equipmentService.getEquipmentByUserAccess().listen((list) {
        if (mounted) setState(() => _allEquipment = list);
      });
    } catch (e) {
      // ignore
    }
  }

  // ── NFC Scan ──────────────────────────────────────────────────────────────

  Future<void> _scanNfc() async {
    final tagId = await NfcScanSheet.zeigen(
      context,
      hinweisText: 'NFC-Tag der Einsatzkleidung an Gerät halten',
    );
    if (tagId == null || tagId.isEmpty || !mounted) return;
    await _processNfcTag(tagId);
  }

  Future<void> _processNfcTag(String tagId) async {
    try {
      final equipment = await _equipmentService.getEquipmentByNfcTag(tagId);
      if (!mounted) return;

      if (equipment == null) {
        _showSnack('Kein Kleidungsstück für diesen Tag gefunden', Colors.orange);
        return;
      }
      if (widget.alreadyAddedEquipmentIds.contains(equipment.id)) {
        _showSnack('${equipment.article} ist bereits im Einsatz', Colors.orange);
        return;
      }
      if (_selectedEquipment.any((e) => e.id == equipment.id)) {
        _showSnack('${equipment.article} bereits ausgewählt', Colors.orange);
        return;
      }

      setState(() {
        _selectedEquipment.add(equipment);
        // Nach Scan direkt auf "Ausgewählt"-Tab wechseln
        _tabController.animateTo(0);
      });
      _showSnack('✓ ${equipment.article} · ${equipment.owner}', Colors.green);
    } catch (e) {
      if (mounted) _showSnack('Fehler: $e', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Toggle Auswahl ────────────────────────────────────────────────────────

  void _toggleSelection(EquipmentModel e) {
    setState(() {
      final idx = _selectedEquipment.indexWhere((s) => s.id == e.id);
      if (idx >= 0) {
        _selectedEquipment.removeAt(idx);
      } else {
        _selectedEquipment.add(e);
        _tabController.animateTo(0);
      }
    });
  }

  // ── Filter ────────────────────────────────────────────────────────────────

  List<EquipmentModel> _applyFilters(List<EquipmentModel> list) {
    var r = list;
    if (_selectedFireStationFilter != 'Alle') {
      r = r.where((e) => e.fireStation == _selectedFireStationFilter).toList();
    }
    if (_selectedTypeFilter != 'Alle') {
      r = r.where((e) => e.type == _selectedTypeFilter).toList();
    }
    if (_selectedStatusFilter != 'Alle') {
      r = r.where((e) => e.status == _selectedStatusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      r = r.where((e) =>
          e.owner.toLowerCase().contains(q) ||
          e.article.toLowerCase().contains(q) ||
          e.nfcTag.toLowerCase().contains(q)).toList();
    }
    return r;
  }

  void _resetFilters() => setState(() {
        _searchQuery = '';
        _selectedFireStationFilter = 'Alle';
        _selectedTypeFilter = 'Alle';
        _selectedStatusFilter = 'Alle';
      });

  Map<String, List<EquipmentModel>> _groupByOwnerMap(List<EquipmentModel> list) {
    final Map<String, List<EquipmentModel>> grouped = {};
    for (final e in list) {
      grouped.putIfAbsent(e.owner, () => []).add(e);
    }
    return Map.fromEntries(
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  // ── Speichern ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedEquipment.isEmpty) {
      _showSnack('Keine Ausrüstung ausgewählt', Colors.orange);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await _missionService.addEquipmentToMission(
          widget.missionId, _selectedEquipment.map((e) => e.id).toList());
      if (mounted) {
        _showSnack('Ausrüstung erfolgreich hinzugefügt', Colors.green);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showSnack('Fehler: $e', Colors.red);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedEquipment.isEmpty
            ? 'Ausrüstung hinzufügen'
            : '${_selectedEquipment.length} ausgewählt'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // NFC-Button immer sichtbar in der AppBar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoadingUser ? null : _scanNfc,
                    icon: const Icon(Icons.nfc, size: 18),
                    label: const Text('NFC-Tag scannen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 16),
                        const SizedBox(width: 6),
                        const Text('Ausgewählt'),
                        if (_selectedEquipment.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_selectedEquipment.length}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 16),
                        SizedBox(width: 6),
                        Text('Hinzufügen'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoadingUser
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAusgewaehltTab(),
                _buildHinzufuegenTab(),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Tab: Ausgewählt ───────────────────────────────────────────────────────

  Widget _buildAusgewaehltTab() {
    if (_selectedEquipment.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nfc, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('Noch nichts ausgewählt',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            Text(
              'NFC-Tag scannen oder im Tab\n"Hinzufügen" manuell auswählen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanNfc,
              icon: const Icon(Icons.nfc),
              label: const Text('Ersten Tag scannen'),
            ),
          ],
        ),
      );
    }

    final grouped = _groupByOwnerMap(_selectedEquipment);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: grouped.length,
      itemBuilder: (_, i) {
        final owner = grouped.keys.elementAt(i);
        final items = grouped[owner]!;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(owner,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const Spacer(),
                    Text('${items.length} Stück',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...items.map((e) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          e.type == 'Jacke' ? Colors.blue : Colors.amber,
                      child: Icon(
                        e.type == 'Jacke'
                            ? Icons.accessibility_new
                            : Icons.airline_seat_legroom_normal,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    title: Text('${e.article} · Gr. ${e.size}',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: _canSeeAllStations
                        ? Text(e.fireStation,
                            style: const TextStyle(fontSize: 11))
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.red, size: 20),
                      onPressed: () =>
                          setState(() => _selectedEquipment.remove(e)),
                      tooltip: 'Entfernen',
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  // ── Tab: Hinzufügen ───────────────────────────────────────────────────────

  Widget _buildHinzufuegenTab() {
    return Column(
      children: [
        // Suche + Filter-Toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Besitzer, Artikel, NFC-Tag...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: () =>
                    setState(() => _showFilters = !_showFilters),
                icon: Icon(_showFilters
                    ? Icons.filter_list_off
                    : Icons.filter_list),
                tooltip: 'Filter',
              ),
            ],
          ),
        ),

        if (_showFilters) _buildFilterDropdowns(),

        Expanded(
          child: _allEquipment.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Builder(builder: (context) {
                  final stationFiltered = _availableFireStations.isEmpty
                      ? _allEquipment
                      : _allEquipment
                          .where((e) => _availableFireStations
                              .contains(e.fireStation))
                          .toList();
                  final filtered = _applyFilters(stationFiltered);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text('Keine Ausrüstung gefunden',
                              style: TextStyle(color: Colors.grey)),
                          TextButton(
                              onPressed: _resetFilters,
                              child: const Text('Filter zurücksetzen')),
                        ],
                      ),
                    );
                  }

                  final grouped = _groupByOwnerMap(filtered);

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: grouped.length,
                    itemBuilder: (_, i) {
                      final owner = grouped.keys.elementAt(i);
                      final items = grouped[owner]!;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 4),
                              child: Text(owner,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                            ),
                            ...items.map((e) => _hinzufuegenTile(e)),
                          ],
                        ),
                      );
                    },
                  );
                }),
        ),
      ],
    );
  }

  Widget _hinzufuegenTile(EquipmentModel e) {
    final isAlreadyAdded = widget.alreadyAddedEquipmentIds.contains(e.id);
    final isSelected = _selectedEquipment.any((s) => s.id == e.id);

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor:
            isAlreadyAdded || isSelected ? Colors.grey.shade300 :
            e.type == 'Jacke' ? Colors.blue : Colors.amber,
        child: Icon(
          e.type == 'Jacke'
              ? Icons.accessibility_new
              : Icons.airline_seat_legroom_normal,
          color: Colors.white,
          size: 16,
        ),
      ),
      title: Text('${e.article} · Gr. ${e.size}',
          style: TextStyle(
              fontSize: 13,
              color: isAlreadyAdded ? Colors.grey : null,
              decoration:
                  isAlreadyAdded ? TextDecoration.lineThrough : null)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canSeeAllStations)
            Text(e.fireStation,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (isAlreadyAdded)
            const Text('Bereits im Einsatz',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold)),
        ],
      ),
      trailing: isAlreadyAdded
          ? const Icon(Icons.check, color: Colors.grey, size: 18)
          : isSelected
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary, size: 22)
              : const Icon(Icons.add_circle_outline, size: 22),
      enabled: !isAlreadyAdded,
      onTap: isAlreadyAdded ? null : () => _toggleSelection(e),
    );
  }

  // ── Filter Dropdowns ──────────────────────────────────────────────────────

  Widget _buildFilterDropdowns() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (_canSeeAllStations)
            _filterDropdown(
              value: _selectedFireStationFilter,
              items: ['Alle', ..._availableFireStations],
              onChanged: (v) =>
                  setState(() => _selectedFireStationFilter = v!),
            ),
          _filterDropdown(
            value: _selectedTypeFilter,
            items: const ['Alle', 'Jacke', 'Hose'],
            onChanged: (v) => setState(() => _selectedTypeFilter = v!),
          ),
          _filterDropdown(
            value: _selectedStatusFilter,
            items: const ['Alle', 'Einsatzbereit', 'Reinigung', 'Reparatur'],
            onChanged: (v) => setState(() => _selectedStatusFilter = v!),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: value,
        items: items
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: onChanged,
        underline: const SizedBox(),
        isDense: true,
      ),
    );
  }

  // ── Bottom Bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedEquipment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_selectedEquipment.length} Artikel ausgewählt',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedEquipment.clear()),
                      child: const Text('Alle entfernen'),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing || _selectedEquipment.isEmpty
                    ? null
                    : _save,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_selectedEquipment.isEmpty
                        ? 'Ausrüstung auswählen'
                        : '${_selectedEquipment.length} zum Einsatz hinzufügen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
