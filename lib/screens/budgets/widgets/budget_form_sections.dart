import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BudgetPickerField extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  const BudgetPickerField({
    super.key,
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
        : Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: active ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Icon(
            icon,
            color: active ? null : Theme.of(context).disabledColor,
          ),
        ),
        child: Text(text, style: textStyle),
      ),
    );
  }
}

class BudgetFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? helperText;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;

  const BudgetFormField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.helperText,
    this.inputFormatters,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class BudgetMoneyField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? helperText;
  final String Function(String rawDigits) format;
  final VoidCallback onChanged;

  const BudgetMoneyField({
    super.key,
    required this.label,
    required this.controller,
    required this.format,
    required this.onChanged,
    this.helperText,
  });

  @override
  State<BudgetMoneyField> createState() => _BudgetMoneyFieldState();
}

class _BudgetMoneyFieldState extends State<BudgetMoneyField> {
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

class BudgetDescFieldWithMic extends StatelessWidget {
  final TextEditingController controller;
  final bool listening;
  final bool micEnabled;
  final VoidCallback onMicTap;
  final VoidCallback onClearTap;

  const BudgetDescFieldWithMic({
    super.key,
    required this.controller,
    required this.listening,
    required this.micEnabled,
    required this.onMicTap,
    required this.onClearTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Descripción del problema *',
            helperText: 'Podés escribir o dictar por voz',
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
      ],
    );
  }
}

class BudgetStatusPill extends StatelessWidget {
  final String text;

  const BudgetStatusPill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final value = text.trim().isEmpty ? 'Pendiente' : text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(value, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
