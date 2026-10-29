import 'package:flutter/material.dart';

/// Ícono de ayuda (?) que explica algo en una línea. En celular se toca y en
/// computadora basta con pasar el mouse.
class InfoHint extends StatelessWidget {
  final String mensaje;
  final double size;
  final Color? color;
  final IconData icon;

  const InfoHint(
    this.mensaje, {
    super.key,
    this.size = 16,
    this.color,
    this.icon = Icons.help_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    if (mensaje.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: mensaje,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 5),
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: size, color: color ?? Colors.grey.shade500),
      ),
    );
  }
}
