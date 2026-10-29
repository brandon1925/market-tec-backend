import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ==========================================
// COLORES DE LA APP
// ==========================================
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0B2447);
  static const Color primaryLight = Color(0xFF19376D);
  static const Color background = Color(0xFFF8F9FA);
  static const Color gradientTop = Color(0xFFE3EEFF);
  static const Color success = Color(0xFF00B074);
  static const Color sendButton = Color(0xFF6C7E93);
  static const Color reportButton = Color(0xFFE84545);
  static const Color warningBg = Color(0xFFFFF5F5);
  static const Color warningBorder = Color(0xFFFFD6D6);
  static const Color warningIcon = Color(0xFFD9383A);
  static const Color warningText = Color(0xFFC82829);
}

// ==========================================
// TEMA GLOBAL
// ==========================================
class AppTheme {
  AppTheme._();

  /// Tema único de la app. Todo usa Poppins (también diálogos, tablas,
  /// selectores de hora y fecha) y el azul de la web. Se fijan todos los
  /// colores del esquema para que Material 3 no genere tonos rosas o morados.
  static ThemeData get light {
    final base = ThemeData(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDCE6F7),
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.primaryLight,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDCE6F7),
      onSecondaryContainer: AppColors.primary,
      tertiary: AppColors.primaryLight,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFDCE6F7),
      onTertiaryContainer: AppColors.primary,
      surface: Colors.white,
      surfaceTint: Colors.transparent,
    );

    final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme);

    return base.copyWith(
      colorScheme: scheme,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      primaryTextTheme: GoogleFonts.poppinsTextTheme(base.primaryTextTheme),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: GoogleFonts.poppins(color: Colors.white),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        hourMinuteColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.grey.shade100,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.primary,
        ),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.white,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.primary,
        ),
        dialBackgroundColor: Colors.grey.shade100,
        dialHandColor: AppColors.primary,
        dialTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.primary,
        ),
        entryModeIconColor: AppColors.primary,
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: Colors.white,
        rangePickerBackgroundColor: Colors.white,
        rangePickerHeaderBackgroundColor: AppColors.primary,
        rangePickerHeaderForegroundColor: Colors.white,
        rangeSelectionBackgroundColor: Color(0xFFDCE6F7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.success : null,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 24),
      ),
    );
  }
}

// ==========================================
// ESTILOS DE TEXTO Y DECORACIONES COMPARTIDAS
// ==========================================
class AppStyles {
  AppStyles._();

  /// Encabezado de columnas de todas las DataTable (admin y vender).
  static TextStyle get tableHeading => TextStyle(
    color: Colors.grey.shade500,
    fontWeight: FontWeight.bold,
    fontSize: 12,
  );

  /// Forma redondeada de los AlertDialog de la app.
  static RoundedRectangleBorder dialogShape([double radius = 20]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

  /// Fondo degradado de Login, Registro y Recuperar contraseña.
  static const BoxDecoration authGradient = BoxDecoration(
    gradient: LinearGradient(
      colors: [AppColors.gradientTop, AppColors.primary],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  );

  /// Campo de texto con borde gris redondeado (buscadores, reportes, etc.).
  static InputDecoration outlinedInput({
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    EdgeInsetsGeometry? contentPadding,
    bool fixedBorderColor = false,
    bool alignLabelWithHint = false,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: contentPadding,
      alignLabelWithHint: alignLabelWithHint,
      border: border,
      enabledBorder: fixedBorderColor ? border : null,
    );
  }
}

// ==========================================
// CONSTANTES DE NEGOCIO COMPARTIDAS
// ==========================================
class AppConstants {
  AppConstants._();

  static const List<String> categoriasProducto = [
    'Dulces',
    'Electrónica',
    'Servicios',
    'Ropa y Accesorios',
    'Materiales',
    'Otros',
  ];

  static const List<String> estadosProducto = [
    'Nuevo',
    'Usado',
    'Hecho a mano',
  ];

  static const List<String> motivosReporte = [
    'Producto en mal estado o distinto a la foto',
    'No se presentó en el punto de entrega',
    'Cobro indebido o cambio de precio sin aviso',
    'Comportamiento inapropiado o lenguaje ofensivo',
    'Venta de artículo prohibido dentro del ITZ',
    'Otro motivo',
  ];

  /// Motivos rápidos cuando el vendedor rechaza un pedido.
  static const List<String> motivosRechazo = [
    'Se agotó',
    'Ya no estoy en el punto de entrega',
    'Ya me fui del campus',
    'No puedo entregar a esa hora',
    'El producto ya no está disponible',
  ];

  /// Tipos de comentario sobre la plataforma.
  static const List<(String, IconData, String)> tiposComentarioWeb = [
    ('Sugerencia', Icons.lightbulb_outline, 'Una idea para mejorar'),
    ('Error', Icons.bug_report_outlined, 'Algo no funcionó bien'),
    ('Comentario', Icons.chat_bubble_outline, 'Cualquier otra opinión'),
  ];

  /// Modalidades de entrega que se eligen en cada turno del horario.
  static const List<(String, String, IconData)> modalidadesEntrega = [
    ('Punto de encuentro', 'Te veo en un lugar del campus', Icons.place_outlined),
    ('Entrega en el salón', 'Lo llevo a donde estés en el ITZ', Icons.school_outlined),
    ('A domicilio cercano', 'Cerca del campus, puede tener costo', Icons.delivery_dining_outlined),
    ('Recoger conmigo', 'Pasas por él a mi ubicación', Icons.storefront_outlined),
  ];

  /// Días hábiles (sin sábado ni domingo: no hay clases).
  static const List<String> diasCortos = ['L', 'M', 'X', 'J', 'V'];
  static const List<String> diasNombres = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
  ];

  /// Rango permitido para los turnos de venta.
  static const int horaMinimaTurno = 6; // 6:00 am
  static const int horaMaximaTurno = 21; // 9:00 pm

  /// Solicitudes pendientes: a partir de cuántas se pinta amarillo / rojo.
  static const int pendientesAmarillo = 1;
  static const int pendientesRojo = 5;

  /// Ancho a partir del cual las pantallas principales dejan de ser "móvil".
  static const double mobileBreakpoint = 1000;
}
