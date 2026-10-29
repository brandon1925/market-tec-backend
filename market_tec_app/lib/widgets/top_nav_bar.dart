import 'package:flutter/material.dart';

import '../admin_screen.dart';
import '../catalogo_screen.dart';
import '../core/app_theme.dart';
import '../core/notificaciones_service.dart';
import '../core/ui_helpers.dart';
import '../globals.dart';
import '../inicio_screen.dart';
import '../mapa_screen.dart';
import '../opiniones_screen.dart';
import '../vender_screen.dart';
import 'chat_pedido_sheet.dart';
import 'perfil_dialogs.dart';
import 'user_avatar.dart';

/// Una sección del menú principal.
class NavItem {
  final String label;
  final IconData icon;
  final Widget Function() pantalla;
  const NavItem(this.label, this.icon, this.pantalla);

  /// Secciones visibles según el rol del usuario.
  static List<NavItem> visibles() => [
    NavItem('Inicio', Icons.home_outlined, () => const InicioScreen()),
    NavItem('Catálogo', Icons.storefront_outlined, () => const CatalogoScreen()),
    NavItem('Mapa', Icons.map_outlined, () => const MapaScreen()),
    if (esVendedor)
      NavItem('Vender', Icons.sell_outlined, () => const VenderScreen()),
    NavItem(
      'Comentarios',
      Icons.forum_outlined,
      () => const OpinionesScreen(),
    ),
    if (currentUserRole == 'Administrador')
      NavItem(
        'Admin',
        Icons.admin_panel_settings_outlined,
        () => const AdminScreen(),
      ),
  ];
}

class TopNavBar extends StatelessWidget {
  final String activeRoute;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool isMobile;
  final VoidCallback onStateChanged;

  const TopNavBar({
    super.key,
    required this.activeRoute,
    required this.scaffoldKey,
    required this.isMobile,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      // SafeArea: el header empieza debajo de la barra de notificaciones
      // del celular (hora, batería) en lugar de quedar detrás de ella.
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 40,
            vertical: isMobile ? 10 : 14,
          ),
          child: Row(
            children: [
              _buildLogo(context),
              if (!isMobile) ...[
                const SizedBox(width: 32),
                for (final item in NavItem.visibles())
                  _buildNavLink(context, item),
              ],
              const Spacer(),
              if (!isMobile)
                Flexible(
                  child: Text(
                    currentUserName,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              const SizedBox(width: 4),
              const NotificacionesBell(),
              _buildProfileMenu(context),
              if (isMobile)
                IconButton(
                  tooltip: 'Menú',
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => scaffoldKey.currentState?.openEndDrawer(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Logo + "Market-Tec": siempre lleva al Inicio.
  Widget _buildLogo(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.irALimpio(const InicioScreen()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/icono.jpg',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 32,
                  height: 32,
                  color: Colors.white,
                  child: const Icon(
                    Icons.shopping_bag,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Market-Tec',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Mi cuenta',
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: UserAvatar(
        nombre: currentUserName,
        fotoUrl: currentUserFoto,
        radius: 17,
        backgroundColor: Colors.white,
        textColor: AppColors.primary,
      ),
      onSelected: (value) {
        if (value == 'perfil') mostrarPerfil(context);
        if (value == 'config') {
          mostrarConfiguracion(context, onChanged: onStateChanged);
        }
        if (value == 'salir') NotificacionesService.instance.cerrarSesion();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 250,
            child: Row(
              children: [
                UserAvatar(nombre: currentUserName, fotoUrl: currentUserFoto),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUserName,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        currentUserEmail,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        _menuItem('perfil', 'Mi perfil', Icons.person_outline),
        _menuItem('config', 'Configuración', Icons.settings_outlined),
        const PopupMenuDivider(),
        _menuItem('salir', 'Cerrar sesión', Icons.logout, destructivo: true),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String title,
    IconData icon, {
    bool destructivo = false,
  }) {
    final color = destructivo ? const Color(0xFFE84545) : Colors.black87;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: destructivo ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavLink(BuildContext context, NavItem item) {
    final bool isActive = item.label == activeRoute;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: InkWell(
        onTap: isActive ? null : () => context.irA(item.pantalla()),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            item.label,
            style: TextStyle(
              color: isActive ? AppColors.primary : Colors.white70,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

/// Campana con el número de avisos sin leer y la lista de los últimos.
class NotificacionesBell extends StatelessWidget {
  const NotificacionesBell({super.key});

  @override
  Widget build(BuildContext context) {
    final servicio = NotificacionesService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: servicio.noLeidas,
      builder: (context, noLeidas, _) => IconButton(
        tooltip: 'Avisos',
        onPressed: () => _abrirLista(context),
        icon: Badge(
          isLabelVisible: noLeidas > 0,
          label: Text(noLeidas > 9 ? '9+' : '$noLeidas'),
          backgroundColor: Colors.orange,
          child: const Icon(
            Icons.notifications_none_rounded,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _abrirLista(BuildContext context) {
    final servicio = NotificacionesService.instance;
    servicio.sincronizar();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: servicio.recientes,
          builder: (context, lista, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Avisos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: servicio.marcarLeidas,
                      child: const Text('Marcar todo como leído'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: lista.isEmpty
                    ? Center(
                        child: Text(
                          'No tienes avisos por ahora',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final n = lista[i];
                          final leida = n['leida'] == true;
                          final ref = n['id_referencia'];
                          return ListTile(
                            leading: Icon(
                              _icono(n['tipo']),
                              color: leida ? Colors.grey : AppColors.primary,
                            ),
                            title: Text(
                              '${n['titulo'] ?? ''}',
                              style: TextStyle(
                                fontWeight: leida
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${n['cuerpo'] ?? ''}\n${fechaRelativa(n['fecha'])}',
                            ),
                            isThreeLine: true,
                            onTap: ref is int
                                ? () {
                                    Navigator.pop(context);
                                    ChatPedidoSheet.abrir(context, idPedido: ref);
                                  }
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(servicio.marcarLeidas);
  }

  IconData _icono(dynamic tipo) => switch (tipo) {
    'chat' => Icons.chat_bubble_outline,
    'venta' => Icons.sell_outlined,
    'compra' => Icons.shopping_bag_outlined,
    _ => Icons.notifications_none,
  };
}
