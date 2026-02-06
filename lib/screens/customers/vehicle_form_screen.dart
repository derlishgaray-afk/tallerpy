import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VehicleFormScreen extends StatefulWidget {
  final String customerId;
  final String? vehicleId;
  final Map<String, dynamic>? initial;

  const VehicleFormScreen({
    super.key,
    required this.customerId,
    this.vehicleId,
    this.initial,
  });

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _year = TextEditingController();
  final _chassis = TextEditingController();
  final _notes = TextEditingController();

  final _brandFocus = FocusNode();
  final _modelFocus = FocusNode();
  final _plateFocus = FocusNode();
  final _chassisFocus = FocusNode();

  bool _saving = false;

  // Cache local (para optionsBuilder sync)
  List<String> _brandTop = [];
  List<String> _brandRecent = [];

  List<String> _modelTop = [];
  List<String> _modelRecent = [];

  StreamSubscription? _brandTopSub;
  StreamSubscription? _brandRecentSub;
  StreamSubscription? _modelTopSub;
  StreamSubscription? _modelRecentSub;

  // Marcas principales (fallback + siempre sugeridas)
  static const List<String> _mainBrands = [
    'Toyota',
    'Volkswagen',
    'Chevrolet',
    'Hyundai',
    'Kia',
    'Nissan',
    'Ford',
    'Renault',
    'Fiat',
    'Peugeot',
    'Honda',
    'Mazda',
    'Mitsubishi',
    'Suzuki',
    'Jeep',
    'BMW',
    'Mercedes-Benz',
    'Audi',
    'Land Rover',
    'Volvo',
  ];

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  CollectionReference<Map<String, dynamic>> _vehiclesCol() {
    return _userDoc
        .collection('customers')
        .doc(widget.customerId)
        .collection('vehicles');
  }

  // Catálogo:
  // users/{uid}/catalog/brands/items/{brandId}
  CollectionReference<Map<String, dynamic>> get _brandsCol =>
      _userDoc.collection('catalog').doc('brands').collection('items');

  CollectionReference<Map<String, dynamic>> _modelsCol(String brandId) =>
      _brandsCol.doc(brandId).collection('models');

  // ===== Helpers =====
  String _norm(String s) => s.trim().toLowerCase();
  String _idFromName(String name) =>
      _norm(name).replaceAll(RegExp(r'\s+'), '_');

  // Paraguay: AAA000 o AAAA000 (acepta guiones/espacios, normaliza)
  String _plateNormalize(String input) {
    final up = input.toUpperCase();
    final only = up.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return only;
  }

  bool _plateIsValidPY(String plateNorm) {
    final re1 = RegExp(r'^[A-Z]{3}\d{3}$');
    final re2 = RegExp(r'^[A-Z]{4}\d{3}$');
    return re1.hasMatch(plateNorm) || re2.hasMatch(plateNorm);
  }

  String _chassisNormalize(String input) {
    // VIN/Chasis suele ser A-Z y 0-9 (sin espacios/guiones)
    final up = input.toUpperCase();
    return up.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  void _showProSnack(String message, {bool error = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Colores bien visibles en claro/oscuro
    final bg = error
        ? (isDark ? const Color(0xFFB3261E) : const Color(0xFFFFE1DD))
        : (isDark ? const Color(0xFF1B5E20) : const Color(0xFFE7F6EA));

    final fg = error
        ? (isDark ? Colors.white : const Color(0xFF5A0B05))
        : (isDark ? Colors.white : const Color(0xFF0F3D17));

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: fg)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        margin: const EdgeInsets.all(14),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ===== Init / Dispose =====
  @override
  void initState() {
    super.initState();

    final d = widget.initial ?? {};
    _brand.text = (d['brand'] ?? '').toString();
    _model.text = (d['model'] ?? '').toString();
    _plate.text = (d['plate'] ?? '').toString();
    _year.text = (d['year'] ?? '').toString();
    _chassis.text = (d['chassis'] ?? '').toString();
    _notes.text = (d['notes'] ?? '').toString();

    _listenBrandsTop();
    _listenBrandsRecent();

    // Si ya viene marca (edit), levantamos modelos de esa marca
    final b = _brand.text.trim();
    if (b.isNotEmpty) {
      _listenModelsForBrand(b);
    }

    // Si el usuario borra marca -> limpiezas
    _brand.addListener(() {
      final current = _brand.text.trim();
      if (current.isEmpty) {
        _stopModelListeners();
        if (mounted) {
          setState(() {
            _modelTop = [];
            _modelRecent = [];
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _brandTopSub?.cancel();
    _brandRecentSub?.cancel();
    _stopModelListeners();

    _brand.dispose();
    _model.dispose();
    _plate.dispose();
    _year.dispose();
    _chassis.dispose();
    _notes.dispose();

    _brandFocus.dispose();
    _modelFocus.dispose();
    _plateFocus.dispose();
    _chassisFocus.dispose();

    super.dispose();
  }

  void _stopModelListeners() {
    _modelTopSub?.cancel();
    _modelRecentSub?.cancel();
    _modelTopSub = null;
    _modelRecentSub = null;
  }

  // ===== Listeners (Top + Recent) =====
  void _listenBrandsTop() {
    _brandTopSub?.cancel();
    _brandTopSub = _brandsCol
        .orderBy('count', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
          final list = snap.docs
              .map((d) => (d.data()['name'] ?? '').toString().trim())
              .where((x) => x.isNotEmpty)
              .toList();
          if (mounted) setState(() => _brandTop = list);
        });
  }

  void _listenBrandsRecent() {
    _brandRecentSub?.cancel();
    _brandRecentSub = _brandsCol
        .orderBy('lastUsedAt', descending: true)
        .limit(10)
        .snapshots()
        .listen((snap) {
          final list = snap.docs
              .map((d) => (d.data()['name'] ?? '').toString().trim())
              .where((x) => x.isNotEmpty)
              .toList();
          if (mounted) setState(() => _brandRecent = list);
        });
  }

  void _listenModelsForBrand(String brandName) {
    _stopModelListeners();

    final brandId = _idFromName(brandName);

    _modelTopSub = _modelsCol(brandId)
        .orderBy('count', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
          final list = snap.docs
              .map((d) => (d.data()['name'] ?? '').toString().trim())
              .where((x) => x.isNotEmpty)
              .toList();
          if (mounted) setState(() => _modelTop = list);
        });

    _modelRecentSub = _modelsCol(brandId)
        .orderBy('lastUsedAt', descending: true)
        .limit(10)
        .snapshots()
        .listen((snap) {
          final list = snap.docs
              .map((d) => (d.data()['name'] ?? '').toString().trim())
              .where((x) => x.isNotEmpty)
              .toList();
          if (mounted) setState(() => _modelRecent = list);
        });
  }

  // ===== Autocomplete options =====
  Iterable<String> _mergeUnique(List<String> a, List<String> b) {
    final seen = <String>{};
    final out = <String>[];
    for (final x in [...a, ...b]) {
      final key = x.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (seen.add(key)) out.add(x);
    }
    return out;
  }

  Iterable<String> _filterRanked(Iterable<String> list, String q) {
    if (q.isEmpty) return list;
    final starts = <String>[];
    final contains = <String>[];
    for (final item in list) {
      final n = item.toLowerCase();
      if (n.startsWith(q)) {
        starts.add(item);
      } else if (n.contains(q)) {
        contains.add(item);
      }
    }
    return [...starts, ...contains];
  }

  List<String> _brandOptions(String query) {
    final q = _norm(query);

    // ✅ Siempre: principales + recientes + más usadas
    final base = _mergeUnique(
      _mainBrands,
      _mergeUnique(_brandRecent, _brandTop).toList(),
    ).toList();

    return _filterRanked(base, q).take(12).toList();
  }

  List<String> _modelOptions(String query) {
    // Modelo como lo tenés: si no hay marca no sugiere, y si no hay catálogo no inventa
    if (_brand.text.trim().isEmpty) return const [];

    final q = _norm(query);
    final base = _mergeUnique(_modelRecent, _modelTop).toList();
    if (base.isEmpty) return const [];

    return _filterRanked(base, q).take(12).toList();
  }

  void _onBrandSelected(String value) {
    final selected = value.trim();

    setState(() {
      _brand.text = selected;
      _model.clear();
      _modelTop = [];
      _modelRecent = [];
    });

    if (selected.isNotEmpty) {
      _listenModelsForBrand(selected);
      _modelFocus.requestFocus();
    }
  }

  void _onModelSelected(String value) {
    setState(() => _model.text = value.trim());
    _plateFocus.requestFocus();
  }

  // ===== Catalog learning =====
  Future<void> _touchCatalog({
    required String brand,
    required String model,
  }) async {
    final b = brand.trim();
    final m = model.trim();
    if (b.isEmpty) return;

    final brandId = _idFromName(b);
    final brandRef = _brandsCol.doc(brandId);

    final batch = FirebaseFirestore.instance.batch();

    batch.set(brandRef, {
      'name': b,
      'count': FieldValue.increment(1),
      'lastUsedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (m.isNotEmpty) {
      final modelId = _idFromName(m);
      final modelRef = brandRef.collection('models').doc(modelId);

      batch.set(modelRef, {
        'name': m,
        'count': FieldValue.increment(1),
        'lastUsedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  // ===== Plate uniqueness (por cliente) =====
  Future<bool> _plateExistsForCustomer(String plateNorm) async {
    final q = await _vehiclesCol()
        .where('plateNorm', isEqualTo: plateNorm)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return false;

    // si estoy editando, permitir si el doc encontrado es el mismo
    if (widget.vehicleId != null && q.docs.first.id == widget.vehicleId) {
      return false;
    }
    return true;
  }

  // ===== Save =====
  Future<void> _save() async {
    if (_brand.text.trim().isEmpty && _model.text.trim().isEmpty) {
      _showProSnack('Ingresá al menos Marca o Modelo', error: true);
      return;
    }

    // Año
    final yearTxt = _year.text.trim();
    if (yearTxt.isNotEmpty) {
      final y = int.tryParse(yearTxt);
      final max = DateTime.now().year + 1;
      if (y == null || y < 1950 || y > max) {
        _showProSnack('Año inválido', error: true);
        return;
      }
    }

    // Chapa PY (si se ingresó)
    final plateNorm = _plateNormalize(_plate.text);
    if (_plate.text.trim().isNotEmpty) {
      if (!_plateIsValidPY(plateNorm)) {
        _showProSnack(
          'Chapa inválida. Formatos: AAA000 o AAAA000',
          error: true,
        );
        return;
      }

      final exists = await _plateExistsForCustomer(plateNorm);
      if (exists) {
        _showProSnack(
          'Esta chapa ya está registrada para este cliente.\nPodés editar el vehículo existente.',
          error: true,
        );
        return;
      }
    }

    // Chasis (opcional) - normalizamos
    final chassisNorm = _chassisNormalize(_chassis.text);

    setState(() => _saving = true);

    final brandTxt = _brand.text.trim();
    final modelTxt = _model.text.trim();

    final data = <String, dynamic>{
      'brand': brandTxt,
      'model': modelTxt,
      'plate': plateNorm, // guardamos normalizado para mostrar consistente
      'plateNorm': plateNorm,
      'year': _year.text.trim(),
      'chassis': chassisNorm,
      'notes': _notes.text.trim(),
      'ownerUid': _uid,
      'customerId': widget.customerId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (widget.vehicleId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await _vehiclesCol().add(data);
      } else {
        await _vehiclesCol()
            .doc(widget.vehicleId)
            .set(data, SetOptions(merge: true));
      }

      // Aprender catálogo (marca/modelo)
      await _touchCatalog(brand: brandTxt, model: modelTxt);

      if (!mounted) return;
      Navigator.pop(context);
      _showProSnack('Vehículo guardado ✅');
    } catch (e) {
      if (!mounted) return;
      _showProSnack('Error al guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.vehicleId != null;
    final hasModelCatalog = _mergeUnique(_modelRecent, _modelTop).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar vehículo' : 'Nuevo vehículo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _ProAutocomplete(
              label: 'Marca',
              controller: _brand,
              focusNode: _brandFocus,
              optionsBuilder: _brandOptions,
              onSelected: _onBrandSelected,
              helperText:
                  'Sugerencias: marcas principales + últimas 10 + más usadas',
            ),
            const SizedBox(height: 12),
            _ProAutocomplete(
              label: 'Modelo',
              controller: _model,
              focusNode: _modelFocus,
              optionsBuilder: _modelOptions,
              onSelected: _onModelSelected,
              helperText: _brand.text.trim().isEmpty
                  ? 'Elegí una marca para sugerir modelos'
                  : (hasModelCatalog
                        ? 'Sugerencias: últimos 10 usados + más usados (por marca)'
                        : 'Todavía no hay modelos guardados para esta marca'),
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Chapa (AAA000 o AAAA000)',
              controller: _plate,
              focusNode: _plateFocus,
              textCapitalization: TextCapitalization.characters,
              helperText: 'Ej: ABC123 o ABCD123 (se normaliza automáticamente)',
            ),
            _Field(
              label: 'Año',
              controller: _year,
              keyboardType: TextInputType.number,
            ),
            _Field(
              label: 'N° de Chasis (VIN)',
              controller: _chassis,
              focusNode: _chassisFocus,
              textCapitalization: TextCapitalization.characters,
              helperText: 'Opcional. Se guarda en mayúsculas (sin espacios)',
            ),
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

/// Autocomplete pro (RawAutocomplete)
class _ProAutocomplete extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> Function(String query) optionsBuilder;
  final void Function(String value) onSelected;
  final String? helperText;

  const _ProAutocomplete({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.optionsBuilder,
    required this.onSelected,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) => optionsBuilder(value.text),
      displayStringForOption: (o) => o,
      onSelected: onSelected,
      fieldViewBuilder: (context, textCtrl, fNode, onFieldSubmitted) {
        return TextField(
          controller: textCtrl,
          focusNode: fNode,
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
            border: const OutlineInputBorder(),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList();
        if (opts.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final option = opts[i];
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? helperText;
  final TextCapitalization textCapitalization;

  const _Field({
    required this.label,
    required this.controller,
    this.focusNode,
    this.keyboardType,
    this.maxLines = 1,
    this.helperText,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
