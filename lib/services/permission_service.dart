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
  Future<bool> canCreateCleaning() async => (await _permissions()).cleaningCreate;

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

  Future<void> saveUserPermissions(
      String userId, UserPermissions permissions) async {
    await _firestore.collection('users').doc(userId).update(
          permissions.toMap(),
        );
  }

  Future<bool> canViewUserRoles() async => isAdmin();

  // ── Altes String-basiertes Interface (Kompatibilität) ────────────────────
  //
  // Screens die noch nicht migriert sind, können weiterhin
  // canPerformAction('edit_equipment') aufrufen. Neue Screens sollen
  // stattdessen getCurrentUser() + UserModel-Properties verwenden.

  Future<bool> canPerformAction(String action) async {
    final p = await _permissions();
    switch (action) {
      case 'view_all_equipment':
      case 'view_equipment':
        return p.equipmentView;
      case 'edit_equipment':
        return p.equipmentEdit;
      case 'add_equipment':
        return p.equipmentAdd;
      case 'delete_equipment':
        return p.equipmentDelete;
      case 'view_all_missions':
      case 'view_missions':
        return p.missionView;
      case 'edit_missions':
        return p.missionEdit;
      case 'add_missions':
        return p.missionAdd;
      case 'delete_missions':
        return p.missionDelete;
      case 'view_all_inspections':
      case 'view_inspections':
        return p.inspectionView;
      case 'edit_inspections':
        return p.inspectionEdit;
      case 'delete_inspections':
        return p.inspectionDelete;
      case 'perform_inspections':
        return p.inspectionPerform;
      case 'view_cleaning_receipts':
        return p.cleaningView;
      case 'generate_cleaning_receipts':
        return p.cleaningCreate;
      case 'update_equipment_status':
      case 'update_wash_cycles':
      case 'update_check_date':
        return p.equipmentEdit;
      default:
        return false;
    }
  }

  // ── Alte rollenbasierte Methoden (Kompatibilität) ─────────────────────────
  //
  // Diese Methoden existieren noch, damit Screens die noch nicht
  // umgestellt wurden nicht brechen. Sie lesen intern über das neue
  // UserModel — kein direkter Rollen-String-Vergleich mehr.

  /// @deprecated Nutze stattdessen getCurrentUser() und user.isAdmin
  Future<bool> isHygieneUnit() async {
    final user = await _fetchCurrentUser();
    // Hygieneeinheit hat cleaningCreate-Recht aber ist kein Admin
    return user != null &&
        !user.isAdmin &&
        user.permissions.cleaningCreate == true;
  }

  /// @deprecated Nutze stattdessen getCurrentUser() und user.permissions
  Future<bool> isOrtszeugwart() async {
    final user = await _fetchCurrentUser();
    // Ortszeugwart: hat Equipment-Edit-Recht aber ist kein Admin
    return user != null &&
        !user.isAdmin &&
        user.permissions.equipmentEdit == true;
  }

  /// @deprecated Nutze stattdessen canViewEquipment()
  Future<bool> hasExtendedReadAccess() async {
    final user = await _fetchCurrentUser();
    if (user == null) return false;
    return user.isAdmin || user.permissions.equipmentView;
  }

  /// @deprecated Nutze stattdessen canViewEquipment()
  Future<bool> canViewAllEquipment() async => canViewEquipment();

  /// @deprecated Nutze stattdessen canViewMissions()
  Future<bool> canViewAllMissions() async => canViewMissions();

  // ── Hilfsmethode ─────────────────────────────────────────────────────────

  String getRoleDisplayName(String role) {
    switch (role) {
      case 'admin':
        return 'Administrator';
      default:
        return 'Benutzer';
    }
  }
}
