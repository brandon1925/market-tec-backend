import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/ui_helpers.dart';
import 'core/validators.dart';
import 'widgets/auth_widgets.dart';

class RecuperarPasswordScreen extends StatefulWidget {
  const RecuperarPasswordScreen({super.key});

  @override
  State<RecuperarPasswordScreen> createState() =>
      _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen>
    with FormSubmitMixin {
  int _pasoActual = 1; // 1: Correo, 2: Código, 3: Nueva Contraseña

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _codigoGeneradoPorBackend;

  @override
  void dispose() {
    _emailController.dispose();
    _codigoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _errorConexion(Object _) =>
      context.showError('No pudimos conectar con el servidor, revisa tu internet');

  /// Pasa al siguiente paso y reinicia la validación en vivo del formulario.
  void _irAPaso(int paso) => setState(() {
    _pasoActual = paso;
    autovalidateMode = AutovalidateMode.disabled;
  });

  // PASO 1: VALIDAR CORREO Y ENVIAR CÓDIGO
  String get _correo => Validators.correoCompleto(_emailController.text);

  Future<void> _enviarCodigo() async {
    context.cerrarTeclado();
    if (!validarFormulario()) return;

    await enviar(() async {
      final response = await ApiClient.post('/recuperar-password/enviar', {
        "correo": _correo,
      });
      if (!mounted) return;

      if (response.statusCode == 200) {
        _codigoGeneradoPorBackend = ApiClient.decode(
          response,
        )['codigo_secreto'];
        _irAPaso(2); // Avanzamos a la pantalla de código
      } else if (response.statusCode == 404) {
        context.showError('Este correo no está registrado');
      } else {
        context.showError(
          ApiClient.detalle(response) ?? 'No se pudo enviar el código',
        );
      }
    }, onError: _errorConexion);
  }

  // PASO 2: VERIFICAR QUE LOS 4 DÍGITOS COINCIDAN
  void _verificarCodigo() {
    context.cerrarTeclado();
    if (!validarFormulario()) return;
    if (_codigoController.text.trim() == _codigoGeneradoPorBackend) {
      _irAPaso(3); // Avanzamos a pedir la nueva contraseña
    } else {
      context.showError('El código no coincide, intenta de nuevo');
    }
  }

  // PASO 3: GUARDAR NUEVA CONTRASEÑA EN BD
  Future<void> _guardarNuevaContrasena() async {
    context.cerrarTeclado();
    if (!validarFormulario()) return;

    await enviar(() async {
      final response = await ApiClient.post('/recuperar-password/restablecer', {
        "correo": _correo,
        "nueva_password": _passwordController.text.trim(),
      });
      if (!mounted) return;

      if (response.statusCode == 200) {
        context.showSuccess('¡Listo! Ya puedes entrar con tu nueva contraseña');
        Navigator.pop(context); // Volvemos al Login
      } else {
        context.showError(
          ApiClient.detalle(response) ?? 'No se pudo cambiar la contraseña',
        );
      }
    }, onError: _errorConexion);
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      showBackBar: true,
      scrollPadding: const EdgeInsets.all(24),
      cardPadding: const EdgeInsets.all(40),
      bouncing: false,
      child: Form(
        key: formKey,
        autovalidateMode: autovalidateMode,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_pasoActual) {
            1 => _buildPaso1(),
            2 => _buildPaso2(),
            _ => _buildPaso3(),
          },
        ),
      ),
    );
  }

  Widget _buildPaso1() {
    return _PasoRecuperacion(
      key: const ValueKey(1),
      icon: Icons.lock_reset,
      title: '¿Olvidaste tu contraseña?',
      description:
          'No pasa nada, escribe tu correo institucional y te mandamos un código para crear una nueva',
      field: CorreoInstitucionalField(
        controller: _emailController,
        subtleHint: false,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _enviarCodigo(),
      ),
      button: LoadingButton(
        text: 'Enviar código',
        isLoading: isLoading,
        onPressed: _enviarCodigo,
      ),
    );
  }

  Widget _buildPaso2() {
    return _PasoRecuperacion(
      key: const ValueKey(2),
      icon: Icons.mark_email_read,
      iconColor: AppColors.success,
      title: 'Revisa tu correo',
      description:
          'Te enviamos un código de 4 dígitos a\n$_correo\nRevisa también la carpeta de spam',
      field: VerificationCodeField(
        controller: _codigoController,
        onFieldSubmitted: (_) => _verificarCodigo(),
      ),
      button: LoadingButton(
        text: 'Verificar código',
        onPressed: _verificarCodigo,
      ),
    );
  }

  Widget _buildPaso3() {
    return _PasoRecuperacion(
      key: const ValueKey(3),
      icon: Icons.vpn_key,
      title: 'Nueva contraseña',
      description:
          'Crea una contraseña nueva para $_correo',
      field: PasswordField(
        controller: _passwordController,
        hint: 'Nueva contraseña',
        subtleHint: false,
        validator: Validators.passwordNueva,
        onFieldSubmitted: (_) => _guardarNuevaContrasena(),
      ),
      button: LoadingButton(
        text: 'Restablecer contraseña',
        isLoading: isLoading,
        onPressed: _guardarNuevaContrasena,
      ),
    );
  }
}

/// Estructura común de los 3 pasos: ícono, título, descripción, campo y botón.
class _PasoRecuperacion extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final Widget field;
  final Widget button;

  const _PasoRecuperacion({
    super.key,
    required this.icon,
    this.iconColor = AppColors.primary,
    required this.title,
    required this.description,
    required this.field,
    required this.button,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: iconColor.withOpacity(0.8)),
        const SizedBox(height: 24),
        AuthTitle(title, fontSize: 24, letterSpacing: null),
        const SizedBox(height: 8),
        AuthSubtitle(description),
        const SizedBox(height: 32),
        field,
        const SizedBox(height: 32),
        button,
      ],
    );
  }
}
