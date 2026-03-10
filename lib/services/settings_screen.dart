// screens/settings_screen.dart
//
// Überarbeiteter Settings Screen.
// Erscheinungsbild: Modus (Hell/System/Dunkel) und Akzentfarbe sind
// klar getrennte Bereiche — keine einzelne Liste mehr, die beides mischt.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/theme_services.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();

  // App-Info
  String _appVersion = '';
  String _appBuild = '';

  // Benachrichtigungen
  bool _notifyInspectionDue = true;
  bool _notifyStatusChange = true;
  bool _notifyNewEquipment = true;

  // Anzeige
  bool _groupByOwner = true;
  bool _showExpiredFirst = true;

  // Sicherheit
  bool _confirmOnDelete = true;
  bool _showNfcTags = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppInfo();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifyInspectionDue = prefs.getBool('notify_inspection_due') ?? true;
      _notifyStatusChange  = prefs.getBool('notify_status_change')  ?? true;
      _notifyNewEquipment  = prefs.getBool('notify_new_equipment')   ?? true;
      _groupByOwner        = prefs.getBool('group_by_owner')         ?? true;
      _showExpiredFirst    = prefs.getBool('show_expired_first')     ?? true;
      _confirmOnDelete     = prefs.getBool('confirm_on_delete')      ?? true;
      _showNfcTags         = prefs.getBool('show_nfc_tags')          ?? true;
    });
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = info.version;
        _appBuild   = info.buildNumber;
      });
    } catch (_) {
      setState(() { _appVersion = '1.0.0'; _appBuild = '1'; });
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // ── Passwort ändern ────────────────────────────────────────────────────────

  Future<void> _showPasswordChangeDialog(BuildContext context) async {
    final currentPw = TextEditingController();
    final newPw     = TextEditingController();
    final confirmPw = TextEditingController();

    // Messenger vor dem Dialog extrahieren — context ist nach await ggf. nicht mehr mounted
    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (dialogContext) => _PasswordChangeDialog(
        currentPw: currentPw,
        newPw: newPw,
        confirmPw: confirmPw,
        authService: _authService,
        messenger: messenger,
      ),
    );

    currentPw.dispose();
    newPw.dispose();
    confirmPw.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _AppearanceCard(themeService: themeService),
          const SizedBox(height: 12),
          _NotificationsCard(
            notifyInspectionDue: _notifyInspectionDue,
            notifyStatusChange:  _notifyStatusChange,
            notifyNewEquipment:  _notifyNewEquipment,
            onChanged: (key, value) {
              setState(() {
                if (key == 'notify_inspection_due') _notifyInspectionDue = value;
                if (key == 'notify_status_change')  _notifyStatusChange  = value;
                if (key == 'notify_new_equipment')  _notifyNewEquipment  = value;
              });
              _saveSetting(key, value);
            },
          ),
          const SizedBox(height: 12),
          _DisplayCard(
            groupByOwner:     _groupByOwner,
            showExpiredFirst: _showExpiredFirst,
            onChanged: (key, value) {
              setState(() {
                if (key == 'group_by_owner')      _groupByOwner     = value;
                if (key == 'show_expired_first')  _showExpiredFirst = value;
              });
              _saveSetting(key, value);
            },
          ),
          const SizedBox(height: 12),
          _SecurityCard(
            confirmOnDelete: _confirmOnDelete,
            showNfcTags:     _showNfcTags,
            onChanged: (key, value) {
              setState(() {
                if (key == 'confirm_on_delete') _confirmOnDelete = value;
                if (key == 'show_nfc_tags')     _showNfcTags     = value;
              });
              _saveSetting(key, value);
            },
            onChangePassword: () => _showPasswordChangeDialog(context),
          ),
          const SizedBox(height: 12),
          _AppInfoCard(
            appVersion: _appVersion,
            appBuild:   _appBuild,
            onSignOut: () => _authService.signOut(),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ERSCHEINUNGSBILD
// ════════════════════════════════════════════════════════════════════════════

class _AppearanceCard extends StatelessWidget {
  final ThemeService themeService;
  const _AppearanceCard({required this.themeService});

  // Die drei Helligkeits-Optionen
  static const _brightnessModes = [
    (BrightnessMode.light,  'Hell',        Icons.light_mode_outlined),
    (BrightnessMode.system, 'Automatisch', Icons.brightness_auto),
    (BrightnessMode.dark,   'Dunkel',      Icons.dark_mode_outlined),
  ];

  // Akzentfarben: (AccentColor, Label, Farbe)
  static const _colorOptions = [
    (AccentColor.red,    'Rot',    Color(0xFFCC2222)),
    (AccentColor.blue,   'Blau',   Color(0xFF0055CC)),
    (AccentColor.green,  'Grün',   Color(0xFF1A6B2E)),
    (AccentColor.orange, 'Orange', Color(0xFFB85000)),
  ];

  // Aktiver Helligkeitsmodus
  BrightnessMode _activeBrightness() => themeService.brightnessMode;

  // Aktive Akzentfarbe
  AccentColor _activeColor() => themeService.accentColor;

  // Helligkeit setzen — Farbe bleibt unberührt
  void _setBrightness(BrightnessMode mode) {
    themeService.setBrightness(mode);
  }

  // Farbe setzen — Helligkeit bleibt unberührt
  void _setColor(BuildContext context, AccentColor color) {
    themeService.setAccent(color);
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final BrightnessMode activeBri = _activeBrightness();
    final AccentColor    activeCol = _activeColor();

    return _SettingsCard(
      title: 'Erscheinungsbild',
      icon: Icons.palette_outlined,
      children: [

        // ── 1. Helligkeit ──────────────────────────────────────────────────
        _sectionLabel(context, 'Helligkeit'),
        const SizedBox(height: 10),
        Row(
          children: _brightnessModes.map((m) {
            final (mode, label, icon) = m;
            final selected = activeBri == mode;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _BrightnessButton(
                  label: label,
                  icon: icon,
                  selected: selected,
                  onTap: () => _setBrightness(mode),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // ── 2. Akzentfarbe ─────────────────────────────────────────────────
        _sectionLabel(context, 'Akzentfarbe'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _colorOptions.map((c) {
            final (accent, label, color) = c;
            final selected = activeCol == accent;
            return _ColorDot(
              label: label,
              color: color,
              selected: selected,
              onTap: () => _setColor(context, accent),
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        // ── Vorschau-Hinweis ───────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activeBri == BrightnessMode.system
                      ? 'Automatisch: folgt der Systemeinstellung des Geräts.'
                      : 'Akzentfarbe + ${activeBri == BrightnessMode.dark ? "Dunkel" : "Hell"}-Modus aktiv.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Helligkeit-Button ─────────────────────────────────────────────────────────

class _BrightnessButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BrightnessButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Farbpunkt ─────────────────────────────────────────────────────────────────

class _ColorDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 3,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 24)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BENACHRICHTIGUNGEN
// ════════════════════════════════════════════════════════════════════════════

class _NotificationsCard extends StatelessWidget {
  final bool notifyInspectionDue;
  final bool notifyStatusChange;
  final bool notifyNewEquipment;
  final void Function(String key, bool value) onChanged;

  const _NotificationsCard({
    required this.notifyInspectionDue,
    required this.notifyStatusChange,
    required this.notifyNewEquipment,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Benachrichtigungen',
      icon: Icons.notifications_outlined,
      children: [
        _SwitchTile(
          title: 'Überfällige Prüfungen',
          subtitle: 'Wenn Prüfungen überfällig werden',
          icon: Icons.warning_amber_outlined,
          value: notifyInspectionDue,
          onChanged: (v) => onChanged('notify_inspection_due', v),
        ),
        _SwitchTile(
          title: 'Statusänderungen',
          subtitle: 'Bei Statusänderungen der Einsatzkleidung',
          icon: Icons.swap_horiz,
          value: notifyStatusChange,
          onChanged: (v) => onChanged('notify_status_change', v),
        ),
        _SwitchTile(
          title: 'Neue Einsatzkleidung',
          subtitle: 'Wenn neue Kleidung hinzugefügt wird',
          icon: Icons.add_circle_outline,
          value: notifyNewEquipment,
          onChanged: (v) => onChanged('notify_new_equipment', v),
          isLast: true,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ANZEIGEOPTIONEN
// ════════════════════════════════════════════════════════════════════════════

class _DisplayCard extends StatelessWidget {
  final bool groupByOwner;
  final bool showExpiredFirst;
  final void Function(String key, bool value) onChanged;

  const _DisplayCard({
    required this.groupByOwner,
    required this.showExpiredFirst,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Anzeige',
      icon: Icons.tune_outlined,
      children: [
        _SwitchTile(
          title: 'Nach Besitzer gruppieren',
          subtitle: 'Kleidung in der Liste nach Besitzer sortieren',
          icon: Icons.people_outline,
          value: groupByOwner,
          onChanged: (v) => onChanged('group_by_owner', v),
        ),
        _SwitchTile(
          title: 'Überfällige zuerst',
          subtitle: 'Ausrüstung mit überfälliger Prüfung oben anzeigen',
          icon: Icons.sort,
          value: showExpiredFirst,
          onChanged: (v) => onChanged('show_expired_first', v),
          isLast: true,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SICHERHEIT
// ════════════════════════════════════════════════════════════════════════════

class _SecurityCard extends StatelessWidget {
  final bool confirmOnDelete;
  final bool showNfcTags;
  final void Function(String key, bool value) onChanged;
  final VoidCallback onChangePassword;

  const _SecurityCard({
    required this.confirmOnDelete,
    required this.showNfcTags,
    required this.onChanged,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Sicherheit',
      icon: Icons.shield_outlined,
      children: [
        _SwitchTile(
          title: 'Löschen bestätigen',
          subtitle: 'Sicherheitsabfrage vor dem Löschen anzeigen',
          icon: Icons.delete_outline,
          value: confirmOnDelete,
          onChanged: (v) => onChanged('confirm_on_delete', v),
        ),
        _SwitchTile(
          title: 'NFC-Tag-IDs anzeigen',
          subtitle: 'Tag-IDs in der Detailansicht einblenden',
          icon: Icons.nfc,
          value: showNfcTags,
          onChanged: (v) => onChanged('show_nfc_tags', v),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: Icon(Icons.lock_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          title: const Text('Passwort ändern'),
          trailing: Icon(Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          onTap: onChangePassword,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// APP-INFO
// ════════════════════════════════════════════════════════════════════════════

class _AppInfoCard extends StatelessWidget {
  final String appVersion;
  final String appBuild;
  final VoidCallback onSignOut;

  const _AppInfoCard({
    required this.appVersion,
    required this.appBuild,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SettingsCard(
      title: 'App-Informationen',
      icon: Icons.info_outline,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.tag, color: cs.onSurfaceVariant),
          title: const Text('Version'),
          trailing: Text(
            '$appVersion (Build $appBuild)',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.help_outline, color: cs.onSurfaceVariant),
          title: const Text('Hilfe & Support'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16, color: cs.onSurfaceVariant),
          onTap: () => Navigator.pushNamed(context, '/help-support'),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.privacy_tip_outlined, color: cs.onSurfaceVariant),
          title: const Text('Datenschutzerklärung'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16, color: cs.onSurfaceVariant),
          onTap: () => Navigator.pushNamed(context, '/privacy-policy'),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.logout, color: cs.error),
          title: Text('Abmelden', style: TextStyle(color: cs.error)),
          onTap: onSignOut,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ════════════════════════════════════════════════════════════════════════════

/// Einheitliche Settings-Card mit Titel + Icon-Header
class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// Switch-Tile ohne äußere Card (lebt innerhalb _SettingsCard)
class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          secondary: Icon(icon, color: cs.onSurfaceVariant),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
          activeColor: cs.primary,
        ),
        if (!isLast) const Divider(height: 1, indent: 4),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PASSWORT ÄNDERN — Dialog als StatefulWidget
// Wird als eigenes Widget ausgelagert damit setState() den Ladezustand
// nur innerhalb des Dialogs aktualisiert, nicht den gesamten SettingsScreen.
// ════════════════════════════════════════════════════════════════════════════

class _PasswordChangeDialog extends StatefulWidget {
  final TextEditingController currentPw;
  final TextEditingController newPw;
  final TextEditingController confirmPw;
  final AuthService authService;
  final ScaffoldMessengerState messenger;

  const _PasswordChangeDialog({
    required this.currentPw,
    required this.newPw,
    required this.confirmPw,
    required this.authService,
    required this.messenger,
  });

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _submit() async {
    final currentPwText = widget.currentPw.text;
    final newPwText     = widget.newPw.text;
    final confirmPwText = widget.confirmPw.text;

    if (currentPwText.isEmpty || newPwText.isEmpty) {
      setState(() => _errorMessage = 'Bitte alle Felder ausfüllen.');
      return;
    }
    if (newPwText != confirmPwText) {
      setState(() => _errorMessage = 'Die neuen Passwörter stimmen nicht überein.');
      return;
    }
    if (newPwText.length < 6) {
      setState(() => _errorMessage = 'Das neue Passwort muss mindestens 6 Zeichen lang sein.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await widget.authService.changePassword(
        currentPassword: currentPwText,
        newPassword: newPwText,
      );

      if (mounted) Navigator.pop(context);
      widget.messenger.showSnackBar(
        const SnackBar(
          content: Text('Passwort erfolgreich geändert.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isLoading    = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.currentPw,
            obscureText: true,
            enabled: !_isLoading,
            decoration: const InputDecoration(labelText: 'Aktuelles Passwort'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.newPw,
            obscureText: true,
            enabled: !_isLoading,
            decoration: const InputDecoration(labelText: 'Neues Passwort'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.confirmPw,
            obscureText: true,
            enabled: !_isLoading,
            decoration: const InputDecoration(labelText: 'Passwort bestätigen'),
          ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _errorMessage,
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Ändern'),
        ),
      ],
    );
  }
}
