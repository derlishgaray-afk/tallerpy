import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../customers/customer_vehicles_screen.dart';
import '../customers/vehicle_detail_screen.dart';

class AllVehiclesScreen extends StatefulWidget {
  const AllVehiclesScreen({super.key});

  @override
  State<AllVehiclesScreen> createState() => _AllVehiclesScreenState();
}

class _AllVehiclesScreenState extends State<AllVehiclesScreen> {
  final _search = TextEditingController();
  String _q = '';

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  final Map<String, String> _customerNames = {};
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _vehiclesByCustomer = {};
  final Set<String> _loadingVehicles = {};

  CollectionReference<Map<String, dynamic>> _customersCol() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('customers');
  }

  Future<void> _ensureVehicles(String customerId) async {
    if (_vehiclesByCustomer.containsKey(customerId)) return;
    if (_loadingVehicles.contains(customerId)) return;
    _loadingVehicles.add(customerId);
    try {
      final snap = await _customersCol()
          .doc(customerId)
          .collection('vehicles')
          .orderBy('updatedAt', descending: true)
          .get();
      if (!mounted) return;
      setState(() => _vehiclesByCustomer[customerId] = snap.docs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _vehiclesByCustomer[customerId] = []);
    } finally {
      _loadingVehicles.remove(customerId);
    }
  }

  bool _match(String hay, String q) {
    return hay.toLowerCase().contains(q);
  }

  String _vehicleTitle(Map<String, dynamic> d) {
    final brand = (d['brand'] ?? '').toString();
    final model = (d['model'] ?? '').toString();
    final title = [brand, model]
        .where((x) => x.trim().isNotEmpty)
        .join(' ')
        .trim();
    return title.isEmpty ? 'Vehículo' : title;
  }

  String _vehicleSubtitle(Map<String, dynamic> d) {
    final plate = (d['plate'] ?? '').toString();
    final year = (d['year'] ?? '').toString();
    final parts = <String>[
      if (plate.trim().isNotEmpty) 'Chapa: $plate',
      if (year.trim().isNotEmpty) 'Año: $year',
    ];
    return parts.join('   •   ');
  }

  void _openCustomerVehicles(BuildContext context, String id, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerVehiclesScreen(
          customerId: id,
          customerName: name,
        ),
      ),
    );
  }

  void _openVehicleDetail(
    BuildContext context,
    String customerId,
    String customerName,
    String vehicleId,
  ) {
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lista de Vehículos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar (cliente o Vehículo)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _customersCol().orderBy('name').snapshots(),
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
                          Icon(Icons.people_alt_outlined, size: 56),
                          SizedBox(height: 12),
                          Text('No hay clientes todavía.'),
                        ],
                      ),
                    ),
                  );
                }

                for (final doc in docs) {
                  final name = (doc.data()['name'] ?? '').toString().trim();
                  _customerNames[doc.id] = name;
                }

                final hasQuery = _q.isNotEmpty;
                if (!hasQuery) {
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final d = doc.data();
                      final name = (d['name'] ?? '').toString().trim();
                      final phone = (d['phone'] ?? '').toString().trim();
                      final ruc = (d['ruc'] ?? '').toString().trim();
                      final subtitleParts = <String>[
                        if (phone.isNotEmpty) phone,
                        if (ruc.isNotEmpty) 'RUC/CI: $ruc',
                      ];
                      final subtitle = subtitleParts.join('   •   ');

                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.people_alt_outlined),
                          title: Text(name.isEmpty ? 'Cliente' : name),
                          subtitle: subtitle.isEmpty ? null : Text(subtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openCustomerVehicles(
                            context,
                            doc.id,
                            name.isEmpty ? 'Cliente' : name,
                          ),
                        ),
                      );
                    },
                  );
                }

                final filteredCustomers = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                for (final doc in docs) {
                  final d = doc.data();
                  final name = (d['name'] ?? '').toString();
                  final phone = (d['phone'] ?? '').toString();
                  final ruc = (d['ruc'] ?? '').toString();
                  if (_match(name.toLowerCase(), _q) ||
                      _match(phone.toLowerCase(), _q) ||
                      _match(ruc.toLowerCase(), _q)) {
                    filteredCustomers.add(doc);
                  }
                  if (!_vehiclesByCustomer.containsKey(doc.id)) {
                    _ensureVehicles(doc.id);
                  }
                }

                final vehicleTiles = <Widget>[];
                for (final entry in _vehiclesByCustomer.entries) {
                  final customerId = entry.key;
                  final customerName = _customerNames[customerId] ?? 'Cliente';
                  for (final vdoc in entry.value) {
                    final d = vdoc.data();
                    final hay = [
                      (d['brand'] ?? '').toString(),
                      (d['model'] ?? '').toString(),
                      (d['plate'] ?? '').toString(),
                      (d['year'] ?? '').toString(),
                    ].join(' ').toLowerCase();
                    if (!_match(hay, _q)) continue;
                    final title = _vehicleTitle(d);
                    final subtitle = _vehicleSubtitle(d);
                    vehicleTiles.add(
                      Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.directions_car_filled_outlined),
                          title: Text(title),
                          subtitle: subtitle.isEmpty ? null : Text(subtitle),
                          trailing: Text(customerName),
                          onTap: () => _openVehicleDetail(
                            context,
                            customerId,
                            customerName,
                            vdoc.id,
                          ),
                        ),
                      ),
                    );
                  }
                }

                if (filteredCustomers.isEmpty && vehicleTiles.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Sin resultados.'),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (filteredCustomers.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Clientes',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...filteredCustomers.map((doc) {
                        final d = doc.data();
                        final name = (d['name'] ?? '').toString().trim();
                        final phone = (d['phone'] ?? '').toString().trim();
                        final ruc = (d['ruc'] ?? '').toString().trim();
                        final subtitleParts = <String>[
                          if (phone.isNotEmpty) phone,
                          if (ruc.isNotEmpty) 'RUC/CI: $ruc',
                        ];
                        final subtitle = subtitleParts.join('   •   ');
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.people_alt_outlined),
                            title: Text(name.isEmpty ? 'Cliente' : name),
                            subtitle:
                                subtitle.isEmpty ? null : Text(subtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openCustomerVehicles(
                              context,
                              doc.id,
                              name.isEmpty ? 'Cliente' : name,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                    if (vehicleTiles.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Vehículos',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...vehicleTiles,
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

