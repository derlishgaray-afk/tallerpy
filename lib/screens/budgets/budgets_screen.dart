import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/budgets/data/models/budget_model.dart';
import '../../features/budgets/data/repositories/budgets_repository.dart';
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
  static const int _pageSize = 25;

  final _search = TextEditingController();
  final _repo = BudgetsRepository();
  final List<BudgetModel> _docs = [];

  String _q = '';
  String _statusFilter = 'Todas';

  bool _loadingFirstPage = true;
  bool _loadingNextPage = false;
  bool _hasMore = true;
  Object? _loadError;

  static final NumberFormat _gsFmt = NumberFormat.decimalPattern('es_PY');
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  static const List<String> _statusOptions = ['Todas', 'Pendiente', 'Aprobado'];

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    unawaited(_resetAndLoad());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _resetAndLoad() async {
    if (!mounted) return;
    setState(() {
      _docs.clear();
      _hasMore = true;
      _loadError = null;
      _loadingFirstPage = true;
      _loadingNextPage = false;
    });
    await _loadNextPage(isFirstPage: true);
  }

  Future<void> _loadNextPage({bool isFirstPage = false}) async {
    if (_loadingNextPage) return;
    if (!isFirstPage && !_hasMore) return;

    if (!mounted) return;
    setState(() {
      _loadingNextPage = true;
      if (isFirstPage) _loadingFirstPage = true;
      _loadError = null;
    });

    try {
      final page = isFirstPage
          ? await _repo.fetchFirstPage(
              uid: _uid,
              customerId: widget.customerId,
              vehicleId: widget.vehicleId,
              statusFilter: _statusFilter,
              limit: _pageSize,
            )
          : await _repo.fetchNextPage(
              uid: _uid,
              customerId: widget.customerId,
              vehicleId: widget.vehicleId,
              statusFilter: _statusFilter,
              limit: _pageSize,
            );
      if (!mounted) return;

      setState(() {
        if (isFirstPage) {
          _docs.clear();
        }
        _docs.addAll(page.items);
        _hasMore = page.hasMore;
        _loadingFirstPage = false;
        _loadingNextPage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loadingFirstPage = false;
        _loadingNextPage = false;
      });
    }
  }

  bool _matchesSearch(BudgetModel budget) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;

    final hay = [
      budget.customerName,
      budget.vehicleTitle,
      budget.problemDescription,
      budget.observations,
      budget.status,
    ].join(' ').toLowerCase();

    return hay.contains(q);
  }

  String _gs(num n) => _gsFmt.format(n.round());

  String _date(DateTime? value) {
    if (value == null) return '';
    return _dateFmt.format(value);
  }

  Map<String, dynamic> _toInitial(BudgetModel budget) {
    return {
      'title': budget.title,
      'customerId': budget.customerId,
      'customerName': budget.customerName,
      'vehicleId': budget.vehicleId,
      'vehicleTitle': budget.vehicleTitle,
      'date': budget.date,
      'problemDescription': budget.problemDescription,
      'estimatedDays': budget.estimatedDays,
      'usePartsItems': budget.usePartsItems,
      'partsItems': budget.partsItems.map((item) => item.toMap()).toList(),
      'partsEstimated': budget.partsEstimated,
      'laborEstimated': budget.laborEstimated,
      'totalEstimated': budget.totalEstimated,
      'observations': budget.observations,
      'status': budget.status,
    };
  }

  String _errorText(Object? error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return 'La consulta requiere un indice de Firestore. Crea el indice sugerido en consola.';
    }
    return 'Error: $error';
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
    if (!mounted) return;
    await _resetAndLoad();
  }

  @override
  Widget build(BuildContext context) {
    final customerTitle = widget.customerName?.trim() ?? '';
    final vehicleTitle = widget.vehicleTitle?.trim() ?? '';

    final appTitle = customerTitle.isEmpty
        ? 'Presupuestos'
        : 'Presupuestos - $customerTitle';

    final filtered = _docs.where(_matchesSearch).toList();

    num sumTotal = 0;
    for (final budget in filtered) {
      sumTotal += budget.totalEstimated;
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
                'Mostrando ${filtered.length} / ${_docs.length} cargados - Total estimado: ${_gs(sumTotal)} Gs.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(appTitle),
        bottom: vehicleTitle.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 10,
                  ),
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
                labelText: 'Buscar (cliente, vehiculo o descripcion)',
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
                    onSelected: (_) {
                      if (_statusFilter == s) return;
                      setState(() => _statusFilter = s);
                      unawaited(_resetAndLoad());
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loadingFirstPage && _docs.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _resetAndLoad,
                      child: ListView(
                        children: [
                          summary,
                          if (_loadError != null && _docs.isEmpty) ...[
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_errorText(_loadError)),
                                    const SizedBox(height: 10),
                                    FilledButton(
                                      onPressed: () =>
                                          _loadNextPage(isFirstPage: true),
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else if (filtered.isEmpty) ...[
                            const SizedBox(height: 12),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 56),
                                    SizedBox(height: 12),
                                    Text(
                                      'No hay presupuestos con ese filtro o busqueda.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 10),
                            ...filtered.map((budget) {
                              final customer =
                                  budget.customerName.trim().isEmpty
                                  ? 'Cliente'
                                  : budget.customerName.trim();
                              final vehicle = budget.vehicleTitle.trim().isEmpty
                                  ? 'Vehiculo'
                                  : budget.vehicleTitle.trim();
                              final problem = budget.problemDescription.trim();
                              final status = budget.status.trim().isEmpty
                                  ? 'Pendiente'
                                  : budget.status.trim();
                              final date = _date(budget.date);
                              final total = _gs(budget.totalEstimated);

                              final subtitleParts = <String>[
                                '$customer • $vehicle',
                                if (date.isNotEmpty) 'Fecha: $date',
                                'Total: $total Gs.',
                              ];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.receipt_long_outlined),
                                    ),
                                    title: Text(
                                      problem.isEmpty
                                          ? '(Sin descripcion)'
                                          : problem,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      subtitleParts.join('   •   '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: _StatusPill(status: status),
                                    onTap: () => _openForm(
                                      budgetId: budget.id,
                                      initial: _toInitial(budget),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                          if (_loadError != null && _docs.isNotEmpty) ...[
                            Card(
                              child: ListTile(
                                title: Text(_errorText(_loadError)),
                                trailing: TextButton(
                                  onPressed: _loadNextPage,
                                  child: const Text('Reintentar'),
                                ),
                              ),
                            ),
                          ],
                          if (_loadingNextPage)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          if (_hasMore && !_loadingNextPage)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: OutlinedButton(
                                  onPressed: _loadNextPage,
                                  child: const Text('Cargar mas'),
                                ),
                              ),
                            ),
                        ],
                      ),
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
