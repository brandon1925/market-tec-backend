import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/ui_helpers.dart';
import 'core/validators.dart';
import 'globals.dart';
import 'widgets/widgets.dart';

/// Secciones del panel (se eligen con las pestañas de arriba).
enum _Seccion { usuarios, productos, reportes, comentarios }

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<dynamic> _usuarios = [];
  List<dynamic> _reportes = [];
  List<dynamic> _productos = [];
  List<dynamic> _comentarios = [];

  bool _isLoading = true;
  bool _guardando = false; // evita mandar dos cambios a la vez
  String _busquedaUsuario = '';
  _Seccion _seccion = _Seccion.usuarios;

  // Sección "Vendedores y productos"
  int? _idVendedor;
  List<dynamic> _productosVendedor = [];
  bool _cargandoProductos = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosAdmin();
  }

  bool _tienePermisoAdmin() {
    final rol = currentUserRole.trim().toLowerCase();
    return rol == 'administrador' || rol == 'admin';
  }

  Future<void> _cargarDatosAdmin() async {
    setState(() => _isLoading = true);
    Future<List<dynamic>> lista(String path, List<dynamic> anterior) async {
      try {
        return await ApiClient.getList(path) ?? anterior;
      } catch (e) {
        debugPrint('Error cargando $path: $e');
        return anterior;
      }
    }

    final r = await Future.wait([
      lista('/admin/usuarios', _usuarios),
      lista('/reportes', _reportes),
      lista('/productos', _productos),
      lista('/admin/comentarios-web', _comentarios),
    ]);
    _usuarios = r[0];
    _reportes = r[1];
    _productos = r[2];
    _comentarios = r[3];
    if (_idVendedor != null) await _cargarProductosVendedor(_idVendedor!);
    if (mounted) setState(() => _isLoading = false);
  }

  /// PUT genérico del panel: si responde 200 recarga y muestra el aviso.
  Future<bool> _actualizar(
    String path,
    Map<String, dynamic>? body, {
    required String mensajeOk,
    Color colorOk = Colors.green,
  }) async {
    if (_guardando) return false;
    _guardando = true;
    try {
      final res = await ApiClient.put(path, body);
      if (res.statusCode == 200) {
        await _cargarDatosAdmin();
        if (mounted) context.showSnack(mensajeOk, color: colorOk);
        return true;
      }
      if (mounted) {
        context.showError(
          ApiClient.detalle(res) ?? 'No se pudo guardar el cambio (${res.statusCode})',
        );
      }
    } catch (e) {
      if (mounted) context.showError('Error de conexión al servidor');
    } finally {
      _guardando = false;
    }
    return false;
  }

  /// Un administrador no puede quitarse el rol ni suspender su propia cuenta
  /// (se quedaría sin acceso al panel).
  bool _esMiCuenta(int userId) {
    if (userId != currentUserId) return false;
    context.showSnack(
      'No puedes cambiar el rol ni el estado de tu propia cuenta',
      color: Colors.orange,
    );
    return true;
  }

  Future<void> _cambiarRolUsuario(int userId, int nuevoRolId) async {
    if (_esMiCuenta(userId)) return;
    await _actualizar(
      '/usuarios/$userId/rol',
      {'nuevo_rol_id': nuevoRolId},
      mensajeOk: 'Rol actualizado',
    );
  }

  Future<void> _cambiarEstadoCuenta(dynamic u) async {
    final int userId = u['id_usuario'];
    if (_esMiCuenta(userId)) return;
    final estadoActual = u['estado_cuenta'] ?? 'Activa';
    final nuevoEstado = estadoActual == 'Activa' ? 'Suspendida' : 'Activa';
    if (nuevoEstado == 'Suspendida') {
      final ok = await showConfirmDialog(
        context: context,
        title: '¿Suspender a ${u['nombre_completo'] ?? 'este usuario'}?',
        message:
            'Se cerrará su sesión en todos sus dispositivos y no podrá volver a entrar hasta que lo reactives',
        confirmText: 'Suspender',
        confirmColor: Colors.red,
        icon: Icons.block,
      );
      if (!ok) return;
    }
    await _actualizar(
      '/admin/usuarios/$userId/estado',
      {'nuevo_estado': nuevoEstado},
      mensajeOk: 'Cuenta marcada como $nuevoEstado',
      colorOk: nuevoEstado == 'Activa' ? Colors.green : Colors.red,
    );
  }

  Future<void> _cambiarEstadoReporte(int idReporte, String nuevoEstado) =>
      _actualizar(
        '/admin/reportes/$idReporte/estado',
        {'nuevo_estado': nuevoEstado},
        mensajeOk: 'Reporte marcado como $nuevoEstado',
      );

  Future<void> _cambiarEstadoComentario(int id, String nuevoEstado) =>
      _actualizar(
        '/admin/comentarios-web/$id/estado',
        {'nuevo_estado': nuevoEstado},
        mensajeOk: 'Comentario marcado como $nuevoEstado',
      );

  // ===================== Productos de un vendedor =====================

  List<dynamic> get _vendedores =>
      _usuarios.where((u) => u['id_rol'] == 2).toList()
        ..sort((a, b) => '${a['nombre_completo']}'.compareTo('${b['nombre_completo']}'));

  Future<void> _cargarProductosVendedor(int id) async {
    setState(() {
      _idVendedor = id;
      _cargandoProductos = true;
    });
    try {
      final lista = await ApiClient.getList('/productos/vendedor/$id');
      if (mounted) setState(() => _productosVendedor = lista ?? []);
    } catch (_) {
      if (mounted) context.showError('No se pudieron cargar sus productos');
    } finally {
      if (mounted) setState(() => _cargandoProductos = false);
    }
  }

  Future<void> _pausarProducto(dynamic p) async {
    final pausado = p['pausado'] == true;
    if (pausado && (p['stock'] ?? 0) <= 0) {
      return context.showSnack(
        'Tiene 0 piezas, edítalo y súbele el stock para reactivarlo',
        color: Colors.orange.shade800,
      );
    }
    await _actualizar(
      '/productos/${p['id']}/pausar',
      null,
      mensajeOk: pausado ? 'Producto activo otra vez' : 'Producto en pausa',
      colorOk: pausado ? Colors.green : Colors.orange.shade800,
    );
  }

  Future<void> _editarProducto(dynamic p) async {
    await showDialog(
      context: context,
      builder: (_) => ProductoFormDialog(producto: Map<String, dynamic>.from(p)),
    );
    if (_idVendedor != null) _cargarProductosVendedor(_idVendedor!);
  }

  Future<void> _eliminarProducto(dynamic p) async {
    final ok = await showConfirmDialog(
      context: context,
      title: '¿Eliminar "${p['nombre']}"?',
      message: 'El producto desaparece del catálogo y no se puede recuperar',
      confirmText: 'Eliminar',
      confirmColor: Colors.red,
      icon: Icons.delete_outline,
    );
    if (!ok) return;
    try {
      final res = await ApiClient.delete('/productos/${p['id']}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        context.showSnack('Producto eliminado');
        _cargarDatosAdmin();
      } else {
        context.showError(ApiClient.detalle(res) ?? 'No se pudo eliminar');
      }
    } catch (_) {
      if (mounted) context.showError('Error de conexión al servidor');
    }
  }

  // ===================== Editar perfil =====================

  Future<void> _editarPerfil(dynamic u) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _EditarUsuarioDialog(usuario: Map<String, dynamic>.from(u)),
    );
    if (guardado == true) {
      await _cargarDatosAdmin();
      if (mounted) context.showSuccess('Perfil actualizado');
    }
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeRoute: 'Admin',
      builder: (context, isMobile) {
        if (!_tienePermisoAdmin()) return _buildAccesoDenegado();
        if (_isLoading && _usuarios.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: _cargarDatosAdmin,
          child: PageScroll(
            isMobile: isMobile,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(isMobile),
                const SizedBox(height: 24),
                _buildTopStats(isMobile),
                const SizedBox(height: 24),
                _buildPestanas(),
                const SizedBox(height: 20),
                switch (_seccion) {
                  _Seccion.usuarios => _buildUsuariosSection(isMobile),
                  _Seccion.productos => _buildProductosSection(isMobile),
                  _Seccion.reportes => _buildReportesSection(isMobile),
                  _Seccion.comentarios => _buildComentariosSection(isMobile),
                },
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccesoDenegado() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gpp_bad_rounded, size: 80, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Acceso denegado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Esta sección es solo para administradores',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SectionHeader(
            eyebrow: 'CENTRO DE CONTROL ITZ',
            title: 'Panel de administración',
            titleSize: isMobile ? 26 : 36,
            subtitle: 'Usuarios, productos, reportes y comentarios de la comunidad',
            subtitleGap: 4,
            subtitleStyle: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
        ),
        IconButton(
          onPressed: _isLoading ? null : _cargarDatosAdmin,
          tooltip: 'Recargar datos',
          icon: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.refresh, color: AppColors.primary, size: 28),
        ),
      ],
    );
  }

  Widget _buildTopStats(bool isMobile) {
    final reportesPendientes =
        _reportes.where((r) => r['estado'] == 'Pendiente').length;

    return StatCardsRow(
      isMobile: isMobile,
      trailingGap: true,
      cards: [
        StatCard.accent(
          icon: Icons.people_alt_outlined,
          title: 'USUARIOS',
          value: '${_usuarios.length}',
          accent: AppColors.primary,
        ),
        StatCard.accent(
          icon: Icons.storefront_outlined,
          title: 'VENDEDORES',
          value: '${_vendedores.length}',
          accent: Colors.green.shade700,
        ),
        StatCard.accent(
          icon: Icons.inventory_2_outlined,
          title: 'PRODUCTOS',
          value: '${_productos.length}',
          accent: Colors.blue.shade700,
        ),
        StatCard.accent(
          icon: Icons.report_problem_outlined,
          title: 'REPORTES PENDIENTES',
          value: '$reportesPendientes',
          accent: Colors.red.shade700,
        ),
      ],
    );
  }

  Widget _buildPestanas() {
    final nuevos = _comentarios.where((c) => (c['estado'] ?? 'Recibido') == 'Recibido').length;
    final pendientes = _reportes.where((r) => r['estado'] == 'Pendiente').length;
    final opciones = [
      (_Seccion.usuarios, Icons.people_alt_outlined, 'Usuarios', 0),
      (_Seccion.productos, Icons.storefront_outlined, 'Vendedores y productos', 0),
      (_Seccion.reportes, Icons.report_outlined, 'Reportes', pendientes),
      (_Seccion.comentarios, Icons.forum_outlined, 'Comentarios', nuevos),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (s, icono, texto, contador) in opciones)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                selected: _seccion == s,
                selectedColor: AppColors.primary,
                avatar: Icon(
                  icono,
                  size: 18,
                  color: _seccion == s ? Colors.white : AppColors.primary,
                ),
                label: Text(contador > 0 ? '$texto ($contador)' : texto),
                labelStyle: TextStyle(
                  color: _seccion == s ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => setState(() => _seccion = s),
              ),
            ),
        ],
      ),
    );
  }

  // ===================== Usuarios =====================

  Widget _buildUsuariosSection(bool isMobile) {
    final q = _busquedaUsuario.toLowerCase();
    final filtrados = _usuarios.where((u) {
      final texto = [
        u['nombre_completo'],
        u['correo'],
        u['numero_control'],
        u['username'],
      ].map((e) => '${e ?? ''}'.toLowerCase()).join(' ');
      return texto.contains(q);
    }).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                const Text(
                  'Usuarios de la plataforma',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 280,
                  child: TextField(
                    inputFormatters: [LengthLimitingTextInputFormatter(50)],
                    onChanged: (val) => setState(() => _busquedaUsuario = val.trim()),
                    decoration: AppStyles.outlinedInput(
                      hintText: 'Buscar por nombre, correo o control',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (filtrados.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No hay usuarios con esa búsqueda',
              ),
            )
          else if (isMobile)
            ...filtrados.map(_buildUsuarioTile)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: AppStyles.tableHeading,
                dataRowMinHeight: 60,
                dataRowMaxHeight: 68,
                columns: const [
                  DataColumn(label: Text('ESTUDIANTE')),
                  DataColumn(label: Text('N° CONTROL')),
                  DataColumn(label: Text('ROL')),
                  DataColumn(label: Text('ESTADO')),
                  DataColumn(label: Text('ACCIONES')),
                ],
                rows: filtrados.map(_buildUsuarioRow).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rolSelector(dynamic u) {
    final int idRol = u['id_rol'] ?? 1;
    return DropdownButton<int>(
      value: [1, 2, 3].contains(idRol) ? idRol : 1,
      underline: const SizedBox(),
      items: const [
        DropdownMenuItem(value: 1, child: Text('Cliente')),
        DropdownMenuItem(value: 2, child: Text('Vendedor')),
        DropdownMenuItem(value: 3, child: Text('Administrador')),
      ],
      onChanged: (nuevoRol) {
        if (nuevoRol != null && nuevoRol != idRol) {
          _cambiarRolUsuario(u['id_usuario'], nuevoRol);
        }
      },
    );
  }

  Widget _estadoBadge(String estado) {
    final activa = estado == 'Activa';
    final color = activa ? Colors.green : Colors.red;
    return StatusBadge(
      text: estado,
      textColor: color.shade700,
      backgroundColor: color.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      radius: 10,
    );
  }

  Widget _accionesUsuario(dynamic u) {
    final activa = (u['estado_cuenta'] ?? 'Activa') == 'Activa';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Editar perfil',
          icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
          onPressed: () => _editarPerfil(u),
        ),
        IconButton(
          tooltip: activa ? 'Suspender cuenta' : 'Reactivar cuenta',
          icon: Icon(
            activa ? Icons.block : Icons.check_circle_outline,
            color: activa ? Colors.red : Colors.green,
          ),
          onPressed: () => _cambiarEstadoCuenta(u),
        ),
      ],
    );
  }

  DataRow _buildUsuarioRow(dynamic u) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              UserAvatar(
                nombre: '${u['nombre_completo'] ?? '?'}',
                fotoUrl: u['foto_url'],
                radius: 18,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    u['nombre_completo'] ?? 'Sin nombre',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    u['correo'] ?? '',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        DataCell(Text('${u['numero_control'] ?? ''}')),
        DataCell(_rolSelector(u)),
        DataCell(_estadoBadge(u['estado_cuenta'] ?? 'Activa')),
        DataCell(_accionesUsuario(u)),
      ],
    );
  }

  Widget _buildUsuarioTile(dynamic u) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                nombre: '${u['nombre_completo'] ?? '?'}',
                fotoUrl: u['foto_url'],
                radius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u['nombre_completo'] ?? 'Sin nombre',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${u['numero_control'] ?? ''} · ${u['correo'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _estadoBadge(u['estado_cuenta'] ?? 'Activa'),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 52),
              _rolSelector(u),
              const Spacer(),
              _accionesUsuario(u),
            ],
          ),
        ],
      ),
    );
  }

  // ===================== Vendedores y productos =====================

  Widget _buildProductosSection(bool isMobile) {
    final vendedores = _vendedores;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Productos por vendedor',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              InfoHint(
                'Elige un vendedor para ver todo lo que publica. Puedes pausar, '
                'editar o eliminar sus productos si no cumplen las reglas del ITZ',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (vendedores.isEmpty)
            const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Aún no hay vendedores',
            )
          else
            DropdownButtonFormField<int>(
              value: vendedores.any((v) => v['id_usuario'] == _idVendedor)
                  ? _idVendedor
                  : null,
              isExpanded: true,
              decoration: AppStyles.outlinedInput(
                labelText: 'Vendedor',
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              items: [
                for (final v in vendedores)
                  DropdownMenuItem<int>(
                    value: v['id_usuario'],
                    child: Text(
                      '${v['nombre_completo'] ?? 'Vendedor'} · ${v['numero_control'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) _cargarProductosVendedor(id);
              },
            ),
          const SizedBox(height: 16),
          if (_idVendedor == null)
            Text(
              'Selecciona un vendedor para ver sus productos',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            )
          else if (_cargandoProductos)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_productosVendedor.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Este vendedor no tiene productos publicados',
            )
          else
            ..._productosVendedor.map(_buildProductoItem),
        ],
      ),
    );
  }

  Widget _buildProductoItem(dynamic p) {
    final pausado = p['pausado'] == true || (p['stock'] ?? 0) <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ProductImage(url: p['imagen_url'], width: 56, height: 56, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['nombre'] ?? 'Producto'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pausado ? Colors.grey : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${p['precio'] ?? 0} · ${p['stock'] ?? 0} piezas · '
                  '${pausado ? 'En pausa' : 'A la venta'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: pausado ? Colors.orange.shade800 : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: p['pausado'] == true ? 'Reactivar' : 'Pausar',
            icon: Icon(
              p['pausado'] == true ? Icons.play_arrow : Icons.pause,
              color: p['pausado'] == true ? Colors.green : Colors.orange,
            ),
            onPressed: () => _pausarProducto(p),
          ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
            onPressed: () => _editarProducto(p),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _eliminarProducto(p),
          ),
        ],
      ),
    );
  }

  // ===================== Reportes =====================

  Widget _buildReportesSection(bool isMobile) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reportes a vendedores',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Llegan desde la sección Comentarios de la página',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_reportes.isEmpty)
            EmptyState(
              icon: Icons.verified_user_outlined,
              iconSize: 52,
              iconColor: Colors.green.shade300,
              title: 'Sin reportes',
              subtitle: 'Todo está en orden dentro del campus',
              subtitleGap: 0,
            )
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final r in _reportes)
                  SizedBox(
                    width: isMobile ? double.infinity : 420,
                    child: _buildReporteItem(r),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildReporteItem(dynamic rep) {
    final estado = '${rep['estado'] ?? 'Pendiente'}';
    final resuelto = estado == 'Resuelto';
    final color = resuelto ? Colors.green : Colors.red;
    final vendedor = rep['vendedor'] ?? rep['vendedor_nombre'];
    final producto = rep['producto'];

    return AppCard(
      padding: const EdgeInsets.all(16),
      radius: 16,
      color: AppColors.background,
      borderColor: color.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusBadge(
                text: estado,
                textColor: color.shade700,
                backgroundColor: color.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                radius: 8,
                fontSize: 11,
              ),
              Text(
                formatFecha(rep['fecha'], conHora: true),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            rep['motivo'] ?? 'Reporte',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              children: [
                const TextSpan(text: 'Vendedor: '),
                TextSpan(
                  text: '${vendedor ?? 'Sin dato'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (producto != null) ...[
                  const TextSpan(text: '\nProducto: '),
                  TextSpan(
                    text: '$producto',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
                TextSpan(text: '\nReportado por: ${rep['reportante'] ?? 'Sin dato'}'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rep['descripcion'] ?? '',
            style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!resuelto)
                ElevatedButton.icon(
                  onPressed: () => _cambiarEstadoReporte(rep['id_reporte'], 'Resuelto'),
                  icon: const Icon(Icons.check, size: 16, color: Colors.white),
                  label: const Text(
                    'Marcar como resuelto',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              if (rep['id_vendedor'] != null)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _seccion = _Seccion.productos);
                    _cargarProductosVendedor(rep['id_vendedor']);
                  },
                  icon: const Icon(Icons.storefront_outlined, size: 16),
                  label: const Text('Ver sus productos', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ===================== Comentarios de la web =====================

  Widget _buildComentariosSection(bool isMobile) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Comentarios sobre la página',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              InfoHint(
                'Recibido: nadie lo ha revisado. Atendido: ya se corrigió o se tomó en cuenta',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_comentarios.isEmpty)
            const EmptyState(
              icon: Icons.forum_outlined,
              title: 'Todavía no hay comentarios',
            )
          else
            for (final c in _comentarios) _buildComentarioItem(c),
        ],
      ),
    );
  }

  Widget _buildComentarioItem(dynamic c) {
    final estado = '${c['estado'] ?? 'Recibido'}';
    final atendido = estado == 'Atendido';
    final tipo = '${c['tipo'] ?? 'Comentario'}';
    final cal = c['calificacion'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tipo == 'Error'
                    ? Icons.bug_report_outlined
                    : tipo == 'Sugerencia'
                    ? Icons.lightbulb_outline
                    : Icons.chat_bubble_outline,
                size: 18,
                color: tipo == 'Error' ? Colors.red : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(tipo, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (cal != null) ...[
                const SizedBox(width: 8),
                StarRating(rating: (cal as num).round(), size: 13),
              ],
              const Spacer(),
              StatusBadge(
                text: estado,
                textColor: atendido ? Colors.green.shade700 : Colors.blueGrey.shade700,
                backgroundColor: atendido ? Colors.green.shade50 : Colors.blueGrey.shade50,
                fontSize: 11,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${c['mensaje'] ?? ''}'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${c['usuario'] ?? 'Usuario'} · ${formatFecha(c['fecha'], conHora: true)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
              TextButton(
                onPressed: () => _cambiarEstadoComentario(
                  c['id'],
                  atendido ? 'Recibido' : 'Atendido',
                ),
                child: Text(atendido ? 'Marcar como pendiente' : 'Marcar como atendido'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Diálogo para que el administrador corrija los datos de cualquier perfil.
class _EditarUsuarioDialog extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const _EditarUsuarioDialog({required this.usuario});

  @override
  State<_EditarUsuarioDialog> createState() => _EditarUsuarioDialogState();
}

class _EditarUsuarioDialogState extends State<_EditarUsuarioDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.usuario['nombre_completo'] ?? '');
  late final _username = TextEditingController(text: widget.usuario['username'] ?? '');
  late final _control = TextEditingController(text: '${widget.usuario['numero_control'] ?? ''}');
  late final _correo = TextEditingController(text: widget.usuario['correo'] ?? '');
  final _redes = RedesControllers();
  bool _cargando = true;
  bool _guardando = false;
  bool _quitarFoto = false;
  String? _fotoUrl;

  int get _id => widget.usuario['id_usuario'];

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _username.dispose();
    _control.dispose();
    _correo.dispose();
    _redes.dispose();
    super.dispose();
  }

  /// Trae username, foto y redes, que la lista de usuarios no incluye.
  Future<void> _cargarPerfil() async {
    try {
      final p = await ApiClient.getMap('/usuarios/$_id/perfil');
      if (p != null && mounted) {
        _username.text = p['username'] ?? _username.text;
        _fotoUrl = p['foto_url'];
        final redes = Map<String, dynamic>.from(p['redes'] ?? {});
        redes.forEach((k, v) => _redes.campos[k]?.text = '${v ?? ''}');
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final res = await ApiClient.put('/admin/usuarios/$_id', {
        'id_admin': currentUserId,
        'nombre_completo': _nombre.text.trim(),
        'username': _username.text.trim(),
        'numero_control': _control.text.trim(),
        'correo_institucional': _correo.text.trim().toLowerCase(),
        if (_quitarFoto) 'foto_url': '',
        ..._redes.valores(),
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        context.showError(ApiClient.detalle(res) ?? 'No se pudo guardar');
      }
    } catch (_) {
      if (mounted) context.showError('Error de conexión al servidor');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppStyles.dialogShape(),
      title: const Text('Editar perfil', textAlign: TextAlign.center),
      content: SizedBox(
        width: 460,
        child: _cargando
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        nombre: _nombre.text.isEmpty ? '?' : _nombre.text,
                        fotoUrl: _quitarFoto ? null : _fotoUrl,
                        radius: 36,
                      ),
                      if ((_fotoUrl ?? '').isNotEmpty)
                        TextButton.icon(
                          onPressed: () => setState(() => _quitarFoto = !_quitarFoto),
                          icon: Icon(_quitarFoto ? Icons.undo : Icons.hide_image_outlined),
                          label: Text(_quitarFoto ? 'Conservar foto' : 'Quitar foto'),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nombre,
                        validator: Validators.nombreCompleto,
                        decoration: AppStyles.outlinedInput(labelText: 'Nombre completo'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        validator: Validators.username,
                        decoration: AppStyles.outlinedInput(labelText: 'Nombre de usuario'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _control,
                        validator: Validators.numeroControl,
                        decoration: AppStyles.outlinedInput(labelText: 'Número de control'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _correo,
                        validator: Validators.correoInstitucional,
                        keyboardType: TextInputType.emailAddress,
                        decoration: AppStyles.outlinedInput(labelText: 'Correo institucional'),
                      ),
                      const SizedBox(height: 16),
                      RedesSocialesCampos(controllers: _redes),
                    ],
                  ),
                ),
              ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogCancelButton(onPressed: () => Navigator.pop(context)),
        ElevatedButton(
          onPressed: _guardando || _cargando ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: _guardando ? const ButtonSpinner() : const Text('Guardar cambios'),
        ),
      ],
    );
  }
}
