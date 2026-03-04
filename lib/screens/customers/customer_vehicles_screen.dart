import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/vehicles/data/models/vehicle_model.dart';
import '../../features/vehicles/data/repositories/vehicles_repository.dart';
import 'vehicle_form_screen.dart';
import 'vehicle_detail_screen.dart';

class CustomerVehiclesScreen extends StatelessWidget {
  final String customerId;
  final String customerName;
  final VehiclesRepository _repo = VehiclesRepository();

  CustomerVehiclesScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Map<String, dynamic> _toInitial(VehicleModel vehicle) {
    return {
      'brand': vehicle.brand,
      'model': vehicle.model,
      'plate': vehicle.plate,
      'year': vehicle.year,
      'chassis': vehicle.chassis,
      'notes': vehicle.notes,
    };
  }

  void _openDetail(BuildContext context, String vehicleId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleDetailScreen(
          customerId: customerId,
          vehicleId: vehicleId,
          customerName: customerName,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, String vehicleId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar vehículo'),
        content: const Text('¿Seguro que querés eliminar este vehículo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _repo.deleteVehicle(_uid, customerId, vehicleId);

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Vehículo eliminado ✅')));
  }

  void _openNew(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleFormScreen(customerId: customerId),
      ),
    );
  }

  void _openEdit(
    BuildContext context,
    String vehicleId,
    VehicleModel vehicle,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleFormScreen(
          customerId: customerId,
          vehicleId: vehicleId,
          initial: _toInitial(vehicle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleName = customerName.trim().isEmpty ? 'Cliente' : customerName;

    return Scaffold(
      appBar: AppBar(title: Text('Vehículos - $titleName')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNew(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<VehicleModel>>(
        stream: _repo.watchVehiclesForCustomer(_uid, customerId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_car_filled_outlined, size: 56),
                    SizedBox(height: 12),
                    Text('No hay vehículos todavía.'),
                    SizedBox(height: 6),
                    Text('Tocá el botón + para agregar uno.'),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final vehicle = doc.data();

              final brand = vehicle.brand;
              final model = vehicle.model;
              final plate = vehicle.plate;
              final year = vehicle.year;

              final title = [
                brand,
                model,
              ].where((x) => x.trim().isNotEmpty).join(' ').trim();

              final subtitleParts = <String>[
                if (plate.trim().isNotEmpty) 'Chapa: $plate',
                if (year.trim().isNotEmpty) 'Año: $year',
              ];
              final subtitle = subtitleParts.join('   •   ');

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.directions_car_filled_outlined),
                  title: Text(title.isEmpty ? 'Vehículo' : title),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onTap: () => _openDetail(context, doc.id),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') {
                        _openEdit(context, doc.id, vehicle);
                      } else if (v == 'del') {
                        _delete(context, doc.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'del', child: Text('Eliminar')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
