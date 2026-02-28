// services/permission_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PermissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Bestehende Methoden
  Future<bool> isAdmin() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      return userData['role'] == 'admin';
    } catch (e) {
      print('Fehler beim Prüfen der Admin-Berechtigung: $e');
      return false;
    }
  }

  // NEUE METHODE: Prüft ob Benutzer zur Hygieneeinheit gehört
  Future<bool> isHygieneUnit() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      return userData['role'] == 'hygiene' || userData['role'] == 'hygiene_unit';
    } catch (e) {
      print('Fehler beim Prüfen der Hygieneeinheit-Berechtigung: $e');
      return false;
    }
  }

  // NEUE METHODE: Prüft ob Benutzer Ortszeugwart ist
  Future<bool> isOrtszeugwart() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      return userData['role'] == 'Ortszeugwart';
    } catch (e) {
      print('Fehler beim Prüfen der Ortszeugwart-Berechtigung: $e');
      return false;
    }
  }

  // NEUE METHODE: Prüft ob Benutzer erweiterte Leserechte hat (Admin oder Hygieneeinheit)
  Future<bool> hasExtendedReadAccess() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      String role = userData['role'] ?? 'user';

      return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit';
    } catch (e) {
      print('Fehler beim Prüfen der erweiterten Leserechte: $e');
      return false;
    }
  }

  // NEUE METHODE: Prüft ob Benutzer Schreibrechte für Ausrüstung hat (nur Admin)
  Future<bool> canEditEquipment() async {
    return await isAdmin();
  }

  // NEUE METHODE: Prüft ob Benutzer Einsätze bearbeiten/löschen kann (nur Admin)
  Future<bool> canEditMissions() async {
    return await isAdmin();
  }

  // NEUE METHODE: Prüft ob Benutzer alle Ausrüstung sehen kann (Admin oder Hygieneeinheit)
  Future<bool> canViewAllEquipment() async {
    return await hasExtendedReadAccess();
  }

  // NEUE METHODE: Prüft ob Benutzer alle Einsätze sehen kann (Admin oder Hygieneeinheit)
  Future<bool> canViewAllMissions() async {
    return await hasExtendedReadAccess();
  }

  // NEUE METHODE: Gibt die Rolle des aktuellen Benutzers zurück
  Future<String> getUserRole() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return 'user';

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return 'user';

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      return userData['role'] ?? 'user';
    } catch (e) {
      print('Fehler beim Abrufen der Benutzerrolle: $e');
      return 'user';
    }
  }

  // Bestehende Methode bleibt unverändert
  Future<String> getUserFireStation() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return '';

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return '';

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      return userData['fireStation'] ?? '';
    } catch (e) {
      print('Fehler beim Abrufen der Feuerwehrstation: $e');
      return '';
    }
  }

  // NEUE METHODE: Bestimmt welche Feuerwehrstationen ein Benutzer sehen kann
  Future<List<String>> getVisibleFireStations() async {
    try {
      final hasExtendedAccess = await hasExtendedReadAccess();

      if (hasExtendedAccess) {
        // Admin und Hygieneeinheit können alle Stationen sehen
        return [
          'Alle', // Spezialwert für "alle anzeigen"
          'Esklum',
          'Breinermoor',
          'Grotegaste',
          'Flachsmeer',
          'Folmhusen',
          'Großwolde',
          'Ihrhove',
          'Ihren',
          'Steenfelde',
          'Völlen',
          'Völlenerfehn',
          'Völlenerkönigsfehn'
        ];
      } else {
        // Normale Benutzer sehen nur ihre eigene Station
        final userStation = await getUserFireStation();
        return userStation.isNotEmpty ? [userStation] : [];
      }
    } catch (e) {
      print('Fehler beim Abrufen der sichtbaren Feuerwehrstationen: $e');
      return [];
    }
  }

  // ERWEITERTE METHODE: Prüft ob Benutzer eine bestimmte Aktion durchführen kann
  Future<bool> canPerformAction(String action) async {
    final role = await getUserRole();

    switch (action) {
      case 'view_all_equipment':
        return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit';
      case 'view_all_missions':
        return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit';
      case 'update_check_date':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';

      case 'edit_equipment':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';
      case 'delete_equipment':
      case 'add_equipment':
      return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';

      case 'edit_missions':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';
      case 'delete_missions':
        return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart';
      case 'add_missions':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';

      case 'update_equipment_status':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';
      case 'update_wash_cycles':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';
      case 'update_check_date':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';

    // NEUE PRÜFUNGSBERECHTIGUNGEN
      case 'perform_inspections':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';
      case 'edit_inspections':
        return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart';
      case 'delete_inspections':
        return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart';
      case 'view_all_inspections':
        return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart';

      case 'view_cleaning_receipts':
        return  role == 'admin' || role == 'hygiene' || role == 'hygiene_unit' || role == 'Ortszeugwart' || role == 'Ortsbrandmeister';
      case 'generate_cleaning_receipts':
        return role == 'admin' || role == 'hygiene' || role == 'hygiene_unit';

      default:
        return false;
    }
  }

  // NEUE METHODE: Gibt benutzerfreundlichen Namen für Rollen zurück
  String getRoleDisplayName(String role) {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'hygiene':
        return 'Hygieneeinheit';
      case 'hygiene_unit':
        return 'Hygieneeinheit';
      case 'Ortszeugwart':
        return 'Ortszeugwart';
      case 'user':
      default:
        return 'Benutzer';
    }
  }

  // NEUE METHODE: Prüft ob Benutzer Berechtigung hat, die Rolle anderer zu sehen
  Future<bool> canViewUserRoles() async {
    return await isAdmin();
  }
}