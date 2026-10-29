import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/notificaciones_service.dart';
import 'core/ui_helpers.dart';
import 'core/validators.dart';
import 'globals.dart' as globals;
import 'inicio_screen.dart';
import 'recuperar_password_screen.dart';
import 'registro_screen.dart';
import 'widgets/auth_widgets.dart';
import 'widgets/perfil_dialogs.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with FormSubmitMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    context.cerrarTeclado();
    if (!validarFormulario()) return;
    final correo = Validators.correoCompleto(_emailController.text);

    await enviar(
      () async {
        final response = await ApiClient.post('/login', {
          "correo_institucional": correo,
          "password": _passwordController.text.trim(),
        });
        if (!mounted) return;

        if (response.statusCode == 200) {
          final data = Map<String, dynamic>.from(ApiClient.decode(response));
          final estado = '${data['estado_cuenta'] ?? 'Activa'}';
          if (estado != 'Activa') {
            context.showError(
              'Tu cuenta está suspendida. Acércate a la coordinación para reactivarla',
            );
            return;
          }

          globals.limpiarUsuario();
          globals.cargarUsuario({
            ...data,
            'correo_institucional': data['correo_institucional'] ?? correo,
          });
          // Foto, redes y estado de la ubicación (endpoint nuevo).
          await refrescarPerfil();
          if (!mounted) return;
          if (globals.currentUserStatus.isNotEmpty &&
              globals.currentUserStatus != 'Activa') {
            globals.limpiarUsuario();
            context.showError('Tu cuenta está suspendida');
            return;
          }

          NotificacionesService.instance.iniciarSesion();
          context.showSuccess(
            '¡Hola, ${globals.currentUserName.split(' ').first}! Qué bueno verte',
          );
          context.irALimpio(const InicioScreen());
        } else if (response.statusCode == 401) {
          context.showError('Correo o contraseña incorrectos');
        } else if (response.statusCode == 403) {
          context.showError(
            ApiClient.detalle(response) ?? 'Tu cuenta está suspendida',
          );
        } else {
          context.showError('Error del servidor (${response.statusCode})');
        }
      },
      onError: (_) => context.showError(
        'No pudimos conectar con el servidor, revisa tu internet',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      child: Form(
        key: formKey,
        autovalidateMode: autovalidateMode,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 72),
            const SizedBox(height: 20),
            _buildExclusiveChip(),
            const SizedBox(height: 24),
            const AuthTitle('¡Bienvenido de vuelta!', fontSize: 28),
            const SizedBox(height: 8),
            const AuthSubtitle(
              'Compra y vende entre compañeros del Tec, sin salir del campus',
            ),
            const SizedBox(height: 28),
            const InputLabel('Correo institucional'),
            CorreoInstitucionalField(controller: _emailController),
            const SizedBox(height: 16),
            const InputLabel('Contraseña'),
            PasswordField(
              controller: _passwordController,
              validator: Validators.passwordLogin,
              onFieldSubmitted: (_) => _iniciarSesion(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.abrir(const RecuperarPasswordScreen()),
                child: const Text(
                  '¿Olvidaste tu contraseña?',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LoadingButton(
              text: 'Entrar a Market-Tec',
              isLoading: isLoading,
              onPressed: _iniciarSesion,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '¿Aún no tienes cuenta?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                TextButton(
                  onPressed: () => context.abrir(const RegistroScreen()),
                  child: const Text(
                    'Créala en 1 minuto',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExclusiveChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Hecho por y para estudiantes del ITZ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
