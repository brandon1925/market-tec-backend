import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../core/validators.dart';

// ==========================================
// LAYOUT DE AUTENTICACIÓN (Login, Registro, Recuperar)
// ==========================================

/// Fondo degradado + tarjeta blanca centrada con sombra.
class AuthLayout extends StatelessWidget {
  final Widget child;
  final bool showBackBar;
  final double maxWidth;
  final EdgeInsetsGeometry cardPadding;
  final EdgeInsetsGeometry scrollPadding;
  final bool bouncing;

  const AuthLayout({
    super.key,
    required this.child,
    this.showBackBar = false,
    this.maxWidth = 450,
    this.cardPadding = const EdgeInsets.all(32),
    this.scrollPadding = const EdgeInsets.symmetric(
      vertical: 24,
      horizontal: 16,
    ),
    this.bouncing = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Center(
      child: SingleChildScrollView(
        physics: bouncing ? const BouncingScrollPhysics() : null,
        padding: scrollPadding,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: cardPadding,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
    // SafeArea siempre: en el celular la tarjeta no queda detrás de la barra
    // de notificaciones ni de la barra de gestos.
    content = SafeArea(child: content);

    return Scaffold(
      extendBodyBehindAppBar: showBackBar,
      appBar: showBackBar
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'Volver al Login',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            )
          : null,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppStyles.authGradient,
        child: content,
      ),
    );
  }
}

/// Logo de la app (assets/images/icono.jpg) con ícono de respaldo.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/images/icono.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) =>
            Icon(Icons.shopping_bag, size: size, color: AppColors.primary),
      ),
    );
  }
}

/// Título grande azul de las pantallas de autenticación.
class AuthTitle extends StatelessWidget {
  final String text;
  final double fontSize;
  final double? letterSpacing;
  final TextAlign textAlign;
  const AuthTitle(
    this.text, {
    super.key,
    this.fontSize = 32,
    this.letterSpacing = -1,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: AppColors.primary,
        letterSpacing: letterSpacing,
      ),
    );
  }
}

/// Texto gris de apoyo debajo del título.
class AuthSubtitle extends StatelessWidget {
  final String text;
  const AuthSubtitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
    );
  }
}

// ==========================================
// CAMPOS DE TEXTO
// ==========================================

/// Etiqueta en negritas arriba de un campo.
class InputLabel extends StatelessWidget {
  final String text;
  const InputLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

InputDecoration _authDecoration({
  required String hint,
  required IconData icon,
  required bool subtleHint,
  Widget? suffixIcon,
  String? suffixText,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: subtleHint
        ? TextStyle(color: Colors.grey.shade400, fontSize: 14)
        : null,
    prefixIcon: Icon(icon, color: Colors.grey.shade600),
    suffixIcon: suffixIcon,
    suffixText: suffixText,
    suffixStyle: TextStyle(
      color: Colors.grey.shade700,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    errorMaxLines: 2,
    filled: true,
    fillColor: Colors.grey.shade50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

/// Campo gris relleno con ícono (correo, nombre, no. de control, ...).
/// Va dentro de un [Form]: [validator] muestra el error debajo del campo e
/// [inputFormatters] impide teclear caracteres inválidos.
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final TextCapitalization textCapitalization;
  final String? suffixText;
  final ValueChanged<String>? onChanged;

  /// Hint gris claro de 14px. En "Recuperar contraseña" era el estilo por defecto.
  final bool subtleHint;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.subtleHint = true,
    this.validator,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.suffixText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      textCapitalization: textCapitalization,
      decoration: _authDecoration(
        hint: hint,
        icon: icon,
        subtleHint: subtleHint,
        suffixText: suffixText,
      ),
    );
  }
}

/// Correo institucional: el usuario solo escribe lo que va antes de la @
/// (L, C o LC + 8 números, en mayúsculas), el dominio @zacatepec.tecnm.mx ya
/// aparece fijo dentro del campo.
/// Para obtener el correo completo usa `Validators.correoCompleto(ctrl.text)`.
class CorreoInstitucionalField extends StatelessWidget {
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool subtleHint;

  const CorreoInstitucionalField({
    super.key,
    required this.controller,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.onChanged,
    this.subtleHint = true,
  });

  @override
  Widget build(BuildContext context) {
    return AuthTextField(
      controller: controller,
      hint: 'L23090970',
      icon: Icons.mail_outline,
      // Teclado sin autocorrector; las letras salen en mayúsculas.
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.characters,
      // Mayúsculas, solo L/C/LC + 8 números y corta lo de después de la @.
      inputFormatters: InputFilters.usuarioCorreo,
      validator: Validators.usuarioCorreo,
      suffixText: Validators.dominioInstitucional,
      subtleHint: subtleHint,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      onChanged: onChanged,
    );
  }
}

/// Campo de contraseña con botón para mostrar/ocultar. No deja escribir
/// espacios y corta en 64 caracteres.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool subtleHint;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    this.hint = 'Tu contraseña',
    this.subtleHint = true,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      inputFormatters: InputFilters.password,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: _authDecoration(
        hint: widget.hint,
        icon: Icons.lock_outline,
        subtleHint: widget.subtleHint,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey.shade600,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Campo grande para el código de verificación de 4 dígitos (solo números).
class VerificationCodeField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onFieldSubmitted;
  const VerificationCodeField({
    super.key,
    required this.controller,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: InputFilters.codigo4,
      validator: Validators.codigoVerificacion,
      onFieldSubmitted: onFieldSubmitted,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: 10,
      ),
      decoration: InputDecoration(
        hintText: "0000",
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ==========================================
// BOTÓN PRINCIPAL CON INDICADOR DE CARGA
// ==========================================

/// Botón ancho completo que muestra un spinner mientras [isLoading] es true
/// (y se deshabilita para evitar doble envío).
class LoadingButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color backgroundColor;
  final double height;
  final double radius;
  final double fontSize;
  final double spinnerSize;
  final double? elevation;

  const LoadingButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.backgroundColor = AppColors.primary,
    this.height = 56,
    this.radius = 16,
    this.fontSize = 16,
    this.spinnerSize = 24,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          elevation: elevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: isLoading
            ? ButtonSpinner(size: spinnerSize)
            : Text(
                text,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
