import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'validators.dart';

/// Llaves globales: permiten mostrar avisos o cambiar de pantalla desde
/// servicios que no tienen `context` (notificaciones, cierre de sesión).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

extension SnackBarX on BuildContext {
  /// Atajo para `ScaffoldMessenger.of(context).showSnackBar(...)`.
  void showSnack(
    String message, {
    Color? color,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction ?? () {},
              ),
      ),
    );
  }

  void showError(String message) => showSnack(message, color: Colors.red);
  void showSuccess(String message) =>
      showSnack(message, color: Colors.green.shade700);

  /// Abre [pantalla] encima de la actual (con flecha para regresar).
  Future<T?> abrir<T>(Widget pantalla) =>
      Navigator.push<T>(this, MaterialPageRoute(builder: (_) => pantalla));

  /// Cambia a [pantalla] reemplazando la actual (navegación del menú).
  void irA(Widget pantalla) => Navigator.pushReplacement(
    this,
    MaterialPageRoute(builder: (_) => pantalla),
  );

  /// Deja solo [pantalla] en la pila (logo, cerrar sesión).
  void irALimpio(Widget pantalla) => Navigator.pushAndRemoveUntil(
    this,
    MaterialPageRoute(builder: (_) => pantalla),
    (_) => false,
  );

  /// Cierra el teclado.
  void cerrarTeclado() => FocusManager.instance.primaryFocus?.unfocus();
}

/// Diálogo de confirmación Sí/No. Regresa `true` solo si se confirmó.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmText,
  required Color confirmColor,
  IconData? icon,
  bool rounded = true,
  TextStyle? messageStyle,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: rounded ? AppStyles.dialogShape() : null,
      icon: icon == null ? null : Icon(icon, color: confirmColor, size: 36),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: messageStyle ?? const TextStyle(height: 1.5),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogCancelButton(onPressed: () => Navigator.pop(context, false)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Botón "Cancelar" gris que aparece en todos los diálogos.
class DialogCancelButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  const DialogCancelButton({
    super.key,
    required this.onPressed,
    this.text = 'Cancelar',
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(color: Colors.grey)),
    );
  }
}

/// Indicador de carga pequeño para usar dentro de botones.
class ButtonSpinner extends StatelessWidget {
  final double size;
  final double? strokeWidth;
  final Color color;
  const ButtonSpinner({
    super.key,
    this.size = 24,
    this.strokeWidth = 2,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        color: color,
        strokeWidth: strokeWidth ?? 4,
      ),
    );
  }
}

// ==========================================
// FOTOS: CÁMARA O GALERÍA
// ==========================================

/// Foto elegida por el usuario, ya comprimida.
class ImagenElegida {
  final Uint8List bytes;
  final String nombre;
  const ImagenElegida(this.bytes, this.nombre);
}

/// Pregunta si se quiere tomar una foto o elegirla de la galería, la
/// comprime (máx. 1280 px, calidad 75) y valida formato y peso.
/// Regresa null si el usuario cancela o la foto no es válida.
Future<ImagenElegida?> elegirFoto(
  BuildContext context, {
  String titulo = 'Agregar foto',
  double maxLado = 1280,
}) async {
  final ImageSource? fuente = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Tomar foto'),
              subtitle: kIsWeb
                  ? const Text('Disponible en celular o con cámara web')
                  : null,
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (fuente == null) return null;

  try {
    final XFile? foto = await ImagePicker().pickImage(
      source: fuente,
      maxWidth: maxLado,
      maxHeight: maxLado,
      imageQuality: 75,
    );
    if (foto == null) return null;
    final bytes = await foto.readAsBytes();
    // En web la cámara puede devolver un nombre sin extensión.
    final nombre = foto.name.contains('.') ? foto.name : '${foto.name}.jpg';
    final error = Validators.imagenProducto(nombre, bytes.length);
    if (error != null) {
      if (context.mounted) context.showError(error);
      return null;
    }
    return ImagenElegida(bytes, nombre);
  } catch (e) {
    debugPrint('Error eligiendo foto: $e');
    if (context.mounted) {
      context.showError(
        fuente == ImageSource.camera
            ? 'No se pudo abrir la cámara'
            : 'No se pudo abrir la galería',
      );
    }
    return null;
  }
}

// ==========================================
// ENLACES EXTERNOS
// ==========================================

/// Abre un enlace (WhatsApp, Instagram, etc.) fuera de la app.
Future<void> abrirUrl(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!ok && context.mounted) context.showError('No se pudo abrir el enlace');
  } catch (_) {
    if (context.mounted) context.showError('No se pudo abrir el enlace');
  }
}

// ==========================================
// FECHAS Y HORAS
// ==========================================

/// Formatea un TimeOfDay como "HH:mm" (lo que guarda el backend).
String formatHora(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "07:00" o "07:00:00" → "7:00 am".
String hora12(String? hora) {
  final partes = (hora ?? '').split(':');
  if (partes.length < 2) return hora ?? '';
  final h = int.tryParse(partes[0]) ?? 0;
  final m = partes[1].padLeft(2, '0');
  final sufijo = h < 12 ? 'am' : 'pm';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m $sufijo';
}

/// "07:00" → TimeOfDay(7, 0).
TimeOfDay? horaDeTexto(String? hora) {
  final partes = (hora ?? '').split(':');
  if (partes.length < 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
}

const _meses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// Fecha ISO del backend → "27 oct 2026 · 3:40 pm". Si no se puede leer,
/// regresa el texto tal cual.
String formatFecha(dynamic valor, {bool conHora = true}) {
  final f = leerFecha(valor);
  if (f == null) return valor?.toString() ?? '';
  final base = '${f.day} ${_meses[f.month - 1]} ${f.year}';
  if (!conHora) return base;
  return '$base · ${hora12('${f.hour}:${f.minute}')}';
}

/// Fecha relativa corta para chats y notificaciones ("hace 5 min").
String fechaRelativa(dynamic valor) {
  final f = leerFecha(valor);
  if (f == null) return '';
  final d = DateTime.now().difference(f);
  if (d.inMinutes < 1) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return formatFecha(f, conHora: false);
}

DateTime? leerFecha(dynamic valor) {
  if (valor is DateTime) return valor;
  if (valor == null) return null;
  return DateTime.tryParse(valor.toString().replaceFirst(' ', 'T'));
}

/// Iniciales de un nombre ("Brandon Landa" → "BL").
String iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (partes.isEmpty) return 'U';
  if (partes.length == 1) {
    return partes[0].substring(0, partes[0].length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
}
