// screens/missions/edit_mission_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/mission_model.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';
import 'select_equipment_screen.dart';

class EditMissionScreen extends StatefulWidget {
  final MissionModel mission;

  const EditMissionScreen({
    Key? key,
    required this.mission,
  }) : super(key: key);

  @override
  State<EditMissionScreen> createState() => _EditMissionScreenState();
}

class _EditMissionScreenState extends State<EditMissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();

  DateTime _startTime = DateTime.now();
  String _missionType = 'fire';
  String _fireStation = '';
  List<String> _selectedEquipmentIds = [];
  List<String> _selectedFireStations = []; // NEU: Liste der beteiligten Ortswehren
  bool _isLoading = false;
  bool _isAdmin = false;

  final List<String> _fireStations = [
    'Esklum',
    'Breinermoor',
    'Grotegaste',
    'Flachsmeer',
    'Folmhusen',
    'Großwolde',
    'Ihrhove',
    'Ihren'
    'Steenfelde',
    'Völlen',
    'Völlenerfehn',
    'Völlenerkönigsfehn'
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadPermissions();
  }

  void _initializeData() {
    // Daten aus dem übergebenen Mission-Objekt initialisieren
    _nameController.text = widget.mission.name;
    _locationController.text = widget.mission.location;
    _descriptionController.text = widget.mission.description;
    _startTime = widget.mission.startTime;
    _startTimeController.text = DateFormat('dd.MM.yyyy HH:mm').format(_startTime);
    _missionType = widget.mission.type;
    _fireStation = widget.mission.fireStation;
    _selectedEquipmentIds = List.from(widget.mission.equipmentIds);

    // NEU: Beteiligte Ortswehren initialisieren
    _selectedFireStations = widget.mission.involvedFireStations.isNotEmpty
        ? List.from(widget.mission.involvedFireStations)
        : [widget.mission.fireStation]; // Fallback: Mindestens die eigene Feuerwehr
  }

  Future<void> _loadPermissions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAdmin = await _permissionService.isAdmin();

      setState(() {
        _isAdmin = isAdmin;
        _isLoading = false;
      });

      // Wenn kein Admin, zurück navigieren
      if (!isAdmin && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sie haben keine Berechtigung, Einsätze zu bearbeiten'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Fehler beim Laden der Berechtigungen: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _startTimeController.dispose();
    super.dispose();
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

  // NEU: Dialog zur Auswahl beteiligter Ortswehren anzeigen
  Future<void> _selectInvolvedFireStations() async {
    final List<String> tempSelectedStations = List.from(_selectedFireStations);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Beteiligte Ortswehren'),
                content: Container(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Wählen Sie die am Einsatz beteiligten Ortswehren aus:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _fireStations.map((station) {
                              final isSelected = tempSelectedStations.contains(station);
                              final isOwnStation = station == _fireStation;

                              return CheckboxListTile(
                                title: Text(station),
                                value: isSelected,
                                // Die eigene Feuerwehr kann nicht abgewählt werden
                                onChanged: isOwnStation ? null : (bool? value) {
                                  setState(() {
                                    if (value == true) {
                                      tempSelectedStations.add(station);
                                    } else {
                                      tempSelectedStations.remove(station);
                                    }
                                  });
                                },
                                // Eigene Feuerwehr hervorheben
                                subtitle: isOwnStation
                                    ? const Text('Hauptfeuerwehr',
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontSize: 12,
                                    ))
                                    : null,
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
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Abbrechen'),
                  ),
                  TextButton(
                    onPressed: () {
                      this.setState(() {
                        _selectedFireStations = tempSelectedStations;
                      });
                      Navigator.of(context).pop();
                    },
                    child: const Text('Übernehmen'),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  Future<void> _updateMission() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        User? currentUser = _auth.currentUser;

        if (currentUser == null) {
          throw Exception('Kein Benutzer angemeldet');
        }

        // Aktualisiertes Mission-Objekt erstellen
        MissionModel updatedMission = MissionModel(
          id: widget.mission.id,
          name: _nameController.text.trim(),
          startTime: _startTime,
          type: _missionType,
          location: _locationController.text.trim(),
          description: _descriptionController.text.trim(),
          equipmentIds: _selectedEquipmentIds,
          fireStation: _fireStation,
          involvedFireStations: _selectedFireStations, // NEU: Beteiligte Ortswehren
          createdBy: widget.mission.createdBy, // Ursprünglicher Ersteller beibehalten
          createdAt: widget.mission.createdAt, // Ursprüngliches Erstellungsdatum beibehalten
        );

        // Aktualisieren in Firestore
        await _missionService.updateMission(updatedMission);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Einsatz erfolgreich aktualisiert'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // true zurückgeben als Erfolg-Indikator
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
        title: const Text('Einsatz bearbeiten'),
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

                      // Name/Beschreibung
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Einsatzname',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte geben Sie einen Einsatznamen ein';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Einsatztyp
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Einsatztyp',
                          border: OutlineInputBorder(),
                        ),
                        value: _missionType,
                        items: [
                          _buildDropdownItem('fire', 'Brandeinsatz', Icons.local_fire_department),
                          _buildDropdownItem('technical', 'Technische Hilfeleistung', Icons.build),
                          _buildDropdownItem('hazmat', 'Gefahrgut', Icons.dangerous),
                          _buildDropdownItem('water', 'Wasser/Hochwasser', Icons.water),
                          _buildDropdownItem('training', 'Übung', Icons.school),
                          _buildDropdownItem('other', 'Sonstiger Einsatz', Icons.more_horiz),
                        ],
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _missionType = newValue;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Ortsinformation
                      TextFormField(
                        controller: _locationController,
                        decoration: const InputDecoration(
                          labelText: 'Einsatzort',
                          border: OutlineInputBorder(),
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

              // NEUE KARTE: Beteiligte Ortswehren
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

                      // Beteiligte Ortswehren anzeigen und auswählen
                      InkWell(
                        onTap: _selectInvolvedFireStations,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Beteiligte Ortswehren',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.fire_truck),
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

                      // Ausrüstung auswählen
                      ListTile(
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
                        'Einsatzbeschreibung',
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
                          alignLabelWithHint: true,
                        ),
                        maxLines: 5,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Speichern-Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateMission,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text(
                    'Änderungen speichern',
                    style: TextStyle(fontSize: 16),
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