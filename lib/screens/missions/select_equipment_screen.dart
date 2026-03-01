// screens/missions/select_equipment_screen.dart
import 'package:flutter/material.dart';
import '../../Lists/fire_stations.dart';
import '../../models/equipment_model.dart';
import '../../models/user_models.dart';
import '../../services/equipment_service.dart';
import '../../services/permission_service.dart';

class SelectEquipmentScreen extends StatefulWidget {
  final List<String> preselectedIds;
  final String fireStation;

  const SelectEquipmentScreen({
    Key? key,
    required this.preselectedIds,
    required this.fireStation,
  }) : super(key: key);

  @override
  State<SelectEquipmentScreen> createState() => _SelectEquipmentScreenState();
}

class _SelectEquipmentScreenState extends State<SelectEquipmentScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;

  List<String> _selectedIds = [];
  String _searchQuery = '';
  String _filterType = 'Alle';
  String _filterFireStation = 'Alle';

  final List<String> _types = ['Alle', 'Jacke', 'Hose'];
  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];

  // Darf der User die Stationsauswahl im Filter ändern?
  bool get _canFilterByStation =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.visibleFireStations.isNotEmpty == true ||
      _currentUser?.permissions.visibleFireStations.contains('*') == true;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.preselectedIds);
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    final user = await _permissionService.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
        // Nicht-Admins ohne erweiterte Rechte: direkt auf eigene Station filtern
        if (user != null &&
            !user.isAdmin &&
            !user.permissions.visibleFireStations.contains('*') &&
            user.permissions.visibleFireStations.isEmpty) {
          _filterFireStation = widget.fireStation;
        }
        _isLoading = false;
      });
    }
  }

  List<EquipmentModel> _applyFilters(List<EquipmentModel> list) {
    var result = list
        // Nur einsatzbereite Ausrüstung
        .where((e) => e.status == EquipmentStatus.ready)
        .toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((e) =>
              e.nfcTag.toLowerCase().contains(q) ||
              (e.barcode?.toLowerCase().contains(q) ?? false) ||
              e.owner.toLowerCase().contains(q) ||
              e.size.toLowerCase().contains(q) ||
              e.article.toLowerCase().contains(q))
          .toList();
    }

    if (_filterFireStation != 'Alle') {
      result =
          result.where((e) => e.fireStation == _filterFireStation).toList();
    }

    if (_filterType != 'Alle') {
      result = result.where((e) => e.type == _filterType).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _selectedIds.isEmpty ? 'Ausrüstung auswählen' : '${_selectedIds.length} ausgewählt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          TextButton(
            onPressed: _selectedIds.isEmpty
                ? null
                : () => Navigator.pop(context, _selectedIds),
            child: const Text('Übernehmen',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Suchfeld
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Suchen',
                      hintText: 'Besitzer, NFC-Tag, Größe...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),

                // Aktive Filter
                if (_filterFireStation != 'Alle' || _filterType != 'Alle')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_filterFireStation != 'Alle')
                          Chip(
                            label: Text(_filterFireStation),
                            deleteIcon: const Icon(Icons.clear),
                            onDeleted: _canFilterByStation
                                ? () => setState(
                                    () => _filterFireStation = 'Alle')
                                : null,
                          ),
                        if (_filterType != 'Alle')
                          Chip(
                            label: Text(_filterType),
                            deleteIcon: const Icon(Icons.clear),
                            onDeleted: () =>
                                setState(() => _filterType = 'Alle'),
                          ),
                      ],
                    ),
                  ),

                // Liste
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
                            child: Text('Fehler: ${snapshot.error}'));
                      }

                      final filtered =
                          _applyFilters(snapshot.data ?? []);

                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 64,
                                  color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              const Text(
                                  'Keine einsatzbereite Ausrüstung gefunden',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) =>
                            _buildEquipmentTile(filtered[i]),
                      );
                    },
                  ),
                ),

                // Fußzeile mit Bestätigen-Button
                if (_selectedIds.isNotEmpty)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pop(context, _selectedIds),
                          style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          child: Text(
                              '${_selectedIds.length} Artikel übernehmen'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildEquipmentTile(EquipmentModel equipment) {
    final isSelected = _selectedIds.contains(equipment.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
          : null,
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (_) => setState(() {
          if (isSelected) {
            _selectedIds.remove(equipment.id);
          } else {
            _selectedIds.add(equipment.id);
          }
        }),
        secondary: CircleAvatar(
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
        title: Text(equipment.article,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${equipment.owner} · Gr. ${equipment.size}'),
            if (_canFilterByStation)
              Text('Ortswehr: ${equipment.fireStation}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Filter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_canFilterByStation) ...[
              const Text('Ortsfeuerwehr',
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
                    setState(() => _filterFireStation = v ?? 'Alle'),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Typ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _filterType,
              isExpanded: true,
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
              items: _types
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _filterType = v ?? 'Alle'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _filterFireStation = _canFilterByStation
                    ? 'Alle'
                    : widget.fireStation;
                _filterType = 'Alle';
              });
              Navigator.pop(context);
            },
            child: const Text('Zurücksetzen'),
          ),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen')),
        ],
      ),
    );
  }
}
