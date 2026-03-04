import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/user_access_service.dart';
import 'app_gate.dart';
import 'theme_controller.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeController _theme = ThemeController();
  String? _lastEnsureUid;

  void _kickoffEnsureUserAccess(User user) {
    if (_lastEnsureUid == user.uid) return;
    _lastEnsureUid = user.uid;
    unawaited(UserAccessService.ensureUserAccessDocument(user));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _theme,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Taller Mecanico',
          theme: ThemeData(useMaterial3: true),
          darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          themeMode: _theme.themeMode,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, authSnap) {
              if (authSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (!authSnap.hasData) {
                _theme.setLocal(AppThemeMode.system);
                _lastEnsureUid = null;
                return const LoginScreen();
              }

              _kickoffEnsureUserAccess(authSnap.data!);
              return AppGate(theme: _theme);
            },
          ),
        );
      },
    );
  }
}
