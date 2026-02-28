// screens/admin/equipment/equipment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import '../../../services/equipment_service.dart';
import '../../../services/equipment_inspection_service.dart';
import '../../../services/permission_service.dart';
import 'edit_equipment_screen.dart';
import 'equipment_inspection_history.dart';
import 'equipment_inspection_form_screen.dart';
import 'equipment_missions_screen.dart';
import 'history_screen.dart';

class EquipmentDetailScreen extends StatefulWidget {
  final EquipmentModel equipment;

  const EquipmentDetailScreen({
    Key? key,
    required this.equipment,
  }) : super(key: key);

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  final EquipmentInspectionService _inspectionService = EquipmentInspectionService();
  final PermissionService _permissionService = PermissionService();

  bool _isProcessing = false;
  bool _isAdmin = false;
  bool _isHygieneUnit = false;
  bool _canEditEquipment = false;
  String _userRole = 'user';

  late int _washCycles;
  late DateTime _checkDate;
  late String _status;
  final TextEditingController _checkDateController = TextEditingController();

  EquipmentInspectionModel? _latestInspection;
  List<EquipmentInspectionModel> _recentInspections = [];
  bool _isLoadingInspections = true;

  @override
  void initState() {
    super.initState();
    _washCycles = widget.equipment.washCycles;
    _checkDate = widget.equipment.checkDate;
    _checkDateController.text = DateFormat('dd.MM.yyyy').format(_checkDate);
    _status = widget.equipment.status;
    _loadPermissions();
    _loadInspectionData();
  }

  @override
  void dispose() {
    _checkDateController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    try {
      final isAdmin = await _permissionService.isAdmin();
      final isHygieneUnit = await _permissionService.isHygieneUnit();
      final canEditEquipment = await _permissionService.canEditEquipment();
      final userRole = await _permissionService.getUserRole();

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _isHygieneUnit = isHygieneUnit;
          _canEditEquipment = canEditEquipment;
          _userRole = userRole;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Berechtigungen: $e');
    }
  }

  Future<void> _loadInspectionData() async {
    setState(() {
      _isLoadingInspections = true;
    });

    try {
      _inspectionService.getInspectionsForEquipment(widget.equipment.id).listen((inspections) {
        if (mounted) {
          setState(() {
            _recentInspections = inspections;
            _latestInspection = inspections.isNotEmpty ? inspections.first : null;
            _isLoadingInspections = false;
          });
        }
      });
    } catch (e) {
      print('Fehler beim Laden der Prüfdaten: $e');
      setState(() {
        _isLoadingInspections = false;
      });
    }
  }

  // Prüfstatus berechnen
  String _getInspectionStatus() {
    if (_latestInspection == null) {
      return 'Noch nie geprüft';
    }

    final now = DateTime.now();
    final daysUntilNext = _latestInspection!.nextInspectionDate.difference(now).inDays;

    if (daysUntilNext < 0) {
      return 'Überfällig (${(-daysUntilNext)} Tage)';
    } else if (daysUntilNext <= 30) {
      return 'Bald fällig ($daysUntilNext Tage)';
    } else {
      return 'Aktuell';
    }
  }

  Color _getInspectionStatusColor() {
    if (_latestInspection == null) {
      return Colors.grey;
    }

    final now = DateTime.now();
    final daysUntilNext = _latestInspection!.nextInspectionDate.difference(now).inDays;

    if (daysUntilNext < 0) {
      return Colors.red;
    } else if (daysUntilNext <= 30) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  IconData _getInspectionStatusIcon() {
    if (_latestInspection == null) {
      return Icons.help_outline;
    }

    final now = DateTime.now();
    final daysUntilNext = _latestInspection!.nextInspectionDate.difference(now).inDays;

    if (daysUntilNext < 0) {
      return Icons.error;
    } else if (daysUntilNext <= 30) {
      return Icons.warning;
    } else {
      return Icons.check_circle;
    }
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

  Future<void> _updateWashCycles(int newWashCycles) async {
    if (newWashCycles < 0) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _equipmentService.updateWashCycles(widget.equipment.id, newWashCycles);
      setState(() {
        _washCycles = newWashCycles;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waschzyklen erfolgreich aktualisiert'),
            backgroundColor: Colors.green,
          ),
        );
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
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    // Prüfung erforderlich, wenn von kritischen Status zu "Einsatzbereit" gewechselt wird
    if (newStatus == EquipmentStatus.ready && _requiresInspectionForReady()) {
      await _showInspectionRequiredDialog();
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _equipmentService.updateStatus(widget.equipment.id, newStatus);

      setState(() {
        _status = newStatus;
        if (newStatus == EquipmentStatus.cleaning &&
            widget.equipment.status != EquipmentStatus.cleaning) {
          _washCycles += 1;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status erfolgreich aktualisiert'),
            backgroundColor: Colors.green,
          ),
        );
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
          _isProcessing = false;
        });
      }
    }
  }

  // Prüft, ob eine Inspektion erforderlich ist, um den Status auf "Einsatzbereit" zu setzen
  bool _requiresInspectionForReady() {
    final currentStatus = _status;
    final criticalStatuses = [
      EquipmentStatus.cleaning,
      EquipmentStatus.repair,
      EquipmentStatus.retired,
    ];

    // Prüfung erforderlich, wenn von einem kritischen Status zu "Einsatzbereit" gewechselt wird
    if (criticalStatuses.contains(currentStatus)) {
      return true;
    }

    // Zusätzlich prüfen, ob seit der letzten Prüfung kritische Änderungen vorgenommen wurden
    if (_latestInspection != null) {
      final daysSinceInspection = DateTime.now().difference(_latestInspection!.inspectionDate).inDays;

      // Wenn letzte Prüfung durchgefallen ist und mehr als 1 Tag her ist
      if (_latestInspection!.result == InspectionResult.failed && daysSinceInspection > 1) {
        return true;
      }
    }

    return false;
  }

  Future<void> _showInspectionRequiredDialog() async {
    final currentStatus = _status;
    String message = _getInspectionRequiredMessage(currentStatus);

    bool? shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.assignment_late,
                color: Colors.orange.shade700,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Prüfung erforderlich',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
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
                    Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Eine erfolgreiche Prüfung ist erforderlich, um den Status auf "Einsatzbereit" zu setzen.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.assignment_add),
              label: const Text('Prüfung durchführen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (shouldProceed == true) {
      await _navigateToInspection();
    }
  }

  String _getInspectionRequiredMessage(String currentStatus) {
    switch (currentStatus) {
      case EquipmentStatus.cleaning:
        return 'Diese Einsatzkleidung befindet sich aktuell in der Reinigung. '
            'Bevor sie wieder als einsatzbereit markiert werden kann, muss eine '
            'Prüfung durchgeführt werden, um sicherzustellen, dass sie ordnungsgemäß '
            'gereinigt wurde und keine Schäden aufweist.';
      case EquipmentStatus.repair:
        return 'Diese Einsatzkleidung war in Reparatur. '
            'Eine Prüfung ist erforderlich, um zu bestätigen, dass alle Reparaturen '
            'ordnungsgemäß durchgeführt wurden und die Ausrüstung wieder voll '
            'funktionsfähig ist.';
      case EquipmentStatus.retired:
        return 'Diese Einsatzkleidung war ausgemustert. '
            'Eine gründliche Prüfung ist erforderlich, um sicherzustellen, dass sie '
            'den Sicherheitsstandards entspricht und wieder für den Einsatz geeignet ist.';
      default:
        return 'Eine Prüfung ist erforderlich, bevor diese Einsatzkleidung wieder '
            'als einsatzbereit markiert werden kann.';
    }
  }

  Future<void> _navigateToInspection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EquipmentInspectionFormScreen(
          equipment: widget.equipment,
        ),
      ),
    );

    if (result == true) {
      // Prüfung wurde gespeichert, Daten neu laden
      await _loadInspectionData();

      // Prüfen, ob die neue Prüfung erfolgreich war
      if (_latestInspection != null &&
          (_latestInspection!.result == InspectionResult.passed ||
              _latestInspection!.result == InspectionResult.conditionalPass)) {

        // Status automatisch auf "Einsatzbereit" setzen, da Prüfung erfolgreich
        await _forceStatusUpdate(EquipmentStatus.ready);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prüfung erfolgreich! Status wurde auf "Einsatzbereit" gesetzt.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      } else if (_latestInspection != null && _latestInspection!.result == InspectionResult.failed) {
        // Bei durchgefallener Prüfung Warnung anzeigen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prüfung durchgefallen. Status wurde auf "In Reparatur" gesetzt.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Interne Methode für das direkte Setzen des Status ohne weitere Prüfungen
  Future<void> _forceStatusUpdate(String newStatus) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await _equipmentService.updateStatus(widget.equipment.id, newStatus);
      setState(() {
        _status = newStatus;
      });
    } catch (e) {
      print('Fehler beim Aktualisieren des Status: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _updateCheckDate() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await _equipmentService.updateCheckDate(widget.equipment.id, _checkDate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prüfdatum erfolgreich aktualisiert'),
            backgroundColor: Colors.green,
          ),
        );
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
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _deleteEquipment() async {
    if (!_canEditEquipment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sie haben keine Berechtigung, Einsatzkleidung zu löschen'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Einsatzkleidung löschen'),
        content: const Text(
            'Sind Sie sicher, dass Sie diese Einsatzkleidung löschen möchten? Diese Aktion kann nicht rückgängig gemacht werden.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Löschen',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _equipmentService.deleteEquipment(widget.equipment.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Einsatzkleidung erfolgreich gelöscht'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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
          _isProcessing = false;
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
            const Text('Einsatzkleidung Details'),
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
                  'Nur Ansicht',
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
          if (_canEditEquipment)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditEquipmentScreen(
                      equipment: widget.equipment,
                    ),
                  ),
                );

                if (result == true) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EquipmentDetailScreen(
                        equipment: widget.equipment,
                      ),
                    ),
                  );
                }
              },
              tooltip: 'Bearbeiten',
            ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EquipmentHistoryScreen(
                    equipment: widget.equipment,
                  ),
                ),
              );
            },
            tooltip: 'Verlauf anzeigen',
          ),
          if (_canEditEquipment)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _isProcessing ? null : _deleteEquipment,
              tooltip: 'Löschen',
            ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Berechtigung-Hinweis für Hygieneeinheit
            if (_isHygieneUnit && !_isAdmin)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hygieneeinheit-Ansicht',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sie können alle Details einsehen, aber keine Änderungen vornehmen',
                            style: TextStyle(
                              color: Colors.blue.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Grundinformationen
            _buildBasicInfoCard(),
            const SizedBox(height: 16),

            // Identifikation
            _buildIdentificationCard(),
            const SizedBox(height: 16),

            // Prüfinformationen - NEUE SEKTION
            _buildInspectionInfoCard(),
            const SizedBox(height: 16),

            // Status
            _buildStatusCard(),
            const SizedBox(height: 16),

            // Waschzyklen
            _buildWashCyclesCard(),
            const SizedBox(height: 16),

            // Prüfdatum (Legacy) - nur für Admins editierbar
            if (_canEditEquipment) _buildCheckDateCard(),
            if (_canEditEquipment) const SizedBox(height: 16),

            // Einsätze
            _buildMissionsCard(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EquipmentInspectionFormScreen(
                equipment: widget.equipment,
              ),
            ),
          );

          if (result == true) {
            _loadInspectionData(); // Prüfdaten neu laden
          }
        },
        icon: const Icon(Icons.assignment_add),
        label: const Text('Neue Prüfung'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
                const Text(
                  'Grundinformationen',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Artikel', widget.equipment.article),
            _buildInfoRow('Typ', widget.equipment.type),
            _buildInfoRow('Größe', widget.equipment.size),
            _buildInfoRow('Ortsfeuerwehr', widget.equipment.fireStation),
            _buildInfoRow('Besitzer', widget.equipment.owner),
            _buildInfoRow('Erstellt am', DateFormat('dd.MM.yyyy').format(widget.equipment.createdAt)),
            _buildInfoRow('Erstellt von', widget.equipment.createdBy),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentificationCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.qr_code,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Identifikation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('NFC-Tag', widget.equipment.nfcTag),
            if (widget.equipment.barcode != null && widget.equipment.barcode!.isNotEmpty)
              _buildInfoRow('Barcode', widget.equipment.barcode!),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectionInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.checklist,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Prüfinformationen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Prüfstatus-Badge
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getInspectionStatusColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _getInspectionStatusColor()),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getInspectionStatusIcon(),
                          size: 14,
                          color: _getInspectionStatusColor(),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _getInspectionStatus(),
                            style: TextStyle(
                              color: _getInspectionStatusColor(),
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

            if (_isLoadingInspections)
              const Center(child: CircularProgressIndicator())
            else if (_latestInspection == null)
              _buildNoInspectionInfo()
            else
              _buildLatestInspectionInfo(),

            const SizedBox(height: 16),

            // Aktions-Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EquipmentInspectionHistoryScreen(
                            equipment: widget.equipment,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Prüfhistorie', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EquipmentInspectionFormScreen(
                            equipment: widget.equipment,
                          ),
                        ),
                      );

                      if (result == true) {
                        _loadInspectionData();
                      }
                    },
                    icon: const Icon(Icons.assignment_add, size: 18),
                    label: const Text('Neue Prüfung', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoInspectionInfo() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_late,
            size: 40,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 8),
          Text(
            'Noch keine Prüfung durchgeführt',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Führen Sie die erste Prüfung durch, um den Status zu verfolgen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLatestInspectionInfo() {
    final inspection = _latestInspection!;
    final now = DateTime.now();
    final daysUntilNext = inspection.nextInspectionDate.difference(now).inDays;

    return Column(
      children: [
        // Letzte Prüfung
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.assignment_turned_in,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Letzte Prüfung',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildInspectionInfoRow('Datum', DateFormat('dd.MM.yyyy').format(inspection.inspectionDate)),
              _buildInspectionInfoRow('Prüfer', inspection.inspector),
              _buildInspectionInfoRow('Ergebnis', _getInspectionResultText(inspection.result)),
              if (inspection.issues != null && inspection.issues!.isNotEmpty)
                _buildInspectionInfoRow('Probleme', '${inspection.issues!.length} gefunden'),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Nächste Prüfung
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getInspectionStatusColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _getInspectionStatusColor()),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: _getInspectionStatusColor(),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Nächste Prüfung',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getInspectionStatusColor(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildInspectionInfoRow('Fällig am', DateFormat('dd.MM.yyyy').format(inspection.nextInspectionDate)),
              _buildInspectionInfoRow('Status', _getInspectionStatus()),
              if (daysUntilNext >= 0)
                _buildInspectionInfoRow('Verbleibend', '$daysUntilNext Tage'),
            ],
          ),
        ),

        // Probleme der letzten Prüfung (falls vorhanden)
        if (inspection.issues != null && inspection.issues!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Gefundene Probleme (${inspection.issues!.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: inspection.issues!.map((issue) =>
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          issue,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                  ).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInspectionInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _getInspectionResultText(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return 'Bestanden ✓';
      case InspectionResult.conditionalPass:
        return 'Bedingt bestanden ⚠';
      case InspectionResult.failed:
        return 'Durchgefallen ✗';
    }
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: EquipmentStatus.getStatusColor(_status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        EquipmentStatus.getStatusIcon(_status),
                        color: EquipmentStatus.getStatusColor(_status),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _status,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: EquipmentStatus.getStatusColor(_status),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Status-Änderung basierend auf Berechtigungen
            const SizedBox(height: 16),
            FutureBuilder<bool>(
              future: _permissionService.canPerformAction('update_equipment_status'),
              builder: (context, snapshot) {
                final canUpdateStatus = snapshot.data ?? false;

                if (canUpdateStatus) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Status ändern:'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: EquipmentStatus.values.map((status) {
                          bool isSelected = _status == status;
                          bool requiresInspection = status == EquipmentStatus.ready && _requiresInspectionForReady();

                          return InkWell(
                            onTap: isSelected ? null : () => _updateStatus(status),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? EquipmentStatus.getStatusColor(status)
                                    : EquipmentStatus.getStatusColor(status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: EquipmentStatus.getStatusColor(status),
                                  width: isSelected ? 0 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    EquipmentStatus.getStatusIcon(status),
                                    color: isSelected
                                        ? Colors.white
                                        : EquipmentStatus.getStatusColor(status),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : EquipmentStatus.getStatusColor(status),
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  if (requiresInspection && !isSelected) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.assignment_late,
                                      color: Colors.orange.shade600,
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                } else {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, color: Colors.grey.shade600, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Status kann nur von berechtigten Benutzern geändert werden',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),

            // Prüfpflicht-Hinweis bleibt für alle sichtbar
            if (_requiresInspectionForReady()) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.assignment_late, color: Colors.orange.shade600, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Prüfung erforderlich',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Um den Status auf "Einsatzbereit" zu setzen, muss eine erfolgreiche Prüfung durchgeführt werden.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWashCyclesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_laundry_service,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Waschzyklen',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Interaktive Steuerung basierend auf Berechtigungen
            FutureBuilder<bool>(
              future: _permissionService.canPerformAction('update_wash_cycles'),
              builder: (context, snapshot) {
                final canUpdateWashCycles = snapshot.data ?? false;

                if (canUpdateWashCycles) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle),
                        onPressed: _washCycles > 0
                            ? () => _updateWashCycles(_washCycles - 1)
                            : null,
                        color: Colors.red,
                        iconSize: 36,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '$_washCycles',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: () => _updateWashCycles(_washCycles + 1),
                        color: Colors.green,
                        iconSize: 36,
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      Center(
                        child: Text(
                          '$_washCycles',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, color: Colors.grey.shade600, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Nur Ansicht',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckDateCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Prüfdatum (Legacy)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.orange.shade600, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Verwenden Sie die neue Prüfungsfunktion für aktuelle Prüfungen',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _checkDateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Prüfdatum',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.event),
              ),
              onTap: _canEditEquipment ? _selectCheckDate : null,
            ),
            if (_canEditEquipment) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _updateCheckDate,
                  child: const Text('Prüfdatum aktualisieren'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMissionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
                  'Einsätze',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Zeigen Sie an, bei welchen Einsätzen diese Einsatzkleidung verwendet wurde:',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EquipmentMissionsScreen(
                        equipment: widget.equipment,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.assignment),
                label: const Text('Einsätze anzeigen'),
              ),
            ),
          ],
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
            width: 120,
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