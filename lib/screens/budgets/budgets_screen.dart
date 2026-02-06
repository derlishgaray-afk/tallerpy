import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'budget_form_screen.dart';

class BudgetsScreen extends StatefulWidget {
  final String? customerId;
  final String? customerName;
  final String? vehicleId;
  final String? vehicleTitle;

  const BudgetsScreen({
    super.key,
    this.customerId,
    this.customerName,
    this.vehicleId,
    this.vehicleTitle,
  });

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _statusFilter = 'Todas';

  static final NumberFormat _gsFmt = NumberFormat.decimalPattern('es_PY');
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  static const List<String> _statusOptions = ['Todas', 'Pendiente', 'Aprobado'];

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _budgetsCol => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('budgets');

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesFixedScope(Map<String, dynamic> d) {
    if (widget.customerId != null &&
        d['customerId'].toString().trim() != widget.customerId) {
      return false;
    }
    if (widget.vehicleId != null &&
        d['vehicleId'].toString().trim() != widget.vehicleId) {
      return false;
    }
    return true;
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;

    final hay = [
      (d['customerName'] ?? '').toString(),
      (d['vehicleTitle'] ?? '').toString(),
      (d['problemDescription'] ?? '').toString(),
      (d['observations'] ?? '').toString(),
      (d['status'] ?? '').toString(),
    ].join(' ').toLowerCase();

    return hay.contains(q);
  }

  bool _matchesStatus(Map<String, dynamic> d) {
    if (_statusFilter == 'Todas') return true;
    final s = (d['status'] ?? 'Pendiente').toString().trim();
    return s == _statusFilter;
  }

  num _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _gs(num n) => _gsFmt.format(n.round());

  String _date(dynamic v) {
    if (v is Timestamp) {
      return _dateFmt.format(v.toDate());
    }
    return '';
  }

  Future<void> _openForm({
    String? budgetId,
    Map<String, dynamic>? initial,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BudgetFormScreen(
          budgetId: budgetId,
          initial: initial,
          initialCustomerId: widget.customerId,
          initialCustomerName: widget.customerName,
          initialVehicleId: widget.vehicleId,
          initialVehicleTitle: widget.vehicleTitle,
          lockCustomer: widget.customerId != null,
          lockVehicle: widget.vehicleId != null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerTitle = widget.customerName?.trim() ?? '';
    final vehicleTitle = widget.vehicleTitle?.trim() ?? '';

    final appTitle = customerTitle.isEmpty
        ? 'Presupuestos'
        : 'Presupuestos - $customerTitle';

    return Scaffold(
      appBar: AppBar(
        title: Text(appTitle),
        bottom: vehicleTitle.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      vehicleTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Buscar (cliente, vehículo o descripción)',
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
                stream: _budgetsCol.orderBy('updatedAt', descending: true).snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data?.docs ?? [];
                  final filtered = docs
                      .where((d) => _matchesFixedScope(d.data()))
                      .where((d) => _matchesSearch(d.data()))
                      .where((d) => _matchesStatus(d.data()))
                      .toList();

                  num sumTotal = 0;
                  for (final d in filtered) {
                    sumTotal += _num(d.data()['totalEstimated']);
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
                              'Mostrando ${filtered.length} / ${docs.length}   •   Total estimado: ${_gs(sumTotal)} Gs.',
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
                                Icon(Icons.receipt_long_outlined, size: 56),
                                SizedBox(height: 12),
                                Text('No hay presupuestos con ese filtro/búsqueda.'),
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

                      final customer = (d['customerName'] ?? 'Cliente')
                          .toString()
                          .trim();
                      final vehicle = (d['vehicleTitle'] ?? 'Vehículo')
                          .toString()
                          .trim();
                      final problem = (d['problemDescription'] ?? '')
                          .toString()
                          .trim();
                      final status = (d['status'] ?? 'Pendiente').toString().trim();
                      final date = _date(d['date']);
                      final total = _gs(_num(d['totalEstimated']));

                      final subtitleParts = <String>[
                        '$customer • $vehicle',
                        if (date.isNotEmpty) 'Fecha: $date',
                        'Total: $total Gs.',
                      ];

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.receipt_long_outlined),
                          ),
                          title: Text(
                            problem.isEmpty ? '(Sin descripción)' : problem,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            subtitleParts.join('   •   '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _StatusPill(status: status),
                          onTap: () => _openForm(budgetId: doc.id, initial: d),
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
    final s = status.trim().isEmpty ? 'Pendiente' : status.trim();
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

