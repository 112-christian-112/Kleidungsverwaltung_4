// screens/admin/equipment/equipment_inspection_form_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/equipment_model.dart';
import '../../../models/equipment_inspection_model.dart';
import '../../../services/equipment_inspection_service.dart';
import '../../../services/permission_service.dart';
import '../../../lists/inspection_checklist_data.dart';

// ─── Internes Laufzeit-Modell (nicht editieren — Definitionen in inspection_checklist_data.dart)

class _CheckItem {
  final String id;
  final String label;
  final bool isCritical;
  final CheckType checkType;
  bool? passed;
  String comment;

  _CheckItem.fromDef(CheckItemDef def)
      : id = def.id,
        label = def.label,
        isCritical = def.isCritical,
        checkType = def.checkType,
        passed = null,
        comment = '';
}

class _CheckCategory {
  final String title;
  final List<_CheckItem> items;
  _CheckCategory.fromDef(CheckCategoryDef def)
      : title = def.title,
        items = def.items.map(_CheckItem.fromDef).toList();
}

/// Baut die editierbare Laufzeit-Checkliste aus den unveränderlichen Definitionen.
List<_CheckCategory> _buildChecklistTemplate() =>
    buildChecklist().map(_CheckCategory.fromDef).toList();

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

  DateTime _inspectionDate = DateTime.now();
  final TextEditingController _inspectionDateController =
      TextEditingController();
  final TextEditingController _inspectorController = TextEditingController();
  DateTime _nextInspectionDate = DateTime.now().add(const Duration(days: 365));
  final TextEditingController _nextInspectionDateController =
      TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  late List<_CheckCategory> _checklist;
  InspectionResult _result = InspectionResult.passed;
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
      _showError('Fehler beim Laden: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserData() async {
    final user = await _permissionService.getCurrentUser();
    if (user != null && mounted && !_isEditing) {
      _inspectorController.text =
          user.name.isNotEmpty ? user.name : user.email;
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
      if (snapshot.docs.isNotEmpty && mounted) {
        final doc = _isEditing && snapshot.docs.length > 1
            ? snapshot.docs[1]
            : snapshot.docs[0];
        setState(() => _lastInspection =
            EquipmentInspectionModel.fromMap(doc.data(), doc.id));
      }
    } catch (_) {}
  }

  void _loadExistingInspection() {
    final e = widget.existingInspection!;
    _inspectionDate = e.inspectionDate;
    _inspectionDateController.text =
        DateFormat('dd.MM.yyyy').format(e.inspectionDate);
    _inspectorController.text = e.inspector;
    _nextInspectionDate = e.nextInspectionDate;
    _nextInspectionDateController.text =
        DateFormat('dd.MM.yyyy').format(e.nextInspectionDate);
    _commentsController.text = e.comments;
    _result = e.result;

    if (e.issues != null) {
      final failedLabels = e.issues!;
      for (final cat in _checklist) {
        for (final item in cat.items) {
          final key = '${cat.title}: ${item.label}';
          final match = failedLabels.firstWhere(
            (i) => i.startsWith(key) || i == key,
            orElse: () => '',
          );
          if (match.isNotEmpty) {
            item.passed = false;
            final parts = match.split(' | ');
            item.comment = parts.length > 1 ? parts.sublist(1).join(' | ') : '';
          } else {
            item.passed = true;
          }
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
    );
    if (picked != null && mounted) {
      setState(() {
        _inspectionDate = picked;
        _inspectionDateController.text = DateFormat('dd.MM.yyyy').format(picked);
        _nextInspectionDate = DateTime(picked.year + 1, picked.month, picked.day);
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
    );
    if (picked != null && mounted) {
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

  /// Alle fehlgeschlagenen k.o.-Kriterien
  List<_CheckItem> get _failedCriticalItems {
    final items = <_CheckItem>[];
    for (final cat in _checklist) {
      for (final item in cat.items) {
        if (item.passed == false && item.isCritical) items.add(item);
      }
    }
    return items;
  }

  int get _totalItems => _checklist.fold(0, (s, c) => s + c.items.length);
  int get _answeredItems => _checklist.fold(
      0, (s, c) => s + c.items.where((i) => i.passed != null).length);
  bool get _allAnswered => _answeredItems == _totalItems;

  void _recalculateResult() {
    final failed = _failedItemIds.length;
    final criticalFailed = _failedCriticalItems.length;

    // Ein k.o.-Kriterium reicht für "Nicht bestanden"
    if (criticalFailed > 0) {
      _result = InspectionResult.failed;
    } else if (failed == 0) {
      _result = InspectionResult.passed;
    } else if (failed <= 2) {
      _result = InspectionResult.conditionalPass;
    } else {
      _result = InspectionResult.failed;
    }
  }

  // ── Speichern ──────────────────────────────────────────────────────────────

  Future<void> _saveInspection() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_allAnswered) {
      _showError(
          'Noch ${_totalItems - _answeredItems} Punkte offen – bitte alle bewerten');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Kein Benutzer angemeldet');
      final userModel = await _permissionService.getCurrentUser();

      final issueLabels = <String>[];
      for (final cat in _checklist) {
        for (final item in cat.items) {
          if (item.passed == false) {
            final label = '${cat.title}: ${item.label}';
            issueLabels.add(
                item.comment.isNotEmpty ? '$label | ${item.comment}' : label);
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
        _showSuccess(
            _isEditing ? 'Prüfung aktualisiert' : 'Prüfung gespeichert');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _showError('Fehler: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prüfung löschen'),
        content: const Text('Prüfung wirklich löschen?'),
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

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating));

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Prüfung bearbeiten' : 'Neue Prüfung'),
        actions: [
          if (_isEditing)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _showDeleteDialog,
                tooltip: 'Prüfung löschen'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: CustomScrollView(
                slivers: [
                  // ── Sticky Fortschrittsleiste ────────────────────────
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProgressBarDelegate(
                      answered: _answeredItems,
                      total: _totalItems,
                      failed: _failedItemIds.length,
                      allAnswered: _allAnswered,
                      primaryColor: cs.primary,
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ── Equipment & Meta ──────────────────────────
                        _buildMetaCard(cs),
                        const SizedBox(height: 16),

                        // ── Checkliste ────────────────────────────────
                        ..._checklist.map((cat) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildCategoryCard(cat, cs),
                            )),

                        // ── Ergebnis ──────────────────────────────────
                        _buildResultCard(cs),
                        const SizedBox(height: 12),

                        // ── Abschluss (Kommentar + Datum) ─────────────
                        _buildFinishCard(cs),
                        const SizedBox(height: 20),

                        // ── Speichern ─────────────────────────────────
                        _buildSaveButton(cs),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // META-CARD (Equipment + Prüfer + Datum)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetaCard(ColorScheme cs) {
    final isJacke = widget.equipment.type == 'Jacke';
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
            // Equipment-Info Zeile
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isJacke
                        ? Icons.accessibility_new
                        : Icons.airline_seat_legroom_normal,
                    color: cs.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.equipment.owner,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '${widget.equipment.article} · Gr. ${widget.equipment.size}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Letzte Prüfung kompakt
                if (_lastInspection != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Letzte Prüfung',
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant)),
                      Text(
                        DateFormat('dd.MM.yy')
                            .format(_lastInspection!.inspectionDate),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Prüfer + Datum
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _inspectorController,
                    decoration: InputDecoration(
                      labelText: 'Prüfer *',
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Pflichtfeld' : null,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: _inspectionDateController,
                    readOnly: true,
                    onTap: _selectInspectionDate,
                    decoration: InputDecoration(
                      labelText: 'Prüfdatum *',
                      prefixIcon:
                          const Icon(Icons.calendar_today, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Pflichtfeld' : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KATEGORIE-CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryCard(_CheckCategory cat, ColorScheme cs) {
    final answered = cat.items.where((i) => i.passed != null).length;
    final failed = cat.items.where((i) => i.passed == false).length;
    final complete = answered == cat.items.length;

    Color accent = cs.primary;
    if (complete) accent = failed == 0 ? Colors.green : Colors.red;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: complete
              ? accent.withOpacity(0.4)
              : cs.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: !complete || failed > 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: EdgeInsets.zero,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: complete
                ? Icon(
                    failed == 0 ? Icons.check_rounded : Icons.close_rounded,
                    color: accent,
                    size: 18)
                : Center(
                    child: Text('$answered/${cat.items.length}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: accent)),
                  ),
          ),
          title: Text(cat.title,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: failed > 0
              ? Text('$failed Mangel${failed > 1 ? 'punkte' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade600))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "Alle IO"-Shortcut
              if (!complete)
                GestureDetector(
                  onTap: () => _setCategoryAllIO(cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.green.withOpacity(0.4)),
                    ),
                    child: const Text('Alle IO',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
          children: cat.items
              .map((item) => _buildCheckItem(item, cat, cs))
              .toList(),
        ),
      ),
    );
  }

  // ── Einzelner Prüfpunkt ────────────────────────────────────────────────────

  Widget _buildCheckItem(
      _CheckItem item, _CheckCategory cat, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIO = item.passed == true;
    final isNIO = item.passed == false;
    final isPending = item.passed == null;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
        color: isNIO
            ? (item.isCritical
                ? Colors.red.withOpacity(isDark ? 0.14 : 0.07)
                : Colors.red.withOpacity(isDark ? 0.08 : 0.04))
            : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badges: Prüfart + k.o.
                Row(
                  children: [
                    _checkTypeBadge(item.checkType, cs),
                    if (item.isCritical) ...[
                      const SizedBox(width: 5),
                      _criticalBadge(isNIO),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // Label + Buttons
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status-Icon
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        isPending
                            ? Icons.radio_button_unchecked
                            : isIO
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                        size: 16,
                        color: isPending
                            ? cs.onSurfaceVariant.withOpacity(0.4)
                            : isIO
                                ? Colors.green
                                : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: isNIO
                              ? (item.isCritical
                                  ? Colors.red.shade800
                                  : Colors.red.shade700)
                              : cs.onSurface,
                          fontWeight: isNIO && item.isCritical
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ioButton(
                      label: 'IO',
                      active: isIO,
                      activeColor: Colors.green,
                      onTap: () => _setItemResult(item.id, true),
                    ),
                    const SizedBox(width: 6),
                    _ioButton(
                      label: 'NIO',
                      active: isNIO,
                      activeColor: Colors.red,
                      onTap: () => _setItemResult(item.id, false),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // NIO-Kommentar
          if (isNIO)
            Padding(
              padding: const EdgeInsets.only(left: 38, right: 14, bottom: 10),
              child: TextField(
                onChanged: (v) => item.comment = v,
                controller: TextEditingController(text: item.comment)
                  ..selection = TextSelection.fromPosition(
                      TextPosition(offset: item.comment.length)),
                decoration: InputDecoration(
                  hintText: item.isCritical
                      ? 'Art des sicherheitskritischen Mangels *'
                      : 'Mangelbeschreibung (optional)',
                  hintStyle:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: Colors.red.withOpacity(0.4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: Colors.red.withOpacity(0.3)),
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// Badge: Sicht / Funktion / Dokument
  Widget _checkTypeBadge(CheckType type, ColorScheme cs) {
    final (label, icon, color) = switch (type) {
      CheckType.visual => ('Sichtprüfung', Icons.visibility_outlined, Colors.blue),
      CheckType.function => ('Funktionsprüfung', Icons.touch_app_outlined, Colors.purple),
      CheckType.document => ('Dokumentprüfung', Icons.description_outlined, Colors.teal),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// k.o.-Badge — leuchtet rot wenn NIO
  Widget _criticalBadge(bool isNio) {
    final color = isNio ? Colors.red : Colors.red.shade300;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isNio ? Colors.red.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(isNio ? 0.5 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 10, color: color),
          const SizedBox(width: 3),
          Text('k.o.-Kriterium',
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: isNio ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _ioButton({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? activeColor : activeColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? activeColor : activeColor.withOpacity(0.3),
              width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active
                ? Colors.white
                : activeColor.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ERGEBNIS-CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildResultCard(ColorScheme cs) {
    final failCount = _failedItemIds.length;
    final criticalFailed = _failedCriticalItems;
    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;

    if (!_allAnswered) {
      color = cs.primary;
      icon = Icons.pending_outlined;
      title = '$_answeredItems / $_totalItems bewertet';
      subtitle = 'Noch ${_totalItems - _answeredItems} Punkte offen';
    } else if (criticalFailed.isNotEmpty) {
      color = Colors.red;
      icon = Icons.dangerous_rounded;
      title = 'Nicht bestanden – k.o.-Kriterium';
      subtitle =
          '${criticalFailed.length} sicherheitskritischer Mangel${criticalFailed.length > 1 ? 'punkte' : ''} · Status wird: In Reparatur';
    } else if (failCount == 0) {
      color = Colors.green;
      icon = Icons.verified_rounded;
      title = 'Bestanden';
      subtitle = 'Keine Mängel · Status wird: Einsatzbereit';
    } else if (failCount <= 2) {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
      title = 'Bedingt bestanden';
      subtitle = '$failCount Beobachtungsmangel${failCount > 1 ? 'punkte' : ''} · Status wird: Einsatzbereit';
    } else {
      color = Colors.red;
      icon = Icons.cancel_rounded;
      title = 'Nicht bestanden';
      subtitle = '$failCount Mängel · Status wird: In Reparatur';
    }

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.35), width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: color.withOpacity(0.8))),
                  ],
                ),
              ),
            ],
          ),
        ),
        // k.o.-Mängel-Liste als Zusatzinfo
        if (criticalFailed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.report_outlined,
                      size: 14, color: Colors.red.shade700),
                  const SizedBox(width: 6),
                  Text('Sicherheitskritische Mängel (k.o.):',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700)),
                ]),
                const SizedBox(height: 6),
                ...criticalFailed.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: TextStyle(
                                  color: Colors.red.shade600, fontSize: 12)),
                          Expanded(
                            child: Text(item.label,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade700)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ABSCHLUSS-CARD (Kommentar + Nächste Prüfung)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFinishCard(ColorScheme cs) {
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
            // Nächste Prüfung
            Row(
              children: [
                Icon(Icons.event_repeat, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                const Text('Nächste Prüfung',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nextInspectionDateController,
              readOnly: true,
              onTap: _selectNextInspectionDate,
              decoration: InputDecoration(
                labelText: 'Nächstes Prüfdatum *',
                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                helperText: 'Standard: 1 Jahr nach Prüfdatum',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Bemerkungen
            Row(
              children: [
                Icon(Icons.comment_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                const Text('Bemerkungen (optional)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _commentsController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Allgemeine Anmerkungen zur Prüfung …',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEICHERN-BUTTON
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSaveButton(ColorScheme cs) {
    return FilledButton.icon(
      onPressed: _allAnswered ? _saveInspection : null,
      icon: const Icon(Icons.save_rounded),
      label: Text(
        _isEditing ? 'Prüfung aktualisieren' : 'Prüfung abschließen & speichern',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        disabledBackgroundColor: cs.onSurface.withOpacity(0.12),
      ),
    );
  }
}

// ─── Sticky Progress Bar ──────────────────────────────────────────────────────

class _ProgressBarDelegate extends SliverPersistentHeaderDelegate {
  final int answered;
  final int total;
  final int failed;
  final bool allAnswered;
  final Color primaryColor;

  const _ProgressBarDelegate({
    required this.answered,
    required this.total,
    required this.failed,
    required this.allAnswered,
    required this.primaryColor,
  });

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = total > 0 ? answered / total : 0.0;
    final barColor = allAnswered
        ? (failed == 0 ? Colors.green : (failed <= 2 ? Colors.orange : Colors.red))
        : primaryColor;
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      elevation: overlapsContent ? 2 : 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(
                  '$answered / $total Prüfpunkte',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                ),
                const Spacer(),
                if (failed > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      '$failed Mangel${failed > 1 ? 'punkte' : ''}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                else if (allAnswered)
                  Text('Vollständig ✓',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: cs.outlineVariant.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_ProgressBarDelegate old) =>
      answered != old.answered ||
      failed != old.failed ||
      allAnswered != old.allAnswered;
}
