// models/user_models.dart

class UserPermissions {
  // Sichtbare Ortswehren (leer = nur eigene, ['*'] = alle)
  final List<String> visibleFireStations;

  // Einsatzkleidung
  final bool equipmentView;
  final bool equipmentEdit;       // Stammdaten: Artikel, Größe, Besitzer, …
  final bool equipmentStatusEdit; // Status manuell ändern (entkoppelt von Edit)
  final bool equipmentAdd;
  final bool equipmentDelete;

  // Einsätze
  final bool missionView;
  final bool missionEdit;
  final bool missionAdd;
  final bool missionDelete;

  // Prüfungen
  final bool inspectionView;
  final bool inspectionEdit;
  final bool inspectionDelete;
  final bool inspectionPerform; // Prüfung durchführen → setzt Status automatisch

  // Reinigung
  final bool cleaningView;
  final bool cleaningCreate;

  const UserPermissions({
    this.visibleFireStations = const [],
    this.equipmentView = false,
    this.equipmentEdit = false,
    this.equipmentStatusEdit = false,
    this.equipmentAdd = false,
    this.equipmentDelete = false,
    this.missionView = false,
    this.missionEdit = false,
    this.missionAdd = false,
    this.missionDelete = false,
    this.inspectionView = false,
    this.inspectionEdit = false,
    this.inspectionDelete = false,
    this.inspectionPerform = false,
    this.cleaningView = false,
    this.cleaningCreate = false,
  });

  /// Admin bekommt alle Rechte automatisch
  factory UserPermissions.admin() {
    return const UserPermissions(
      visibleFireStations: ['*'],
      equipmentView: true,
      equipmentEdit: true,
      equipmentStatusEdit: true,
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
    );
  }

  /// Standard-User: nur Lesezugriff auf eigene Feuerwehr
  factory UserPermissions.defaultUser() {
    return const UserPermissions(
      visibleFireStations: [],
      equipmentView: true,
      missionView: true,
      inspectionView: true,
      cleaningView: true,
    );
  }

  /// Liest flache perm_-Felder direkt aus dem Firestore-Dokument.
  factory UserPermissions.fromMap(Map<String, dynamic> map) {
    return UserPermissions(
      visibleFireStations: List<String>.from(map['visibleFireStations'] ?? []),
      equipmentView: map['perm_equipmentView'] ?? false,
      equipmentEdit: map['perm_equipmentEdit'] ?? false,
      // Rückwärtskompatibilität: alte Dokumente ohne dieses Feld erben es
      // von equipmentEdit, damit bestehende Admins/Zeugwarte nicht gesperrt werden.
      equipmentStatusEdit: map['perm_equipmentStatusEdit'] ?? map['perm_equipmentEdit'] ?? false,
      equipmentAdd: map['perm_equipmentAdd'] ?? false,
      equipmentDelete: map['perm_equipmentDelete'] ?? false,
      missionView: map['perm_missionView'] ?? false,
      missionEdit: map['perm_missionEdit'] ?? false,
      missionAdd: map['perm_missionAdd'] ?? false,
      missionDelete: map['perm_missionDelete'] ?? false,
      inspectionView: map['perm_inspectionView'] ?? false,
      inspectionEdit: map['perm_inspectionEdit'] ?? false,
      inspectionDelete: map['perm_inspectionDelete'] ?? false,
      inspectionPerform: map['perm_inspectionPerform'] ?? false,
      cleaningView: map['perm_cleaningView'] ?? false,
      cleaningCreate: map['perm_cleaningCreate'] ?? false,
    );
  }

  /// Schreibt flache perm_-Felder — passend zu fromMap und saveUserPermissions.
  Map<String, dynamic> toMap() {
    return {
      'visibleFireStations': visibleFireStations,
      'perm_equipmentView': equipmentView,
      'perm_equipmentEdit': equipmentEdit,
      'perm_equipmentStatusEdit': equipmentStatusEdit,
      'perm_equipmentAdd': equipmentAdd,
      'perm_equipmentDelete': equipmentDelete,
      'perm_missionView': missionView,
      'perm_missionEdit': missionEdit,
      'perm_missionAdd': missionAdd,
      'perm_missionDelete': missionDelete,
      'perm_inspectionView': inspectionView,
      'perm_inspectionEdit': inspectionEdit,
      'perm_inspectionDelete': inspectionDelete,
      'perm_inspectionPerform': inspectionPerform,
      'perm_cleaningView': cleaningView,
      'perm_cleaningCreate': cleaningCreate,
    };
  }

  UserPermissions copyWith({
    List<String>? visibleFireStations,
    bool? equipmentView,
    bool? equipmentEdit,
    bool? equipmentStatusEdit,
    bool? equipmentAdd,
    bool? equipmentDelete,
    bool? missionView,
    bool? missionEdit,
    bool? missionAdd,
    bool? missionDelete,
    bool? inspectionView,
    bool? inspectionEdit,
    bool? inspectionDelete,
    bool? inspectionPerform,
    bool? cleaningView,
    bool? cleaningCreate,
  }) {
    return UserPermissions(
      visibleFireStations: visibleFireStations ?? this.visibleFireStations,
      equipmentView: equipmentView ?? this.equipmentView,
      equipmentEdit: equipmentEdit ?? this.equipmentEdit,
      equipmentStatusEdit: equipmentStatusEdit ?? this.equipmentStatusEdit,
      equipmentAdd: equipmentAdd ?? this.equipmentAdd,
      equipmentDelete: equipmentDelete ?? this.equipmentDelete,
      missionView: missionView ?? this.missionView,
      missionEdit: missionEdit ?? this.missionEdit,
      missionAdd: missionAdd ?? this.missionAdd,
      missionDelete: missionDelete ?? this.missionDelete,
      inspectionView: inspectionView ?? this.inspectionView,
      inspectionEdit: inspectionEdit ?? this.inspectionEdit,
      inspectionDelete: inspectionDelete ?? this.inspectionDelete,
      inspectionPerform: inspectionPerform ?? this.inspectionPerform,
      cleaningView: cleaningView ?? this.cleaningView,
      cleaningCreate: cleaningCreate ?? this.cleaningCreate,
    );
  }
}

class UserModel {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String fireStation;
  final bool isApproved;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final UserPermissions permissions;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.fireStation,
    required this.isApproved,
    required this.createdAt,
    this.approvedAt,
    UserPermissions? permissions,
  }) : permissions = permissions ??
            (role == 'admin'
                ? UserPermissions.admin()
                : UserPermissions.defaultUser());

  bool get isAdmin => role == 'admin';

  bool canSeeFireStation(String station) {
    if (isAdmin) return true;
    if (permissions.visibleFireStations.contains('*')) return true;
    if (permissions.visibleFireStations.isEmpty) {
      return station == fireStation;
    }
    return permissions.visibleFireStations.contains(station) ||
        station == fireStation;
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'role': role,
      'fireStation': fireStation,
      'isApproved': isApproved,
      'createdAt': createdAt,
      'approvedAt': approvedAt,
      ...permissions.toMap(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String documentId) {
    final String role = map['role'] ?? '';
    UserPermissions perms;

    if (role == 'admin') {
      perms = UserPermissions.admin();
    } else if (map['perm_equipmentView'] != null) {
      perms = UserPermissions.fromMap(map);
    } else if (map['permissions'] is Map) {
      perms = UserPermissions.fromMap(
          Map<String, dynamic>.from(map['permissions'] as Map));
    } else {
      perms = UserPermissions.defaultUser();
    }

    return UserModel(
      uid: documentId,
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: role,
      fireStation: map['fireStation'] ?? '',
      isApproved: map['isApproved'] ?? false,
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      approvedAt: map['approvedAt']?.toDate(),
      permissions: perms,
    );
  }
}
