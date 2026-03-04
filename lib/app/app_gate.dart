import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/profile/my_taller_screen.dart';
import '../services/user_access_service.dart';
import 'home_screen.dart';
import 'theme_controller.dart';
import 'trial_expired_screen.dart';

/// AppGate escucha /users/{uid} en tiempo real:
/// - isActive true => acceso normal
/// - isActive false + prueba activa => acceso normal
/// - isActive false + prueba vencida => TrialExpiredScreen
class AppGate extends StatelessWidget {
  final ThemeController theme;

  const AppGate({super.key, required this.theme});

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userRef(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data?.data() ?? {};

        final settings = (data['settings'] as Map<String, dynamic>?) ?? {};
        final remoteThemeStr = (settings['theme'] ?? 'system').toString();
        final remoteTheme = appThemeModeFromString(remoteThemeStr);
        theme.syncFromRemote(remoteTheme);

        final isActive = (data['isActive'] == true);
        final trialEndsAt =
            UserAccessService.readDate(data['trialEndsAt']) ??
            UserAccessService.authTrialEndsAt(user);
        final hasTrialAccess = UserAccessService.trialStillActive(trialEndsAt);

        final profile = (data['profile'] as Map<String, dynamic>?) ?? {};
        final tallerName = (profile['name'] ?? '').toString().trim();
        final isAdmin = (data['isAdmin'] == true);

        if (!isActive && !hasTrialAccess) {
          return TrialExpiredScreen(trialEndsAt: trialEndsAt);
        }

        if (tallerName.isEmpty) {
          return const MyTallerScreen();
        }

        return HomeScreen(
          tallerName: tallerName,
          theme: theme,
          isAdmin: isAdmin,
        );
      },
    );
  }
}
