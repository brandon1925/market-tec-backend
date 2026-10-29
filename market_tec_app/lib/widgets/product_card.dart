import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'status_badge.dart';
import 'user_avatar.dart';

/// Tarjeta de producto del catálogo (grid general y carrusel de favoritos).
/// Tiene altura fija para que todas se vean iguales y sin huecos: la foto
/// se muestra completa (sin recortarla) y el texto ocupa solo lo necesario.
class ProductCard extends StatelessWidget {
  final Map<String, dynamic> producto;
  final bool isFavorite;
  final bool isMine;

  /// En el carrusel de favoritos (fondo azul) la tarjeta no lleva sombra.
  final bool isDarkTheme;
  final bool compacta;
  final VoidCallback onToggleFavorite;

  /// Botón "Ver" (comprar) o "Editar" (si el producto es mío).
  final VoidCallback onAction;

  const ProductCard({
    super.key,
    required this.producto,
    required this.isFavorite,
    required this.isMine,
    required this.isDarkTheme,
    required this.onToggleFavorite,
    required this.onAction,
    this.compacta = false,
  });

  /// Alto total de la tarjeta (lo usa el grid para que todas midan igual).
  static double alto({required bool compacta}) => compacta ? 292 : 332;

  @override
  Widget build(BuildContext context) {
    final String badge = producto['estado'] ?? '';
    final String category = producto['categoria'] ?? 'Otros';
    final String title = producto['nombre'] ?? 'Sin nombre';
    final num precio = producto['precio'] ?? 0;
    final String seller =
        producto['vendedor_nombre'] ?? 'Vendedor #${producto['vendedor_id']}';
    final double ratingNum = (producto['rating'] ?? 0.0).toDouble();
    final double altoFoto = compacta ? 128 : 160;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: isDarkTheme ? 0 : 1,
      shadowColor: Colors.black12,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ProductImage(
                  url: producto['imagen_url'],
                  height: altoFoto,
                  width: double.infinity,
                ),
                if (badge.isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: StatusBadge(
                      text: badge,
                      textColor: Colors.white,
                      backgroundColor: AppColors.primary,
                      fontSize: 11,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                  ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    tooltip: isFavorite ? 'Quitar de favoritos' : 'Guardar',
                    icon: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.85),
                      radius: 15,
                      child: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                    onPressed: onToggleFavorite,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(compacta ? 10 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.star,
                          size: 14,
                          color: ratingNum > 0
                              ? Colors.amber
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          ratingNum > 0 ? ratingNum.toStringAsFixed(1) : 'Nuevo',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compacta ? 14 : 15,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '\$${precio is double ? precio.toStringAsFixed(2) : precio}',
                      style: TextStyle(
                        fontSize: compacta ? 17 : 19,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      isMine ? 'Mi producto' : seller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isMine
                            ? Colors.green.shade700
                            : Colors.grey.shade600,
                        fontWeight: isMine ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: ElevatedButton(
                        onPressed: onAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isMine
                              ? Colors.green.shade700
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          isMine ? 'Editar' : 'Ver',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
