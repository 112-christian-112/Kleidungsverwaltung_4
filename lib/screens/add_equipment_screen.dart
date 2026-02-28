// screens/admin/equipment/add_equipment_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import '../../../services/equipment_service.dart';
import '../../../services/equipment_inspection_service.dart';
import '../../../services/barcode_service.dart';
import '../../../services/permission_service.dart';
import 'admin/equipment/barcode_scanner_screen.dart';
import 'admin/equipment/nfc_scanner_screen.dart';


class AddEquipmentScreen extends StatefulWidget {
  const AddEquipmentScreen({Key? key}) : super(key: key);

  @override
  State<AddEquipmentScreen> createState() => _AddEquipmentScreenState();
}

class _AddEquipmentScreenState extends State<AddEquipmentScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final EquipmentService _equipmentService = EquipmentService();
  final EquipmentInspectionService _inspectionService = EquipmentInspectionService();
  final PermissionService _permissionService = PermissionService();

  // Controllers
  final TextEditingController _nfcTagController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _checkDateController = TextEditingController();

  // State variables
  String _nfcTag = '';
  String _barcode = '';
  String _article = 'Viking Performer Evolution Einsatzjacke AGT';
  String _type = 'Jacke';
  String _fireStation = 'Esklum';
  String _status = EquipmentStatus.ready;
  String _userFireStation = '';

  bool _isLoading = false;
  bool _isAdmin = false;
  DateTime _selectedCheckDate = DateTime.now().add(const Duration(days: 365)); // Ein Jahr in die Zukunft

  // Animation controllers
  late AnimationController _nfcAnimationController;
  late AnimationController _barcodeAnimationController;
  late Animation<double> _nfcAnimation;
  late Animation<double> _barcodeAnimation;

  // Predefined values
  final List<String> _articles = [
    'Viking Performer Evolution Einsatzjacke AGT',
    'Viking Performer Evolution Einsatzhose AGT',
    'Viking Einsatzhose TH Assistance',
    'Viking Einsatzjacke TH Assistance'
  ];

  final List<String> _types = ['Jacke', 'Hose'];

  final List<String> _fireStations = [
    'Esklum',
    'Breinermoor',
    'Grotegaste',
    'Flachsmeer',
    'Folmhusen',
    'Großwolde',
    'Ihrhove',
    'Ihren'
    'Steenfelde',
    'Völlen',
    'Völlenerfehn',
    'Völlenerkönigsfehn'
  ];

  final List<String> _commonSizes = [
    'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL',
    '36', '38', '40', '42', '44', '46', '48', '50', '52', '54', '56'
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadUserData();
    // Standardmäßig Prüfdatum auf ein Jahr von heute setzen
    final futureDate = DateTime.now().add(const Duration(days: 365));
    _selectedCheckDate = futureDate;
    _checkDateController.text = DateFormat('dd.MM.yyyy').format(futureDate);
  }

  void _initializeAnimations() {
    _nfcAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _barcodeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _nfcAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _nfcAnimationController, curve: Curves.elasticOut),
    );
    _barcodeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _barcodeAnimationController, curve: Curves.elasticOut),
    );
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAdmin = await _permissionService.isAdmin();
      final userFireStation = await _permissionService.getUserFireStation();

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _userFireStation = userFireStation;
          _fireStation = userFireStation; // Standardwert auf Benutzer-Feuerwehr setzen
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden der Benutzerdaten: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createInitialInspection(String equipmentId, String inspectorName) async {
    try {
      // Prüfung für heute mit "bestanden" und Kommentar "Neuer Artikel"
      final inspection = EquipmentInspectionModel(
        id: '', // Wird von Firestore generiert
        equipmentId: equipmentId, // Korrekte Equipment-ID verwenden
        inspectionDate: DateTime.now(), // Heutiges Datum
        inspector: inspectorName,
        result: InspectionResult.passed, // Bestanden
        comments: 'Neuer Artikel - Erstprüfung bei Anlage',
        nextInspectionDate: _selectedCheckDate, // Das gewählte Prüfdatum (ein Jahr später)
        issues: null, // Keine Mängel bei neuem Artikel
        createdAt: DateTime.now(),
        createdBy: inspectorName,
      );

      await _inspectionService.addInspection(inspection);
    } catch (e) {
      print('Fehler beim Erstellen der automatischen Prüfung: $e');
      // Fehler nicht weiterwerfen, da die Hauptfunktion (Equipment anlegen) erfolgreich war
    }
  }

  @override
  void dispose() {
    _nfcTagController.dispose();
    _barcodeController.dispose();
    _sizeController.dispose();
    _ownerController.dispose();
    _checkDateController.dispose();
    _nfcAnimationController.dispose();
    _barcodeAnimationController.dispose();
    super.dispose();
  }

  Future<void> _scanNfcTag() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NfcScannerScreen(),
      ),
    );

    if (result != null && result is String) {
      setState(() {
        _nfcTag = result;
        _nfcTagController.text = result;
      });
      _nfcAnimationController.forward().then((_) {
        _nfcAnimationController.reset();
      });

      // Vibration feedback
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const BarcodeScannerScreen(),
        ),
      );

      if (result != null && result is String && result.isNotEmpty) {
        setState(() {
          _barcode = result;
          _barcodeController.text = result;
        });
        _barcodeAnimationController.forward().then((_) {
          _barcodeAnimationController.reset();
        });

        // Vibration feedback
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Fehler beim Barcode-Scan: $e');
      }
    }
  }

  void _generateOwnerFromNfc(String nfcTag) {
    // Einfache Logik zur Besitzer-Generierung basierend auf NFC-Tag
    // Dies kann je nach NFC-Tag-Schema angepasst werden
    if (nfcTag.length >= 4) {
      String prefix = nfcTag.substring(0, 2).toUpperCase();
      String suffix = nfcTag.substring(nfcTag.length - 2);
      setState(() {
        _ownerController.text = 'Benutzer-$prefix$suffix';
      });
    }
  }

  Future<void> _selectCheckDate() async {
    // Funktion nicht mehr benötigt, aber behalten für eventuelle zukünftige Verwendung
    return;
  }

  void _setTypeBasedOnArticle(String article) {
    setState(() {
      _article = article;

      // Automatische Typ-Erkennung
      if (article.toLowerCase().contains('jacke')) {
        _type = 'Jacke';
      } else if (article.toLowerCase().contains('hose')) {
        _type = 'Hose';
      }
    });
  }

  Future<void> _validateAndSave() async {
    // Erweiterte Validierung
    if (_nfcTag.isEmpty) {
      _showErrorSnackBar('Bitte scannen Sie einen NFC-Tag');
      return;
    }

    // Formular validieren (ohne NFC-Tag, da das bereits geprüft wurde)
    if (_formKey.currentState!.validate()) {
      await _saveEquipment();
    }
  }

  Future<void> _saveEquipment() async {
    setState(() {
      _isLoading = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Kein Benutzer angemeldet');
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Finalen NFC-Tag bestimmen
      String finalNfcTag = _nfcTag;

      // Finalen Artikel bestimmen
      String finalArticle = _article;

      EquipmentModel newEquipment = EquipmentModel(
        id: '',
        nfcTag: finalNfcTag,
        barcode: _barcode.isNotEmpty ? _barcode : (_barcodeController.text.isNotEmpty ? _barcodeController.text.trim() : null),
        article: finalArticle,
        type: _type,
        size: _sizeController.text.trim(),
        fireStation: _fireStation,
        owner: _ownerController.text.trim(),
        washCycles: 0,
        checkDate: _selectedCheckDate,
        createdAt: DateTime.now(),
        createdBy: userData['name'] ?? currentUser.email ?? '',
        status: _status,
      );

      // Equipment speichern und DocumentReference erhalten
      DocumentReference docRef = await _equipmentService.addEquipment(newEquipment);

      // Automatische Prüfung erstellen mit der korrekten Equipment-ID
      await _createInitialInspection(docRef.id, userData['name'] ?? currentUser.email ?? '');

      if (mounted) {
        _showSuccessSnackBar('Einsatzkleidung und Erstprüfung erfolgreich angelegt');
        _resetForm();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Fehler: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetForm() {
    setState(() {
      _nfcTag = '';
      _barcode = '';
      _article = _articles.first;
      _type = 'Jacke';
      _fireStation = _userFireStation.isNotEmpty ? _userFireStation : _fireStations.first;
      _status = EquipmentStatus.ready;
      _selectedCheckDate = DateTime.now().add(const Duration(days: 365)); // Ein Jahr in die Zukunft
    });

    _nfcTagController.clear();
    _barcodeController.clear();
    _sizeController.clear();
    _ownerController.clear();
    _checkDateController.text = DateFormat('dd.MM.yyyy').format(DateTime.now().add(const Duration(days: 365)));
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _userFireStation.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Einsatzkleidung anlegen')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatzkleidung anlegen'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(),
            tooltip: 'Hilfe',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildScanningSection(),
              const SizedBox(height: 24),
              _buildArticleSection(),
              const SizedBox(height: 24),
              _buildAssignmentSection(),
              const SizedBox(height: 24),
              _buildInspectionSection(),
              const SizedBox(height: 24),
              _buildStatusSection(),
              const SizedBox(height: 32),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanningSection() {
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
                Icon(Icons.qr_code_scanner, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Identifikation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // NFC-Tag Sektion
            AnimatedBuilder(
              animation: _nfcAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_nfcAnimation.value * 0.05),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _nfcTag.isNotEmpty
                          ? Colors.green.withOpacity(0.1)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _nfcTag.isNotEmpty ? Colors.green : Colors.grey.shade300,
                        width: _nfcTag.isNotEmpty ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.nfc,
                              color: _nfcTag.isNotEmpty ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'NFC-Tag (erforderlich)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _nfcTag.isNotEmpty ? Colors.green : null,
                              ),
                            ),
                            const Spacer(),
                            if (_nfcTag.isNotEmpty)
                              const Icon(Icons.check_circle, color: Colors.green),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Hinweis für neuen Artikel
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.blue,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Bei neuen Artikeln wird automatisch eine bestandene Erstprüfung mit dem Kommentar "Neuer Artikel" erstellt.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _nfcTagController,
                                readOnly: true, // Nur-Lese-Modus
                                decoration: InputDecoration(
                                  hintText: _nfcTag.isNotEmpty ? _nfcTag : 'NFC-Tag scannen',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  filled: true,
                                  fillColor: Colors.grey.shade100, // Grauer Hintergrund für Read-Only
                                ),
                                validator: (value) {
                                  if (_nfcTag.isEmpty) {
                                    return 'NFC-Tag ist erforderlich';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _scanNfcTag,
                              icon: const Icon(Icons.nfc),
                              label: const Text('Scannen'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Barcode Sektion
            AnimatedBuilder(
              animation: _barcodeAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_barcodeAnimation.value * 0.05),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _barcode.isNotEmpty
                          ? Colors.blue.withOpacity(0.1)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _barcode.isNotEmpty ? Colors.blue : Colors.grey.shade300,
                        width: _barcode.isNotEmpty ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.qr_code,
                              color: _barcode.isNotEmpty ? Colors.blue : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Barcode (optional)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _barcode.isNotEmpty ? Colors.blue : null,
                              ),
                            ),
                            const Spacer(),
                            if (_barcode.isNotEmpty)
                              const Icon(Icons.check_circle, color: Colors.blue),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _barcodeController,
                                decoration: InputDecoration(
                                  hintText: _barcode.isNotEmpty ? _barcode : 'Barcode scannen oder manuell eingeben',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  suffixIcon: _barcodeController.text.isNotEmpty
                                      ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        _barcodeController.clear();
                                        _barcode = '';
                                      });
                                    },
                                  )
                                      : null,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _barcode = value;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _scanBarcode,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Scannen'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArticleSection() {
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
                Icon(Icons.inventory_2, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Artikelinformationen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Artikel Dropdown
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Artikel',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.category),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
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

            // Typ und Größe in einer Reihe
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.style,
                              color: Theme.of(context).colorScheme.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Typ',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.auto_awesome,
                              color: Theme.of(context).colorScheme.primary,
                              size: 14,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _type,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Automatisch bestimmt',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _sizeController,
                    decoration: InputDecoration(
                      labelText: 'Größe',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.format_size),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Größe erforderlich';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),

            // Größen-Chips
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _commonSizes.map((size) {
                return ActionChip(
                  label: Text(size),
                  onPressed: () {
                    setState(() {
                      _sizeController.text = size;
                    });
                  },
                  backgroundColor: _sizeController.text == size
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                      : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentSection() {
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
                Icon(Icons.assignment_ind, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Zuordnung',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Ortsfeuerwehr (nur für Admins editierbar)
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Ortsfeuerwehr',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.location_city),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              value: _fireStation,
              items: _fireStations.map((String station) {
                return DropdownMenuItem<String>(
                  value: station,
                  child: Text(station),
                );
              }).toList(),
              onChanged: _isAdmin ? (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _fireStation = newValue;
                  });
                }
              } : null,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte wählen Sie eine Ortsfeuerwehr aus';
                }
                return null;
              },
            ),

            if (!_isAdmin) ...[
              const SizedBox(height: 8),
              Text(
                'Hinweis: Als Nicht-Administrator können Sie nur Ausrüstung für Ihre eigene Feuerwehr anlegen.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.secondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Besitzer
            TextFormField(
              controller: _ownerController,
              decoration: InputDecoration(
                labelText: 'Besitzer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.person),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
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
    );
  }

  Widget _buildInspectionSection() {
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
                Icon(Icons.fact_check, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Prüfinformationen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Prüfdatum - Elegante Info-Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.event,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Nächstes Prüfdatum',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Auto',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('dd.MM.yyyy').format(_selectedCheckDate),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Automatisch auf 1 Jahr ab heute gesetzt',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
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
                Icon(Icons.flag, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Status als Chips-Auswahl
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: EquipmentStatus.values.map((status) {
                final isSelected = _status == status;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _status = status;
                    });
                    HapticFeedback.selectionClick();
                  },
                  borderRadius: BorderRadius.circular(25),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? EquipmentStatus.getStatusColor(status).withOpacity(0.2)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: isSelected
                            ? EquipmentStatus.getStatusColor(status)
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          EquipmentStatus.getStatusIcon(status),
                          color: isSelected
                              ? EquipmentStatus.getStatusColor(status)
                              : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status,
                          style: TextStyle(
                            color: isSelected
                                ? EquipmentStatus.getStatusColor(status)
                                : Colors.grey.shade700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_circle,
                            color: EquipmentStatus.getStatusColor(status),
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // Status-Erklärung
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EquipmentStatus.getStatusColor(_status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: EquipmentStatus.getStatusColor(_status).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: EquipmentStatus.getStatusColor(_status),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getStatusDescription(_status),
                      style: TextStyle(
                        fontSize: 12,
                        color: EquipmentStatus.getStatusColor(_status),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusDescription(String status) {
    switch (status) {
      case EquipmentStatus.ready:
        return 'Die Ausrüstung ist einsatzbereit und kann verwendet werden.';
      case EquipmentStatus.cleaning:
        return 'Die Ausrüstung befindet sich in der Reinigung und ist temporär nicht verfügbar.';
      case EquipmentStatus.repair:
        return 'Die Ausrüstung ist defekt und muss repariert werden.';
      case EquipmentStatus.retired:
        return 'Die Ausrüstung ist ausgemustert und darf nicht mehr verwendet werden.';
      default:
        return 'Unbekannter Status.';
    }
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _validateAndSave,
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
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.save, size: 24),
            SizedBox(width: 12),
            Text(
              'Einsatzkleidung anlegen',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Hilfe'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpItem(
                'NFC-Tag scannen',
                'Halten Sie Ihr Gerät an den NFC-Tag. Der Tag wird automatisch erkannt und kann nicht manuell geändert werden.',
                Icons.nfc,
              ),
              const SizedBox(height: 16),
              _buildHelpItem(
                'Barcode scannen',
                'Richten Sie die Kamera auf den Barcode. Der Code wird automatisch erkannt.',
                Icons.qr_code_scanner,
              ),
              const SizedBox(height: 16),
              _buildHelpItem(
                'Prüfdatum',
                'Das nächste Prüfdatum wird automatisch auf 1 Jahr ab heute gesetzt. Bei Anlage wird eine bestandene Erstprüfung erstellt.',
                Icons.event,
              ),
              const SizedBox(height: 16),
              _buildHelpItem(
                'Automatische Prüfung',
                'Beim Anlegen wird automatisch eine bestandene Prüfung mit "Neuer Artikel" als Kommentar erstellt.',
                Icons.verified,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String title, String description, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.blue, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
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
}