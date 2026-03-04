// screens/admin/equipment/equipment_inspection_form_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import '../../../services/equipment_inspection_service.dart';
import '../../../services/permission_service.dart';

// ─── Datenmodell für die Viking-Checkliste ────────────────────────────────────

class _CheckItem {
  final String id;
  final String label;
  /// true = bestanden, false = nicht bestanden, null = noch nicht bewertet
  bool? passed;
  /// Kommentar bei NIO (optional)
  String comment;

  _CheckItem({required this.id, required this.label, this.passed, this.comment = ''});
}

class _CheckCategory {
  final String title;
  final List<_CheckItem> items;

  _CheckCategory({required this.title, required this.items});
}

// Alle Prüfpunkte gemäß VIKING Prüfliste Feuerwehr – Einsatzkleidung
List<_CheckCategory> _buildChecklistTemplate() {
  return [
    _CheckCategory(title: 'Kennzeichnung', items: [
      _CheckItem(id: 'kenn_1', label: 'Kennzeichnung (z.B. DIN EN 469 bzw. Prüfnummer, Pflegeanweisung) lesbar?'),
      _CheckItem(id: 'kenn_2', label: 'Pflegeanleitung lesbar?'),
      _CheckItem(id: 'kenn_3', label: 'Informationen des Herstellers vorhanden, vollständig, verfügbar?'),
    ]),
    _CheckCategory(title: 'Oberstoff', items: [
      _CheckItem(id: 'ober_1', label: 'Sichtprüfung auf Löcher'),
      _CheckItem(id: 'ober_2', label: 'Sichtprüfung auf Verschmutzungen, die die Sicherheit beeinflussen können?'),
      _CheckItem(id: 'ober_3', label: 'Sichtprüfung auf erkennbare thermische Schädigungen / Kräuselungen'),
      _CheckItem(id: 'ober_4', label: 'Bei Laminat (z.B. Ausführung Niedersachsen): Sichtprüfung auf Ablösung Oberstoff – Laminat'),
    ]),
    _CheckCategory(title: 'Nahtverbindungen', items: [
      _CheckItem(id: 'naht_1', label: 'Sichtprüfung auf Beschädigungen der Nahtverbindungen'),
      _CheckItem(id: 'naht_2', label: 'Sichtprüfung der Abklebungen vollständig'),
    ]),
    _CheckCategory(title: 'Isolationsfutter', items: [
      _CheckItem(id: 'iso_1', label: 'Sichtprüfung auf Beschädigung'),
      _CheckItem(id: 'iso_2', label: 'Funktionsprüfung Reißverschluss (Beschädigungen, Leichtläufigkeit)'),
    ]),
    _CheckCategory(title: 'Innenfutter', items: [
      _CheckItem(id: 'inn_1', label: 'Sichtprüfung auf Löcher'),
      _CheckItem(id: 'inn_2', label: 'Sichtprüfung auf Verschmutzungen, die die Sicherheit beeinflussen können?'),
      _CheckItem(id: 'inn_3', label: 'Sichtprüfung auf erkennbare thermische Schädigungen / Kräuselungen'),
      _CheckItem(id: 'inn_4', label: 'Sichtprüfung auf Beschädigungen der Nahtverbindungen'),
    ]),
    _CheckCategory(title: 'Reißverschluss', items: [
      _CheckItem(id: 'reiss_1', label: 'Sichtprüfung auf vollständige Schließung'),
      _CheckItem(id: 'reiss_2', label: 'Sichtprüfung auf Beschädigung'),
      _CheckItem(id: 'reiss_3', label: 'Funktionsprüfung Reißverschluss (Beschädigungen, Leichtläufigkeit)'),
    ]),
    _CheckCategory(title: 'Taschen / Überlappungen', items: [
      _CheckItem(id: 'tasch_1', label: 'Sichtprüfung auf Überdeckung der Taschenpatten'),
      _CheckItem(id: 'tasch_2', label: 'Sichtprüfung Knöpfe oder Klett vollständig & sauber'),
      _CheckItem(id: 'tasch_3', label: 'Funktionsprüfung Schließung mit Klettstreifen'),
    ]),
    _CheckCategory(title: 'Aufhänger', items: [
      _CheckItem(id: 'aufh_1', label: 'Sichtprüfung auf Vorhandensein und Beschädigung'),
    ]),
    _CheckCategory(title: 'Karabiner', items: [
      _CheckItem(id: 'kara_1', label: 'Sichtprüfung auf Vorhandensein und Beschädigung'),
    ]),
    _CheckCategory(title: 'Klettverschlüsse', items: [
      _CheckItem(id: 'klett_1', label: 'Sichtprüfung auf Beschädigung und Verschmutzung'),
      _CheckItem(id: 'klett_2', label: 'Funktionsprüfung der sachgerechten Schließung'),
    ]),
    _CheckCategory(title: 'Reflexstreifen', items: [
      _CheckItem(id: 'reflex_1', label: 'Sichtprüfung der Nahtverbindungen (Festigkeit, Ablösen)'),
      _CheckItem(id: 'reflex_2', label: 'Sichtprüfung auf Beschädigung und Verschmutzung'),
      _CheckItem(id: 'reflex_3', label: 'Funktionsprüfung der Reflexstreifen (ggf. mittels Lampe)'),
    ]),
  ];
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class EquipmentInspectionFormScreen extends StatefulWidget {
  final EquipmentModel equipment;
  final EquipmentInspectionModel? existingInspection;

  const EquipmentInspectionFormScreen({
    Key? key,
    required this.equipment,
    this.existingInspection,
  }) : super(key: key);

  @override
  State<EquipmentInspectionFormScreen> createState() =>
      _EquipmentInspectionFormScreenState();
}

class _EquipmentInspectionFormScreenState
    extends State<EquipmentInspectionFormScreen> {
  final PermissionService _permissionService = PermissionService();
  final _formKey = GlobalKey<FormState>();
  final EquipmentInspectionService _inspectionService =
      EquipmentInspectionService();

  // Datum & Prüfer
  DateTime _inspectionDate = DateTime.now();
  final TextEditingController _inspectionDateController =
      TextEditingController();
  final TextEditingController _inspectorController = TextEditingController();

  DateTime _nextInspectionDate =
      DateTime.now().add(const Duration(days: 365));
  final TextEditingController _nextInspectionDateController =
      TextEditingController();

  final TextEditingController _commentsController = TextEditingController();

  // Checkliste
  late List<_CheckCategory> _checklist;

  // Ergebnis (wird automatisch berechnet)
  InspectionResult _result = InspectionResult.passed;

  // Letzte Prüfung (zur Anzeige im Header)
  EquipmentInspectionModel? _lastInspection;

  bool _isLoading = false;
  bool _isEditing = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingInspection != null;
    _checklist = _buildChecklistTemplate();
    _initDateControllers();
    _loadData();
  }

  @override
  void dispose() {
    _inspectionDateController.dispose();
    _inspectorController.dispose();
    _nextInspectionDateController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  // ── Daten laden ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _loadUserData();
      await _loadLastInspection();
      if (_isEditing) _loadExistingInspection();
    } catch (e) {
      _showErrorSnackBar('Fehler beim Laden der Daten: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLastInspection() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('equipment_inspections')
          .where('equipmentId', isEqualTo: widget.equipment.id)
          .orderBy('inspectionDate', descending: true)
          .limit(_isEditing ? 2 : 1)
          .get();

      if (snapshot.docs.isEmpty) return;

      // Beim Bearbeiten: die aktuelle Prüfung überspringen, die vorherige zeigen
      final targetIndex = _isEditing && snapshot.docs.length > 1 ? 1 : 0;
      final doc = snapshot.docs[targetIndex];
      // Beim Bearbeiten nicht die eigene Prüfung als "letzte" zeigen
      if (_isEditing && doc.id == widget.existingInspection!.id) return;

      setState(() {
        _lastInspection = EquipmentInspectionModel.fromMap(doc.data(), doc.id);
      });
    } catch (e) {
      // Nicht kritisch — Header funktioniert ohne letzte Prüfung
      print('Letzte Prüfung konnte nicht geladen werden: $e');
    }
  }

  Future<void> _loadUserData() async {
    final user = await _permissionService.getCurrentUser();
    if (user != null && !_isEditing) {
      _inspectorController.text =
          user.name.isNotEmpty ? user.name : user.email;
    }
  }

  /// Beim Bearbeiten: vorhandene Issues als "nicht bestanden" markieren.
  void _loadExistingInspection() {
    final inspection = widget.existingInspection!;
    _inspectionDate = inspection.inspectionDate;
    _inspectorController.text = inspection.inspector;
    _result = inspection.result;
    _commentsController.text = inspection.comments;
    _nextInspectionDate = inspection.nextInspectionDate;
    _inspectionDateController.text =
        DateFormat('dd.MM.yyyy').format(_inspectionDate);
    _nextInspectionDateController.text =
        DateFormat('dd.MM.yyyy').format(_nextInspectionDate);

    // Issues werden als "Kategorie: Label" gespeichert — darüber matchen
    final failedLabels = inspection.issues ?? [];
    for (final cat in _checklist) {
      for (final item in cat.items) {
        final issueKey = '${cat.title}: ${item.label}';
        final match = failedLabels.firstWhere(
          (issue) => issue.startsWith(issueKey) || issue == issueKey,
          orElse: () => '',
        );
        if (match.isNotEmpty) {
          item.passed = false;
          // Kommentar extrahieren falls vorhanden (Format: "Kat: Label | Kommentar")
          final parts = match.split(' | ');
          item.comment = parts.length > 1 ? parts.sublist(1).join(' | ') : '';
        } else {
          item.passed = true;
          item.comment = '';
        }
      }
    }
  }

  // ── Datum-Helfer ───────────────────────────────────────────────────────────

  void _initDateControllers() {
    _inspectionDateController.text =
        DateFormat('dd.MM.yyyy').format(_inspectionDate);
    _nextInspectionDateController.text =
        DateFormat('dd.MM.yyyy').format(_nextInspectionDate);
  }

  Future<void> _selectInspectionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _inspectionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('de', 'DE'),
      helpText: 'Prüfdatum auswählen',
    );
    if (picked != null) {
      setState(() {
        _inspectionDate = picked;
        _inspectionDateController.text =
            DateFormat('dd.MM.yyyy').format(picked);
        _nextInspectionDate = DateTime(
            picked.year + 1, picked.month, picked.day);
        _nextInspectionDateController.text =
            DateFormat('dd.MM.yyyy').format(_nextInspectionDate);
      });
    }
  }

  Future<void> _selectNextInspectionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextInspectionDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      locale: const Locale('de', 'DE'),
      helpText: 'Nächstes Prüfdatum auswählen',
    );
    if (picked != null) {
      setState(() {
        _nextInspectionDate = picked;
        _nextInspectionDateController.text =
            DateFormat('dd.MM.yyyy').format(picked);
      });
    }
  }

  // ── Checklisten-Logik ──────────────────────────────────────────────────────

  void _setItemResult(String itemId, bool passed) {
    setState(() {
      for (final cat in _checklist) {
        for (final item in cat.items) {
          if (item.id == itemId) {
            item.passed = passed;
            // Kommentar zurücksetzen wenn wieder auf IO gesetzt
            if (passed) item.comment = '';
          }
        }
      }
      _recalculateResult();
    });
  }

  void _setCategoryAllIO(_CheckCategory cat) {
    setState(() {
      for (final item in cat.items) {
        item.passed = true;
        item.comment = '';
      }
      _recalculateResult();
    });
  }

  List<String> get _failedItemIds {
    final ids = <String>[];
    for (final cat in _checklist) {
      for (final item in cat.items) {
        if (item.passed == false) ids.add(item.id);
      }
    }
    return ids;
  }

  int get _totalItems =>
      _checklist.fold(0, (sum, cat) => sum + cat.items.length);

  int get _answeredItems => _checklist.fold(
      0,
      (sum, cat) =>
          sum + cat.items.where((i) => i.passed != null).length);

  bool get _allAnswered => _answeredItems == _totalItems;

  void _recalculateResult() {
    final failed = _failedItemIds.length;
    if (failed == 0) {
      _result = InspectionResult.passed;
    } else if (failed <= 2) {
      _result = InspectionResult.conditionalPass;
    } else {
      _result = InspectionResult.failed;
    }
  }

  // ── Speichern ──────────────────────────────────────────────────────────────

  Future<void> _saveInspection() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Bitte füllen Sie alle Pflichtfelder aus');
      return;
    }
    if (!_allAnswered) {
      _showErrorSnackBar(
          'Bitte bewerten Sie alle Prüfpunkte (noch ${_totalItems - _answeredItems} offen)');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Kein Benutzer angemeldet');

      final userModel = await _permissionService.getCurrentUser();

      // Nicht-bestandene Items als Issues speichern (mit lesbarem Label)
      final issueLabels = <String>[];
      for (final cat in _checklist) {
        for (final item in cat.items) {
          if (item.passed == false) {
            issueLabels.add('${cat.title}: ${item.label}');
          }
        }
      }

      final inspection = EquipmentInspectionModel(
        id: _isEditing ? widget.existingInspection!.id : '',
        equipmentId: widget.equipment.id,
        inspectionDate: _inspectionDate,
        inspector: _inspectorController.text.trim(),
        result: _result,
        comments: _commentsController.text.trim(),
        nextInspectionDate: _nextInspectionDate,
        issues: issueLabels.isNotEmpty ? issueLabels : null,
        createdAt: _isEditing
            ? widget.existingInspection!.createdAt
            : DateTime.now(),
        createdBy: userModel?.name.isNotEmpty == true
            ? userModel!.name
            : userModel?.email ?? '',
      );

      if (_isEditing) {
        await _inspectionService.updateInspection(inspection);
      } else {
        await _inspectionService.addInspection(inspection);
      }

      if (mounted) {
        _showSuccessSnackBar(_isEditing
            ? 'Prüfung erfolgreich aktualisiert'
            : 'Prüfung erfolgreich gespeichert');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Fehler beim Speichern: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Löschen ────────────────────────────────────────────────────────────────

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prüfung löschen'),
        content: const Text('Möchten Sie diese Prüfung wirklich löschen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _inspectionService
                  .deleteInspection(widget.existingInspection!.id);
              if (mounted) Navigator.pop(context, true);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  // ── Snackbars ──────────────────────────────────────────────────────────────

  void _showErrorSnackBar(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));

  void _showSuccessSnackBar(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating));

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _isEditing ? 'Prüfung bearbeiten' : 'Neue Prüfung durchführen'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isEditing)
            IconButton(
                icon: const Icon(Icons.delete), onPressed: _showDeleteDialog),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildProgressBanner(),
                  const SizedBox(height: 16),
                  ..._checklist.map(_buildCategoryCard),
                  const SizedBox(height: 16),
                  _buildResultSummaryCard(),
                  const SizedBox(height: 16),
                  _buildCommentsCard(),
                  const SizedBox(height: 16),
                  _buildNextInspectionCard(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── Kopfbereich: Metadaten ─────────────────────────────────────────────────

  Widget _buildHeaderCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.fact_check,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Prüfinformationen',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            Text(
              'Prüfliste Feuerwehr – Einsatzkleidung (VIKING)',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),

            // Equipment-Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.inventory_2,
                    color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${widget.equipment.article} – ${widget.equipment.type}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('Besitzer: ${widget.equipment.owner}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                      if (widget.equipment.nfcTag.isNotEmpty)
                        Text('NFC-Tag: ${widget.equipment.nfcTag}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Letzte Prüfung
            if (_lastInspection != null) _buildLastInspectionBox(_lastInspection!),
            if (_lastInspection != null) const SizedBox(height: 16),

            // Prüfdatum
            TextFormField(
              controller: _inspectionDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Geprüft am *',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.event),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              onTap: _selectInspectionDate,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Bitte Datum auswählen' : null,
            ),
            const SizedBox(height: 12),

            // Prüfer
            TextFormField(
              controller: _inspectorController,
              decoration: InputDecoration(
                labelText: 'Unterschrift / Prüfer *',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.person),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Bitte Prüfer angeben' : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Letzte Prüfung Box ────────────────────────────────────────────────────────

  Widget _buildLastInspectionBox(EquipmentInspectionModel last) {
    Color resultColor;
    IconData resultIcon;
    String resultText;
    switch (last.result) {
      case InspectionResult.passed:
        resultColor = Colors.green;
        resultIcon = Icons.check_circle;
        resultText = 'Bestanden';
        break;
      case InspectionResult.conditionalPass:
        resultColor = Colors.orange;
        resultIcon = Icons.warning_amber_rounded;
        resultText = 'Bedingt bestanden';
        break;
      case InspectionResult.failed:
        resultColor = Colors.red;
        resultIcon = Icons.cancel;
        resultText = 'Nicht bestanden';
        break;
    }

    final hasIssues = last.issues != null && last.issues!.isNotEmpty;
    final hasComments = last.comments.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: resultColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resultColor.withOpacity(0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(resultIcon, color: resultColor, size: 20),
          title: Text(
            'Letzte Prüfung: ${DateFormat("dd.MM.yyyy").format(last.inspectionDate)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: resultColor),
          ),
          subtitle: Text(
            '$resultText  ·  ${last.inspector}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          // Nur aufklappbar wenn es Mängel oder Kommentare gibt
          initiallyExpanded: false,
          children: [
            if (!hasIssues && !hasComments)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Keine Mängel festgestellt.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),

            // Mängel
            if (hasIssues) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.red.shade400),
                const SizedBox(width: 6),
                Text('Festgestellte Mängel:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700)),
              ]),
              const SizedBox(height: 6),
              ...last.issues!.map((issue) {
                // Format: "Kategorie: Label" oder "Kategorie: Label | Kommentar"
                final parts = issue.split(' | ');
                final label = parts[0];
                final comment = parts.length > 1 ? parts.sublist(1).join(' | ') : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: const TextStyle(fontSize: 12)),
                            if (comment.isNotEmpty)
                              Text('↳ $comment',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // Kommentar
            if (hasComments) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.comment, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text('Bemerkung:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700)),
              ]),
              const SizedBox(height: 4),
              Text(last.comments,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  // ── Fortschrittsanzeige ────────────────────────────────────────────────────

  Widget _buildProgressBanner() {
    final progress =
        _totalItems > 0 ? _answeredItems / _totalItems : 0.0;
    final failCount = _failedItemIds.length;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                '$_answeredItems / $_totalItems Punkte bewertet',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (failCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: failCount > 2
                        ? Colors.red.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color:
                            failCount > 2 ? Colors.red : Colors.orange),
                  ),
                  child: Text(
                    '$failCount Mängel',
                    style: TextStyle(
                        color: failCount > 2 ? Colors.red : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              color: _allAnswered
                  ? (failCount == 0 ? Colors.green : Colors.orange)
                  : Theme.of(context).colorScheme.primary,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }

  // ── Kategorie-Karte ────────────────────────────────────────────────────────

  Widget _buildCategoryCard(_CheckCategory cat) {
    final answeredInCat = cat.items.where((i) => i.passed != null).length;
    final failedInCat = cat.items.where((i) => i.passed == false).length;

    Color headerColor = Theme.of(context).colorScheme.primary;
    if (answeredInCat == cat.items.length) {
      headerColor = failedInCat == 0 ? Colors.green : Colors.red;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Kategorie-Kopf
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12)),
              border: Border(
                  left: BorderSide(color: headerColor, width: 4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(cat.title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: headerColor)),
                ),
                Text('$answeredInCat/${cat.items.length}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                // "Alle IO"-Schnellbutton
                if (cat.items.any((i) => i.passed != true))
                  GestureDetector(
                    onTap: () => _setCategoryAllIO(cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.done_all, size: 13, color: Colors.white),
                          SizedBox(width: 3),
                          Text('Alle IO',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Prüfpunkte
          ...cat.items.map((item) => _buildCheckItem(item)),
        ],
      ),
    );
  }

  // ── Einzelner Prüfpunkt ────────────────────────────────────────────────────

  Widget _buildCheckItem(_CheckItem item) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                        fontSize: 13,
                        color: item.passed == false
                            ? Colors.red.shade700
                            : Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                // IO-Toggle-Buttons
                _buildToggleButton(
                  label: 'IO',
                  icon: Icons.check,
                  active: item.passed == true,
                  activeColor: Colors.green,
                  onTap: () => _setItemResult(item.id, true),
                ),
                const SizedBox(width: 6),
                _buildToggleButton(
                  label: 'NIO',
                  icon: Icons.close,
                  active: item.passed == false,
                  activeColor: Colors.red,
                  onTap: () => _setItemResult(item.id, false),
                ),
              ],
            ),
          ),
          // NIO-Kommentarfeld — erscheint nur wenn NIO gewählt
          if (item.passed == false)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Mangel beschreiben ...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.red.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.red.shade200),
                  ),
                  filled: true,
                  fillColor: Colors.red.shade50,
                  prefixIcon: Icon(Icons.edit_note,
                      size: 16, color: Colors.red.shade300),
                ),
                style: const TextStyle(fontSize: 12),
                controller: TextEditingController(text: item.comment)
                  ..selection = TextSelection.collapsed(offset: item.comment.length),
                onChanged: (val) => item.comment = val,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? activeColor : Colors.grey.shade300,
              width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14,
              color: active ? Colors.white : Colors.grey.shade500),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  // ── Ergebnis-Zusammenfassung ───────────────────────────────────────────────

  Widget _buildResultSummaryCard() {
    final failCount = _failedItemIds.length;
    Color resultColor;
    IconData resultIcon;
    String resultText;
    String resultSubtext;

    if (!_allAnswered) {
      resultColor = Colors.grey;
      resultIcon = Icons.hourglass_empty;
      resultText = 'Prüfung unvollständig';
      resultSubtext =
          'Noch ${_totalItems - _answeredItems} Punkte offen';
    } else if (failCount == 0) {
      resultColor = Colors.green;
      resultIcon = Icons.check_circle;
      resultText = 'Bestanden';
      resultSubtext = 'Keine Mängel → Status: Einsatzbereit';
    } else if (failCount <= 2) {
      resultColor = Colors.orange;
      resultIcon = Icons.warning;
      resultText = 'Bedingt bestanden';
      resultSubtext =
          '$failCount geringfügige Mängel → Status: Einsatzbereit';
    } else {
      resultColor = Colors.red;
      resultIcon = Icons.cancel;
      resultText = 'Nicht bestanden';
      resultSubtext =
          '$failCount Mängel festgestellt → Status: In Reparatur';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: resultColor, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: resultColor.withOpacity(0.15),
            radius: 28,
            child: Icon(resultIcon, color: resultColor, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Prüfergebnis',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey)),
                  Text(resultText,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: resultColor)),
                  Text(resultSubtext,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700)),
                ]),
          ),
        ]),
      ),
    );
  }

  // ── Kommentare ─────────────────────────────────────────────────────────────

  Widget _buildCommentsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.comment,
                color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            const Text('Bemerkungen',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          TextFormField(
            controller: _commentsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Optionale Bemerkungen zur Prüfung ...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Nächstes Prüfdatum ─────────────────────────────────────────────────────

  Widget _buildNextInspectionCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event_repeat,
                color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            const Text('Nächste Prüfung',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nextInspectionDateController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Nächstes Prüfdatum *',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.event_repeat),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              helperText: 'Standardmäßig 1 Jahr nach Prüfdatum',
            ),
            onTap: _selectNextInspectionDate,
            validator: (v) =>
                v == null || v.isEmpty ? 'Datum erforderlich' : null,
          ),
        ]),
      ),
    );
  }

  // ── Speichern-Button ───────────────────────────────────────────────────────

  Widget _buildSaveButton() {
    final canSave = _allAnswered;
    return ElevatedButton.icon(
      onPressed: canSave ? _saveInspection : null,
      icon: const Icon(Icons.save),
      label: Text(_isEditing
          ? 'Prüfung aktualisieren'
          : 'Prüfung abschließen & speichern'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade300,
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
