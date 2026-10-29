import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../core/validators.dart';
import '../globals.dart';
import 'auth_widgets.dart';
import 'custom_buttons.dart';
import 'redes_sociales.dart';
import 'user_avatar.dart';

/// Vuelve a pedir el perfil al backend y actualiza los globales.
Future<void> refrescarPerfil() async {
  if (currentUserId == 0) return;
  try {
    final p = await ApiClient.getMap('/usuarios/$currentUserId/perfil');
    if (p != null) cargarUsuario(p);
  } catch (_) {}
}

// ==========================================
// MI PERFIL
// ==========================================
Future<void> mostrarPerfil(BuildContext context) async {
  final perfilFuture = ApiClient.getMap('/usuarios/$currentUserId/perfil')
      .catchError((_) => null);

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: AppStyles.dialogShape(24),
      content: SizedBox(
        width: 400,
        child: FutureBuilder<Map<String, dynamic>?>(
          future: perfilFuture,
          builder: (context, snap) {
            final stats = Map<String, dynamic>.from(snap.data?['stats'] ?? {});
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(
                    nombre: currentUserName,
                    fotoUrl: currentUserFoto,
                    radius: 44,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    currentUserName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    '@$currentUserUsername',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _dato('No. de control', currentUserControl),
                  _dato('Correo', currentUserEmail),
                  _dato('Cuenta', currentUserStatus, color: Colors.green),
                  _dato('Rol', currentUserRole),
                  if (currentUserRedes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    RedesSocialesBotones(redes: currentUserRedes, compacto: true),
                  ],
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _stat('Compras', stats['compras'], Icons.shopping_bag_outlined),
                      _stat('Favoritos', stats['favoritos'], Icons.favorite_border),
                      _stat('Reseñas', stats['resenas'], Icons.star_border),
                      _stat('Reportes', stats['reportes'], Icons.flag_outlined),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SecondaryButton(
                    text: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

Widget _dato(String label, String value, {Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black87,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

Widget _stat(String title, dynamic value, IconData icon) {
  return Column(
    children: [
      Icon(icon, color: Colors.grey.shade600, size: 22),
      const SizedBox(height: 6),
      Text(
        '${value ?? 0}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
    ],
  );
}

// ==========================================
// CONFIGURACIÓN DE CUENTA
// ==========================================
Future<void> mostrarConfiguracion(
  BuildContext context, {
  required VoidCallback onChanged,
}) {
  return showDialog(
    context: context,
    builder: (_) => _ConfiguracionDialog(onChanged: onChanged),
  );
}

class _ConfiguracionDialog extends StatefulWidget {
  final VoidCallback onChanged;
  const _ConfiguracionDialog({required this.onChanged});

  @override
  State<_ConfiguracionDialog> createState() => _ConfiguracionDialogState();
}

class _ConfiguracionDialogState extends State<_ConfiguracionDialog>
    with FormSubmitMixin {
  late final TextEditingController _nombre = TextEditingController(
    text: currentUserName,
  );
  late final TextEditingController _usuario = TextEditingController(
    text: currentUserUsername,
  );
  final TextEditingController _passActual = TextEditingController();
  final TextEditingController _passNueva = TextEditingController();
  final TextEditingController _passConfirmar = TextEditingController();
  late final RedesControllers _redes = RedesControllers(currentUserRedes);

  String? _fotoUrl = currentUserFoto;
  ImagenElegida? _fotoNueva;
  bool _cambiarPassword = false;
  bool _convirtiendo = false;

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _passActual.dispose();
    _passNueva.dispose();
    _passConfirmar.dispose();
    _redes.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    final foto = await elegirFoto(
      context,
      titulo: esVendedor ? 'Foto de perfil o logo' : 'Foto de perfil',
      maxLado: 600,
    );
    if (foto != null) setState(() => _fotoNueva = foto);
  }

  Future<void> _guardar() async {
    if (!validarFormulario()) return;
    await enviar(() async {
      // 1. Contraseña: se valida la actual con /login y se cambia con el
      //    mismo endpoint de "Recuperar contraseña".
      if (_cambiarPassword) {
        final login = await ApiClient.post('/login', {
          "correo_institucional": currentUserEmail,
          "password": _passActual.text.trim(),
        });
        if (login.statusCode != 200) {
          if (mounted) context.showError('Tu contraseña actual no es correcta');
          return;
        }
        final cambio = await ApiClient.post('/recuperar-password/restablecer', {
          "correo": currentUserEmail,
          "nueva_password": _passNueva.text.trim(),
        });
        if (cambio.statusCode != 200) {
          if (mounted) context.showError('No se pudo cambiar la contraseña');
          return;
        }
      }

      // 2. Foto nueva
      if (_fotoNueva != null) {
        final url = await ApiClient.uploadImage(
          _fotoNueva!.bytes,
          _fotoNueva!.nombre,
        );
        if (!Validators.esUrlImagen(url)) {
          throw const FormatException('No se pudo subir la foto');
        }
        _fotoUrl = url;
      }

      // 3. Datos del perfil
      final res = await ApiClient.put('/usuarios/$currentUserId/perfil', {
        "nombre_completo": _nombre.text.trim(),
        "username": _usuario.text.trim(),
        "foto_url": _fotoUrl ?? '',
        if (esVendedor) ..._redes.valores(),
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        cargarUsuario(ApiClient.decode(res));
        widget.onChanged();
        Navigator.pop(context);
        context.showSuccess(
          _cambiarPassword
              ? 'Perfil y contraseña actualizados'
              : 'Perfil actualizado',
        );
      } else {
        context.showError(
          ApiClient.detalle(res) ?? 'No se pudieron guardar los cambios',
        );
      }
    }, onError: (e) => context.showError(
      e is FormatException ? e.message : 'Sin conexión con el servidor',
    ));
  }

  Future<void> _convertirmeEnVendedor() async {
    final ok = await showConfirmDialog(
      context: context,
      icon: Icons.storefront,
      title: '¿Quieres empezar a vender?',
      message:
          'Tu perfil aparecerá en el catálogo de vendedores y podrás publicar productos. Este cambio no se puede deshacer',
      confirmText: 'Sí, quiero vender',
      confirmColor: AppColors.primary,
    );
    if (!ok || !mounted) return;
    setState(() => _convirtiendo = true);
    try {
      final res = await ApiClient.put('/usuarios/$currentUserId/rol', {
        "nuevo_rol_id": 2,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        currentUserRole = 'Vendedor';
        widget.onChanged();
        setState(() {});
        context.showSuccess('¡Listo! Ya eres vendedor en Market-Tec');
      } else {
        context.showError('No se pudo activar tu cuenta de vendedor');
      }
    } catch (_) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      if (mounted) setState(() => _convirtiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppStyles.dialogShape(24),
      title: const Text(
        'Configuración de cuenta',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            autovalidateMode: autovalidateMode,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFoto(),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: InputFilters.nombre,
                  validator: Validators.nombreCompleto,
                  decoration: _deco('Nombre completo', Icons.person_outline),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _usuario,
                  inputFormatters: InputFilters.username,
                  validator: Validators.username,
                  decoration: _deco('Nombre de usuario', Icons.alternate_email),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: currentUserControl,
                  enabled: false,
                  decoration: _deco('Número de control', Icons.badge_outlined),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _cambiarPassword,
                  onChanged: (v) => setState(() => _cambiarPassword = v),
                  title: const Text(
                    'Cambiar contraseña',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_cambiarPassword) ...[
                  PasswordField(
                    controller: _passActual,
                    hint: 'Contraseña actual',
                    validator: Validators.passwordLogin,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _passNueva,
                    hint: 'Contraseña nueva',
                    validator: Validators.passwordNueva,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _passConfirmar,
                    hint: 'Repite la contraseña nueva',
                    validator: (v) =>
                        Validators.confirmarPassword(v, _passNueva.text),
                  ),
                  const SizedBox(height: 8),
                ],
                if (esVendedor) ...[
                  const Divider(height: 32),
                  const Text(
                    'Tus redes para que te contacten',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Aparecen en tu catálogo y en el chat de cada venta',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  RedesSocialesCampos(controllers: _redes),
                ],
                const SizedBox(height: 8),
                _buildRolVendedor(),
              ],
            ),
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SecondaryButton(
          text: 'Cancelar',
          onPressed: () => Navigator.pop(context),
        ),
        PrimaryButton(
          text: isLoading ? 'Guardando' : 'Guardar cambios',
          onPressed: isLoading ? null : _guardar,
        ),
      ],
    );
  }

  Widget _buildFoto() {
    final Widget avatar = _fotoNueva != null
        ? CircleAvatar(
            radius: 46,
            backgroundImage: MemoryImage(_fotoNueva!.bytes),
          )
        : UserAvatar(nombre: currentUserName, fotoUrl: _fotoUrl, radius: 46);
    return Column(
      children: [
        GestureDetector(
          onTap: _elegirFoto,
          child: Stack(
            children: [
              avatar,
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary,
                  child: const Icon(
                    Icons.photo_camera,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _elegirFoto,
          child: Text(
            esVendedor ? 'Cambiar foto o logo' : 'Cambiar foto',
          ),
        ),
        if (_fotoUrl != null || _fotoNueva != null)
          TextButton(
            onPressed: () => setState(() {
              _fotoUrl = null;
              _fotoNueva = null;
            }),
            child: const Text(
              'Quitar foto',
              style: TextStyle(color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildRolVendedor() {
    if (currentUserRole != 'Cliente') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tu cuenta ya puede vender en Market-Tec',
                style: TextStyle(color: Colors.green.shade800, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            '¿Tienes algo que vender?',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Activa tu tienda y empieza a vender dentro del campus',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              text: _convirtiendo ? 'Activando' : 'Convertirme en vendedor',
              icon: Icons.storefront,
              onPressed: _convirtiendo ? null : _convertirmeEnVendedor,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
