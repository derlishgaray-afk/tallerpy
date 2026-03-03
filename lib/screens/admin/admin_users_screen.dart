import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/user_access_service.dart';

enum _UserStatusFilter { all, active, inactive }

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _usersCol = FirebaseFirestore.instance.collection('users');
  final _searchCtrl = TextEditingController();
  final _savingIds = <String>{};
  late final Future<bool> _isAdminFuture;

  String _search = '';
  _UserStatusFilter _statusFilter = _UserStatusFilter.all;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _isAdminFuture = _checkIsAdmin();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<bool> _checkIsAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final snap = await _usersCol.doc(user.uid).get();
      final data = snap.data();
      return data != null && data['isAdmin'] == true;
    } catch (_) {
      return false;
    }
  }

  bool _isSaving(String key) => _savingIds.contains(key);

  void _setSaving(String key, bool value) {
    setState(() {
      if (value) {
        _savingIds.add(key);
      } else {
        _savingIds.remove(key);
      }
    });
  }

  Future<void> _setUserActive({
    required String userId,
    required bool isActive,
  }) async {
    final key = 'active:$userId';
    if (_isSaving(key)) return;
    _setSaving(key, true);

    try {
      final payload = <String, dynamic>{
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isActive) {
        payload['activatedAt'] = FieldValue.serverTimestamp();
      } else {
        payload['deactivatedAt'] = FieldValue.serverTimestamp();
      }

      await _usersCol.doc(userId).set(payload, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar acceso: $e')),
      );
    } finally {
      if (mounted) _setSaving(key, false);
    }
  }

  Future<void> _setUserAdmin({
    required String userId,
    required bool isAdmin,
  }) async {
    final key = 'admin:$userId';
    if (_isSaving(key)) return;
    _setSaving(key, true);

    try {
      await _usersCol.doc(userId).set({
        'isAdmin': isAdmin,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar rol admin: $e')),
      );
    } finally {
      if (mounted) _setSaving(key, false);
    }
  }

  String _fmtDate(dynamic value) {
    final date = UserAccessService.readDate(value);
    if (date == null) return '-';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        // Fallback para textos mojibake legados.
        .replaceAll('Ã¡', 'a')
        .replaceAll('Ã ', 'a')
        .replaceAll('Ã¤', 'a')
        .replaceAll('Ã¢', 'a')
        .replaceAll('Ã©', 'e')
        .replaceAll('Ã¨', 'e')
        .replaceAll('Ã«', 'e')
        .replaceAll('Ãª', 'e')
        .replaceAll('Ã­', 'i')
        .replaceAll('Ã¬', 'i')
        .replaceAll('Ã¯', 'i')
        .replaceAll('Ã®', 'i')
        .replaceAll('Ã³', 'o')
        .replaceAll('Ã²', 'o')
        .replaceAll('Ã¶', 'o')
        .replaceAll('Ã´', 'o')
        .replaceAll('Ãº', 'u')
        .replaceAll('Ã¹', 'u')
        .replaceAll('Ã¼', 'u')
        .replaceAll('Ã»', 'u')
        .replaceAll('Ã±', 'n');
  }

  bool _matchesSearch(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final query = _normalize(_search);
    if (query.isEmpty) return true;

    final data = doc.data();
    final email = _normalize((data['email'] ?? '').toString());
    final name = _normalize((data['displayName'] ?? '').toString());
    final uid = _normalize(doc.id);

    final forceUid = query.startsWith('uid:');
    if (forceUid) {
      final uidQuery = query.substring(4).trim();
      if (uidQuery.isEmpty) return true;
      return uid.startsWith(uidQuery);
    }

    return email.contains(query) || name.contains(query) || uid.contains(query);
  }

  bool _matchesStatus(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final isActive = doc.data()['isActive'] == true;
    switch (_statusFilter) {
      case _UserStatusFilter.all:
        return true;
      case _UserStatusFilter.active:
        return isActive;
      case _UserStatusFilter.inactive:
        return !isActive;
    }
  }

  Widget _buildUserCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final email = (d['email'] ?? '').toString().trim();
    final name = (d['displayName'] ?? '').toString().trim();
    final isActive = d['isActive'] == true;
    final isAdmin = d['isAdmin'] == true;
    final trialEndsAt = _fmtDate(d['trialEndsAt']);
    final isSelf = doc.id == _currentUid;
    final activeBusy = _isSaving('active:${doc.id}');
    final adminBusy = _isSaving('admin:${doc.id}');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? '(Sin nombre)' : name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(email.isEmpty ? doc.id : email),
            const SizedBox(height: 2),
            Text('UID: ${doc.id}'),
            const SizedBox(height: 2),
            Text('Prueba hasta: $trialEndsAt'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _RightLabeledSwitch(
                    label: 'Activo',
                    value: isActive,
                    onChanged: activeBusy
                        ? null
                        : (v) => _setUserActive(userId: doc.id, isActive: v),
                  ),
                  _RightLabeledSwitch(
                    label: 'Admin',
                    value: isAdmin,
                    onChanged: (adminBusy || (isSelf && isAdmin))
                        ? null
                        : (v) => _setUserAdmin(userId: doc.id, isAdmin: v),
                  ),
                ],
              ),
            ),
            if (isSelf && isAdmin)
              const Text('No puedes quitarte tu propio rol admin desde aquí.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUid.isEmpty) {
      return const Scaffold(body: Center(child: Text('Sesión no disponible.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Panel Admin - Usuarios')),
      body: FutureBuilder<bool>(
        future: _isAdminFuture,
        builder: (context, adminSnap) {
          if (adminSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (adminSnap.data != true) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Acceso restringido.\nEste panel es sólo para administradores.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, email o UID',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() => _search = value.trim());
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Todo'),
                        selected: _statusFilter == _UserStatusFilter.all,
                        onSelected: (_) {
                          setState(() => _statusFilter = _UserStatusFilter.all);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Activo'),
                        selected: _statusFilter == _UserStatusFilter.active,
                        onSelected: (_) {
                          setState(
                            () => _statusFilter = _UserStatusFilter.active,
                          );
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Inactivo'),
                        selected: _statusFilter == _UserStatusFilter.inactive,
                        onSelected: (_) {
                          setState(
                            () => _statusFilter = _UserStatusFilter.inactive,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _usersCol.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No se pudo cargar usuarios.\n${snap.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final docs =
                        (snap.data?.docs ??
                                const <
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >[])
                            .where(
                              (doc) =>
                                  _matchesStatus(doc) && _matchesSearch(doc),
                            )
                            .toList();

                    docs.sort((a, b) {
                      final da = UserAccessService.readDate(
                        a.data()['createdAt'],
                      );
                      final db = UserAccessService.readDate(
                        b.data()['createdAt'],
                      );
                      if (da == null && db == null) return a.id.compareTo(b.id);
                      if (da == null) return 1;
                      if (db == null) return -1;
                      return db.compareTo(da);
                    });

                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('No hay usuarios que coincidan.'),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      itemCount: docs.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _buildUserCard(docs[index]),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RightLabeledSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _RightLabeledSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
