// screens/admin/equipment/equipment_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import '../../../models/user_models.dart';
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
  StreamSubscription? _equipmentSubscription;

  late int _washCycles;
  late DateTime _checkDate;
  late String _status;
  final TextEditingController _checkDateController = TextEditingController();

  EquipmentInspectionModel? _latestInspection;
  List<EquipmentInspectionModel> _recentInspections = [];
  bool _isLoadingInspections = true;

  bool get _canEdit =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentEdit == true;
  /// Status manuell ändern — bewusst von equipmentEdit entkoppelt
  bool get _canChangeStatus =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentStatusEdit == true;
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
    _checkDateController.text = DateFormat('dd.MM.yyyy').format(_checkDate);
    _status = widget.equipment.status;
    _loadUser();
    _loadInspectionData();
    _startEquipmentStream();
  }

  @override
  void dispose() {
    _inspectionSubscription?.cancel();
    _equipmentSubscription?.cancel();
    _checkDateController.dispose();
    super.dispose();
  }

  // ── Daten laden ───────────────────────────────────────────────────────────

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
          if (mounted) setState(() => _isLoadingInspections = false);
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (mounted) setState(() => _isLoadingInspections = false);
    }
  }

  void _startEquipmentStream() {
    _equipmentSubscription = _equipmentService
        .getEquipmentById(widget.equipment.id)
        .listen((equipment) {
      if (equipment != null && mounted) {
        setState(() {
          _status = equipment.status;
          _washCycles = equipment.washCycles;
          _checkDate = equipment.checkDate;
          _checkDateController.text =
              DateFormat('dd.MM.yyyy').format(_checkDate);
        });
      }
    }, onError: (_) {});
  }

  // ── Prüfstatus-Helfer ─────────────────────────────────────────────────────

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
    if (days < 0) return Icons.error_rounded;
    if (days <= 30) return Icons.warning_rounded;
    return Icons.check_circle_rounded;
  }

  String _getResultText(InspectionResult result) {
    switch (result) {
      case InspectionResult.passed:
        return 'Bestanden';
      case InspectionResult.conditionalPass:
        return 'Bedingt bestanden';
      case InspectionResult.failed:
        return 'Nicht bestanden';
    }
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
        _checkDateController.text = DateFormat('dd.MM.yyyy').format(picked);
      });
    }
  }

  /// Statuswechsel mit Prüfpflicht für Nicht-Admins.
  ///
  /// Regel: Wenn ein Nicht-Admin die Kleidung von "In der Reinigung" oder
  /// "In Reparatur" auf "Einsatzbereit" setzen will, muss er zuerst eine
  /// Prüfung durchführen. Die Prüfung setzt den Status automatisch auf
  /// "Einsatzbereit" — danach ist kein manueller Statuswechsel nötig.
  /// Admins können den Status jederzeit direkt ändern.
  void _handleStatusChange(String newStatus) {
    final isAdmin = _currentUser?.isAdmin == true;
    final requiresInspection = !isAdmin &&
        newStatus == EquipmentStatus.ready &&
        (_status == EquipmentStatus.cleaning ||
            _status == EquipmentStatus.repair);

    if (requiresInspection) {
      _showInspectionRequiredDialog();
    } else {
      _updateStatus(newStatus);
    }
  }

  void _showInspectionRequiredDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.assignment_turned_in_outlined,
            size: 40, color: Colors.orange),
        title: const Text('Prüfung erforderlich'),
        content: const Text(
          'Bevor die Kleidung wieder als "Einsatzbereit" markiert werden kann, '
          'muss eine Prüfung durchgeführt werden.'
          'Die Prüfung setzt den Status automatisch auf "Einsatzbereit".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => EquipmentInspectionFormScreen(
                      equipment: widget.equipment),
                ),
              );
              if (result == true && mounted) {
                setState(() => _status = EquipmentStatus.ready);
                _loadInspectionData();
              }
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Prüfung starten'),
          ),
        ],
      ),
    );
  }

  void _showStatusPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Status ändern',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ...EquipmentStatus.values.map((s) {
              final selected = _status == s;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      EquipmentStatus.getStatusColor(s).withOpacity(0.12),
                  child: Icon(EquipmentStatus.getStatusIcon(s),
                      color: EquipmentStatus.getStatusColor(s), size: 20),
                ),
                title: Text(s,
                    style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: selected
                            ? EquipmentStatus.getStatusColor(s)
                            : null)),
                trailing: selected
                    ? Icon(Icons.check_rounded,
                        color: EquipmentStatus.getStatusColor(s))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _handleStatusChange(s);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.equipment.article),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Bearbeiten',
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
            ),
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'Verlauf',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) =>
                        EquipmentHistoryScreen(equipment: widget.equipment))),
          ),
          if (_canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Löschen',
              onPressed: _isProcessing ? null : _deleteEquipment,
            ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 0. FREMD-WEHR-BANNER ─────────────────────────────
                  if (_currentUser != null &&
                      !_currentUser!.canSeeFireStation(widget.equipment.fireStation))
                    _buildForeignStationBanner(),
                  if (_currentUser != null &&
                      !_currentUser!.canSeeFireStation(widget.equipment.fireStation))
                    const SizedBox(height: 12),

                  // ── 1. HERO-HEADER ────────────────────────────────────
                  _buildHeroHeader(cs, isDark),
                  const SizedBox(height: 16),

                  // ── 2. SCHNELLAKTIONEN ────────────────────────────────
                  _buildQuickActions(cs),
                  const SizedBox(height: 20),

                  // ── 3. PRÜFINFORMATIONEN ──────────────────────────────
                  _buildInspectionCard(cs, isDark),
                  const SizedBox(height: 14),

                  // ── 4. DETAILS (kompakt) ──────────────────────────────
                  _buildDetailsCard(cs, isDark),
                  const SizedBox(height: 14),

                  // ── 5. STATUS (nur für berechtigte) ───────────────────
                  _buildStatusCard(cs, isDark),
                  const SizedBox(height: 14),

                  // ── 6. WASCHZYKLEN ────────────────────────────────────
                  _buildWashCard(cs, isDark),
                ],
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HERO HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeroHeader(ColorScheme cs, bool isDark) {
    final isJacke = widget.equipment.type == 'Jacke';
    final inspColor = _getInspectionStatusColor();
    final statusColor = EquipmentStatus.getStatusColor(_status);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Typ-Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isJacke
                        ? (isDark
                            ? const Color(0xFF1A3A5C)
                            : const Color(0xFFDBEAFB))
                        : (isDark
                            ? const Color(0xFF4D3000)
                            : const Color(0xFFFFF0CC)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isJacke
                        ? Icons.accessibility_new
                        : Icons.airline_seat_legroom_normal,
                    size: 30,
                    color: isJacke
                        ? (isDark
                            ? const Color(0xFF90CAF9)
                            : const Color(0xFF1565C0))
                        : (isDark
                            ? const Color(0xFFFFCC02)
                            : const Color(0xFFE65100)),
                  ),
                ),
                const SizedBox(width: 14),
                // Texte — Besitzer ist die wichtigste Info → zuerst
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.equipment.owner,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.equipment.article,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'Gr. ${widget.equipment.size} · ${widget.equipment.type}',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.local_fire_department_outlined,
                              size: 12, color: cs.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(widget.equipment.fireStation,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Chips: Status + Prüfstatus
            Row(
              children: [
                // Status-Chip
                _chip(
                  icon: EquipmentStatus.getStatusIcon(_status),
                  label: _status,
                  color: statusColor,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                // Prüfstatus-Chip
                _chip(
                  icon: _getInspectionStatusIcon(),
                  label: _isLoadingInspections
                      ? '…'
                      : _getInspectionStatus(),
                  color: inspColor,
                  isDark: isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
      {required IconData icon,
      required String label,
      required Color color,
      required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCHNELLAKTIONEN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickActions(ColorScheme cs) {
    return Row(
      children: [
        if (_canInspect) ...[
          Expanded(
            flex: 2,
            child: _actionButton(
              icon: Icons.fact_check_outlined,
              label: 'Neue Prüfung',
              filled: true,
              onTap: () async {
                final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EquipmentInspectionFormScreen(
                            equipment: widget.equipment)));
                if (result == true) _loadInspectionData();
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: _actionButton(
            icon: Icons.local_fire_department_outlined,
            label: 'Einsätze',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        EquipmentMissionsScreen(equipment: widget.equipment))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            icon: Icons.history_outlined,
            label: 'Prüfungen',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EquipmentInspectionHistoryScreen(
                        equipment: widget.equipment))),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: filled ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 22,
                  color: filled ? cs.onPrimary : cs.onSurfaceVariant),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: filled ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRÜFINFORMATIONEN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInspectionCard(ColorScheme cs, bool isDark) {
    final inspColor = _getInspectionStatusColor();

    return _sectionCard(
      title: 'Prüfinformationen',
      icon: Icons.fact_check_outlined,
      accentColor: inspColor,
      child: _isLoadingInspections
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          : _latestInspection == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text('Noch keine Prüfung durchgeführt',
                            style:
                                TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                    if (_canInspect) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
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
                  ],
                )
              : Column(
                  children: [
                    // Letzte Prüfung — prominent
                    _infoTile(
                      label: 'Letzte Prüfung',
                      value: DateFormat('dd.MM.yyyy')
                          .format(_latestInspection!.inspectionDate),
                      icon: Icons.event_available_outlined,
                    ),
                    _infoTile(
                      label: 'Nächste Prüfung',
                      value: DateFormat('dd.MM.yyyy')
                          .format(_latestInspection!.nextInspectionDate),
                      icon: Icons.event_outlined,
                      valueColor: inspColor,
                    ),
                    _infoTile(
                      label: 'Ergebnis',
                      value: _getResultText(_latestInspection!.result),
                      icon: Icons.rule_outlined,
                      valueColor: _getResultColor(_latestInspection!.result),
                    ),
                    if (_latestInspection!.inspector.isNotEmpty)
                      _infoTile(
                        label: 'Prüfer',
                        value: _latestInspection!.inspector,
                        icon: Icons.person_outline,
                      ),
                    // Prüfdatum ändern (nur canEdit)
                    if (_canEdit) ...[
                      const Divider(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _selectCheckDate,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Prüfdatum manuell setzen',
                                  prefixIcon:
                                      Icon(Icons.calendar_today, size: 18),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                child: Text(_checkDateController.text,
                                    style: const TextStyle(fontSize: 14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _updateCheckDate,
                            style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 13)),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAILS (kompakt)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailsCard(ColorScheme cs, bool isDark) {
    return _sectionCard(
      title: 'Details',
      icon: Icons.info_outline,
      child: Column(
        children: [
          _infoTile(
            label: 'NFC-Tag',
            value: widget.equipment.nfcTag.isNotEmpty
                ? widget.equipment.nfcTag
                : '—',
            icon: Icons.nfc_outlined,
            onTap: widget.equipment.nfcTag.isNotEmpty
                ? () {
                    Clipboard.setData(
                        ClipboardData(text: widget.equipment.nfcTag));
                    _showSuccess('NFC-Tag kopiert');
                  }
                : null,
            trailing: widget.equipment.nfcTag.isNotEmpty
                ? Icon(Icons.copy_outlined,
                    size: 14, color: cs.onSurfaceVariant)
                : null,
          ),
          if (widget.equipment.barcode?.isNotEmpty == true)
            _infoTile(
              label: 'Barcode',
              value: widget.equipment.barcode!,
              icon: Icons.qr_code_outlined,
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: widget.equipment.barcode!));
                _showSuccess('Barcode kopiert');
              },
              trailing:
                  Icon(Icons.copy_outlined, size: 14, color: cs.onSurfaceVariant),
            ),
          _infoTile(
            label: 'Erstellt am',
            value: DateFormat('dd.MM.yyyy').format(widget.equipment.createdAt),
            icon: Icons.calendar_today_outlined,
          ),
          _infoTile(
            label: 'Erstellt von',
            value: widget.equipment.createdBy.isNotEmpty
                ? widget.equipment.createdBy
                : '—',
            icon: Icons.person_add_outlined,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatusCard(ColorScheme cs, bool isDark) {
    final statusColor = EquipmentStatus.getStatusColor(_status);
    return _sectionCard(
      title: 'Status',
      icon: Icons.swap_horiz_rounded,
      child: _canChangeStatus
          ? GestureDetector(
              onTap: _showStatusPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(isDark ? 0.15 : 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Icon(EquipmentStatus.getStatusIcon(_status),
                        color: statusColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_status,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                    ),
                    Icon(Icons.expand_more_rounded,
                        color: statusColor.withOpacity(0.7), size: 20),
                  ],
                ),
              ),
            )
          : Row(
              children: [
                Icon(EquipmentStatus.getStatusIcon(_status),
                    color: statusColor, size: 20),
                const SizedBox(width: 8),
                Text(_status,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(Icons.lock_outline, size: 14, color: cs.onSurfaceVariant),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WASCHZYKLEN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWashCard(ColorScheme cs, bool isDark) {
    return _sectionCard(
      title: 'Waschzyklen',
      icon: Icons.local_laundry_service_outlined,
      child: Row(
        children: [
          // Visualisierung
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$_washCycles',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Durchgeführte Wäschen',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant)),
                if (_canChangeStatus || _canInspect) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _washButton(
                        icon: Icons.remove,
                        color: Colors.red,
                        onPressed: _washCycles > 0
                            ? () => _updateWashCycles(_washCycles - 1)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _washButton(
                        icon: Icons.add,
                        color: Colors.green,
                        onPressed: () => _updateWashCycles(_washCycles + 1),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _washButton(
      {required IconData icon,
      required Color color,
      VoidCallback? onPressed}) {
    return SizedBox(
      width: 36,
      height: 36,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: onPressed != null
              ? color.withOpacity(0.12)
              : Colors.grey.withOpacity(0.08),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        child:
            Icon(icon, size: 18, color: onPressed != null ? color : Colors.grey),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HILFS-WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Einheitliche Section-Card
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Color? accentColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = accentColor ?? cs.primary;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  /// Einheitliche Info-Zeile mit Icon
  Widget _infoTile({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? cs.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildForeignStationBanner() {
    final e = widget.equipment;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.swap_horiz, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kleidung einer anderen Ortswehr',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Besitzer: ${e.owner}  ·  Heimatwehr: ${e.fireStation}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
