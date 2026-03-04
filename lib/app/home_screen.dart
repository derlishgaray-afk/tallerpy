import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/admin/admin_users_screen.dart';
import '../screens/budgets/budgets_screen.dart';
import '../screens/customers/customers_screen.dart';
import '../screens/profile/my_taller_screen.dart';
import '../screens/repairs/repairs_hub_screen.dart';
import '../screens/vehicles/all_vehicles_screen.dart';
import 'theme_controller.dart';

class HomeScreen extends StatelessWidget {
  final String tallerName;
  final ThemeController theme;
  final bool isAdmin;

  const HomeScreen({
    super.key,
    required this.tallerName,
    required this.theme,
    required this.isAdmin,
  });

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

  void _openAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
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
                      'Menu principal',
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
                title: const Text('Mi taller'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openMiTaller(context);
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Panel admin'),
                  onTap: () {
                    Navigator.pop(context);
                    _openAdminUsers(context);
                  },
                ),

              ExpansionTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: const Text('Tema'),
                children: [
                  RadioGroup<AppThemeMode>(
                    groupValue: theme.mode,
                    onChanged: (value) {
                      if (value != null) theme.setAndPersist(value);
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
                  'Cerrar sesion',
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _MenuCard(
              title: 'Registro de clientes',
              icon: Icons.people_alt_outlined,
              onTap: () => _openClientes(context),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              title: 'Lista de vehiculos',
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
