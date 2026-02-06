import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../utils/speech_web.dart';
import '../repairs/repair_detail_screen.dart';

class BudgetFormScreen extends StatefulWidget {
  final String? budgetId;
  final Map<String, dynamic>? initial;
  final String? initialCustomerId;
  final String? initialCustomerName;
  final String? initialVehicleId;
  final String? initialVehicleTitle;
  final bool lockCustomer;
  final bool lockVehicle;

  const BudgetFormScreen({
    super.key,
    this.budgetId,
    this.initial,
    this.initialCustomerId,
    this.initialCustomerName,
    this.initialVehicleId,
    this.initialVehicleTitle,
    this.lockCustomer = false,
    this.lockVehicle = false,
  });

  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

enum DictationMode { add, replace }

class _LocalePick {
  final String? localeId;
  final bool hasSpanish;
  const _LocalePick({required this.localeId, required this.hasSpanish});
}

class _BudgetFormScreenState extends State<BudgetFormScreen> {
  final _problem = TextEditingController();
  final _days = TextEditingController();
  final _parts = TextEditingController();
  final _labor = TextEditingController();
  final _obs = TextEditingController();

  String? _customerId;
  String _customerName = '';
  String? _vehicleId;
  String _vehicleTitle = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _vehicleDocs = [];

  DateTime _date = DateTime.now();
  String _status = 'Pendiente';
  String? _currentBudgetId;

  bool _saving = false;
  bool _sharing = false;
  bool _approving = false;
  bool _loadingVehicles = false;

  final NumberFormat _gsFmt = NumberFormat.decimalPattern('es_PY');
  final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  // Dictado
  DictationMode _mode = DictationMode.add;
  bool _listening = false;
  String _dictBase = '';
  String _lastPartial = '';
  String _lastFinalNorm = '';
  int _lastFinalMs = 0;
  Timer? _partialDebounce;
  String _pendingPartialText = '';

  final stt.SpeechToText _speechMobile = stt.SpeechToText();
  bool _mobileReady = false;
  String? _mobileLocaleId;
  bool _mobileHasSpanish = true;
  bool _mobileLocaleSnackShown = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _budgetsCol => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('budgets');

  CollectionReference<Map<String, dynamic>> get _customersCol => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('customers');

  CollectionReference<Map<String, dynamic>> _vehiclesCol(String customerId) {
    return _customersCol.doc(customerId).collection('vehicles');
  }

  @override
  void initState() {
    super.initState();
    _currentBudgetId = widget.budgetId;
    final d = widget.initial ?? <String, dynamic>{};

    _customerId = _firstNotEmpty(widget.initialCustomerId, d['customerId']);
    _customerName =
        _firstNotEmpty(widget.initialCustomerName, d['customerName']) ?? '';
    _vehicleId = _firstNotEmpty(widget.initialVehicleId, d['vehicleId']);
    _vehicleTitle =
        _firstNotEmpty(widget.initialVehicleTitle, d['vehicleTitle']) ?? '';

    _date = _parseDate(d['date']) ?? DateTime.now();
    _problem.text = (d['problemDescription'] ?? '').toString();
    _days.text = (d['estimatedDays'] ?? '').toString();
    _parts.text = _numToGsText(d['partsEstimated']);
    _labor.text = _numToGsText(d['laborEstimated']);
    _obs.text = (d['observations'] ?? '').toString();
    final s = (d['status'] ?? 'Pendiente').toString().trim();
    _status = s.isEmpty ? 'Pendiente' : s;

    if (_customerId != null) {
      _loadVehiclesForCustomer(_customerId!, keepSelection: true);
      _ensureNames();
    }

    if (kIsWeb && SpeechWeb.isSupported()) {
      SpeechWeb.setCallbacks(
        onPartial: _onWebPartial,
        onFinal: _onWebFinal,
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'stopped' || status == 'error') {
            setState(() => _listening = false);
          }
        },
        onError: (msg) {
          if (!mounted) return;
          setState(() => _listening = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Dictado (Web): $msg')));
        },
      );
    } else {
      _initMobileSpeech();
    }
  }

  @override
  void dispose() {
    _partialDebounce?.cancel();
    if (kIsWeb) {
      SpeechWeb.stop();
    } else {
      _speechMobile.stop();
    }
    _problem.dispose();
    _days.dispose();
    _parts.dispose();
    _labor.dispose();
    _obs.dispose();
    super.dispose();
  }

  String? _firstNotEmpty(dynamic a, dynamic b, [dynamic c]) {
    final values = [a, b, c];
    for (final v in values) {
      final t = (v ?? '').toString().trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _vehicleTitleFromData(Map<String, dynamic> d) {
    final brand = (d['brand'] ?? '').toString().trim();
    final model = (d['model'] ?? '').toString().trim();
    final plate = (d['plate'] ?? '').toString().trim();
    final base = [brand, model].where((e) => e.isNotEmpty).join(' ').trim();
    if (plate.isEmpty) return base.isEmpty ? 'Vehículo' : base;
    return base.isEmpty ? plate : '$base - $plate';
  }

  Future<void> _ensureNames() async {
    if (_customerId != null && _customerName.trim().isEmpty) {
      final s = await _customersCol.doc(_customerId).get();
      final d = s.data();
      if (d != null && mounted) {
        _customerName = (d['name'] ?? 'Cliente').toString().trim();
      }
    }
    if (_customerId != null && _vehicleId != null && _vehicleTitle.trim().isEmpty) {
      final s = await _vehiclesCol(_customerId!).doc(_vehicleId).get();
      final d = s.data();
      if (d != null && mounted) {
        _vehicleTitle = _vehicleTitleFromData(d);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadVehiclesForCustomer(
    String customerId, {
    bool keepSelection = false,
  }) async {
    if (mounted) setState(() => _loadingVehicles = true);
    try {
      final snap = await _vehiclesCol(customerId)
          .orderBy('updatedAt', descending: true)
          .get();
      if (!mounted) return;
      String? selectedId = keepSelection ? _vehicleId : null;
      String selectedTitle = keepSelection ? _vehicleTitle : '';
      if (keepSelection && selectedId != null) {
        bool exists = false;
        for (final doc in snap.docs) {
          if (doc.id == selectedId) {
            exists = true;
            selectedTitle = _vehicleTitleFromData(doc.data());
            break;
          }
        }
        if (!exists) {
          selectedId = null;
          selectedTitle = '';
        }
      }
      setState(() {
        _vehicleDocs = snap.docs;
        _vehicleId = selectedId;
        _vehicleTitle = selectedTitle;
      });
    } finally {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickCustomer() async {
    if (widget.lockCustomer || _saving || _approving) return;

    final snap = await _customersCol.orderBy('name').get();
    final docs = snap.docs;
    if (!mounted) return;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay clientes registrados todavía.')),
      );
      return;
    }

    final picked = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = docs.where((doc) {
              final d = doc.data();
              final hay = [
                (d['name'] ?? '').toString(),
                (d['phone'] ?? '').toString(),
                (d['ruc'] ?? '').toString(),
              ].join(' ').toLowerCase();
              return hay.contains(q.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Seleccionar cliente'),
              content: SizedBox(
                width: 500,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar cliente',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocal(() => q = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Sin resultados'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final doc = filtered[i];
                                final d = doc.data();
                                final name = (d['name'] ?? 'Cliente')
                                    .toString()
                                    .trim();
                                final phone = (d['phone'] ?? '').toString().trim();
                                return ListTile(
                                  leading: const Icon(Icons.people_alt_outlined),
                                  title: Text(name.isEmpty ? 'Cliente' : name),
                                  subtitle: phone.isEmpty ? null : Text(phone),
                                  onTap: () => Navigator.pop(ctx, doc),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;
    final d = picked.data();
    final name = (d['name'] ?? 'Cliente').toString().trim();
    setState(() {
      _customerId = picked.id;
      _customerName = name.isEmpty ? 'Cliente' : name;
      _vehicleId = null;
      _vehicleTitle = '';
      _vehicleDocs = [];
    });
    await _loadVehiclesForCustomer(picked.id);
  }

  Future<void> _pickVehicle() async {
    if (widget.lockVehicle || _saving || _approving) return;
    if (_customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero seleccioná un cliente.')),
      );
      return;
    }

    if (_vehicleDocs.isEmpty) {
      await _loadVehiclesForCustomer(_customerId!, keepSelection: true);
    }
    if (!mounted) return;
    if (_vehicleDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este cliente no tiene vehículos.')),
      );
      return;
    }

    final picked = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = _vehicleDocs.where((doc) {
              final d = doc.data();
              final hay = [
                (d['brand'] ?? '').toString(),
                (d['model'] ?? '').toString(),
                (d['plate'] ?? '').toString(),
                (d['year'] ?? '').toString(),
              ].join(' ').toLowerCase();
              return hay.contains(q.toLowerCase());
            }).toList();
            return AlertDialog(
              title: const Text('Seleccionar vehículo'),
              content: SizedBox(
                width: 500,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar vehículo',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocal(() => q = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Sin resultados'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final doc = filtered[i];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.directions_car_filled_outlined,
                                  ),
                                  title: Text(_vehicleTitleFromData(doc.data())),
                                  onTap: () => Navigator.pop(ctx, doc),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _vehicleId = picked.id;
      _vehicleTitle = _vehicleTitleFromData(picked.data());
    });
  }

  bool _shouldIgnoreFinal(String text) {
    final norm = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final now = DateTime.now().millisecondsSinceEpoch;
    final same = norm.isNotEmpty && norm == _lastFinalNorm;
    final tooSoon = (now - _lastFinalMs) < 1200;
    if (same && tooSoon) return true;
    _lastFinalNorm = norm;
    _lastFinalMs = now;
    return false;
  }

  String _numToGsText(dynamic v) {
    if (v == null) return '';
    final n = (v is num) ? v : num.tryParse(v.toString());
    if (n == null) return '';
    return _gsFmt.format(n.round());
  }

  num _parseGs(String s) {
    final digits = s.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return num.tryParse(digits) ?? 0;
  }

  String _formatGsFromDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final n = num.tryParse(digits);
    if (n == null) return '';
    return _gsFmt.format(n.round());
  }

  int _parseDays() {
    final digits = _days.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  num get _total => _parseGs(_labor.text) + _parseGs(_parts.text);
  String get _totalText => _gsFmt.format(_total.round());

  Future<void> _initMobileSpeech() async {
    if (kIsWeb) return;
    try {
      final ok = await _speechMobile.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'notListening') setState(() => _listening = false);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _listening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dictado (App): ${e.errorMsg}')),
          );
        },
      );
      if (mounted) setState(() => _mobileReady = ok);
      if (ok) await _logAvailableLocales();
    } catch (_) {
      if (mounted) setState(() => _mobileReady = false);
    }
  }

  Future<void> _logAvailableLocales() async {
    try {
      final locales = await _speechMobile.locales();
      final system = await _speechMobile.systemLocale();
      final pick = _pickMobileLocaleId(locales, system?.localeId ?? '');
      _mobileLocaleId = pick.localeId;
      _mobileHasSpanish = pick.hasSpanish;
      if (!_mobileHasSpanish && !_mobileLocaleSnackShown && mounted) {
        _mobileLocaleSnackShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No encontré un locale de español; usaré el idioma del sistema.',
            ),
          ),
        );
      }
    } catch (_) {}
  }

  _LocalePick _pickMobileLocaleId(
    List<stt.LocaleName> locales,
    String systemId,
  ) {
    if (locales.isEmpty) {
      return const _LocalePick(localeId: null, hasSpanish: false);
    }
    final exactEs = locales.firstWhere(
      (l) => l.localeId == 'es-ES',
      orElse: () => locales.first,
    );
    if (exactEs.localeId == 'es-ES') {
      return _LocalePick(localeId: exactEs.localeId, hasSpanish: true);
    }
    final anyEs = locales.firstWhere(
      (l) => l.localeId.toLowerCase().startsWith('es'),
      orElse: () => locales.first,
    );
    if (anyEs.localeId.toLowerCase().startsWith('es')) {
      return _LocalePick(localeId: anyEs.localeId, hasSpanish: true);
    }
    final system = locales.firstWhere(
      (l) => l.localeId == systemId,
      orElse: () => locales.first,
    );
    return _LocalePick(localeId: system.localeId, hasSpanish: false);
  }

  void _setProblemText(String v) {
    if (_problem.text == v) return;
    _problem.value = _problem.value.copyWith(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    setState(() {});
  }

  void _schedulePartialUpdate(String v) {
    _pendingPartialText = v;
    _partialDebounce?.cancel();
    _partialDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted || !_listening) return;
      _setProblemText(_pendingPartialText);
    });
  }

  void _onWebPartial(String text) {
    if (!mounted || !_listening) return;
    if (_mode == DictationMode.replace) {
      _lastPartial = text.trim();
      final combined = _dictBase.isEmpty
          ? _lastPartial
          : (_lastPartial.isEmpty ? _dictBase : '$_dictBase $_lastPartial');
      _schedulePartialUpdate(combined.trim());
    }
  }

  void _onWebFinal(String text) {
    if (!mounted || !_listening) return;
    final finalText = text.trim();
    if (finalText.isEmpty || _shouldIgnoreFinal(finalText)) return;
    if (_mode == DictationMode.add) {
      final current = _problem.text.trim();
      if (current.isNotEmpty &&
          current.toLowerCase().endsWith(finalText.toLowerCase())) {
        return;
      }
      _setProblemText((current.isEmpty ? finalText : '$current $finalText').trim());
    } else {
      final base = _dictBase.trim();
      final next = base.isEmpty ? finalText : '$base $finalText';
      _dictBase = next.trim();
      _lastPartial = '';
      _setProblemText(_dictBase);
    }
  }

  void _resetDictationBase() {
    _dictBase = _problem.text.trim();
    _lastPartial = '';
  }

  Future<void> _toggleMic() async {
    if (_saving || _sharing || _approving) return;
    if (_listening) {
      if (kIsWeb) {
        SpeechWeb.stop();
      } else {
        await _speechMobile.stop();
      }
      _partialDebounce?.cancel();
      if (mounted) setState(() => _listening = false);
      return;
    }

    _resetDictationBase();
    if (kIsWeb) {
      if (!SpeechWeb.isSupported()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este navegador no soporta dictado por voz (Web).'),
          ),
        );
        return;
      }
      SpeechWeb.start(localeId: 'es-ES');
      if (mounted) setState(() => _listening = true);
      return;
    }

    if (!_mobileReady) {
      await _initMobileSpeech();
      if (!_mobileReady) return;
    }

    await _speechMobile.listen(
      localeId: _mobileLocaleId ?? 'es-ES',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (res) {
        if (!mounted) return;
        final text = res.recognizedWords.trim();
        if (text.isEmpty) return;
        if (_mode == DictationMode.add) {
          if (res.finalResult) {
            if (_shouldIgnoreFinal(text)) return;
            final current = _problem.text.trim();
            if (current.isNotEmpty &&
                current.toLowerCase().endsWith(text.toLowerCase())) {
              return;
            }
            _setProblemText((current.isEmpty ? text : '$current $text').trim());
          }
        } else {
          if (!res.finalResult) {
            _schedulePartialUpdate(
              (_dictBase.isEmpty ? text : '$_dictBase $text').trim(),
            );
          } else {
            if (_shouldIgnoreFinal(text)) return;
            _dictBase = (_dictBase.isEmpty ? text : '$_dictBase $text').trim();
            _setProblemText(_dictBase);
          }
        }
      },
    );
    if (mounted) setState(() => _listening = true);
  }

  void _clearProblem() {
    if (_listening) {
      if (kIsWeb) {
        SpeechWeb.stop();
      } else {
        _speechMobile.stop();
      }
      _partialDebounce?.cancel();
      setState(() => _listening = false);
    }
    _dictBase = '';
    _lastPartial = '';
    _setProblemText('');
  }

  void _setMode(DictationMode mode) {
    setState(() => _mode = mode);
    _resetDictationBase();
  }

  bool _validate() {
    if (_customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un cliente')),
      );
      return false;
    }
    if (_vehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un vehículo')),
      );
      return false;
    }
    if (_problem.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La descripción del problema es obligatoria')),
      );
      return false;
    }
    if (_parseDays() <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tiempo estimado inválido (en días)')),
      );
      return false;
    }
    return true;
  }

  Future<String?> _save({
    bool popAfterSave = true,
    bool showSnack = true,
  }) async {
    if (!_validate()) return null;
    if (_saving || _approving) return null;

    setState(() => _saving = true);
    try {
      final labor = _parseGs(_labor.text);
      final parts = _parseGs(_parts.text);
      final total = labor + parts;
      final data = <String, dynamic>{
        'customerId': _customerId,
        'customerName': _customerName.trim().isEmpty ? 'Cliente' : _customerName.trim(),
        'vehicleId': _vehicleId,
        'vehicleTitle': _vehicleTitle.trim().isEmpty ? 'Vehículo' : _vehicleTitle.trim(),
        'date': Timestamp.fromDate(DateTime(_date.year, _date.month, _date.day)),
        'problemDescription': _problem.text.trim(),
        'estimatedDays': _parseDays(),
        'partsEstimated': parts,
        'laborEstimated': labor,
        'totalEstimated': total,
        'observations': _obs.text.trim(),
        'status': _status.trim().isEmpty ? 'Pendiente' : _status.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_currentBudgetId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        final ref = await _budgetsCol.add(data);
        _currentBudgetId = ref.id;
        _status = 'Pendiente';
      } else {
        await _budgetsCol.doc(_currentBudgetId).set(data, SetOptions(merge: true));
      }

      if (!mounted) return _currentBudgetId;
      if (showSnack) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Presupuesto guardado')));
      }
      if (popAfterSave) Navigator.pop(context);
      return _currentBudgetId;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _buildRepairTitle() {
    final p = _problem.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (p.isNotEmpty) return p.length <= 70 ? p : '${p.substring(0, 67)}...';
    if (_vehicleTitle.trim().isNotEmpty) return 'Reparación - ${_vehicleTitle.trim()}';
    return 'Reparación aprobada desde presupuesto';
  }

  Future<void> _approveAndConvert() async {
    if (_approving || _saving) return;
    String? budgetId = _currentBudgetId;
    if (budgetId == null) {
      budgetId = await _save(popAfterSave: false, showSnack: false);
      if (budgetId == null) return;
    } else if (!_validate()) {
      return;
    }
    if (_customerId == null || _vehicleId == null) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprobar presupuesto'),
        content: const Text(
          'Se creará una reparación con estos datos y el presupuesto quedará aprobado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _approving = true);
    try {
      final labor = _parseGs(_labor.text);
      final parts = _parseGs(_parts.text);
      final total = labor + parts;
      final desc = _problem.text.trim();
      final obs = _obs.text.trim();
      final fullDesc = obs.isEmpty
          ? desc
          : '$desc\n\nObservaciones del presupuesto:\n$obs';

      final repairRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('customers')
          .doc(_customerId)
          .collection('vehicles')
          .doc(_vehicleId)
          .collection('repairs')
          .doc();

      final repairData = <String, dynamic>{
        'title': _buildRepairTitle(),
        'km': '',
        'description': fullDesc,
        'status': 'Abierta',
        'labor': labor,
        'parts': parts,
        'total': total,
        'customerId': _customerId,
        'customerName': _customerName,
        'vehicleId': _vehicleId,
        'vehicleTitle': _vehicleTitle,
        'sourceBudgetId': budgetId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final batch = FirebaseFirestore.instance.batch();
      batch.set(repairRef, repairData);
      batch.set(_budgetsCol.doc(budgetId), {
        'status': 'Aprobado',
        'approvedAt': FieldValue.serverTimestamp(),
        'repairId': repairRef.id,
        'repairPath': repairRef.path,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();

      _status = 'Aprobado';
      if (mounted) setState(() {});
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Presupuesto aprobado y convertido a reparación'),
        ),
      );

      final openRepair = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Conversión completada'),
          content: const Text('¿Querés abrir la reparación creada?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir'),
            ),
          ],
        ),
      );

      if (openRepair == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RepairDetailScreen(
              customerId: _customerId!,
              vehicleId: _vehicleId!,
              vehicleTitle: _vehicleTitle.trim().isEmpty ? 'Vehículo' : _vehicleTitle.trim(),
              repairId: repairRef.id,
              customerName: _customerName,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al aprobar: $e')));
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<Map<String, dynamic>> _loadWorkshopProfile() async {
    final snap = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    final data = snap.data() ?? {};
    final profile = (data['profile'] as Map<String, dynamic>?) ?? {};
    return {
      'name': (profile['name'] ?? '').toString().trim(),
      'owner': (profile['owner'] ?? '').toString().trim(),
      'address': (profile['address'] ?? '').toString().trim(),
      'phone': (profile['phone'] ?? '').toString().trim(),
      'ruc': (profile['ruc'] ?? '').toString().trim(),
    };
  }

  pw.Widget _pdfInfoLine(String label, String value) {
    if (value.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  Future<Uint8List> _buildPdfBytes(Map<String, dynamic> profile) async {
    final doc = pw.Document();
    final workshopName = (profile['name'] ?? '').toString().trim();
    final owner = (profile['owner'] ?? '').toString().trim();
    final address = (profile['address'] ?? '').toString().trim();
    final phone = (profile['phone'] ?? '').toString().trim();
    final ruc = (profile['ruc'] ?? '').toString().trim();

    final customer = _customerName.trim().isEmpty ? 'Cliente' : _customerName.trim();
    final vehicle = _vehicleTitle.trim().isEmpty ? 'Vehículo' : _vehicleTitle.trim();
    final problem = _problem.text.trim();
    final obs = _obs.text.trim();
    final days = _parseDays();

    final parts = _parseGs(_parts.text);
    final labor = _parseGs(_labor.text);
    final total = parts + labor;
    final moneyFmt = NumberFormat.decimalPattern('es_PY');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0F172A'),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  workshopName.isEmpty ? 'Mi Taller' : workshopName,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                if (owner.isNotEmpty)
                  pw.Text(
                    'Propietario: $owner',
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
                if (address.isNotEmpty)
                  pw.Text(
                    'Dirección: $address',
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
                if (phone.isNotEmpty)
                  pw.Text(
                    'Teléfono: $phone',
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
                if (ruc.isNotEmpty)
                  pw.Text(
                    'RUC/CI: $ruc',
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'PRESUPUESTO',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(999),
                  border: pw.Border.all(color: PdfColor.fromHex('#334155')),
                ),
                child: pw.Text('Fecha: ${_dateFmt.format(_date)}'),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(8),
              color: PdfColor.fromHex('#F8FAFC'),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _pdfInfoLine('Cliente', customer),
                _pdfInfoLine('Vehículo', vehicle),
                _pdfInfoLine('Tiempo estimado', '$days día(s)'),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1')),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Descripción del problema',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Text(problem.isEmpty ? '-' : problem),
                if (obs.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'Observaciones',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(obs),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1')),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Costos estimados (Gs.)',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                _pdfInfoLine('Repuestos', moneyFmt.format(parts.round())),
                _pdfInfoLine('Mano de obra', moneyFmt.format(labor.round())),
                pw.Divider(),
                _pdfInfoLine('TOTAL', moneyFmt.format(total.round())),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _sharePdf() async {
    if (_sharing || _saving || _approving) return;
    if (_currentBudgetId == null) {
      final id = await _save(popAfterSave: false, showSnack: false);
      if (id == null) return;
    } else if (!_validate()) {
      return;
    }

    setState(() => _sharing = true);
    try {
      final profile = await _loadWorkshopProfile();
      final bytes = await _buildPdfBytes(profile);
      final safeCustomer = _customerName
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      final file = 'presupuesto_${safeCustomer}_${DateFormat('yyyyMMdd').format(_date)}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo compartir PDF: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _currentBudgetId != null;
    final micEnabled =
        !_saving &&
        !_sharing &&
        !_approving &&
        (kIsWeb ? SpeechWeb.isSupported() : _mobileReady);

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar presupuesto' : 'Nuevo presupuesto'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Compartir PDF',
              onPressed: _sharing ? null : _sharePdf,
              icon: _sharing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _PickerField(
              label: 'Fecha *',
              value: _dateFmt.format(_date),
              hint: 'Seleccionar fecha',
              icon: Icons.calendar_today_outlined,
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            _PickerField(
              label: 'Cliente *',
              value: _customerName,
              hint: 'Buscar y seleccionar cliente',
              icon: Icons.people_alt_outlined,
              onTap: widget.lockCustomer ? null : _pickCustomer,
              disabled: widget.lockCustomer,
            ),
            const SizedBox(height: 12),
            _PickerField(
              label: 'Vehículo *',
              value: _vehicleTitle,
              hint: _loadingVehicles
                  ? 'Cargando vehículos...'
                  : 'Seleccionar vehículo',
              icon: Icons.directions_car_filled_outlined,
              onTap: widget.lockVehicle ? null : _pickVehicle,
              disabled: widget.lockVehicle,
            ),
            const SizedBox(height: 12),
            _DescFieldWithMic(
              controller: _problem,
              listening: _listening,
              micEnabled: micEnabled,
              mode: _mode,
              onMicTap: _toggleMic,
              onClearTap: _clearProblem,
              onModeChanged: _setMode,
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Tiempo estimado (días) *',
              controller: _days,
              keyboardType: TextInputType.number,
              helperText: 'Ej: 2',
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Costos estimados (Gs.)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _MoneyField(
                      label: 'Monto de repuestos estimado',
                      controller: _parts,
                      helperText: 'Ej: 450.000',
                      format: _formatGsFromDigits,
                      onChanged: () => setState(() {}),
                    ),
                    _MoneyField(
                      label: 'Monto de mano de obra estimado',
                      controller: _labor,
                      helperText: 'Ej: 300.000',
                      format: _formatGsFromDigits,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.calculate_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Total estimado: $_totalText Gs.',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obs,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Text('Estado:'),
                    const SizedBox(width: 8),
                    _StatusPill(text: _status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_saving || _approving || _sharing) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar presupuesto'),
              ),
            ),
            const SizedBox(height: 10),
            if (editing) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_sharing || _saving || _approving) ? null : _sharePdf,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Compartir en PDF'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (editing && _status != 'Aprobado')
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: (_approving || _saving || _sharing)
                      ? null
                      : _approveAndConvert,
                  icon: _approving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _approving
                        ? 'Aprobando...'
                        : 'Aprobar y convertir en reparación',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  const _PickerField({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    final text = hasValue ? value.trim() : hint;
    final active = onTap != null && !disabled;
    final textStyle = hasValue
        ? null
        : Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).hintColor,
            );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: active ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Icon(icon, color: active ? null : Theme.of(context).disabledColor),
        ),
        child: Text(text, style: textStyle),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? helperText;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.helperText,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _MoneyField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? helperText;
  final String Function(String rawDigits) format;
  final VoidCallback onChanged;

  const _MoneyField({
    required this.label,
    required this.controller,
    required this.format,
    required this.onChanged,
    this.helperText,
  });

  @override
  State<_MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<_MoneyField> {
  bool _formatting = false;

  void _handleChange(String v) {
    if (_formatting) return;
    final formatted = widget.format(v);
    if (formatted == v) {
      widget.onChanged();
      return;
    }
    _formatting = true;
    widget.controller.value = widget.controller.value.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _formatting = false;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: widget.controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
        ],
        onChanged: _handleChange,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _DescFieldWithMic extends StatelessWidget {
  final TextEditingController controller;
  final bool listening;
  final bool micEnabled;
  final DictationMode mode;
  final VoidCallback onMicTap;
  final VoidCallback onClearTap;
  final void Function(DictationMode mode) onModeChanged;

  const _DescFieldWithMic({
    required this.controller,
    required this.listening,
    required this.micEnabled,
    required this.mode,
    required this.onMicTap,
    required this.onClearTap,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final modeText = mode == DictationMode.add ? 'Agregar' : 'Reemplazar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Descripción de problema *',
            helperText: 'Dictado: $modeText',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Borrar rápido',
                  onPressed: onClearTap,
                  icon: const Icon(Icons.backspace_outlined),
                ),
                IconButton(
                  tooltip: listening ? 'Detener dictado' : 'Dictar por voz',
                  onPressed: micEnabled ? onMicTap : null,
                  icon: Icon(
                    listening ? Icons.mic : Icons.mic_none,
                    color: listening ? Colors.redAccent : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (listening) ...[
          const SizedBox(height: 6),
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 6),
          const Text('Escuchando...'),
        ],
        const SizedBox(height: 10),
        SegmentedButton<DictationMode>(
          segments: const [
            ButtonSegment(
              value: DictationMode.add,
              label: Text('Agregar'),
              icon: Icon(Icons.add),
            ),
            ButtonSegment(
              value: DictationMode.replace,
              label: Text('Reemplazar'),
              icon: Icon(Icons.find_replace),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = text.trim().isEmpty ? 'Pendiente' : text.trim();
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
