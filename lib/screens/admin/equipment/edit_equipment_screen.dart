// screens/admin/equipment/edit_equipment_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../Lists/fire_stations.dart';
import '../../../models/equipment_model.dart';
import '../../../services/equipment_service.dart';
import '../../../services/permission_service.dart';

class EditEquipmentScreen extends StatefulWidget {
  final EquipmentModel equipment;

  const EditEquipmentScreen({
    Key? key,
    required this.equipment,
  }) : super(key: key);

  @override
  State<EditEquipmentScreen> createState() => _EditEquipmentScreenState();
}

class _EditEquipmentScreenState extends State<EditEquipmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final EquipmentService _equipmentService = EquipmentService();
  final PermissionService _permissionService = PermissionService();

  bool _isLoading = false;
  bool _isAdmin = false;

  // Controller für die Textfelder
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _checkDateController = TextEditingController();

  // Dropdown-Werte
  String _article = '';
  String _type = '';
  String _fireStation = '';
  String _status = '';

  // Datum
  late DateTime _checkDate;

  // Listen für Dropdown-Menüs (jetzt aus Konstanten)
  final List<String> _articles = [
    'Viking Performer Evolution Einsatzjacke AGT',
    'Viking Performer Evolution Einsatzhose AGT',
    'Viking Einsatzhose TH Assistance',
    'Viking Einsatzjacke TH Assistance'
  ];

  final List<String> _types = ['Jacke', 'Hose'];

  // Ortswehren aus Konstanten-Klasse
  List<String> get _fireStations => FireStations.getAllStations();

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _initControllers();
  }

  Future<void> _loadPermissions() async {
    final isAdmin = await _permissionService.isAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });

      // Wenn der Benutzer kein Admin ist, zurück zur vorherigen Seite navigieren
      if (!isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sie haben keine Berechtigung, Einsatzkleidung zu bearbeiten'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  void _initControllers() {
    // Textfelder initialisieren
    _sizeController.text = widget.equipment.size;
    _ownerController.text = widget.equipment.owner;
    _checkDate = widget.equipment.checkDate;
    _checkDateController.text = DateFormat('dd.MM.yyyy').format(_checkDate);

    // Dropdown-Werte initialisieren
    _article = widget.equipment.article;
    _type = widget.equipment.type;
    _fireStation = widget.equipment.fireStation;
    _status = widget.equipment.status;
  }

  @override
  void dispose() {
    _sizeController.dispose();
    _ownerController.dispose();
    _checkDateController.dispose();
    super.dispose();
  }

  void _setTypeBasedOnArticle(String article) {
    setState(() {
      _article = article;
      if (article.contains('Jacke')) {
        _type = 'Jacke';
      } else if (article.contains('Hose')) {
        _type = 'Hose';
      }
    });
  }

  Future<void> _selectCheckDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _checkDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null && pickedDate != _checkDate) {
      setState(() {
        _checkDate = pickedDate;
        _checkDateController.text = DateFormat('dd.MM.yyyy').format(pickedDate);
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sie haben keine Berechtigung, Einsatzkleidung zu bearbeiten'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Alle Felder aktualisieren
        await _equipmentService.updateEquipment(
          equipmentId: widget.equipment.id,
          article: _article,
          type: _type,
          size: _sizeController.text.trim(),
          fireStation: _fireStation,
          owner: _ownerController.text.trim(),
          checkDate: _checkDate,
          status: _status,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Einsatzkleidung erfolgreich aktualisiert'),
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
        title: const Text('Einsatzkleidung bearbeiten'),
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
              // Identifikation (nicht editierbar)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Identifikation',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow('NFC-Tag', widget.equipment.nfcTag),
                      if (widget.equipment.barcode != null && widget.equipment.barcode!.isNotEmpty)
                        _buildInfoRow('Barcode', widget.equipment.barcode!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Artikelinformationen
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Artikelinformationen',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Artikel
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Artikel',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        isExpanded: true,
                        value: _article,
                        items: _articles.map((String article) {
                          return DropdownMenuItem<String>(
                            value: article,
                            child: Text(
                              article,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            _setTypeBasedOnArticle(newValue);
                          }
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte wählen Sie einen Artikel aus';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Typ
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Typ',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.style),
                        ),
                        value: _type,
                        items: _types.map((String type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _type = newValue;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte wählen Sie einen Typ aus';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Größe
                      TextFormField(
                        controller: _sizeController,
                        decoration: const InputDecoration(
                          labelText: 'Größe',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.format_size),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte geben Sie eine Größe ein';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Zuordnung
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zuordnung',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Ortsfeuerwehr (jetzt aus Konstanten)
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Ortsfeuerwehr',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.location_city),
                          helperText: 'Ortswehr: ${FireStations.getFullName(_fireStation)}',
                        ),
                        value: _fireStation,
                        items: _fireStations.map((String station) {
                          return DropdownMenuItem<String>(
                            value: station,
                            child: Text(station),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _fireStation = newValue;
                            });
                          }
                        },
                        validator: FireStations.validateStation,
                      ),
                      const SizedBox(height: 16),

                      // Besitzer
                      TextFormField(
                        controller: _ownerController,
                        decoration: const InputDecoration(
                          labelText: 'Besitzer',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte geben Sie einen Besitzer ein';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Status und Prüfdatum
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status und Prüfung',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Status
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.flag),
                        ),
                        value: _status,
                        items: EquipmentStatus.values.map((String status) {
                          return DropdownMenuItem<String>(
                            value: status,
                            child: Row(
                              children: [
                                Icon(
                                  EquipmentStatus.getStatusIcon(status),
                                  color: EquipmentStatus.getStatusColor(status),
                                  size: 20,
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
                              _status = newValue;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte wählen Sie einen Status aus';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Prüfdatum
                      TextFormField(
                        controller: _checkDateController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Prüfdatum',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.event),
                        ),
                        onTap: _selectCheckDate,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte wählen Sie ein Prüfdatum aus';
                          }
                          return null;
                        },
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
                  onPressed: _isLoading ? null : _saveChanges,
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}