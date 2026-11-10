import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dark mode for the tutor and student screens, switched on their Profile
/// page.
///
/// Each role's choice is kept on this device separately, and it only applies
/// while a tutor or student is signed in: the login and admin screens always
/// stay light. MaterialApp listens to [mode].
class TutorTheme {
  TutorTheme._();

  static const _roles = ['tutor', 'student'];
  static String _prefsKey(String role) => '${role}_dark_mode';

  static final Map<String, bool> _darkChosen = {
    for (final role in _roles) role: false,
  };

  /// Who is signed in ('tutor' or 'student'), or null.
  static String? _signedInRole;

  /// The last role signed in, so the switch still knows whose choice it is.
  static String _role = 'tutor';

  /// The ThemeMode MaterialApp uses.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  /// What the Dark Mode switch shows (for the signed-in role).
  static bool get darkChosen => _darkChosen[_role] ?? false;

  /// Reads the saved choices. Called once in main().
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final role in _roles) {
        _darkChosen[role] = prefs.getBool(_prefsKey(role)) ?? false;
      }
    } catch (_) {
      // No saved choice (e.g. storage blocked): stay light.
    }
    _apply();
  }

  /// A tutor or student has signed in: use their choice.
  static void signedIn([String role = 'tutor']) {
    _role = _roles.contains(role) ? role : 'tutor';
    _signedInRole = _role;
    _apply();
  }

  /// They signed out: back to light for the login screen.
  static void signedOut() {
    _signedInRole = null;
    _apply();
  }

  /// The Dark Mode switch on the Profile page.
  static Future<void> setDark(bool on) async {
    final role = _role;
    _darkChosen[role] = on;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey(role), on);
    } catch (_) {
      // Still dark for this session, just not remembered.
    }
  }

  static void _apply() {
    final role = _signedInRole;
    mode.value = role != null && (_darkChosen[role] ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  /// The app theme while dark mode is on.
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

/// The dark-mode colours of the tutor and student screens. In light mode
/// every screen keeps its own colours; in dark mode it uses these.
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

/// True when the tutor or student screens are dark.
extension TutorThemeContext on BuildContext {
  bool get tutorDark => Theme.of(this).brightness == Brightness.dark;
}
