// screens/missions/add_equipment_to_mission_nfc_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../../Lists/fire_stations.dart';
import '../../models/equipment_model.dart';
import '../../models/user_models.dart';
import '../../services/equipment_service.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';

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
    with TickerProviderStateMixin {
  final EquipmentService _equipmentService = EquipmentService();
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  late TabController _tabController;
  Timer? _resetTimer;

  // User
  UserModel? _currentUser;
  bool _isLoadingUser = true;

  // Sichtbare Stationen für diesen Einsatz
  List<String> _availableFireStations = [];

  // NFC
  bool _isScanning = false;
  bool _isNfcAvailable = false;
  bool _sessionActive = false;
  String _statusMessage = 'Bereit zum Scannen';
  String _lastScannedTagId = '';

  // Manueller Tab – Filter
  String _searchQuery = '';
  String _selectedFireStationFilter = 'Alle';
  String _selectedOwnerFilter = 'Alle';
  String _selectedTypeFilter = 'Alle';
  String _selectedStatusFilter = 'Einsatzbereit';
  bool _groupByOwner = true;
  bool _showFilters = false;
  final Set<String> _expandedOwners = {};

  // Shared
  List<EquipmentModel> _selectedEquipment = [];
  bool _isProcessing = false;

  // Berechtigungen
  bool get _canSeeAllStations =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.visibleFireStations.contains('*') == true ||
      (_currentUser?.permissions.visibleFireStations.isNotEmpty == true);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkNfcAvailability();
    _loadUser();
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _stopNfcSession();
    _tabController.dispose();
    super.dispose();
  }

  // ── User & Stationen laden ────────────────────────────────────────────────

  Future<void> _loadUser() async {
    setState(() => _isLoadingUser = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (user == null || !mounted) return;

      // Verfügbare Stationen für diesen Einsatz ermitteln
      List<String> stations = [user.fireStation];

      final canSeeAll = user.isAdmin ||
          user.permissions.visibleFireStations.contains('*');

      if (canSeeAll) {
        // Alle beteiligten Stationen aus der Mission laden
        final mission =
            await _missionService.getMissionById(widget.missionId);
        if (mission != null) {
          final Set<String> missionStations = {
            mission.fireStation,
            ...mission.involvedFireStations,
            user.fireStation,
          };
          stations = missionStations.toList()..sort();
        }
      } else {
        // User mit sichtbaren Stationen: eigene + freigegebene
        stations = {
          user.fireStation,
          ...user.permissions.visibleFireStations,
        }.toList()
          ..sort();
      }

      if (mounted) {
        setState(() {
          _currentUser = user;
          _availableFireStations = stations;
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      print('Fehler _loadUser: $e');
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  // ── NFC ───────────────────────────────────────────────────────────────────

  Future<void> _checkNfcAvailability() async {
    try {
      _isNfcAvailable = await NfcManager.instance.isAvailable();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _startContinuousNfcSession() async {
    if (!_isNfcAvailable) return;
    setState(() {
      _sessionActive = true;
      _isScanning = true;
      _statusMessage = 'NFC-Tag an Gerät halten...';
    });

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      final id = _extractNfcId(tag);
      if (id.isEmpty || id == _lastScannedTagId) return;
      _lastScannedTagId = id;
      await _processNfcTag(id);
    });
  }

  String _extractNfcId(NfcTag tag) {
    try {
      final ndef = tag.data['ndef'];
      if (ndef != null) {
        final records = ndef['cachedMessage']?['records'] as List?;
        if (records != null && records.isNotEmpty) {
          final payload = records.first['payload'] as List<int>?;
          if (payload != null && payload.length > 3) {
            return String.fromCharCodes(payload.sublist(3));
          }
        }
      }
      final nfcA = tag.data['nfca'];
      if (nfcA != null) {
        final id = nfcA['identifier'] as List<int>?;
        if (id != null) {
          return id.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> _processNfcTag(String tagId) async {
    setState(() => _statusMessage = 'Suche Ausrüstung für Tag: $tagId...');
    try {
      final equipment =
          await _equipmentService.getEquipmentByNfcTag(tagId);
      if (equipment == null) {
        setState(() => _statusMessage = 'Keine Ausrüstung für diesen Tag gefunden');
        _resetStatusAfterDelay();
        return;
      }
      if (_isEquipmentAlreadyAdded(equipment)) {
        setState(() => _statusMessage =
            '${equipment.article} ist bereits im Einsatz');
        _resetStatusAfterDelay();
        return;
      }
      if (_isEquipmentSelected(equipment)) {
        setState(() =>
            _statusMessage = '${equipment.article} bereits ausgewählt');
        _resetStatusAfterDelay();
        return;
      }
      setState(() {
        _selectedEquipment.add(equipment);
        _statusMessage =
            '✓ ${equipment.article} (${equipment.owner}) hinzugefügt';
      });
      _resetStatusAfterDelay();
    } catch (e) {
      setState(() => _statusMessage = 'Fehler: $e');
      _resetStatusAfterDelay();
    }
  }

  void _resetStatusAfterDelay() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _statusMessage = 'Bereit zum Scannen';
          _lastScannedTagId = '';
        });
      }
    });
  }

  Future<void> _stopNfcSession() async {
    try {
      _resetTimer?.cancel();
      _sessionActive = false;
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  void _restartNfcSession() {
    _stopNfcSession().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startContinuousNfcSession();
      });
    });
  }

  // ── Auswahl-Logik ─────────────────────────────────────────────────────────

  void _toggleSelection(EquipmentModel equipment) {
    setState(() {
      final idx = _selectedEquipment.indexWhere((e) => e.id == equipment.id);
      if (idx >= 0) {
        _selectedEquipment.removeAt(idx);
      } else {
        _selectedEquipment.add(equipment);
      }
    });
  }

  bool _isEquipmentSelected(EquipmentModel e) =>
      _selectedEquipment.any((s) => s.id == e.id);

  bool _isEquipmentAlreadyAdded(EquipmentModel e) =>
      widget.alreadyAddedEquipmentIds.contains(e.id);

  // ── Filter ────────────────────────────────────────────────────────────────

  List<EquipmentModel> _applyFilters(List<EquipmentModel> list) {
    var result = list;

    if (_selectedFireStationFilter != 'Alle') {
      result = result
          .where((e) => e.fireStation == _selectedFireStationFilter)
          .toList();
    }

    switch (_selectedStatusFilter) {
      case 'Einsatzbereit':
        result = result
            .where((e) => e.status == EquipmentStatus.ready)
            .toList();
        break;
      case 'In Reinigung':
        result = result
            .where((e) => e.status == EquipmentStatus.cleaning)
            .toList();
        break;
      case 'Alle':
      default:
        break;
    }

    if (_selectedOwnerFilter != 'Alle') {
      result =
          result.where((e) => e.owner == _selectedOwnerFilter).toList();
    }

    if (_selectedTypeFilter != 'Alle') {
      result =
          result.where((e) => e.type == _selectedTypeFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((e) =>
              e.owner.toLowerCase().contains(q) ||
              e.nfcTag.toLowerCase().contains(q) ||
              e.article.toLowerCase().contains(q) ||
              e.size.toLowerCase().contains(q))
          .toList();
    }

    // Sortierung
    result.sort((a, b) => a.owner.compareTo(b.owner));

    return result;
  }

  void _resetFilters() {
    setState(() {
      _selectedFireStationFilter = 'Alle';
      _selectedOwnerFilter = 'Alle';
      _selectedTypeFilter = 'Alle';
      _selectedStatusFilter = 'Einsatzbereit';
      _searchQuery = '';
      _groupByOwner = true;
    });
  }

  Map<String, List<EquipmentModel>> _groupByOwnerMap(
      List<EquipmentModel> list) {
    final Map<String, List<EquipmentModel>> grouped = {};
    for (final e in list) {
      grouped.putIfAbsent(e.owner, () => []).add(e);
    }
    return Map.fromEntries(
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  // ── Speichern ─────────────────────────────────────────────────────────────

  Future<void> _saveSelectedEquipment() async {
    if (_selectedEquipment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine Ausrüstung ausgewählt'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await _missionService.addEquipmentToMission(
          widget.missionId,
          _selectedEquipment.map((e) => e.id).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ausrüstung erfolgreich hinzugefügt'),
            backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fehler: $e'), backgroundColor: Colors.red));
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.nfc), text: 'NFC Scan'),
            Tab(icon: Icon(Icons.list), text: 'Manuell'),
          ],
        ),
      ),
      body: _isLoadingUser
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNfcTab(),
                _buildManualTab(),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── NFC Tab ───────────────────────────────────────────────────────────────

  Widget _buildNfcTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Session-Status
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _sessionActive
                          ? Colors.green[100]
                          : Colors.red[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _sessionActive
                              ? Colors.green
                              : Colors.red),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _sessionActive
                              ? Icons.wifi_tethering
                              : Icons.wifi_tethering_off,
                          size: 14,
                          color: _sessionActive
                              ? Colors.green
                              : Colors.red),
                        const SizedBox(width: 4),
                        Text(
                          _sessionActive
                              ? 'NFC Session aktiv'
                              : 'NFC Session gestoppt',
                          style: TextStyle(
                              fontSize: 11,
                              color: _sessionActive
                                  ? Colors.green[800]
                                  : Colors.red[800],
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Status-Meldung
                  Row(
                    children: [
                      Icon(
                        _isScanning
                            ? Icons.nfc
                            : (_isNfcAvailable
                                ? Icons.check_circle
                                : Icons.error),
                        color: _isScanning
                            ? Colors.blue
                            : (_isNfcAvailable
                                ? Colors.green
                                : Colors.red),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_statusMessage,
                              style: const TextStyle(fontSize: 16))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isNfcAvailable && !_sessionActive
                              ? _startContinuousNfcSession
                              : null,
                          icon: const Icon(Icons.nfc),
                          label: Text(_sessionActive
                              ? 'Scannen läuft...'
                              : 'NFC-Scan starten'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _sessionActive
                                  ? Colors.green
                                  : null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed:
                            _sessionActive ? _restartNfcSession : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Neustart'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
              'Ausgewählte Ausrüstung (${_selectedEquipment.length})',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(child: _buildSelectedEquipmentList()),
        ],
      ),
    );
  }

  // ── Manueller Tab ─────────────────────────────────────────────────────────

  Widget _buildManualTab() {
    return Column(
      children: [
        // Suchfeld + Filter-Toggle
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Suchen',
                    hintText: 'Besitzer, NFC-Tag...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () =>
                    setState(() => _showFilters = !_showFilters),
                icon: Icon(
                    _showFilters ? Icons.filter_list_off : Icons.filter_list),
                tooltip: 'Filter',
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _groupByOwner = !_groupByOwner),
                icon: Icon(_groupByOwner ? Icons.person : Icons.view_list),
                tooltip: _groupByOwner
                    ? 'Listenansicht'
                    : 'Nach Besitzer gruppieren',
              ),
            ],
          ),
        ),

        // Filter-Dropdowns
        if (_showFilters) _buildFilterDropdowns(),

        // Equipment-Liste
        Expanded(
          child: StreamBuilder<List<EquipmentModel>>(
            stream: _equipmentService.getEquipmentByUserAccess(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('Fehler: ${snapshot.error}'));
              }

              final all = snapshot.data ?? [];
              // Nur Ausrüstung aus verfügbaren Stationen
              final stationFiltered = _availableFireStations.isEmpty
                  ? all
                  : all
                      .where((e) =>
                          _availableFireStations.contains(e.fireStation))
                      .toList();

              final filtered = _applyFilters(stationFiltered);

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('Keine Ausrüstung gefunden',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _resetFilters,
                          child: const Text('Filter zurücksetzen')),
                    ],
                  ),
                );
              }

              return _groupByOwner
                  ? _buildGroupedList(filtered)
                  : _buildFlatList(filtered);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdowns() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Ortswehr (nur wenn mehrere sichtbar)
          if (_canSeeAllStations && _availableFireStations.length > 1)
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _selectedFireStationFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Ortswehr',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8)),
                items: ['Alle', ..._availableFireStations]
                    .toSet()
                    .toList()
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(
                    () => _selectedFireStationFilter = v ?? 'Alle'),
              ),
            ),

          // Typ
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String>(
              value: _selectedTypeFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Typ',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8)),
              items: ['Alle', 'Jacke', 'Hose']
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _selectedTypeFilter = v ?? 'Alle'),
            ),
          ),

          // Status
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              value: _selectedStatusFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8)),
              items: ['Alle', 'Einsatzbereit', 'In Reinigung']
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _selectedStatusFilter = v ?? 'Einsatzbereit'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Listen ────────────────────────────────────────────────────────────────

  Widget _buildGroupedList(List<EquipmentModel> list) {
    final grouped = _groupByOwnerMap(list);

    return ListView.builder(
      itemCount: grouped.length,
      itemBuilder: (_, i) {
        final owner = grouped.keys.elementAt(i);
        final items = grouped[owner]!;
        final selectedCount =
            items.where((e) => _isEquipmentSelected(e)).length;
        final availableCount =
            items.where((e) => !_isEquipmentAlreadyAdded(e)).length;
        final isExpanded = _expandedOwners.contains(owner);

        return Card(
          margin:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ExpansionTile(
            initiallyExpanded: isExpanded,
            onExpansionChanged: (exp) => setState(() => exp
                ? _expandedOwners.add(owner)
                : _expandedOwners.remove(owner)),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(owner[0].toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800)),
            ),
            title: Text(owner,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '$selectedCount von $availableCount ausgewählt',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 12)),
            trailing: availableCount > 0
                ? TextButton(
                    onPressed: () => setState(() {
                      for (final e in items) {
                        if (!_isEquipmentAlreadyAdded(e) &&
                            !_isEquipmentSelected(e)) {
                          _selectedEquipment.add(e);
                        }
                      }
                    }),
                    child: const Text('Alle'),
                  )
                : null,
            children:
                items.map((e) => _buildEquipmentTile(e)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFlatList(List<EquipmentModel> list) {
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) => _buildEquipmentTile(list[i]),
    );
  }

  Widget _buildEquipmentTile(EquipmentModel equipment) {
    final isSelected = _isEquipmentSelected(equipment);
    final isAlreadyAdded = _isEquipmentAlreadyAdded(equipment);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
        child: Icon(
          equipment.type == 'Jacke'
              ? Icons.accessibility_new
              : Icons.airline_seat_legroom_normal,
          color: Colors.white,
          size: 18,
        ),
      ),
      title: Text(equipment.article,
          style: TextStyle(
              color: isAlreadyAdded ? Colors.grey : null,
              decoration: isAlreadyAdded
                  ? TextDecoration.lineThrough
                  : null)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${equipment.owner} · Gr. ${equipment.size}'),
          if (_canSeeAllStations)
            Text('Ortswehr: ${equipment.fireStation}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey)),
          if (isAlreadyAdded)
            const Text('Bereits im Einsatz',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold)),
        ],
      ),
      trailing: isAlreadyAdded
          ? const Icon(Icons.check, color: Colors.grey)
          : Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelection(equipment),
            ),
      enabled: !isAlreadyAdded,
      onTap:
          isAlreadyAdded ? null : () => _toggleSelection(equipment),
    );
  }

  Widget _buildSelectedEquipmentList() {
    if (_selectedEquipment.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Noch keine Ausrüstung ausgewählt',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
                'NFC-Tag scannen oder manuell im zweiten Tab auswählen',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final grouped = _groupByOwnerMap(_selectedEquipment);

    return ListView.builder(
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
                child: Text(owner,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              ...items.map((e) => ListTile(
                    dense: true,
                    leading: Icon(
                      e.type == 'Jacke'
                          ? Icons.accessibility_new
                          : Icons.airline_seat_legroom_normal,
                      color: e.type == 'Jacke'
                          ? Colors.blue
                          : Colors.amber,
                    ),
                    title: Text(e.article),
                    subtitle: Text('Gr. ${e.size}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle,
                          color: Colors.red),
                      onPressed: () => setState(
                          () => _selectedEquipment.remove(e)),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  // ── Bottom Bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedEquipment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_selectedEquipment.length} Artikel ausgewählt',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                    TextButton(
                        onPressed: () =>
                            setState(() => _selectedEquipment.clear()),
                        child: const Text('Alle entfernen')),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing || _selectedEquipment.isEmpty
                    ? null
                    : _saveSelectedEquipment,
                style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14)),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : Text(
                        _selectedEquipment.isEmpty
                            ? 'Ausrüstung auswählen'
                            : '${_selectedEquipment.length} Artikel zum Einsatz hinzufügen',
                        style: const TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
