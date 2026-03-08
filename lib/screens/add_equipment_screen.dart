// screens/add_equipment_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/equipment_model.dart';
import '../models/equipment_inspection_model.dart';
import '../services/equipment_service.dart';
import '../services/equipment_inspection_service.dart';
import '../services/permission_service.dart';
import '../Lists/fire_stations.dart';
import '../Lists/equipment_data.dart';
import 'admin/equipment/barcode_scanner_screen.dart';
import 'admin/equipment/nfc_scanner_screen.dart';
import 'admin/equipment/equipment_detail_screen.dart';
import '../widgets/nfc_scan_sheet.dart';

class AddEquipmentScreen extends StatefulWidget {
  const AddEquipmentScreen({Key? key}) : super(key: key);

  @override
  State<AddEquipmentScreen> createState() => _AddEquipmentScreenState();
}

class _AddEquipmentScreenState extends State<AddEquipmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final EquipmentService _equipmentService = EquipmentService();
  final EquipmentInspectionService _inspectionService =
      EquipmentInspectionService();
  final PermissionService _permissionService = PermissionService();

  // Controllers
  final TextEditingController _sizeController    = TextEditingController();
  final TextEditingController _ownerController   = TextEditingController();
  final TextEditingController _articleSearchController = TextEditingController();

  // State
  String _nfcTag      = '';
  String _barcode     = '';
  String _article     = '';
  String _type        = 'Jacke';
  String _fireStation = FireStations.all.first;
  String _status      = EquipmentStatus.ready;
  bool   _isLoading   = false;
  bool   _isAdmin     = false;
  bool   _articleSearchOpen = false;
  DateTime _checkDate = DateTime.now().add(const Duration(days: 365));

  // Artikel-Suche — Daten kommen aus EquipmentData
  List<Map<String, String>> get _filteredArticles =>
      EquipmentData.search(_articleSearchController.text);

  // Größen-Suche
  final TextEditingController _sizeSearchController = TextEditingController();
  bool _sizePickerOpen = false;
  List<String> get _filteredSizes =>
      EquipmentData.searchSizes(_sizeSearchController.text);

  @override
  void initState() {
    super.initState();
    _loadUser();
    _articleSearchController.addListener(() => setState(() {}));
    _sizeSearchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sizeController.dispose();
    _ownerController.dispose();
    _articleSearchController.dispose();
    _sizeSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final user = await _permissionService.getCurrentUser();
      if (mounted && user != null) {
        setState(() {
          _isAdmin      = user.isAdmin;
          _fireStation  = user.fireStation.isNotEmpty
              ? user.fireStation
              : FireStations.all.first;
          _isLoading    = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── NFC / Barcode ─────────────────────────────────────────────────────────

  Future<void> _scanNfc() async {
    // Modernes BottomSheet statt eigenem Screen
    final tagId = await NfcScanSheet.zeigen(
      context,
      hinweisText: 'NFC-Tag an die Rückseite des Geräts halten',
    );
    if (tagId == null || tagId.isEmpty || !mounted) return;

    // Duplikat-Prüfung in Firestore
    setState(() => _isLoading = true);
    try {
      final existing = await _equipmentService.getEquipmentByNfcTag(tagId);
      if (!mounted) return;

      if (existing != null) {
        // Tag bereits vergeben → Dialog anzeigen
        setState(() => _isLoading = false);
        await _showDuplicateDialog(existing, tagId);
      } else {
        // Tag frei → übernehmen
        setState(() {
          _nfcTag  = tagId;
          _isLoading = false;
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Fehler bei Duplikat-Prüfung: $e', isError: true);
      }
    }
  }

  Future<void> _showDuplicateDialog(
      EquipmentModel existing, String tagId) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.orange, size: 36),
        title: const Text('NFC-Tag bereits vergeben'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dieser Tag ist bereits der folgenden Kleidung zugewiesen:',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing.article,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${existing.owner} · Gr. ${existing.size}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                  Text(existing.fireStation,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Erneut scannen'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      EquipmentDetailScreen(equipment: existing),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Artikel öffnen'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _barcode = result);
      HapticFeedback.lightImpact();
    }
  }

  // ── Speichern ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_nfcTag.isEmpty) {
      _snack('Bitte NFC-Tag scannen', isError: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) throw Exception('Nicht angemeldet');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final userName =
          (userDoc.data() as Map<String, dynamic>?)?['name'] ?? authUser.email ?? '';

      final equipment = EquipmentModel(
        id:          '',
        nfcTag:      _nfcTag,
        barcode:     _barcode.isNotEmpty ? _barcode : null,
        article:     _article,
        type:        _type,
        size:        _sizeController.text.trim(),
        fireStation: _fireStation,
        owner:       _ownerController.text.trim(),
        washCycles:  0,
        checkDate:   _checkDate,
        createdAt:   DateTime.now(),
        createdBy:   userName,
        status:      _status,
      );

      final ref = await _equipmentService.addEquipment(equipment);

      // Erstprüfung anlegen
      await _inspectionService.addInspection(EquipmentInspectionModel(
        id:                  '',
        equipmentId:         ref.id,
        inspectionDate:      DateTime.now(),
        inspector:           userName,
        result:              InspectionResult.passed,
        comments:            'Neuer Artikel – Erstprüfung bei Anlage',
        nextInspectionDate:  _checkDate,
        issues:              null,
        createdAt:           DateTime.now(),
        createdBy:           userName,
      ));

      if (mounted) {
        _snack('Einsatzkleidung erfolgreich angelegt');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack('Fehler: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _fireStation.isEmpty) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einsatzkleidung anlegen'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionCard(
                icon: Icons.nfc,
                title: 'Identifikation',
                isDark: isDark,
                cs: cs,
                child: Column(
                  children: [
                    // NFC
                    _scanTile(
                      label: 'NFC-Tag',
                      value: _nfcTag,
                      icon: Icons.nfc,
                      required: true,
                      onScan: _scanNfc,
                      onClear: () => setState(() => _nfcTag = ''),
                      isDark: isDark,
                      cs: cs,
                    ),
                    const SizedBox(height: 10),
                    // Barcode
                    _scanTile(
                      label: 'Barcode (optional)',
                      value: _barcode,
                      icon: Icons.qr_code,
                      required: false,
                      onScan: _scanBarcode,
                      onClear: () => setState(() => _barcode = ''),
                      isDark: isDark,
                      cs: cs,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _sectionCard(
                icon: Icons.inventory_2_outlined,
                title: 'Artikel',
                isDark: isDark,
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Artikel-Suche / Auswahl
                    _buildArticlePicker(cs, isDark),
                    const SizedBox(height: 14),
                    // Typ (wird auto gesetzt, aber manuell änderbar)
                    _label('Typ'),
                    const SizedBox(height: 6),
                    Row(
                      children: ['Jacke', 'Hose'].map((t) {
                        final sel = _type == t;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: t == 'Jacke' ? 8 : 0),
                            child: GestureDetector(
                              onTap: () => setState(() => _type = t),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? cs.primaryContainer
                                      : (isDark
                                          ? cs.surfaceContainerHigh
                                          : Colors.grey.shade100),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                    color: sel
                                        ? cs.primary
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      t == 'Jacke'
                                          ? Icons.accessibility_new
                                          : Icons
                                              .airline_seat_legroom_normal,
                                      size: 18,
                                      color: sel
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(t,
                                        style: TextStyle(
                                          fontWeight: sel
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                          color: sel
                                              ? cs.primary
                                              : cs.onSurfaceVariant,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    // Größe
                    _label('Größe'),
                    const SizedBox(height: 6),
                    _buildSizePicker(cs, isDark),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _sectionCard(
                icon: Icons.person_outline,
                title: 'Zuweisung',
                isDark: isDark,
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ortswehr
                    _label('Ortswehr'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _fireStation,
                      decoration: _inputDeco(
                          'Ortswehr wählen',
                          Icons.local_fire_department_outlined,
                          cs),
                      isExpanded: true,
                      items: FireStations.all
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text(s)))
                          .toList(),
                      onChanged: _isAdmin
                          ? (v) =>
                              setState(() => _fireStation = v ?? _fireStation)
                          : null,
                    ),
                    if (!_isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Ortswehr wird automatisch auf deine eigene gesetzt.',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 14),
                    // Besitzer
                    _label('Besitzer'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _ownerController,
                      decoration: _inputDeco(
                          'Vor- und Nachname', Icons.person, cs),
                      textCapitalization:
                          TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Besitzer angeben'
                              : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _sectionCard(
                icon: Icons.fact_check_outlined,
                title: 'Prüfung & Status',
                isDark: isDark,
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Prüfdatum
                    _label('Nächstes Prüfdatum'),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickCheckDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? cs.surfaceContainerHigh
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.outlineVariant, width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                DateFormat('dd.MM.yyyy')
                                    .format(_checkDate),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              _checkDateHint(),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 13,
                            color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Erstprüfung wird automatisch heute angelegt.',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Status
                    _label('Anfangsstatus'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: EquipmentStatus.values.map((s) {
                        final sel = _status == s;
                        final color =
                            EquipmentStatus.getStatusColor(s);
                        return GestureDetector(
                          onTap: () => setState(() => _status = s),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? color.withOpacity(
                                      isDark ? 0.25 : 0.12)
                                  : (isDark
                                      ? cs.surfaceContainerHigh
                                      : Colors.grey.shade100),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                color: sel
                                    ? color
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    EquipmentStatus.getStatusIcon(
                                        s),
                                    size: 15,
                                    color: sel
                                        ? color
                                        : cs.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(s,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: sel
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: sel
                                          ? color
                                          : cs.onSurfaceVariant,
                                    )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Speichern-Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_outlined, size: 20),
                            SizedBox(width: 10),
                            Text('Einsatzkleidung anlegen',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
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


  // ── Größen-Picker ─────────────────────────────────────────────────────────

  Widget _buildSizePicker(ColorScheme cs, bool isDark) {
    final hasValue = _sizeController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ausgewählte Größe oder Suchfeld
        if (!_sizePickerOpen && hasValue)
          _selectedSizeTile(cs, isDark)
        else
          _sizeSearchField(cs, isDark),

        // Ergebnisliste (nur wenn Picker offen)
        if (_sizePickerOpen) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainer : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: _filteredSizes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Größe nicht in der Liste?',
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _sizeController.text =
                                    _sizeSearchController.text.trim();
                                _sizePickerOpen = false;
                                _sizeSearchController.clear();
                              });
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: Text(
                                '"${_sizeSearchController.text.trim()}" übernehmen'),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredSizes.length,
                    itemBuilder: (context, i) {
                      final size = _filteredSizes[i];
                      final parts = size.split(' ');
                      final base   = parts[0];
                      final suffix = parts.length > 1 ? parts[1] : '';
                      final isLast = i == _filteredSizes.length - 1;

                      return Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _sizeController.text = size;
                                _sizePickerOpen = false;
                                _sizeSearchController.clear();
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 11),
                              child: Row(
                                children: [
                                  Text(base,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface,
                                          fontFamily: 'monospace')),
                                  if (suffix.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer,
                                        borderRadius:
                                            BorderRadius.circular(5),
                                      ),
                                      child: Text(suffix,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: cs.primary)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (!isLast)
                            Divider(
                                height: 1,
                                indent: 16,
                                color: cs.outlineVariant.withOpacity(0.35)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _selectedSizeTile(ColorScheme cs, bool isDark) {
    final parts  = _sizeController.text.split(' ');
    final base   = parts[0];
    final suffix = parts.length > 1 ? parts[1] : '';

    return InkWell(
      onTap: () => setState(() => _sizePickerOpen = true),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHigh : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: cs.primary.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.straighten, size: 18),
            const SizedBox(width: 10),
            Text(base,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontFamily: 'monospace')),
            if (suffix.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(suffix,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ),
            ],
            const Spacer(),
            Icon(Icons.edit_outlined,
                size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _sizeSearchField(ColorScheme cs, bool isDark) {
    return FormField<String>(
      validator: (_) => EquipmentData.validateSize(_sizeController.text),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _sizeSearchController,
            autofocus: _sizePickerOpen,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              hintText: 'Größe suchen, z.B. 54 oder K…',
              prefixIcon: const Icon(Icons.straighten, size: 20),
              suffixIcon: _sizeSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _sizeSearchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              errorText: state.errorText,
              filled: true,
              fillColor: isDark
                  ? cs.surfaceContainerHigh
                  : Colors.grey.shade50,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: cs.primary, width: 2)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            onTap: () => setState(() => _sizePickerOpen = true),
          ),
        ],
      ),
    );
  }

  // ── Artikel-Picker ────────────────────────────────────────────────────────

  Widget _buildArticlePicker(ColorScheme cs, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Artikel'),
        const SizedBox(height: 6),

        // Ausgewählter Artikel oder Suchfeld
        if (!_articleSearchOpen && _article.isNotEmpty)
          _selectedArticleTile(cs, isDark)
        else
          _articleSearchField(cs, isDark),

        // Ergebnisliste (nur wenn Suche offen)
        if (_articleSearchOpen) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainer : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
            ),
            child: _filteredArticles.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Kein Artikel gefunden',
                        style:
                            TextStyle(color: cs.onSurfaceVariant)),
                  )
                : Column(
                    children:
                        _filteredArticles.asMap().entries.map((e) {
                      final idx     = e.key;
                      final article = e.value;
                      final isLast  =
                          idx == _filteredArticles.length - 1;
                      return Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _article = article['name']!;
                                _type    = article['type']!;
                                _articleSearchOpen = false;
                                _articleSearchController.clear();
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: article['type'] ==
                                              'Jacke'
                                          ? (isDark
                                              ? const Color(
                                                  0xFF1A3A5C)
                                              : const Color(
                                                  0xFFDBEAFB))
                                          : (isDark
                                              ? const Color(
                                                  0xFF4D3000)
                                              : const Color(
                                                  0xFFFFF0CC)),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      article['type'] == 'Jacke'
                                          ? Icons.accessibility_new
                                          : Icons
                                              .airline_seat_legroom_normal,
                                      size: 16,
                                      color: article['type'] ==
                                              'Jacke'
                                          ? (isDark
                                              ? const Color(
                                                  0xFF90CAF9)
                                              : const Color(
                                                  0xFF1565C0))
                                          : (isDark
                                              ? const Color(
                                                  0xFFFFCC02)
                                              : const Color(
                                                  0xFFE65100)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(article['name']!,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w500)),
                                        Text(article['type']!,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: cs
                                                    .onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!isLast)
                            Divider(
                                height: 1,
                                indent: 58,
                                color: cs.outlineVariant
                                    .withOpacity(0.4)),
                        ],
                      );
                    }).toList(),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _selectedArticleTile(ColorScheme cs, bool isDark) {
    final isJacke = _type == 'Jacke';
    final iconBg  = isJacke
        ? (isDark ? const Color(0xFF1A3A5C) : const Color(0xFFDBEAFB))
        : (isDark ? const Color(0xFF4D3000) : const Color(0xFFFFF0CC));
    final iconFg  = isJacke
        ? (isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0))
        : (isDark ? const Color(0xFFFFCC02) : const Color(0xFFE65100));

    return InkWell(
      onTap: () => setState(() => _articleSearchOpen = true),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHigh : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.primary.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(
                isJacke
                    ? Icons.accessibility_new
                    : Icons.airline_seat_legroom_normal,
                color: iconFg,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_article,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  Text(_type,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.edit_outlined,
                size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _articleSearchField(ColorScheme cs, bool isDark) {
    return TextFormField(
      controller: _articleSearchController,
      autofocus: _articleSearchOpen,
      decoration: InputDecoration(
        hintText: 'Artikel suchen…',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _articleSearchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _articleSearchController.clear();
                  setState(() {});
                },
              )
            : null,
        filled: true,
        fillColor:
            isDark ? cs.surfaceContainerHigh : Colors.grey.shade50,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.primary, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onTap: () => setState(() => _articleSearchOpen = true),
      validator: (_) => _article.isEmpty ? 'Artikel wählen' : null,
    );
  }

  // ── Prüfdatum ─────────────────────────────────────────────────────────────

  Future<void> _pickCheckDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _checkDate = picked);
  }

  String _checkDateHint() {
    final days = _checkDate.difference(DateTime.now()).inDays;
    if (days >= 365) return 'in ${(days / 365).toStringAsFixed(1)} J.';
    return 'in $days Tagen';
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return Material(
      color: isDark ? cs.surfaceContainer : Colors.white,
      elevation: isDark ? 0 : 2,
      shadowColor: cs.shadow.withOpacity(0.07),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isDark
            ? BorderSide(color: cs.outlineVariant, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _scanTile({
    required String label,
    required String value,
    required IconData icon,
    required bool required,
    required VoidCallback onScan,
    required VoidCallback onClear,
    required bool isDark,
    required ColorScheme cs,
  }) {
    final hasValue = value.isNotEmpty;
    final Color borderColor = hasValue
        ? Colors.green
        : required
            ? cs.outlineVariant
            : cs.outlineVariant.withOpacity(0.5);
    final Color bgColor = hasValue
        ? Colors.green.withOpacity(isDark ? 0.12 : 0.06)
        : (isDark ? cs.surfaceContainerHigh : Colors.grey.shade50);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: hasValue ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: hasValue ? Colors.green : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  hasValue ? value : 'Noch nicht gescannt',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        hasValue ? FontWeight.w600 : FontWeight.normal,
                    color: hasValue
                        ? cs.onSurface
                        : cs.onSurfaceVariant.withOpacity(0.6),
                    fontFamily: hasValue ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          if (hasValue)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onClear,
            )
          else
            TextButton.icon(
              onPressed: onScan,
              icon: Icon(icon, size: 16),
              label: const Text('Scan'),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));

  InputDecoration _inputDeco(
          String hint, IconData icon, ColorScheme cs) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.primary, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      );
}
