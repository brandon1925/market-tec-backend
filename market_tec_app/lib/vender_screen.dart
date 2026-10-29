import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/pedido_estado.dart';
import 'core/ui_helpers.dart';
import 'core/validators.dart';
import 'globals.dart';
import 'inicio_screen.dart';
import 'widgets/vendedor_widgets.dart';
import 'widgets/widgets.dart';

class VenderScreen extends StatefulWidget {
  const VenderScreen({super.key});

  @override
  State<VenderScreen> createState() => _VenderScreenState();
}

class _VenderScreenState extends State<VenderScreen> {
  List<dynamic> _misProductos = [];
  List<dynamic> _pedidosPendientes = [];
  List<dynamic> _historialPedidos = [];
  List<dynamic> _todosLosHorarios = [];

  bool _isLoading = true;
  bool _cargandoHistorial = false;
  String _filtroInventario = '';
  int _diaSeleccionado = _diaInicial();

  // Filtros del historial
  String _filtroHistorial = 'Todos';
  DateTimeRange? _rangoHistorial;

  double _totalGanado = 0.0;
  int _unidadesVendidas = 0;

  /// Pedidos con una respuesta en curso (evita confirmar/rechazar dos veces).
  final Set<int> _pedidosEnProceso = {};

  late final RedesControllers _redes = RedesControllers(currentUserRedes);
  final _redesFormKey = GlobalKey<FormState>();
  bool _guardandoRedes = false;

  /// Abre en el día de hoy (o lunes si es fin de semana).
  static int _diaInicial() {
    final hoy = DateTime.now().weekday;
    return hoy <= 5 ? hoy : 1;
  }

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _redes.dispose();
    super.dispose();
  }

  // ==========================================
  // DATOS
  // ==========================================
  Future<void> _cargarTodo({bool mostrarCarga = true}) async {
    if (mostrarCarga) setState(() => _isLoading = true);
    try {
      final r = await Future.wait([
        ApiClient.getList('/productos/vendedor/$currentUserId'),
        _cargarHorarios(),
        ApiClient.getList('/pedidos/vendedor/$currentUserId'),
      ]);
      if (r[0] != null) _misProductos = r[0]!;
      if (r[1] != null) _todosLosHorarios = r[1]!;
      if (r[2] != null) _pedidosPendientes = r[2]!;
      await _cargarHistorial(soloDatos: true);
    } catch (e) {
      debugPrint("Error de red: $e");
      if (mounted) context.showError('No se pudo actualizar tu panel');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Horarios con modalidad (endpoint nuevo) o los de antes.
  Future<List<dynamic>?> _cargarHorarios() async {
    final v2 = await ApiClient.getList('/v2/horarios/$currentUserId');
    return v2 ?? await ApiClient.getList('/horarios/$currentUserId');
  }

  Future<void> _cargarHistorial({bool soloDatos = false}) async {
    if (!soloDatos) setState(() => _cargandoHistorial = true);
    try {
      final estados = PedidoEstadoStyle.filtros[_filtroHistorial]!;
      final params = <String, String>{
        if (estados.isNotEmpty) 'estados': estados.join(','),
        if (_rangoHistorial != null)
          'desde': _rangoHistorial!.start.toIso8601String().substring(0, 10),
        if (_rangoHistorial != null)
          'hasta': _rangoHistorial!.end.toIso8601String().substring(0, 10),
      };
      final q = Uri(queryParameters: params).query;
      var historial = await ApiClient.getList(
        '/v2/ventas/$currentUserId${q.isEmpty ? '' : '?$q'}',
      );
      historial ??= await ApiClient.getList(
        '/pedidos/vendedor/$currentUserId/historial',
      );
      if (historial == null) return;

      // Respaldo por si el servidor no aplicó los filtros.
      _historialPedidos = historial.where((p) {
        if (estados.isNotEmpty && !estados.contains(p['estado'])) return false;
        final f = leerFecha(p['fecha']);
        if (_rangoHistorial != null && f != null) {
          final fin = _rangoHistorial!.end.add(const Duration(days: 1));
          if (f.isBefore(_rangoHistorial!.start) || !f.isBefore(fin)) {
            return false;
          }
        }
        return true;
      }).toList();

      if (_filtroHistorial == 'Todos' && _rangoHistorial == null) {
        final vendidos = historial.where(
          (p) => p['estado'] == 'Confirmado' || p['estado'] == 'Entregado',
        );
        _totalGanado = vendidos.fold(
          0.0,
          (t, p) => t + ((p['total'] ?? 0) as num).toDouble(),
        );
        _unidadesVendidas = vendidos.fold(
          0,
          (u, p) => u + ((p['cantidad'] ?? 0) as num).toInt(),
        );
      }
    } finally {
      if (mounted && !soloDatos) setState(() => _cargandoHistorial = false);
    }
  }

  // ==========================================
  // PEDIDOS
  // ==========================================
  Future<void> _confirmarPedido(int idPedido) async {
    if (!_pedidosEnProceso.add(idPedido)) return;
    setState(() {});
    try {
      final response = await ApiClient.put('/pedidos/$idPedido/estado', {
        "nuevo_estado": "Confirmado",
      });
      if (!mounted) return;
      if (response.statusCode == 200) {
        await _cargarTodo(mostrarCarga: false);
        if (mounted) {
          context.showSnack(
            '¡Venta aceptada! Usa el chat para acordar la entrega',
            color: Colors.green.shade700,
            actionLabel: 'Abrir chat',
            onAction: () => ChatPedidoSheet.abrir(context, idPedido: idPedido),
          );
        }
      } else {
        context.showError('No se pudo confirmar el pedido');
      }
    } catch (e) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      _pedidosEnProceso.remove(idPedido);
      if (mounted) setState(() {});
    }
  }

  /// Rechazo con motivo: el comprador lo ve en "Mis compras" y le llega aviso.
  Future<void> _rechazarPedido(dynamic pedido) async {
    final int idPedido = pedido['id_pedido'];
    final motivo = await _pedirMotivoRechazo(pedido);
    if (motivo == null || !mounted) return;
    if (!_pedidosEnProceso.add(idPedido)) return;
    setState(() {});
    try {
      // 1. Se guarda el motivo (endpoint nuevo). 2. Se rechaza como antes.
      await ApiClient.put('/pedidos/$idPedido/motivo', {"motivo": motivo});
      final response = await ApiClient.put('/pedidos/$idPedido/estado', {
        "nuevo_estado": "Rechazado_Agotado",
      });
      if (!mounted) return;
      if (response.statusCode == 200) {
        await _cargarTodo(mostrarCarga: false);
        if (mounted) {
          context.showSnack(
            'Pedido rechazado, le avisamos al comprador',
            color: Colors.orange.shade800,
          );
        }
      } else {
        context.showError('No se pudo rechazar el pedido');
      }
    } catch (e) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      _pedidosEnProceso.remove(idPedido);
      if (mounted) setState(() {});
    }
  }

  Future<String?> _pedirMotivoRechazo(dynamic pedido) {
    String? elegido;
    final otroCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final esOtro = elegido == 'Otro';
          final motivoFinal = esOtro ? otroCtrl.text.trim() : elegido;
          return AlertDialog(
            shape: AppStyles.dialogShape(),
            icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 36),
            title: const Text(
              '¿Por qué rechazas el pedido?',
              textAlign: TextAlign.center,
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${pedido['cliente_nombre'] ?? 'El comprador'} verá este motivo',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final m in [...AppConstants.motivosRechazo, 'Otro'])
                          ChoiceChip(
                            label: Text(m),
                            selected: elegido == m,
                            showCheckmark: false,
                            selectedColor: Colors.red.shade50,
                            side: BorderSide(
                              color: elegido == m
                                  ? Colors.red.shade300
                                  : Colors.grey.shade300,
                            ),
                            labelStyle: TextStyle(
                              color: elegido == m
                                  ? Colors.red.shade700
                                  : Colors.black87,
                              fontWeight: elegido == m
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (_) =>
                                setStateDialog(() => elegido = m),
                          ),
                      ],
                    ),
                    if (esOtro) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: otroCtrl,
                        autofocus: true,
                        maxLength: 80,
                        onChanged: (_) => setStateDialog(() {}),
                        decoration: InputDecoration(
                          hintText: 'Escribe el motivo, corto',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              DialogCancelButton(onPressed: () => Navigator.pop(context)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: motivoFinal == null || motivoFinal.length < 3
                    ? null
                    : () => Navigator.pop(context, motivoFinal),
                child: const Text('Rechazar pedido'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(otroCtrl.dispose);
  }

  // ==========================================
  // PRODUCTOS
  // ==========================================
  Future<void> _eliminarProducto(int idProducto) async {
    final bool confirm = await showConfirmDialog(
      context: context,
      icon: Icons.delete_outline,
      title: '¿Eliminar este producto?',
      message: 'Desaparecerá del catálogo y no se puede recuperar',
      confirmText: 'Eliminar',
      confirmColor: Colors.red,
    );
    if (!confirm) return;
    try {
      final res = await ApiClient.delete('/productos/$idProducto');
      await _cargarTodo(mostrarCarga: false);
      if (!mounted) return;
      res.statusCode == 200
          ? context.showSnack('Producto eliminado')
          : context.showError('No se pudo eliminar');
    } catch (e) {
      if (mounted) context.showError('Sin conexión con el servidor');
    }
  }

  Future<void> _togglePausarProducto(Map<String, dynamic> producto) async {
    final int stockActual = producto['stock'] ?? 0;
    final bool estaPausado = producto['pausado'] ?? false;
    if (estaPausado && stockActual <= 0) {
      context.showSnack(
        'Tiene 0 piezas, edita el producto y súbele el stock para volver a venderlo',
        color: Colors.orange.shade800,
      );
      return;
    }
    try {
      await ApiClient.put('/productos/${producto['id']}/pausar');
      _cargarTodo(mostrarCarga: false);
    } catch (e) {
      if (mounted) context.showError('Sin conexión con el servidor');
    }
  }

  Future<void> _abrirFormulario({dynamic producto}) async {
    await showDialog(
      context: context,
      builder: (context) => ProductoFormDialog(producto: producto),
    );
    _cargarTodo(mostrarCarga: false);
  }

  // ==========================================
  // HORARIOS (con modalidad de entrega en cada turno)
  // ==========================================
  Future<void> _agregarTurno() async {
    final turno = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TurnoDialog(
        dia: _diaSeleccionado,
        existentes: _todosLosHorarios
            .where((t) => t['dia'] == _diaSeleccionado)
            .map((t) => ('${t['inicio']}', '${t['fin']}'))
            .toList(),
      ),
    );
    if (turno == null || !mounted) return;

    try {
      var res = await ApiClient.post('/v2/horarios', {
        "id_vendedor": currentUserId,
        ...turno,
      });
      // Servidor sin el endpoint nuevo: se guarda solo la hora.
      if (res.statusCode == 404 || res.statusCode == 405) {
        res = await ApiClient.post('/horarios', {
          "id_vendedor": currentUserId,
          "dia_semana": turno['dia_semana'],
          "hora_inicio": turno['hora_inicio'],
          "hora_fin": turno['hora_fin'],
        });
      }
      if (!mounted) return;
      if (res.statusCode == 200) {
        context.showSuccess('Turno agregado');
        _cargarTodo(mostrarCarga: false);
      } else {
        context.showError(
          ApiClient.detalle(res) ?? 'No se pudo guardar el turno',
        );
      }
    } catch (e) {
      if (mounted) context.showError('Sin conexión con el servidor');
    }
  }

  Future<void> _eliminarTurno(int idHorario) async {
    try {
      await ApiClient.delete('/horarios/$idHorario');
      _cargarTodo(mostrarCarga: false);
    } catch (e) {
      if (mounted) context.showError('Sin conexión con el servidor');
    }
  }

  // ==========================================
  // REDES SOCIALES
  // ==========================================
  Future<void> _guardarRedes() async {
    context.cerrarTeclado();
    if (!_redesFormKey.currentState!.validate()) return;
    setState(() => _guardandoRedes = true);
    try {
      final res = await ApiClient.put(
        '/usuarios/$currentUserId/perfil',
        _redes.valores(),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        cargarUsuario(ApiClient.decode(res));
        context.showSuccess('Redes guardadas, ya aparecen en tu catálogo');
      } else {
        context.showError('No se pudieron guardar tus redes');
      }
    } catch (_) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      if (mounted) setState(() => _guardandoRedes = false);
    }
  }

  // ==========================================
  // PANTALLA
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (!esVendedor) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.storefront, size: 72, color: AppColors.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Esta sección es para vendedores',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Actívala desde Configuración en tu perfil',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    text: 'Volver al inicio',
                    onPressed: () => context.irALimpio(const InicioScreen()),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MainLayout(
      activeRoute: 'Vender',
      onStateChanged: () => setState(() {}),
      builder: (context, isMobile) => _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _cargarTodo(mostrarCarga: false),
              child: PageScroll(
                isMobile: isMobile,
                verticalPadding: isMobile ? 20 : 40,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(isMobile),
                    const SizedBox(height: 24),
                    _buildTopStats(isMobile),
                    const SizedBox(height: 24),
                    _buildPedidosSection(isMobile),
                    const SizedBox(height: 24),
                    ResponsiveSplit(
                      isMobile: isMobile,
                      leftFlex: 6,
                      rightFlex: 4,
                      spacing: 24,
                      mobileCrossAxisAlignment: CrossAxisAlignment.stretch,
                      left: _buildInventorySection(isMobile),
                      right: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHorarioSection(),
                          const SizedBox(height: 24),
                          _buildRedesSection(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildHistorialSection(isMobile),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final boton = PrimaryButton(
      text: 'Publicar producto',
      icon: Icons.add,
      onPressed: () => _abrirFormulario(),
    );
    final titulo = SectionHeader(
      eyebrow: 'PANEL DE VENTAS',
      eyebrowGap: 0,
      title: 'Tu tienda',
      titleSize: isMobile ? 30 : 36,
      subtitle: 'Todo lo de tu negocio en un solo lugar: pedidos, productos y horarios',
      subtitleGap: 2,
      subtitleStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    );
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: titulo),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => _cargarTodo(),
                icon: const Icon(Icons.refresh, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          boton,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: titulo),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: () => _cargarTodo(),
          icon: const Icon(Icons.refresh, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        boton,
      ],
    );
  }

  Widget _buildTopStats(bool isMobile) {
    final int activos = _misProductos
        .where((p) => (p['pausado'] != true) && ((p['stock'] ?? 0) > 0))
        .length;
    final cards = [
      StatCard.neutral(
        icon: Icons.inventory_2_outlined,
        title: 'PRODUCTOS ACTIVOS',
        value: '$activos',
      ),
      StatCard.neutral(
        icon: Icons.payments_outlined,
        title: 'TOTAL GANADO',
        value: '\$${_totalGanado.toStringAsFixed(2)}',
        isMonetary: true,
      ),
      StatCard.neutral(
        icon: Icons.shopping_cart_outlined,
        title: 'PIEZAS VENDIDAS',
        value: '$_unidadesVendidas',
      ),
    ];
    if (isMobile) return StatCardsRow(isMobile: true, cards: cards);
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 24,
      mainAxisSpacing: 24,
      childAspectRatio: 2.4,
      children: cards,
    );
  }

  // ==========================================
  // SOLICITUDES PENDIENTES
  // ==========================================
  Widget _buildPedidosSection(bool isMobile) {
    final n = _pedidosPendientes.length;
    final (Color color, String ayuda) = n >= AppConstants.pendientesRojo
        ? (Colors.red, 'Tienes muchas solicitudes, respóndelas pronto')
        : n >= AppConstants.pendientesAmarillo
        ? (Colors.amber.shade700, 'Tienes solicitudes esperando respuesta')
        : (Colors.green, 'Estás al día, no hay solicitudes pendientes');

    return AppCard(
      radius: 20,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: ayuda,
                triggerMode: TooltipTriggerMode.tap,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.4), blurRadius: 6),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Solicitudes pendientes',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              if (n > 0)
                StatusBadge(
                  text: '$n por responder',
                  textColor: color,
                  backgroundColor: color.withOpacity(0.1),
                ),
              const InfoHint(
                'Verde: sin pendientes · Amarillo: tienes solicitudes · Rojo: 5 o más esperando',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_pedidosPendientes.isEmpty)
            EmptyState(
              icon: Icons.check_circle_outline,
              iconColor: Colors.green.shade300,
              iconGap: 12,
              title: '¡Todo al día!',
              subtitle: 'Cuando alguien te compre, aparecerá aquí y te llegará un aviso',
              padding: const EdgeInsets.symmetric(vertical: 16),
            )
          else
            for (final p in _pedidosPendientes) ...[
              _buildPedidoItem(p, isMobile),
              if (p != _pedidosPendientes.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }

  Widget _buildPedidoItem(dynamic p, bool isMobile) {
    final String name = '${p['cliente_nombre'] ?? 'Comprador'}';
    final bool enProceso = _pedidosEnProceso.contains(p['id_pedido']);

    final info = Row(
      children: [
        UserAvatar(
          nombre: name,
          fotoUrl: p['cliente_foto'],
          backgroundColor: Colors.grey.shade100,
          textColor: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${p['producto'] ?? ''} x${p['cantidad']} · \$${p['total']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Chat con el comprador',
          onPressed: () =>
              ChatPedidoSheet.abrir(context, idPedido: p['id_pedido']),
          icon: const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
        ),
      ],
    );

    final rechazar = OutlinedButton.icon(
      onPressed: enProceso ? null : () => _rechazarPedido(p),
      icon: const Icon(Icons.close, size: 18),
      label: const Text('Rechazar'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
      ),
    );
    final aceptar = ElevatedButton.icon(
      onPressed: enProceso ? null : () => _confirmarPedido(p['id_pedido']),
      icon: const Icon(Icons.check, size: 18),
      label: const Text('Aceptar'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
    );
    final botones = isMobile
        ? Row(
            children: [
              Expanded(child: rechazar),
              const SizedBox(width: 10),
              Expanded(child: aceptar),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [rechazar, const SizedBox(width: 10), aceptar],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: isMobile
          ? Column(children: [info, const SizedBox(height: 10), botones])
          : Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                botones,
              ],
            ),
    );
  }

  // ==========================================
  // INVENTARIO
  // ==========================================
  Widget _buildInventorySection(bool isMobile) {
    final productos = _misProductos
        .where(
          (p) => '${p['nombre']} ${p['categoria']}'.toLowerCase().contains(
            _filtroInventario,
          ),
        )
        .toList();

    return AppCard(
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTitle(
                  title: 'Mis productos',
                  badge: StatusBadge(
                    text: '${_misProductos.length}',
                    textColor: Colors.grey.shade700,
                    backgroundColor: Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  inputFormatters: [LengthLimitingTextInputFormatter(50)],
                  onChanged: (v) =>
                      setState(() => _filtroInventario = v.trim().toLowerCase()),
                  decoration: AppStyles.outlinedInput(
                    hintText: 'Buscar en mis productos',
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_misProductos.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              iconSize: 56,
              title: 'Aún no publicas nada',
              subtitle: 'Toca "Publicar producto" y empieza a vender hoy',
              padding: EdgeInsets.all(32),
            )
          else
            for (final p in productos) ...[
              _buildProductoItem(p, isMobile),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }

  Widget _buildProductoItem(dynamic producto, bool isMobile) {
    final int stockActual = producto['stock'] ?? 0;
    final bool sinStock = stockActual <= 0;
    final bool estaPausado = (producto['pausado'] ?? false) || sinStock;

    final acciones = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _accion(
          tooltip: estaPausado ? 'Volver a vender' : 'Pausar',
          icon: estaPausado ? Icons.play_arrow : Icons.pause,
          color: estaPausado ? Colors.green : Colors.orange,
          onPressed: () => _togglePausarProducto(producto),
        ),
        _accion(
          tooltip: 'Editar (también la foto)',
          icon: Icons.edit_outlined,
          color: Colors.blue,
          onPressed: () => _abrirFormulario(producto: producto),
        ),
        _accion(
          tooltip: 'Eliminar',
          icon: Icons.delete_outline,
          color: Colors.red,
          onPressed: () => _eliminarProducto(producto['id']),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 10),
      child: Row(
        children: [
          ProductImage(
            url: producto['imagen_url'],
            width: 56,
            height: 56,
            radius: 10,
            cover: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto['nombre'] ?? 'Sin nombre',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: estaPausado
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                Text(
                  '\$${producto['precio'] ?? 0} · $stockActual piezas · ${producto['categoria'] ?? 'Otros'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: sinStock ? Colors.red : Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                _buildEstadoProducto(producto, sinStock, estaPausado),
              ],
            ),
          ),
          acciones,
        ],
      ),
    );
  }

  Widget _buildEstadoProducto(dynamic producto, bool sinStock, bool pausado) {
    final (String texto, MaterialColor c) = sinStock
        ? ('Agotado', Colors.red)
        : pausado
        ? ('Pausado', Colors.grey)
        : ('A la venta', Colors.green);
    return StatusBadge(
      text: texto,
      textColor: c.shade700,
      backgroundColor: c.shade50,
      fontSize: 11,
    );
  }

  Widget _accion({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: color),
      onPressed: onPressed,
    );
  }

  // ==========================================
  // HORARIO Y FORMA DE ENTREGA
  // ==========================================
  Widget _buildHorarioSection() {
    final turnosDelDia = _todosLosHorarios
        .where((t) => t['dia'] == _diaSeleccionado)
        .toList()
      ..sort((a, b) => '${a['inicio']}'.compareTo('${b['inicio']}'));

    return AppCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Horario y entrega',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              StatusBadge(
                text: '${_todosLosHorarios.length} turnos',
                textColor: AppColors.primary,
                backgroundColor: AppColors.primary.withOpacity(0.08),
              ),
              const InfoHint(
                'Cada turno dice a qué hora vendes y cómo entregas. Solo de lunes a viernes, de 6:00 am a 9:00 pm',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Elige un día y agrega cuándo y cómo entregas',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 14),
          // Selector de días: se reparte el ancho disponible (responsivo).
          Row(
            children: [
              for (var i = 0; i < AppConstants.diasCortos.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _buildDia(i + 1)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            AppConstants.diasNombres[_diaSeleccionado - 1].toUpperCase(),
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (turnosDelDia.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sin turnos este día',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          for (final t in turnosDelDia) _buildTurno(t),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _agregarTurno,
            icon: const Icon(Icons.add),
            label: const Text('Agregar turno'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDia(int dia) {
    final bool sel = _diaSeleccionado == dia;
    final bool tieneTurnos = _todosLosHorarios.any((t) => t['dia'] == dia);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _diaSeleccionado = dia),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              AppConstants.diasCortos[dia - 1],
              style: TextStyle(
                color: sel ? Colors.white : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (tieneTurnos)
              Positioned(
                bottom: 5,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurno(dynamic turno) {
    final modalidad = '${turno['modalidad'] ?? ''}';
    final punto = '${turno['punto_entrega'] ?? ''}';
    final icono = AppConstants.modalidadesEntrega
        .where((m) => m.$1 == modalidad)
        .map((m) => m.$3)
        .firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icono ?? Icons.schedule, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rangoTurno(turno),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (modalidad.isNotEmpty || punto.isNotEmpty)
                  Text(
                    [modalidad, punto].where((x) => x.isNotEmpty).join(' · '),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar turno',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            onPressed: () => _eliminarTurno(turno['id']),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // REDES SOCIALES
  // ==========================================
  Widget _buildRedesSection() {
    return AppCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _redesFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tus redes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Así tus clientes te encuentran para quedar de acuerdo en la entrega',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 14),
            RedesSocialesCampos(controllers: _redes),
            ElevatedButton(
              onPressed: _guardandoRedes ? null : _guardarRedes,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _guardandoRedes
                  ? const ButtonSpinner(size: 18)
                  : const Text('Guardar redes'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // HISTORIAL DE VENTAS (con filtros)
  // ==========================================
  Future<void> _elegirRango() async {
    final hoy = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoy.year - 2),
      lastDate: hoy,
      initialDateRange: _rangoHistorial,
      helpText: 'Elige las fechas',
      saveText: 'Aplicar',
    );
    if (rango == null) return;
    setState(() => _rangoHistorial = rango);
    _cargarHistorial();
  }

  Widget _buildHistorialSection(bool isMobile) {
    return AppCard(
      radius: 20,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle(
            title: 'Historial de ventas',
            badge: StatusBadge(
              text: '${_historialPedidos.length}',
              textColor: AppColors.primary,
              backgroundColor: AppColors.primary.withOpacity(0.08),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in PedidoEstadoStyle.filtros.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: _filtroHistorial == f,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: _filtroHistorial == f
                            ? Colors.white
                            : Colors.grey.shade700,
                      ),
                      onSelected: (_) {
                        setState(() => _filtroHistorial = f);
                        _cargarHistorial();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _elegirRango,
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  _rangoHistorial == null
                      ? 'Filtrar por fechas'
                      : '${formatFecha(_rangoHistorial!.start, conHora: false)} al ${formatFecha(_rangoHistorial!.end, conHora: false)}',
                ),
              ),
              if (_rangoHistorial != null)
                TextButton(
                  onPressed: () {
                    setState(() => _rangoHistorial = null);
                    _cargarHistorial();
                  },
                  child: const Text('Quitar fechas'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cargandoHistorial)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_historialPedidos.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No hay ventas con estos filtros',
              padding: EdgeInsets.symmetric(vertical: 24),
            )
          else if (isMobile)
            for (final p in _historialPedidos) _buildVentaCard(p)
          else
            _buildHistorialTable(),
        ],
      ),
    );
  }

  Widget _buildVentaCard(dynamic pedido) {
    final estilo = PedidoEstadoStyle.paraVendedor(pedido['estado']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(
                      text: estilo.label,
                      textColor: estilo.color,
                      backgroundColor: estilo.background,
                      fontSize: 11,
                    ),
                    InfoHint(estilo.ayuda, size: 14),
                    const Spacer(),
                    Text(
                      '\$${pedido['total']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${pedido['producto'] ?? ''} x${pedido['cantidad'] ?? 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${pedido['cliente_nombre'] ?? ''} · ${formatFecha(pedido['fecha'])}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                if ((pedido['motivo_rechazo'] ?? '').toString().isNotEmpty)
                  Text(
                    'Motivo: ${pedido['motivo_rechazo']}',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Chat',
            icon: const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
            onPressed: () =>
                ChatPedidoSheet.abrir(context, idPedido: pedido['id_pedido']),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorialTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: AppStyles.tableHeading,
        columns: const [
          DataColumn(label: Text('PEDIDO')),
          DataColumn(label: Text('CLIENTE')),
          DataColumn(label: Text('PRODUCTO')),
          DataColumn(label: Text('FECHA')),
          DataColumn(label: Text('TOTAL')),
          DataColumn(label: Text('ESTADO')),
          DataColumn(label: Text('CHAT')),
        ],
        rows: _historialPedidos.map((pedido) {
          final estilo = PedidoEstadoStyle.paraVendedor(pedido['estado']);
          return DataRow(
            cells: [
              DataCell(
                Text(
                  '#${pedido['id_pedido']}',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
              DataCell(
                Text(
                  pedido['cliente_nombre'] ?? 'Comprador',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(
                Text('${pedido['producto'] ?? ''} (x${pedido['cantidad'] ?? 1})'),
              ),
              DataCell(Text(formatFecha(pedido['fecha']))),
              DataCell(
                Text(
                  '\$${pedido['total']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusBadge.dot(
                      text: estilo.label,
                      textColor: estilo.color,
                      backgroundColor: estilo.background,
                      borderColor: estilo.color.withOpacity(0.3),
                      dotColor: estilo.color,
                    ),
                    InfoHint(
                      (pedido['motivo_rechazo'] ?? '').toString().isNotEmpty
                          ? 'Motivo: ${pedido['motivo_rechazo']}'
                          : estilo.ayuda,
                      size: 14,
                    ),
                  ],
                ),
              ),
              DataCell(
                IconButton(
                  tooltip: 'Abrir chat',
                  icon: const Icon(
                    Icons.chat_bubble_outline,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  onPressed: () => ChatPedidoSheet.abrir(
                    context,
                    idPedido: pedido['id_pedido'],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// Diálogo para agregar un turno: día, horas (6 am a 9 pm), forma de
/// entrega y lugar. Regresa el cuerpo listo para POST /v2/horarios.
class _TurnoDialog extends StatefulWidget {
  final int dia;
  final List<(String, String)> existentes;
  const _TurnoDialog({required this.dia, required this.existentes});

  @override
  State<_TurnoDialog> createState() => _TurnoDialogState();
}

class _TurnoDialogState extends State<_TurnoDialog> {
  TimeOfDay _inicio = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _fin = const TimeOfDay(hour: 9, minute: 0);
  String _modalidad = AppConstants.modalidadesEntrega.first.$1;
  final TextEditingController _punto = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _punto.dispose();
    super.dispose();
  }

  Future<void> _elegirHora(bool esInicio) async {
    final h = await showTimePicker(
      context: context,
      initialTime: esInicio ? _inicio : _fin,
      helpText: esInicio ? 'Hora de inicio' : 'Hora de fin',
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (h == null) return;
    setState(() {
      esInicio ? _inicio = h : _fin = h;
      _error = null;
    });
  }

  void _guardar() {
    final error = Validators.turno(_inicio, _fin, widget.existentes);
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, {
      "dia_semana": widget.dia,
      "hora_inicio": formatHora(_inicio),
      "hora_fin": formatHora(_fin),
      "modalidad": _modalidad,
      "punto_entrega": _punto.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppStyles.dialogShape(),
      title: Text(
        'Nuevo turno · ${AppConstants.diasNombres[widget.dia - 1]}',
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _horaBox('Desde', _inicio, () => _elegirHora(true))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('a'),
                  ),
                  Expanded(child: _horaBox('Hasta', _fin, () => _elegirHora(false))),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Puedes elegir de 6:00 am a 9:00 pm',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
              const SizedBox(height: 16),
              const Text(
                '¿Cómo entregas en este horario?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final (titulo, detalle, icono) in AppConstants.modalidadesEntrega)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _modalidad = titulo),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _modalidad == titulo
                            ? AppColors.primary.withOpacity(0.06)
                            : Colors.white,
                        border: Border.all(
                          color: _modalidad == titulo
                              ? AppColors.primary
                              : Colors.grey.shade300,
                          width: _modalidad == titulo ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(icono, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  detalle,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_modalidad == titulo)
                            const Icon(Icons.check_circle, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              TextField(
                controller: _punto,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Lugar (opcional)',
                  hintText: 'Ej. Afuera del edificio U',
                  prefixIcon: const Icon(Icons.place_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogCancelButton(onPressed: () => Navigator.pop(context)),
        ElevatedButton(
          onPressed: _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Guardar turno'),
        ),
      ],
    );
  }

  Widget _horaBox(String label, TimeOfDay hora, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: const Icon(Icons.access_time, size: 18),
        ),
        child: Text(
          hora12(formatHora(hora)),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
