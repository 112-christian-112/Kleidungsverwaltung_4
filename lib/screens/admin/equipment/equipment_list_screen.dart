// screens/admin/equipment/equipment_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Lists/fire_stations.dart';
import '../../../models/equipment_model.dart';
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

  // Berechtigungsstatus
  bool _isAdmin = false;
  bool _isHygieneUnit = false;
  bool _hasExtendedReadAccess = false;
  bool _canEditEquipment = false;
  String _userRole = 'user';

  // Filter und Suche
  String _searchQuery = '';
  String _filterFireStation = 'Alle';
  String _filterType = 'Alle';
  String _filterStatus = 'Alle';
  bool _groupByOwner = true;

  // Mehrfachauswahl
  bool _selectionMode = false;
  final Set<String> _selectedEquipmentIds = {};
  bool _isProcessingBatch = false;

  // Listen aus Konstanten
  List<String> get _fireStations => ['Alle', ...FireStations.getAllStations()];
  final List<String> _types = ['Alle', 'Jacke', 'Hose'];
  final List<String> _statusOptions = ['Alle', ...EquipmentStatus.values];

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final isAdmin = await _permissionService.isAdmin();
      final isHygieneUnit = await _permissionService.isHygieneUnit();
      final hasExtendedReadAccess = await _permissionService.hasExtendedReadAccess();
      final canEditEquipment = await _permissionService.canEditEquipment();
      final userRole = await _permissionService.getUserRole();

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _isHygieneUnit = isHygieneUnit;
          _hasExtendedReadAccess = hasExtendedReadAccess;
          _canEditEquipment = canEditEquipment;
          _userRole = userRole;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Berechtigungen: $e');
    }
  }

  void _toggleSelection(String equipmentId) {
    if (!_canEditEquipment) return; // Nur Admins können Mehrfachauswahl verwenden

    setState(() {
      if (_selectedEquipmentIds.contains(equipmentId)) {
        _selectedEquipmentIds.remove(equipmentId);
        if (_selectedEquipmentIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedEquipmentIds.add(equipmentId);
      }
    });
  }

  void _selectAll(List<EquipmentModel> equipmentList) {
    if (!_canEditEquipment) return; // Nur Admins können Mehrfachauswahl verwenden

    setState(() {
      if (_selectedEquipmentIds.length == equipmentList.length) {
        _selectedEquipmentIds.clear();
        _selectionMode = false;
      } else {
        _selectedEquipmentIds.clear();
        for (var equipment in equipmentList) {
          _selectedEquipmentIds.add(equipment.id);
        }
        _selectionMode = true;
      }
    });
  }

  Future<void> _updateStatusForSelected(String newStatus) async {
    if (!_canEditEquipment || _selectedEquipmentIds.isEmpty) return;

    setState(() {
      _isProcessingBatch = true;
    });

    try {
      await _equipmentService.updateStatusBatch(_selectedEquipmentIds.toList(), newStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status für ${_selectedEquipmentIds.length} Ausrüstungsgegenstände aktualisiert'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          _selectedEquipmentIds.clear();
          _selectionMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingBatch = false;
        });
      }
    }
  }

  void _showBatchStatusUpdateDialog() {
    if (!_canEditEquipment) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Status ändern'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Status für ${_selectedEquipmentIds.length} ausgewählte Ausrüstungsgegenstände ändern:'),
              const SizedBox(height: 16),
              ...EquipmentStatus.values.map((status) {
                return ListTile(
                  leading: Icon(
                    EquipmentStatus.getStatusIcon(status),
                    color: EquipmentStatus.getStatusColor(status),
                  ),
                  title: Text(status),
                  onTap: () {
                    Navigator.pop(context);
                    _updateStatusForSelected(status);
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  void _toggleGrouping() {
    setState(() {
      _groupByOwner = !_groupByOwner;
    });
  }

  List<EquipmentModel> _getFilteredEquipment(List<EquipmentModel> equipmentList) {
    List<EquipmentModel> filtered = List.from(equipmentList);

    // Filtern nach Suchbegriff
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((equipment) =>
      equipment.nfcTag.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (equipment.barcode != null && equipment.barcode!.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          equipment.owner.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          equipment.size.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    // Filtern nach Ortsfeuerwehr (nur für Benutzer mit erweiterten Rechten relevant)
    // WICHTIG: Filter nur anwenden wenn nicht "Alle" ausgewählt ist UND erweiterte Rechte vorhanden sind
    if (_filterFireStation != 'Alle' && _hasExtendedReadAccess) {
      filtered = filtered.where((equipment) => equipment.fireStation == _filterFireStation).toList();
    }

    // Filtern nach Typ
    if (_filterType != 'Alle') {
      filtered = filtered.where((equipment) => equipment.type == _filterType).toList();
    }

    // Filtern nach Status
    if (_filterStatus != 'Alle') {
      filtered = filtered.where((equipment) => equipment.status == _filterStatus).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Einsatzkleidung verwalten'),
            if (_isHygieneUnit && !_isAdmin) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'Hygieneeinheit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_groupByOwner ? Icons.person : Icons.view_list),
            onPressed: _toggleGrouping,
            tooltip: _groupByOwner ? 'Gruppierung nach Besitzer aufheben' : 'Nach Besitzer gruppieren',
          ),
          if (_selectionMode && _canEditEquipment) ...[
            IconButton(
              icon: const Icon(Icons.change_circle),
              onPressed: _showBatchStatusUpdateDialog,
              tooltip: 'Status ändern',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectedEquipmentIds.clear();
                  _selectionMode = false;
                });
              },
              tooltip: 'Auswahl abbrechen',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _showFilterDialog,
              tooltip: 'Filter',
            ),
          ],
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

          // Berechtigungs-Info für Hygieneeinheit
          if (_isHygieneUnit && !_isAdmin)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8.0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hygieneeinheit-Ansicht: Sie können alle Ausrüstung einsehen, aber nicht bearbeiten',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Aktive Filter-Chips
          if (_filterFireStation != 'Alle' || _filterType != 'Alle' || _filterStatus != 'Alle')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              margin: const EdgeInsets.only(top: 8),
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
                          avatar: Icon(
                            FireStations.getIcon(_filterFireStation),
                            size: 16,
                          ),
                          deleteIcon: const Icon(Icons.clear),
                          onDeleted: () {
                            setState(() {
                              _filterFireStation = 'Alle';
                            });
                          },
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
                      if (_filterStatus != 'Alle')
                        Chip(
                          label: Text(_filterStatus),
                          avatar: Icon(
                            EquipmentStatus.getStatusIcon(_filterStatus),
                            size: 16,
                            color: EquipmentStatus.getStatusColor(_filterStatus),
                          ),
                          deleteIcon: const Icon(Icons.clear),
                          onDeleted: () {
                            setState(() {
                              _filterStatus = 'Alle';
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

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

                final filteredEquipment = _getFilteredEquipment(snapshot.data!);

                if (filteredEquipment.isEmpty) {
                  return const Center(
                    child: Text('Keine Einsatzkleidung gefunden, die den Filterkriterien entspricht'),
                  );
                }

                // Gruppierte oder normale Ansicht
                return _groupByOwner
                    ? _buildGroupedListView(filteredEquipment)
                    : _buildNormalListView(filteredEquipment);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selectionMode && _canEditEquipment
          ? (_selectedEquipmentIds.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: _showBatchStatusUpdateDialog,
        label: const Text('Status ändern'),
        icon: const Icon(Icons.change_circle),
      )
          : null)
          : (_canEditEquipment
          ? FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddEquipmentScreen(),
            ),
          );
        },
        tooltip: 'Einsatzkleidung hinzufügen',
        child: const Icon(Icons.add),
      )
          : null),
    );
  }

  Widget _buildGroupedListView(List<EquipmentModel> equipmentList) {
    // Nach Besitzer gruppieren
    Map<String, List<EquipmentModel>> ownerGroups = {};
    for (var equipment in equipmentList) {
      ownerGroups.putIfAbsent(equipment.owner, () => []).add(equipment);
    }

    // Nach Besitzer sortieren
    List<String> sortedOwners = ownerGroups.keys.toList()..sort();

    return ListView.separated(
      itemCount: sortedOwners.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final owner = sortedOwners[index];
        final ownerEquipment = ownerGroups[owner]!;

        // Nach Typ sortieren
        ownerEquipment.sort((a, b) => a.type.compareTo(b.type));

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Column(
            children: [
              // Header für Besitzer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        owner,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${ownerEquipment.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Equipment-Liste für diesen Besitzer
              ...ownerEquipment.map((equipment) => _buildEquipmentItem(equipment)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNormalListView(List<EquipmentModel> equipmentList) {
    return Column(
      children: [
        // Header mit Auswahl-Optionen (nur für Admins)
        if (equipmentList.isNotEmpty && _canEditEquipment)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Checkbox(
                  value: _selectedEquipmentIds.length == equipmentList.length && equipmentList.isNotEmpty,
                  onChanged: (value) => _selectAll(equipmentList),
                ),
                Text(
                  '${equipmentList.length} Ausrüstungsgegenstände',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_selectionMode)
                  Text(
                    '${_selectedEquipmentIds.length} ausgewählt',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
              ],
            ),
          )
        else if (equipmentList.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Text(
                  '${equipmentList.length} Ausrüstungsgegenstände',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_hasExtendedReadAccess)
                  Text(
                    _permissionService.getUserRole as String,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),

        // Equipment-Liste
        Expanded(
          child: ListView.builder(
            itemCount: equipmentList.length,
            itemBuilder: (context, index) {
              return _buildEquipmentItem(equipmentList[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEquipmentItem(EquipmentModel equipment) {
    final bool isSelected = _selectedEquipmentIds.contains(equipment.id);
    final formattedCheckDate = DateFormat('dd.MM.yyyy').format(equipment.checkDate);
    final bool isCheckDateExpired = equipment.checkDate.isBefore(
        DateTime.now().subtract(const Duration(days: 365)));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (equipment.status == EquipmentStatus.ready
                ? Colors.green.withOpacity(0.3)
                : Colors.grey.withOpacity(0.2)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _selectionMode && _canEditEquipment
              ? () => _toggleSelection(equipment.id)
              : () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EquipmentDetailScreen(equipment: equipment),
              ),
            );
          },
          onLongPress: _canEditEquipment ? () {
            if (_selectionMode) {
              _toggleSelection(equipment.id);
            } else {
              setState(() {
                _selectionMode = true;
                _selectedEquipmentIds.add(equipment.id);
              });
            }
          } : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Checkbox für Mehrfachauswahl (nur für Admins)
                if (_selectionMode && _canEditEquipment)
                  Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) => _toggleSelection(equipment.id),
                  ),

                // Icon für Jacke/Hose
                Container(
                  decoration: BoxDecoration(
                    color: equipment.type == 'Jacke'
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    equipment.type == 'Jacke'
                        ? Icons.accessibility_new
                        : Icons.airline_seat_legroom_normal,
                    color: equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        equipment.article,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            EquipmentStatus.getStatusIcon(equipment.status),
                            color: EquipmentStatus.getStatusColor(equipment.status),
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            equipment.status,
                            style: TextStyle(
                              color: EquipmentStatus.getStatusColor(equipment.status),
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Besitzer: ${equipment.owner}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        'Größe: ${equipment.size}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        'Prüfdatum: $formattedCheckDate',
                        style: TextStyle(
                          fontSize: 11,
                          color: isCheckDateExpired ? Colors.red : Colors.black87,
                        ),
                      ),
                      // Ortswehr nur anzeigen wenn erweiterte Rechte vorhanden
                      if (_hasExtendedReadAccess)
                        Text(
                          'Ortswehr: ${equipment.fireStation}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),

                // Berechtigung-Indikator
                if (!_canEditEquipment && (_isHygieneUnit || _hasExtendedReadAccess))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.visibility,
                      size: 16,
                      color: Colors.orange,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ortsfeuerwehr-Filter nur für Benutzer mit erweiterten Rechten anzeigen
              if (_hasExtendedReadAccess) ...[
                const Text('Ortsfeuerwehr'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterFireStation,
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
                          Text(station),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _filterFireStation = newValue;
                      });
                    }
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('Typ'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _filterType,
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Status'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _filterStatus,
                items: _statusOptions.map((String status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: status == 'Alle'
                        ? const Text('Alle')
                        : Row(
                      children: [
                        Icon(
                          EquipmentStatus.getStatusIcon(status),
                          color: EquipmentStatus.getStatusColor(status),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(status),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _filterStatus = newValue;
                    });
                  }
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anwenden'),
          ),
        ],
      ),
    );
  }

}