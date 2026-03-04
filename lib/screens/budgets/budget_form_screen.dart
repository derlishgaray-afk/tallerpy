import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../utils/speech_web.dart';
import '../../features/budgets/data/repositories/budget_form_repository.dart';
import 'widgets/budget_form_sections.dart';
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

class _PartItemInput {
  final TextEditingController nameCtrl;
  final TextEditingController unitPriceCtrl;

  _PartItemInput({String name = '', String unitPrice = ''})
    : nameCtrl = TextEditingController(text: name),
      unitPriceCtrl = TextEditingController(text: unitPrice);

  void dispose() {
    nameCtrl.dispose();
    unitPriceCtrl.dispose();
  }
}

class _LocalePick {
  final String? localeId;
  final bool hasSpanish;
  const _LocalePick({required this.localeId, required this.hasSpanish});
}

class _BudgetFormScreenState extends State<BudgetFormScreen> {
  final _title = TextEditingController();
  final _problem = TextEditingController();
  final _days = TextEditingController();
  final _parts = TextEditingController();
  final _labor = TextEditingController();
  final _obs = TextEditingController();

  final _repo = BudgetFormRepository();
  bool _usePartsItems = false;
  final List<_PartItemInput> _partsItems = [];

  String? _customerId;
  String _customerName = '';
  String? _vehicleId;
  String _vehicleTitle = '';
  List<VehicleLookup> _vehicleDocs = [];

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
  bool _listening = false;
  TextEditingController? _dictTarget;
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
    _title.text = (d['title'] ?? '').toString();
    _problem.text = (d['problemDescription'] ?? '').toString();
    _days.text = (d['estimatedDays'] ?? '').toString();
    _parts.text = _numToGsText(d['partsEstimated']);
    _labor.text = _numToGsText(d['laborEstimated']);
    _obs.text = (d['observations'] ?? '').toString();
    _loadPartsItemsFromInitial(d['partsItems']);
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
            setState(() {
              _listening = false;
              _dictTarget = null;
              _dictBase = '';
              _lastPartial = '';
            });
          }
        },
        onError: (msg) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _dictTarget = null;
            _dictBase = '';
            _lastPartial = '';
          });
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
    _title.dispose();
    _problem.dispose();
    _days.dispose();
    _parts.dispose();
    _labor.dispose();
    _obs.dispose();
    for (final item in _partsItems) {
      item.dispose();
    }
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
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v != null) {
      final dynamicValue = v as dynamic;
      try {
        final date = dynamicValue.toDate();
        if (date is DateTime) return date;
      } catch (_) {
        // Ignored: not a timestamp-like object.
      }
    }
    return null;
  }

  void _loadPartsItemsFromInitial(dynamic raw) {
    if (raw is! List) return;
    for (final e in raw) {
      if (e is! Map) continue;
      final name = (e['name'] ?? '').toString().trim();
      final unitPriceText = _numToGsText(e['unitPrice']);
      if (name.isEmpty && unitPriceText.isEmpty) continue;
      _partsItems.add(_PartItemInput(name: name, unitPrice: unitPriceText));
    }
    if (_partsItems.isNotEmpty) {
      _usePartsItems = true;
      _syncPartsTotalFromItems();
    }
  }

  String _vehicleTitleFromData(VehicleLookup vehicle) {
    return vehicle.title;
  }

  Future<void> _ensureNames() async {
    if (_customerId != null && _customerName.trim().isEmpty) {
      final customer = await _repo.getCustomerById(_uid, _customerId!);
      if (customer != null && mounted) {
        _customerName = customer.name.isEmpty ? 'Cliente' : customer.name;
      }
    }
    if (_customerId != null &&
        _vehicleId != null &&
        _vehicleTitle.trim().isEmpty) {
      final vehicle = await _repo.getVehicleById(
        _uid,
        _customerId!,
        _vehicleId!,
      );
      if (vehicle != null && mounted) {
        _vehicleTitle = _vehicleTitleFromData(vehicle);
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
      final vehicles = await _repo.listVehiclesForCustomer(_uid, customerId);
      if (!mounted) return;
      String? selectedId = keepSelection ? _vehicleId : null;
      String selectedTitle = keepSelection ? _vehicleTitle : '';
      if (keepSelection && selectedId != null) {
        bool exists = false;
        for (final vehicle in vehicles) {
          if (vehicle.id == selectedId) {
            exists = true;
            selectedTitle = _vehicleTitleFromData(vehicle);
            break;
          }
        }
        if (!exists) {
          selectedId = null;
          selectedTitle = '';
        }
      }
      setState(() {
        _vehicleDocs = vehicles;
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

    final customers = await _repo.listCustomers(_uid);
    if (!mounted) return;
    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay clientes registrados todav\u00eda.'),
        ),
      );
      return;
    }

    final picked = await showDialog<CustomerLookup>(
      context: context,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = customers.where((customer) {
              final hay = [
                customer.name,
                customer.phone,
                customer.ruc,
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
                                final customer = filtered[i];
                                final name = customer.name;
                                final phone = customer.phone;
                                return ListTile(
                                  leading: const Icon(
                                    Icons.people_alt_outlined,
                                  ),
                                  title: Text(name.isEmpty ? 'Cliente' : name),
                                  subtitle: phone.isEmpty ? null : Text(phone),
                                  onTap: () => Navigator.pop(ctx, customer),
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
    final name = picked.name;
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
        const SnackBar(content: Text('Primero seleccion\u00e1 un cliente.')),
      );
      return;
    }

    if (_vehicleDocs.isEmpty) {
      await _loadVehiclesForCustomer(_customerId!, keepSelection: true);
    }
    if (!mounted) return;
    if (_vehicleDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este cliente no tiene veh\u00edculos.')),
      );
      return;
    }

    final picked = await showDialog<VehicleLookup>(
      context: context,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = _vehicleDocs.where((vehicle) {
              final hay = [
                vehicle.brand,
                vehicle.model,
                vehicle.plate,
                vehicle.year,
              ].join(' ').toLowerCase();
              return hay.contains(q.toLowerCase());
            }).toList();
            return AlertDialog(
              title: const Text('Seleccionar veh\u00edculo'),
              content: SizedBox(
                width: 500,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar veh\u00edculo',
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
                                final vehicle = filtered[i];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.directions_car_filled_outlined,
                                  ),
                                  title: Text(_vehicleTitleFromData(vehicle)),
                                  onTap: () => Navigator.pop(ctx, vehicle),
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
      _vehicleTitle = _vehicleTitleFromData(picked);
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

  void _addPartsItem() {
    setState(() => _partsItems.add(_PartItemInput()));
  }

  void _removePartsItem(int index) {
    if (index < 0 || index >= _partsItems.length) return;
    final item = _partsItems[index];
    if (_isDictating(item.nameCtrl)) {
      unawaited(_stopDictation());
    }
    setState(() {
      _partsItems.removeAt(index);
      item.dispose();
      _syncPartsTotalFromItems();
    });
  }

  void _onPartsItemPriceChanged(_PartItemInput item, String raw) {
    final formatted = _formatGsFromDigits(raw);
    if (formatted != raw) {
      item.unitPriceCtrl.value = item.unitPriceCtrl.value.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    _syncPartsTotalFromItems();
  }

  void _syncPartsTotalFromItems() {
    if (!_usePartsItems) return;
    num sum = 0;
    for (final item in _partsItems) {
      sum += _parseGs(item.unitPriceCtrl.text);
    }
    _parts.text = _gsFmt.format(sum.round());
  }

  List<Map<String, dynamic>>? _collectPartsItems({required bool validate}) {
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < _partsItems.length; i++) {
      final item = _partsItems[i];
      final name = item.nameCtrl.text.trim();
      final unit = _parseGs(item.unitPriceCtrl.text);
      final allEmpty = name.isEmpty && unit <= 0;
      if (allEmpty) continue;
      if (validate && (name.isEmpty || unit <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Complet\u00e1 correctamente el repuesto #${i + 1} (nombre y precio).',
            ),
          ),
        );
        return null;
      }
      result.add({'name': name, 'unitPrice': unit});
    }
    return result;
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
          if (s == 'notListening') {
            setState(() {
              _listening = false;
              _dictTarget = null;
              _dictBase = '';
              _lastPartial = '';
            });
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _dictTarget = null;
            _dictBase = '';
            _lastPartial = '';
          });
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
              'No encontr\u00e9 un locale de espa\u00f1ol; usar\u00e9 el idioma del sistema.',
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

  void _setControllerText(TextEditingController ctrl, String v) {
    if (ctrl.text == v) return;
    ctrl.value = ctrl.value.copyWith(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    setState(() {});
  }

  String _appendPhrase(String base, String phrase) {
    final b = base.trim();
    final p = phrase.trim();
    if (p.isEmpty) return b;
    if (b.isEmpty) return p;
    if (b.toLowerCase().endsWith(p.toLowerCase())) return b;
    return '$b $p'.trim();
  }

  bool _isDictating(TextEditingController ctrl) {
    return _listening && identical(_dictTarget, ctrl);
  }

  void _schedulePartialUpdate(String v) {
    _pendingPartialText = v;
    _partialDebounce?.cancel();
    _partialDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted || !_listening || _dictTarget == null) return;
      _setControllerText(_dictTarget!, _pendingPartialText);
    });
  }

  void _onWebPartial(String text) {
    if (!mounted || !_listening || _dictTarget == null) return;
    _lastPartial = text.trim();
    final combined = _dictBase.isEmpty
        ? _lastPartial
        : (_lastPartial.isEmpty ? _dictBase : '$_dictBase $_lastPartial');
    _schedulePartialUpdate(combined.trim());
  }

  void _onWebFinal(String text) {
    if (!mounted || !_listening || _dictTarget == null) return;
    final finalText = text.trim();
    if (finalText.isEmpty || _shouldIgnoreFinal(finalText)) return;
    _dictBase = _appendPhrase(_dictBase, finalText);
    _lastPartial = '';
    _setControllerText(_dictTarget!, _dictBase);
  }

  Future<void> _stopDictation() async {
    if (!_listening) return;
    if (kIsWeb) {
      SpeechWeb.stop();
    } else {
      await _speechMobile.stop();
    }
    _partialDebounce?.cancel();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _dictTarget = null;
      _dictBase = '';
      _lastPartial = '';
    });
  }

  Future<void> _toggleMicFor(TextEditingController target) async {
    if (_saving || _sharing || _approving) return;

    if (_listening && identical(_dictTarget, target)) {
      await _stopDictation();
      return;
    }
    if (_listening) {
      await _stopDictation();
    }

    _dictTarget = target;
    _dictBase = target.text.trim();
    _lastPartial = '';

    if (kIsWeb) {
      if (!SpeechWeb.isSupported()) {
        if (!mounted) return;
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
        if (!mounted || _dictTarget == null) return;
        final text = res.recognizedWords.trim();
        if (text.isEmpty) return;
        if (!res.finalResult) {
          _schedulePartialUpdate(_appendPhrase(_dictBase, text));
          return;
        }
        if (_shouldIgnoreFinal(text)) return;
        _dictBase = _appendPhrase(_dictBase, text);
        _lastPartial = '';
        _setControllerText(_dictTarget!, _dictBase);
      },
    );
    if (mounted) setState(() => _listening = true);
  }

  void _clearProblem() {
    if (_isDictating(_problem)) {
      unawaited(_stopDictation());
    }
    _setControllerText(_problem, '');
  }

  bool _validate() {
    if (_customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccion\u00e1 un cliente')),
      );
      return false;
    }
    if (_vehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccion\u00e1 un veh\u00edculo')),
      );
      return false;
    }
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El t\u00edtulo es obligatorio')),
      );
      return false;
    }
    if (_problem.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La descripci\u00f3n del problema es obligatoria'),
        ),
      );
      return false;
    }
    if (_parseDays() <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tiempo estimado inv\u00e1lido (en d\u00edas)'),
        ),
      );
      return false;
    }
    if (_usePartsItems) {
      final items = _collectPartsItems(validate: true);
      if (items == null) return false;
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
      final partsItems =
          _collectPartsItems(validate: true) ?? <Map<String, dynamic>>[];
      if (_usePartsItems) _syncPartsTotalFromItems();
      final labor = _parseGs(_labor.text);
      final parts = _parseGs(_parts.text);
      final total = labor + parts;
      final data = <String, dynamic>{
        'title': _title.text.trim(),
        'customerId': _customerId,
        'customerName': _customerName.trim().isEmpty
            ? 'Cliente'
            : _customerName.trim(),
        'vehicleId': _vehicleId,
        'vehicleTitle': _vehicleTitle.trim().isEmpty
            ? 'Veh\u00edculo'
            : _vehicleTitle.trim(),
        'date': DateTime(_date.year, _date.month, _date.day),
        'problemDescription': _problem.text.trim(),
        'estimatedDays': _parseDays(),
        'usePartsItems': _usePartsItems,
        'partsItems': partsItems,
        'partsEstimated': parts,
        'laborEstimated': labor,
        'totalEstimated': total,
        'observations': _obs.text.trim(),
        'status': _status.trim().isEmpty ? 'Pendiente' : _status.trim(),
      };

      if (_currentBudgetId == null) {
        _currentBudgetId = await _repo.saveBudget(uid: _uid, data: data);
        _status = 'Pendiente';
      } else {
        await _repo.saveBudget(
          uid: _uid,
          data: data,
          budgetId: _currentBudgetId,
        );
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
    final fromTitle = _title.text.trim();
    if (fromTitle.isNotEmpty) return fromTitle;
    final p = _problem.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (p.isNotEmpty) return p.length <= 70 ? p : '${p.substring(0, 67)}...';
    if (_vehicleTitle.trim().isNotEmpty) {
      return 'Reparación - ${_vehicleTitle.trim()}';
    }
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
          'Se crear\u00e1 una reparaci\u00f3n con estos datos y el presupuesto quedar\u00e1 aprobado.',
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
      final partsItems =
          _collectPartsItems(validate: true) ?? <Map<String, dynamic>>[];
      if (_usePartsItems) _syncPartsTotalFromItems();
      final labor = _parseGs(_labor.text);
      final parts = _parseGs(_parts.text);
      final desc = _problem.text.trim();
      final obs = _obs.text.trim();
      final fullDesc = obs.isEmpty
          ? desc
          : '$desc\n\nObservaciones del presupuesto:\n$obs';
      final repairId = await _repo.approveAndConvert(
        uid: _uid,
        budgetId: budgetId,
        customerId: _customerId!,
        vehicleId: _vehicleId!,
        customerName: _customerName,
        vehicleTitle: _vehicleTitle,
        repairTitle: _buildRepairTitle(),
        repairDescription: fullDesc,
        usePartsItems: _usePartsItems,
        partsItems: partsItems,
        labor: labor,
        parts: parts,
      );

      _status = 'Aprobado';
      if (mounted) setState(() {});
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Presupuesto aprobado y convertido a reparaci\u00f3n'),
        ),
      );

      final openRepair = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Conversi\u00f3n completada'),
          content: const Text(
            '\u00bfQuer\u00e9s abrir la reparaci\u00f3n creada?',
          ),
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
              vehicleTitle: _vehicleTitle.trim().isEmpty
                  ? 'Veh\u00edculo'
                  : _vehicleTitle.trim(),
              repairId: repairId,
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
    return _repo.loadWorkshopProfile(_uid);
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

    final customer = _customerName.trim().isEmpty
        ? 'Cliente'
        : _customerName.trim();
    final vehicle = _vehicleTitle.trim().isEmpty
        ? 'Veh\u00edculo'
        : _vehicleTitle.trim();
    final title = _title.text.trim();
    final problem = _problem.text.trim();
    final obs = _obs.text.trim();
    final days = _parseDays();
    final partsItems =
        _collectPartsItems(validate: false) ?? <Map<String, dynamic>>[];

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
                    'Direcci\u00f3n: $address',
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
                if (phone.isNotEmpty)
                  pw.Text(
                    'Tel\u00e9fono: $phone',
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
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                _pdfInfoLine('T\u00edtulo', title),
                _pdfInfoLine('Cliente', customer),
                _pdfInfoLine('Veh\u00edculo', vehicle),
                _pdfInfoLine('Tiempo estimado', '$days d\u00eda(s)'),
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
                  'Descripci\u00f3n del problema',
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
                if (partsItems.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Detalle de repuestos',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  ...partsItems.map(
                    (e) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Text(
                        '- ${(e['name'] ?? '').toString()} | ${moneyFmt.format(((e['unitPrice'] as num?) ?? 0).round())} Gs.',
                      ),
                    ),
                  ),
                ],
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
      final safeCustomer = _customerName.trim().replaceAll(
        RegExp(r'[^a-zA-Z0-9]+'),
        '_',
      );
      final file =
          'presupuesto_${safeCustomer}_${DateFormat('yyyyMMdd').format(_date)}.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
          fileNameOverrides: [file],
          title: file,
          subject: file,
          downloadFallbackEnabled: true,
          mailToFallbackEnabled: true,
        ),
      );
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
            BudgetFormField(
              label: 'T\u00edtulo *',
              controller: _title,
              helperText: 'Se copiar\u00e1 a Reparaciones al convertir',
            ),
            const SizedBox(height: 12),
            BudgetPickerField(
              label: 'Fecha *',
              value: _dateFmt.format(_date),
              hint: 'Seleccionar fecha',
              icon: Icons.calendar_today_outlined,
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            BudgetPickerField(
              label: 'Cliente *',
              value: _customerName,
              hint: 'Buscar y seleccionar cliente',
              icon: Icons.people_alt_outlined,
              onTap: widget.lockCustomer ? null : _pickCustomer,
              disabled: widget.lockCustomer,
            ),
            const SizedBox(height: 12),
            BudgetPickerField(
              label: 'Veh\u00edculo *',
              value: _vehicleTitle,
              hint: _loadingVehicles
                  ? 'Cargando veh\u00edculos...'
                  : 'Seleccionar veh\u00edculo',
              icon: Icons.directions_car_filled_outlined,
              onTap: widget.lockVehicle ? null : _pickVehicle,
              disabled: widget.lockVehicle,
            ),
            const SizedBox(height: 12),
            BudgetDescFieldWithMic(
              controller: _problem,
              listening: _isDictating(_problem),
              micEnabled: micEnabled,
              onMicTap: () => _toggleMicFor(_problem),
              onClearTap: _clearProblem,
            ),
            const SizedBox(height: 12),
            BudgetFormField(
              label: 'Tiempo estimado (d\u00edas) *',
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cargar repuestos item por item'),
                      subtitle: const Text(
                        'Opcional: nombre + precio unitario (manual o voz)',
                      ),
                      value: _usePartsItems,
                      onChanged: (_saving || _approving || _sharing)
                          ? null
                          : (v) {
                              setState(() {
                                _usePartsItems = v;
                                if (_usePartsItems && _partsItems.isEmpty) {
                                  _partsItems.add(_PartItemInput());
                                }
                              });
                              if (_usePartsItems) {
                                _syncPartsTotalFromItems();
                              }
                            },
                    ),
                    if (_usePartsItems) ...[
                      const SizedBox(height: 6),
                      if (_partsItems.isEmpty)
                        OutlinedButton.icon(
                          onPressed: _addPartsItem,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar repuesto'),
                        ),
                      ...List.generate(_partsItems.length, (i) {
                        final item = _partsItems[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: TextField(
                                  controller: item.nameCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Repuesto #${i + 1}',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: _isDictating(item.nameCtrl)
                                          ? 'Detener dictado'
                                          : 'Dictar por voz',
                                      onPressed: micEnabled
                                          ? () => _toggleMicFor(item.nameCtrl)
                                          : null,
                                      icon: Icon(
                                        _isDictating(item.nameCtrl)
                                            ? Icons.mic
                                            : Icons.mic_none,
                                        color: _isDictating(item.nameCtrl)
                                            ? Colors.redAccent
                                            : null,
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 4,
                                child: TextField(
                                  controller: item.unitPriceCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9., ]'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      _onPartsItemPriceChanged(item, v),
                                  decoration: const InputDecoration(
                                    labelText: 'Unitario (Gs.)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                children: [
                                  IconButton(
                                    tooltip: 'Agregar repuesto',
                                    onPressed: _addPartsItem,
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  IconButton(
                                    tooltip: 'Eliminar repuesto',
                                    onPressed: _partsItems.length <= 1
                                        ? null
                                        : () => _removePartsItem(i),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      BudgetFormField(
                        label: 'Total repuestos estimado (auto)',
                        controller: _parts,
                        keyboardType: TextInputType.number,
                        readOnly: true,
                      ),
                    ] else
                      BudgetMoneyField(
                        label: 'Monto de repuestos estimado',
                        controller: _parts,
                        helperText: 'Ej: 450.000',
                        format: _formatGsFromDigits,
                        onChanged: () => setState(() {}),
                      ),
                    BudgetMoneyField(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Text('Estado:'),
                    const SizedBox(width: 8),
                    BudgetStatusPill(text: _status),
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
                  onPressed: (_sharing || _saving || _approving)
                      ? null
                      : _sharePdf,
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
                        : 'Aprobar y convertir en reparaci\u00f3n',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
