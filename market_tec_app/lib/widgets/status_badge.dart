import 'package:flutter/material.dart';

/// Etiqueta tipo "píldora" para estados y contadores
/// (Pendiente, Activa, Pausado (Agotado), "3 turnos", "12 productos", ...).
class StatusBadge extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color backgroundColor;
  final Color? borderColor;

  /// Si no es null se dibuja un punto de este color antes del texto.
  final Color? dotColor;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double fontSize;
  final double? letterSpacing;

  const StatusBadge({
    super.key,
    required this.text,
    required this.textColor,
    required this.backgroundColor,
    this.borderColor,
    this.dotColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    this.radius = 12,
    this.fontSize = 12,
    this.letterSpacing,
  });

  /// Badge con punto y borde (estado de producto / historial de pedidos).
  const StatusBadge.dot({
    super.key,
    required this.text,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required Color this.dotColor,
  }) : padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
       radius = 12,
       fontSize = 12,
       letterSpacing = null;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        letterSpacing: letterSpacing,
      ),
    );
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: dotColor == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                label,
              ],
            ),
    );
  }
}
