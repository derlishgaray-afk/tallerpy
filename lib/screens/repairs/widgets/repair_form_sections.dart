import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RepairTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? helperText;
  final List<TextInputFormatter>? inputFormatters;

  const RepairTextField({
    super.key,
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

class RepairMoneyField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? helperText;
  final String Function(String rawDigits) format;
  final VoidCallback onChanged;

  const RepairMoneyField({
    super.key,
    required this.label,
    required this.controller,
    required this.format,
    required this.onChanged,
    this.helperText,
  });

  @override
  State<RepairMoneyField> createState() => _RepairMoneyFieldState();
}

class _RepairMoneyFieldState extends State<RepairMoneyField> {
  bool _formatting = false;

  void _handleChange(String value) {
    if (_formatting) return;

    final formatted = widget.format(value);
    if (formatted == value) {
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

class RepairDescFieldWithMic extends StatefulWidget {
  final TextEditingController controller;
  final bool listening;
  final bool micEnabled;
  final bool isAddMode;

  final VoidCallback onMicTap;
  final VoidCallback onClearTap;
  final ValueChanged<bool> onModeChanged;

  const RepairDescFieldWithMic({
    super.key,
    required this.controller,
    required this.listening,
    required this.micEnabled,
    required this.isAddMode,
    required this.onMicTap,
    required this.onClearTap,
    required this.onModeChanged,
  });

  @override
  State<RepairDescFieldWithMic> createState() => _RepairDescFieldWithMicState();
}

class _RepairDescFieldWithMicState extends State<RepairDescFieldWithMic>
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
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _opacity = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant RepairDescFieldWithMic oldWidget) {
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
    final modeText = widget.isAddMode ? 'Agregar' : 'Reemplazar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Descripcion',
            border: const OutlineInputBorder(),
            helperText: 'Dictado: $modeText',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Borrar rapido',
                  onPressed: widget.onClearTap,
                  icon: const Icon(Icons.backspace_outlined),
                ),
                IconButton(
                  tooltip: widget.listening
                      ? 'Detener dictado'
                      : 'Dictar por voz',
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
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              label: Text('Agregar'),
              icon: Icon(Icons.add),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text('Reemplazar'),
              icon: Icon(Icons.find_replace),
            ),
          ],
          selected: {widget.isAddMode},
          onSelectionChanged: (value) => widget.onModeChanged(value.first),
        ),
      ],
    );
  }
}
