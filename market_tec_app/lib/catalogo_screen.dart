import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/ui_helpers.dart';
import 'core/validators.dart';
import 'globals.dart';
import 'vender_screen.dart';
import 'widgets/compra_card.dart';
import 'widgets/vendedor_widgets.dart';
import 'widgets/widgets.dart';

class CatalogoScreen extends StatefulWidget {
  /// Si viene, el catálogo abre mostrando solo los productos de ese vendedor
  /// (por ejemplo desde el mapa).
  final int? vendedorId;
  final String? vendedorNombre;

  const CatalogoScreen({super.key, this.vendedorId, this.vendedorNombre});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  String selectedCategory = 'Todos';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<dynamic> _productos = [];
  List<dynamic> _vendedores = [];
  List<int> _misFavoritosIds = [];

  /// Compras entregadas por producto: id_producto → ya_calificado.
  Map<int, bool> _comprados = {};
  int? _vendedorFiltro;
  bool _isLoading = true;
  bool _buscando = false;

  final List<String> categories = ['Todos', ...AppConstants.categoriasProducto];

  @override
  void initState() {
    super.initState();
    _vendedorFiltro = widget.vendedorId;
    _cargarDatos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ==========================================
  // DATOS
  // ==========================================
  Future<void> _cargarDatos({bool mostrarCarga = true}) async {
    if (mostrarCarga) setState(() => _isLoading = true);
    try {
      final resultados = await Future.wait([
        ApiClient.getList('/productos'),
        ApiClient.getList('/favoritos/$currentUserId'),
        ApiClient.getList('/vendedores').catchError((_) => null),
        cargarMisCompras().catchError((_) => <dynamic>[]),
      ]);
      _productos = resultados[0] ?? _productos;
      final favs = resultados[1];
      if (favs != null) _misFavoritosIds = favs.whereType<int>().toList();
      _vendedores = resultados[2] ?? _vendedoresDesdeProductos();
      _comprados = {
        for (final c in resultados[3] ?? const [])
          if (c['estado'] == 'Entregado' && c['id_producto'] is int)
            c['id_producto'] as int:
                (c['ya_calificado'] == true) ||
                (_comprados[c['id_producto']] ?? false),
      };
      _searchController.clear();
    } catch (e) {
      debugPrint('Error cargando catálogo: $e');
      if (mounted) context.showError('No se pudo actualizar el catálogo');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Si el servidor aún no tiene /vendedores, se arma la lista con los
  /// vendedores que tienen productos publicados.
  List<dynamic> _vendedoresDesdeProductos() {
    final vistos = <int, Map<String, dynamic>>{};
    for (final p in _productos) {
      final id = p['vendedor_id'];
      if (id is int && !vistos.containsKey(id)) {
        vistos[id] = {'id': id, 'nombre': p['vendedor_nombre'] ?? 'Vendedor'};
      }
    }
    return vistos.values.toList();
  }

  Future<void> _ejecutarBusquedaInteligente() async {
    context.cerrarTeclado();
    final String query = _searchController.text.trim();
    if (query.isEmpty) return _cargarDatos();
    if (_buscando) return;
    if (query.length < 2) {
      context.showSnack('Escribe al menos 2 letras para buscar');
      return;
    }
    setState(() {
      _buscando = true;
      selectedCategory = 'Todos';
      _vendedorFiltro = null;
    });
    try {
      final res = await ApiClient.get(
        '/productos/buscar?q=${Uri.encodeQueryComponent(query)}',
      );
      if (res.statusCode == 200) _productos = ApiClient.decodeList(res);
    } catch (e) {
      if (mounted) context.showError('No se pudo hacer la búsqueda');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _toggleFavorito(int idProducto) async {
    setState(() {
      _misFavoritosIds.contains(idProducto)
          ? _misFavoritosIds.remove(idProducto)
          : _misFavoritosIds.add(idProducto);
    });
    try {
      await ApiClient.post('/favoritos', {
        "id_producto": idProducto,
        "id_cliente": currentUserId,
      });
    } catch (e) {
      _cargarDatos(mostrarCarga: false);
    }
  }

  Map<String, dynamic>? get _vendedorSeleccionado {
    if (_vendedorFiltro == null) return null;
    for (final v in _vendedores) {
      if (v['id'] == _vendedorFiltro) return Map<String, dynamic>.from(v);
    }
    return {
      'id': _vendedorFiltro,
      'nombre': widget.vendedorNombre ?? 'Vendedor',
    };
  }

  void _seleccionarVendedor(int? id) {
    setState(() {
      _vendedorFiltro = id;
      selectedCategory = 'Todos';
    });
  }

  // ==========================================
  // PANTALLA
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeRoute: 'Catálogo',
      backgroundColor: AppColors.background,
      builder: (context, isMobile) => _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _cargarDatos(mostrarCarga: false),
              child: _buildBody(isMobile),
            ),
    );
  }

  Widget _buildBody(bool isMobile) {
    final productosFiltrados = _productos.where((p) {
      if (_vendedorFiltro != null && p['vendedor_id'] != _vendedorFiltro) {
        return false;
      }
      return selectedCategory == 'Todos' || p['categoria'] == selectedCategory;
    }).toList();

    final favoritos = _vendedorFiltro != null
        ? const []
        : productosFiltrados
              .where((p) => _misFavoritosIds.contains(p['id']))
              .toList();
    final double h = isMobile ? 16.0 : 60.0;
    final vendedor = _vendedorSeleccionado;

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(h, isMobile ? 20 : 32, h, 8),
          sliver: SliverToBoxAdapter(child: _buildHeaderAndSearch(isMobile)),
        ),
        if (_vendedores.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(h, 8, h, 4),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Vendedores del campus',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const InfoHint(
                        'Toca a un vendedor para ver todo lo que vende',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  VendedoresStrip(
                    vendedores: _vendedores,
                    seleccionado: _vendedorFiltro,
                    onSeleccionar: _seleccionarVendedor,
                  ),
                ],
              ),
            ),
          ),
        if (vendedor != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(h, 8, h, 8),
            sliver: SliverToBoxAdapter(
              child: VendedorInfoCard(
                key: ValueKey(vendedor['id']),
                idVendedor: vendedor['id'],
                nombre: '${vendedor['nombre']}',
                fotoUrl: vendedor['foto_url'],
                onCerrar: () => _seleccionarVendedor(null),
              ),
            ),
          ),
        // Barra de categorías fija: se queda arriba al bajar.
        SliverPersistentHeader(
          pinned: true,
          delegate: _CategoriasHeader(
            child: Container(
              color: AppColors.background,
              padding: EdgeInsets.symmetric(horizontal: h, vertical: 10),
              child: _buildCategorias(productosFiltrados.length, isMobile),
            ),
          ),
        ),
        if (_buscando)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (productosFiltrados.isEmpty)
          SliverToBoxAdapter(child: _buildVacio())
        else ...[
          if (favoritos.isNotEmpty)
            SliverToBoxAdapter(child: _buildFavoritosSection(favoritos, isMobile)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(h, 20, h, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                vendedor != null
                    ? 'Todo lo que vende ${'${vendedor['nombre']}'.split(' ').first}'
                    : _searchController.text.isNotEmpty
                    ? 'Resultados de tu búsqueda'
                    : selectedCategory == 'Todos'
                    ? 'Todo el catálogo'
                    : selectedCategory,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(h, 8, h, 40),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isMobile ? 220 : 280,
                mainAxisExtent: ProductCard.alto(compacta: isMobile),
                crossAxisSpacing: isMobile ? 12 : 24,
                mainAxisSpacing: isMobile ? 12 : 24,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildProductCard(
                  productosFiltrados[i],
                  isDarkTheme: false,
                  compacta: isMobile,
                ),
                childCount: productosFiltrados.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVacio() {
    final enCategoria = selectedCategory != 'Todos';
    final String titulo;
    final String detalle;
    if (_searchController.text.isNotEmpty) {
      titulo = 'No encontramos nada con esa búsqueda';
      detalle = 'Prueba con otra palabra o revisa la ortografía';
    } else if (_vendedorFiltro != null) {
      titulo = enCategoria
          ? 'Este vendedor no tiene productos en $selectedCategory'
          : 'Este vendedor aún no tiene productos publicados';
      detalle = 'Vuelve pronto o mira lo que venden los demás';
    } else if (enCategoria) {
      titulo = 'Aún no hay productos en $selectedCategory';
      detalle = '¿Tú vendes algo así? Publícalo y sé el primero';
    } else {
      titulo = 'Todavía no hay productos publicados';
      detalle = 'Vuelve en un rato, los vendedores publican durante el día';
    }
    return EmptyState(
      icon: Icons.inventory_2_outlined,
      iconSize: 56,
      title: titulo,
      subtitle: detalle,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    );
  }

  Widget _buildHeaderAndSearch(bool isMobile) {
    final buscador = TextField(
      controller: _searchController,
      inputFormatters: [LengthLimitingTextInputFormatter(100)],
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _ejecutarBusquedaInteligente(),
      decoration: InputDecoration(
        hintText: 'Busca "audífonos" o "algo de menos de 50"',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          tooltip: 'Buscar',
          icon: const Icon(Icons.arrow_forward, color: AppColors.primary),
          onPressed: _ejecutarBusquedaInteligente,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Catálogo',
                style: TextStyle(
                  fontSize: isMobile ? 30 : 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Actualizar catálogo',
              onPressed: () => _cargarDatos(),
              icon: const Icon(Icons.refresh, color: AppColors.primary),
            ),
          ],
        ),
        Text(
          'Antojitos, gadgets, ropa y asesorías de tus compañeros del ITZ',
          style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: buscador,
        ),
      ],
    );
  }

  Widget _buildCategorias(int resultCount, bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final bool isSelected = selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    // Sin palomita: antes salía doble.
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => selectedCategory = cat);
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : Colors.grey.shade300,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              '$resultCount productos',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFavoritosSection(List<dynamic> productos, bool isMobile) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 40, vertical: 12),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16.0 : 24.0,
        vertical: 24.0,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(isMobile ? 0 : 28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tus favoritos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StatusBadge(
                text: '${productos.length}',
                textColor: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.15),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                radius: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: ProductCard.alto(compacta: true),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: productos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: 190,
                child: _buildProductCard(
                  productos[index],
                  isDarkTheme: true,
                  compacta: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> producto, {
    required bool isDarkTheme,
    required bool compacta,
  }) {
    final int idProducto = producto['id'];
    final bool isMine = producto['vendedor_id'] == currentUserId;

    return ProductCard(
      producto: producto,
      isFavorite: _misFavoritosIds.contains(idProducto),
      isMine: isMine,
      isDarkTheme: isDarkTheme,
      compacta: compacta,
      onToggleFavorite: () => _toggleFavorito(idProducto),
      onAction: () {
        if (isMine) {
          context.irA(const VenderScreen());
        } else {
          _mostrarDetalle(producto);
        }
      },
    );
  }

  // ==========================================
  // DETALLE DEL PRODUCTO (responsivo)
  // ==========================================
  Future<void> _mostrarDetalle(Map<String, dynamic> producto) async {
    final ancho = MediaQuery.of(context).size.width;
    final detalle = _DetalleProducto(
      producto: producto,
      comprado: _comprados.containsKey(producto['id']),
      yaCalificado: _comprados[producto['id']] ?? false,
      esMovil: ancho < 760,
      onVerVendedor: () {
        Navigator.pop(context);
        _seleccionarVendedor(producto['vendedor_id']);
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
    );

    final cambios = ancho < 760
        ? await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            backgroundColor: Colors.white,
            builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: detalle),
          )
        : await showDialog<bool>(
            context: context,
            builder: (_) => Dialog(
              shape: AppStyles.dialogShape(24),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920, maxHeight: 620),
                child: detalle,
              ),
            ),
          );
    if (cambios == true) _cargarDatos(mostrarCarga: false);
  }
}

/// Mantiene la barra de categorías pegada arriba al hacer scroll.
class _CategoriasHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  _CategoriasHeader({required this.child});

  @override
  double get minExtent => 58;
  @override
  double get maxExtent => 58;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      elevation: overlapsContent || shrinkOffset > 0 ? 2 : 0,
      color: AppColors.background,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _CategoriasHeader oldDelegate) => true;
}

/// Contenido del detalle: foto completa, datos, vendedor, redes, cantidad,
/// botones y opiniones. En celular todo va en una sola columna con scroll.
class _DetalleProducto extends StatefulWidget {
  final Map<String, dynamic> producto;
  final bool comprado;
  final bool yaCalificado;
  final bool esMovil;
  final VoidCallback onVerVendedor;

  const _DetalleProducto({
    required this.producto,
    required this.comprado,
    required this.yaCalificado,
    required this.esMovil,
    required this.onVerVendedor,
  });

  @override
  State<_DetalleProducto> createState() => _DetalleProductoState();
}

class _DetalleProductoState extends State<_DetalleProducto> {
  int cantidad = 1;
  bool _pidiendo = false;
  bool _calificado = false;
  bool _cambios = false;
  late final Future<List<dynamic>> _resenas = ApiClient.getList(
    '/productos/${widget.producto['id']}/resenas',
  ).then((l) => l ?? <dynamic>[]).catchError((_) => <dynamic>[]);
  late final Future<Map<String, dynamic>?> _vendedor = ApiClient.getMap(
    '/vendedores/${widget.producto['vendedor_id']}',
  ).catchError((_) => null);

  Map<String, dynamic> get p => widget.producto;
  double get precio => (p['precio'] ?? 0.0).toDouble();
  int get stock => p['stock'] ?? 1;

  @override
  void initState() {
    super.initState();
    _calificado = widget.yaCalificado;
  }

  Future<void> _solicitarPedido() async {
    final error = Validators.cantidad(cantidad, stock);
    if (error != null) return context.showError(error);
    setState(() => _pidiendo = true);
    try {
      final response = await ApiClient.post('/pedidos', {
        "id_cliente": currentUserId,
        "id_vendedor": p['vendedor_id'],
        "id_producto": p['id'],
        "cantidad": cantidad,
        "precio_congelado": precio,
        "total_venta": precio * cantidad,
      });
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        int? idPedido;
        try {
          final d = ApiClient.decode(response);
          idPedido = d['id_pedido'] ?? d['id'];
        } catch (_) {}
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 6),
            content: Text(
              '¡Pedido enviado! Apartamos tus piezas, ${p['vendedor_nombre']} te confirmará pronto',
            ),
            action: idPedido == null
                ? null
                : SnackBarAction(
                    label: 'Abrir chat',
                    textColor: Colors.white,
                    onPressed: () {
                      final ctx = navigatorKey.currentContext;
                      if (ctx != null) {
                        ChatPedidoSheet.abrir(ctx, idPedido: idPedido!);
                      }
                    },
                  ),
          ),
        );
      } else {
        context.showError(
          ApiClient.detalle(response) ?? 'Ya no hay suficientes piezas disponibles',
        );
      }
    } catch (e) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      if (mounted) setState(() => _pidiendo = false);
    }
  }

  Future<void> _opinar() async {
    final ok = await mostrarCalificarDialog(
      context,
      idProducto: p['id'],
      nombreProducto: '${p['nombre']}',
    );
    if (ok && mounted) {
      setState(() {
        _calificado = true;
        _cambios = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.esMovil ? _buildMovil() : _buildEscritorio();
  }

  Widget _buildMovil() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ProductImage(url: p['imagen_url'], radius: 18),
              ),
              const SizedBox(height: 16),
              ..._buildInfo(),
              const SizedBox(height: 16),
              _buildResenas(alturaFija: false),
            ],
          ),
        ),
        _buildBarraCompra(),
      ],
    );
  }

  Widget _buildEscritorio() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Container(
            color: Colors.grey.shade100,
            child: ProductImage(url: p['imagen_url']),
          ),
        ),
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context, _cambios),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                  children: [
                    ..._buildInfo(),
                    const SizedBox(height: 16),
                    _buildResenas(alturaFija: false),
                  ],
                ),
              ),
              _buildBarraCompra(),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildInfo() {
    final double rating = (p['rating'] ?? 0.0).toDouble();
    final descripcion = '${p['descripcion'] ?? ''}'.trim();
    return [
      Row(
        children: [
          Flexible(
            child: Text(
              '${p['categoria'] ?? ''}'.toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.star, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            rating > 0 ? rating.toStringAsFixed(1) : 'Sin opiniones aún',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '${p['nombre']}',
        style: TextStyle(
          fontSize: widget.esMovil ? 22 : 26,
          fontWeight: FontWeight.w900,
          height: 1.15,
        ),
      ),
      if (descripcion.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          descripcion,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 14, height: 1.4),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        '\$${precio.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: 12),
      FutureBuilder<Map<String, dynamic>?>(
        future: _vendedor,
        builder: (context, snap) {
          final v = snap.data ?? {};
          final redes = Map<String, dynamic>.from(v['redes'] ?? {});
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    UserAvatar(
                      nombre: '${p['vendedor_nombre'] ?? 'V'}',
                      fotoUrl: v['foto_url'],
                      radius: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vendido por',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${p['vendedor_nombre'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onVerVendedor,
                      child: const Text('Ver su catálogo'),
                    ),
                  ],
                ),
                if (redes.values.any((x) => x != null && '$x'.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  RedesSocialesBotones(redes: redes, compacto: true),
                ],
              ],
            ),
          );
        },
      ),
    ];
  }

  Widget _buildResenas({required bool alturaFija}) {
    return FutureBuilder<List<dynamic>>(
      future: _resenas,
      builder: (context, snap) {
        final resenas = snap.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lo que opinan los compradores (${resenas.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (!snap.hasData)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (resenas.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Aún nadie lo ha calificado',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              for (final r in resenas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildResenaMini(r),
                ),
          ],
        );
      },
    );
  }

  Widget _buildResenaMini(dynamic r) {
    final int cal = r['calificacion'] ?? 5;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['cliente'] ?? 'Estudiante'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              StarRating(rating: cal, size: 13),
            ],
          ),
          if ('${r['comentario'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${r['comentario']}',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// Cantidad + botones. Si ya lo compró: opinar (una vez) y volver a comprar.
  Widget _buildBarraCompra() {
    final sinStock = Validators.cantidad(1, stock);
    final botonComprar = SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _pidiendo || sinStock != null ? null : _solicitarPedido,
        icon: _pidiendo
            ? const ButtonSpinner(size: 20)
            : Icon(
                widget.comprado ? Icons.replay : Icons.shopping_cart_outlined,
                size: 20,
              ),
        label: Text(
          sinStock ??
              (widget.comprado
                  ? 'Volver a comprar'
                  : 'Pedir por \$${(precio * cantidad).toStringAsFixed(2)}'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sinStock == null)
              _QuantitySelector(
                cantidad: cantidad,
                stockMaximo: stock,
                onChanged: (v) => setState(() => cantidad = v),
              ),
            const SizedBox(height: 10),
            if (widget.comprado && !_calificado)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _opinar,
                        icon: const Icon(Icons.star, color: Colors.amber),
                        label: const Text(
                          'Dar mi opinión',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: botonComprar),
                ],
              )
            else
              SizedBox(width: double.infinity, child: botonComprar),
            if (!widget.comprado)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Podrás opinar cuando recibas tu pedido',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Selector "Cantidad [-] 1 [+] (5 disponibles)".
class _QuantitySelector extends StatelessWidget {
  final int cantidad;
  final int stockMaximo;
  final ValueChanged<int> onChanged;

  const _QuantitySelector({
    required this.cantidad,
    required this.stockMaximo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Cantidad',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 16),
                onPressed: cantidad > 1 ? () => onChanged(cantidad - 1) : null,
              ),
              Text(
                '$cantidad',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 16),
                onPressed: cantidad < stockMaximo
                    ? () => onChanged(cantidad + 1)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$stockMaximo disponibles',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    );
  }
}
