// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/theme_services.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();

  // Benachrichtigungseinstellungen
  bool _notifyInspectionDue = true;
  bool _notifyStatusChange = true;
  bool _notifyNewEquipment = true;

  // Anzeigeeinstellungen
  bool _groupByOwner = true;
  bool _showExpiredFirst = true;

  // Sicherheitseinstellungen
  bool _confirmOnDelete = true;
  bool _showNfcTags = true;

  // App-Info
  String _appVersion = '';
  String _appBuild = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppInfo();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // Benachrichtigungen
      _notifyInspectionDue = prefs.getBool('notify_inspection_due') ?? true;
      _notifyStatusChange = prefs.getBool('notify_status_change') ?? true;
      _notifyNewEquipment = prefs.getBool('notify_new_equipment') ?? true;

      // Anzeige
      _groupByOwner = prefs.getBool('group_by_owner') ?? true;
      _showExpiredFirst = prefs.getBool('show_expired_first') ?? true;

      // Sicherheit
      _confirmOnDelete = prefs.getBool('confirm_on_delete') ?? true;
      _showNfcTags = prefs.getBool('show_nfc_tags') ?? true;
    });
  }

  Future<void> _loadAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
        _appBuild = packageInfo.buildNumber;
      });
    } catch (e) {
      setState(() {
        _appVersion = '1.0.0';
        _appBuild = '1';
      });
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Erscheinungsbild-Karte
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Erscheinungsbild',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Theme-Modus'),
                  const SizedBox(height: 8),
                  _buildThemeOptionTile(
                    context,
                    ThemeOption.system,
                    themeService,
                    'Systemstandard',
                    Icons.brightness_auto,
                  ),
                  _buildThemeOptionTile(
                    context,
                    ThemeOption.light,
                    themeService,
                    'Hell',
                    Icons.brightness_high,
                  ),
                  _buildThemeOptionTile(
                    context,
                    ThemeOption.dark,
                    themeService,
                    'Dunkel',
                    Icons.brightness_2,
                  ),
                  const Divider(height: 32),
                  const Text('Farbschema'),
                  const SizedBox(height: 8),
                  _buildThemeOptionTile(
                    context,
                    ThemeOption.blue,
                    themeService,
                    'Blau',
                    Icons.circle,
                    iconColor: Colors.blue,
                  ),
                  _buildThemeOptionTile(
                    context,
                    ThemeOption.green,
                    themeService,
                    'Grün',
                    Icons.circle,
                    iconColor: Colors.green,
                  ),
                  _buildThemeOptionTile(
                    context,
                    ThemeOption.orange,
                    themeService,
                    'Orange',
                    Icons.circle,
                    iconColor: Colors.orange,
                  ),
                ],
              ),
            ),
          ),

          // Benachrichtigungen-Karte
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Benachrichtigungen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Überfällige Prüfungen'),
                    subtitle: const Text('Benachrichtigung, wenn Prüfungen überfällig sind'),
                    value: _notifyInspectionDue,
                    onChanged: (value) {
                      setState(() {
                        _notifyInspectionDue = value;
                        _saveSetting('notify_inspection_due', value);
                      });
                    },
                    secondary: const Icon(Icons.warning),
                  ),
                  SwitchListTile(
                    title: const Text('Statusänderungen'),
                    subtitle: const Text('Benachrichtigung bei Statusänderungen der Einsatzkleidung'),
                    value: _notifyStatusChange,
                    onChanged: (value) {
                      setState(() {
                        _notifyStatusChange = value;
                        _saveSetting('notify_status_change', value);
                      });
                    },
                    secondary: const Icon(Icons.swap_horiz),
                  ),
                  SwitchListTile(
                    title: const Text('Neue Einsatzkleidung'),
                    subtitle: const Text('Benachrichtigung, wenn neue Einsatzkleidung hinzugefügt wird'),
                    value: _notifyNewEquipment,
                    onChanged: (value) {
                      setState(() {
                        _notifyNewEquipment = value;
                        _saveSetting('notify_new_equipment', value);
                      });
                    },
                    secondary: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          ),

          // Anzeigeoptionen-Karte
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Anzeigeoptionen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Nach Besitzer gruppieren'),
                    subtitle: const Text('Einsatzkleidung in der Liste nach Besitzer gruppieren'),
                    value: _groupByOwner,
                    onChanged: (value) {
                      setState(() {
                        _groupByOwner = value;
                        _saveSetting('group_by_owner', value);
                      });
                    },
                    secondary: const Icon(Icons.people),
                  ),
                  SwitchListTile(
                    title: const Text('Überfällige zuerst anzeigen'),
                    subtitle: const Text('Ausrüstung mit überfälliger Prüfung zuerst anzeigen'),
                    value: _showExpiredFirst,
                    onChanged: (value) {
                      setState(() {
                        _showExpiredFirst = value;
                        _saveSetting('show_expired_first', value);
                      });
                    },
                    secondary: const Icon(Icons.sort),
                  ),
                ],
              ),
            ),
          ),

          // Sicherheit-Karte
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Datenschutz & Sicherheit',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Löschen bestätigen'),
                    subtitle: const Text('Bestätigungsdialog beim Löschen anzeigen'),
                    value: _confirmOnDelete,
                    onChanged: (value) {
                      setState(() {
                        _confirmOnDelete = value;
                        _saveSetting('confirm_on_delete', value);
                      });
                    },
                    secondary: const Icon(Icons.delete_outline),
                  ),
                  SwitchListTile(
                    title: const Text('NFC-Tags anzeigen'),
                    subtitle: const Text('Vollständige NFC-Tag-IDs in der App anzeigen'),
                    value: _showNfcTags,
                    onChanged: (value) {
                      setState(() {
                        _showNfcTags = value;
                        _saveSetting('show_nfc_tags', value);
                      });
                    },
                    secondary: const Icon(Icons.nfc),
                  ),
                  ListTile(
                    title: const Text('Passwort ändern'),
                    subtitle: Text(user?.email ?? ''),
                    leading: const Icon(Icons.lock_outline),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      // Hier zur Passwortänderungsseite navigieren
                      _showPasswordChangeDialog(context);
                    },
                  ),
                ],
              ),
            ),
          ),

          // App-Info-Karte
          Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App-Informationen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Version'),
                    subtitle: Text('$_appVersion (Build $_appBuild)'),
                    leading: const Icon(Icons.info_outline),
                  ),
                  ListTile(
                    title: const Text('Hilfe & Support'),
                    subtitle: const Text('Dokumentation und Hilfestellung zur App'),
                    leading: const Icon(Icons.help_outline),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, '/help-support');
                    },
                  ),
                  ListTile(
                    title: const Text('Datenschutzerklärung'),
                    subtitle: const Text('Informationen zur Verwendung Ihrer Daten'),
                    leading: const Icon(Icons.privacy_tip_outlined),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pushNamed(context, '/privacy-policy');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Abmelden'),
                    onTap: () async {
                      await _authService.signOut();
                      // StreamBuilder übernimmt automatisch
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOptionTile(
      BuildContext context,
      ThemeOption option,
      ThemeService themeService,
      String title,
      IconData icon, {
        Color? iconColor,
      }) {
    final isSelected = themeService.currentTheme == option;

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).cardColor,
      child: InkWell(
        onTap: () {
          themeService.setTheme(option);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            children: [
              Icon(
                icon,
                color: iconColor ?? Theme.of(context).iconTheme.color,
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const Spacer(),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPasswordChangeDialog(BuildContext context) {
    final TextEditingController _currentPasswordController = TextEditingController();
    final TextEditingController _newPasswordController = TextEditingController();
    final TextEditingController _confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Passwort ändern'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _currentPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Aktuelles Passwort',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _newPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort bestätigen',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Hier die Passwortänderung implementieren
              if (_newPasswordController.text != _confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Die neuen Passwörter stimmen nicht überein'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                User? user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  // Erneut mit aktuellem Passwort anmelden, um Berechtigung zu überprüfen
                  AuthCredential credential = EmailAuthProvider.credential(
                    email: user.email!,
                    password: _currentPasswordController.text,
                  );

                  await user.reauthenticateWithCredential(credential);
                  await user.updatePassword(_newPasswordController.text);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passwort erfolgreich geändert'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Fehler: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Passwort ändern'),
          ),
        ],
      ),
    );
  }
}