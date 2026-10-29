import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/ui_helpers.dart';
import 'core/validators.dart';
import 'globals.dart';
import 'widgets/widgets.dart';

/// Pantalla "Comentarios": a la izquierda los comentarios sobre la página
/// (sugerencias, errores u opiniones) y a la derecha el formulario para
/// reportar a un vendedor, con un producto suyo de forma opcional.
///
/// Las opiniones de productos ya no se hacen aquí: se dejan desde la compra
/// (solo quien compró el producto puede calificarlo).
class OpinionesScreen extends StatefulWidget {
  /// Si se abre desde un producto, el reporte ya trae vendedor y producto.
  final Map<String, dynamic>? productoInicial;

  const OpinionesScreen({super.key, this.productoInicial});

  @override
  State<OpinionesScreen> createState() => _OpinionesScreenState();
}

class _OpinionesScreenState extends State<OpinionesScreen> {
  // ---- Comentarios de la web ----
  String _tipo = AppConstants.tiposComentarioWeb.first.$1;
  int _estrellas = 0; // 0 = sin calificar (es opcional)
  final _mensajeCtrl = TextEditingController();
  bool _enviandoComentario = false;
  List<dynamic> _misComentarios = [];

  // ---- Reporte a vendedor ----
  final _reporteFormKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  List<dynamic> _vendedores = [];
  Map<String, dynamic>? _vendedor;
  bool _incluirProducto = false;
  List<dynamic> _productosVendedor = [];
  bool _cargandoProductos = false;
  int? _idProducto;
  String? _motivo;
  final _descripcionCtrl = TextEditingController();
  bool _enviandoReporte = false;
  int _versionBuscador = 0; // fuerza a limpiar el buscador al enviar

  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _mensajeCtrl.dispose();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    await Future.wait([_cargarVendedores(), _cargarMisComentarios()]);
    final p = widget.productoInicial;
    if (p != null && p['vendedor_id'] != null) {
      final v = _vendedores.firstWhere(
        (v) => v['id'] == p['vendedor_id'],
        orElse: () => {'id': p['vendedor_id'], 'nombre': p['vendedor_nombre']},
      );
      await _elegirVendedor(Map<String, dynamic>.from(v));
      _incluirProducto = true;
      _idProducto = p['id'];
    }
    if (mounted) setState(() => _cargando = false);
  }

  /// Lista de vendedores. Si el servidor todavía no tiene /vendedores se
  /// arma con los productos del catálogo.
  Future<void> _cargarVendedores() async {
    try {
      final lista = await ApiClient.getList('/vendedores');
      if (lista != null) {
        _vendedores = lista.where((v) => v['id'] != currentUserId).toList();
        return;
      }
    } catch (_) {}
    try {
      final productos = await ApiClient.getList('/productos') ?? [];
      final mapa = <int, Map<String, dynamic>>{};
      for (final p in productos) {
        final id = p['vendedor_id'];
        if (id is int && id != currentUserId) {
          mapa[id] = {'id': id, 'nombre': p['vendedor_nombre'] ?? 'Vendedor'};
        }
      }
      _vendedores = mapa.values.toList();
    } catch (e) {
      debugPrint('Error cargando vendedores: $e');
    }
  }

  Future<void> _cargarMisComentarios() async {
    try {
      final lista = await ApiClient.getList(
        '/usuarios/$currentUserId/comentarios-web',
      );
      if (lista != null && mounted) setState(() => _misComentarios = lista);
    } catch (_) {}
  }

  Future<void> _elegirVendedor(Map<String, dynamic>? v) async {
    setState(() {
      _vendedor = v;
      _idProducto = null;
      _productosVendedor = [];
    });
    if (v == null) return;
    setState(() => _cargandoProductos = true);
    try {
      final lista = await ApiClient.getList('/productos/vendedor/${v['id']}');
      if (mounted) setState(() => _productosVendedor = lista ?? []);
    } catch (_) {
      // Si falla, se queda sin productos y el reporte va solo al vendedor
    } finally {
      if (mounted) setState(() => _cargandoProductos = false);
    }
  }

  // ===================== Envíos =====================

  Future<void> _enviarComentario() async {
    if (_enviandoComentario) return;
    final texto = _mensajeCtrl.text.trim();
    final error = Validators.comentario(texto);
    if (error != null) return context.showSnack(error);

    setState(() => _enviandoComentario = true);
    try {
      final res = await ApiClient.post('/comentarios-web', {
        'id_usuario': currentUserId,
        'tipo': _tipo,
        'calificacion': _estrellas == 0 ? null : _estrellas,
        'mensaje': texto,
      });
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        _mensajeCtrl.clear();
        setState(() => _estrellas = 0);
        context.showSuccess('¡Gracias! Tu comentario ya le llegó al equipo');
        _cargarMisComentarios();
      } else {
        context.showError(
          ApiClient.detalle(res) ?? 'No se pudo enviar tu comentario',
        );
      }
    } catch (_) {
      if (mounted) context.showError('Error de conexión al servidor');
    } finally {
      if (mounted) setState(() => _enviandoComentario = false);
    }
  }

  Future<void> _enviarReporte() async {
    if (_enviandoReporte) return;
    if (_vendedor == null) {
      return context.showSnack('Busca y elige al vendedor que quieres reportar');
    }
    if (!_reporteFormKey.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    if (_incluirProducto && _idProducto == null) {
      return context.showSnack('Elige el producto o desmarca la casilla');
    }

    setState(() => _enviandoReporte = true);
    try {
      final res = await ApiClient.post('/reportes', {
        'id_reportante': currentUserId,
        'id_vendedor': _vendedor!['id'],
        'id_producto': _incluirProducto ? _idProducto : null,
        'motivo': _motivo,
        'descripcion': _descripcionCtrl.text.trim(),
      });
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        _reporteFormKey.currentState?.reset();
        _descripcionCtrl.clear();
        setState(() {
          _vendedor = null;
          _productosVendedor = [];
          _incluirProducto = false;
          _idProducto = null;
          _motivo = null;
          _autovalidate = AutovalidateMode.disabled;
          _versionBuscador++;
        });
        context.showSuccess('Reporte enviado, el equipo de administración lo revisará');
      } else {
        context.showError(ApiClient.detalle(res) ?? 'No se pudo enviar el reporte');
      }
    } catch (_) {
      if (mounted) context.showError('Error de conexión al servidor');
    } finally {
      if (mounted) setState(() => _enviandoReporte = false);
    }
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeRoute: 'Comentarios',
      builder: (context, isMobile) => _cargando
          ? const Center(child: CircularProgressIndicator())
          : PageScroll(
              isMobile: isMobile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    eyebrow: 'TU OPINIÓN NOS IMPORTA',
                    title: 'Comentarios y reportes',
                    titleSize: isMobile ? 28 : 36,
                    subtitle:
                        'Ayúdanos a mejorar Market-Tec o avísanos si tuviste un problema con un vendedor',
                  ),
                  const SizedBox(height: 28),
                  ResponsiveSplit(
                    isMobile: isMobile,
                    left: _buildComentarios(),
                    right: _buildReporte(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildComentarios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.forum_outlined, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Comenta sobre la página',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                  ),
                  InfoHint(
                    'Tus comentarios solo los lee el equipo de Market-Tec. '
                    'Si algo falló, cuéntanos qué estabas haciendo y en qué pantalla',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (nombre, icono, ayuda) in AppConstants.tiposComentarioWeb)
                    Tooltip(
                      message: ayuda,
                      child: ChoiceChip(
                        showCheckmark: false,
                        avatar: Icon(
                          icono,
                          size: 18,
                          color: _tipo == nombre ? Colors.white : AppColors.primary,
                        ),
                        label: Text(nombre),
                        selected: _tipo == nombre,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: _tipo == nombre ? Colors.white : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setState(() => _tipo = nombre),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '¿Qué tal te parece la página? (opcional)',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              StarRatingSelector(
                value: _estrellas,
                size: 32,
                onChanged: (v) => setState(() => _estrellas = v == _estrellas ? 0 : v),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _mensajeCtrl,
                maxLines: 4,
                maxLength: Validators.maxComentario,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(Validators.maxComentario),
                ],
                decoration: AppStyles.outlinedInput(
                  hintText: _tipo == 'Error'
                      ? 'Ej. Al subir la foto del producto me salió un error'
                      : _tipo == 'Sugerencia'
                      ? 'Ej. Estaría bien poder pagar con transferencia'
                      : 'Escribe lo que quieras decirnos',
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                text: 'Enviar comentario',
                icon: Icons.send_rounded,
                onPressed: _enviandoComentario ? null : _enviarComentario,
              ),
            ],
          ),
        ),
        if (_misComentarios.isNotEmpty) ...[
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Lo que nos has enviado',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                for (final c in _misComentarios.take(6)) _buildMiComentario(c),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMiComentario(dynamic c) {
    final estado = '${c['estado'] ?? 'Recibido'}';
    final atendido = estado == 'Atendido';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            c['tipo'] == 'Error'
                ? Icons.bug_report_outlined
                : c['tipo'] == 'Sugerencia'
                ? Icons.lightbulb_outline
                : Icons.chat_bubble_outline,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c['mensaje'] ?? ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatFecha(c['fecha']),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                if ((c['respuesta'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Respuesta: ${c['respuesta']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(
            text: estado,
            textColor: atendido ? Colors.green.shade700 : Colors.blueGrey.shade700,
            backgroundColor: atendido ? Colors.green.shade50 : Colors.blueGrey.shade50,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          ),
        ],
      ),
    );
  }

  Widget _buildReporte() {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _reporteFormKey,
        autovalidateMode: _autovalidate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.report_gmailerrorred, color: AppColors.reportButton),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Reportar a un vendedor',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
                InfoHint(
                  'El reporte es privado: el vendedor no sabe quién lo envió. '
                  'Un administrador lo revisa y puede suspender la cuenta si es necesario',
                  color: Colors.grey.shade600,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildBuscadorVendedor(),
            if (_vendedor != null) ...[
              const SizedBox(height: 12),
              _buildVendedorElegido(),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _incluirProducto,
                title: const Text('Fue por un producto en específico'),
                subtitle: const Text('Opcional'),
                onChanged: (v) => setState(() {
                  _incluirProducto = v ?? false;
                  if (!_incluirProducto) _idProducto = null;
                }),
              ),
              if (_incluirProducto) _buildSelectorProducto(),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _motivo,
              isExpanded: true,
              decoration: AppStyles.outlinedInput(labelText: 'Motivo'),
              items: [
                for (final m in AppConstants.motivosReporte)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m, overflow: TextOverflow.ellipsis),
                  ),
              ],
              validator: (v) => v == null ? 'Elige un motivo' : null,
              onChanged: (v) => setState(() => _motivo = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descripcionCtrl,
              maxLines: 4,
              maxLength: Validators.maxReporte,
              inputFormatters: [
                LengthLimitingTextInputFormatter(Validators.maxReporte),
              ],
              validator: Validators.descripcionReporte,
              decoration: AppStyles.outlinedInput(
                hintText: 'Cuéntanos qué pasó, cuándo y dónde',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _enviandoReporte ? null : _enviarReporte,
              icon: _enviandoReporte
                  ? const ButtonSpinner()
                  : const Icon(Icons.send_rounded, color: Colors.white),
              label: const Text(
                'Enviar reporte',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.reportButton,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuscadorVendedor() {
    return LayoutBuilder(
      builder: (context, c) => Autocomplete<Map<String, dynamic>>(
        key: ValueKey(_versionBuscador),
        displayStringForOption: (v) => '${v['nombre'] ?? ''}',
        optionsBuilder: (texto) {
          final q = texto.text.trim().toLowerCase();
          final todos = _vendedores.map((v) => Map<String, dynamic>.from(v));
          if (q.isEmpty) return todos.take(8);
          return todos.where(
            (v) =>
                '${v['nombre'] ?? ''}'.toLowerCase().contains(q) ||
                '${v['username'] ?? ''}'.toLowerCase().contains(q),
          );
        },
        onSelected: (v) {
          context.cerrarTeclado();
          _elegirVendedor(v);
        },
        fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
          controller: ctrl,
          focusNode: focus,
          decoration: AppStyles.outlinedInput(
            labelText: 'Vendedor',
            hintText: 'Escribe su nombre para buscarlo',
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        optionsViewBuilder: (context, onSelected, opciones) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 280, maxWidth: c.maxWidth),
              child: opciones.isEmpty
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: [
                        for (final v in opciones)
                          ListTile(
                            leading: UserAvatar(
                              nombre: '${v['nombre'] ?? 'V'}',
                              fotoUrl: v['foto_url'],
                              radius: 18,
                            ),
                            title: Text('${v['nombre'] ?? ''}'),
                            subtitle: v['username'] != null
                                ? Text('@${v['username']}')
                                : null,
                            onTap: () => onSelected(v),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVendedorElegido() {
    final v = _vendedor!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          UserAvatar(nombre: '${v['nombre'] ?? 'V'}', fotoUrl: v['foto_url'], radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${v['nombre'] ?? 'Vendedor'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Elegir otro vendedor',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _vendedor = null;
              _incluirProducto = false;
              _idProducto = null;
              _versionBuscador++;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorProducto() {
    if (_cargandoProductos) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      );
    }
    if (_productosVendedor.isEmpty) {
      return Text(
        'Este vendedor no tiene productos publicados',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade600),
      );
    }
    return DropdownButtonFormField<int>(
      value: _productosVendedor.any((p) => p['id'] == _idProducto)
          ? _idProducto
          : null,
      isExpanded: true,
      decoration: AppStyles.outlinedInput(labelText: 'Producto'),
      items: [
        for (final p in _productosVendedor)
          DropdownMenuItem<int>(
            value: p['id'],
            child: Row(
              children: [
                ProductImage(url: p['imagen_url'], width: 32, height: 32, radius: 6),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${p['nombre'] ?? 'Producto'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) => setState(() => _idProducto = v),
    );
  }
}
