import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// Web speech (JS)
import '/utils/speech_web.dart';

// Mobile speech (opcional)
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'widgets/repair_form_sections.dart';

class RepairFormScreen extends StatefulWidget {
  final String customerId;
  final String? customerName;
  final String vehicleId;
  final String vehicleTitle;

  final String? repairId;
  final Map<String, dynamic>? initial;

  const RepairFormScreen({
    super.key,
    required this.customerId,
    this.customerName,
    required this.vehicleId,
    required this.vehicleTitle,
    this.repairId,
    this.initial,
  });

  @override
  State<RepairFormScreen> createState() => _RepairFormScreenState();
}

enum DictationMode { add, replace }

class _LocalePick {
  final String? localeId;
  final bool hasSpanish;

  const _LocalePick({required this.localeId, required this.hasSpanish});
}

class _RepairFormScreenState extends State<RepairFormScreen> {
  final _title = TextEditingController();
  final _km = TextEditingController();
  final _desc = TextEditingController();

  final _labor = TextEditingController();
  final _parts = TextEditingController();

  String _status = 'Abierta';
  bool _saving = false;
  bool _sharing = false;
  // ===== Anti-duplicado (final repetido) =====
  String _lastFinalNorm = '';
  int _lastFinalMs = 0;

  bool _shouldIgnoreFinal(String text) {
    final norm = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    final now = DateTime.now().millisecondsSinceEpoch;

    // si llega el mismo final en menos de 1200ms, lo ignoramos
    final same = norm.isNotEmpty && norm == _lastFinalNorm;
    final tooSoon = (now - _lastFinalMs) < 1200;

    if (same && tooSoon) return true;

    _lastFinalNorm = norm;
    _lastFinalMs = now;
    return false;
  }

  // ===== Money formatter (Paraguay) =====
  final NumberFormat _gsFmt = NumberFormat.decimalPattern('es_PY');
  final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  // ===== Dictado =====
  DictationMode _mode = DictationMode.add;
  bool _listening = false;

  // Para modo replace (guardamos base + parcial actual)
  String _dictBase = '';
  String _lastPartial = '';

  // Mobile speech (opcional)
  final stt.SpeechToText _speechMobile = stt.SpeechToText();
  bool _mobileReady = false;
  String? _mobileLocaleId;
  bool _mobileHasSpanish = true;
  bool _mobileLocaleSnackShown = false;
  Timer? _partialDebounce;
  String _pendingPartialText = '';

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _repairsCol => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('customers')
      .doc(widget.customerId)
      .collection('vehicles')
      .doc(widget.vehicleId)
      .collection('repairs');

  @override
  void initState() {
    super.initState();

    final d = widget.initial ?? {};
    _title.text = (d['title'] ?? '').toString();
    _km.text = (d['km'] ?? '').toString();
    _desc.text = (d['description'] ?? '').toString();

    final rawStatus = (d['status'] ?? 'Abierta').toString().trim();
    _status = rawStatus.isEmpty ? 'Abierta' : rawStatus;

    _labor.text = _numToGsText(d['labor']);
    _parts.text = _numToGsText(d['parts']);

    // Configurar callbacks web (si aplica)
    if (kIsWeb && SpeechWeb.isSupported()) {
      SpeechWeb.setCallbacks(
        onPartial: _onWebPartial,
        onFinal: _onWebFinal,
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'stopped' || s == 'error') {
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
      // Mobile init (opcional)
      _initMobileSpeech();
    }
  }

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
      if (ok) {
        await _logAvailableLocales();
      }
    } catch (_) {
      if (mounted) setState(() => _mobileReady = false);
    }
  }

  Future<void> _logAvailableLocales() async {
    try {
      final locales = await _speechMobile.locales();
      final system = await _speechMobile.systemLocale();
      final systemId = system?.localeId ?? '';
      final pick = _pickMobileLocaleId(locales, systemId);
      _mobileLocaleId = pick.localeId;
      _mobileHasSpanish = pick.hasSpanish;
      if (!mounted) return;
      debugPrint(
        'Speech locales: ${locales.map((l) => l.localeId).join(', ')}',
      );
      debugPrint('Speech system locale: ${system?.localeId ?? 'null'}');
      debugPrint('Speech selected locale: ${_mobileLocaleId ?? 'null'}');
      if (!_mobileHasSpanish && !_mobileLocaleSnackShown) {
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

  @override
  void dispose() {
    _partialDebounce?.cancel();
    if (!kIsWeb) {
      _speechMobile.stop();
    } else {
      SpeechWeb.stop();
    }

    _title.dispose();
    _km.dispose();
    _desc.dispose();
    _labor.dispose();
    _parts.dispose();
    super.dispose();
  }

  // ===== Money helpers =====
  String _numToGsText(dynamic v) {
    if (v == null) return '';
    final n = (v is num) ? v : num.tryParse(v.toString());
    if (n == null) return '';
    return _gsFmt.format(n.round());
  }

  num _parseGs(String s) {
    final t = s.trim();
    if (t.isEmpty) return 0;
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
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

  num get _total => _parseGs(_labor.text) + _parseGs(_parts.text);
  String get _totalText => _gsFmt.format(_total.round());

  // ===== Dictado (Web callbacks) =====
  void _onWebPartial(String text) {
    if (!mounted) return;
    if (!_listening) return;

    if (_mode == DictationMode.replace) {
      _lastPartial = text.trim();
      final combined = _dictBase.isEmpty
          ? _lastPartial
          : (_lastPartial.isEmpty ? _dictBase : '$_dictBase $_lastPartial');

      _schedulePartialUpdate(combined.trim());
    }
    // En modo add, ignoramos partial para no duplicar.
  }

  void _onWebFinal(String text) {
    if (!mounted) return;
    if (!_listening) return;

    final finalText = text.trim();
    if (finalText.isEmpty) return;

    // evita duplicados de Web Speech
    if (_shouldIgnoreFinal(finalText)) return;

    if (_mode == DictationMode.add) {
      final current = _desc.text.trim();

      // si ya termina con lo mismo, no agregues
      if (current.isNotEmpty &&
          current.toLowerCase().endsWith(finalText.toLowerCase())) {
        return;
      }

      final next = current.isEmpty ? finalText : '$current $finalText';
      _setDescText(next.trim());
    } else {
      final base = _dictBase.trim();
      final next = base.isEmpty ? finalText : '$base $finalText';
      _dictBase = next.trim();
      _lastPartial = '';
      _setDescText(_dictBase);
    }
  }

  void _setDescText(String v) {
    if (_desc.text == v) return;
    _desc.value = _desc.value.copyWith(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    setState(() {}); // para refrescar UI si queres
  }

  void _schedulePartialUpdate(String v) {
    _pendingPartialText = v;
    _partialDebounce?.cancel();
    _partialDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      if (!_listening) return;
      _setDescText(_pendingPartialText);
    });
  }

  void _resetDictationBase() {
    _dictBase = _desc.text.trim();
    _lastPartial = '';
  }

  // ===== Toggle mic =====
  Future<void> _toggleMic() async {
    if (_saving) return;

    if (_listening) {
      // stop
      if (kIsWeb) {
        SpeechWeb.stop();
      } else {
        await _speechMobile.stop();
      }
      _partialDebounce?.cancel();
      if (mounted) setState(() => _listening = false);
      return;
    }

    // start
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

      // IMPORTANTE: llamar start SOLO dentro del onPressed (gesto usuario)
      SpeechWeb.start(localeId: 'es-ES');
      if (mounted) setState(() => _listening = true);
      return;
    }

    // Mobile
    if (!_mobileReady) {
      await _initMobileSpeech();
      if (!_mobileReady) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pude iniciar el microfono. Revisa permisos.'),
          ),
        );
        return;
      }
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
          // en add: solo "final", pero con dedupe
          if (res.finalResult) {
            if (_shouldIgnoreFinal(text)) return;

            final current = _desc.text.trim();

            // si ya termina con lo mismo, no agregues
            if (current.isNotEmpty &&
                current.toLowerCase().endsWith(text.toLowerCase())) {
              return;
            }

            final next = current.isEmpty ? text : '$current $text';
            _setDescText(next.trim());
          }
        } else {
          // replace
          if (!res.finalResult) {
            _schedulePartialUpdate(
              (_dictBase.isEmpty ? text : '$_dictBase $text').trim(),
            );
          } else {
            if (_shouldIgnoreFinal(text)) return;

            _dictBase = (_dictBase.isEmpty ? text : '$_dictBase $text').trim();
            _setDescText(_dictBase);
          }
        }
      },
    );

    if (mounted) setState(() => _listening = true);
  }

  void _quickClearDesc() {
    if (_listening) {
      // opcional: parar al borrar
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
    _setDescText('');
  }

  void _setMode(DictationMode mode) {
    setState(() => _mode = mode);
    // recalcular base al cambiar modo para que no mezcle
    _resetDictationBase();
  }

  bool get _canSharePdf =>
      !_saving && !_sharing && _status.trim().toLowerCase() == 'terminada';

  DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDateTime(dynamic v) {
    final d = _parseDate(v);
    if (d == null) return '';
    return _dateTimeFmt.format(d);
  }

  String _kmForPdf(String rawKm) {
    final raw = rawKm.trim();
    if (raw.isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return raw;
    final n = int.tryParse(digits);
    if (n == null) return raw;
    return '${_gsFmt.format(n)} km';
  }

  String _safeFileToken(String input, {required String fallback}) {
    final token = input.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final clean = token.replaceAll(RegExp(r'^_+|_+$'), '');
    return clean.isEmpty ? fallback : clean;
  }

  Future<Map<String, dynamic>> _loadWorkshopProfile() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();
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

  Future<String> _resolveCustomerName() async {
    final fromWidget = (widget.customerName ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('customers')
        .doc(widget.customerId)
        .get();
    final data = snap.data() ?? {};
    final fromDb = (data['name'] ?? '').toString().trim();
    return fromDb.isEmpty ? 'Cliente' : fromDb;
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

  Future<Uint8List> _buildPdfBytes({
    required Map<String, dynamic> profile,
    required String customerName,
  }) async {
    final doc = pw.Document();
    final workshopName = (profile['name'] ?? '').toString().trim();
    final owner = (profile['owner'] ?? '').toString().trim();
    final address = (profile['address'] ?? '').toString().trim();
    final phone = (profile['phone'] ?? '').toString().trim();
    final ruc = (profile['ruc'] ?? '').toString().trim();

    final title = _title.text.trim();
    final desc = _desc.text.trim();
    final status = _status.trim().isEmpty ? 'Abierta' : _status.trim();
    final km = _kmForPdf(_km.text);
    final labor = _parseGs(_labor.text);
    final parts = _parseGs(_parts.text);
    final total = labor + parts;
    final moneyFmt = NumberFormat.decimalPattern('es_PY');
    final issuedAt = _dateTimeFmt.format(DateTime.now());
    final createdAt = _fmtDateTime(widget.initial?['createdAt']);
    final updatedAt = _fmtDateTime(widget.initial?['updatedAt']);
    final vehicle = widget.vehicleTitle.trim().isEmpty
        ? 'Vehiculo'
        : widget.vehicleTitle.trim();
    final customer = customerName.trim().isEmpty
        ? 'Cliente'
        : customerName.trim();

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
                    'Direccion: $address',
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
                if (phone.isNotEmpty)
                  pw.Text(
                    'Telefono: $phone',
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
                'REPARACION',
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
                child: pw.Text('Estado: $status'),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(8),
              color: PdfColor.fromHex('#F8FAFC'),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _pdfInfoLine('Emitido', issuedAt),
                _pdfInfoLine('Cliente', customer),
                _pdfInfoLine('Vehiculo', vehicle),
                _pdfInfoLine('Km', km),
                _pdfInfoLine('Creada', createdAt),
                _pdfInfoLine('Actualizada', updatedAt),
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
                  title.isEmpty ? 'Sin titulo' : title,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(desc.isEmpty ? '-' : desc),
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
                  'Costos (Gs.)',
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
    if (!_canSharePdf) return;

    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El titulo es obligatorio')));
      return;
    }

    final kmTxt = _km.text.trim();
    final kmDigits = kmTxt.replaceAll(RegExp(r'[^0-9]'), '');
    if (kmTxt.isNotEmpty && kmDigits.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Km invalido')));
      return;
    }

    setState(() => _sharing = true);

    try {
      final profile = await _loadWorkshopProfile();
      final customerName = await _resolveCustomerName();
      final bytes = await _buildPdfBytes(
        profile: profile,
        customerName: customerName,
      );
      final safeVehicle = _safeFileToken(
        widget.vehicleTitle,
        fallback: 'vehiculo',
      );
      final safeTitle = _safeFileToken(title, fallback: 'reparacion');
      final fileDate = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = 'reparacion_${safeVehicle}_${safeTitle}_$fileDate.pdf';
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

  // ===== Save =====
  Future<void> _save() async {
    final title = _title.text.trim();
    final kmTxt = _km.text.trim();
    final desc = _desc.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El titulo es obligatorio')));
      return;
    }

    // km opcional; validar dígitos
    final kmDigits = kmTxt.replaceAll(RegExp(r'[^0-9]'), '');
    if (kmTxt.isNotEmpty && kmDigits.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Km inválido')));
      return;
    }

    setState(() => _saving = true);

    final labor = _parseGs(_labor.text);
    final parts = _parseGs(_parts.text);
    final total = labor + parts;

    final data = <String, dynamic>{
      'title': title,
      'km': kmTxt,
      'description': desc,
      'status': _status,
      'labor': labor,
      'parts': parts,
      'total': total,
      'customerId': widget.customerId,
      'customerName': (widget.customerName ?? '').trim(),
      'vehicleId': widget.vehicleId,
      'vehicleTitle': widget.vehicleTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (widget.repairId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await _repairsCol.add(data);
      } else {
        await _repairsCol
            .doc(widget.repairId)
            .set(data, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reparación guardada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildStatusField() {
    return DropdownButtonFormField<String>(
      initialValue: _status,
      decoration: const InputDecoration(
        labelText: 'Estado',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'Abierta', child: Text('Abierta')),
        DropdownMenuItem(value: 'En proceso', child: Text('En proceso')),
        DropdownMenuItem(value: 'Terminada', child: Text('Terminada')),
        DropdownMenuItem(value: 'Entregada', child: Text('Entregada')),
        DropdownMenuItem(value: 'Cancelada', child: Text('Cancelada')),
      ],
      onChanged: (value) => setState(() => _status = value ?? 'Abierta'),
    );
  }

  Widget _buildCostsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Costos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            RepairMoneyField(
              label: 'Mano de obra',
              controller: _labor,
              helperText: 'Ej: 150.000',
              format: _formatGsFromDigits,
              onChanged: () => setState(() {}),
            ),
            RepairMoneyField(
              label: 'Repuestos',
              controller: _parts,
              helperText: 'Ej: 320.000',
              format: _formatGsFromDigits,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calculate_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Total: $_totalText',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.repairId != null;

    final micEnabled =
        !_saving &&
        !_sharing &&
        (kIsWeb ? SpeechWeb.isSupported() : _mobileReady);

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar reparación' : 'Nueva reparación'),
        actions: [
          IconButton(
            tooltip: _canSharePdf
                ? 'Compartir PDF'
                : 'Disponible al estado Terminada',
            onPressed: _canSharePdf ? _sharePdf : null,
            icon: _sharing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            RepairTextField(label: 'Título *', controller: _title),
            const SizedBox(height: 12),

            _buildStatusField(),

            const SizedBox(height: 12),
            RepairTextField(
              label: 'Km',
              controller: _km,
              keyboardType: TextInputType.number,
              helperText: 'Opcional. Solo números.',
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),

            const SizedBox(height: 12),
            RepairDescFieldWithMic(
              controller: _desc,
              listening: _listening,
              micEnabled: micEnabled,
              isAddMode: _mode == DictationMode.add,
              onMicTap: _toggleMic,
              onClearTap: _quickClearDesc,
              onModeChanged: (isAdd) {
                _setMode(isAdd ? DictationMode.add : DictationMode.replace);
              },
            ),

            const SizedBox(height: 12),
            _buildCostsSection(),

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
