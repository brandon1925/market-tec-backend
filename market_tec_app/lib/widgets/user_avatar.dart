import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../core/validators.dart';

/// Foto de perfil (o logo del negocio). Si no hay foto, muestra las iniciales.
class UserAvatar extends StatelessWidget {
  final String nombre;
  final String? fotoUrl;
  final double radius;
  final Color backgroundColor;
  final Color textColor;

  const UserAvatar({
    super.key,
    required this.nombre,
    this.fotoUrl,
    this.radius = 20,
    this.backgroundColor = AppColors.primary,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final inicialesTexto = Text(
      iniciales(nombre),
      style: TextStyle(
        color: textColor,
        fontWeight: FontWeight.bold,
        fontSize: radius * 0.7,
      ),
    );
    if (!Validators.esUrlImagen(fotoUrl)) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: inicialesTexto,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: Image.network(
          fotoUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => Center(child: inicialesTexto),
        ),
      ),
    );
  }
}

/// Imagen de producto que siempre cabe completa en su caja (sin recortes):
/// fondo difuminado con la misma foto y la foto completa encima.
class ProductImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final bool cover;

  const ProductImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = 0,
    this.cover = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: width,
      height: height,
      color: Colors.grey.shade100,
      child: Icon(Icons.image_outlined, color: Colors.grey.shade400),
    );

    if (!Validators.esUrlImagen(url)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: placeholder(),
      );
    }

    final Widget imagen = cover
        ? Image.network(
            url!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => placeholder(),
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url!,
                fit: BoxFit.cover,
                color: Colors.white.withOpacity(0.55),
                colorBlendMode: BlendMode.lighten,
                errorBuilder: (c, e, s) => placeholder(),
              ),
              Image.network(
                url!,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const SizedBox.shrink(),
              ),
            ],
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: cover ? imagen : SizedBox(width: width, height: height, child: imagen),
    );
  }
}
