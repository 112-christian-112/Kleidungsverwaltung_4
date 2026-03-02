// screens/equipment_scan_screen.dart
import 'package:flutter/material.dart';
import '../../../models/equipment_model.dart';
import '../../../services/equipment_service.dart';
import 'barcode_scanner_screen.dart';
import 'equipment_detail_screen.dart';
import 'equipment_inspection_form_screen.dart';
import 'nfc_scanner_screen.dart';

class EquipmentScanScreen extends StatefulWidget {
  const EquipmentScanScreen({Key? key}) : super(key: key);

  @override
  State<EquipmentScanScreen> createState() => _EquipmentScanScreenState();
}

class _EquipmentScanScreenState extends State<EquipmentScanScreen> {
  final EquipmentService _equipmentService = EquipmentService();
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  EquipmentModel? _foundEquipment;
  List<EquipmentModel> _searchResults = [];
  String _errorMessage = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // NFC-Tag scannen
  Future<void> _scanNfcTag() async {
    setState(() {
      _isLoading = true;
      _foundEquipment = null;
      _searchResults = [];
      _errorMessage = '';
    });

    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const NfcScannerScreen(),
        ),
      );

      if (result != null && result is String) {
        await _searchByNfcTag(result);
      } else {
        setState(() {
          _errorMessage = 'Scan wurde abgebrochen';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Scannen: $e';
        _isLoading = false;
      });
    }
  }

  // Barcode scannen
  Future<void> _scanBarcode() async {
    setState(() {
      _isLoading = true;
      _foundEquipment = null;
      _searchResults = [];
      _errorMessage = '';
    });

    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const BarcodeScannerScreen(),
        ),
      );

      if (result != null && result is String) {
        await _searchByBarcode(result);
      } else {
        setState(() {
          _errorMessage = 'Scan wurde abgebrochen';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Scannen: $e';
        _isLoading = false;
      });
    }
  }

  // Nach NFC-Tag suchen
  Future<void> _searchByNfcTag(String nfcTag) async {
    setState(() {
      _isLoading = true;
      _foundEquipment = null;
      _searchResults = [];
      _errorMessage = '';
    });

    try {
      final equipment = await _equipmentService.getEquipmentByNfcTag(nfcTag);

      setState(() {
        _isLoading = false;

        if (equipment != null) {
          _foundEquipment = equipment;
        } else {
          _searchByPartialMatch(nfcTag);
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Fehler bei der Suche: $e';
      });
    }
  }

  // Nach Barcode suchen
  Future<void> _searchByBarcode(String barcode) async {
    setState(() {
      _isLoading = true;
      _foundEquipment = null;
      _searchResults = [];
      _errorMessage = '';
    });

    try {
      final equipment = await _equipmentService.getEquipmentByBarcode(barcode);

      setState(() {
        _isLoading = false;

        if (equipment != null) {
          _foundEquipment = equipment;
        } else {
          _searchByPartialMatch(barcode);
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Fehler bei der Suche: $e';
      });
    }
  }

  // Nach Teilübereinstimmungen suchen
  Future<void> _searchByPartialMatch(String searchString) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _equipmentService
          .searchEquipmentByPartialTagOrBarcode(searchString);

      setState(() {
        _isLoading = false;

        if (results.isNotEmpty) {
          if (results.length == 1) {
            _foundEquipment = results.first;
          } else {
            _searchResults = results;
          }
        } else {
          _errorMessage = 'Keine Einsatzkleidung mit diesem Code gefunden';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Fehler bei der Suche nach Teilübereinstimmungen: $e';
      });
    }
  }

  // Manuelle Suche nach NFC-Tag/Barcode
  Future<void> _search() async {
    if (_searchQuery.isEmpty) {
      setState(() {
        _errorMessage = 'Bitte geben Sie einen NFC-Tag oder Barcode ein';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _foundEquipment = null;
      _searchResults = [];
      _errorMessage = '';
    });

    try {
      var equipment =
          await _equipmentService.getEquipmentByNfcTag(_searchQuery);

      if (equipment == null) {
        equipment = await _equipmentService.getEquipmentByBarcode(_searchQuery);
      }

      if (equipment != null) {
        setState(() {
          _isLoading = false;
          _foundEquipment = equipment;
        });
      } else {
        await _searchByPartialMatch(_searchQuery);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Fehler bei der Suche: $e';
      });
    }
  }

  // Zur Detailseite navigieren
  void _viewDetails() {
    if (_foundEquipment != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EquipmentDetailScreen(
            equipment: _foundEquipment!,
          ),
        ),
      );
    }
  }

  // Zur Prüfungsseite navigieren
  void _createInspection() {
    if (_foundEquipment != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EquipmentInspectionFormScreen(
            equipment: _foundEquipment!,
          ),
        ),
      ).then((value) {
        if (value == true && _foundEquipment != null) {
          if (_foundEquipment!.nfcTag.isNotEmpty) {
            _searchByNfcTag(_foundEquipment!.nfcTag);
          } else if (_foundEquipment!.barcode != null &&
              _foundEquipment!.barcode!.isNotEmpty) {
            _searchByBarcode(_foundEquipment!.barcode!);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausrüstung scannen'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Einführungstext
            const Text(
              'Ausrüstung identifizieren',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scannen Sie den NFC-Tag oder Barcode der Einsatzkleidung, um diese zu identifizieren und Aktionen durchzuführen.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Scan-Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _scanNfcTag,
                    icon: const Icon(Icons.nfc),
                    label: const Text('NFC-Tag scannen'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _scanBarcode,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Barcode scannen'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Manuelle Eingabe
            const Text(
              'Manuelle Eingabe',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'NFC-Tag oder Barcode',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _search,
                  child: const Text('Suchen'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Fehlermeldung
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),

            // Ladeindikator
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              ),

            // Mehrere Suchergebnisse anzeigen
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                '${_searchResults.length} Ergebnisse gefunden',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final equipment = _searchResults[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: equipment.type == 'Jacke'
                            ? Colors.blue.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        child: Icon(
                          equipment.type == 'Jacke'
                              ? Icons.accessibility_new
                              : Icons.airline_seat_legroom_normal,
                          color: equipment.type == 'Jacke'
                              ? Colors.blue
                              : Colors.orange,
                        ),
                      ),
                      title: Text(equipment.article),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Besitzer: ${equipment.owner}'),
                          Text('NFC: ${equipment.nfcTag}'),
                          if (equipment.barcode != null &&
                              equipment.barcode!.isNotEmpty)
                            Text('Barcode: ${equipment.barcode}'),
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          _foundEquipment = equipment;
                          _searchResults = [];
                        });
                      },
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ],

            // Gefundene Einsatzkleidung anzeigen
            if (_foundEquipment != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Gefundene Einsatzkleidung',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icon für Typ (Jacke/Hose)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _foundEquipment!.type == 'Jacke'
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _foundEquipment!.type == 'Jacke'
                                  ? Icons.accessibility_new
                                  : Icons.airline_seat_legroom_normal,
                              color: _foundEquipment!.type == 'Jacke'
                                  ? Colors.blue
                                  : Colors.orange,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Artikel-Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _foundEquipment!.article,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Größe: ${_foundEquipment!.size}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Weitere Details
                      _buildInfoRow(
                          context, 'Besitzer', _foundEquipment!.owner),
                      _buildInfoRow(
                          context, 'Feuerwehr', _foundEquipment!.fireStation),
                      _buildInfoRow(
                        context,
                        'Status',
                        _foundEquipment!.status,
                        iconData: EquipmentStatus.getStatusIcon(
                            _foundEquipment!.status),
                        iconColor: EquipmentStatus.getStatusColor(
                            _foundEquipment!.status),
                      ),
                      _buildInfoRow(
                        context,
                        'NFC-Tag',
                        _foundEquipment!.nfcTag,
                        iconData: Icons.nfc,
                      ),
                      if (_foundEquipment!.barcode != null &&
                          _foundEquipment!.barcode!.isNotEmpty)
                        _buildInfoRow(
                          context,
                          'Barcode',
                          _foundEquipment!.barcode!,
                          iconData: Icons.qr_code,
                        ),
                      const SizedBox(height: 16),

                      // FIX: Aktions-Buttons in Expanded wrappen,
                      // damit sie bei schmalem Display nicht überlaufen.
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
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    IconData? iconData,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: iconData != null
                ? Icon(
                    iconData,
                    size: 18,
                    color: iconColor ??
                        Theme.of(context).colorScheme.secondary,
                  )
                : const SizedBox.shrink(),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
