import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'vehicle_form_screen.dart';

class VehicleDetailScreen extends StatelessWidget {
  final String customerId;
  final String vehicleId;
  final String customerName;

  const VehicleDetailScreen({
    super.key,
    required this.customerId,
    required this.vehicleId,
    required this.customerName,
  });

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _vehicleRef() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('customers')
        .doc(customerId)
        .collection('vehicles')
        .doc(vehicleId);
  }

  @override
  Widget build(BuildContext context) {
    final custName = customerName.trim().isEmpty ? 'Cliente' : customerName;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _vehicleRef().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vehiculo')),
            body: Center(child: Text('Error: ${snap.error}')),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vehiculo')),
            body: const Center(child: Text('Cargando...')),
          );
        }

        final data = snap.data!.data();
        if (data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vehiculo')),
            body: const Center(child: Text('Vehiculo no encontrado')),
          );
        }

        final brand = (data['brand'] ?? '').toString().trim();
        final model = (data['model'] ?? '').toString().trim();
        final plate = (data['plate'] ?? '').toString().trim();
        final year = (data['year'] ?? '').toString().trim();
        final notes = (data['notes'] ?? '').toString().trim();

        final title = [
          if (brand.isNotEmpty) brand,
          if (model.isNotEmpty) model,
          if (plate.isNotEmpty) '($plate)',
        ].join(' ').trim();

        return Scaffold(
          appBar: AppBar(
            title: Text(title.isEmpty ? 'Vehiculo' : title),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VehicleFormScreen(
                        customerId: customerId,
                        vehicleId: vehicleId,
                        initial: data,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          custName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(label: 'Marca', value: brand),
                        _InfoRow(label: 'Modelo', value: model),
                        _InfoRow(label: 'Chapa', value: plate),
                        _InfoRow(label: 'Ano', value: year),
                        _InfoRow(label: 'Obs.', value: notes),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Presupuestos y Reparaciones se gestionan desde el menu principal.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

