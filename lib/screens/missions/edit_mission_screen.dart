// screens/missions/edit_mission_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../Lists/fire_stations.dart';
import '../../models/mission_model.dart';
import '../../models/user_models.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';
import 'select_equipment_screen.dart';

class EditMissionScreen extends StatefulWidget {
  final MissionModel mission;

  const EditMissionScreen({Key? key, required this.mission}) : super(key: key);

  @override
  State<EditMissionScreen> createState() => _EditMissionScreenState();
}

class _EditMissionScreenState extends State<EditMissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startTimeController = TextEditingController();

  UserModel? _currentUser;
  bool _isLoading = true;

  DateTime _startTime = DateTime.now();
  String _missionType = 'fire';
  String _fireStation = '';
  List<String> _selectedEquipmentIds = [];
  List<String> _selectedFireStations = [];

  // Abgeleitete Berechtigungen
  bool get _canEditStation => _currentUser?.isAdmin == true;
  bool get _canEdit =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.missionEdit == true;

  List<String> get _allStations => FireStations.getAllStations();

  static const Map<String, _MissionTypeInfo> _missionTypes = {
    'fire': _MissionTypeInfo('Brandeinsatz', Icons.local_fire_department),
    'technical': _MissionTypeInfo('Technische Hilfeleistung', Icons.build),
    'hazmat': _MissionTypeInfo('Gefahrgut', Icons.dangerous),
    'water': _MissionTypeInfo('Wasser/Hochwasser', Icons.water),
    'training': _MissionTypeInfo('Übung', Icons.school),
    'other': _MissionTypeInfo('Sonstiger Einsatz', Icons.more_horiz),
  };

  @override
  void initState() {
    super.initState();
    _initFields();
    _loadUser();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _startTimeController.dispose();
    super.dispose();
  }

  // ── Initialisierung ───────────────────────────────────────────────────────

  void _initFields() {
    _nameController.text = widget.mission.name;
    _locationController.text = widget.mission.location;
    _descriptionController.text = widget.mission.description;
    _startTime = widget.mission.startTime;
    _startTimeController.text =
        DateFormat('dd.MM.yyyy HH:mm').format(_startTime);
    _missionType = widget.mission.type;
    _fireStation = widget.mission.fireStation;
    _selectedEquipmentIds = List.from(widget.mission.equipmentIds);
    _selectedFireStations = widget.mission.involvedFireStations.isNotEmpty
        ? List.from(widget.mission.involvedFireStations)
        : [widget.mission.fireStation];
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (!mounted) return;

      // Kein Edit-Recht → sofort zurück
      if (user == null ||
          (!user.isAdmin && user.permissions.missionEdit != true)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Keine Berechtigung zum Bearbeiten von Einsätzen'),
            backgroundColor: Colors.red));
        Navigator.pop(context);
        return;
      }

      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
    } catch (e) {
      print('Fehler _loadUser: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Aktionen ──────────────────────────────────────────────────────────────

  Future<void> _selectStartTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (pickedTime == null) return;

    setState(() {
      _startTime = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
          pickedTime.hour, pickedTime.minute);
      _startTimeController.text =
          DateFormat('dd.MM.yyyy HH:mm').format(_startTime);
    });
  }

  Future<void> _selectEquipment() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectEquipmentScreen(
          preselectedIds: _selectedEquipmentIds,
          fireStation: _fireStation,
        ),
      ),
    );
    if (result != null) setState(() => _selectedEquipmentIds = result);
  }

  Future<void> _selectInvolvedFireStations() async {
    final tempSelected = List<String>.from(_selectedFireStations);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FireStationSelectorDialog(
        allStations: _allStations,
        selectedStations: tempSelected,
        ownFireStation: _fireStation,
      ),
    );

    if (result != null) setState(() => _selectedFireStations = result);
  }

  Future<void> _updateMission() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final updatedMission = MissionModel(
        id: widget.mission.id,
        name: _nameController.text.trim(),
        startTime: _startTime,
        type: _missionType,
        location: _locationController.text.trim(),
        description: _descriptionController.text.trim(),
        equipmentIds: _selectedEquipmentIds,
        fireStation: _fireStation,
        involvedFireStations: _selectedFireStations,
        createdBy: widget.mission.createdBy,
        createdAt: widget.mission.createdAt,
      );

      await _missionService.updateMission(updatedMission);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Einsatz erfolgreich aktualisiert'),
            backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fehler: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatz bearbeiten'),
        actions: [
          if (!_isLoading && _canEdit)
            TextButton(
              onPressed: _updateMission,
              child: const Text('Speichern',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(),
                    const SizedBox(height: 16),
                    _buildTimeCard(),
                    const SizedBox(height: 16),
                    _buildFireStationCard(),
                    const SizedBox(height: 16),
                    _buildEquipmentCard(),
                    const SizedBox(height: 16),
                    _buildDescriptionCard(),
                    const SizedBox(height: 24),
                    _buildSaveButton(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Karten ────────────────────────────────────────────────────────────────

  Widget _buildInfoCard() {
    return _card(
      icon: Icons.local_fire_department,
      title: 'Einsatzinformationen',
      child: Column(
        children: [
          // Einsatzname
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Einsatzname',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Bitte Einsatzname eingeben' : null,
          ),
          const SizedBox(height: 16),

          // Einsatztyp
          DropdownButtonFormField<String>(
            value: _missionType,
            decoration: const InputDecoration(
              labelText: 'Einsatztyp',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
            ),
            items: _missionTypes.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(children: [
                        Icon(e.value.icon, size: 20),
                        const SizedBox(width: 8),
                        Text(e.value.label),
                      ]),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _missionType = v);
            },
          ),
          const SizedBox(height: 16),

          // Einsatzort
          TextFormField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Einsatzort',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Bitte Einsatzort eingeben' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard() {
    return _card(
      icon: Icons.access_time,
      title: 'Zeitinformation',
      child: TextFormField(
        controller: _startTimeController,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Einsatzzeitpunkt',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.calendar_today),
        ),
        onTap: _selectStartTime,
        validator: (v) =>
            v == null || v.isEmpty ? 'Bitte Zeitpunkt wählen' : null,
      ),
    );
  }

  Widget _buildFireStationCard() {
    return _card(
      icon: Icons.location_city,
      title: 'Ortsfeuerwehren',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hauptfeuerwehr (nur für Admins editierbar)
          DropdownButtonFormField<String>(
            value: _fireStation.isNotEmpty ? _fireStation : null,
            decoration: InputDecoration(
              labelText: 'Hauptfeuerwehr',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.home),
              helperText: _canEditStation
                  ? null
                  : 'Nur Admins können die Hauptfeuerwehr ändern',
            ),
            items: _allStations
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Row(children: [
                        Icon(FireStations.getIcon(s),
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(s),
                      ]),
                    ))
                .toList(),
            onChanged: _canEditStation
                ? (v) {
                    if (v != null) {
                      setState(() {
                        _fireStation = v;
                        // Eigene Station immer in involvedFireStations
                        if (!_selectedFireStations.contains(v)) {
                          _selectedFireStations = [v, ..._selectedFireStations];
                        }
                      });
                    }
                  }
                : null,
            validator: (v) => v == null || v.isEmpty
                ? 'Bitte Feuerwehr auswählen'
                : null,
          ),
          const SizedBox(height: 16),

          // Beteiligte Ortswehren
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Beteiligte Ortswehren',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _selectInvolvedFireStations,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Bearbeiten'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedFireStations.isEmpty)
            Text('Keine beteiligten Ortswehren',
                style: TextStyle(color: Colors.grey[600]))
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _selectedFireStations
                  .map((s) => Chip(
                        avatar: Icon(FireStations.getIcon(s), size: 16),
                        label: Text(s),
                        backgroundColor: s == _fireStation
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.15)
                            : null,
                        deleteIcon: s == _fireStation
                            ? null
                            : const Icon(Icons.close, size: 14),
                        onDeleted: s == _fireStation
                            ? null
                            : () => setState(
                                () => _selectedFireStations.remove(s)),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildEquipmentCard() {
    return _card(
      icon: Icons.inventory_2,
      title: 'Ausrüstung',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
          child: Icon(Icons.inventory_2,
              color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(_selectedEquipmentIds.isEmpty
            ? 'Keine Ausrüstung ausgewählt'
            : '${_selectedEquipmentIds.length} Ausrüstungsgegenstände'),
        subtitle: _selectedEquipmentIds.isNotEmpty
            ? const Text('Tippe zum Ändern')
            : null,
        trailing: ElevatedButton(
          onPressed: _selectEquipment,
          child: const Text('Auswählen'),
        ),
        onTap: _selectEquipment,
      ),
    );
  }

  Widget _buildDescriptionCard() {
    return _card(
      icon: Icons.description,
      title: 'Beschreibung',
      child: TextFormField(
        controller: _descriptionController,
        decoration: const InputDecoration(
          labelText: 'Beschreibung (optional)',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        maxLines: 4,
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _updateMission,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Text('Einsatz aktualisieren',
                style: TextStyle(fontSize: 16)),
      ),
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  Widget _card(
      {required IconData icon,
      required String title,
      required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon,
                  color: Theme.of(context).colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ── Hilfsdaten ────────────────────────────────────────────────────────────────

class _MissionTypeInfo {
  final String label;
  final IconData icon;
  const _MissionTypeInfo(this.label, this.icon);
}

// ── Stationsauswahl-Dialog ────────────────────────────────────────────────────

class _FireStationSelectorDialog extends StatefulWidget {
  final List<String> allStations;
  final List<String> selectedStations;
  final String ownFireStation;

  const _FireStationSelectorDialog({
    required this.allStations,
    required this.selectedStations,
    required this.ownFireStation,
  });

  @override
  State<_FireStationSelectorDialog> createState() =>
      _FireStationSelectorDialogState();
}

class _FireStationSelectorDialogState
    extends State<_FireStationSelectorDialog> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedStations);
    // Eigene Station immer drin
    if (!_selected.contains(widget.ownFireStation)) {
      _selected.add(widget.ownFireStation);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Beteiligte Ortswehren'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Wähle die am Einsatz beteiligten Ortswehren aus:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.allStations.map((station) {
                    final isOwn = station == widget.ownFireStation;
                    final isSelected = _selected.contains(station);
                    return CheckboxListTile(
                      dense: true,
                      value: isSelected,
                      title: Row(children: [
                        Icon(FireStations.getIcon(station),
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(station),
                      ]),
                      subtitle: isOwn
                          ? const Text('Hauptfeuerwehr',
                              style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 11))
                          : null,
                      // Eigene Station kann nicht abgewählt werden
                      onChanged: isOwn
                          ? null
                          : (v) => setState(() => v == true
                              ? _selected.add(station)
                              : _selected.remove(station)),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('Übernehmen')),
      ],
    );
  }
}
