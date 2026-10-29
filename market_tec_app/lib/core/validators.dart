import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ==========================================
// VALIDADORES DE FORMULARIOS
// ==========================================
// Todos regresan null si el valor es válido, o el mensaje de error en
// español. Se usan como `validator:` de un TextFormField, o directamente
// (`Validators.comentario(texto)`) cuando el campo no está en un Form.
class Validators {
  Validators._();

  static const String dominioInstitucional = '@zacatepec.tecnm.mx';

  static final RegExp _correo = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
  // Número de control: 8 dígitos, con una C opcional al inicio
  // (ej. 22090752 o C22090752).
  static final RegExp _numeroControl = RegExp(r'^C?\d{8}$');
  // Usuario del correo de alumno (lo que va antes de la @): L, C o LC y
  // luego 8 dígitos (ej. L23090970, C22090752, LC22090752).
  static final RegExp _usuarioCorreo = RegExp(r'^(L|C|LC)\d{8}$');
  static final RegExp _nombre = RegExp(r"^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' ]+$");
  static final RegExp _username = RegExp(r'^[A-Za-z0-9_.]+$');
  static final RegExp _precio = RegExp(r'^\d+(\.\d{1,2})?$');

  static bool _vacio(String? v) => v == null || v.trim().isEmpty;

  /// Campo obligatorio.
  static String? requerido(String? v, [String campo = 'Este campo']) =>
      _vacio(v) ? '$campo es obligatorio' : null;

  /// Correo institucional completo (ej. L23090970@zacatepec.tecnm.mx).
  /// La parte de antes de la @ sigue las mismas reglas que [usuarioCorreo].
  static String? correoInstitucional(String? v) {
    if (_vacio(v)) return 'Ingresa tu correo institucional';
    final correo = v!.trim().toLowerCase();
    if (!_correo.hasMatch(correo)) return 'Formato de correo inválido';
    if (!correo.endsWith(dominioInstitucional)) {
      return 'Debe ser un correo institucional ($dominioInstitucional)';
    }
    return usuarioCorreo(correo.split('@').first);
  }

  /// Solo la parte antes de la @ (el dominio ya está fijo en el campo):
  /// L, C o LC y después exactamente 8 números.
  static String? usuarioCorreo(String? v) {
    if (_vacio(v)) return 'Ingresa tu correo institucional';
    final u = v!.trim().toUpperCase();
    if (!RegExp(r'^(L|C|LC)(\d|$)').hasMatch(u)) {
      return 'Debe empezar con L, C o LC';
    }
    if (!_usuarioCorreo.hasMatch(u)) {
      return 'Después de la letra van 8 números, ej. L23090970';
    }
    return null;
  }

  /// Arma el correo completo a partir de lo que escribió el usuario.
  /// En el campo se ve en mayúsculas (L23090970), pero se manda en
  /// minúsculas para que coincida con las cuentas que ya existen.
  static String correoCompleto(String usuario) =>
      '${usuario.trim().split('@').first.toLowerCase()}$dominioInstitucional';

  /// Correo sugerido a partir del número de control: "L" + número de control
  /// (22090752 → L22090752, C22090752 → LC22090752).
  static String usuarioCorreoDesdeControl(String control) {
    final c = control.trim().toUpperCase();
    if (c.isEmpty) return '';
    return '$prefijoCorreoAlumno$c';
  }

  static const String prefijoCorreoAlumno = 'L';

  static String? numeroControl(String? v) {
    if (_vacio(v)) return 'Ingresa tu número de control';
    final c = v!.trim().toUpperCase();
    if (RegExp(r'^[A-Z]').hasMatch(c) && !c.startsWith('C')) {
      return 'Solo se permite la letra C al inicio';
    }
    if (!_numeroControl.hasMatch(c)) {
      return 'Deben ser 8 números, ej. 22090752 o C22090752';
    }
    return null;
  }

  static String? nombreCompleto(String? v) {
    if (_vacio(v)) return 'Ingresa tu nombre completo';
    final nombre = v!.trim();
    if (!_nombre.hasMatch(nombre)) return 'Usa solo letras y espacios';
    if (nombre.length < 5 || nombre.split(RegExp(r'\s+')).length < 2) {
      return 'Escribe al menos nombre y apellido';
    }
    if (nombre.length > 80) return 'Máximo 80 caracteres';
    return null;
  }

  static String? username(String? v) {
    if (_vacio(v)) return 'Ingresa un nombre de usuario';
    final u = v!.trim();
    if (u.length < 3 || u.length > 20) return 'Debe tener de 3 a 20 caracteres';
    if (!_username.hasMatch(u)) return 'Solo letras, números, "." y "_"';
    return null;
  }

  /// Contraseña nueva (registro y recuperación): 8 a 64 caracteres, sin
  /// espacios, con al menos una letra y un número.
  static String? passwordNueva(String? v) {
    if (v == null || v.isEmpty) return 'Ingresa una contraseña';
    if (v.contains(' ')) return 'La contraseña no puede tener espacios';
    if (v.length < 8) return 'Mínimo 8 caracteres';
    if (v.length > 64) return 'Máximo 64 caracteres';
    if (!v.contains(RegExp(r'[A-Za-z]')) || !v.contains(RegExp(r'\d'))) {
      return 'Debe incluir al menos una letra y un número';
    }
    return null;
  }

  /// Confirmación de la contraseña nueva.
  static String? confirmarPassword(String? v, String original) {
    if (v == null || v.isEmpty) return 'Repite la contraseña';
    if (v != original) return 'Las contraseñas no coinciden';
    return null;
  }

  /// Contraseña del login: solo se pide que no esté vacía, para no bloquear
  /// cuentas creadas antes de estas reglas.
  static String? passwordLogin(String? v) =>
      _vacio(v) ? 'Ingresa tu contraseña' : null;

  static String? codigoVerificacion(String? v) {
    if (_vacio(v)) return 'Ingresa el código que te enviamos';
    if (!RegExp(r'^\d{4}$').hasMatch(v!.trim())) {
      return 'El código debe tener 4 dígitos';
    }
    return null;
  }

  /// Texto libre con largo mínimo y máximo (comentarios, reportes, ...).
  static String? texto(
    String? v, {
    required String campo,
    int min = 1,
    required int max,
    bool opcional = false,
  }) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return opcional ? null : 'Escribe $campo';
    if (t.length < min) return '$campo: mínimo $min caracteres';
    if (t.length > max) return '$campo: máximo $max caracteres';
    return null;
  }

  static String? comentario(String? v, {bool opcional = false}) => texto(
    v,
    campo: 'el comentario',
    min: 3,
    max: maxComentario,
    opcional: opcional,
  );

  static String? descripcionReporte(String? v) =>
      texto(v, campo: 'la explicación', min: 20, max: maxReporte);

  static String? nombreProducto(String? v) =>
      texto(v, campo: 'el nombre del producto', min: 3, max: 60);

  static String? descripcionProducto(String? v) => texto(
    v,
    campo: 'la descripción',
    max: maxDescripcionProducto,
    opcional: true,
  );

  static String? precio(String? v) {
    if (_vacio(v)) return 'Ingresa el precio';
    final p = v!.trim();
    if (!_precio.hasMatch(p)) return 'Precio inválido, máximo 2 decimales';
    final valor = double.parse(p);
    if (valor <= 0) return 'Debe ser mayor a \$0';
    if (valor > 100000) return 'Máximo \$100,000';
    return null;
  }

  /// Stock entero. Al publicar se pide al menos 1; al editar se permite 0
  /// (el producto queda "Pausado (Agotado)").
  static String? stock(String? v, {int minimo = 0}) {
    if (_vacio(v)) return 'Ingresa el stock';
    final s = int.tryParse(v!.trim());
    if (s == null) return 'Debe ser un número entero';
    if (s < minimo) return 'El mínimo es $minimo';
    if (s > 9999) return 'Máximo 9999 unidades';
    return null;
  }

  /// Imagen elegida para un producto: formato y tamaño.
  static String? imagenProducto(String nombre, int bytes) {
    final ext = nombre.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
      return 'La imagen debe ser JPG, PNG, WEBP o GIF';
    }
    if (bytes > maxImagenBytes) return 'La imagen no puede pesar más de 5 MB';
    return null;
  }

  /// URL http(s) de una imagen (para datos que vienen del backend).
  static bool esUrlImagen(String? url) {
    final uri = Uri.tryParse(url ?? '');
    return uri != null &&
        uri.hasAuthority &&
        (uri.isScheme('http') || uri.isScheme('https'));
  }

  /// Turno de horario: fin > inicio y sin traslaparse con [existentes]
  /// (lista de pares "HH:mm" inicio/fin del mismo día).
  static String? turno(
    TimeOfDay inicio,
    TimeOfDay fin,
    Iterable<(String, String)> existentes,
  ) {
    final ini = _minutos(inicio);
    final f = _minutos(fin);
    const minimo = AppLimites.horaMinimaTurno * 60;
    const maximo = AppLimites.horaMaximaTurno * 60;
    if (ini < minimo || f > maximo) {
      return 'El horario permitido es de 6:00 am a 9:00 pm';
    }
    if (f <= ini) return 'La hora de fin debe ser después de la de inicio';
    if (f - ini < 15) return 'El turno debe durar al menos 15 minutos';
    for (final (a, b) in existentes) {
      final otroIni = _minutosDeTexto(a);
      final otroFin = _minutosDeTexto(b);
      if (otroIni == null || otroFin == null) continue;
      if (ini < otroFin && otroIni < f) {
        return 'Se traslapa con el turno de ${a.substring(0, 5)} a ${b.substring(0, 5)}';
      }
    }
    return null;
  }

  // ---------- Redes sociales ----------
  static final RegExp _usuarioRed = RegExp(r'^[A-Za-z0-9._]{1,30}$');

  /// Usuario de Instagram o TikTok (sin @). Opcional.
  static String? usuarioRed(String? v) {
    final t = limpiarUsuarioRed(v ?? '');
    if (t.isEmpty) return null;
    if (!_usuarioRed.hasMatch(t)) return 'Usuario inválido (sin espacios)';
    return null;
  }

  /// WhatsApp a 10 dígitos (México). Opcional.
  static String? whatsapp(String? v) {
    final t = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (t.isEmpty) return null;
    if (t.length != 10) return 'Escribe tu número a 10 dígitos';
    return null;
  }

  /// Facebook: usuario o enlace del perfil. Opcional.
  static String? facebook(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    if (t.contains(' ')) return 'Sin espacios';
    if (t.length > 120) return 'Demasiado largo';
    return null;
  }

  /// Quita @, espacios y el enlace completo si lo pegaron.
  static String limpiarUsuarioRed(String v) {
    var t = v.trim();
    final uri = Uri.tryParse(t);
    if (uri != null && uri.hasAuthority && uri.pathSegments.isNotEmpty) {
      t = uri.pathSegments.first;
    }
    return t.replaceAll('@', '').trim();
  }

  /// Cantidad a comprar: entre 1 y el stock disponible.
  static String? cantidad(int cantidad, int stock) {
    if (stock <= 0) return 'Este producto está agotado';
    if (cantidad < 1) return 'La cantidad mínima es 1';
    if (cantidad > stock) return 'Solo hay $stock disponibles';
    return null;
  }

  static int _minutos(TimeOfDay t) => t.hour * 60 + t.minute;

  /// "07:30" o "07:30:00" → minutos desde medianoche.
  static int? _minutosDeTexto(String hora) {
    final partes = hora.split(':');
    if (partes.length < 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  // Límites compartidos por los validadores y los `maxLength` de los campos.
  static const int maxComentario = 300;
  static const int maxReporte = 500;
  static const int maxDescripcionProducto = 250;
  static const int maxImagenBytes = 5 * 1024 * 1024;
}

/// Límites de horario (duplicados aquí para no depender de app_theme).
class AppLimites {
  AppLimites._();
  static const int horaMinimaTurno = 6;
  static const int horaMaximaTurno = 21;
}

// ==========================================
// FILTROS DE ESCRITURA (inputFormatters)
// ==========================================
// Impiden teclear caracteres inválidos desde el principio.
class InputFilters {
  InputFilters._();

  static final List<TextInputFormatter> sinEspacios = [
    FilteringTextInputFormatter.deny(RegExp(r'\s')),
  ];

  static final List<TextInputFormatter> correo = [
    FilteringTextInputFormatter.deny(RegExp(r'\s')),
    LengthLimitingTextInputFormatter(80),
  ];

  static final List<TextInputFormatter> password = [
    FilteringTextInputFormatter.deny(RegExp(r'\s')),
    LengthLimitingTextInputFormatter(64),
  ];

  /// Usuario del correo: solo deja escribir L, C o LC y luego hasta 8
  /// números. Las letras se pasan a mayúsculas y, si pegan el correo
  /// completo, se queda solo lo de antes de la @.
  static final List<TextInputFormatter> usuarioCorreo = [
    _MayusculasConPatron(RegExp(r'^((L|C|LC)\d{0,8})?$')),
  ];

  static final List<TextInputFormatter> telefono = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ];

  static final List<TextInputFormatter> usuarioRed = [
    FilteringTextInputFormatter.deny(RegExp(r'\s')),
    LengthLimitingTextInputFormatter(60),
  ];

  /// Número de control: una C opcional al inicio y hasta 8 números.
  static final List<TextInputFormatter> numeroControl = [
    _MayusculasConPatron(RegExp(r'^C?\d{0,8}$')),
  ];

  static final List<TextInputFormatter> nombre = [
    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' ]")),
    LengthLimitingTextInputFormatter(80),
  ];

  static final List<TextInputFormatter> username = [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.]')),
    LengthLimitingTextInputFormatter(20),
  ];

  static final List<TextInputFormatter> codigo4 = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(4),
  ];

  /// Hasta 6 enteros y 2 decimales.
  static final List<TextInputFormatter> precio = [
    _PatronCompleto(RegExp(r'^\d{0,6}(\.\d{0,2})?$')),
  ];

  static final List<TextInputFormatter> entero4 = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(4),
  ];
}

/// Rechaza la tecla si el texto resultante no cumple [patron] completo.
class _PatronCompleto extends TextInputFormatter {
  final RegExp patron;
  _PatronCompleto(this.patron);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => patron.hasMatch(newValue.text) ? newValue : oldValue;
}

/// Pasa el texto a mayúsculas, quita espacios y lo de después de una @, y
/// rechaza la tecla si lo que queda no cumple [patron].
class _MayusculasConPatron extends TextInputFormatter {
  final RegExp patron;
  _MayusculasConPatron(this.patron);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final texto = newValue.text
        .split('@')
        .first
        .replaceAll(RegExp(r'\s'), '')
        .toUpperCase();
    if (!patron.hasMatch(texto)) return oldValue;
    if (texto.length == newValue.text.length) {
      // Mismo largo: solo cambió a mayúsculas, se conserva el cursor.
      return newValue.copyWith(text: texto, composing: TextRange.empty);
    }
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

// ==========================================
// AYUDA PARA FORMULARIOS CON ENVÍO
// ==========================================
/// Agrega a un State un [formKey], la validación "en vivo" después del
/// primer intento fallido y un candado contra envíos dobles.
mixin FormSubmitMixin<T extends StatefulWidget> on State<T> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  AutovalidateMode autovalidateMode = AutovalidateMode.disabled;
  bool isLoading = false;

  /// Valida el Form. Si falla, a partir de ahí los errores se actualizan
  /// mientras el usuario escribe.
  bool validarFormulario() {
    final ok = formKey.currentState?.validate() ?? false;
    if (!ok && autovalidateMode == AutovalidateMode.disabled) {
      setState(() => autovalidateMode = AutovalidateMode.onUserInteraction);
    }
    return ok;
  }

  /// Ejecuta [accion] mostrando el indicador de carga. Si ya hay un envío en
  /// curso no hace nada (evita doble clic / doble Enter).
  Future<void> enviar(
    Future<void> Function() accion, {
    void Function(Object error)? onError,
  }) async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      await accion();
    } catch (e) {
      if (mounted) onError?.call(e);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
}
