// lib/services/update_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../changelog.dart'; // lib/changelog.dart

const String kVersionUrl =
    'https://raw.githubusercontent.com/112-christian-112/Kleidungsverwaltung_4/master/version.json';

// ── Models ────────────────────────────────────────────────────────────────────

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String apkUrl;
  final List<VersionEntry> versions;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.apkUrl,
    required this.versions,
  });

  /// Changelog für die neueste Version aus changelog.dart
  List<String> get changelog => _changelogForVersion(latestVersion);
}

class VersionEntry {
  final String version;
  final String apkUrl;

  const VersionEntry({
    required this.version,
    required this.apkUrl,
  });

  /// Datum aus changelog.dart
  String get date {
    final entry = changelog.firstWhere(
      (e) => e.version == version,
      orElse: () => const ChangelogEntry(version: '', date: '', changes: []),
    );
    return entry.date.isNotEmpty ? entry.date : '';
  }

  /// Changelog-Texte aus changelog.dart
  List<String> get changelogItems => _changelogForVersion(version);
}

/// Hilfsfunktion: Changelog-Texte für eine Version aus changelog.dart holen
List<String> _changelogForVersion(String version) {
  final entry = changelog.firstWhere(
    (e) => e.version == version,
    orElse: () => const ChangelogEntry(version: '', date: '', changes: []),
  );
  return entry.changes.map((c) => c.text).toList();
}

// ── Service ───────────────────────────────────────────────────────────────────

class UpdateService {
  static Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http
          .get(Uri.parse(kVersionUrl))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final latestVersion = data['latestVersion'] as String;

      final versions = ((data['versions'] as List<dynamic>?) ?? [])
          .map((v) => VersionEntry(
                version: v['version'] as String,
                apkUrl: v['apkUrl'] as String,
              ))
          .toList();

      final latestEntry = versions.firstWhere(
        (v) => v.version == latestVersion,
        orElse: () => VersionEntry(version: latestVersion, apkUrl: ''),
      );

      // Nur zurückgeben wenn wirklich ein Update verfügbar ist
      if (!_isNewer(latestVersion, currentVersion)) return null;

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        apkUrl: latestEntry.apkUrl,
        versions: versions,
      );
    } catch (e) {
      print('[UPDATE] Exception: $e');
      return null;
    }
  }

  /// Lädt Versionsliste – APK-URLs aus version.json, Rest aus changelog.dart
  static Future<List<VersionEntry>> loadVersions() async {
    // APK-URLs aus version.json laden
    final Map<String, String> apkUrls = {};
    try {
      final response = await http
          .get(Uri.parse(kVersionUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        for (final v in (data['versions'] as List<dynamic>? ?? [])) {
          apkUrls[v['version'] as String] = v['apkUrl'] as String;
        }
      }
    } catch (_) {}

    // Alle Versionen aus changelog.dart – APK-URL einsetzen wenn vorhanden
    return changelog.map((entry) => VersionEntry(
          version: entry.version,
          apkUrl: apkUrls[entry.version] ?? '',
        )).toList();
  }

  static Future<void> openDownloadUrl(
      BuildContext context, String apkUrl) async {
    try {
      final launched = await launchUrl(
        Uri.parse(apkUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Browser konnte nicht geöffnet werden.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fehler beim Öffnen: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  static Future<void> showUpdateDialog(
      BuildContext context, UpdateInfo info) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _UpdateDialog(info: info),
    );
  }

  static Future<void> showVersionPicker(
      BuildContext context, UpdateInfo info) async {
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _VersionPickerSheet(info: info),
    );
  }

  static bool _isNewer(String a, String b) {
    final ap = _parse(a);
    final bp = _parse(b);
    for (int i = 0; i < 3; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return false;
  }

  static List<int> _parse(String v) =>
      v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
}

// ── Update-Dialog ─────────────────────────────────────────────────────────────

class _UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final changelogItems = info.changelog;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.system_update, color: cs.primary),
          const SizedBox(width: 10),
          const Text('Update verfügbar'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Aktuell',
                      style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
                  Text('v${info.currentVersion}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer)),
                ]),
                Icon(Icons.arrow_forward, color: cs.onPrimaryContainer, size: 18),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Neu',
                      style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
                  Text('v${info.latestVersion}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                          fontSize: 16)),
                ]),
              ],
            ),
          ),
          if (changelogItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Was ist neu:',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: cs.onSurface)),
            const SizedBox(height: 6),
            ...changelogItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 15, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(item,
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ],
      ),
      actions: [
        if (info.versions.length > 1)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              UpdateService.showVersionPicker(context, info);
            },
            icon: const Icon(Icons.history, size: 16),
            label: const Text('Andere Version'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Später'),
        ),
        FilledButton.icon(
          onPressed: () {
            final apkUrl = info.apkUrl;
            final ctx = context;
            Navigator.pop(context);
            UpdateService.openDownloadUrl(ctx, apkUrl);
          },
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Herunterladen'),
        ),
      ],
    );
  }
}

// ── Versionsauswahl Bottom Sheet ──────────────────────────────────────────────

class _VersionPickerSheet extends StatelessWidget {
  final UpdateInfo info;
  const _VersionPickerSheet({required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Icon(Icons.history, color: cs.primary),
                const SizedBox(width: 10),
                Text('Version auswählen',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Aktuell: v${info.currentVersion}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: info.versions.length,
              itemBuilder: (_, i) {
                final v = info.versions[i];
                final isLatest = v.version == info.latestVersion;
                final isCurrent = v.version == info.currentVersion;
                final items = v.changelogItems;

                return ExpansionTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isLatest
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    child: Text(
                      'v${v.version.split('.')[1]}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isLatest
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text('Version ${v.version}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      if (isLatest) _Badge('Neu', cs.primary),
                      if (isCurrent) _Badge('Installiert', cs.secondary),
                    ],
                  ),
                  subtitle: v.date.isNotEmpty
                      ? Text(v.date,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant))
                      : null,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...items.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        size: 14, color: cs.primary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(item,
                                            style: const TextStyle(
                                                fontSize: 13))),
                                  ],
                                ),
                              )),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: isCurrent
                                ? OutlinedButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Bereits installiert'),
                                  )
                                : v.apkUrl.isEmpty
                                    ? OutlinedButton.icon(
                                        onPressed: null,
                                        icon: const Icon(Icons.block, size: 16),
                                        label: const Text('Kein Download verfügbar'),
                                      )
                                    : FilledButton.icon(
                                        onPressed: () {
                                          final ctx = context;
                                          Navigator.pop(context);
                                          UpdateService.openDownloadUrl(
                                              ctx, v.apkUrl);
                                        },
                                        icon: const Icon(Icons.download, size: 16),
                                        label: Text('v${v.version} herunterladen'),
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
