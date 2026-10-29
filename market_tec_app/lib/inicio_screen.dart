import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalogo_screen.dart';
import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/ui_helpers.dart';
import 'globals.dart';
import 'historial_compras_screen.dart';
import 'mapa_screen.dart';
import 'widgets/compra_card.dart';
import 'widgets/widgets.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  /// En Inicio solo se muestran las compras más recientes.
  static const int _maxCompras = 5;

  List<dynamic> _misCompras = [];
  bool _isLoading = true;
  bool _cargandoCompras = false;

  int _estudiantesActivos = 0;
  int _productosVendidos = 0;
  int _carrerasItz = 7;

  static const String _apkDownloadUrl =
      'https://market-tec-itz.duckdns.org/descargar-apk';

  /// Pedidos con una actualización en curso (evita dobles clics).
  final Set<int> _pedidosEnProceso = {};

  @override
  void initState() {
    super.initState();
    _cargarDatosInicio();
  }

  Future<void> _descargarApk() async {
    try {
      final ok = await launchUrl(
        Uri.parse(_apkDownloadUrl),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!ok && mounted) context.showError('No se pudo iniciar la descarga');
    } catch (e) {
      if (mounted) context.showError('No se pudo abrir el enlace de descarga');
    }
  }

  Future<void> _cargarDatosInicio() async {
    setState(() => _isLoading = true);
    try {
      final resStats = await ApiClient.get('/estadisticas/inicio');
      if (resStats.statusCode == 200) {
        final stats = ApiClient.decode(resStats);
        _estudiantesActivos = stats['estudiantes_activos'] ?? 0;
        _productosVendidos = stats['productos_vendidos'] ?? 0;
        _carrerasItz = stats['carreras_itz'] ?? 7;
      }
      _misCompras = await cargarMisCompras(limite: _maxCompras);
    } catch (e) {
      debugPrint('Error cargando inicio: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _recargarCompras() async {
    setState(() => _cargandoCompras = true);
    try {
      _misCompras = await cargarMisCompras(limite: _maxCompras);
    } catch (_) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      if (mounted) setState(() => _cargandoCompras = false);
    }
  }

  Future<void> _cambiarEstado(int idPedido, String nuevoEstado) async {
    if (!_pedidosEnProceso.add(idPedido)) return;
    setState(() {});
    final ok = await cambiarEstadoCompra(context, idPedido, nuevoEstado);
    _pedidosEnProceso.remove(idPedido);
    if (ok) {
      await _recargarCompras();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeRoute: 'Inicio',
      builder: (context, isMobile) => _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatosInicio,
              child: PageScroll(
                isMobile: isMobile,
                verticalPadding: isMobile ? 20 : 36,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHero(isMobile),
                        const SizedBox(height: 24),
                        _buildMisCompras(isMobile),
                        const SizedBox(height: 24),
                        StatCardsRow(
                          isMobile: isMobile,
                          spacing: 20,
                          mobileSpacing: 16,
                          cards: [
                            InlineStatCard(
                              icon: Icons.people_alt_outlined,
                              value: '$_estudiantesActivos',
                              label: 'Estudiantes activos',
                            ),
                            InlineStatCard(
                              icon: Icons.local_mall_outlined,
                              value: '$_productosVendidos',
                              label: 'Ventas en el campus',
                            ),
                            InlineStatCard(
                              icon: Icons.school_outlined,
                              value: '$_carrerasItz',
                              label: 'Carreras conectadas',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildComoFunciona(),
                        if (kIsWeb) ...[
                          const SizedBox(height: 24),
                          DownloadAppCard(isMobile: isMobile),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  static const _heroPadding = EdgeInsets.symmetric(
    horizontal: 22,
    vertical: 16,
  );
  static final _heroShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30),
  );

  Widget _buildHero(bool isMobile) {
    final nombre = currentUserName.split(' ').first;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 24.0 : 44.0),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isMobile
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          StatusBadge(
            text: nombre.isEmpty ? 'COMUNIDAD ITZ' : 'HOLA, ${nombre.toUpperCase()}',
            textColor: Colors.white,
            backgroundColor: Colors.white.withOpacity(0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            radius: 20,
            fontSize: 11,
            letterSpacing: 1.5,
          ),
          const SizedBox(height: 18),
          Text(
            'El marketplace oficial de los estudiantes del ITZ',
            textAlign: isMobile ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 26 : 40,
              fontWeight: FontWeight.w900,
              height: 1.15,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Ese antojo, ese cargador que olvidaste o la asesoría que necesitas, ya lo vende alguien del Tec. Encuéntralo aquí y míralo en el mapa en tiempo real',
            textAlign: isMobile ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: isMobile ? 14 : 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: () => context.irA(const CatalogoScreen()),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: const Text(
                  'Ver qué hay hoy',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: _heroPadding,
                  shape: _heroShape,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => context.irA(const MapaScreen()),
                icon: const Icon(
                  Icons.location_on_outlined,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  '¿Quién vende cerca?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: _heroPadding,
                  shape: _heroShape,
                ),
              ),
              if (kIsWeb)
                ElevatedButton.icon(
                  onPressed: _descargarApk,
                  icon: const Icon(Icons.android, color: Colors.white, size: 18),
                  label: const Text(
                    'Descargar app (APK)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: _heroPadding,
                    shape: _heroShape,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MIS COMPRAS (justo debajo del cuadro principal)
  // ==========================================
  Widget _buildMisCompras(bool isMobile) {
    return AppCard(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      shadow: AppCard.softShadow(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader(
                  eyebrow: 'SEGUIMIENTO',
                  eyebrowSize: 11,
                  eyebrowSpacing: 1.2,
                  title: 'Mis compras',
                  titleSize: 22,
                  titleColor: null,
                  titleLetterSpacing: null,
                ),
              ),
              const InfoHint(
                'Aquí ves tus últimos 5 pedidos. Toca el ícono (?) de cada estado para saber qué significa',
              ),
              IconButton(
                onPressed: _cargandoCompras ? null : _recargarCompras,
                tooltip: 'Actualizar',
                icon: _cargandoCompras
                    ? const ButtonSpinner(size: 18, color: AppColors.primary)
                    : const Icon(Icons.refresh, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sigue tus pedidos, platica con el vendedor y califica lo que recibiste',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_misCompras.isEmpty)
            EmptyState(
              icon: Icons.shopping_bag_outlined,
              iconSize: 52,
              title: 'Todavía no has comprado nada',
              subtitle: 'Date una vuelta por el catálogo, seguro algo se te antoja',
              padding: const EdgeInsets.symmetric(vertical: 24),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                // En pantallas anchas se acomodan en 2 columnas.
                final columnas = c.maxWidth > 760 ? 2 : 1;
                final ancho = (c.maxWidth - (columnas - 1) * 16) / columnas;
                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    for (final compra in _misCompras.take(_maxCompras))
                      SizedBox(
                        width: ancho,
                        child: CompraCard(
                          compra: Map<String, dynamic>.from(compra),
                          enProceso: _pedidosEnProceso.contains(
                            compra['id_pedido'],
                          ),
                          onCambiarEstado: _cambiarEstado,
                          onCalificada: _recargarCompras,
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                await context.abrir(const HistorialComprasScreen());
                _recargarCompras();
              },
              icon: const Icon(Icons.history),
              label: const Text(
                'Ver todo mi historial',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _pasos = [
    (
      'Elige lo que se te antoje',
      'Busca en el catálogo, aparta las piezas que quieras y listo',
    ),
    (
      'Ponte de acuerdo con el vendedor',
      'Cuando acepte tu pedido, usa el chat para quedar en el lugar y la hora',
    ),
    (
      'Recibe y califica',
      'Marca "Ya lo recibí" y deja tus estrellas para ayudar a otros',
    ),
  ];

  Widget _buildComoFunciona() {
    return AppCard(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Así de fácil funciona',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          for (final (i, (titulo, detalle)) in _pasos.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            _buildStepItem('${i + 1}', titulo, detalle),
          ],
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.primary,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
