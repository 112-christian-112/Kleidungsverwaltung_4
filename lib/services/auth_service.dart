// services/auth_service.dart (Ergänzungen)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_models.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Aktueller Benutzer Stream
  Stream<User?> get user => _auth.authStateChanges();

  // Anmelden mit E-Mail und Passwort
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // Registrieren mit E-Mail und Passwort
  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential userCredential =
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Initialen Benutzer erstellen, der noch vervollständigt werden muss
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'email': email,
        'name': '',
        'role': '',
        'fireStation': '',
        'isApproved': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return userCredential;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // Prüfen ob Benutzer in Firestore existiert und freigegeben ist
    Stream<Map<String, dynamic>> watchUserStatus(String userId) {
      return _firestore
          .collection('users')
          .doc(userId)
          .snapshots()
          .map((doc) {
        if (!doc.exists) {
          return {'exists': false, 'isApproved': false, 'isProfileComplete': false};
        }
        final data = doc.data() as Map<String, dynamic>;
        final isProfileComplete =
            (data['name'] as String? ?? '').isNotEmpty &&
                (data['role'] as String? ?? '').isNotEmpty &&
                (data['fireStation'] as String? ?? '').isNotEmpty;
        return {
          'exists': true,
          'isApproved': data['isApproved'] ?? false,
          'isProfileComplete': isProfileComplete,
        };
      });
    }

  // Benutzerprofil aktualisieren
  Future<void> updateUserProfile(
      String userId, String name, String role, String fireStation) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'name': name,
        'role': role,
        'fireStation': fireStation,
      });
    } catch (e) {
      throw Exception('Fehler beim Aktualisieren des Profils: $e');
    }
  }

  // Benutzer genehmigen
  Future<void> approveUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isApproved': true,
        'approvedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Fehler beim Genehmigen des Benutzers: $e');
    }
  }

  // Benutzer ablehnen
  Future<void> rejectUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isApproved': false,
        'approvedAt': null,
      });
    } catch (e) {
      throw Exception('Fehler beim Ablehnen des Benutzers: $e');
    }
  }

  // Benutzer löschen
  Future<void> deleteUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
      // Hinweis: Der Auth-Eintrag wird hier nicht gelöscht
    } catch (e) {
      throw Exception('Fehler beim Löschen des Benutzers: $e');
    }
  }

  // Liste aller Benutzer abrufen (für Admin-Seite)
  Stream<List<UserModel>> getAllUsers() {
    return _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => UserModel.fromMap(
        doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }

  // Abmelden
  Future<void> signOut() async {
    try {
      return await _auth.signOut();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // Aktueller Benutzer
  User? get currentUser => _auth.currentUser;
}
