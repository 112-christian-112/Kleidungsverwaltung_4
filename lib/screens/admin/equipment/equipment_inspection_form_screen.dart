// screens/admin/equipment/equipment_inspection_form_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import '../../../services/equipment_inspection_service.dart';
import '../../../services/permission_service.dart';

class EquipmentInspectionFormScreen extends StatefulWidget {
  final EquipmentModel equipment;
  final EquipmentInspectionModel? existingInspection; // Für Bearbeitung


  const EquipmentInspectionFormScreen({
    Key? key,
    required this.equipment,
    this.existingInspection,
  }) : super(key: key);

  @override
  State<EquipmentInspectionFormScreen> createState() => _EquipmentInspectionFormScreenState();
}

class _EquipmentInspectionFormScreenState extends State<EquipmentInspectionFormScreen> {
  final PermissionService _permissionService = PermissionService();
  final _formKey = GlobalKey<FormState>();
  final EquipmentInspectionService _inspectionService = EquipmentInspectionService();

  DateTime _inspectionDate = DateTime.now();
  final TextEditingController _inspectionDateController = TextEditingController();

  String _inspector = '';
  final TextEditingController _inspectorController = TextEditingController();

  InspectionResult _result = InspectionResult.passed;

  final TextEditingController _commentsController = TextEditingController();

  DateTime _nextInspectionDate = DateTime.now().add(const Duration(days: 365));
  final TextEditingController _nextInspectionDateController = TextEditingController();

  final List<String> _issues = [];

  bool _isLoading = false;
  bool _isEditing = false;

  // Erweiterte Issue-Kategorien mit Schweregradkennzeichnung
  final Map<String, Map<String, String>> _issueCategories = {
    'Materialschäden': {
      'Leichter Verschleiß': 'low',
      'Starker Verschleiß': 'high',
      'Kleine Nahtbeschädigung': 'medium',
      'Große Nahtbeschädigung': 'high',
      'Reißverschluss klemmt': 'medium',
      'Reißverschluss defekt': 'high',
      'Kleine Brandlöcher': 'medium',
      'Große Brandlöcher': 'high',
      'Materialermüdung': 'medium',
      'Risse im Material': 'high'
    },
    'Sicherheitsmängel': {
      'Einzelne Reflektoren fehlen': 'medium',
      'Viele Reflektoren fehlen': 'high',
      'Reflektoren beschädigt': 'medium',
      'Warn-Streifen beschädigt': 'high',
      'Kennzeichnung unvollständig': 'medium',
      'Kennzeichnung unleserlich': 'high'
    },
    'Optische Mängel': {
      'Leichte Verschmutzung': 'low',
      'Starke Verschmutzung': 'medium',
      'Verblasste Farbe': 'low',
      'Hartnäckige Flecken': 'medium',
      'Unangenehmer Geruch': 'medium'
    },
    'Funktionsmängel': {
      'Kapuze sitzt schlecht': 'low',
      'Kapuze defekt': 'medium',
      'Taschen beschädigt': 'low',
      'Klettverschluss schwach': 'low',
      'Klettverschluss defekt': 'medium',
      'Druckknöpfe lose': 'low',
      'Druckknöpfe fehlen': 'medium'
    }
  };

  // Automatische Status-Zuordnung basierend auf Prüfergebnis
  String _getNewStatusFromResult(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return EquipmentStatus.ready;
      case InspectionResult.conditionalPass:
        return EquipmentStatus.ready; // Bedingt bestanden = trotzdem einsatzbereit
      case InspectionResult.failed:
        return EquipmentStatus.repair; // Durchgefallen = in Reparatur
    }
  }

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingInspection != null;
    _loadData();
    _initDateControllers();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Bestehende Prüfung laden (falls Bearbeitung)
      if (_isEditing && widget.existingInspection != null) {
        _loadExistingInspection();
      }

      // Benutzerdaten laden
      await _loadUserData();

      // Letzte Prüfung abrufen für bessere Vorschläge
      await _loadLastInspection();

    } catch (e) {
      print('Fehler beim Laden der Daten: $e');
      _showErrorSnackBar('Fehler beim Laden der Daten');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadExistingInspection() {
    final inspection = widget.existingInspection!;
    _inspectionDate = inspection.inspectionDate;
    _inspector = inspection.inspector;
    _result = inspection.result;
    _commentsController.text = inspection.comments;
    _nextInspectionDate = inspection.nextInspectionDate;
    _issues.addAll(inspection.issues ?? []);
    _inspectorController.text = inspection.inspector;
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _permissionService.getCurrentUser();
      if (user != null && !_isEditing) {
        setState(() {
          _inspector = user.name.isNotEmpty ? user.name : user.email;
          _inspectorController.text = _inspector;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Benutzerdaten: $e');
    }
  }

  Future<void> _loadLastInspection() async {
    try {
      // Letzte Prüfung für Vergleich abrufen
      final lastInspections = await FirebaseFirestore.instance
          .collection('equipment_inspections')
          .where('equipmentId', isEqualTo: widget.equipment.id)
          .orderBy('inspectionDate', descending: true)
          .limit(1)
          .get();

      if (lastInspections.docs.isNotEmpty && !_isEditing) {
        final lastInspection = EquipmentInspectionModel.fromMap(
          lastInspections.docs.first.data(),
          lastInspections.docs.first.id,
        );

        // Vorschläge basierend auf letzter Prüfung machen
        _suggestInspectionInterval(lastInspection);
      }
    } catch (e) {
      print('Fehler beim Laden der letzten Prüfung: $e');
    }
  }

  void _suggestInspectionInterval(EquipmentInspectionModel lastInspection) {
    // Entfernt - Prüfintervall wird nicht mehr verwendet
  }

  String _getIssueSeverity(String issue) {
    for (var category in _issueCategories.values) {
      if (category.containsKey(issue)) {
        return category[issue]!;
      }
    }
    return 'low';
  }

  void _initDateControllers() {
    _inspectionDateController.text = DateFormat('dd.MM.yyyy').format(_inspectionDate);
    _nextInspectionDateController.text = DateFormat('dd.MM.yyyy').format(_nextInspectionDate);
  }

  @override
  void dispose() {
    _inspectionDateController.dispose();
    _inspectorController.dispose();
    _commentsController.dispose();
    _nextInspectionDateController.dispose();
    super.dispose();
  }

  Future<void> _selectInspectionDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _inspectionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('de', 'DE'),
      helpText: 'Prüfdatum auswählen',
    );

    if (pickedDate != null && pickedDate != _inspectionDate) {
      setState(() {
        _inspectionDate = pickedDate;
        _inspectionDateController.text = DateFormat('dd.MM.yyyy').format(pickedDate);
        _updateNextInspectionDate();
      });
    }
  }

  Future<void> _selectNextInspectionDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _nextInspectionDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      locale: const Locale('de', 'DE'),
      helpText: 'Nächstes Prüfdatum auswählen',
    );

    if (pickedDate != null && pickedDate != _nextInspectionDate) {
      setState(() {
        _nextInspectionDate = pickedDate;
        _nextInspectionDateController.text = DateFormat('dd.MM.yyyy').format(pickedDate);
      });
    }
  }

  void _updateNextInspectionDate() {
    // Standardmäßig 1 Jahr ab Prüfdatum
    setState(() {
      _nextInspectionDate = DateTime(_inspectionDate.year + 1, _inspectionDate.month, _inspectionDate.day);
      _nextInspectionDateController.text = DateFormat('dd.MM.yyyy').format(_nextInspectionDate);
    });
  }

  void _toggleIssue(String issue) {
    setState(() {
      if (_issues.contains(issue)) {
        _issues.remove(issue);
      } else {
        _issues.add(issue);
      }
      _autoSuggestResult();
    });
  }

  void _autoSuggestResult() {
    if (_issues.isEmpty) {
      setState(() {
        _result = InspectionResult.passed;
      });
      return;
    }

    bool hasHighSeverity = _issues.any((issue) => _getIssueSeverity(issue) == 'high');
    bool hasMediumSeverity = _issues.any((issue) => _getIssueSeverity(issue) == 'medium');

    setState(() {
      if (hasHighSeverity) {
        _result = InspectionResult.failed;
      } else if (hasMediumSeverity) {
        _result = InspectionResult.conditionalPass;
      } else {
        _result = InspectionResult.passed;
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

// Nur der relevante Teil der _saveInspection Methode:

  Future<void> _saveInspection() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Bitte füllen Sie alle erforderlichen Felder aus');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Kein Benutzer angemeldet');
      }

      final userModel = await _permissionService.getCurrentUser();

      EquipmentInspectionModel inspection = EquipmentInspectionModel(
        id: _isEditing ? widget.existingInspection!.id : '', // Für Update
        equipmentId: widget.equipment.id,
        inspectionDate: _inspectionDate,
        inspector: _inspectorController.text.trim(),
        result: _result,
        comments: _commentsController.text.trim(),
        nextInspectionDate: _nextInspectionDate,
        issues: _issues.isNotEmpty ? _issues : null,
        createdAt: _isEditing ? widget.existingInspection!.createdAt : DateTime.now(),
        createdBy: userModel?.name.isNotEmpty == true
            ? userModel!.name
            : userModel?.email ?? '',
      );

      if (_isEditing) {
        await _inspectionService.updateInspection(inspection);
      } else {
        await _inspectionService.addInspection(inspection);
      }

      // HINWEIS: Equipment-Status wird automatisch im InspectionService aktualisiert
      // basierend auf dem Prüfergebnis:
      // - Bestanden → Einsatzbereit
      // - Bedingt bestanden → Einsatzbereit
      // - Durchgefallen → In Reparatur

      if (mounted) {
        _showSuccessSnackBar(_isEditing ? 'Prüfung erfolgreich aktualisiert' : 'Prüfung erfolgreich gespeichert');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Fehler beim Speichern: $e');
      }
    } finally {
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
        title: Text(_isEditing ? 'Prüfung bearbeiten' : 'Neue Prüfung durchführen'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _showDeleteDialog,
            ),
        ],
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
              _buildEquipmentInfoCard(),
              const SizedBox(height: 16),
              _buildInspectionDataCard(),
              const SizedBox(height: 16),
              _buildIssuesCard(),
              const SizedBox(height: 16),
              _buildSummaryCard(),
              const SizedBox(height: 24),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEquipmentInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Einsatzkleidung',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: EquipmentStatus.getStatusColor(widget.equipment.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: EquipmentStatus.getStatusColor(widget.equipment.status),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          EquipmentStatus.getStatusIcon(widget.equipment.status),
                          size: 14,
                          color: EquipmentStatus.getStatusColor(widget.equipment.status),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.equipment.status,
                            style: TextStyle(
                              color: EquipmentStatus.getStatusColor(widget.equipment.status),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Artikel', widget.equipment.article),
            _buildInfoRow('Typ', widget.equipment.type),
            _buildInfoRow('Größe', widget.equipment.size),
            _buildInfoRow('Besitzer', widget.equipment.owner),
            _buildInfoRow('Ortsfeuerwehr', widget.equipment.fireStation),
            _buildInfoRow('NFC-Tag', widget.equipment.nfcTag),
            _buildInfoRow('Waschzyklen', '${widget.equipment.washCycles}'),
            _buildInfoRow('Letztes Prüfdatum', DateFormat('dd.MM.yyyy').format(widget.equipment.checkDate)),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectionDataCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.assignment,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Prüfungsdaten',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Prüfdatum
            TextFormField(
              controller: _inspectionDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Prüfdatum *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.event),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              onTap: _selectInspectionDate,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte wählen Sie ein Prüfdatum aus';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Prüfer
            TextFormField(
              controller: _inspectorController,
              decoration: InputDecoration(
                labelText: 'Prüfer *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.person),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte geben Sie den Namen des Prüfers ein';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Prüfergebnis
            const Text(
              'Prüfergebnis *',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Der Equipment-Status wird automatisch basierend auf dem Prüfergebnis aktualisiert',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _buildResultCard(InspectionResult.passed, 'Bestanden',
                'Keine Mängel → Status: Einsatzbereit', Colors.green, Icons.check_circle),
            const SizedBox(height: 8),
            _buildResultCard(InspectionResult.conditionalPass, 'Bedingt bestanden',
                'Geringfügige Mängel → Status: Einsatzbereit', Colors.orange, Icons.warning),
            const SizedBox(height: 8),
            _buildResultCard(InspectionResult.failed, 'Durchgefallen',
                'Schwerwiegende Mängel → Status: In Reparatur', Colors.red, Icons.cancel),

            const SizedBox(height: 20),

            // Nächstes Prüfdatum
            TextFormField(
              controller: _nextInspectionDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Nächstes Prüfdatum *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.event_repeat),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                helperText: 'Standardmäßig 1 Jahr nach Prüfdatum',
              ),
              onTap: _selectNextInspectionDate,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte wählen Sie ein Datum für die nächste Prüfung aus';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssuesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bug_report,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Festgestellte Probleme (${_issues.length} ausgewählt)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Issue Categories mit Schweregrad-Legende
            _buildSeverityLegend(),
            const SizedBox(height: 16),

            // Issue Categories
            ..._issueCategories.entries.map((category) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      category.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: category.value.entries.map((issue) =>
                        _buildIssueChip(issue.key, issue.value)).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }).toList(),

            // Kommentare
            TextFormField(
              controller: _commentsController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Zusätzliche Kommentare',
                hintText: 'Beschreiben Sie weitere Details oder spezielle Beobachtungen...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            'Schweregrad-Legende:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildSeverityItem('Gering', Colors.green, 'low'),
              _buildSeverityItem('Mittel', Colors.orange, 'medium'),
              _buildSeverityItem('Hoch', Colors.red, 'high'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityItem(String label, Color color, String severity) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    if (_issues.isEmpty && _result == InspectionResult.passed) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.summarize,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Prüfungszusammenfassung',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_issues.isNotEmpty) ...[
              Text(
                'Gefundene Probleme nach Schweregrad:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              ..._buildIssueSummary(),
            ],

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getResultColor(_result).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getResultColor(_result)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(_getResultIcon(_result), color: _getResultColor(_result)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Empfohlenes Ergebnis: ${_getResultText(_result)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getResultColor(_result),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        EquipmentStatus.getStatusIcon(_getNewStatusFromResult(_result)),
                        color: _getResultColor(_result),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Neuer Status: ${_getNewStatusFromResult(_result)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _getResultColor(_result),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIssueSummary() {
    final severityGroups = <String, List<String>>{
      'high': [],
      'medium': [],
      'low': [],
    };

    for (String issue in _issues) {
      String severity = _getIssueSeverity(issue);
      severityGroups[severity]!.add(issue);
    }

    List<Widget> summaryWidgets = [];

    severityGroups.forEach((severity, issues) {
      if (issues.isNotEmpty) {
        Color color = severity == 'high' ? Colors.red :
        severity == 'medium' ? Colors.orange : Colors.green;
        String label = severity == 'high' ? 'Hoher Schweregrad' :
        severity == 'medium' ? 'Mittlerer Schweregrad' : 'Geringer Schweregrad';

        summaryWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$label (${issues.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      Text(
                        issues.join(', '),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });

    return summaryWidgets;
  }

  Color _getResultColor(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return Colors.green;
      case InspectionResult.conditionalPass:
        return Colors.orange;
      case InspectionResult.failed:
        return Colors.red;
    }
  }

  IconData _getResultIcon(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return Icons.check_circle;
      case InspectionResult.conditionalPass:
        return Icons.warning;
      case InspectionResult.failed:
        return Icons.cancel;
    }
  }

  String _getResultText(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return 'Bestanden';
      case InspectionResult.conditionalPass:
        return 'Bedingt bestanden';
      case InspectionResult.failed:
        return 'Durchgefallen';
    }
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveInspection,
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
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_isEditing ? Icons.update : Icons.save, size: 24),
            const SizedBox(width: 12),
            Text(
              _isEditing ? 'Prüfung aktualisieren' : 'Prüfung speichern',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(InspectionResult result, String title, String description, Color color, IconData icon) {
    final isSelected = _result == result;
    return InkWell(
      onTap: () => setState(() => _result = result),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? color.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : null,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? color.withOpacity(0.8) : Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueChip(String issue, String severity) {
    final bool isSelected = _issues.contains(issue);
    final Color severityColor = severity == 'high' ? Colors.red :
    severity == 'medium' ? Colors.orange : Colors.green;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: severityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              issue,
              style: TextStyle(
                color: isSelected ? Colors.white : null,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (bool selected) {
        _toggleIssue(issue);
      },
      backgroundColor: Colors.grey.shade200,
      selectedColor: severityColor.withOpacity(0.8),
      checkmarkColor: Colors.white,
      elevation: isSelected ? 2 : 1,
      pressElevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Prüfung löschen'),
          content: const Text('Sind Sie sicher, dass Sie diese Prüfung löschen möchten? Diese Aktion kann nicht rückgängig gemacht werden.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await _inspectionService.deleteInspection(widget.existingInspection!.id);
                  _showSuccessSnackBar('Prüfung erfolgreich gelöscht');
                  Navigator.pop(context, true);
                } catch (e) {
                  _showErrorSnackBar('Fehler beim Löschen: $e');
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
  }
}