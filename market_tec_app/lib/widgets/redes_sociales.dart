import 'package:flutter/material.dart';

import '../core/ui_helpers.dart';
import '../core/validators.dart';

/// Datos de cada red social: clave en la BD, nombre, ícono, color y cómo
/// se arma el enlace.
class RedSocial {
  final String clave;
  final String nombre;
  final IconData icon;
  final Color color;
  final String hint;
  final String Function(String valor) enlace;

  const RedSocial(
    this.clave,
    this.nombre,
    this.icon,
    this.color,
    this.hint,
    this.enlace,
  );

  static final List<RedSocial> todas = [
    RedSocial(
      'whatsapp',
      'WhatsApp',
      Icons.chat,
      const Color(0xFF25D366),
      '10 dígitos, ej. 7771234567',
      (v) => 'https://wa.me/52${v.replaceAll(RegExp(r'\D'), '')}',
    ),
    RedSocial(
      'instagram',
      'Instagram',
      Icons.camera_alt_outlined,
      const Color(0xFFC13584),
      'Usuario, ej. dulces_itz',
      (v) => 'https://instagram.com/${Validators.limpiarUsuarioRed(v)}',
    ),
    RedSocial(
      'facebook',
      'Facebook',
      Icons.facebook,
      const Color(0xFF1877F2),
      'Usuario o enlace de tu perfil',
      (v) => v.startsWith('http') ? v : 'https://facebook.com/$v',
    ),
    RedSocial(
      'tiktok',
      'TikTok',
      Icons.music_note_outlined,
      Colors.black,
      'Usuario, ej. dulces_itz',
      (v) => 'https://tiktok.com/@${Validators.limpiarUsuarioRed(v)}',
    ),
  ];

  String? validar(String? v) => switch (clave) {
    'whatsapp' => Validators.whatsapp(v),
    'facebook' => Validators.facebook(v),
    _ => Validators.usuarioRed(v),
  };
}

/// Botones para contactar por redes sociales. Solo aparecen las que el
/// usuario llenó.
class RedesSocialesBotones extends StatelessWidget {
  final Map<String, dynamic> redes;
  final bool compacto;
  final WrapAlignment alignment;

  const RedesSocialesBotones({
    super.key,
    required this.redes,
    this.compacto = false,
    this.alignment = WrapAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final disponibles = RedSocial.todas.where((r) {
      final v = redes[r.clave];
      return v != null && '$v'.trim().isNotEmpty;
    }).toList();
    if (disponibles.isEmpty) return const SizedBox.shrink();

    return Wrap(
      alignment: alignment,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in disponibles)
          ActionChip(
            avatar: Icon(r.icon, color: r.color, size: compacto ? 16 : 18),
            label: Text(r.nombre),
            labelStyle: TextStyle(
              fontSize: compacto ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
            visualDensity: compacto ? VisualDensity.compact : null,
            backgroundColor: r.color.withOpacity(0.08),
            side: BorderSide(color: r.color.withOpacity(0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onPressed: () => abrirUrl(context, r.enlace('${redes[r.clave]}'.trim())),
          ),
      ],
    );
  }
}

/// Controladores de los 4 campos de redes sociales.
class RedesControllers {
  final Map<String, TextEditingController> campos;

  RedesControllers([Map<String, String> iniciales = const {}])
    : campos = {
        for (final r in RedSocial.todas)
          r.clave: TextEditingController(text: iniciales[r.clave] ?? ''),
      };

  /// Valores limpios listos para mandar al backend ('' = borrar).
  Map<String, String> valores() => {
    for (final r in RedSocial.todas)
      r.clave: switch (r.clave) {
        'whatsapp' => campos[r.clave]!.text.replaceAll(RegExp(r'\D'), ''),
        'facebook' => campos[r.clave]!.text.trim(),
        _ => Validators.limpiarUsuarioRed(campos[r.clave]!.text),
      },
  };

  void dispose() {
    for (final c in campos.values) {
      c.dispose();
    }
  }
}

/// Los 4 campos (van dentro de un Form).
class RedesSocialesCampos extends StatelessWidget {
  final RedesControllers controllers;
  const RedesSocialesCampos({super.key, required this.controllers});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in RedSocial.todas) ...[
          TextFormField(
            controller: controllers.campos[r.clave],
            validator: r.validar,
            keyboardType: r.clave == 'whatsapp'
                ? TextInputType.phone
                : TextInputType.text,
            inputFormatters: r.clave == 'whatsapp'
                ? InputFilters.telefono
                : InputFilters.usuarioRed,
            decoration: InputDecoration(
              labelText: r.nombre,
              hintText: r.hint,
              prefixIcon: Icon(r.icon, color: r.color),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
