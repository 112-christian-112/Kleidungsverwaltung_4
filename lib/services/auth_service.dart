// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_models.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Auth-State Stream
  Stream<User?> get user => _auth.authStateChanges();

  // Aktueller Benutzer
  User? get currentUser => _auth.currentUser;

  // ── Anmelden ──────────────────────────────────────────────────────────────
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ── Registrieren ──────────────────────────────────────────────────────────
  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Firestore-Dokument anlegen
      await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
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

  // ── Abmelden ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ── Live-Status Stream (ersetzt checkUserStatus Future) ───────────────────
  // Reagiert sofort auf Firestore-Änderungen — z.B. wenn Admin freigibt.
  Stream<Map<String, dynamic>> watchUserStatus(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) {
        return {
          'exists': false,
          'isApproved': false,
          'isProfileComplete': false,
        };
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

  // ── Einmaliger Status-Check (für Kompatibilität) ──────────────────────────
  Future<Map<String, dynamic>> checkUserStatus(String userId) async {
    try {
      final doc =
          await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        return {
          'exists': false,
          'isApproved': false,
          'isProfileComplete': false
        };
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
    } catch (e) {
      return {
        'exists': false,
        'isApproved': false,
        'isProfileComplete': false
      };
    }
  }

  // ── Benutzerprofil aktualisieren ──────────────────────────────────────────
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

  // ── Benutzer genehmigen ───────────────────────────────────────────────────
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

  // ── Benutzer ablehnen ─────────────────────────────────────────────────────
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

  // ── Benutzer löschen ──────────────────────────────────────────────────────
  Future<void> deleteUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
    } catch (e) {
      throw Exception('Fehler beim Löschen des Benutzers: $e');
    }
  }

  // ── Alle Benutzer (Admin) ─────────────────────────────────────────────────
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
}
