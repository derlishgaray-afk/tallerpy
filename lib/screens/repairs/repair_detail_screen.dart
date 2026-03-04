import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/repairs/data/models/repair_model.dart';
import '../../features/repairs/data/repositories/repairs_repository.dart';
import 'repair_form_screen.dart';

class RepairDetailScreen extends StatelessWidget {
  final String customerId;
  final String? customerName;
  final String vehicleId;
  final String vehicleTitle;
  final String repairId;
  final RepairsRepository _repo = RepairsRepository();

  RepairDetailScreen({
    super.key,
    required this.customerId,
    this.customerName,
    required this.vehicleId,
    required this.vehicleTitle,
    required this.repairId,
  });

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Stream<RepairModel?> _repairStream() {
    return _repo.watchRepairById(
      uid: _uid,
      customerId: customerId,
      vehicleId: vehicleId,
      repairId: repairId,
    );
  }

  // ===== Formatters (Paraguay) =====
  static final NumberFormat _gsFmt = NumberFormat.decimalPattern('es_PY');
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  String _gs(dynamic v) {
    if (v == null) return '0';
    final n = (v is num) ? v : num.tryParse(v.toString());
    if (n == null) return '0';
    return _gsFmt.format(n.round());
  }

  String _kmText(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    final n = int.tryParse(digits);
    if (n == null) return t; // si viene raro, mostramos tal cual
    return _gsFmt.format(n); // mismo separador de miles
  }

  String _date(DateTime? value, {bool withTime = false}) {
    if (value == null) return '';
    return withTime ? _dateTimeFmt.format(value) : _dateFmt.format(value);
  }

  Map<String, dynamic> _toInitial(RepairModel repair) {
    return {
      'title': repair.title,
      'km': repair.km,
      'description': repair.description,
      'status': repair.status,
      'labor': repair.labor,
      'parts': repair.parts,
      'total': repair.total,
      'createdAt': repair.createdAt,
      'updatedAt': repair.updatedAt,
    };
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar reparación'),
        content: const Text('¿Seguro que querés eliminar esta reparación?'),
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

    await _repo.deleteRepair(
      uid: _uid,
      customerId: customerId,
      vehicleId: vehicleId,
      repairId: repairId,
    );

    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Reparación eliminada ✅')));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RepairModel?>(
      stream: _repairStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Reparación')),
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
            appBar: AppBar(title: Text('Reparación')),
            body: Center(child: Text('Cargando...')),
          );
        }

        final repair = snap.data;
        if (repair == null) {
          return Scaffold(
            appBar: AppBar(title: Text('Reparación')),
            body: Center(child: Text('Reparación no encontrada')),
          );
        }

        final title = repair.title.trim();
        final status = repair.status.trim();
        final kmRaw = repair.km;
        final km = _kmText(kmRaw);
        final desc = repair.description.trim();

        final labor = _gs(repair.labor);
        final parts = _gs(repair.parts);
        final total = _gs(repair.total);

        final createdAt = _date(repair.createdAt, withTime: true);
        final updatedAt = _date(repair.updatedAt, withTime: true);

        final statusLabel = status.isEmpty ? 'Abierta' : status;

        return Scaffold(
          appBar: AppBar(
            title: Text(title.isEmpty ? 'Reparación' : title),
            bottom: PreferredSize(
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
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepairFormScreen(
                        customerId: customerId,
                        customerName: customerName,
                        vehicleId: vehicleId,
                        vehicleTitle: vehicleTitle,
                        repairId: repairId,
                        initial: _toInitial(repair),
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Eliminar',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context),
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
                        Row(
                          children: [
                            const Icon(Icons.flag_outlined, size: 18),
                            const SizedBox(width: 8),
                            _StatusPill(text: statusLabel),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(label: 'Km', value: km),
                        _InfoRow(label: 'Creada', value: createdAt),
                        _InfoRow(label: 'Actualizada', value: updatedAt),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalle',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(desc.isEmpty ? '—' : desc),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Costos (Gs)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(label: 'Mano de obra', value: labor),
                        _InfoRow(label: 'Repuestos', value: parts),
                        const Divider(),
                        _InfoRow(label: 'Total', value: total, bold: true),
                      ],
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

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = text.trim().isEmpty ? 'Abierta' : text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(t, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InfoRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final v = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
