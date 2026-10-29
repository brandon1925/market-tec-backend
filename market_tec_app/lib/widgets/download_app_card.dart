import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import 'app_card.dart';

/// Tarjeta "Descarga la app para Android" de la página de Inicio (web).
/// El botón abre [AppConfig.apkUrl]; si es una ruta relativa se resuelve
/// contra la URL donde está publicada la web.
class DownloadAppCard extends StatelessWidget {
  final bool isMobile;
  const DownloadAppCard({super.key, required this.isMobile});

  Future<void> _descargar(BuildContext context) async {
    final url = Uri.base.resolve(AppConfig.apkUrl);
    final ok = await launchUrl(url, webOnlyWindowName: '_self');
    if (!ok && context.mounted) {
      context.showSnack('No se pudo iniciar la descarga', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lleva Market-Tec en tu celular',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Descarga la app para Android, instálala y entra con tu misma cuenta. '
          'Si tu celular lo pide, permite instalar apps de "orígenes desconocidos"',
          style: TextStyle(color: Colors.grey.shade600, height: 1.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Versión ${AppConfig.appVersion} · Android 5.0 o superior',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    );

    final boton = ElevatedButton.icon(
      onPressed: () => _descargar(context),
      icon: const Icon(Icons.android, size: 20),
      label: const Text(
        'Descargar app Android',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );

    final icono = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.phone_android,
        color: AppColors.primary,
        size: 32,
      ),
    );

    return AppCard(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icono,
                const SizedBox(height: 16),
                info,
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: boton),
              ],
            )
          : Row(
              children: [
                icono,
                const SizedBox(width: 20),
                Expanded(child: info),
                const SizedBox(width: 20),
                boton,
              ],
            ),
    );
  }
}
