import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/repairs/data/models/repair_model.dart';
import '../../features/repairs/data/repositories/repairs_repository.dart';
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
  static const int _pageSize = 25;

  final _search = TextEditingController();
  final _repo = RepairsRepository();
  final List<RepairModel> _docs = [];

  String _q = '';
  String _statusFilter = 'Todas';

  bool _loadingFirstPage = true;
  bool _loadingNextPage = false;
  bool _hasMore = true;
  Object? _loadError;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

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
        if (isFirstPage) _docs.clear();
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

  String _statusLabel(String raw) {
    final s = raw.trim();
    return s.isEmpty ? 'Abierta' : s;
  }

  bool _matchesSearch(RepairModel repair) {
    if (_q.trim().isEmpty) return true;
    final q = _q.trim().toLowerCase();

    final title = repair.title.toLowerCase();
    final desc = repair.description.toLowerCase();
    final status = repair.status.toLowerCase();
    final km = repair.km.toLowerCase();

    return title.contains(q) ||
        desc.contains(q) ||
        status.contains(q) ||
        km.contains(q);
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

  String _dateText(DateTime? value) {
    if (value == null) return '';
    return _dateFmt.format(value);
  }

  String _errorText(Object? error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return 'La consulta requiere un indice de Firestore. Crea el indice sugerido en consola.';
    }
    return 'Error: $error';
  }

  Future<void> _openNew() async {
    await Navigator.push(
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
    if (!mounted) return;
    await _resetAndLoad();
  }

  Future<void> _openDetail(String repairId) async {
    await Navigator.push(
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
    if (!mounted) return;
    await _resetAndLoad();
  }

  @override
  Widget build(BuildContext context) {
    final cust = widget.customerName.trim().isEmpty
        ? 'Cliente'
        : widget.customerName.trim();

    final filtered = _docs.where(_matchesSearch).toList();

    num sumTotal = 0;
    for (final repair in filtered) {
      sumTotal += repair.total;
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
                'Mostrando ${filtered.length} / ${_docs.length} cargados - Total: ${_gs(sumTotal)}',
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
                labelText: 'Buscar (titulo, estado, km)',
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
                    selected: s == _statusFilter,
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
                                    Icon(Icons.build_circle_outlined, size: 56),
                                    SizedBox(height: 12),
                                    Text(
                                      'No hay reparaciones con ese filtro o busqueda.',
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Prueba con otro estado o limpia la busqueda.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 10),
                            ...filtered.map((repair) {
                              final title = repair.title.trim();
                              final status = _statusLabel(repair.status);
                              final km = _kmText(repair.km);
                              final total = _gs(repair.total);
                              final createdAt = _dateText(repair.createdAt);

                              final subtitleParts = <String>[
                                if (km.isNotEmpty) 'Km: $km',
                                if (createdAt.isNotEmpty) 'Fecha: $createdAt',
                                if (total.isNotEmpty) 'Total: $total',
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
                                      child: Icon(Icons.build),
                                    ),
                                    title: Text(
                                      title.isEmpty ? '(Sin titulo)' : title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: subtitleParts.isEmpty
                                        ? null
                                        : Text(subtitleParts.join('   •   ')),
                                    trailing: _StatusPill(status: status),
                                    onTap: () => _openDetail(repair.id),
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
