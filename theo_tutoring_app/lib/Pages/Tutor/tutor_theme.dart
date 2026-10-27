import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dark mode for the tutor screens, switched on the tutor Profile page.
///
/// The choice is kept on this device, and it only applies while a tutor is
/// signed in: the login, student and admin screens always stay light.
/// MaterialApp listens to [mode].
class TutorTheme {
  TutorTheme._();

  static const _prefsKey = 'tutor_dark_mode';

  static bool _darkChosen = false;
  static bool _tutorSignedIn = false;

  /// The ThemeMode MaterialApp uses.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  /// What the Dark Mode switch shows.
  static bool get darkChosen => _darkChosen;

  /// Reads the saved choice. Called once in main().
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _darkChosen = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      // No saved choice (e.g. storage blocked): stay light.
    }
    _apply();
  }

  /// A tutor has signed in: use their choice.
  static void signedIn() {
    _tutorSignedIn = true;
    _apply();
  }

  /// The tutor signed out: back to light for the login screen.
  static void signedOut() {
    _tutorSignedIn = false;
    _apply();
  }

  /// The Dark Mode switch on the Profile page.
  static Future<void> setDark(bool on) async {
    _darkChosen = on;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, on);
    } catch (_) {
      // Still dark for this session, just not remembered.
    }
  }

  static void _apply() {
    mode.value = _tutorSignedIn && _darkChosen
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  /// The app theme while a tutor has dark mode on.
  static final ThemeData darkTheme = () {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF246BFE),
      brightness: Brightness.dark,
    ).copyWith(surface: TutorDark.card);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: TutorDark.background,
      dividerColor: TutorDark.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: TutorDark.card,
        surfaceTintColor: TutorDark.card,
        foregroundColor: TutorDark.text,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: TutorDark.card,
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: TutorDark.card),
      dialogTheme: const DialogThemeData(backgroundColor: TutorDark.card),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TutorDark.card,
      ),
    );
  }();
}

/// The dark-mode colours of the tutor screens. In light mode every screen
/// keeps its own colours; in dark mode it uses these.
abstract final class TutorDark {
  static const background = Color(0xFF0F141C); // page
  static const card = Color(0xFF1A212C); // cards, bars, sheets
  static const cardAlt = Color(0xFF232B38); // fills inside a card
  static const border = Color(0xFF2F3A4A);
  static const text = Color(0xFFF3F4F6); // headings, names
  static const textSecondary = Color(0xFFD1D5DB); // body text
  static const textMuted = Color(0xFF9CA3AF); // labels, hints
  static const textFaint = Color(0xFF7C8594); // placeholders, disabled
  static const blueTint = Color(0xFF1E2F52); // light-blue fills
  static const blueText = Color(0xFF93B4FF); // blue text on a blue tint
  static const amberTint = Color(0xFF3D2E12);
  static const amberText = Color(0xFFFCD34D);
  static const greenTint = Color(0xFF14342A);
  static const greenText = Color(0xFF6EE7B7);
  static const redTint = Color(0xFF3B1E22);
  static const redText = Color(0xFFFCA5A5);
}

/// True when the tutor screens are dark.
extension TutorThemeContext on BuildContext {
  bool get tutorDark => Theme.of(this).brightness == Brightness.dark;
}
