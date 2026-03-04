import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/customers/data/models/customer_model.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  String _q = '';

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<CustomerModel> get _col =>
      CustomerModel.collectionForUser(FirebaseFirestore.instance, _uid);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> _toInitial(CustomerModel customer) {
    return {
      'name': customer.name,
      'phone': customer.phone,
      'address': customer.address,
      'ruc': customer.ruc,
      'notes': customer.notes,
    };
  }

  void _openForm({String? id, CustomerModel? data}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          customerId: id,
          initial: data == null ? null : _toInitial(data),
        ),
      ),
    );
  }

  void _openDetail(String customerId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customerId: customerId),
      ),
    );
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: const Text('¿Seguro que querés eliminar este cliente?'),
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
    await _col.doc(id).delete();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cliente eliminado ✅')));
  }

  bool _matches(CustomerModel customer) {
    if (_q.trim().isEmpty) return true;
    final name = customer.name.toLowerCase();
    final phone = customer.phone.toLowerCase();
    final ruc = customer.ruc.toLowerCase();
    return name.contains(_q) || phone.contains(_q) || ruc.contains(_q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
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
                labelText: 'Buscar (nombre, teléfono o RUC)',
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
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<CustomerModel>>(
                stream: _col.orderBy('name').snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }

                  final docs = snap.data?.docs ?? [];
                  final filtered = docs
                      .where((d) => _matches(d.data()))
                      .toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No hay clientes todavía.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final doc = filtered[i];
                      final customer = doc.data();

                      final name = customer.name;
                      final phone = customer.phone;
                      final ruc = customer.ruc;

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          title: Text(
                            name.isEmpty ? '(Sin nombre)' : name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            [
                              if (phone.isNotEmpty) '📞 $phone',
                              if (ruc.isNotEmpty) '🧾 RUC/CI: $ruc',
                            ].join('   '),
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'view') {
                                _openDetail(doc.id);
                              } else if (v == 'edit') {
                                _openForm(id: doc.id, data: customer);
                              } else if (v == 'del') {
                                _delete(doc.id);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'view',
                                child: Text('Ver detalle'),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Editar'),
                              ),
                              PopupMenuItem(
                                value: 'del',
                                child: Text('Eliminar'),
                              ),
                            ],
                          ),

                          // ✅ PRO: tap abre el DETALLE (no el formulario)
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
