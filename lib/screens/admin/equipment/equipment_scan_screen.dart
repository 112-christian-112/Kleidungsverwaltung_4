// screens/admin/equipment/equipment_scan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/equipment_model.dart';
import '../../../services/equipment_service.dart';
import '../../../widgets/nfc_scan_sheet.dart';
import 'barcode_scanner_screen.dart';
import 'equipment_detail_screen.dart';
import 'equipment_inspection_form_screen.dart';
import 'prueftag_screen.dart';

class EquipmentScanScreen extends StatefulWidget {
  const EquipmentScanScreen({Key? key}) : super(key: key);

  @override
  State<EquipmentScanScreen> createState() => _EquipmentScanScreenState();
}

class _EquipmentScanScreenState extends State<EquipmentScanScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String _searchQuery = '';
  EquipmentModel? _foundEquipment;
  List<EquipmentModel> _searchResults = [];
  String _errorMessage = '';
  EquipmentModel? _lastInspected;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _prueftagStarten() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrueftagScreen()),
    );
  }

  // ── Scan ─────────────────────────────────────────────────────────────────

  Future<void> _scanNfcTag() async {
    _resetScanState();
    final tagId = await NfcScanSheet.zeigen(
      context,
      hinweisText: 'NFC-Tag der Einsatzkleidung scannen',
    );
    if (tagId != null && tagId.isNotEmpty) {
      await _searchByNfcTag(tagId);
    } else {
      setState(() { _isLoading = false; _errorMessage = 'Scan wurde abgebrochen'; });
    }
  }

  Future<void> _scanBarcode() async {
    _resetScanState();
    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
      );
      if (result != null && result.isNotEmpty) {
        await _searchByBarcode(result);
      } else {
        setState(() { _isLoading = false; _errorMessage = 'Scan wurde abgebrochen'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'Fehler: $e'; });
    }
  }

  void _resetScanState() {
    setState(() {
      _isLoading = true;
      _foundEquipment = null;
      _searchResults = [];
      _errorMessage = '';
    });
  }

  // ── Suche ─────────────────────────────────────────────────────────────────

  Future<void> _searchByNfcTag(String nfcTag) async {
    setState(() => _isLoading = true);
    try {
      final e = await _equipmentService.getEquipmentByNfcTag(nfcTag);
      if (e != null) {
        setState(() { _isLoading = false; _foundEquipment = e; });
      } else {
        await _searchByPartialMatch(nfcTag);
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'Fehler: $e'; });
    }
  }

  Future<void> _searchByBarcode(String barcode) async {
    setState(() => _isLoading = true);
    try {
      final e = await _equipmentService.getEquipmentByBarcode(barcode);
      if (e != null) {
        setState(() { _isLoading = false; _foundEquipment = e; });
      } else {
        await _searchByPartialMatch(barcode);
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'Fehler: $e'; });
    }
  }

  Future<void> _search() async {
    if (_searchQuery.isEmpty) {
      setState(() => _errorMessage = 'Bitte NFC-Tag oder Barcode eingeben');
      return;
    }
    setState(() { _isLoading = true; _foundEquipment = null; _searchResults = []; _errorMessage = ''; });
    try {
      var e = await _equipmentService.getEquipmentByNfcTag(_searchQuery);
      e ??= await _equipmentService.getEquipmentByBarcode(_searchQuery);
      if (e != null) {
        setState(() { _isLoading = false; _foundEquipment = e; });
      } else {
        await _searchByPartialMatch(_searchQuery);
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'Fehler: $e'; });
    }
  }

  Future<void> _searchByPartialMatch(String query) async {
    try {
      final results = await _equipmentService.searchEquipmentByPartialTagOrBarcode(query);
      setState(() {
        _isLoading = false;
        if (results.length == 1) {
          _foundEquipment = results.first;
        } else if (results.isNotEmpty) {
          _searchResults = results;
        } else {
          _errorMessage = 'Keine Einsatzkleidung mit diesem Code gefunden';
        }
      });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'Fehler: $e'; });
    }
  }

  Future<void> _createInspection() async {
    if (_foundEquipment == null) return;
    final equipment = _foundEquipment!;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => EquipmentInspectionFormScreen(equipment: equipment)),
    );
    if (!mounted) return;
    if (result == true) {
      HapticFeedback.lightImpact();
      setState(() {
        _lastInspected = equipment;
        _foundEquipment = null;
        _errorMessage = '';
        _searchController.clear();
        _searchQuery = '';
      });
    }
  }

  void _viewDetails() {
    if (_foundEquipment == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => EquipmentDetailScreen(equipment: _foundEquipment!)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausrüstung scannen'),
        actions: [
          Tooltip(
            message: 'Prüftag-Modus starten',
            child: IconButton(
              icon: const Icon(Icons.playlist_add_check),
              onPressed: _prueftagStarten,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Bestätigung letzte Prüfung ─────────────────────────
                  if (_lastInspected != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Prüfung gespeichert: ${_lastInspected!.article} · ${_lastInspected!.owner}',
                              style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Prüftag-Hinweis ────────────────────────────────────
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.playlist_add_check,
                            color: Colors.indigo.shade600, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mehrere Kleidungsstücke prüfen?',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade700,
                                    fontSize: 13),
                              ),
                              Text(
                                'Prüftag-Modus für automatischen Scan-Loop mit Übersicht.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.indigo.shade500),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _prueftagStarten,
                          child: const Text('Starten'),
                        ),
                      ],
                    ),
                  ),

                  // ── Scan-Buttons ───────────────────────────────────────
                  Text(
                    'Einzelscan',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _scanNfcTag,
                          icon: const Icon(Icons.nfc),
                          label: const Text('NFC-Tag'),
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _scanBarcode,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Barcode'),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Manuelle Eingabe ───────────────────────────────────
                  const SizedBox(height: 20),
                  Text(
                    'Manuelle Eingabe',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'NFC-Tag oder Barcode...',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setState(() => _searchQuery = v),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                          onPressed: _search,
                          child: const Text('Suchen')),
                    ],
                  ),

                  // ── Fehlermeldung ──────────────────────────────────────
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMessage,
                                style: TextStyle(
                                    color: Colors.red.shade700)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Mehrere Treffer ────────────────────────────────────
                  if (_searchResults.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('${_searchResults.length} Treffer:',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._searchResults.map((e) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: e.type == 'Jacke'
                                  ? Colors.blue.shade100
                                  : Colors.orange.shade100,
                              child: Icon(
                                e.type == 'Jacke'
                                    ? Icons.accessibility_new
                                    : Icons.airline_seat_legroom_normal,
                                color: e.type == 'Jacke'
                                    ? Colors.blue
                                    : Colors.orange,
                              ),
                            ),
                            title: Text(e.article,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${e.owner} · ${e.fireStation} · Gr. ${e.size}'),
                            trailing: Icon(
                              EquipmentStatus.getStatusIcon(e.status),
                              color: EquipmentStatus.getStatusColor(
                                  e.status),
                            ),
                            onTap: () =>
                                setState(() => _foundEquipment = e),
                          ),
                        )),
                  ],

                  // ── Gefundenes Equipment ───────────────────────────────
                  if (_foundEquipment != null) ...[
                    const SizedBox(height: 20),
                    _buildEquipmentCard(_foundEquipment!),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Equipment Card ────────────────────────────────────────────────────────

  Widget _buildEquipmentCard(EquipmentModel equipment) {
    final statusColor = EquipmentStatus.getStatusColor(equipment.status);
    final statusIcon = EquipmentStatus.getStatusIcon(equipment.status);
    return Card(
      elevation: 3,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: equipment.type == 'Jacke'
                      ? Colors.blue.shade100
                      : Colors.orange.shade100,
                  radius: 24,
                  child: Icon(
                    equipment.type == 'Jacke'
                        ? Icons.accessibility_new
                        : Icons.airline_seat_legroom_normal,
                    color: equipment.type == 'Jacke'
                        ? Colors.blue
                        : Colors.orange,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(equipment.article,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text('Gr. ${equipment.size}',
                          style: TextStyle(
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(equipment.status,
                          style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _infoRow('Besitzer', equipment.owner),
            _infoRow('Ortsfeuerwehr', equipment.fireStation),
            _infoRow('NFC-Tag', equipment.nfcTag, icon: Icons.nfc),
            if (equipment.barcode?.isNotEmpty == true)
              _infoRow('Barcode', equipment.barcode!,
                  icon: Icons.qr_code),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _viewDetails,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Details'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _createInspection,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Prüfung durchführen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.primary,
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimary,
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

  Widget _infoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: icon != null
                ? Icon(icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary)
                : null,
          ),
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
