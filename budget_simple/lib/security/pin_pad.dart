import 'package:flutter/material.dart';

/// Numeric keypad instead of a TextField: no system keyboard, no clipboard,
/// and it works above the Navigator where there is no Overlay.
class PinPad extends StatefulWidget {
  const PinPad(
      {super.key,
      required this.title,
      required this.onSubmit,
      this.subtitle,
      this.extra});

  final String title;
  final String? subtitle;

  /// Returns an error to show, or null when the PIN was accepted.
  final Future<String?> Function(String pin) onSubmit;
  final Widget? extra;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String pin = '';
  String? error;
  bool busy = false;

  void _type(String digit) {
    if (busy || pin.length >= 8) return;
    setState(() {
      pin += digit;
      error = null;
    });
  }

  Future<void> _submit() async {
    if (busy || pin.length < 6) return;
    setState(() => busy = true);
    final result = await widget.onSubmit(pin);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = result;
      pin = '';
    });
  }

  Widget _key(Widget child, VoidCallback? onTap, {String? label}) => Padding(
        padding: const EdgeInsets.all(6),
        child: Semantics(
          button: true,
          label: label,
          child: SizedBox(
            width: 72,
            height: 72,
            child: FilledButton.tonal(
                style: FilledButton.styleFrom(shape: const CircleBorder()),
                onPressed: busy ? null : onTap,
                child: child),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget digit(String d) =>
        _key(Text(d, style: const TextStyle(fontSize: 26)), () => _type(d));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 40, color: colors.primary),
        const SizedBox(height: 12),
        Text(widget.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        if (widget.subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.subtitle!, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 16),
        Semantics(
          label: '${pin.length} dígitos introducidos',
          child: Text(pin.isEmpty ? ' ' : '●' * pin.length,
              style: const TextStyle(fontSize: 24, letterSpacing: 6)),
        ),
        SizedBox(
          height: 40,
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : error == null
                  ? null
                  : Text(error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error)),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9']
        ])
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map(digit).toList()),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _key(const Icon(Icons.backspace_outlined), () {
            if (pin.isNotEmpty) {
              setState(() => pin = pin.substring(0, pin.length - 1));
            }
          }, label: 'Borrar'),
          digit('0'),
          _key(const Icon(Icons.check), pin.length >= 6 ? _submit : null,
              label: 'Aceptar'),
        ]),
        if (widget.extra != null) widget.extra!,
      ],
    );
  }
}

/// Full-screen route around a PinPad; pops with the accepted PIN.
Future<String?> askPin(BuildContext context,
    {required String title,
    String? subtitle,
    required Future<String?> Function(String pin) check}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (context) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            title: title,
            subtitle: subtitle,
            onSubmit: (pin) async {
              final error = await check(pin);
              if (error == null && context.mounted) {
                Navigator.of(context).pop(pin);
              }
              return error;
            },
          ),
        ),
      ),
    ),
  ));
}
