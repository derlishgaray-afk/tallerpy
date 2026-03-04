import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/repairs_hub_repository.dart';
import 'repair_detail_screen.dart';
import 'repair_form_screen.dart';

class RepairsHubScreen extends StatefulWidget {
  const RepairsHubScreen({super.key});

  @override
  State<RepairsHubScreen> createState() => _RepairsHubScreenState();
}

class _RepairsHubScreenState extends State<RepairsHubScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _statusFilter = 'Todas';
  final _repo = RepairsHubRepository();
  late Future<List<RepairHubItem>> _futureRepairs;

  static final NumberFormat _gsFmt = NumberFormat.decimalPattern('es_PY');
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  static const List<String> _statusOptions = [
    'Todas',
    'Abierta',
    'En proceso',
    'Terminada',
    'Entregada',
    'Cancelada',
  ];

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _customersCol =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('customers');

  @override
  void initState() {
    super.initState();
    _futureRepairs = _repo.loadRepairsForUser(_uid);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = _repo.loadRepairsForUser(_uid);
    setState(() => _futureRepairs = next);
    try {
      await next;
    } catch (_) {
      // El error ya lo maneja FutureBuilder.
    }
  }

  String _vehicleTitleFromData(Map<String, dynamic> d) {
    final brand = (d['brand'] ?? '').toString().trim();
    final model = (d['model'] ?? '').toString().trim();
    final plate = (d['plate'] ?? '').toString().trim();
    final base = [brand, model].where((e) => e.isNotEmpty).join(' ').trim();
    if (plate.isEmpty) return base.isEmpty ? 'Vehiculo' : base;
    return base.isEmpty ? plate : '$base - $plate';
  }

  String _status(Map<String, dynamic> d) {
    final s = (d['status'] ?? 'Abierta').toString().trim();
    return s.isEmpty ? 'Abierta' : s;
  }

  bool _matchStatus(Map<String, dynamic> d) {
    if (_statusFilter == 'Todas') return true;
    return _status(d) == _statusFilter;
  }

  bool _matchSearch(Map<String, dynamic> d) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      (d['title'] ?? '').toString(),
      (d['description'] ?? '').toString(),
      (d['status'] ?? '').toString(),
      (d['customerName'] ?? '').toString(),
      (d['vehicleTitle'] ?? '').toString(),
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  num _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _date(dynamic ts) {
    if (ts is Timestamp) return _dateFmt.format(ts.toDate());
    return '';
  }

  Future<_PickedCustomer?> _pickCustomer() async {
    final snap = await _customersCol.orderBy('name').get();
    final docs = snap.docs;
    if (!mounted) return null;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay clientes registrados todavia.')),
      );
      return null;
    }

    return showDialog<_PickedCustomer>(
      context: context,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = docs.where((doc) {
              final d = doc.data();
              final hay = [
                (d['name'] ?? '').toString(),
                (d['phone'] ?? '').toString(),
                (d['ruc'] ?? '').toString(),
              ].join(' ').toLowerCase();
              return hay.contains(q.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Seleccionar cliente'),
              content: SizedBox(
                width: 500,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar cliente',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocal(() => q = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Sin resultados'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final doc = filtered[i];
                                final d = doc.data();
                                final name = (d['name'] ?? 'Cliente')
                                    .toString()
                                    .trim();
                                return ListTile(
                                  leading: const Icon(
                                    Icons.people_alt_outlined,
                                  ),
                                  title: Text(name.isEmpty ? 'Cliente' : name),
                                  onTap: () => Navigator.pop(
                                    ctx,
                                    _PickedCustomer(
                                      customerId: doc.id,
                                      customerName: name.isEmpty
                                          ? 'Cliente'
                                          : name,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_PickedVehicle?> _pickVehicle(String customerId) async {
    final snap = await _customersCol
        .doc(customerId)
        .collection('vehicles')
        .orderBy('updatedAt', descending: true)
        .get();
    final docs = snap.docs;
    if (!mounted) return null;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este cliente no tiene vehiculos.')),
      );
      return null;
    }

    return showDialog<_PickedVehicle>(
      context: context,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = docs.where((doc) {
              final d = doc.data();
              final hay = [
                (d['brand'] ?? '').toString(),
                (d['model'] ?? '').toString(),
                (d['plate'] ?? '').toString(),
                (d['year'] ?? '').toString(),
              ].join(' ').toLowerCase();
              return hay.contains(q.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Seleccionar vehiculo'),
              content: SizedBox(
                width: 500,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar vehiculo',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocal(() => q = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Sin resultados'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final doc = filtered[i];
                                final title = _vehicleTitleFromData(doc.data());
                                return ListTile(
                                  leading: const Icon(
                                    Icons.directions_car_filled_outlined,
                                  ),
                                  title: Text(title),
                                  onTap: () => Navigator.pop(
                                    ctx,
                                    _PickedVehicle(
                                      vehicleId: doc.id,
                                      vehicleTitle: title,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openNewRepair() async {
    final pickedCustomer = await _pickCustomer();
    if (pickedCustomer == null || !mounted) return;

    final pickedVehicle = await _pickVehicle(pickedCustomer.customerId);
    if (pickedVehicle == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepairFormScreen(
          customerId: pickedCustomer.customerId,
          customerName: pickedCustomer.customerName,
          vehicleId: pickedVehicle.vehicleId,
          vehicleTitle: pickedVehicle.vehicleTitle,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _openDetail(RepairHubItem item) async {
    final vehicleTitle = (item.data['vehicleTitle'] ?? '').toString().trim();
    final customerName = (item.data['customerName'] ?? '').toString().trim();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepairDetailScreen(
          customerId: item.customerId,
          vehicleId: item.vehicleId,
          vehicleTitle: vehicleTitle.isEmpty ? 'Vehiculo' : vehicleTitle,
          repairId: item.repairId,
          customerName: customerName,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reparaciones')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewRepair,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Buscar (titulo, estado, cliente, vehiculo)',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _statusOptions.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final s = _statusOptions[i];
                  return FilterChip(
                    label: Text(s),
                    selected: _statusFilter == s,
                    onSelected: (_) => setState(() => _statusFilter = s),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<List<RepairHubItem>>(
                future: _futureRepairs,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final all = snap.data ?? [];
                  final filtered = all
                      .where((e) => _matchSearch(e.data))
                      .where((e) => _matchStatus(e.data))
                      .toList();

                  num total = 0;
                  for (final e in filtered) {
                    total += _num(e.data['total']);
                  }

                  final summary = Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.summarize_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mostrando ${filtered.length} / ${all.length}   •   Total: ${_gsFmt.format(total.round())}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (filtered.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        children: [
                          summary,
                          const SizedBox(height: 12),
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.build_circle_outlined, size: 56),
                                  SizedBox(height: 12),
                                  Text(
                                    'No hay reparaciones con ese filtro/busqueda.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.separated(
                      itemCount: filtered.length + 1,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        if (i == 0) return summary;
                        final item = filtered[i - 1];
                        final d = item.data;
                        final title = (d['title'] ?? '').toString().trim();
                        final status = _status(d);
                        final customerName = (d['customerName'] ?? '')
                            .toString()
                            .trim();
                        final vehicleTitle = (d['vehicleTitle'] ?? '')
                            .toString()
                            .trim();
                        final date = _date(d['createdAt']);
                        final totalGs = _gsFmt.format(_num(d['total']).round());

                        final subtitle = [
                          '${customerName.isEmpty ? 'Cliente' : customerName} • ${vehicleTitle.isEmpty ? 'Vehiculo' : vehicleTitle}',
                          if (date.isNotEmpty) 'Fecha: $date',
                          'Total: $totalGs',
                        ].join('   •   ');

                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.build),
                            ),
                            title: Text(
                              title.isEmpty ? '(Sin titulo)' : title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _StatusPill(status: status),
                            onTap: () => _openDetail(item),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedCustomer {
  final String customerId;
  final String customerName;

  const _PickedCustomer({required this.customerId, required this.customerName});
}

class _PickedVehicle {
  final String vehicleId;
  final String vehicleTitle;

  const _PickedVehicle({required this.vehicleId, required this.vehicleTitle});
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.trim().isEmpty ? 'Abierta' : status.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(s, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
