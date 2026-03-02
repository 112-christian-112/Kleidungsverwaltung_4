// lib/services/profile_completetion_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Lists/fire_stations.dart';
import '../services/auth_service.dart';

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({Key? key}) : super(key: key);

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final AuthService _authService = AuthService();

  String _selectedRole = '';
  String _selectedFireStation = '';
  bool _isLoading = false;

  final List<String> _roles = [
    'Ortszeugwart',
    'Ortsbrandmeister',
    'Stv. Ortsbrandmeister',
    'Gemeindebrandmeister',
    'Stv. Gemeindebrandmeister',
    'Wäscherei',
    'Gemeindezeugwart',
  ];

  @override
  void initState() {
    super.initState();
    _selectedRole = _roles.first;
    _selectedFireStation = FireStations.all.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _completeProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) return;

      await _authService.updateUserProfile(
        currentUser.uid,
        _nameController.text.trim(),
        _selectedRole,
        _selectedFireStation,
      );

      // watchUserStatus erkennt isProfileComplete: true →
      // StreamBuilder in main.dart wechselt automatisch zu PendingApprovalScreen.
      // KEINE manuelle Navigation — der Screen wird vom StreamBuilder ersetzt.

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil vervollständigen'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => _authService.signOut(),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Abmelden'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bitte vervollständigen Sie Ihr Profil',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Angemeldet als: ${FirebaseAuth.instance.currentUser?.email ?? ''}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Vor- und Nachname',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Bitte geben Sie Ihren Namen ein';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Funktion',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: _roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedRole = v);
                  },
                  validator: (v) => v == null || v.isEmpty
                      ? 'Bitte wählen Sie Ihre Funktion'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedFireStation,
                  decoration: const InputDecoration(
                    labelText: 'Ortsfeuerwehr',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_fire_department),
                  ),
                  items: FireStations.all
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedFireStation = v);
                  },
                  validator: (v) => v == null || v.isEmpty
                      ? 'Bitte wählen Sie Ihre Ortsfeuerwehr'
                      : null,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _completeProfile,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Profil speichern',
                          style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
