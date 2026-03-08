// services/permission_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_models.dart';

/// Zentraler Berechtigungs-Service mit In-Memory-Cache.
///
/// [_fetchCurrentUser] macht pro Cache-Miss einen Firestore-Read und
/// hält das Ergebnis für [_cacheTtl] im Speicher. Alle public-Methoden
/// profitieren automatisch vom Cache.
///
/// Cache wird invalidiert bei:
/// - [invalidateCache] manuell aufrufen (z.B. nach Profil-Update)
/// - Automatisch nach [_cacheTtl] (Standard: 60 Sekunden)
/// - Automatisch bei Benutzerwechsel (andere UID)
class PermissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Cache ─────────────────────────────────────────────────────────────────

  static const Duration _cacheTtl = Duration(seconds: 60);

  UserModel? _cachedUser;
  DateTime? _cacheTimestamp;
  String? _cachedUid;

  bool get _isCacheValid {
    if (_cachedUser == null || _cacheTimestamp == null || _cachedUid == null) {
      return false;
    }
    final currentUid = _auth.currentUser?.uid;
    if (currentUid != _cachedUid) return false;
    return DateTime.now().difference(_cacheTimestamp!) < _cacheTtl;
  }

  /// Cache manuell leeren — aufrufen wenn das eigene Profil geändert wurde
  /// (z.B. nach Rolle/Station-Update durch Admin).
  void invalidateCache() {
    _cachedUser = null;
    _cacheTimestamp = null;
    _cachedUid = null;
  }

  // ── Interner Basis-Read ───────────────────────────────────────────────────

  Future<UserModel?> _fetchCurrentUser() async {
    // Cache-Treffer: direkt zurückgeben, kein Firestore-Read
    if (_isCacheValid) return _cachedUser;

    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        invalidateCache();
        return null;
      }

      final doc = await _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .get();

      if (!doc.exists) {
        invalidateCache();
        return null;
      }

      final user =
          UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);

      // Im Cache speichern
      _cachedUser = user;
      _cacheTimestamp = DateTime.now();
      _cachedUid = firebaseUser.uid;

      return user;
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

  // ── Berechtigungs-Shortcuts (nutzen jetzt den Cache) ─────────────────────

  Future<UserPermissions> _permissions() async {
    final user = await _fetchCurrentUser();
    if (user == null) return const UserPermissions();
    if (user.isAdmin) return UserPermissions.admin();
    return user.permissions;
  }

  // Einsatzkleidung
  Future<bool> canViewEquipment() async => (await _permissions()).equipmentView;
  Future<bool> canEditEquipment() async => (await _permissions()).equipmentEdit;
  Future<bool> canEditEquipmentStatus() async => (await _permissions()).equipmentStatusEdit;
  Future<bool> canAddEquipment() async => (await _permissions()).equipmentAdd;
  Future<bool> canDeleteEquipment() async => (await _permissions()).equipmentDelete;

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
      return ['*'];
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
  ///
  /// Invalidiert den Cache automatisch wenn die eigenen Permissions
  /// geändert wurden.
  Future<void> saveUserPermissions(
      String userId, UserPermissions permissions) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .update(permissions.toMap());

    // Cache leeren wenn die eigenen Permissions geändert wurden
    if (userId == _auth.currentUser?.uid) {
      invalidateCache();
    }
  }

  Future<bool> canViewUserRoles() async => isAdmin();

  // ── Altes String-basiertes Interface (Kompatibilität) ────────────────────

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
