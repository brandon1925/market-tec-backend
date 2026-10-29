import 'package:flutter/material.dart';

/// Fila de 5 estrellas de solo lectura.
class StarRating extends StatelessWidget {
  final int rating;
  final double size;
  final Color color;

  const StarRating({
    super.key,
    required this.rating,
    this.size = 14,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < rating ? Icons.star : Icons.star_border,
          size: size,
          color: color,
        ),
      ),
    );
  }
}

/// Selector de calificación (1 a 5 estrellas).
/// - [compact] = false: estrellas grandes con IconButton (modal de Inicio).
/// - [compact] = true: estrellas pequeñas con GestureDetector (Opiniones).
class StarRatingSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;
  final bool compact;
  final MainAxisAlignment alignment;

  const StarRatingSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 38,
    this.compact = false,
    this.alignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: alignment,
      children: List.generate(5, (index) {
        final icon = Icon(
          index < value ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: size,
        );
        if (compact) {
          return GestureDetector(
            onTap: () => onChanged(index + 1),
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: icon,
            ),
          );
        }
        return IconButton(icon: icon, onPressed: () => onChanged(index + 1));
      }),
    );
  }
}
