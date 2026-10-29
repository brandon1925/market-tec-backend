import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Texto pequeño en mayúsculas que va arriba de los títulos
/// ("PANEL DE VENTAS", "SEGUIMIENTO", "QUEJAS", ...).
class EyebrowText extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;
  final double letterSpacing;
  final IconData? icon;

  const EyebrowText(
    this.text, {
    super.key,
    this.color = AppColors.primary,
    this.fontSize = 12,
    this.letterSpacing = 1.5,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        letterSpacing: letterSpacing,
      ),
    );
    if (icon == null) return label;
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        label,
      ],
    );
  }
}

/// Bloque "eyebrow + título + subtítulo" usado como encabezado de página
/// y de secciones. Todos los tamaños son configurables para respetar
/// exactamente el diseño de cada pantalla.
class SectionHeader extends StatelessWidget {
  final String? eyebrow;
  final IconData? eyebrowIcon;
  final Color eyebrowColor;
  final double eyebrowSize;
  final double eyebrowSpacing;
  final double eyebrowGap;

  final String title;
  final double titleSize;
  final Color? titleColor;
  final double? titleLetterSpacing;

  final String? subtitle;
  final TextStyle? subtitleStyle;
  final double subtitleGap;

  const SectionHeader({
    super.key,
    this.eyebrow,
    this.eyebrowIcon,
    this.eyebrowColor = AppColors.primary,
    this.eyebrowSize = 12,
    this.eyebrowSpacing = 1.5,
    this.eyebrowGap = 4,
    required this.title,
    this.titleSize = 36,
    this.titleColor = Colors.black87,
    this.titleLetterSpacing = -1,
    this.subtitle,
    this.subtitleStyle,
    this.subtitleGap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          EyebrowText(
            eyebrow!,
            color: eyebrowColor,
            fontSize: eyebrowSize,
            letterSpacing: eyebrowSpacing,
            icon: eyebrowIcon,
          ),
          if (eyebrowGap > 0) SizedBox(height: eyebrowGap),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            color: titleColor,
            letterSpacing: titleLetterSpacing,
          ),
        ),
        if (subtitle != null) ...[
          if (subtitleGap > 0) SizedBox(height: subtitleGap),
          Text(
            subtitle!,
            style:
                subtitleStyle ??
                TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }
}

/// Título de tarjeta con un badge al lado ("Inventario [2 artículos]").
class CardTitle extends StatelessWidget {
  final String title;
  final double fontSize;
  final Widget? leading;
  final Widget? badge;

  const CardTitle({
    super.key,
    required this.title,
    this.fontSize = 20,
    this.leading,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        if (leading != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [leading!, const SizedBox(width: 12), text],
          )
        else
          text,
        if (badge != null) badge!,
      ],
    );
  }
}
