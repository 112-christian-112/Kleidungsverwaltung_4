// screens/missions/mission_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/equipment_model.dart';
import '../../models/mission_model.dart';
import '../../models/user_models.dart';
import '../../services/cleaning_receipt_pdf_service.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';

import '../admin/equipment/equipment_detail_screen.dart';
import 'add_equipment_to_mission_nfc_screen.dart';
import 'edit_mission_screen.dart';
import 'mission_send_to_cleaning_screen.dart';
import '../../widgets/cleaning_receipt_preview.dart';

class MissionDetailScreen extends StatefulWidget {
  final String missionId;
  const MissionDetailScreen({Key? key, required this.missionId}) : super(key: key);

  @override
  State<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends State<MissionDetailScreen> {
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();

  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  MissionModel? _mission;
  List<EquipmentModel> _equipmentList = [];

  bool get _canEdit =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.missionEdit == true;
  bool get _canDelete => _currentUser?.isAdmin == true;
  bool get _canAddEquipment =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.equipmentView == true;
  bool get _canSendToCleaning =>
      _currentUser?.isAdmin == true ||
      _currentUser?.permissions.cleaningCreate == true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _permissionService.getCurrentUser(),
        _missionService.getMissionById(widget.missionId),
        _missionService.getEquipmentForMission(widget.missionId),
      ]);
      if (mounted) {
        setState(() {
          _currentUser = results[0] as UserModel?;
          _mission = results[1] as MissionModel?;
          _equipmentList = results[2] as List<EquipmentModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Aktionen ──────────────────────────────────────────────────────────────

  Future<void> _addEquipmentByNfc() async {
    if (_mission == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEquipmentToMissionNfcScreen(
          missionId: _mission!.id,
          alreadyAddedEquipmentIds: _mission!.equipmentIds,
        ),
      ),
    );
    if (result == true) _loadData();
  }

  Future<void> _sendToCleaningAndGeneratePdf() async {
    if (_mission == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionSendToCleaningScreen(
          missionId: _mission!.id,
          missionName: _mission!.name,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _regenerateCleaningReceipt() async {
    if (_mission == null) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final cleaningEquipment =
          _equipmentList.where((e) => e.status == EquipmentStatus.cleaning).toList();
      if (cleaningEquipment.isEmpty) {
        _showSnack('Keine Ausrüstung in der Reinigung', Colors.orange);
        setState(() => _isGeneratingPdf = false);
        return;
      }
      final pdfBytes = await CleaningReceiptPdfService.generateCleaningReceiptCopy(
        mission: _mission!,
        equipmentList: cleaningEquipment,
      );
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CleaningReceiptPreviewScreen(
              pdfBytes: pdfBytes,
              mission: _mission!,
              equipmentList: cleaningEquipment,
              isRegenerated: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        _showSnack('Fehler beim PDF: $e', Colors.red);
      }
    }
  }

  Future<void> _deleteMission() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Einsatz löschen'),
        content: const Text('Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      await _missionService.deleteMission(widget.missionId);
      if (mounted) {
        _showSnack('Einsatz gelöscht', Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Fehler: $e', Colors.red);
      }
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating));
  }

  // ── Typ-Helfer ────────────────────────────────────────────────────────────

  IconData _typeIcon(String t) {
    switch (t) {
      case 'fire': return Icons.local_fire_department;
      case 'technical': return Icons.build;
      case 'hazmat': return Icons.dangerous;
      case 'water': return Icons.water;
      case 'training': return Icons.school;
      default: return Icons.assignment;
    }
  }

  Color _typeColor(String t) {
    switch (t) {
      case 'fire': return Colors.red.shade700;
      case 'technical': return Colors.blue.shade700;
      case 'hazmat': return Colors.orange.shade700;
      case 'water': return Colors.lightBlue.shade700;
      case 'training': return Colors.green.shade700;
      default: return Colors.grey.shade700;
    }
  }

  String _typeName(String t) {
    const m = {
      'fire': 'Brandeinsatz',
      'technical': 'Technische Hilfeleistung',
      'hazmat': 'Gefahrguteinsatz',
      'water': 'Wasser / Hochwasser',
      'training': 'Übung',
    };
    return m[t] ?? 'Sonstiger Einsatz';
  }

  _EquipmentCounts _countTypes(List<EquipmentModel> list) {
    int j = 0, h = 0, o = 0;
    for (final e in list) {
      switch (e.type.toLowerCase()) {
        case 'jacke': j++; break;
        case 'hose': h++; break;
        default: o++;
      }
    }
    return _EquipmentCounts(jackets: j, pants: h, other: o);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Einsatz')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_mission == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Einsatz')),
        body: const Center(child: Text('Einsatz nicht gefunden')),
      );
    }

    final m = _mission!;
    final tc = _typeColor(m.type);
    final ti = _typeIcon(m.type);
    final tn = _typeName(m.type);
    final date = DateFormat('dd.MM.yyyy').format(m.startTime);
    final time = DateFormat('HH:mm').format(m.startTime);
    final cleaningEquipment =
        _equipmentList.where((e) => e.status == EquipmentStatus.cleaning).toList();
    final counts = _countTypes(_equipmentList);

    return Scaffold(
      appBar: AppBar(
        title: Text(m.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Bearbeiten',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EditMissionScreen(mission: m)),
                );
                if (result == true) _loadData();
              },
            ),
          if (_canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Löschen',
              onPressed: _deleteMission,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Einsatz-Typ Banner ─────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: tc.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tc.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(ti, color: tc, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tn,
                              style: TextStyle(
                                  color: tc,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          Text('$date · $time Uhr · ${m.location}',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
                  // ── Einsatzdetails ─────────────────────────────────
                  _sectionCard(
                    icon: Icons.info_outline,
                    title: 'Einsatzdetails',
                    child: Column(
                      children: [
                        _infoRow(Icons.local_fire_department,
                            'Ortswehr', m.fireStation),
                        if (m.involvedFireStations.isNotEmpty &&
                            m.involvedFireStations.length > 1)
                          _infoRow(Icons.group, 'Beteiligte',
                              m.involvedFireStations.join(', ')),
                        if (m.description.isNotEmpty)
                          _infoRow(Icons.notes, 'Beschreibung',
                              m.description),
                        if (m.createdBy.isNotEmpty)
                          _infoRow(Icons.person_outline,
                              'Erfasst von', m.createdBy),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Ausrüstungs-Statistik ──────────────────────────
                  _sectionCard(
                    icon: Icons.inventory_2_outlined,
                    title: 'Ausrüstung',
                    trailing: _equipmentList.isNotEmpty
                        ? Text('${counts.total} Stück',
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13))
                        : null,
                    child: _equipmentList.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('Noch keine Ausrüstung erfasst',
                                style: TextStyle(
                                    color: Colors.grey.shade500)),
                          )
                        : Column(
                            children: [
                              // Stat-Zeile
                              Row(
                                children: [
                                  _statBox('Gesamt', counts.total,
                                      Icons.inventory, tc),
                                  const SizedBox(width: 8),
                                  _statBox('Jacken', counts.jackets,
                                      Icons.accessibility_new,
                                      Colors.blue.shade600),
                                  const SizedBox(width: 8),
                                  _statBox('Hosen', counts.pants,
                                      Icons.airline_seat_legroom_normal,
                                      Colors.amber.shade700),
                                ],
                              ),
                              if (cleaningEquipment.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.local_laundry_service,
                                          color: Colors.orange.shade700,
                                          size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${cleaningEquipment.length} in der Reinigung',
                                        style: TextStyle(
                                            color: Colors.orange.shade700,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),

                  // ── Ausrüstungsliste ───────────────────────────────
                  if (_equipmentList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _sectionCard(
                      icon: Icons.list_alt,
                      title: 'Kleidungsstücke',
                      child: Column(
                        children: _equipmentList
                            .map((e) => _equipmentTile(e))
                            .toList(),
                      ),
                    ),
                  ],
            ],
          ),
        ),
      ),

      // ── Feste Bottom-Bar mit Aktionen ──────────────────────────────────
      bottomNavigationBar: _buildBottomBar(cleaningEquipment),
    );
  }

  // ── Bottom-Bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar(List<EquipmentModel> cleaningEquipment) {
    final hasActions = _canAddEquipment ||
        (_canSendToCleaning && _equipmentList.isNotEmpty) ||
        cleaningEquipment.isNotEmpty;

    if (!hasActions) return const SizedBox.shrink();

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_canAddEquipment)
              Expanded(
                child: _bottomButton(
                  icon: Icons.nfc,
                  label: 'Kleidung erfassen',
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _addEquipmentByNfc,
                ),
              ),
            if (_canAddEquipment &&
                (_canSendToCleaning && _equipmentList.isNotEmpty))
              const SizedBox(width: 8),
            if (_canSendToCleaning && _equipmentList.isNotEmpty)
              Expanded(
                child: _bottomButton(
                  icon: Icons.local_laundry_service,
                  label: 'Reinigung',
                  color: Colors.green.shade700,
                  onPressed: _sendToCleaningAndGeneratePdf,
                ),
              ),
            if (cleaningEquipment.isNotEmpty) ...[
              const SizedBox(width: 8),
              _bottomButton(
                icon: _isGeneratingPdf ? null : Icons.picture_as_pdf,
                label: 'Schein',
                color: Colors.purple.shade700,
                onPressed: _isGeneratingPdf ? null : _regenerateCleaningReceipt,
                isLoading: _isGeneratingPdf,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomButton({
    required IconData? icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool compact = false,
  }) {
    final btn = ElevatedButton.icon(
      onPressed: onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
            vertical: 12, horizontal: compact ? 14 : 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    return compact ? btn : btn;
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text('$value',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _equipmentTile(EquipmentModel e) {
    final isCleaning = e.status == EquipmentStatus.cleaning;
    final isRepair = e.status == EquipmentStatus.repair;
    final statusColor = isCleaning
        ? Colors.orange
        : isRepair
            ? Colors.red
            : Colors.green;
    final statusLabel = isCleaning
        ? 'Reinigung'
        : isRepair
            ? 'Reparatur'
            : 'Bereit';

    return InkWell(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => EquipmentDetailScreen(equipment: e))),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  e.type == 'Jacke' ? Colors.blue.shade50 : Colors.amber.shade50,
              child: Icon(
                e.type == 'Jacke'
                    ? Icons.accessibility_new
                    : Icons.airline_seat_legroom_normal,
                size: 18,
                color: e.type == 'Jacke'
                    ? Colors.blue.shade600
                    : Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.owner,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('${e.article} · Gr. ${e.size}',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class _EquipmentCounts {
  final int jackets, pants, other;
  const _EquipmentCounts(
      {required this.jackets, required this.pants, required this.other});
  int get total => jackets + pants + other;
}
