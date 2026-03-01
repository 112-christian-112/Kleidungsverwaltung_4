// screens/missions/mission_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/equipment_model.dart';
import '../../models/mission_model.dart';
import '../../models/user_models.dart';
import '../../services/cleaning_receipt_pdf_service.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/cleaning_receipt_preview.dart';
import '../admin/equipment/equipment_detail_screen.dart';
import 'add_equipment_to_mission_nfc_screen.dart';
import 'edit_mission_screen.dart';
import 'mission_send_to_cleaning_screen.dart';

class MissionDetailScreen extends StatefulWidget {
  final String missionId;

  const MissionDetailScreen({Key? key, required this.missionId})
      : super(key: key);

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

  // Berechtigungen
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
      // User und Einsatz parallel laden
      final results = await Future.wait([
        _permissionService.getCurrentUser(),
        _missionService.getMissionById(widget.missionId),
        _missionService.getEquipmentForMission(widget.missionId),
      ]);

      final user = results[0] as UserModel?;
      final mission = results[1] as MissionModel?;
      final equipment = results[2] as List<EquipmentModel>;

      if (mission == null) throw Exception('Einsatz nicht gefunden');

      if (mounted) {
        setState(() {
          _currentUser = user;
          _mission = mission;
          _equipmentList = equipment;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'),
                backgroundColor: Colors.red));
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
      final cleaningEquipment = _equipmentList
          .where((e) => e.status == EquipmentStatus.cleaning)
          .toList();

      if (cleaningEquipment.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Keine Ausrüstung in der Reinigung'),
            backgroundColor: Colors.orange));
        setState(() => _isGeneratingPdf = false);
        return;
      }

      final pdfBytes =
          await CleaningReceiptPdfService.generateCleaningReceiptCopy(
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteMission() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Einsatz löschen'),
        content: const Text(
            'Sicher? Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _missionService.deleteMission(widget.missionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Einsatz gelöscht'),
            backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Einsatz-Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_mission == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Einsatz-Details')),
        body: const Center(child: Text('Einsatz nicht gefunden')),
      );
    }

    final typeIcon = _getTypeIcon(_mission!.type);
    final typeColor = _getTypeColor(_mission!.type);
    final typeText = _getTypeName(_mission!.type);
    final formattedDate =
        DateFormat('dd.MM.yyyy').format(_mission!.startTime);
    final formattedTime = DateFormat('HH:mm').format(_mission!.startTime);

    final cleaningEquipment =
        _equipmentList.where((e) => e.status == EquipmentStatus.cleaning).toList();
    final counts = _countTypes(_equipmentList);
    final cleaningCounts = _countTypes(cleaningEquipment);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatz-Details'),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          EditMissionScreen(mission: _mission!)),
                );
                if (result == true) _loadData();
              },
              tooltip: 'Bearbeiten',
            ),
          if (_canDelete)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteMission,
              tooltip: 'Löschen',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Einsatzübersicht ────────────────────────────────────────
              _buildOverviewCard(typeIcon, typeColor, typeText,
                  formattedDate, formattedTime),
              const SizedBox(height: 16),

              // ── Ausrüstungs-Statistik ───────────────────────────────────
              if (_equipmentList.isNotEmpty) ...[
                _buildStatisticsCard(counts, cleaningCounts),
                const SizedBox(height: 16),
              ],

              // ── Aktions-Buttons ─────────────────────────────────────────
              _buildActionButtons(cleaningEquipment),
              const SizedBox(height: 16),

              // ── Ausrüstungsliste ────────────────────────────────────────
              _buildEquipmentSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Karten ────────────────────────────────────────────────────────────────

  Widget _buildOverviewCard(IconData typeIcon, Color typeColor,
      String typeText, String date, String time) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: typeColor.withOpacity(0.2),
                  child: Icon(typeIcon, color: typeColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_mission!.name,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: typeColor.withOpacity(0.4)),
                        ),
                        child: Text(typeText,
                            style: TextStyle(
                                color: typeColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _infoRow(Icons.calendar_today, 'Datum', '$date um $time Uhr'),
            _infoRow(Icons.location_on, 'Ort', _mission!.location),
            _infoRow(Icons.local_fire_department, 'Ortswehr',
                _mission!.fireStation),
            if (_mission!.involvedFireStations.isNotEmpty &&
                _mission!.involvedFireStations.length > 1)
              _infoRow(Icons.group, 'Beteiligte',
                  _mission!.involvedFireStations.join(', ')),
            if (_mission!.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_mission!.description,
                  style: TextStyle(color: Colors.grey[700])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(
      _EquipmentCounts all, _EquipmentCounts cleaning) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ausrüstung',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _statChip('Gesamt', '${all.total}',
                        Icons.inventory, Colors.blue)),
                const SizedBox(width: 8),
                Expanded(
                    child: _statChip(
                        'Jacken',
                        '${all.jackets}',
                        Icons.accessibility_new,
                        Colors.indigo)),
                const SizedBox(width: 8),
                Expanded(
                    child: _statChip(
                        'Hosen',
                        '${all.pants}',
                        Icons.airline_seat_legroom_normal,
                        Colors.teal)),
              ],
            ),
            if (cleaning.total > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.orange.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_laundry_service,
                        color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Text(
                        '${cleaning.total} in der Reinigung (${cleaning.jackets} Jacken, ${cleaning.pants} Hosen)',
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(List<EquipmentModel> cleaningEquipment) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_canAddEquipment)
          _actionButton(
            icon: Icons.nfc,
            label: 'Kleidung erfassen',
            color: Colors.blue,
            onPressed: _addEquipmentByNfc,
          ),
        if (_canSendToCleaning && _equipmentList.isNotEmpty)
          _actionButton(
            icon: Icons.local_laundry_service,
            label: 'Reinigung',
            color: Colors.green,
            onPressed: _sendToCleaningAndGeneratePdf,
          ),
        if (cleaningEquipment.isNotEmpty)
          _actionButton(
            icon: _isGeneratingPdf ? null : Icons.description,
            label: 'Wäschereischein',
            color: Colors.purple,
            onPressed: _isGeneratingPdf ? null : _regenerateCleaningReceipt,
            isLoading: _isGeneratingPdf,
          ),
      ],
    );
  }

  Widget _buildEquipmentSection() {
    if (_equipmentList.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text('Noch keine Ausrüstung erfasst',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Ausrüstungsliste (${_equipmentList.length})',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ..._equipmentList.map((e) => _buildEquipmentTile(e)),
        ],
      ),
    );
  }

  Widget _buildEquipmentTile(EquipmentModel equipment) {
    final isCleaning = equipment.status == EquipmentStatus.cleaning;
    final isRepair = equipment.status == EquipmentStatus.repair;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
        child: Icon(
          equipment.type == 'Jacke'
              ? Icons.accessibility_new
              : Icons.airline_seat_legroom_normal,
          color: Colors.white,
          size: 18,
        ),
      ),
      title: Text(equipment.owner),
      subtitle: Text('${equipment.article} · Gr. ${equipment.size}'),
      trailing: isCleaning
          ? const Chip(
              avatar: Icon(Icons.local_laundry_service,
                  color: Colors.orange, size: 14),
              label: Text('Reinigung',
                  style: TextStyle(fontSize: 11)),
              backgroundColor: Color(0xFFFFF3E0),
            )
          : isRepair
              ? const Chip(
                  avatar: Icon(Icons.build,
                      color: Colors.red, size: 14),
                  label: Text('Reparatur',
                      style: TextStyle(fontSize: 11)),
                  backgroundColor: Color(0xFFFFEBEE),
                )
              : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                EquipmentDetailScreen(equipment: equipment)),
      ),
    );
  }

  // ── Hilfs-Widgets ─────────────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _statChip(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData? icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: color,
          foregroundColor: Colors.white,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  _EquipmentCounts _countTypes(List<EquipmentModel> list) {
    int jackets = 0, pants = 0, other = 0;
    for (final e in list) {
      switch (e.type.toLowerCase()) {
        case 'jacke':
          jackets++;
          break;
        case 'hose':
          pants++;
          break;
        default:
          other++;
      }
    }
    return _EquipmentCounts(jackets: jackets, pants: pants, other: other);
  }

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

class _EquipmentCounts {
  final int jackets;
  final int pants;
  final int other;
  const _EquipmentCounts(
      {required this.jackets, required this.pants, required this.other});
  int get total => jackets + pants + other;
}
