// services/theme_service.dart
//
// Überarbeiteter ThemeService mit manuell abgestimmten ColorSchemes.
// Ziele:
//  - WCAG AA konformer Kontrast (min. 4.5:1 für Text)
//  - Klare Unterscheidbarkeit von Surfaces im Dark Mode
//  - Feuerwehr-gerechte Farbgebung (Rot/Orange für Warnungen bleibt lesbar)
//  - Konsistente Card-, AppBar- und Input-Farben über alle Themes

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Helligkeit: unabhängig von der Akzentfarbe
enum BrightnessMode { system, light, dark }

// Akzentfarbe: unabhängig vom Helligkeitsmodus
enum AccentColor { red, blue, green, orange }

// Rückwärtskompatibles Enum für Widgets die ThemeOption noch referenzieren
enum ThemeOption { system, light, dark, blue, green, orange, red }

class ThemeService extends ChangeNotifier {
  static const String _brightnessKey = 'brightness_mode';
  static const String _accentKey     = 'accent_color';
  static const String _legacyKey     = 'selected_theme'; // Migration

  late SharedPreferences _prefs;

  BrightnessMode _brightness = BrightnessMode.system;
  AccentColor    _accent     = AccentColor.red;

  BrightnessMode get brightnessMode => _brightness;
  AccentColor    get accentColor    => _accent;

  /// Rückwärtskompatibel: liefert nur den Helligkeitsteil
  ThemeOption get currentTheme {
    switch (_brightness) {
      case BrightnessMode.light: return ThemeOption.light;
      case BrightnessMode.dark:  return ThemeOption.dark;
      default:                   return ThemeOption.system;
    }
  }

  // Singleton
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    // Legacy-Migration: altes combined-int auf zwei Keys umrechnen
    final legacy = _prefs.getInt(_legacyKey);
    if (legacy != null && !_prefs.containsKey(_brightnessKey)) {
      switch (legacy) {
        case 1: _prefs.setInt(_brightnessKey, BrightnessMode.light.index); break;
        case 2: _prefs.setInt(_brightnessKey, BrightnessMode.dark.index);  break;
        case 3: _prefs.setInt(_accentKey, AccentColor.blue.index);         break;
        case 4: _prefs.setInt(_accentKey, AccentColor.green.index);        break;
        case 5: _prefs.setInt(_accentKey, AccentColor.orange.index);       break;
        case 6: _prefs.setInt(_accentKey, AccentColor.red.index);          break;
      }
    }

    final bIdx = _prefs.getInt(_brightnessKey);
    final aIdx = _prefs.getInt(_accentKey);
    if (bIdx != null && bIdx < BrightnessMode.values.length) {
      _brightness = BrightnessMode.values[bIdx];
    }
    if (aIdx != null && aIdx < AccentColor.values.length) {
      _accent = AccentColor.values[aIdx];
    }
    notifyListeners();
  }

  /// Helligkeit setzen — Akzentfarbe bleibt unverändert
  Future<void> setBrightness(BrightnessMode mode) async {
    _brightness = mode;
    await _prefs.setInt(_brightnessKey, mode.index);
    notifyListeners();
  }

  /// Akzentfarbe setzen — Helligkeit bleibt unverändert
  Future<void> setAccent(AccentColor color) async {
    _accent = color;
    await _prefs.setInt(_accentKey, color.index);
    notifyListeners();
  }

  /// Legacy-API für alten Code — leitet intern auf setBrightness/setAccent
  Future<void> setTheme(ThemeOption theme) async {
    switch (theme) {
      case ThemeOption.system: await setBrightness(BrightnessMode.system); break;
      case ThemeOption.light:  await setBrightness(BrightnessMode.light);  break;
      case ThemeOption.dark:   await setBrightness(BrightnessMode.dark);   break;
      case ThemeOption.blue:   await setAccent(AccentColor.blue);   break;
      case ThemeOption.green:  await setAccent(AccentColor.green);  break;
      case ThemeOption.orange: await setAccent(AccentColor.orange); break;
      case ThemeOption.red:    await setAccent(AccentColor.red);    break;
    }
  }

  ThemeMode getThemeMode() {
    switch (_brightness) {
      case BrightnessMode.light: return ThemeMode.light;
      case BrightnessMode.dark:  return ThemeMode.dark;
      default:                   return ThemeMode.system;
    }
  }

  ThemeData getLightTheme() {
    switch (_accent) {
      case AccentColor.blue:   return _blueLightTheme();
      case AccentColor.green:  return _greenLightTheme();
      case AccentColor.orange: return _orangeLightTheme();
      case AccentColor.red:    return _defaultLightTheme();
    }
  }

  ThemeData getDarkTheme() {
    switch (_accent) {
      case AccentColor.blue:   return _blueDarkTheme();
      case AccentColor.green:  return _greenDarkTheme();
      case AccentColor.orange: return _orangeDarkTheme();
      case AccentColor.red:    return _defaultDarkTheme();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED HELPER — baut ein ThemeData aus einem vollständigen ColorScheme
  // ─────────────────────────────────────────────────────────────────────────

  ThemeData _buildTheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,

      // ── Scaffold / Canvas ─────────────────────────────────────────────────
      // Explizit setzen damit kein Widget auf veraltete defaults zurückfällt
      scaffoldBackgroundColor: scheme.surface,
      // cardColor: veraltete API aber viele Widgets nutzen sie noch
      cardColor: isDark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      canvasColor: scheme.surface,
      dialogBackgroundColor: isDark
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerLow,

      // ── AppBar ────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Cards ─────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        // Dark: surfaceContainer (#211F26) hebt sich klar von surface (#1C1B1F) ab
        color: isDark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          // Dark: voller Border für klare Card-Abgrenzung
          side: isDark
              ? BorderSide(color: scheme.outlineVariant, width: 1)
              : BorderSide.none,
        ),
      ),

      // ── Input Fields ──────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(0.7)),
      ),

      // ── Buttons ───────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withOpacity(0.12),
          disabledForegroundColor: scheme.onSurface.withOpacity(0.38),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      // ── ListTile ──────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        // Dark: onSurfaceVariant = #CAC4D0 → klar lesbar auf #211F26
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13,
        ),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 16,
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        side: BorderSide(color: scheme.outlineVariant),
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),

      // ── BottomSheet ───────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ── SnackBar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? scheme.surfaceContainerHighest : const Color(0xFF1C1B1F),
        contentTextStyle: TextStyle(
          color: isDark ? scheme.onSurface : Colors.white,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // ── NavigationBar ─────────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          );
        }),
      ),

      // ── FloatingActionButton ──────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: isDark ? 1 : 3,
      ),

      // ── Text ─────────────────────────────────────────────────────────────
      // onSurface     = #E6E1E5 (fast weiß) → Kontrast ~14:1 auf #1C1B1F
      // onSurfaceVariant = #CAC4D0         → Kontrast  ~7:1 → WCAG AA ✓
      textTheme: TextTheme(
        bodyLarge:   TextStyle(color: scheme.onSurface),
        bodyMedium:  TextStyle(color: scheme.onSurface),
        bodySmall:   TextStyle(color: scheme.onSurfaceVariant),
        labelLarge:  TextStyle(color: scheme.onSurface),
        labelMedium: TextStyle(color: scheme.onSurfaceVariant),
        labelSmall:  TextStyle(color: scheme.onSurfaceVariant),
        titleLarge:  TextStyle(color: scheme.onSurface),
        titleMedium: TextStyle(color: scheme.onSurface),
        titleSmall:  TextStyle(color: scheme.onSurface),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEFAULT (Feuerwehr-Rot/Dunkelgrau)
  // ─────────────────────────────────────────────────────────────────────────

  ThemeData _defaultLightTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.light,
        // Primary: Feuerwehr-Rot
        primary: Color(0xFFCC2222),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFFFDAD6),
        onPrimaryContainer: Color(0xFF410002),
        // Secondary: Warm-Grau
        secondary: Color(0xFF775651),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFFDAD6),
        onSecondaryContainer: Color(0xFF2C1512),
        // Tertiary: Dunkelbraun
        tertiary: Color(0xFF715B2E),
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFFDDFA6),
        onTertiaryContainer: Color(0xFF261900),
        // Error
        error: Color(0xFFBA1A1A),
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        // Surfaces
        surface: Color(0xFFFFF8F7),
        onSurface: Color(0xFF201A1A),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFFFF0EE),
        surfaceContainer: Color(0xFFFFEAE8),
        surfaceContainerHigh: Color(0xFFFAE4E2),
        surfaceContainerHighest: Color(0xFFF5DEDC),
        onSurfaceVariant: Color(0xFF534341),
        // Outline
        outline: Color(0xFF857370),
        outlineVariant: Color(0xFFD8C2BF),
        // Misc
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF362F2E),
        onInverseSurface: Color(0xFFFFEDEB),
        inversePrimary: Color(0xFFFFB3AD),
      ));

  ThemeData _defaultDarkTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.dark,
        // Primärfarbe im Dark Mode: helles Korall-Rot, gut lesbar auf dunklem Grund
        primary: Color(0xFFFFB3AD),
        onPrimary: Color(0xFF680006),
        primaryContainer: Color(0xFF93000F),
        onPrimaryContainer: Color(0xFFFFDAD6),
        secondary: Color(0xFFEDC5C1),          // heller als vorher
        onSecondary: Color(0xFF442927),
        secondaryContainer: Color(0xFF5D3F3C),
        onSecondaryContainer: Color(0xFFFFDAD6),
        tertiary: Color(0xFFEDD08A),
        onTertiary: Color(0xFF3E2D04),
        tertiaryContainer: Color(0xFF574319),
        onTertiaryContainer: Color(0xFFFDDFA6),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        // ── Surfaces: Material You Dunkel-Basis ──────────────────────────────
        // surface = Haupthintergrund
        surface: Color(0xFF1C1B1F),
        // onSurface = primärer Text → fast weiß (~14:1 Kontrast)
        onSurface: Color(0xFFE6E1E5),
        // Container-Abstufung: GRÖSSERE Schritte damit Cards sichtbar werden
        surfaceContainerLowest: Color(0xFF0F0D13),
        surfaceContainerLow:    Color(0xFF1C1B1F),   // = surface / Hintergrund
        surfaceContainer:       Color(0xFF2A2831),   // Cards  (+14 heller)
        surfaceContainerHigh:   Color(0xFF332F3C),   // elevated Cards (+19)
        surfaceContainerHighest:Color(0xFF3E3A47),   // Dialoge, BottomSheets
        // onSurfaceVariant = Subtitles, Labels → hell genug für WCAG AA
        onSurfaceVariant: Color(0xFFCAC4D0),
        // outlineVariant = Card-Border → deutlich sichtbar
        outline: Color(0xFF938F99),
        outlineVariant: Color(0xFF605C66),           // heller als vorher (#49454F)
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFE6E1E5),
        onInverseSurface: Color(0xFF322F35),
        inversePrimary: Color(0xFFCC2222),
      ));

  // ─────────────────────────────────────────────────────────────────────────
  // BLAU
  // ─────────────────────────────────────────────────────────────────────────

  ThemeData _blueLightTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF0055CC),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFD8E2FF),
        onPrimaryContainer: Color(0xFF001849),
        secondary: Color(0xFF565E71),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFDAE2F9),
        onSecondaryContainer: Color(0xFF131C2C),
        tertiary: Color(0xFF705574),
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFFAD8FD),
        onTertiaryContainer: Color(0xFF28132D),
        error: Color(0xFFBA1A1A),
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFFAF9FF),
        onSurface: Color(0xFF1A1B21),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFF3F3FA),
        surfaceContainer: Color(0xFFEDEDF4),
        surfaceContainerHigh: Color(0xFFE7E7EF),
        surfaceContainerHighest: Color(0xFFE1E2E9),
        onSurfaceVariant: Color(0xFF44474F),
        outline: Color(0xFF757780),
        outlineVariant: Color(0xFFC4C6D0),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF2F3036),
        onInverseSurface: Color(0xFFF1F0F7),
        inversePrimary: Color(0xFFAEC6FF),
      ));

  ThemeData _blueDarkTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFAEC6FF),
        onPrimary: Color(0xFF002A78),
        primaryContainer: Color(0xFF003EA8),
        onPrimaryContainer: Color(0xFFD8E2FF),
        secondary: Color(0xFFBEC6DC),
        onSecondary: Color(0xFF283041),
        secondaryContainer: Color(0xFF3F4759),
        onSecondaryContainer: Color(0xFFDAE2F9),
        tertiary: Color(0xFFDDBCE0),
        onTertiary: Color(0xFF3F2844),
        tertiaryContainer: Color(0xFF573E5B),
        onTertiaryContainer: Color(0xFFFAD8FD),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF111318),
        onSurface: Color(0xFFE1E2E9),
        surfaceContainerLowest: Color(0xFF0C0E13),
        surfaceContainerLow: Color(0xFF1A1B21),
        surfaceContainer: Color(0xFF1E1F25),
        surfaceContainerHigh: Color(0xFF282930),
        surfaceContainerHighest: Color(0xFF33343A),
        onSurfaceVariant: Color(0xFFC4C6D0),
        outline: Color(0xFF8E9099),
        outlineVariant: Color(0xFF44474F),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFE1E2E9),
        onInverseSurface: Color(0xFF2F3036),
        inversePrimary: Color(0xFF0055CC),
      ));

  // ─────────────────────────────────────────────────────────────────────────
  // GRÜN
  // ─────────────────────────────────────────────────────────────────────────

  ThemeData _greenLightTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF1A6B2E),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFB6F0C4),
        onPrimaryContainer: Color(0xFF002109),
        secondary: Color(0xFF4E6353),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFD0E8D3),
        onSecondaryContainer: Color(0xFF0B1F13),
        tertiary: Color(0xFF3A6471),
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFBEEAF8),
        onTertiaryContainer: Color(0xFF001F27),
        error: Color(0xFFBA1A1A),
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFF6FBF3),
        onSurface: Color(0xFF181D19),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFF0F5EE),
        surfaceContainer: Color(0xFFEAF0E8),
        surfaceContainerHigh: Color(0xFFE4EAE2),
        surfaceContainerHighest: Color(0xFFDEE4DC),
        onSurfaceVariant: Color(0xFF404942),
        outline: Color(0xFF707972),
        outlineVariant: Color(0xFFC0C9C1),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF2D322E),
        onInverseSurface: Color(0xFFECF2EA),
        inversePrimary: Color(0xFF9BD4A9),
      ));

  ThemeData _greenDarkTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF9BD4A9),
        onPrimary: Color(0xFF003914),
        primaryContainer: Color(0xFF005221),
        onPrimaryContainer: Color(0xFFB6F0C4),
        secondary: Color(0xFFB5CCB8),
        onSecondary: Color(0xFF203527),
        secondaryContainer: Color(0xFF364B3D),
        onSecondaryContainer: Color(0xFFD0E8D3),
        tertiary: Color(0xFFA3CEDB),
        onTertiary: Color(0xFF063541),
        tertiaryContainer: Color(0xFF224C58),
        onTertiaryContainer: Color(0xFFBEEAF8),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF101410),
        onSurface: Color(0xFFDEE4DC),
        surfaceContainerLowest: Color(0xFF0B0F0B),
        surfaceContainerLow: Color(0xFF181D19),
        surfaceContainer: Color(0xFF1C211D),
        surfaceContainerHigh: Color(0xFF272B27),
        surfaceContainerHighest: Color(0xFF313632),
        onSurfaceVariant: Color(0xFFC0C9C1),
        outline: Color(0xFF8A938C),
        outlineVariant: Color(0xFF404942),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFDEE4DC),
        onInverseSurface: Color(0xFF2D322E),
        inversePrimary: Color(0xFF1A6B2E),
      ));

  // ─────────────────────────────────────────────────────────────────────────
  // ORANGE
  // ─────────────────────────────────────────────────────────────────────────

  ThemeData _orangeLightTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFFB85000),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFFFDCC2),
        onPrimaryContainer: Color(0xFF3A1500),
        secondary: Color(0xFF745844),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFFDCC2),
        onSecondaryContainer: Color(0xFF2A1708),
        tertiary: Color(0xFF5D6022),
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFE2E59A),
        onTertiaryContainer: Color(0xFF1A1D00),
        error: Color(0xFFBA1A1A),
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFFFF8F5),
        onSurface: Color(0xFF201A16),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFFFF1E9),
        surfaceContainer: Color(0xFFFAEBE2),
        surfaceContainerHigh: Color(0xFFF5E5DC),
        surfaceContainerHighest: Color(0xFFEFDFD6),
        onSurfaceVariant: Color(0xFF52443B),
        outline: Color(0xFF85736A),
        outlineVariant: Color(0xFFD6C3B9),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF362F2A),
        onInverseSurface: Color(0xFFFBEEE7),
        inversePrimary: Color(0xFFFFB786),
      ));

  ThemeData _orangeDarkTheme() => _buildTheme(const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFFFB786),
        onPrimary: Color(0xFF612700),
        primaryContainer: Color(0xFF893B00),
        onPrimaryContainer: Color(0xFFFFDCC2),
        secondary: Color(0xFFE4BFA8),
        onSecondary: Color(0xFF422B1A),
        secondaryContainer: Color(0xFF5A412F),
        onSecondaryContainer: Color(0xFFFFDCC2),
        tertiary: Color(0xFFC6C981),
        onTertiary: Color(0xFF2F3200),
        tertiaryContainer: Color(0xFF45490C),
        onTertiaryContainer: Color(0xFFE2E59A),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF181210),
        onSurface: Color(0xFFEFDFD6),
        surfaceContainerLowest: Color(0xFF120D0A),
        surfaceContainerLow: Color(0xFF201A16),
        surfaceContainer: Color(0xFF251E1B),
        surfaceContainerHigh: Color(0xFF2F2825),
        surfaceContainerHighest: Color(0xFF3B322F),
        onSurfaceVariant: Color(0xFFD6C3B9),
        outline: Color(0xFF9F8D84),
        outlineVariant: Color(0xFF52443B),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFEFDFD6),
        onInverseSurface: Color(0xFF362F2A),
        inversePrimary: Color(0xFFB85000),
      ));

  // ─────────────────────────────────────────────────────────────────────────
  // ROT (Feuerwehr-klassisch, neu hinzugefügt)
  // ─────────────────────────────────────────────────────────────────────────

  ThemeData _redLightTheme() => _defaultLightTheme();
  ThemeData _redDarkTheme() => _defaultDarkTheme();

  // ─────────────────────────────────────────────────────────────────────────
  // NAMEN
  // ─────────────────────────────────────────────────────────────────────────

  String getThemeName(ThemeOption theme) {
    switch (theme) {
      case ThemeOption.system:
        return 'Systemstandard';
      case ThemeOption.light:
        return 'Hell';
      case ThemeOption.dark:
        return 'Dunkel';
      case ThemeOption.blue:
        return 'Blau';
      case ThemeOption.green:
        return 'Grün';
      case ThemeOption.orange:
        return 'Orange';
      case ThemeOption.red:
        return 'Feuerwehr-Rot';
    }
  }

  IconData getThemeIcon(ThemeOption theme) {
    switch (theme) {
      case ThemeOption.system:
        return Icons.brightness_auto;
      case ThemeOption.light:
        return Icons.brightness_high;
      case ThemeOption.dark:
        return Icons.brightness_2;
      case ThemeOption.blue:
        return Icons.circle;
      case ThemeOption.green:
        return Icons.circle;
      case ThemeOption.orange:
        return Icons.circle;
      case ThemeOption.red:
        return Icons.local_fire_department;
    }
  }

  Color? getThemeIconColor(ThemeOption theme) {
    switch (theme) {
      case ThemeOption.blue:
        return const Color(0xFF0055CC);
      case ThemeOption.green:
        return const Color(0xFF1A6B2E);
      case ThemeOption.orange:
        return const Color(0xFFB85000);
      case ThemeOption.red:
        return const Color(0xFFCC2222);
      default:
        return null;
    }
  }
}
