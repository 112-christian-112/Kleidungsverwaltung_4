// services/permission_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_models.dart';

/// Zentraler Berechtigungs-Service.
///
/// Jede public-Methode macht intern **einen** Firestore-Read via
/// [_fetchCurrentUser] und leitet daraus das Ergebnis ab.
/// Screens, die mehrere Informationen gleichzeitig brauchen, sollen
/// stattdessen direkt [getCurrentUser] aufrufen und das [UserModel]
/// lokal auswerten — so spart man mehrere sequenzielle Reads.
class PermissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Interner Basis-Read ───────────────────────────────────────────────────

  /// Lädt das [UserModel] des aktuell eingeloggten Benutzers.
  /// Gibt `null` zurück wenn kein User eingeloggt ist oder das Dokument
  /// nicht existiert.
  Future<UserModel?> _fetchCurrentUser() async {
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) return null;

      final doc = await _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .get();
      if (!doc.exists) return null;

      return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      print('PermissionService._fetchCurrentUser: $e');
      return null;
    }
  }

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Gibt das vollständige [UserModel] zurück.
  /// **Bevorzugte Methode** für Screens, die mehrere Permissions brauchen.
  Future<UserModel?> getCurrentUser() => _fetchCurrentUser();

  // Basis-Infos
  Future<bool> isAdmin() async => (await _fetchCurrentUser())?.isAdmin ?? false;
  Future<String> getUserRole() async =>
      (await _fetchCurrentUser())?.role ?? 'user';
  Future<String> getUserFireStation() async =>
      (await _fetchCurrentUser())?.fireStation ?? '';

  // ── Berechtigungs-Shortcuts (jeweils 1 Firestore-Read) ───────────────────

  Future<UserPermissions> _permissions() async {
    final user = await _fetchCurrentUser();
    if (user == null) return const UserPermissions();
    if (user.isAdmin) return UserPermissions.admin();
    return user.permissions;
  }

  // Einsatzkleidung
  Future<bool> canViewEquipment() async => (await _permissions()).equipmentView;
  Future<bool> canEditEquipment() async => (await _permissions()).equipmentEdit;
  Future<bool> canAddEquipment() async => (await _permissions()).equipmentAdd;
  Future<bool> canDeleteEquipment() async =>
      (await _permissions()).equipmentDelete;

  // Einsätze
  Future<bool> canViewMissions() async => (await _permissions()).missionView;
  Future<bool> canEditMissions() async => (await _permissions()).missionEdit;
  Future<bool> canAddMissions() async => (await _permissions()).missionAdd;
  Future<bool> canDeleteMissions() async => (await _permissions()).missionDelete;

  // Prüfungen
  Future<bool> canViewInspections() async =>
      (await _permissions()).inspectionView;
  Future<bool> canEditInspections() async =>
      (await _permissions()).inspectionEdit;
  Future<bool> canDeleteInspections() async =>
      (await _permissions()).inspectionDelete;
  Future<bool> canPerformInspections() async =>
      (await _permissions()).inspectionPerform;

  // Reinigung
  Future<bool> canViewCleaning() async => (await _permissions()).cleaningView;
  Future<bool> canCreateCleaning() async =>
      (await _permissions()).cleaningCreate;

  // ── Sichtbare Ortswehren ──────────────────────────────────────────────────

  Future<List<String>> getVisibleFireStations() async {
    final user = await _fetchCurrentUser();
    if (user == null) return [];
    if (user.isAdmin || user.permissions.visibleFireStations.contains('*')) {
      return ['*']; // alle
    }
    return <String>{user.fireStation, ...user.permissions.visibleFireStations}
        .toList();
  }

  Future<bool> canSeeFireStation(String station) async {
    final user = await _fetchCurrentUser();
    if (user == null) return false;
    return user.canSeeFireStation(station);
  }

  // ── Admin: Permissions eines anderen Users speichern ─────────────────────

  /// Speichert die Permissions als flache perm_-Felder direkt im
  /// Firestore-Dokument — konsistent mit [UserPermissions.fromMap].
  Future<void> saveUserPermissions(
      String userId, UserPermissions permissions) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .update(permissions.toMap()); // toMap() liefert flache perm_-Felder
  }

  Future<bool> canViewUserRoles() async => isAdmin();

  // ── Altes String-basiertes Interface (Kompatibilität) ────────────────────
  //
  // Screens die noch nicht migriert sind, können weiterhin
  // canPerformAction('edit_equipment') aufrufen.

  Future<bool> canPerformAction(String action) async {
    final perms = await _permissions();
    switch (action) {
      case 'view_equipment':
        return perms.equipmentView;
      case 'edit_equipment':
        return perms.equipmentEdit;
      case 'add_equipment':
        return perms.equipmentAdd;
      case 'delete_equipment':
        return perms.equipmentDelete;
      case 'view_missions':
        return perms.missionView;
      case 'edit_missions':
        return perms.missionEdit;
      case 'add_missions':
        return perms.missionAdd;
      case 'delete_missions':
        return perms.missionDelete;
      case 'view_inspections':
        return perms.inspectionView;
      case 'edit_inspections':
        return perms.inspectionEdit;
      case 'delete_inspections':
        return perms.inspectionDelete;
      case 'perform_inspections':
        return perms.inspectionPerform;
      case 'view_cleaning':
        return perms.cleaningView;
      case 'create_cleaning':
        return perms.cleaningCreate;
      default:
        return false;
    }
  }

  /// Kompatibilitäts-Methode für Screens, die noch canViewAllMissions() nutzen.
  Future<bool> canViewAllMissions() async {
    final user = await _fetchCurrentUser();
    if (user == null) return false;
    if (user.isAdmin) return true;
    return user.permissions.visibleFireStations.contains('*');
  }
}
