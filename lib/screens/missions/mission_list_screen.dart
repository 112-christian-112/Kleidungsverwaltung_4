// screens/missions/mission_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/mission_model.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';

import 'add_missions_screen.dart';
import 'mission_detail_screen.dart';

class MissionListScreen extends StatefulWidget {
  const MissionListScreen({Key? key}) : super(key: key);

  @override
  State<MissionListScreen> createState() => _MissionListScreenState();
}

class _MissionListScreenState extends State<MissionListScreen> {
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  // Berechtigungsstatus
  bool _isAdmin = false;
  bool _isHygieneUnit = false;
  bool _canViewAllMissions = false;
  bool _canEditMissions = false;
  String _userRole = 'user';
  String _userFireStation = '';

  bool _isLoading = true;
  String _searchQuery = '';
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAdmin = await _permissionService.isAdmin();
      final isHygieneUnit = await _permissionService.isHygieneUnit();
      final canViewAllMissions = await _permissionService.canViewAllMissions();
      final canEditMissions = await _permissionService.canEditMissions();
      final userRole = await _permissionService.getUserRole();
      final userFireStation = await _permissionService.getUserFireStation();

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _isHygieneUnit = isHygieneUnit;
          _canViewAllMissions = canViewAllMissions;
          _canEditMissions = canEditMissions;
          _userRole = userRole;
          _userFireStation = userFireStation;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Benutzerinformationen: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Einsätze'),
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
          // Berechtigung-Info für Hygieneeinheit
          if (_isHygieneUnit && !_isAdmin)
            Container(
              margin: const EdgeInsets.all(8.0),
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
                      'Hygieneeinheit-Ansicht: Sie können alle Einsätze einsehen',
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

          // Suchfeld
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Suchen',
                hintText: 'Nach Einsatzname oder Ort suchen...',
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

          // Statistik-Banner für erweiterte Berechtigungen
          if (_canViewAllMissions)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    Theme.of(context).colorScheme.primary.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isAdmin ? Icons.admin_panel_settings : Icons.local_laundry_service,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isAdmin
                          ? 'Administrator-Ansicht: Alle Einsätze aller Ortswehren'
                          : 'Hygieneeinheit-Ansicht: Alle Einsätze aller Ortswehren',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: StreamBuilder<List<MissionModel>>(
              stream: _missionService.getMissionsForCurrentUser(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Fehler beim Laden der Daten',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Keine Einsätze vorhanden',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _canViewAllMissions
                                ? 'Es wurden noch keine Einsätze erfasst'
                                : 'Ihre Ortswehr war noch bei keinem Einsatz beteiligt',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                List<MissionModel> missionList = snapshot.data!;

                // Filtern nach Suchbegriff
                if (_searchQuery.isNotEmpty) {
                  missionList = missionList
                      .where((mission) =>
                  mission.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      mission.location.toLowerCase().contains(_searchQuery.toLowerCase()))
                      .toList();
                }

                // Filtern nach Typ
                if (_filterType != null) {
                  missionList = missionList
                      .where((mission) => mission.type == _filterType)
                      .toList();
                }

                if (missionList.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Keine passenden Einsätze gefunden',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Versuchen Sie andere Suchbegriffe oder Filter',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: missionList.length,
                  itemBuilder: (context, index) {
                    final mission = missionList[index];

                    // Icon und Farbe basierend auf Einsatztyp
                    IconData typeIcon;
                    Color typeColor;

                    switch (mission.type) {
                      case 'fire':
                        typeIcon = Icons.local_fire_department;
                        typeColor = Colors.red;
                        break;
                      case 'technical':
                        typeIcon = Icons.build;
                        typeColor = Colors.blue;
                        break;
                      case 'hazmat':
                        typeIcon = Icons.dangerous;
                        typeColor = Colors.orange;
                        break;
                      case 'water':
                        typeIcon = Icons.water;
                        typeColor = Colors.lightBlue;
                        break;
                      case 'training':
                        typeIcon = Icons.school;
                        typeColor = Colors.green;
                        break;
                      default:
                        typeIcon = Icons.more_horiz;
                        typeColor = Colors.grey;
                        break;
                    }

                    final formattedDate = DateFormat('dd.MM.yyyy').format(mission.startTime);
                    final formattedTime = DateFormat('HH:mm').format(mission.startTime);

                    // Prüfen ob die aktuelle Feuerwehr nur beteiligt oder Hauptfeuerwehr ist
                    final bool isMainFireStation = mission.fireStation == _userFireStation;
                    final bool isInvolvedFireStation = mission.involvedFireStations.contains(_userFireStation);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: typeColor.withOpacity(0.2),
                          child: Icon(typeIcon, color: typeColor),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(mission.name)),
                            // Kennzeichnung für beteiligte vs. Hauptfeuerwehr (nur für normale Benutzer relevant)
                            if (!_canViewAllMissions && !isMainFireStation && isInvolvedFireStation)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Beteiligt',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            // Berechtigung-Indikator für Hygieneeinheit
                            if (_isHygieneUnit && !_isAdmin)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: const Icon(
                                  Icons.visibility,
                                  size: 12,
                                  color: Colors.orange,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$formattedDate um $formattedTime Uhr\n${mission.location}'),
                            // Zeige beteiligte Feuerwehren an, wenn mehr als eine (für erweiterte Rechte)
                            if (_canViewAllMissions && mission.involvedFireStations.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Beteiligte: ${mission.involvedFireStations.join(', ')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.secondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            // Hauptfeuerwehr anzeigen (für erweiterte Rechte)
                            if (_canViewAllMissions)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Hauptfeuerwehr: ${mission.fireStation}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        isThreeLine: _canViewAllMissions || mission.involvedFireStations.length > 1,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${mission.equipmentIds.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              'Ausrüstung',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MissionDetailScreen(
                                missionId: mission.id,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddMissionScreen(),
            ),
          );

          if (result == true) {
            // Optional: Reload oder Feedback
          }
        },
        tooltip: 'Einsatz hinzufügen',
        child: const Icon(Icons.add),
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
            children: [
              const Text('Einsatztyp'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Alle'),
                    selected: _filterType == null,
                    onSelected: (selected) {
                      setState(() {
                        _filterType = null;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Brand'),
                    selected: _filterType == 'fire',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = selected ? 'fire' : null;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Technisch'),
                    selected: _filterType == 'technical',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = selected ? 'technical' : null;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Gefahrgut'),
                    selected: _filterType == 'hazmat',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = selected ? 'hazmat' : null;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Wasser'),
                    selected: _filterType == 'water',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = selected ? 'water' : null;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Übung'),
                    selected: _filterType == 'training',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = selected ? 'training' : null;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Sonstige'),
                    selected: _filterType == 'other',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = selected ? 'other' : null;
                      });
                    },
                  ),
                ],
              ),

              // Zusätzliche Info für erweiterte Berechtigungen
              if (_canViewAllMissions) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isAdmin ? Icons.admin_panel_settings : Icons.local_laundry_service,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isAdmin
                              ? 'Sie sehen alle Einsätze aller Ortswehren'
                              : 'Als Hygieneeinheit sehen Sie alle Einsätze',
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
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _filterType = null;
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