import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'repair_detail_screen.dart';
import 'repair_form_screen.dart';

class RepairsScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String vehicleId;
  final String vehicleTitle; // ej: "Volkswagen Amarok (SAC947)"

  const RepairsScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.vehicleId,
    required this.vehicleTitle,
  });

  @override
  State<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends State<RepairsScreen> {
  final _search = TextEditingController();
  String _q = '';

  // ✅ filtro por estado
  String _statusFilter = 'Todas';

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _repairsCol => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('customers')
      .doc(widget.customerId)
      .collection('vehicles')
      .doc(widget.vehicleId)
      .collection('repairs');

  // ===== Formatters (Paraguay) =====
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openNew() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepairFormScreen(
          customerId: widget.customerId,
          customerName: widget.customerName,
          vehicleId: widget.vehicleId,
          vehicleTitle: widget.vehicleTitle,
        ),
      ),
    );
  }

  void _openDetail(String repairId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepairDetailScreen(
          customerId: widget.customerId,
          vehicleId: widget.vehicleId,
          vehicleTitle: widget.vehicleTitle,
          repairId: repairId,
          customerName: widget.customerName,
        ),
      ),
    );
  }

  String _statusLabel(String raw) {
    final s = raw.trim();
    return s.isEmpty ? 'Abierta' : s;
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    if (_q.trim().isEmpty) return true;
    final q = _q.trim().toLowerCase();

    final title = (d['title'] ?? '').toString().toLowerCase();
    final desc = (d['description'] ?? '').toString().toLowerCase();
    final status = (d['status'] ?? '').toString().toLowerCase();
    final km = (d['km'] ?? '').toString().toLowerCase();

    return title.contains(q) ||
        desc.contains(q) ||
        status.contains(q) ||
        km.contains(q);
  }

  bool _matchesStatus(Map<String, dynamic> d) {
    if (_statusFilter == 'Todas') return true;
    final s = _statusLabel((d['status'] ?? '').toString());
    return s == _statusFilter;
  }

  // Para el resumen/suma
  num _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _gs(num n) => _gsFmt.format(n.round());

  String _kmText(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    final n = int.tryParse(digits);
    if (n == null) return t;
    return _gsFmt.format(n);
  }

  String _dateText(dynamic ts) {
    if (ts is Timestamp) return _dateFmt.format(ts.toDate());
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cust = widget.customerName.trim().isEmpty
        ? 'Cliente'
        : widget.customerName.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('Reparaciones - $cust'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.vehicleTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNew,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Buscar (título, estado, km)',
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

            // ✅ Chips de filtro
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _statusOptions.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final s = _statusOptions[i];
                  final selected = s == _statusFilter;
                  return FilterChip(
                    label: Text(s),
                    selected: selected,
                    onSelected: (_) => setState(() => _statusFilter = s),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _repairsCol
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

                  // 🔎 filtrado
                  final filtered = docs
                      .where((d) => _matchesSearch(d.data()))
                      .where((d) => _matchesStatus(d.data()))
                      .toList();

                  // ✅ resumen (sobre el filtrado)
                  num sumTotal = 0;
                  for (final doc in filtered) {
                    sumTotal += _num(doc.data()['total']);
                  }

                  // Resumen arriba de la lista
                  final summary = Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.summarize_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mostrando ${filtered.length} / ${docs.length}   •   Total: ${_gs(sumTotal)}',
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
                                Text(
                                  'No hay reparaciones con ese filtro/búsqueda.',
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Probá cambiar el estado o limpiar la búsqueda.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length + 1, // +1 para el resumen
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      if (i == 0) return summary;

                      final doc = filtered[i - 1];
                      final d = doc.data();

                      final title = (d['title'] ?? '').toString().trim();
                      final status = _statusLabel(
                        (d['status'] ?? '').toString(),
                      );

                      final km = _kmText((d['km'] ?? '').toString());
                      final total = _gs(_num(d['total']));
                      final createdAt = _dateText(d['createdAt']);

                      final subtitleParts = <String>[
                        if (km.isNotEmpty) 'Km: $km',
                        if (createdAt.isNotEmpty) 'Fecha: $createdAt',
                        if (total.isNotEmpty) 'Total: $total',
                      ];

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
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(subtitleParts.join('   •   ')),
                          trailing: _StatusPill(status: status),
                          onTap: () => _openDetail(doc.id),
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
