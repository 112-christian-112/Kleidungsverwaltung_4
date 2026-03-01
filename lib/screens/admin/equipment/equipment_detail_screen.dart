// screens/admin/equipment/equipment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import 'dart:async';
import '../../../models/user_models.dart';
import '../../../services/equipment_service.dart';
import '../../../services/equipment_inspection_service.dart';
import '../../../services/permission_service.dart';
import 'edit_equipment_screen.dart';
import 'equipment_inspection_history.dart'; // Dateiname bleibt gleich
import 'equipment_inspection_form_screen.dart';
import 'equipment_missions_screen.dart';
import 'history_screen.dart';

class EquipmentDetailScreen extends StatefulWidget {
  final EquipmentModel equipment;
  const EquipmentDetailScreen({Key? key, required this.equipment})
      : super(key: key);

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  final EquipmentInspectionService _inspectionService =
      EquipmentInspectionService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isProcessing = false;
  StreamSubscription? _inspectionSubscription;

  late int _washCycles;
  late DateTime _checkDate;
  late String _status;
  final TextEditingController _checkDateController = TextEditingController();

  EquipmentInspectionModel? _latestInspection;
  List<EquipmentInspectionModel> _recentInspections = [];
  bool _isLoadingInspections = true;

  // Abgeleitete Berechtigungen
  bool get _canEdit =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentEdit == true;
  bool get _canDelete =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentDelete == true;
  bool get _canInspect =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.inspectionPerform == true;

  @override
  void initState() {
    super.initState();
    _washCycles = widget.equipment.washCycles;
    _checkDate = widget.equipment.checkDate;
    _checkDateController.text =
        DateFormat('dd.MM.yyyy').format(_checkDate);
    _status = widget.equipment.status;
    _loadUser();
    _loadInspectionData();
  }

  @override
  void dispose() {
    _inspectionSubscription?.cancel();
    _checkDateController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await _permissionService.getCurrentUser();
    if (mounted) setState(() => _currentUser = user);
  }

  Future<void> _loadInspectionData() async {
    if (!mounted) return;
    setState(() => _isLoadingInspections = true);

    await _inspectionSubscription?.cancel();

    try {
      _inspectionSubscription = _inspectionService
          .getInspectionsForEquipment(widget.equipment.id)
          .listen(
        (inspections) {
          print('Prüfungen geladen: ${inspections.length}');
          if (mounted) {
            setState(() {
              _recentInspections = inspections;
              _latestInspection =
                  inspections.isNotEmpty ? inspections.first : null;
              _isLoadingInspections = false;
            });
          }
        },
        onError: (e) {
          print('Stream-Fehler Prüfungen: $e');
          if (mounted) setState(() => _isLoadingInspections = false);
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('Fehler beim Starten des Prüfungs-Streams: $e');
      if (mounted) setState(() => _isLoadingInspections = false);
    }
  }

  // ── Prüfstatus ────────────────────────────────────────────────────────────

  String _getInspectionStatus() {
    if (_latestInspection == null) return 'Noch nie geprüft';
    final days =
        _latestInspection!.nextInspectionDate.difference(DateTime.now()).inDays;
    if (days < 0) return 'Überfällig (${-days} Tage)';
    if (days <= 30) return 'Bald fällig ($days Tage)';
    return 'Aktuell';
  }

  Color _getInspectionStatusColor() {
    if (_latestInspection == null) return Colors.grey;
    final days =
        _latestInspection!.nextInspectionDate.difference(DateTime.now()).inDays;
    if (days < 0) return Colors.red;
    if (days <= 30) return Colors.orange;
    return Colors.green;
  }

  IconData _getInspectionStatusIcon() {
    if (_latestInspection == null) return Icons.help_outline;
    final days =
        _latestInspection!.nextInspectionDate.difference(DateTime.now()).inDays;
    if (days < 0) return Icons.error;
    if (days <= 30) return Icons.warning;
    return Icons.check_circle;
  }

  // ── Aktionen ──────────────────────────────────────────────────────────────

  Future<void> _updateWashCycles(int newCount) async {
    if (newCount < 0) return;
    setState(() => _isProcessing = true);
    try {
      await _equipmentService.updateWashCycles(widget.equipment.id, newCount);
      if (mounted) setState(() => _washCycles = newCount);
    } catch (e) {
      _showError('Fehler: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isProcessing = true);
    try {
      await _equipmentService.updateStatus(widget.equipment.id, newStatus);
      if (mounted) setState(() => _status = newStatus);
    } catch (e) {
      _showError('Fehler: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _updateCheckDate() async {
    setState(() => _isProcessing = true);
    try {
      await _equipmentService.updateCheckDate(widget.equipment.id, _checkDate);
      _showSuccess('Prüfdatum aktualisiert');
    } catch (e) {
      _showError('Fehler: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteEquipment() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Einsatzkleidung löschen'),
        content: const Text(
            'Wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await _equipmentService.deleteEquipment(widget.equipment.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Fehler: $e');
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _selectCheckDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _checkDate = picked;
        _checkDateController.text =
            DateFormat('dd.MM.yyyy').format(picked);
      });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Details'),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EditEquipmentScreen(
                            equipment: widget.equipment)));
                if (result == true && mounted) {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => EquipmentDetailScreen(
                              equipment: widget.equipment)));
                }
              },
              tooltip: 'Bearbeiten',
            ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        EquipmentHistoryScreen(equipment: widget.equipment))),
            tooltip: 'Verlauf',
          ),
          if (_canDelete)
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBasicInfoCard(),
                  const SizedBox(height: 16),
                  _buildIdentificationCard(),
                  const SizedBox(height: 16),
                  _buildInspectionInfoCard(),
                  const SizedBox(height: 16),
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildWashCyclesCard(),
                  const SizedBox(height: 16),
                  if (_canEdit) ...[
                    _buildCheckDateCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildMissionsCard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: _canInspect
          ? FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EquipmentInspectionFormScreen(
                            equipment: widget.equipment)));
                if (result == true) _loadInspectionData();
              },
              icon: const Icon(Icons.assignment_add),
              label: const Text('Neue Prüfung'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _buildBasicInfoCard() {
    return _card(
      icon: Icons.inventory_2,
      title: 'Grundinformationen',
      child: Column(
        children: [
          _infoRow('Artikel', widget.equipment.article),
          _infoRow('Typ', widget.equipment.type),
          _infoRow('Größe', widget.equipment.size),
          _infoRow('Ortsfeuerwehr', widget.equipment.fireStation),
          _infoRow('Besitzer', widget.equipment.owner),
          _infoRow('Erstellt am',
              DateFormat('dd.MM.yyyy').format(widget.equipment.createdAt)),
          _infoRow('Erstellt von', widget.equipment.createdBy),
        ],
      ),
    );
  }

  Widget _buildIdentificationCard() {
    return _card(
      icon: Icons.qr_code,
      title: 'Identifikation',
      child: Column(
        children: [
          _infoRow('NFC-Tag', widget.equipment.nfcTag),
          if (widget.equipment.barcode?.isNotEmpty == true)
            _infoRow('Barcode', widget.equipment.barcode!),
        ],
      ),
    );
  }

  Widget _buildInspectionInfoCard() {
    final statusColor = _getInspectionStatusColor();
    return _card(
      icon: Icons.checklist,
      title: 'Prüfinformationen',
      badge: _isLoadingInspections
          ? null
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getInspectionStatusIcon(),
                      size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Text(_getInspectionStatus(),
                      style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
      child: _isLoadingInspections
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          : _latestInspection == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Noch keine Prüfung vorhanden'),
                    const SizedBox(height: 8),
                    if (_canInspect)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        EquipmentInspectionFormScreen(
                                            equipment: widget.equipment)));
                            if (result == true) _loadInspectionData();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Erste Prüfung erfassen'),
                        ),
                      ),
                  ],
                )
              : Column(
                  children: [
                    _infoRow(
                        'Letzte Prüfung',
                        DateFormat('dd.MM.yyyy')
                            .format(_latestInspection!.inspectionDate)),
                    _infoRow(
                        'Nächste Prüfung',
                        DateFormat('dd.MM.yyyy')
                            .format(_latestInspection!.nextInspectionDate)),
                    _infoRow('Ergebnis',
                        _getResultText(_latestInspection!.result)),
                    if (_latestInspection!.inspector.isNotEmpty)
                      _infoRow('Prüfer', _latestInspection!.inspector),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    EquipmentInspectionHistoryScreen(
                                        equipment: widget.equipment))),
                        icon: const Icon(Icons.history),
                        label: const Text('Alle Prüfungen anzeigen'),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatusCard() {
    return _card(
      icon: Icons.info_outline,
      title: 'Status',
      child: _canEdit
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: EquipmentStatus.values.map((s) {
                final selected = _status == s;
                return GestureDetector(
                  onTap: () => _updateStatus(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? EquipmentStatus.getStatusColor(s)
                          : EquipmentStatus.getStatusColor(s).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: EquipmentStatus.getStatusColor(s),
                          width: selected ? 0 : 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(EquipmentStatus.getStatusIcon(s),
                            color: selected
                                ? Colors.white
                                : EquipmentStatus.getStatusColor(s),
                            size: 16),
                        const SizedBox(width: 6),
                        Text(s,
                            style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : EquipmentStatus.getStatusColor(s),
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            )
          : Row(
              children: [
                Icon(EquipmentStatus.getStatusIcon(_status),
                    color: EquipmentStatus.getStatusColor(_status), size: 20),
                const SizedBox(width: 8),
                Text(_status,
                    style: TextStyle(
                        color: EquipmentStatus.getStatusColor(_status),
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(Icons.lock, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text('Nur Ansicht',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
    );
  }

  Widget _buildWashCyclesCard() {
    return _card(
      icon: Icons.local_laundry_service,
      title: 'Waschzyklen',
      child: _canEdit
          ? Row(
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
                Text('$_washCycles',
                    style: const TextStyle(
                        fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: () => _updateWashCycles(_washCycles + 1),
                  color: Colors.green,
                  iconSize: 36,
                ),
              ],
            )
          : Center(
              child: Text('$_washCycles',
                  style: const TextStyle(
                      fontSize: 36, fontWeight: FontWeight.bold))),
    );
  }

  Widget _buildCheckDateCard() {
    return _card(
      icon: Icons.event,
      title: 'Prüfdatum',
      child: Column(
        children: [
          TextFormField(
            controller: _checkDateController,
            readOnly: true,
            onTap: _canEdit ? _selectCheckDate : null,
            decoration: InputDecoration(
              labelText: 'Nächstes Prüfdatum',
              suffixIcon: _canEdit
                  ? const Icon(Icons.calendar_today)
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _updateCheckDate,
                  child: const Text('Prüfdatum aktualisieren')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMissionsCard() {
    return _card(
      icon: Icons.assignment,
      title: 'Einsätze',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Einsätze in denen diese Einsatzkleidung verwendet wurde:'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EquipmentMissionsScreen(
                          equipment: widget.equipment))),
              icon: const Icon(Icons.local_fire_department),
              label: const Text('Einsätze anzeigen'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  Widget _card(
      {required IconData icon,
      required String title,
      required Widget child,
      Widget? badge}) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    color: Theme.of(context).colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold))),
                if (badge != null) badge,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getResultText(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return 'Bestanden ✓';
      case InspectionResult.conditionalPass:
        return 'Bedingt bestanden ⚠';
      case InspectionResult.failed:
        return 'Durchgefallen ✗';
    }
  }
}
