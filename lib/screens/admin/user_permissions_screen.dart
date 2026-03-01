// screens/admin/user_permissions_screen.dart
//
// Admin-Screen: Individuelle Rechte pro Benutzer vergeben.
// Erreichbar aus der Benutzerverwaltung (AdminUserApprovalScreen).

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../Lists/fire_stations.dart';
import '../../models/user_models.dart';
import '../../services/permission_service.dart';

class UserPermissionsScreen extends StatefulWidget {
  final UserModel user;

  const UserPermissionsScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<UserPermissionsScreen> createState() => _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends State<UserPermissionsScreen> {
  late UserPermissions _permissions;
  bool _isSaving = false;
  bool _allStations = false;

  final PermissionService _permissionService = PermissionService();

  @override
  void initState() {
    super.initState();
    _permissions = widget.user.permissions;
    _allStations = _permissions.visibleFireStations.contains('*');
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _permissionService.saveUserPermissions(
          widget.user.uid, _permissions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berechtigungen gespeichert'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleStation(String station) {
    final current = List<String>.from(_permissions.visibleFireStations);
    if (current.contains(station)) {
      current.remove(station);
    } else {
      current.add(station);
    }
    setState(() {
      _permissions = _permissions.copyWith(visibleFireStations: current);
    });
  }

  void _setAllStations(bool value) {
    setState(() {
      _allStations = value;
      if (value) {
        _permissions = _permissions.copyWith(visibleFireStations: ['*']);
      } else {
        // Zurück auf eigene Feuerwehr
        _permissions = _permissions.copyWith(
            visibleFireStations: [widget.user.fireStation]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user.isAdmin) {
      return _buildAdminHint();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Rechte: ${widget.user.name}'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, color: Colors.white),
              label:
                  const Text('Speichern', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Benutzerinfo ─────────────────────────────────────────────────
          _UserInfoCard(user: widget.user),
          const SizedBox(height: 16),

          // ── Sichtbare Ortswehren ──────────────────────────────────────────
          _SectionCard(
            title: 'Sichtbare Ortswehren',
            icon: Icons.location_city,
            iconColor: Colors.blue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Alle Ortswehren',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'Benutzer kann alle Ortswehren sehen'),
                  value: _allStations,
                  onChanged: _setAllStations,
                ),
                if (!_allStations) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Text(
                      'Eigene Feuerwehr (${widget.user.fireStation}) ist immer sichtbar.',
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...FireStations.all.map((station) {
                    final isOwn = station == widget.user.fireStation;
                    final isSelected = isOwn ||
                        _permissions.visibleFireStations.contains(station);
                    return CheckboxListTile(
                      dense: true,
                      title: Text(
                        station,
                        style: TextStyle(
                            fontWeight: isOwn
                                ? FontWeight.bold
                                : FontWeight.normal),
                      ),
                      subtitle: isOwn
                          ? const Text('Eigene Feuerwehr',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic))
                          : null,
                      value: isSelected,
                      onChanged:
                          isOwn ? null : (_) => _toggleStation(station),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Einsatzkleidung ───────────────────────────────────────────────
          _PermissionsGroup(
            title: 'Einsatzkleidung',
            icon: Icons.checkroom,
            iconColor: Colors.orange,
            rows: [
              _PermRow(
                label: 'Einsehen',
                value: _permissions.equipmentView,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(equipmentView: v)),
              ),
              _PermRow(
                label: 'Bearbeiten',
                value: _permissions.equipmentEdit,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(equipmentEdit: v)),
              ),
              _PermRow(
                label: 'Hinzufügen',
                value: _permissions.equipmentAdd,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(equipmentAdd: v)),
              ),
              _PermRow(
                label: 'Löschen',
                value: _permissions.equipmentDelete,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(equipmentDelete: v)),
                isDangerous: true,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Einsätze ──────────────────────────────────────────────────────
          _PermissionsGroup(
            title: 'Einsätze',
            icon: Icons.local_fire_department,
            iconColor: Colors.red,
            rows: [
              _PermRow(
                label: 'Einsehen',
                value: _permissions.missionView,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(missionView: v)),
              ),
              _PermRow(
                label: 'Bearbeiten',
                value: _permissions.missionEdit,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(missionEdit: v)),
              ),
              _PermRow(
                label: 'Hinzufügen',
                value: _permissions.missionAdd,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(missionAdd: v)),
              ),
              _PermRow(
                label: 'Löschen',
                value: _permissions.missionDelete,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(missionDelete: v)),
                isDangerous: true,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Prüfungen ─────────────────────────────────────────────────────
          _PermissionsGroup(
            title: 'Prüfungen',
            icon: Icons.fact_check,
            iconColor: Colors.green,
            rows: [
              _PermRow(
                label: 'Einsehen',
                value: _permissions.inspectionView,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(inspectionView: v)),
              ),
              _PermRow(
                label: 'Prüfung durchführen',
                value: _permissions.inspectionPerform,
                onChanged: (v) => setState(() =>
                    _permissions =
                        _permissions.copyWith(inspectionPerform: v)),
              ),
              _PermRow(
                label: 'Bearbeiten',
                value: _permissions.inspectionEdit,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(inspectionEdit: v)),
              ),
              _PermRow(
                label: 'Löschen',
                value: _permissions.inspectionDelete,
                onChanged: (v) => setState(() =>
                    _permissions =
                        _permissions.copyWith(inspectionDelete: v)),
                isDangerous: true,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Reinigung ─────────────────────────────────────────────────────
          _PermissionsGroup(
            title: 'Reinigung',
            icon: Icons.local_laundry_service,
            iconColor: Colors.teal,
            rows: [
              _PermRow(
                label: 'Reinigungsscheine einsehen',
                value: _permissions.cleaningView,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(cleaningView: v)),
              ),
              _PermRow(
                label: 'Reinigungsscheine erstellen',
                value: _permissions.cleaningCreate,
                onChanged: (v) => setState(() =>
                    _permissions = _permissions.copyWith(cleaningCreate: v)),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── Schnellvorlagen ───────────────────────────────────────────────
          _QuickTemplatesSection(
            onApply: (perms) => setState(() => _permissions = perms),
            userFireStation: widget.user.fireStation,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAdminHint() {
    return Scaffold(
      appBar: AppBar(title: Text('Rechte: ${widget.user.name}')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings, size: 64, color: Colors.orange),
              SizedBox(height: 16),
              Text(
                'Administrator',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Administratoren haben automatisch alle Rechte.\nIndividuelle Berechtigungen sind nicht anwendbar.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hilfs-Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _UserInfoCard extends StatelessWidget {
  final UserModel user;
  const _UserInfoCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withOpacity(0.15),
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(user.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${user.email}\n${user.fireStation}'),
        isThreeLine: true,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          child,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PermissionsGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<_PermRow> rows;

  const _PermissionsGroup({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...rows,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDangerous;

  const _PermRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.isDangerous = false,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      title: Text(
        label,
        style: TextStyle(
          color: isDangerous && value ? Colors.red : null,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: isDangerous ? Colors.red : null,
    );
  }
}

// ─── Schnellvorlagen ──────────────────────────────────────────────────────────

class _QuickTemplatesSection extends StatelessWidget {
  final ValueChanged<UserPermissions> onApply;
  final String userFireStation;

  const _QuickTemplatesSection({
    required this.onApply,
    required this.userFireStation,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Schnellvorlagen',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Wende eine Vorlage an und passe anschließend Details an.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TemplateChip(
                  label: 'Nur lesen',
                  icon: Icons.visibility,
                  onTap: () => onApply(const UserPermissions(
                    equipmentView: true,
                    missionView: true,
                    inspectionView: true,
                    cleaningView: true,
                  )),
                ),
                _TemplateChip(
                  label: 'Ortszeugwart',
                  icon: Icons.manage_accounts,
                  onTap: () => onApply(const UserPermissions(
                    equipmentView: true,
                    equipmentEdit: true,
                    equipmentAdd: true,
                    missionView: true,
                    missionAdd: true,
                    inspectionView: true,
                    inspectionPerform: true,
                    inspectionEdit: true,
                    cleaningView: true,
                    cleaningCreate: true,
                  )),
                ),
                _TemplateChip(
                  label: 'Hygieneeinheit',
                  icon: Icons.local_laundry_service,
                  onTap: () => onApply(UserPermissions(
                    visibleFireStations: const ['*'],
                    equipmentView: true,
                    equipmentEdit: true,
                    missionView: true,
                    missionAdd: true,
                    inspectionView: true,
                    inspectionPerform: true,
                    cleaningView: true,
                    cleaningCreate: true,
                  )),
                ),
                _TemplateChip(
                  label: 'Alle Rechte',
                  icon: Icons.admin_panel_settings,
                  color: Colors.deepOrange,
                  onTap: () => onApply(UserPermissions(
                    visibleFireStations: const ['*'],
                    equipmentView: true,
                    equipmentEdit: true,
                    equipmentAdd: true,
                    equipmentDelete: true,
                    missionView: true,
                    missionEdit: true,
                    missionAdd: true,
                    missionDelete: true,
                    inspectionView: true,
                    inspectionEdit: true,
                    inspectionDelete: true,
                    inspectionPerform: true,
                    cleaningView: true,
                    cleaningCreate: true,
                  )),
                ),
                _TemplateChip(
                  label: 'Zurücksetzen',
                  icon: Icons.restart_alt,
                  color: Colors.grey,
                  onTap: () => onApply(UserPermissions.defaultUser()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _TemplateChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(color: c)),
      onPressed: onTap,
    );
  }
}
