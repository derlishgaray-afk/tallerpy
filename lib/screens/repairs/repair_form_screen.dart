import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// Web speech (JS)
import '/utils/speech_web.dart';

// Mobile speech (opcional)
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

  @override
  Widget build(BuildContext context) {
    final editing = widget.repairId != null;

    final micEnabled =
        !_saving && (kIsWeb ? SpeechWeb.isSupported() : _mobileReady);

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar reparación' : 'Nueva reparación'),
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
            _Field(label: 'Título *', controller: _title),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Estado',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Abierta', child: Text('Abierta')),
                DropdownMenuItem(
                  value: 'En proceso',
                  child: Text('En proceso'),
                ),
                DropdownMenuItem(value: 'Terminada', child: Text('Terminada')),
                DropdownMenuItem(value: 'Entregada', child: Text('Entregada')),
                DropdownMenuItem(value: 'Cancelada', child: Text('Cancelada')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'Abierta'),
            ),

            const SizedBox(height: 12),
            _Field(
              label: 'Km',
              controller: _km,
              keyboardType: TextInputType.number,
              helperText: 'Opcional. Solo números.',
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),

            const SizedBox(height: 12),
            _DescFieldWithMic(
              controller: _desc,
              listening: _listening,
              micEnabled: micEnabled,
              mode: _mode,
              onMicTap: _toggleMic,
              onClearTap: _quickClearDesc,
              onModeChanged: _setMode,
            ),

            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Costos',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),

                    _MoneyField(
                      label: 'Mano de obra',
                      controller: _labor,
                      helperText: 'Ej: 150.000',
                      format: _formatGsFromDigits,
                      onChanged: () => setState(() {}),
                    ),

                    _MoneyField(
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
            ),

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

// ===== Widgets auxiliares =====

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
      maxLines: 1,
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

class _DescFieldWithMic extends StatefulWidget {
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
  State<_DescFieldWithMic> createState() => _DescFieldWithMicState();
}

class _DescFieldWithMicState extends State<_DescFieldWithMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.2).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _DescFieldWithMic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.listening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modeText =
        widget.mode == DictationMode.add ? 'Agregar' : 'Reemplazar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Descripción',
            border: const OutlineInputBorder(),
            helperText: 'Dictado: $modeText',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Borrar rápido',
                  onPressed: widget.onClearTap,
                  icon: const Icon(Icons.backspace_outlined),
                ),
                IconButton(
                  tooltip:
                      widget.listening ? 'Detener dictado' : 'Dictar por voz',
                  onPressed: widget.micEnabled ? widget.onMicTap : null,
                  icon: Icon(
                    widget.listening ? Icons.mic : Icons.mic_none,
                    color: widget.listening ? Colors.redAccent : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.listening) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Escuchando...'),
            ],
          ),
          const SizedBox(height: 6),
          const LinearProgressIndicator(minHeight: 2),
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
          selected: {widget.mode},
          onSelectionChanged: (s) => widget.onModeChanged(s.first),
        ),
      ],
    );
  }
}

