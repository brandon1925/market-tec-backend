import 'dart:async'; // Necesario para el temporizador de 30 segundos

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/ui_helpers.dart';
import 'core/validators.dart';
import 'widgets/auth_widgets.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> with FormSubmitMixin {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _controlController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Guardará el código que envíe FastAPI en secreto
  String? _codigoGeneradoPorBackend;

  // Foto de perfil o logo del negocio (opcional).
  ImagenElegida? _foto;

  // Mientras el usuario no edite el correo a mano, se llena solo con el
  // número de control.
  bool _correoEditadoAMano = false;

  void _alCambiarControl(String control) {
    if (_correoEditadoAMano) return;
    _emailController.text = Validators.usuarioCorreoDesdeControl(control);
  }

  String get _correo => Validators.correoCompleto(_emailController.text);

  Future<void> _elegirFoto() async {
    final foto = await elegirFoto(
      context,
      titulo: 'Foto de perfil o logo de tu negocio',
      maxLado: 600,
    );
    if (foto != null) setState(() => _foto = foto);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _controlController.dispose();
    _userController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ==========================================
  // PASO 1: PEDIR A FASTAPI QUE ENVÍE EL CORREO
  // ==========================================
  /// [reenvio] = true cuando se pide desde el pop-up: solo se actualiza el
  /// código, sin abrir otro pop-up encima.
  Future<bool> _solicitarCodigoVerificacion({bool reenvio = false}) async {
    context.cerrarTeclado();
    if (!reenvio && !validarFormulario()) return false;

    var enviado = false;
    await enviar(
      () async {
        final response = await ApiClient.post('/enviar-codigo', {
          "correo": _correo,
        });
        if (!mounted) return;

        if (response.statusCode == 200) {
          _codigoGeneradoPorBackend = ApiClient.decode(
            response,
          )['codigo_secreto'];
          enviado = true;
          if (!reenvio) _mostrarDialogoVerificacion();
        } else {
          context.showError('Error del servidor: ${response.statusCode}');
        }
      },
      onError: (_) => context.showError(
        'No pudimos conectar con el servidor, revisa tu internet',
      ),
    );
    return enviado;
  }

  // ==========================================
  // PASO 2: POP-UP DE VERIFICACIÓN CON TEMPORIZADOR
  // ==========================================
  void _mostrarDialogoVerificacion() {
    final TextEditingController codigoController = TextEditingController();
    final codigoFormKey = GlobalKey<FormState>();
    int segundosRestantes = 30;
    bool puedeReenviar = false;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          void iniciarTimer() {
            setStateDialog(() {
              segundosRestantes = 30;
              puedeReenviar = false;
            });
            timer?.cancel();
            timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
              if (segundosRestantes == 0) {
                setStateDialog(() => puedeReenviar = true);
                t.cancel();
              } else {
                setStateDialog(() => segundosRestantes--);
              }
            });
          }

          void verificar() {
            if (!codigoFormKey.currentState!.validate()) return;
            // COMPROBAMOS QUE EL CÓDIGO SEA EL CORRECTO
            if (codigoController.text.trim() == _codigoGeneradoPorBackend) {
              timer?.cancel();
              Navigator.pop(context);
              _registrarUsuarioFinal();
            } else {
              context.showError('El código es incorrecto');
            }
          }

          if (timer == null) iniciarTimer();

          return AlertDialog(
            shape: AppStyles.dialogShape(),
            title: const Text(
              'Verifica tu correo',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            content: Form(
              key: codigoFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Te enviamos un código de 4 dígitos a\n$_correo\nRevisa también la carpeta de spam',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  VerificationCodeField(
                    controller: codigoController,
                    onFieldSubmitted: (_) => verificar(),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: puedeReenviar
                        ? () async {
                            iniciarTimer(); // Reinicia el reloj
                            if (await _solicitarCodigoVerificacion(
                                  reenvio: true,
                                ) &&
                                context.mounted) {
                              codigoController.clear();
                              context.showSnack(
                                'Se ha enviado un nuevo código',
                              );
                            }
                          }
                        : null,
                    child: Text(
                      puedeReenviar
                          ? 'Reenviar código'
                          : 'Reenviar código en ${segundosRestantes}s',
                      style: TextStyle(
                        color: puedeReenviar ? AppColors.primary : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              DialogCancelButton(
                onPressed: () {
                  timer?.cancel();
                  Navigator.pop(context);
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: verificar,
                child: const Text(
                  'Verificar y Registrar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    ).then((_) => timer?.cancel());
  }

  // ==========================================
  // PASO 3: REGISTRAR EN LA BASE DE DATOS
  // ==========================================
  Future<void> _registrarUsuarioFinal() => enviar(() async {
    // 1. Si eligió foto, se sube primero.
    String? fotoUrl;
    if (_foto != null) {
      try {
        final url = await ApiClient.uploadImage(_foto!.bytes, _foto!.nombre);
        if (Validators.esUrlImagen(url)) fotoUrl = url;
      } catch (_) {
        // Sin foto no se detiene el registro; la puede poner después.
      }
    }

    // 2. Se crea la cuenta.
    final password = _passwordController.text.trim();
    final response = await ApiClient.post('/usuarios', {
      "numero_control": _controlController.text.trim().toUpperCase(),
      "nombre_completo": _nombreController.text.trim(),
      "username": _userController.text.trim(),
      "correo_institucional": _correo,
      "password": password,
      "id_rol": 1, // 1 = Cliente
      "foto_url": fotoUrl,
    });
    if (!mounted) return;

    if (response.statusCode == 200 || response.statusCode == 201) {
      // 3. Se guarda la foto en el perfil (el registro original no la recibe).
      if (fotoUrl != null) await _guardarFoto(password, fotoUrl);
      if (!mounted) return;
      context.showSuccess('¡Tu cuenta está lista! Ya puedes iniciar sesión');
      Navigator.pop(context);
    } else {
      context.showError(
        ApiClient.detalle(response) ??
            'No se pudo crear la cuenta, puede que el correo, usuario o número de control ya estén registrados',
      );
    }
  }, onError: (e) => context.showError('Sin conexión con el servidor'));

  /// Inicia sesión "por detrás" para obtener el id y guardar la foto.
  Future<void> _guardarFoto(String password, String fotoUrl) async {
    try {
      final login = await ApiClient.post('/login', {
        "correo_institucional": _correo,
        "password": password,
      });
      if (login.statusCode != 200) return;
      final id = ApiClient.decode(login)['user_id'];
      if (id == null) return;
      await ApiClient.put('/usuarios/$id/perfil', {"foto_url": fotoUrl});
    } catch (_) {}
  }

  // ==========================================
  // DISEÑO VISUAL DE LA PANTALLA
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    final controlField = _labeled(
      'No. Control',
      AuthTextField(
        controller: _controlController,
        hint: '22090752',
        icon: Icons.badge_outlined,
        keyboardType: TextInputType.visiblePassword,
        textCapitalization: TextCapitalization.characters,
        // Solo una C opcional al inicio y 8 números (en mayúsculas).
        inputFormatters: InputFilters.numeroControl,
        validator: Validators.numeroControl,
        onChanged: _alCambiarControl,
      ),
    );
    final userField = _labeled(
      'Nombre de usuario',
      AuthTextField(
        controller: _userController,
        hint: 'Juanito',
        icon: Icons.alternate_email,
        inputFormatters: InputFilters.username,
        validator: Validators.username,
      ),
    );

    return AuthLayout(
      showBackBar: true,
      maxWidth: 550,
      cardPadding: EdgeInsets.all(isMobile ? 24 : 40),
      child: Form(
        key: formKey,
        autovalidateMode: autovalidateMode,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: AuthTitle(
                'Únete a Market-Tec',
                fontSize: 28,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: AuthSubtitle(
                'Crea tu cuenta y empieza a comprar hoy mismo. Si quieres vender, lo activas después desde tu perfil',
              ),
            ),
            const SizedBox(height: 24),
            Center(child: _buildFotoPicker()),
            const SizedBox(height: 24),

            _labeled(
              'Nombre completo',
              AuthTextField(
                controller: _nombreController,
                hint: 'Ej. Juanito Perez',
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
                inputFormatters: InputFilters.nombre,
                validator: Validators.nombreCompleto,
              ),
            ),
            const SizedBox(height: 16),

            if (isMobile) ...[
              controlField,
              const SizedBox(height: 16),
              userField,
            ] else
              Row(
                children: [
                  Expanded(child: controlField),
                  const SizedBox(width: 16),
                  Expanded(child: userField),
                ],
              ),
            const SizedBox(height: 16),

            _labeled(
              'Correo institucional',
              CorreoInstitucionalField(
                controller: _emailController,
                onChanged: (_) => _correoEditadoAMano = true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Se llena solo con tu número de control, puedes cambiarlo',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),

            _labeled(
              'Contraseña',
              PasswordField(
                controller: _passwordController,
                hint: 'Crea una contraseña segura',
                validator: Validators.passwordNueva,
                onFieldSubmitted: (_) => _solicitarCodigoVerificacion(),
              ),
            ),
            const SizedBox(height: 40),

            LoadingButton(
              text: 'Enviar código de verificación',
              isLoading: isLoading,
              onPressed: _solicitarCodigoVerificacion,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFotoPicker() {
    return Column(
      children: [
        GestureDetector(
          onTap: _elegirFoto,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: Colors.grey.shade100,
                backgroundImage: _foto == null ? null : MemoryImage(_foto!.bytes),
                child: _foto == null
                    ? Icon(
                        Icons.person_outline,
                        size: 40,
                        color: Colors.grey.shade400,
                      )
                    : null,
              ),
              const Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.photo_camera, size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _elegirFoto,
          child: Text(
            _foto == null
                ? 'Agregar foto o logo (opcional)'
                : 'Cambiar foto',
          ),
        ),
      ],
    );
  }

  /// Etiqueta + campo apilados.
  Widget _labeled(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [InputLabel(label), field],
    );
  }
}
