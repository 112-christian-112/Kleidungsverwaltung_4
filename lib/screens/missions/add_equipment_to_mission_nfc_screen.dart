// screens/missions/add_equipment_to_mission_nfc_screen.dart
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'dart:async';
import '../../models/equipment_model.dart';
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
    extends State<AddEquipmentToMissionNfcScreen> with TickerProviderStateMixin {
  final EquipmentService _equipmentService = EquipmentService();
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  late TabController _tabController;
  Timer? _resetTimer;

  // NFC Tab
  bool _isScanning = false;
  bool _isNfcAvailable = false;
  bool _sessionActive = false;
  String _statusMessage = 'Bereit zum Scannen';
  String _lastScannedTagId = '';

  // Manual Tab - Vereinfachte Filter
  String _userFireStation = '';
  String _searchQuery = '';
  bool _isLoadingUserData = true;
  bool _isAdmin = false;
  List<String> _availableFireStations = [];

  // Filter- und Sortieroptionen
  String _selectedFireStationFilter = 'Alle';
  String _selectedOwnerFilter = 'Alle';
  String _selectedTypeFilter = 'Alle';
  String _selectedStatusFilter = 'Einsatzbereit';
  String _sortBy = 'owner';
  bool _groupByOwner = true;
  bool _showFilters = false;

  // NEU: Set für die geöffneten ExpansionTiles
  final Set<String> _expandedOwners = <String>{};

  // Shared
  List<EquipmentModel> _selectedEquipment = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkNfcAvailability();
    _loadUserData();
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _stopNfcSession();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoadingUserData = true;
    });

    try {
      final userFireStation = await _permissionService.getUserFireStation();
      final isAdmin = await _permissionService.isAdmin();

      // Verfügbare Feuerwehren ermitteln
      List<String> availableFireStations = [userFireStation];

      if (isAdmin) {
        // Für Admins: Alle beteiligten Feuerwehren aus der Mission laden
        final mission = await _missionService.getMissionById(widget.missionId);
        if (mission != null) {
          final Set<String> fireStations = {
            mission.fireStation,
            ...mission.involvedFireStations,
            userFireStation, // Eigene Feuerwehr sicherheitshalber
          };
          availableFireStations = fireStations.toList()..sort();
        }
      }

      if (mounted) {
        setState(() {
          _userFireStation = userFireStation;
          _isAdmin = isAdmin;
          _availableFireStations = availableFireStations;
          _isLoadingUserData = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Benutzerdaten: $e');
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
        });
      }
    }
  }

  Future<void> _checkNfcAvailability() async {
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      if (mounted) {
        setState(() {
          _isNfcAvailable = isAvailable;
          if (isAvailable) {
            _statusMessage = 'Bereit zum Scannen';
          } else {
            _statusMessage = 'NFC ist auf diesem Gerät nicht verfügbar';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isNfcAvailable = false;
          _statusMessage = 'Fehler beim Prüfen der NFC-Verfügbarkeit';
        });
      }
    }
  }

  void _startContinuousNfcSession() {
    if (_sessionActive || !_isNfcAvailable) return;

    setState(() {
      _isScanning = true;
      _statusMessage = 'NFC-Tag scannen...';
      _sessionActive = true;
    });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          var tagId = _extractTagIdFast(tag);

          if (tagId.isNotEmpty && tagId != _lastScannedTagId) {
            _lastScannedTagId = tagId;
            await _processScannedTag(tagId);
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Fehler beim Lesen des NFC-Tags: $e';
            });
            _resetStatusAfterDelay();
          }
        }
      },
      onError: (error) async {
        if (mounted) {
          setState(() {
            _statusMessage = 'NFC-Fehler: $error';
            _sessionActive = false;
          });
        }
      },
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
        NfcPollingOption.iso18092,
      },
    );
  }

  String _extractTagIdFast(NfcTag tag) {
    try {
      if (tag.data.containsKey('nfca')) {
        final nfcA = tag.data['nfca']['identifier'];
        if (nfcA != null) {
          return _bytesToHex(nfcA);
        }
      }

      if (tag.data.containsKey('ndef')) {
        final ndefTag = tag.data['ndef']['identifier'];
        if (ndefTag != null) {
          return _bytesToHex(ndefTag);
        }
      }

      if (tag.data.containsKey('nfcb')) {
        final nfcB = tag.data['nfcb']['applicationData'];
        if (nfcB != null) {
          return _bytesToHex(nfcB);
        }
      }

      if (tag.data.containsKey('nfcf')) {
        final nfcF = tag.data['nfcf']['identifier'];
        if (nfcF != null) {
          return _bytesToHex(nfcF);
        }
      }

      if (tag.data.containsKey('nfcv')) {
        final nfcV = tag.data['nfcv']['identifier'];
        if (nfcV != null) {
          return _bytesToHex(nfcV);
        }
      }

      for (final key in tag.data.keys) {
        final tagData = tag.data[key];
        if (tagData != null && tagData['identifier'] != null) {
          return _bytesToHex(tagData['identifier']);
        }
      }
    } catch (e) {
      print('Fehler bei schneller Tag-ID-Extraktion: $e');
    }

    return '';
  }

  String _bytesToHex(List<int> bytes) {
    if (bytes.isEmpty) return '';

    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      if (i > 0) buffer.write(':');
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return buffer.toString();
  }

  Future<void> _processScannedTag(String tagId) async {
    try {
      final equipment = await _equipmentService.getEquipmentByNfcTag(tagId);

      if (equipment == null) {
        setState(() {
          _statusMessage = 'Keine Ausrüstung mit diesem NFC-Tag gefunden';
        });
        _resetStatusAfterDelay();
        return;
      }

      if (widget.alreadyAddedEquipmentIds.contains(equipment.id)) {
        setState(() {
          _statusMessage = 'Diese Ausrüstung wurde bereits zum Einsatz hinzugefügt';
        });
        _resetStatusAfterDelay();
        return;
      }

      if (_selectedEquipment.any((e) => e.id == equipment.id)) {
        setState(() {
          _statusMessage = 'Diese Ausrüstung ist bereits ausgewählt';
        });
        _resetStatusAfterDelay();
        return;
      }

      if (equipment.status != EquipmentStatus.ready) {
        setState(() {
          _statusMessage = 'Diese Ausrüstung ist nicht einsatzbereit (Status: ${equipment.status})';
        });
        _resetStatusAfterDelay();
        return;
      }

      setState(() {
        _selectedEquipment.add(equipment);
        _statusMessage = 'Ausrüstung erfolgreich gescannt: ${equipment.article}';
      });
      _resetStatusAfterDelay();
    } catch (e) {
      setState(() {
        _statusMessage = 'Fehler beim Verarbeiten: $e';
      });
      _resetStatusAfterDelay();
    }
  }

  void _resetStatusAfterDelay() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _statusMessage = 'Bereit zum Scannen';
        });
      }
    });
  }

  Future<void> _stopNfcSession() async {
    try {
      _resetTimer?.cancel();
      _sessionActive = false;
      await NfcManager.instance.stopSession();
    } catch (e) {
      print('Fehler beim Stoppen der NFC-Session: $e');
    }
  }

  void _restartNfcSession() {
    _stopNfcSession().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _startContinuousNfcSession();
        }
      });
    });
  }

  void _toggleEquipmentSelection(EquipmentModel equipment) {
    setState(() {
      final index = _selectedEquipment.indexWhere((e) => e.id == equipment.id);
      if (index >= 0) {
        _selectedEquipment.removeAt(index);
      } else {
        _selectedEquipment.add(equipment);
      }
    });
  }

  bool _isEquipmentSelected(EquipmentModel equipment) {
    return _selectedEquipment.any((e) => e.id == equipment.id);
  }

  bool _isEquipmentAlreadyAdded(EquipmentModel equipment) {
    return widget.alreadyAddedEquipmentIds.contains(equipment.id);
  }

  // Vereinfachte Filterfunktionen
  List<EquipmentModel> _filterAndSortEquipment(List<EquipmentModel> equipmentList) {
    List<EquipmentModel> filtered = equipmentList;

    // Ortswehr-Filter anwenden
    if (_selectedFireStationFilter != 'Alle') {
      filtered = filtered.where((e) => e.fireStation == _selectedFireStationFilter).toList();
    }

    // Status-Filter anwenden
    switch (_selectedStatusFilter) {
      case 'Einsatzbereit':
        filtered = filtered.where((e) => e.status == EquipmentStatus.ready).toList();
        break;
      case 'In Reinigung':
        filtered = filtered.where((e) => e.status == EquipmentStatus.cleaning).toList();
        break;
      case 'Ausgemustert':
        filtered = filtered.where((e) => e.status == EquipmentStatus.retired).toList();
        break;
    }

    // Typ-Filter anwenden
    if (_selectedTypeFilter != 'Alle') {
      filtered = filtered.where((e) => e.type == _selectedTypeFilter).toList();
    }

    // Besitzer-Filter anwenden
    if (_selectedOwnerFilter != 'Alle') {
      filtered = filtered.where((e) => e.owner == _selectedOwnerFilter).toList();
    }

    // Suchbegriff-Filter anwenden
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((equipment) =>
      equipment.nfcTag.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (equipment.barcode != null &&
              equipment.barcode!.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          equipment.owner.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          equipment.article.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          equipment.size.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Sortierung anwenden
    switch (_sortBy) {
      case 'owner':
        filtered.sort((a, b) => a.owner.compareTo(b.owner));
        break;
      case 'fireStation':
        filtered.sort((a, b) => a.fireStation.compareTo(b.fireStation));
        break;
      case 'type':
        filtered.sort((a, b) => a.type.compareTo(b.type));
        break;
      case 'article':
        filtered.sort((a, b) => a.article.compareTo(b.article));
        break;
      case 'size':
        filtered.sort((a, b) => a.size.compareTo(b.size));
        break;
    }

    return filtered;
  }

  // Gruppierung nach Besitzern
  Map<String, List<EquipmentModel>> _groupEquipmentByOwner(List<EquipmentModel> equipmentList) {
    final Map<String, List<EquipmentModel>> grouped = {};

    for (var equipment in equipmentList) {
      if (!grouped.containsKey(equipment.owner)) {
        grouped[equipment.owner] = [];
      }
      grouped[equipment.owner]!.add(equipment);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    final Map<String, List<EquipmentModel>> sortedGrouped = {};

    for (var key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
    }

    return sortedGrouped;
  }

  // Eindeutige Werte für Filter-Dropdowns extrahieren
  List<String> _getUniqueOwners(List<EquipmentModel> equipmentList) {
    final owners = equipmentList.map((e) => e.owner).toSet().toList();
    owners.sort();
    return ['Alle', ...owners];
  }

  List<String> _getUniqueTypes(List<EquipmentModel> equipmentList) {
    final types = equipmentList.map((e) => e.type).toSet().toList();
    types.sort();
    return ['Alle', ...types];
  }

  List<String> _getUniqueFireStations(List<EquipmentModel> equipmentList) {
    final fireStations = equipmentList.map((e) => e.fireStation).toSet().toList();
    fireStations.sort();
    return ['Alle', ...fireStations];
  }

  void _resetFilters() {
    setState(() {
      _selectedFireStationFilter = 'Alle';
      _selectedOwnerFilter = 'Alle';
      _selectedTypeFilter = 'Alle';
      _selectedStatusFilter = 'Einsatzbereit';
      _searchQuery = '';
      _sortBy = 'owner';
      _groupByOwner = true;
    });
  }

  Future<void> _saveSelectedEquipment() async {
    if (_selectedEquipment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine Ausrüstung ausgewählt'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final List<String> equipmentIds = _selectedEquipment.map((e) => e.id).toList();
      await _missionService.addEquipmentToMission(widget.missionId, equipmentIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ausrüstung erfolgreich zum Einsatz hinzugefügt'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausrüstung hinzufügen'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.nfc),
              text: 'NFC Scan',
            ),
            Tab(
              icon: Icon(Icons.list),
              text: 'Manuell',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNfcTab(),
          _buildManualTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildNfcTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status-Indikator und Steuerung
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _sessionActive ? Colors.green[100] : Colors.red[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _sessionActive ? Colors.green : Colors.red,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _sessionActive ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                          size: 14,
                          color: _sessionActive ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _sessionActive ? 'NFC Session aktiv' : 'NFC Session gestoppt',
                          style: TextStyle(
                            fontSize: 11,
                            color: _sessionActive ? Colors.green[800] : Colors.red[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Icon(
                        _isScanning ? Icons.nfc : (_isNfcAvailable ? Icons.check_circle : Icons.error),
                        color: _isScanning
                            ? Colors.blue
                            : (_isNfcAvailable ? Colors.green : Colors.red),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isNfcAvailable && !_sessionActive ? _startContinuousNfcSession : null,
                          icon: const Icon(Icons.nfc),
                          label: Text(_sessionActive ? 'Scannen läuft...' : 'NFC-Scan starten'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sessionActive ? Colors.green : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _sessionActive ? _restartNfcSession : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Neustart'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Ausgewählte Ausrüstung (${_selectedEquipment.length})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildSelectedEquipmentList(),
          ),
        ],
      ),
    );
  }

  Widget _buildManualTab() {
    if (_isLoadingUserData) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Admin-Info und Suchfeld
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Admin-Hinweis (wenn relevant)
              if (_isAdmin && _availableFireStations.length > 1)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: Colors.blue.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Admin-Ansicht: Ausrüstung aller beteiligten Ortswehren verfügbar',
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

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Suchen',
                        hintText: 'Nach Besitzer, Artikel oder NFC-Tag suchen...',
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
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _showFilters ? Icons.filter_list_off : Icons.filter_list,
                      color: _showFilters ? Colors.blue : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _showFilters = !_showFilters;
                      });
                    },
                    tooltip: _showFilters ? 'Filter ausblenden' : 'Filter anzeigen',
                  ),
                ],
              ),

              // Filter-Bereich
              if (_showFilters) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Filter und Sortierung',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: _resetFilters,
                              child: const Text('Zurücksetzen'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Gruppierung Toggle
                        Row(
                          children: [
                            const Text('Nach Besitzer gruppieren:'),
                            const SizedBox(width: 8),
                            Switch(
                              value: _groupByOwner,
                              onChanged: (value) {
                                setState(() {
                                  _groupByOwner = value;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _buildFilterDropdowns(),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Ausrüstungsliste
        Expanded(
          child: StreamBuilder<List<EquipmentModel>>(
            stream: _equipmentService.getEquipmentByMultipleFireStations(_availableFireStations),
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

              // Filter und Sortierung anwenden
              final filteredEquipment = _filterAndSortEquipment(snapshot.data!);

              if (filteredEquipment.isEmpty) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Keine passende Einsatzkleidung gefunden',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _resetFilters,
                      child: const Text('Filter zurücksetzen'),
                    ),
                  ],
                );
              }

              // Gruppiert oder normale Anzeige
              if (_groupByOwner) {
                return _buildGroupedEquipmentList(filteredEquipment);
              } else {
                return _buildRegularEquipmentList(filteredEquipment);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdowns() {
    return StreamBuilder<List<EquipmentModel>>(
      stream: _equipmentService.getEquipmentByMultipleFireStations(_availableFireStations),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final allEquipment = snapshot.data!;
        final uniqueFireStations = _getUniqueFireStations(allEquipment);
        final uniqueOwners = _getUniqueOwners(allEquipment);
        final uniqueTypes = _getUniqueTypes(allEquipment);

        return Column(
          children: [
            // Erste Zeile: Ortswehr und Status
            Row(
              children: [
                // Ortswehr-Filterung
                if (_isAdmin && _availableFireStations.length > 1)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: uniqueFireStations.contains(_selectedFireStationFilter)
                          ? _selectedFireStationFilter
                          : 'Alle',
                      decoration: const InputDecoration(
                        labelText: 'Ortswehr',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: uniqueFireStations
                          .map((fireStation) => DropdownMenuItem(
                        value: fireStation,
                        child: Text(
                          fireStation,
                          style: TextStyle(
                            fontWeight: fireStation == _userFireStation
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedFireStationFilter = value!;
                        });
                      },
                    ),
                  ),
                if (_isAdmin && _availableFireStations.length > 1) const SizedBox(width: 8),

                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedStatusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ['Alle', 'Einsatzbereit', 'In Reinigung', 'Defekt']
                        .map((status) => DropdownMenuItem(
                      value: status,
                      child: Text(status),
                    ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedStatusFilter = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Zweite Zeile: Typ und Besitzer
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: uniqueTypes.contains(_selectedTypeFilter)
                        ? _selectedTypeFilter
                        : 'Alle',
                    decoration: const InputDecoration(
                      labelText: 'Typ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: uniqueTypes
                        .map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTypeFilter = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: uniqueOwners.contains(_selectedOwnerFilter)
                        ? _selectedOwnerFilter
                        : 'Alle',
                    decoration: const InputDecoration(
                      labelText: 'Besitzer',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: uniqueOwners
                        .map((owner) => DropdownMenuItem(
                      value: owner,
                      child: Text(owner),
                    ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedOwnerFilter = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Dritte Zeile: Sortierung
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _sortBy,
                    decoration: const InputDecoration(
                      labelText: 'Sortieren nach',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(value: 'owner', child: Text('Besitzer')),
                      if (_isAdmin && _availableFireStations.length > 1)
                        const DropdownMenuItem(value: 'fireStation', child: Text('Ortswehr')),
                      const DropdownMenuItem(value: 'type', child: Text('Typ')),
                      const DropdownMenuItem(value: 'article', child: Text('Artikel')),
                      const DropdownMenuItem(value: 'size', child: Text('Größe')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _sortBy = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupedEquipmentList(List<EquipmentModel> equipmentList) {
    final groupedEquipment = _groupEquipmentByOwner(equipmentList);

    return ListView.builder(
      itemCount: groupedEquipment.length,
      itemBuilder: (context, groupIndex) {
        final owner = groupedEquipment.keys.elementAt(groupIndex);
        final ownerEquipment = groupedEquipment[owner]!;

        final selectedInGroup = ownerEquipment.where((e) => _isEquipmentSelected(e)).length;
        final totalInGroup = ownerEquipment.length;
        final availableInGroup = ownerEquipment.where((e) => !_isEquipmentAlreadyAdded(e)).length;

        // NEU: Prüfen ob diese Gruppe erweitert ist
        final isExpanded = _expandedOwners.contains(owner);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: ExpansionTile(
            // NEU: initiallyExpanded basierend auf dem gespeicherten Zustand
            initiallyExpanded: isExpanded,
            // NEU: onExpansionChanged Callback um den Zustand zu speichern
            onExpansionChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedOwners.add(owner);
                } else {
                  _expandedOwners.remove(owner);
                }
              });
            },
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(
                owner.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
            title: Text(
              owner,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              '$selectedInGroup von $availableInGroup ausgewählt ($totalInGroup gesamt)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 12,
              ),
            ),
            trailing: availableInGroup > 0
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.select_all, size: 20),
                  onPressed: () {
                    setState(() {
                      for (var equipment in ownerEquipment) {
                        if (!_isEquipmentAlreadyAdded(equipment) &&
                            !_isEquipmentSelected(equipment)) {
                          _selectedEquipment.add(equipment);
                        }
                      }
                    });
                  },
                  tooltip: 'Alle von $owner auswählen',
                ),
                IconButton(
                  icon: const Icon(Icons.deselect, size: 20),
                  onPressed: () {
                    setState(() {
                      _selectedEquipment.removeWhere((selected) =>
                          ownerEquipment.any((owner) => owner.id == selected.id));
                    });
                  },
                  tooltip: 'Alle von $owner abwählen',
                ),
                const Icon(Icons.expand_more),
              ],
            )
                : const Icon(Icons.expand_more),
            children: ownerEquipment.map((equipment) {
              final isSelected = _isEquipmentSelected(equipment);
              final isAlreadyAdded = _isEquipmentAlreadyAdded(equipment);

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
                leading: CircleAvatar(
                  backgroundColor: equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
                  child: Icon(
                    equipment.type == 'Jacke'
                        ? Icons.accessibility_new
                        : Icons.airline_seat_legroom_normal,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  equipment.article,
                  style: TextStyle(
                    color: isAlreadyAdded ? Colors.grey : null,
                    fontSize: 14,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Größe: ${equipment.size}',
                      style: TextStyle(
                        color: isAlreadyAdded ? Colors.grey : null,
                        fontSize: 12,
                      ),
                    ),
                    // Ortswehr-Info für Multi-Feuerwehr-Anzeige
                    if (_isAdmin && _availableFireStations.length > 1)
                      Text(
                        'Ortswehr: ${equipment.fireStation}',
                        style: TextStyle(
                          color: isAlreadyAdded ? Colors.grey.shade600 : Colors.blue.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (isAlreadyAdded)
                      const Text(
                        'Bereits zum Einsatz hinzugefügt',
                        style: TextStyle(
                          color: Colors.orange,
                          fontStyle: FontStyle.italic,
                          fontSize: 11,
                        ),
                      ),
                    // Status-Anzeige
                    Row(
                      children: [
                        Icon(
                          EquipmentStatus.getStatusIcon(equipment.status),
                          size: 12,
                          color: EquipmentStatus.getStatusColor(equipment.status),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          equipment.status,
                          style: TextStyle(
                            color: EquipmentStatus.getStatusColor(equipment.status),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: isAlreadyAdded
                    ? const Icon(Icons.check, color: Colors.grey, size: 20)
                    : Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    _toggleEquipmentSelection(equipment);
                  },
                ),
                onTap: isAlreadyAdded
                    ? null
                    : () => _toggleEquipmentSelection(equipment),
                enabled: !isAlreadyAdded,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildRegularEquipmentList(List<EquipmentModel> equipmentList) {
    return ListView.builder(
      itemCount: equipmentList.length,
      itemBuilder: (context, index) {
        final equipment = equipmentList[index];
        final isSelected = _isEquipmentSelected(equipment);
        final isAlreadyAdded = _isEquipmentAlreadyAdded(equipment);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
              child: Icon(
                equipment.type == 'Jacke'
                    ? Icons.accessibility_new
                    : Icons.airline_seat_legroom_normal,
                color: Colors.white,
              ),
            ),
            title: Text(
              equipment.article,
              style: TextStyle(
                color: isAlreadyAdded ? Colors.grey : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Besitzer: ${equipment.owner} | Größe: ${equipment.size}',
                  style: TextStyle(
                    color: isAlreadyAdded ? Colors.grey : null,
                  ),
                ),
                // Ortswehr-Info für Multi-Feuerwehr-Anzeige
                if (_isAdmin && _availableFireStations.length > 1)
                  Text(
                    'Ortswehr: ${equipment.fireStation}',
                    style: TextStyle(
                      color: isAlreadyAdded ? Colors.grey.shade600 : Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (isAlreadyAdded)
                  const Text(
                    'Bereits zum Einsatz hinzugefügt',
                    style: TextStyle(
                      color: Colors.orange,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                  ),
                // Status-Anzeige
                Row(
                  children: [
                    Icon(
                      EquipmentStatus.getStatusIcon(equipment.status),
                      size: 14,
                      color: EquipmentStatus.getStatusColor(equipment.status),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Status: ${equipment.status}',
                      style: TextStyle(
                        color: EquipmentStatus.getStatusColor(equipment.status),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: isAlreadyAdded
                ? const Icon(Icons.check, color: Colors.grey)
                : Checkbox(
              value: isSelected,
              onChanged: (value) {
                _toggleEquipmentSelection(equipment);
              },
            ),
            onTap: isAlreadyAdded
                ? null
                : () => _toggleEquipmentSelection(equipment),
            enabled: !isAlreadyAdded,
          ),
        );
      },
    );
  }

  Widget _buildSelectedEquipmentList() {
    if (_selectedEquipment.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Noch keine Ausrüstung ausgewählt',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Starten Sie den NFC-Scan oder wählen Sie manuell aus',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    // Gruppiere ausgewählte Ausrüstung nach Besitzern für bessere Übersicht
    final groupedSelected = _groupEquipmentByOwner(_selectedEquipment);

    return ListView.builder(
      itemCount: groupedSelected.length,
      itemBuilder: (context, groupIndex) {
        final owner = groupedSelected.keys.elementAt(groupIndex);
        final ownerEquipment = groupedSelected[owner]!;

        if (ownerEquipment.length == 1) {
          // Einzelnes Item ohne Gruppierung anzeigen
          final equipment = ownerEquipment.first;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
                child: Icon(
                  equipment.type == 'Jacke'
                      ? Icons.accessibility_new
                      : Icons.airline_seat_legroom_normal,
                  color: Colors.white,
                ),
              ),
              title: Text(equipment.article),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Besitzer: ${equipment.owner} | Größe: ${equipment.size}'),
                  if (_isAdmin && _availableFireStations.length > 1)
                    Text(
                      'Ortswehr: ${equipment.fireStation}',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _selectedEquipment.remove(equipment);
                  });
                },
              ),
            ),
          );
        } else {
          // Gruppierte Anzeige für mehrere Items vom selben Besitzer
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade100,
                child: Text(
                  owner.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
              title: Text(
                owner,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${ownerEquipment.length} Artikel ausgewählt'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() {
                        for (var equipment in ownerEquipment) {
                          _selectedEquipment.remove(equipment);
                        }
                      });
                    },
                    tooltip: 'Alle von $owner entfernen',
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: ownerEquipment.map((equipment) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
                  leading: CircleAvatar(
                    backgroundColor: equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
                    child: Icon(
                      equipment.type == 'Jacke'
                          ? Icons.accessibility_new
                          : Icons.airline_seat_legroom_normal,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    equipment.article,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Größe: ${equipment.size}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (_isAdmin && _availableFireStations.length > 1)
                        Text(
                          'Ortswehr: ${equipment.fireStation}',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() {
                        _selectedEquipment.remove(equipment);
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          );
        }
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedEquipment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedEquipment.length} Artikel ausgewählt',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedEquipment.clear();
                      });
                    },
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
                  : _saveSelectedEquipment,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isProcessing
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text(
                'Ausrüstung zum Einsatz hinzufügen',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}