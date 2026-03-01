// screens/missions/mission_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/mission_model.dart';
import '../../models/user_models.dart';
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

  UserModel? _currentUser;
  bool _isLoading = true;
  String _searchQuery = '';
  String? _filterType;

  // Berechtigungen
  bool get _canAdd =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.missionAdd == true;
  bool get _canViewAll =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.visibleFireStations.contains('*') == true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    final user = await _permissionService.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
    }
  }

  List<MissionModel> _applyFilters(List<MissionModel> missions) {
    var result = missions;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((m) =>
              m.name.toLowerCase().contains(q) ||
              m.location.toLowerCase().contains(q) ||
              m.fireStation.toLowerCase().contains(q))
          .toList();
    }
    if (_filterType != null) {
      result = result.where((m) => m.type == _filterType).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsätze'),
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
                // Suchfeld
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Einsatz suchen...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: EdgeInsets.zero,
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

                // Aktiver Filter-Chip
                if (_filterType != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Chip(
                          avatar: Icon(_getTypeIcon(_filterType!), size: 16),
                          label: Text(_getTypeName(_filterType!)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => setState(() => _filterType = null),
                        ),
                      ],
                    ),
                  ),

                // Einsatzliste
                Expanded(
                  child: StreamBuilder<List<MissionModel>>(
                    stream: _missionService
                        .getMissionsForCurrentUser(_currentUser),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 64,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error),
                                const SizedBox(height: 16),
                                Text('Fehler beim Laden: ${snapshot.error}',
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        );
                      }

                      final missions =
                          _applyFilters(snapshot.data ?? []);

                      if (missions.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.assignment_outlined,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty ||
                                        _filterType != null
                                    ? 'Keine Einsätze gefunden'
                                    : 'Noch keine Einsätze vorhanden',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _loadUser,
                        child: ListView.builder(
                          itemCount: missions.length,
                          padding: const EdgeInsets.only(bottom: 80),
                          itemBuilder: (_, i) =>
                              _buildMissionCard(missions[i]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _canAdd
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AddMissionScreen()),
                );
              },
              tooltip: 'Einsatz hinzufügen',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildMissionCard(MissionModel mission) {
    final typeIcon = _getTypeIcon(mission.type);
    final typeColor = _getTypeColor(mission.type);
    final typeText = _getTypeName(mission.type);
    final formattedDate =
        DateFormat('dd.MM.yyyy').format(mission.startTime);
    final formattedTime = DateFormat('HH:mm').format(mission.startTime);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withOpacity(0.15),
          child: Icon(typeIcon, color: typeColor, size: 22),
        ),
        title: Text(mission.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$formattedDate · $formattedTime Uhr'),
            Text(mission.location,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: typeColor.withOpacity(0.4)),
                  ),
                  child: Text(typeText,
                      style: TextStyle(
                          fontSize: 11,
                          color: typeColor,
                          fontWeight: FontWeight.w600)),
                ),
                if (_canViewAll && mission.fireStation.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text('· ${mission.fireStation}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                ],
              ],
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  MissionDetailScreen(missionId: mission.id)),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    final types = {
      'fire': ('Brand', Icons.local_fire_department),
      'technical': ('Technisch', Icons.build),
      'hazmat': ('Gefahrgut', Icons.dangerous),
      'water': ('Wasser', Icons.water),
      'training': ('Übung', Icons.school),
      'other': ('Sonstiges', Icons.more_horiz),
    };

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Filter'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Einsatztyp',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('Alle'),
                    selected: _filterType == null,
                    onSelected: (_) {
                      setDialogState(() => _filterType = null);
                      setState(() => _filterType = null);
                    },
                  ),
                  ...types.entries.map((e) => FilterChip(
                        avatar: Icon(e.value.$2, size: 14),
                        label: Text(e.value.$1),
                        selected: _filterType == e.key,
                        onSelected: (_) {
                          setDialogState(() => _filterType = e.key);
                          setState(() => _filterType = e.key);
                        },
                      )),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () {
                  setState(() => _filterType = null);
                  Navigator.pop(ctx);
                },
                child: const Text('Zurücksetzen')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen')),
          ],
        ),
      ),
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'fire':
        return Icons.local_fire_department;
      case 'technical':
        return Icons.build;
      case 'hazmat':
        return Icons.dangerous;
      case 'water':
        return Icons.water;
      case 'training':
        return Icons.school;
      default:
        return Icons.more_horiz;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'fire':
        return Colors.red;
      case 'technical':
        return Colors.blue;
      case 'hazmat':
        return Colors.orange;
      case 'water':
        return Colors.lightBlue;
      case 'training':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getTypeName(String type) {
    switch (type) {
      case 'fire':
        return 'Brandeinsatz';
      case 'technical':
        return 'Technische Hilfeleistung';
      case 'hazmat':
        return 'Gefahrguteinsatz';
      case 'water':
        return 'Wasser/Hochwasser';
      case 'training':
        return 'Übung';
      default:
        return 'Sonstiger Einsatz';
    }
  }
}
