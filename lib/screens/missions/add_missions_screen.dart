// screens/missions/add_mission_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../Lists/fire_stations.dart';
import '../../Lists/mission_keywords.dart';
import '../../models/mission_model.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/fire_station_selector.dart';
import 'select_equipment_screen.dart';

class AddMissionScreen extends StatefulWidget {
  const AddMissionScreen({Key? key}) : super(key: key);

  @override
  State<AddMissionScreen> createState() => _AddMissionScreenState();
}

class _AddMissionScreenState extends State<AddMissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();

  DateTime _startTime = DateTime.now();
  String _missionType = 'fire';
  String _selectedKeyword = ''; // Neues Feld für Einsatzstichwort
  String _fireStation = '';
  List<String> _selectedEquipmentIds = [];
  List<String> _selectedFireStations = [];
  bool _isLoading = false;
  bool _isAdmin = false;

  // Ortswehren-Liste aus Konstanten-Klasse entfernt
  // Wird jetzt über FireStations.getAllStations() abgerufen

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _startTimeController.text = DateFormat('dd.MM.yyyy HH:mm').format(_startTime);
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userFireStation = await _permissionService.getUserFireStation();
      final isAdmin = await _permissionService.isAdmin();

      setState(() {
        _fireStation = userFireStation;
        _isAdmin = isAdmin;
        _selectedFireStations = [userFireStation];
        _isLoading = false;
      });
    } catch (e) {
      print('Fehler beim Laden der Benutzerdaten: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    _startTimeController.dispose();
    super.dispose();
  }

  // Einsatzstichwörter für den aktuellen Typ abrufen - jetzt aus der Konstanten-Klasse
  List<String> _getKeywordsForType(String type) {
    return MissionKeywords.getKeywordsForType(type);
  }

  // Beim Wechsel des Einsatztyps das Stichwort zurücksetzen
  void _onMissionTypeChanged(String newType) {
    setState(() {
      _missionType = newType;
      _selectedKeyword = ''; // Stichwort zurücksetzen
    });
  }

  Future<void> _selectStartTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_startTime),
      );

      if (pickedTime != null) {
        setState(() {
          _startTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _startTimeController.text = DateFormat('dd.MM.yyyy HH:mm').format(_startTime);
        });
      }
    }
  }

  Future<void> _selectEquipment() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectEquipmentScreen(
          preselectedIds: _selectedEquipmentIds,
          fireStation: _fireStation,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedEquipmentIds = result;
      });
    }
  }

  Future<void> _selectInvolvedFireStations() async {
    final result = await showFireStationSelector(
      context: context,
      selectedStations: _selectedFireStations,
      userFireStation: _fireStation,
      title: 'Beteiligte Ortswehren',
      helpText: 'Wählen Sie die am Einsatz beteiligten Ortswehren aus:',
      showFullNames: true,
    );

    if (result != null) {
      setState(() {
        _selectedFireStations = result;
      });
    }
  }

  Future<void> _saveMission() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          throw Exception('Kein Benutzer angemeldet');
        }

        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        // Einsatzname aus Stichwort generieren
        String missionName = _selectedKeyword.isNotEmpty
            ? _selectedKeyword
            : 'Einsatz ohne Stichwort';

        MissionModel mission = MissionModel(
          id: '',
          name: missionName, // Verwende das ausgewählte Stichwort als Name
          startTime: _startTime,
          type: _missionType,
          location: _locationController.text.trim(),
          description: _descriptionController.text.trim(),
          equipmentIds: _selectedEquipmentIds,
          fireStation: _fireStation,
          involvedFireStations: _selectedFireStations,
          createdBy: userData['name'] ?? currentUser.email ?? '',
          createdAt: DateTime.now(),
        );

        DocumentReference missionRef = await _missionService.createMission(mission);

        if (_selectedEquipmentIds.isNotEmpty) {
          await _missionService.addEquipmentToMission(
              missionRef.id,
              _selectedEquipmentIds
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Einsatz erfolgreich gespeichert'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
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
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neuen Einsatz erfassen'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grundinformationen
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Einsatzinformationen',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Einsatztyp (zuerst, damit Stichwörter aktualisiert werden)
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Einsatztyp',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        value: _missionType,
                        items: MissionKeywords.getAllTypes().map((type) {
                          return _buildDropdownItem(
                              type,
                              MissionKeywords.getTypeName(type),
                              MissionKeywords.getTypeIcon(type)
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            _onMissionTypeChanged(newValue);
                          }
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte wählen Sie einen Einsatztyp aus';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Einsatzstichwort (neues Feld)
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Einsatzstichwort',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label),
                          helperText: 'Wählen Sie das passende Einsatzstichwort aus',
                        ),
                        value: _selectedKeyword.isEmpty ? null : _selectedKeyword,
                        hint: const Text('Bitte Einsatzstichwort auswählen'),
                        isExpanded: true,
                        items: _getKeywordsForType(_missionType).map((String keyword) {
                          return DropdownMenuItem<String>(
                            value: keyword,
                            child: Text(
                              keyword,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedKeyword = newValue ?? '';
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte wählen Sie ein Einsatzstichwort aus';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Ortsinformation
                      TextFormField(
                        controller: _locationController,
                        decoration: const InputDecoration(
                          labelText: 'Einsatzort',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on),
                          helperText: 'z.B. Hauptstraße 123, Ihrhove',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte geben Sie einen Einsatzort ein';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Zeitinformationen
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zeitinformation',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Startzeit
                      TextFormField(
                        controller: _startTimeController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Einsatzzeitpunkt',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time),
                          helperText: 'Tippen Sie hier, um Datum und Uhrzeit zu ändern',
                        ),
                        onTap: _selectStartTime,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte wählen Sie einen Zeitpunkt';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Beteiligte Ortswehren
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Beteiligte Ortswehren',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      InkWell(
                        onTap: _selectInvolvedFireStations,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Beteiligte Ortswehren',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.fire_truck),
                            helperText: 'Tippen Sie hier, um weitere Ortswehren hinzuzufügen',
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _selectedFireStations.isEmpty
                                    ? const Text('Keine Ortswehren ausgewählt',
                                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
                                    : Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: _selectedFireStations.map((station) => Chip(
                                    label: Text(station),
                                    backgroundColor: station == _fireStation
                                        ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                                        : null,
                                  )).toList(),
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Ausrüstungsauswahl
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ausrüstung',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      ListTile(
                        leading: const Icon(Icons.inventory_2),
                        title: const Text('Verwendete Ausrüstung'),
                        subtitle: Text(
                          _selectedEquipmentIds.isEmpty
                              ? 'Keine Ausrüstung ausgewählt'
                              : '${_selectedEquipmentIds.length} Ausrüstungsgegenstände ausgewählt',
                        ),
                        trailing: ElevatedButton(
                          onPressed: _selectEquipment,
                          child: const Text('Auswählen'),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Beschreibung
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zusätzliche Informationen',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Beschreibung (optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                          alignLabelWithHint: true,
                          helperText: 'Weitere Details zum Einsatz',
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Speichern-Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveMission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Einsatz speichern',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DropdownMenuItem<String> _buildDropdownItem(String value, String text, IconData icon) {
    return DropdownMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}