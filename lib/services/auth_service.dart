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
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e.code));
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
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e.code));
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ── Passwort zurücksetzen ──────────────────────────────────────────────────

  /// Sendet eine Passwort-Reset-E-Mail an [email].
  /// Wirft eine verständliche Exception wenn die E-Mail nicht registriert ist.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e.code));
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // ── Passwort ändern ───────────────────────────────────────────────────────

  /// Ändert das Passwort des aktuell eingeloggten Nutzers.
  /// Erfordert eine vorherige Re-Authentifizierung via [currentPassword].
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kein Benutzer angemeldet');

    try {
      // Re-Authentifizierung erforderlich für sicherheitsrelevante Aktionen
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e.code));
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

  // ── Live-Status Stream ────────────────────────────────────────────────────

  /// Reagiert sofort auf Firestore-Änderungen — z.B. wenn Admin freigibt.
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

  // ── Admin-Aktionen ────────────────────────────────────────────────────────

  Future<void> approveUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'isApproved': true,
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'isApproved': false,
      'approvedAt': null,
    });
  }

  Future<void> updateUserProfile({
    required String userId,
    required String name,
    required String role,
    required String fireStation,
  }) async {
    await _firestore.collection('users').doc(userId).update({
      'name': name,
      'role': role,
      'fireStation': fireStation,
    });
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

  /// Löscht nur das Firestore-Dokument.
  /// Der Firebase-Auth-Account bleibt bestehen (serverseitige Cloud Function
  /// oder manuelles Löschen in der Firebase Console erforderlich).
  Future<void> deleteUser(String userId) async {
    await _firestore.collection('users').doc(userId).delete();
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  /// Übersetzt FirebaseAuthException-Codes in verständliche deutsche Meldungen.
  String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Kein Konto mit dieser E-Mail-Adresse gefunden.';
      case 'wrong-password':
        return 'Falsches Passwort. Bitte erneut versuchen.';
      case 'invalid-credential':
        return 'E-Mail oder Passwort ist falsch.';
      case 'email-already-in-use':
        return 'Diese E-Mail-Adresse ist bereits registriert.';
      case 'weak-password':
        return 'Das Passwort ist zu schwach (mindestens 6 Zeichen).';
      case 'invalid-email':
        return 'Die E-Mail-Adresse ist ungültig.';
      case 'too-many-requests':
        return 'Zu viele Versuche. Bitte kurz warten und erneut versuchen.';
      case 'requires-recent-login':
        return 'Bitte erneut anmelden und dann noch einmal versuchen.';
      case 'network-request-failed':
        return 'Keine Internetverbindung. Bitte Verbindung prüfen.';
      default:
        return 'Authentifizierungsfehler ($code).';
    }
  }
}
