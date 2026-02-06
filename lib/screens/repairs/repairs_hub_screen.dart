import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'repair_detail_screen.dart';

class RepairsHubScreen extends StatefulWidget {
  const RepairsHubScreen({super.key});

  @override
  State<RepairsHubScreen> createState() => _RepairsHubScreenState();
}

class _RepairsHubScreenState extends State<RepairsHubScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _statusFilter = 'Todas';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _PathInfo _pathInfo(DocumentReference<Map<String, dynamic>> ref) {
    final s = ref.path.split('/');
    if (s.length >= 8 &&
        s[0] == 'users' &&
        s[1] == _uid &&
        s[2] == 'customers' &&
        s[4] == 'vehicles' &&
        s[6] == 'repairs') {
      return _PathInfo(customerId: s[3], vehicleId: s[5]);
    }
    return const _PathInfo(customerId: null, vehicleId: null);
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

  Future<void> _openDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final info = _pathInfo(doc.reference);
    if (!info.valid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pude identificar cliente/vehículo de esta reparación')),
      );
      return;
    }

    final data = doc.data();
    final vehicleTitle = (data['vehicleTitle'] ?? '').toString().trim();
    final customerName = (data['customerName'] ?? '').toString().trim();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepairDetailScreen(
          customerId: info.customerId!,
          vehicleId: info.vehicleId!,
          vehicleTitle: vehicleTitle.isEmpty ? 'Vehículo' : vehicleTitle,
          repairId: doc.id,
          customerName: customerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reparaciones')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Buscar (título, estado, cliente, vehículo)',
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
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('repairs')
                    .orderBy('updatedAt', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data?.docs ?? [];
                  final scoped = docs.where((d) => _pathInfo(d.reference).valid).toList();
                  final filtered = scoped
                      .where((d) => _matchSearch(d.data()))
                      .where((d) => _matchStatus(d.data()))
                      .toList();

                  num total = 0;
                  for (final d in filtered) {
                    total += _num(d.data()['total']);
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
                              'Mostrando ${filtered.length} / ${scoped.length}   •   Total: ${_gsFmt.format(total.round())}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (filtered.isEmpty) {
                    return ListView(
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
                                Text('No hay reparaciones con ese filtro/búsqueda.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length + 1,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      if (i == 0) return summary;

                      final doc = filtered[i - 1];
                      final d = doc.data();
                      final info = _pathInfo(doc.reference);

                      final title = (d['title'] ?? '').toString().trim();
                      final status = _status(d);
                      final customerName = (d['customerName'] ?? '').toString().trim();
                      final vehicleTitle = (d['vehicleTitle'] ?? '').toString().trim();
                      final date = _date(d['createdAt']);
                      final totalGs = _gsFmt.format(_num(d['total']).round());

                      final customerText = customerName.isEmpty
                          ? 'Cliente: ${info.customerId ?? '-'}'
                          : customerName;
                      final vehicleText = vehicleTitle.isEmpty
                          ? 'Vehículo: ${info.vehicleId ?? '-'}'
                          : vehicleTitle;

                      final subtitle = [
                        '$customerText • $vehicleText',
                        if (date.isNotEmpty) 'Fecha: $date',
                        'Total: $totalGs',
                      ].join('   •   ');

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.build)),
                          title: Text(
                            title.isEmpty ? '(Sin título)' : title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _StatusPill(status: status),
                          onTap: () => _openDetail(doc),
                        ),
                      );
                    },
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

class _PathInfo {
  final String? customerId;
  final String? vehicleId;
  const _PathInfo({required this.customerId, required this.vehicleId});

  bool get valid => customerId != null && vehicleId != null;
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

