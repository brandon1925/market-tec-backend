import 'package:flutter/material.dart';

/// Mensaje centrado con ícono para listas vacías
/// ("Sin compras registradas", "Inventario vacío", "¡Todo al día!", ...).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final double iconGap;
  final String? title;
  final double titleSize;
  final String? subtitle;
  final TextStyle? subtitleStyle;
  final double subtitleGap;
  final TextAlign? subtitleAlign;
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    this.iconSize = 48,
    this.iconColor,
    this.iconGap = 12,
    this.title,
    this.titleSize = 16,
    this.subtitle,
    this.subtitleStyle,
    this.subtitleGap = 4,
    this.subtitleAlign,
    this.padding = const EdgeInsets.symmetric(vertical: 40),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: iconSize,
              color: iconColor ?? Colors.grey.shade300,
            ),
            SizedBox(height: iconGap),
            if (title != null)
              Text(
                title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: titleSize,
                ),
              ),
            if (subtitle != null) ...[
              if (title != null && subtitleGap > 0)
                SizedBox(height: subtitleGap),
              Text(
                subtitle!,
                textAlign: subtitleAlign ?? TextAlign.center,
                style:
                    subtitleStyle ??
                    TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
