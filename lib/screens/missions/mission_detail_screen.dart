// screens/missions/mission_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/mission_model.dart';
import '../../models/equipment_model.dart';
import '../../services/mission_service.dart';
import '../../services/permission_service.dart';
import '../../services/cleaning_receipt_pdf_service.dart';

import '../../widgets/cleaning_receipt_preview.dart';
import 'edit_mission_screen.dart';
import 'add_equipment_to_mission_nfc_screen.dart';
import 'mission_send_to_cleaning_screen.dart';
import '../admin/equipment/equipment_detail_screen.dart';

class MissionDetailScreen extends StatefulWidget {
  final String missionId;

  const MissionDetailScreen({
    Key? key,
    required this.missionId,
  }) : super(key: key);

  @override
  State<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends State<MissionDetailScreen> {
  final MissionService _missionService = MissionService();
  final PermissionService _permissionService = PermissionService();
  bool _isAdmin = false;
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  MissionModel? _mission;
  List<EquipmentModel> _equipmentList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAdmin = await _permissionService.isAdmin();

      final missionDoc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .get();

      if (!missionDoc.exists) {
        throw Exception('Einsatz nicht gefunden');
      }

      final mission = MissionModel.fromMap(
          missionDoc.data() as Map<String, dynamic>,
          missionDoc.id
      );

      final equipmentList = await _missionService.getEquipmentForMission(widget.missionId);

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _mission = mission;
          _equipmentList = equipmentList;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Einsatzdaten: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addEquipmentByNfc() async {
    if (_mission == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddEquipmentToMissionNfcScreen(
          missionId: _mission!.id,
          alreadyAddedEquipmentIds: _mission!.equipmentIds,
        ),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _sendToCleaningAndGeneratePdf() async {
    if (_mission == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MissionSendToCleaningScreen(
          missionId: _mission!.id,
          missionName: _mission!.name,
        ),
      ),
    );

    _loadData();
  }

  // Vereinfachte Funktion: Wäschereischein für bereits in der Reinigung befindliche Ausrüstung generieren
  Future<void> _regenerateCleaningReceipt() async {
    if (_mission == null) return;

    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      // Alle Ausrüstungsgegenstände finden, die in der Reinigung sind
      final cleaningEquipment = _equipmentList
          .where((item) => item.status == EquipmentStatus.cleaning)
          .toList();

      if (cleaningEquipment.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Keine Ausrüstung in der Reinigung gefunden'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isGeneratingPdf = false;
        });
        return;
      }

      // PDF generieren mit dem neuen Service
      final pdfBytes = await CleaningReceiptPdfService.generateCleaningReceiptCopy(
        mission: _mission!,
        equipmentList: cleaningEquipment,
      );

      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });

        // PDF anzeigen mit der ausgelagerten Preview-Screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CleaningReceiptPreviewScreen(
              pdfBytes: pdfBytes,
              mission: _mission!,
              equipmentList: cleaningEquipment,
              isRegenerated: true,
            ),
          ),
        );
      }
    } catch (e) {
      print('Fehler beim Generieren des Wäschereischeins: $e');
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMission() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sie haben keine Berechtigung, Einsätze zu löschen'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Einsatz löschen'),
        content: const Text(
          'Sind Sie sicher, dass Sie diesen Einsatz löschen möchten? Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _missionService.deleteMission(widget.missionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Einsatz erfolgreich gelöscht'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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

    final formattedStartDate = DateFormat('dd.MM.yyyy').format(_mission!.startTime);
    final formattedStartTime = DateFormat('HH:mm').format(_mission!.startTime);

    // Einsatztyp-Anzeige
    IconData typeIcon;
    Color typeColor;
    String typeText;

    switch (_mission!.type) {
      case 'fire':
        typeIcon = Icons.local_fire_department;
        typeColor = Colors.red;
        typeText = 'Brandeinsatz';
        break;
      case 'technical':
        typeIcon = Icons.build;
        typeColor = Colors.blue;
        typeText = 'Technische Hilfeleistung';
        break;
      case 'hazmat':
        typeIcon = Icons.dangerous;
        typeColor = Colors.orange;
        typeText = 'Gefahrguteinsatz';
        break;
      case 'water':
        typeIcon = Icons.water;
        typeColor = Colors.lightBlue;
        typeText = 'Wasser/Hochwasser';
        break;
      case 'training':
        typeIcon = Icons.school;
        typeColor = Colors.green;
        typeText = 'Übung';
        break;
      default:
        typeIcon = Icons.more_horiz;
        typeColor = Colors.grey;
        typeText = 'Sonstiger Einsatz';
        break;
    }

    // Prüfen, ob Ausrüstung in der Reinigung ist
    final cleaningEquipment = _equipmentList
        .where((item) => item.status == EquipmentStatus.cleaning)
        .toList();

    // Ausrüstungsstatistiken berechnen
    final allEquipmentCounts = _countEquipmentTypes(_equipmentList);
    final cleaningCounts = _countEquipmentTypes(cleaningEquipment);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatz-Details'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditMissionScreen(
                      mission: _mission!,
                    ),
                  ),
                );

                if (result == true) {
                  _loadData();
                }
              },
              tooltip: 'Bearbeiten',
            ),
          if (_isAdmin)
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Einsatzübersicht
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: typeColor.withOpacity(0.2),
                            child: Icon(typeIcon, color: typeColor, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _mission!.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: typeColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: typeColor.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    typeText,
                                    style: TextStyle(
                                      color: typeColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _buildInfoRow('Einsatzort:', _mission!.location),
                      _buildInfoRow('Datum:', formattedStartDate),
                      _buildInfoRow('Uhrzeit:', '$formattedStartTime Uhr'),
                      _buildInfoRow('Feuerwehr:', _mission!.fireStation),

                      // Beteiligte Ortswehren
                      if (_mission!.involvedFireStations.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Beteiligte Ortswehren:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _mission!.involvedFireStations.map((station) => Chip(
                            label: Text(station),
                            backgroundColor: station == _mission!.fireStation
                                ? typeColor.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                            labelStyle: TextStyle(
                              fontWeight: station == _mission!.fireStation ? FontWeight.bold : FontWeight.normal,
                            ),
                          )).toList(),
                        ),
                      ],

                      // Beschreibung
                      if (_mission!.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Beschreibung:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(_mission!.description),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Ausrüstungsbereich
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Verwendete Ausrüstung',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  // Ausrüstungsstatistiken
                  if (_equipmentList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Statistik',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    'Gesamt',
                                    '${allEquipmentCounts.total}',
                                    Icons.inventory,
                                    Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildStatCard(
                                    'In Reinigung',
                                    '${cleaningCounts.total}',
                                    Icons.local_laundry_service,
                                    Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Button-Leiste
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        _buildActionButton(
                          icon: Icons.nfc,
                          label: 'Kleidung erfassen',
                          onPressed: _addEquipmentByNfc,
                          color: Colors.blue,
                        ),
                        if (_equipmentList.isNotEmpty)
                          _buildActionButton(
                            icon: Icons.local_laundry_service,
                            label: 'Reinigung',
                            onPressed: _sendToCleaningAndGeneratePdf,
                            color: Colors.green,
                          ),
                        if (cleaningEquipment.isNotEmpty)
                          _buildActionButton(
                            icon: _isGeneratingPdf ? null : Icons.description,
                            label: 'Wäschereischein',
                            onPressed: _isGeneratingPdf ? null : _regenerateCleaningReceipt,
                            color: Colors.orange,
                            isLoading: _isGeneratingPdf,
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Ausrüstungsliste
              if (_equipmentList.isEmpty)
                Card(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Keine Ausrüstung registriert',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Verwenden Sie den "Kleidung erfassen" Button um Ausrüstung hinzuzufügen',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _equipmentList.length,
                  itemBuilder: (context, index) {
                    final equipment = _equipmentList[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: equipment.type == 'Jacke' ? Colors.blue : Colors.amber,
                          child: Icon(
                            equipment.type == 'Jacke'
                                ? Icons.accessibility_new
                                : Icons.airline_seat_legroom_normal,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          equipment.article,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Besitzer: ${equipment.owner} | Größe: ${equipment.size}'),
                            if (equipment.barcode != null && equipment.barcode!.isNotEmpty)
                              Text(
                                'Barcode: ${equipment.barcode}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: EquipmentStatus.getStatusColor(equipment.status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    EquipmentStatus.getStatusIcon(equipment.status),
                                    size: 14,
                                    color: EquipmentStatus.getStatusColor(equipment.status),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Status: ${equipment.status}',
                                    style: TextStyle(
                                      color: EquipmentStatus.getStatusColor(equipment.status),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EquipmentDetailScreen(
                                  equipment: equipment,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),

              // Einsatzinformationen
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          const Text(
                            'Einsatzinformationen',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Erstellt von:', _mission!.createdBy),
                      _buildInfoRow(
                        'Erstellt am:',
                        DateFormat('dd.MM.yyyy HH:mm').format(_mission!.createdAt),
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

  // Hilfsmethoden für UI-Komponenten
  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData? icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    bool isLoading = false,
  }) {
    return SizedBox(
      height: 36,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
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

  // Ausrüstungszählung
  EquipmentCounts _countEquipmentTypes(List<EquipmentModel> equipmentList) {
    int jacketCount = 0;
    int pantsCount = 0;
    int otherCount = 0;

    for (var item in equipmentList) {
      switch (item.type.toLowerCase()) {
        case 'jacke':
          jacketCount++;
          break;
        case 'hose':
          pantsCount++;
          break;
        default:
          otherCount++;
          break;
      }
    }

    return EquipmentCounts(
      jackets: jacketCount,
      pants: pantsCount,
      other: otherCount,
    );
  }
}

// Hilfsklassen
class EquipmentCounts {
  final int jackets;
  final int pants;
  final int other;

  const EquipmentCounts({
    required this.jackets,
    required this.pants,
    required this.other,
  });

  int get total => jackets + pants + other;
}