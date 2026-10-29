import 'package:flutter/material.dart';

/// Contenedor blanco con borde gris y esquinas redondeadas.
/// Es la "tarjeta" base de casi todos los paneles de la app.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color color;
  final Color? borderColor;
  final List<BoxShadow>? shadow;
  final double? width;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 24,
    this.color = Colors.white,
    this.borderColor,
    this.shadow,
    this.width,
  });

  /// Sombra suave usada en los paneles destacados (Mis Compras, Mi Ubicación).
  static List<BoxShadow> softShadow({double dy = 4}) => [
    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, dy)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? Colors.grey.shade200),
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}
