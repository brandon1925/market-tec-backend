import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/notificaciones_service.dart';
import '../core/ui_helpers.dart';
import '../globals.dart';
import 'perfil_dialogs.dart';
import 'top_nav_bar.dart';
import 'user_avatar.dart';

/// Menú lateral de la versión móvil.
class SideDrawer extends StatelessWidget {
  final String activeRoute;
  final VoidCallback? onStateChanged;
  const SideDrawer({super.key, required this.activeRoute, this.onStateChanged});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primary,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  children: [
                    UserAvatar(
                      nombre: currentUserName,
                      fotoUrl: currentUserFoto,
                      radius: 36,
                      backgroundColor: Colors.white,
                      textColor: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      currentUserName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      currentUserRole,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final item in NavItem.visibles())
                  _tile(
                    context,
                    icon: item.icon,
                    label: item.label,
                    activo: item.label == activeRoute,
                    onTap: () {
                      Navigator.pop(context);
                      if (item.label != activeRoute) context.irA(item.pantalla());
                    },
                  ),
                const Divider(),
                _tile(
                  context,
                  icon: Icons.person_outline,
                  label: 'Mi perfil',
                  onTap: () {
                    Navigator.pop(context);
                    mostrarPerfil(context);
                  },
                ),
                _tile(
                  context,
                  icon: Icons.settings_outlined,
                  label: 'Configuración',
                  onTap: () {
                    Navigator.pop(context);
                    mostrarConfiguracion(
                      context,
                      onChanged: onStateChanged ?? () {},
                    );
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: _tile(
              context,
              icon: Icons.logout,
              label: 'Cerrar sesión',
              color: const Color(0xFFE84545),
              onTap: () => NotificacionesService.instance.cerrarSesion(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool activo = false,
    Color? color,
  }) {
    final c = color ?? (activo ? AppColors.primary : Colors.black87);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(icon, color: c),
        title: Text(
          label,
          style: TextStyle(
            color: c,
            fontWeight: activo ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: activo,
        selectedTileColor: AppColors.primary.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}
