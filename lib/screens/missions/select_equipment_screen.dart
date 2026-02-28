// screens/missions/select_equipment_screen.dart
import 'package:flutter/material.dart';
import '../../models/equipment_model.dart';
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

  List<String> _selectedIds = [];
  String _searchQuery = '';
  String _filterType = 'Alle';
  String _filterFireStation = 'Alle'; // Neue Variable für Feuerwehr-Filter
  bool _isAdmin = false;
  bool _isLoading = true;

  final List<String> _types = ['Alle', 'Jacke', 'Hose'];
  final List<String> _fireStations = [
    'Alle',
    'Esklum',
    'Breinermoor',
    'Grotegaste',
    'Flachsmeer',
    'Folmhusen',
    'Großwolde',
    'Ihrhove',
    'Ihren',
    'Steenfelde',
    'Völlen',
    'Völlenerfehn',
    'Völlenerkönigsfehn'
  ];

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.preselectedIds);
    _loadAdminStatus();
  }

  // Prüft, ob der aktuelle Benutzer ein Admin ist
  Future<void> _loadAdminStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAdmin = await _permissionService.isAdmin();

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          // Wenn kein Admin, dann Standard-Filter auf die eigene Feuerwehr
          _filterFireStation = isAdmin ? 'Alle' : widget.fireStation;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden des Admin-Status: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _filterFireStation = widget.fireStation; // Fallback: eigene Feuerwehr
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausrüstung auswählen'),
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
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Suchen',
                hintText: 'Nach Besitzer, NFC-Tag suchen...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Anzeigen der aktiven Filter als Chips
          if (_filterFireStation != 'Alle' || _filterType != 'Alle')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aktive Filter:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_filterFireStation != 'Alle')
                        Chip(
                          label: Text(_filterFireStation),
                          deleteIcon: const Icon(Icons.clear),
                          onDeleted: _isAdmin ? () {
                            setState(() {
                              _filterFireStation = 'Alle';
                            });
                          } : null, // Nur Admins können diesen Filter ändern
                        ),
                      if (_filterType != 'Alle')
                        Chip(
                          label: Text(_filterType),
                          deleteIcon: const Icon(Icons.clear),
                          onDeleted: () {
                            setState(() {
                              _filterType = 'Alle';
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),

          Expanded(
            child: StreamBuilder<List<EquipmentModel>>(
              stream: _filterFireStation == 'Alle' && _isAdmin
                  ? _equipmentService.getAllEquipment()
                  : _equipmentService.getEquipmentByFireStation(_filterFireStation),
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

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text('Keine Einsatzkleidung vorhanden'),
                  );
                }

                List<EquipmentModel> equipmentList = snapshot.data!;

                // Nur einsatzbereite Ausrüstung anzeigen
                equipmentList = equipmentList
                    .where((equipment) => equipment.status == EquipmentStatus.ready)
                    .toList();

                // Filtern nach Suchbegriff
                if (_searchQuery.isNotEmpty) {
                  equipmentList = equipmentList
                      .where((equipment) =>
                  equipment.nfcTag.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      (equipment.barcode != null &&
                          equipment.barcode!.toLowerCase().contains(_searchQuery.toLowerCase())) ||
                      equipment.owner.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      equipment.size.toLowerCase().contains(_searchQuery.toLowerCase()))
                      .toList();
                }

                // Filtern nach Typ
                if (_filterType != 'Alle') {
                  equipmentList = equipmentList
                      .where((equipment) => equipment.type == _filterType)
                      .toList();
                }

                if (equipmentList.isEmpty) {
                  return const Center(
                    child: Text('Keine passende Einsatzkleidung gefunden'),
                  );
                }

                return ListView.builder(
                  itemCount: equipmentList.length,
                  itemBuilder: (context, index) {
                    final equipment = equipmentList[index];
                    final isSelected = _selectedIds.contains(equipment.id);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      child: CheckboxListTile(
                        title: Text(equipment.article),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Besitzer: ${equipment.owner} | Größe: ${equipment.size}'),
                            // Zeige auch die Feuerwehr an, besonders relevant für Admins
                            Text('Feuerwehr: ${equipment.fireStation}',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.secondary)),
                          ],
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
                          child: Icon(
                            equipment.type == 'Jacke'
                                ? Icons.accessibility_new
                                : Icons.airline_seat_legroom_normal,
                            color: Colors.white,
                          ),
                        ),
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selectedIds.add(equipment.id);
                            } else {
                              _selectedIds.remove(equipment.id);
                            }
                          });
                        },
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Ausgewählte Anzahl und Bestätigen-Button
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  '${_selectedIds.length} Artikel ausgewählt',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedIds),
                  child: const Text('Bestätigen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Filter'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Feuerwehr-Filter (nur für Admins)
              if (_isAdmin) ...[
                const Text('Ortsfeuerwehr'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterFireStation,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _fireStations.map((String station) {
                    return DropdownMenuItem<String>(
                      value: station,
                      child: Text(station),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _filterFireStation = newValue;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],

              const Text('Typ'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _filterType,
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
                      _filterType = newValue;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  if (_isAdmin) {
                    _filterFireStation = 'Alle';
                  }
                  _filterType = 'Alle';
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
}