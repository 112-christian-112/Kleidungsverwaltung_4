// screens/admin/debug_permissions_screen.dart
//
// TEMPORÄRER DEBUG-SCREEN — nach Behebung des Problems wieder entfernen.
// Zeigt den rohen Firestore-Inhalt des eigenen User-Dokuments
// und erlaubt dem Admin, alle User zu migrieren.
//
// Einbinden z.B. in navigation_drawer.dart (nur für Admin sichtbar):
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => const DebugPermissionsScreen()));

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/user_models.dart';

class DebugPermissionsScreen extends StatefulWidget {
  const DebugPermissionsScreen({Key? key}) : super(key: key);

  @override
  State<DebugPermissionsScreen> createState() => _DebugPermissionsScreenState();
}

class _DebugPermissionsScreenState extends State<DebugPermissionsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _ownDoc;
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = true;
  bool _isMigrating = false;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _log = ''; });
    try {
      // Eigenes Dokument laden
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        final doc = await _firestore.collection('users').doc(uid).get();
        _ownDoc = doc.data();
      }

      // Alle User laden
      final snap = await _firestore.collection('users').get();
      _allUsers = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      _log = 'Fehler beim Laden: $e';
    }
    if (mounted) setState(() { _isLoading = false; });
  }

  // Setzt perm_* Felder für alle User die sie noch nicht haben
  Future<void> _migrateAllUsers() async {
    setState(() { _isMigrating = true; _log = ''; });

    int migrated = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final user in _allUsers) {
      final id = user['id'] as String;
      final role = user['role'] ?? '';

      // Admin braucht keine perm_* Felder
      if (role == 'admin') { skipped++; continue; }

      // Schon migriert?
      if (user['perm_equipmentView'] != null) { skipped++; continue; }

      try {
        // Standard-Permissions schreiben
        final perms = UserPermissions.defaultUser().toMap();
        await _firestore.collection('users').doc(id).update(perms);
        migrated++;
        setState(() {
          _log += '✅ ${user['name'] ?? id} → Standard-Rechte gesetzt\n';
        });
      } catch (e) {
        errors.add('$id: $e');
        setState(() { _log += '❌ ${user['name'] ?? id}: $e\n'; });
      }
    }

    setState(() {
      _log += '\n── Fertig: $migrated migriert, $skipped übersprungen ──';
      _isMigrating = false;
    });

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug: Berechtigungen'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // ── Eigenes Dokument ─────────────────────────────────────────
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dein Firestore-Dokument',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        if (_ownDoc == null)
                          const Text('Nicht gefunden!',
                              style: TextStyle(color: Colors.red))
                        else ...[
                          _docRow('role', _ownDoc!['role']),
                          _docRow('isApproved', _ownDoc!['isApproved']),
                          _docRow('fireStation', _ownDoc!['fireStation']),
                          const Divider(),
                          const Text('perm_* Felder:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          _permRow('perm_equipmentView'),
                          _permRow('perm_equipmentEdit'),
                          _permRow('perm_equipmentAdd'),
                          _permRow('perm_equipmentDelete'),
                          _permRow('perm_missionView'),
                          _permRow('perm_missionEdit'),
                          _permRow('perm_missionAdd'),
                          _permRow('perm_missionDelete'),
                          _permRow('perm_inspectionView'),
                          _permRow('perm_inspectionPerform'),
                          _permRow('perm_cleaningView'),
                          _permRow('perm_cleaningCreate'),
                          const Divider(),
                          _docRow('visibleFireStations',
                              _ownDoc!['visibleFireStations']),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Migration ────────────────────────────────────────────────
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Migration',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(
                          '${_allUsers.length} User gefunden. '
                          'User ohne perm_* Felder bekommen Standard-Rechte '
                          '(equipmentView=true, missionView=true, inspectionView=true).',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isMigrating ? null : _migrateAllUsers,
                            icon: _isMigrating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.upgrade),
                            label: Text(_isMigrating
                                ? 'Migriere...'
                                : 'Alle User migrieren'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        if (_log.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _log,
                              style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontFamily: 'monospace',
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Alle User ────────────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Alle User — perm_equipmentView Status',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        ..._allUsers.map((u) {
                          final name = u['name'] ?? u['email'] ?? u['id'];
                          final role = u['role'] ?? '?';
                          final hasPerm = u['perm_equipmentView'];
                          final isAdmin = role == 'admin';

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isAdmin
                                  ? Icons.admin_panel_settings
                                  : hasPerm == true
                                      ? Icons.check_circle
                                      : Icons.cancel,
                              color: isAdmin
                                  ? Colors.orange
                                  : hasPerm == true
                                      ? Colors.green
                                      : Colors.red,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              isAdmin
                                  ? 'Admin — alle Rechte automatisch'
                                  : hasPerm == null
                                      ? '⚠️ perm_* Felder fehlen → Migration nötig!'
                                      : 'perm_equipmentView = $hasPerm',
                            ),
                            trailing: Text(role,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _docRow(String key, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
              width: 160,
              child: Text(key,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12))),
          Expanded(
            child: Text(
              value?.toString() ?? '⚠️ null / fehlt',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: value == null ? Colors.red : Colors.black87,
                fontWeight:
                    value == null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow(String key) {
    final value = _ownDoc?[key];
    return _docRow(key, value);
  }
}
