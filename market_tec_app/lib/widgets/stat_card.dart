import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'app_card.dart';

/// Tarjeta de estadística vertical: ícono, título en mayúsculas y valor grande.
/// Se usa en el Panel de Administración y en el Panel de Ventas.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color iconColor;
  final Color iconBackground;
  final Color valueColor;
  final double padding;
  final double iconPadding;
  final double iconRadius;
  final double titleSize;
  final bool centerVertically;

  const StatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.iconColor,
    required this.iconBackground,
    required this.valueColor,
    this.padding = 24,
    this.iconPadding = 10,
    this.iconRadius = 12,
    this.titleSize = 11,
    this.centerVertically = false,
  });

  /// Estilo del Panel de Administración: todo pintado con el color de acento.
  factory StatCard.accent({
    required IconData icon,
    required String title,
    required String value,
    required Color accent,
  }) => StatCard(
    icon: icon,
    title: title,
    value: value,
    iconColor: accent,
    iconBackground: accent.withOpacity(0.1),
    valueColor: accent,
    padding: 22,
  );

  /// Estilo del Panel de Ventas: ícono azul sobre gris, valor negro o verde.
  factory StatCard.neutral({
    required IconData icon,
    required String title,
    required String value,
    bool isMonetary = false,
  }) => StatCard(
    icon: icon,
    title: title,
    value: value,
    iconColor: AppColors.primary,
    iconBackground: Colors.grey.shade100,
    valueColor: isMonetary ? Colors.green.shade700 : Colors.black87,
    iconPadding: 8,
    iconRadius: 8,
    titleSize: 12,
    centerVertically: true,
  );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      width: double.infinity,
      radius: 20,
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: centerVertically
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(iconPadding),
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(iconRadius),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de estadística horizontal (ícono a la izquierda) de la pantalla
/// de Inicio: "4 Estudiantes Activos", "6 Ventas en el Campus", ...
class InlineStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const InlineStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      width: double.infinity,
      radius: 20,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Distribuye tarjetas en fila (escritorio) o en columna (móvil).
/// Con [trailingGap] también se deja el espacio después de la última
/// tarjeta (así estaba maquetado el Panel de Administración).
class StatCardsRow extends StatelessWidget {
  final List<Widget> cards;
  final bool isMobile;
  final double spacing;
  final double? mobileSpacing;
  final bool trailingGap;

  const StatCardsRow({
    super.key,
    required this.cards,
    required this.isMobile,
    this.spacing = 16,
    this.mobileSpacing,
    this.trailingGap = false,
  });

  @override
  Widget build(BuildContext context) {
    final gap = isMobile ? (mobileSpacing ?? spacing) : spacing;
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      final isLast = i == cards.length - 1;
      final card = trailingGap
          ? Padding(
              padding: isMobile
                  ? EdgeInsets.only(bottom: gap)
                  : EdgeInsets.only(right: gap),
              child: cards[i],
            )
          : cards[i];
      children.add(isMobile ? card : Expanded(child: card));
      if (!trailingGap && !isLast) {
        children.add(isMobile ? SizedBox(height: gap) : SizedBox(width: gap));
      }
    }
    return isMobile ? Column(children: children) : Row(children: children);
  }
}
