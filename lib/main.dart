import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/profile/my_taller_screen.dart';
import 'screens/customers/customers_screen.dart';
import 'screens/vehicles/all_vehicles_screen.dart';
import 'screens/budgets/budgets_screen.dart';
import 'screens/repairs/repairs_hub_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

/// Tema guardado en Firestore:
/// users/{uid}.settings.theme = 'system' | 'light' | 'dark'
enum AppThemeMode { system, light, dark }

AppThemeMode _themeFromString(String? v) {
  switch ((v ?? 'system').toLowerCase()) {
    case 'light':
      return AppThemeMode.light;
    case 'dark':
      return AppThemeMode.dark;
    default:
      return AppThemeMode.system;
  }
}

ThemeMode _toThemeMode(AppThemeMode m) {
  switch (m) {
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
    case AppThemeMode.system:
      //default:
      return ThemeMode.system;
  }
}

/// Controlador simple (sin Provider) para que el tema cambie instantáneo
class ThemeController extends ChangeNotifier {
  AppThemeMode _mode = AppThemeMode.system;

  AppThemeMode get mode => _mode;
  ThemeMode get themeMode => _toThemeMode(_mode);

  void setLocal(AppThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Se usa cuando Firestore cambia (NO vuelve a escribir en Firestore)
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeController _theme = ThemeController();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _theme,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Taller Mecánico',
          theme: ThemeData(useMaterial3: true),
          darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          themeMode: _theme.themeMode, // ✓ CAMBIA INSTANTÁNEO
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, authSnap) {
              if (authSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // No logueado
              if (!authSnap.hasData) {
                // si querés, al salir vuelve a System
                _theme.setLocal(AppThemeMode.system);
                return const LoginScreen();
              }

              // Logueado
              return AppGate(theme: _theme);
            },
          ),
        );
      },
    );
  }
}

/// AppGate escucha /users/{uid} en tiempo real:
/// - isActive false => AccessPendingScreen
/// - profile.name vacío => MyTallerScreen
/// - caso normal => Home
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

        // --- Tema desde Firestore (aplica instantáneo)
        final settings = (data['settings'] as Map<String, dynamic>?) ?? {};
        final remoteThemeStr = (settings['theme'] ?? 'system').toString();
        final remoteTheme = _themeFromString(remoteThemeStr);

        // Evita setState en build: solo sincroniza si cambió
        theme.syncFromRemote(remoteTheme);

        // --- Acceso
        final isActive = (data['isActive'] == true);

        // --- Perfil
        final profile = (data['profile'] as Map<String, dynamic>?) ?? {};
        final tallerName = (profile['name'] ?? '').toString().trim();

        // 1) Bloqueo por acceso (sin Cerrar Sesión)
        if (!isActive) {
          return AccessPendingScreen(email: user.email ?? '');
        }

        // 2) Forzar completar Mi Taller la primera vez
        if (tallerName.isEmpty) {
          return const MyTallerScreen();
        }

        // 3) Home normal
        return HomeScreen(tallerName: tallerName, theme: theme);
      },
    );
  }
}

/// Pantalla de acceso pendiente (usuario sigue logueado)
class AccessPendingScreen extends StatelessWidget {
  final String email;

  const AccessPendingScreen({super.key, required this.email});

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso Pendiente')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_bottom, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'Tu cuenta está pendiente de aprobación',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Usuario: $email\n\nUn administrador revisará tu solicitud de acceso. '
                      'Si la espera es demasiado larga, contactá con soporte.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar Sesión'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final String tallerName;
  final ThemeController theme;

  const HomeScreen({super.key, required this.tallerName, required this.theme});

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _openMiTaller(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyTallerScreen()),
    );
  }

  void _openClientes(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomersScreen()),
    );
  }

  void _openVehiculos(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AllVehiclesScreen()),
    );
  }

  void _openPresupuestos(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BudgetsScreen()),
    );
  }

  void _openReparaciones(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RepairsHubScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final appTitle = 'Taller App - Taller "$tallerName"';

    return Scaffold(
      appBar: AppBar(title: Text(appTitle)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Menú Principal',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.store),
                title: const Text('Mi Taller'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openMiTaller(context);
                },
              ),

              // ✓ Selector de tema PRO (instantáneo + persistente)
              ExpansionTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: const Text('Tema'),
                children: [
                  RadioGroup<AppThemeMode>(
                    groupValue: theme.mode,
                    onChanged: (v) {
                      if (v != null) theme.setAndPersist(v);
                    },
                    child: const Column(
                      children: [
                        RadioListTile<AppThemeMode>(
                          value: AppThemeMode.system,
                          title: Text('Sistema'),
                        ),
                        RadioListTile<AppThemeMode>(
                          value: AppThemeMode.light,
                          title: Text('Claro'),
                        ),
                        RadioListTile<AppThemeMode>(
                          value: AppThemeMode.dark,
                          title: Text('Oscuro'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Spacer(),
              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _logout();
                },
              ),
            ],
          ),
        ),
      ),

      // Menu 1 por fila (tarjetas grandes)
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _MenuCard(
              title: 'Registro de Clientes',
              icon: Icons.people_alt_outlined,
              onTap: () => _openClientes(context),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              title: 'Lista de Vehículos',
              icon: Icons.directions_car_filled_outlined,
              onTap: () => _openVehiculos(context),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              title: 'Presupuestos',
              icon: Icons.receipt_long_outlined,
              onTap: () => _openPresupuestos(context),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              title: 'Reparaciones',
              icon: Icons.build_circle_outlined,
              onTap: () => _openReparaciones(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  const _MenuCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          onTap ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Abrir: $title (pendiente)')),
            );
          },
      borderRadius: BorderRadius.circular(18),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          height: 110,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icon, size: 44),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}





