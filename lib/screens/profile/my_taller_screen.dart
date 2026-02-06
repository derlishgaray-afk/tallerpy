import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MyTallerScreen extends StatefulWidget {
  const MyTallerScreen({super.key});

  @override
  State<MyTallerScreen> createState() => _MyTallerScreenState();
}

class _MyTallerScreenState extends State<MyTallerScreen> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _ruc = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> _ref() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Future<void> _load() async {
    try {
      final snap = await _ref().get();
      final data = snap.data() ?? {};
      final profile = (data['profile'] as Map<String, dynamic>?) ?? {};

      _name.text = (profile['name'] ?? '').toString();
      _owner.text = (profile['owner'] ?? '').toString();
      _address.text = (profile['address'] ?? '').toString();
      _phone.text = (profile['phone'] ?? '').toString();
      _ruc.text = (profile['ruc'] ?? '').toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre del taller es obligatorio')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _ref().set({
        'profile': {
          'name': _name.text.trim(),
          'owner': _owner.text.trim(),
          'address': _address.text.trim(),
          'phone': _phone.text.trim(),
          'ruc': _ruc.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos del taller guardados ✅')),
      );
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
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _address.dispose();
    _phone.dispose();
    _ruc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi Taller')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  _Field(label: 'Nombre del taller', controller: _name),
                  _Field(label: 'Propietario', controller: _owner),
                  _Field(label: 'Dirección', controller: _address),
                  _Field(
                    label: 'Teléfono',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                  ),
                  _Field(label: 'RUC', controller: _ruc),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
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

  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
