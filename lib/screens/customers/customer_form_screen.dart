import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CustomerFormScreen extends StatefulWidget {
  final String? customerId;
  final Map<String, dynamic>? initial;

  const CustomerFormScreen({super.key, this.customerId, this.initial});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _ruc = TextEditingController();
  final _notes = TextEditingController();

  bool _saving = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('customers');

  @override
  void initState() {
    super.initState();
    final d = widget.initial ?? {};
    _name.text = (d['name'] ?? '').toString();
    _phone.text = (d['phone'] ?? '').toString();
    _address.text = (d['address'] ?? '').toString();
    _ruc.text = (d['ruc'] ?? '').toString();
    _notes.text = (d['notes'] ?? '').toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _ruc.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El nombre es obligatorio')));
      return;
    }

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'ruc': _ruc.text.trim(),
      'notes': _notes.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (widget.customerId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await _col.add(data);
      } else {
        await _col.doc(widget.customerId).set(data, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente guardado ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.customerId != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Editar cliente' : 'Nuevo cliente')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _Field(label: 'Nombre *', controller: _name),
            _Field(
              label: 'Teléfono',
              controller: _phone,
              keyboardType: TextInputType.phone,
            ),
            _Field(label: 'Dirección', controller: _address),
            _Field(label: 'RUC / CI', controller: _ruc),
            _Field(label: 'Observaciones', controller: _notes, maxLines: 3),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;

  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
