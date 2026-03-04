import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Tema guardado en Firestore:
/// users/{uid}.settings.theme = 'system' | 'light' | 'dark'
enum AppThemeMode { system, light, dark }

AppThemeMode appThemeModeFromString(String? value) {
  switch ((value ?? 'system').toLowerCase()) {
    case 'light':
      return AppThemeMode.light;
    case 'dark':
      return AppThemeMode.dark;
    default:
      return AppThemeMode.system;
  }
}

ThemeMode appThemeModeToThemeMode(AppThemeMode mode) {
  switch (mode) {
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
    case AppThemeMode.system:
      return ThemeMode.system;
  }
}

/// Controlador simple (sin Provider) para que el tema cambie instantaneo.
class ThemeController extends ChangeNotifier {
  AppThemeMode _mode = AppThemeMode.system;

  AppThemeMode get mode => _mode;
  ThemeMode get themeMode => appThemeModeToThemeMode(_mode);

  void setLocal(AppThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Se usa cuando Firestore cambia (NO vuelve a escribir en Firestore).
  void syncFromRemote(AppThemeMode remoteMode) {
    if (_mode == remoteMode) return;
    _mode = remoteMode;
    notifyListeners();
  }

  Future<void> setAndPersist(AppThemeMode mode) async {
    setLocal(mode);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'settings': {
        'theme': mode.name, // system|light|dark
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }
}
