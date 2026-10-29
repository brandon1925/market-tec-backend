import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'catalogo_screen.dart';
import 'core/api_client.dart';
import 'core/app_theme.dart';
import 'core/notificaciones_service.dart';
import 'core/ui_helpers.dart';
import 'globals.dart';
import 'widgets/vendedor_widgets.dart';
import 'widgets/widgets.dart';

class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  /// Avisa a la pantalla del mapa (si está abierta) que cambió el estado de
  /// "compartir ubicación" desde fuera (recordatorio de 1 hora, cierre de
  /// sesión...).
  static final ValueNotifier<int> cambiosUbicacion = ValueNotifier(0);
  static void avisarCambioUbicacion() => cambiosUbicacion.value++;

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  bool _procesandoUbicacion = false; // evita encender/apagar dos veces seguidas
  bool _actualizando = false;
  final MapController _mapController = MapController();
  Timer? _timerRefresco;

  // Centro del mapa: un poco al norte de la cancha, sobre los edificios y el
  // estacionamiento del ITZ. Para moverlo: clic derecho en Google Maps →
  // copiar coordenadas.
  static const LatLng _itzLocation = LatLng(18.6527, -99.1838);
  static const double _zoomInicial = 17.3;
  static const Duration _intervaloRefresco = Duration(seconds: 20);

  // Área a la que se limita la cámara (~1.5 km alrededor del campus).
  static final LatLngBounds _limitesCampus = LatLngBounds(
    const LatLng(18.6359, -99.1999),
    const LatLng(18.6679, -99.1679),
  );

  LatLng _miUbicacionActual = _itzLocation;
  double _zoom = _zoomInicial;

  Map<String, dynamic>? _vendedorSeleccionado;
  List<dynamic> _vendedoresActivos = [];
  DateTime? _ultimaActualizacion;

  bool get _compartir => compartiendoUbicacion;

  @override
  void initState() {
    super.initState();
    MapaScreen.cambiosUbicacion.addListener(_alCambiarUbicacionFuera);
    _cargarVendedoresActivos();
    // El mapa se actualiza solo cada 20 segundos.
    _timerRefresco = Timer.periodic(
      _intervaloRefresco,
      (_) => _cargarVendedoresActivos(),
    );
  }

  @override
  void dispose() {
    _timerRefresco?.cancel();
    MapaScreen.cambiosUbicacion.removeListener(_alCambiarUbicacionFuera);
    super.dispose();
  }

  void _alCambiarUbicacionFuera() {
    if (mounted) setState(() {});
    _cargarVendedoresActivos();
  }

  /// Horario en que el mapa muestra vendedores: lunes a viernes, 6 am a 9 pm
  /// (igual que los turnos de venta).
  bool _esHorarioPermitido() {
    final ahora = DateTime.now();
    if (ahora.weekday > 5) return false;
    return ahora.hour >= AppConstants.horaMinimaTurno &&
        ahora.hour < AppConstants.horaMaximaTurno;
  }

  Future<void> _cargarVendedoresActivos({bool manual = false}) async {
    if (!_esHorarioPermitido()) {
      if (mounted) setState(() => _vendedoresActivos = []);
      if (manual && mounted) {
        context.showSnack('El mapa solo muestra vendedores de lunes a viernes de 6 am a 9 pm');
      }
      return;
    }
    if (_actualizando) return;
    if (manual) setState(() => _actualizando = true);
    try {
      // Endpoint nuevo (incluye foto) o el anterior.
      var lista = await ApiClient.getList('/v2/ubicaciones/activas');
      lista ??= await ApiClient.getList('/ubicaciones/activas');
      if (lista != null && mounted) {
        setState(() {
          _vendedoresActivos = lista!;
          _ultimaActualizacion = DateTime.now();
          // Si yo aparezco en la lista, mi switch debe estar encendido.
          final yo = lista.where((v) => v['id'] == currentUserId);
          if (yo.isNotEmpty && !compartiendoUbicacion) {
            compartiendoUbicacion = true;
            final v = yo.first;
            if (v['latitud'] is num && v['longitud'] is num) {
              _miUbicacionActual = LatLng(
                (v['latitud'] as num).toDouble(),
                (v['longitud'] as num).toDouble(),
              );
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error al cargar vendedores: $e");
      if (manual && mounted) context.showError('No se pudo actualizar el mapa');
    } finally {
      if (mounted && manual) setState(() => _actualizando = false);
    }
  }

  Future<void> _guardarUbicacionEnBD(
    bool compartir, {
    double? lat,
    double? lng,
  }) async {
    try {
      await ApiClient.put('/ubicacion/$currentUserId', {
        "compartir": compartir,
        "latitud": lat,
        "longitud": lng,
      });
    } catch (e) {
      debugPrint("Error guardando ubicación: $e");
    }
  }

  Future<void> _intentarCompartirUbicacion(bool valor) async {
    if (_procesandoUbicacion) return;
    setState(() => _procesandoUbicacion = true);
    try {
      await _cambiarCompartirUbicacion(valor);
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
      if (mounted) {
        setState(() => compartiendoUbicacion = false);
        context.showError('No pudimos obtener tu ubicación, revisa el GPS');
      }
    } finally {
      if (mounted) setState(() => _procesandoUbicacion = false);
    }
  }

  Future<void> _cambiarCompartirUbicacion(bool valor) async {
    if (!valor) {
      await NotificacionesService.instance.dejarDeCompartirUbicacion();
      if (mounted) {
        setState(() {});
        context.showSnack('Dejaste de compartir tu ubicación');
      }
      _cargarVendedoresActivos();
      return;
    }

    if (!_esHorarioPermitido()) {
      _mostrarDialogoFueraDeHorario();
      return;
    }

    final bool confirmar = await showConfirmDialog(
      context: context,
      title: '¿Compartir tu ubicación?',
      icon: Icons.location_on,
      message:
          'Los compradores verán en el mapa dónde estás para encontrarte fácil.\n\n'
          'En 1 hora te mandaremos una notificación para preguntarte si quieres seguir compartiéndola',
      confirmText: 'Sí, compartir',
      confirmColor: AppColors.success,
    );
    if (!confirmar || !mounted) return;
    if (!await _obtenerUbicacionReal()) return;

    await NotificacionesService.instance.pedirPermiso();
    await NotificacionesService.instance.programarRecordatorioUbicacion();
    _cargarVendedoresActivos();
    if (mounted) {
      context.showSnack(
        '¡Listo! Ya apareces en el mapa. Te avisamos en 1 hora',
        color: Colors.green.shade800,
      );
    }
  }

  void _mostrarDialogoFueraDeHorario() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: AppStyles.dialogShape(),
        icon: const Icon(
          Icons.access_time_filled,
          color: Colors.orange,
          size: 36,
        ),
        title: const Text('Fuera de horario', textAlign: TextAlign.center),
        content: const Text(
          'Por seguridad solo puedes compartir tu ubicación dentro del ITZ, de lunes a viernes de 6:00 am a 9:00 pm',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Entendido',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Regresa true si la ubicación quedó compartida.
  Future<bool> _obtenerUbicacionReal() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) context.showSnack('Enciende el GPS de tu celular');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        context.showSnack('Necesitamos permiso de ubicación para mostrarte');
      }
      return false;
    }

    if (!kIsWeb) {
      final Position? ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) {
        final p = LatLng(ultima.latitude, ultima.longitude);
        if (_limitesCampus.contains(p)) _moverA(p);
      }
    }

    final Position pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    final punto = LatLng(pos.latitude, pos.longitude);
    if (!_limitesCampus.contains(punto)) {
      if (mounted) {
        context.showError(
          'Parece que no estás en el ITZ. Solo puedes compartir tu ubicación dentro del campus',
        );
      }
      await _guardarUbicacionEnBD(false);
      return false;
    }
    if (!mounted) return false;

    setState(() {
      _miUbicacionActual = punto;
      compartiendoUbicacion = true;
    });
    _moverA(punto);
    await _guardarUbicacionEnBD(true, lat: punto.latitude, lng: punto.longitude);
    return true;
  }

  void _moverA(LatLng punto, [double? zoom]) {
    try {
      _mapController.move(punto, zoom ?? _zoomInicial);
    } catch (_) {}
  }

  void _seleccionarVendedor(dynamic v) {
    setState(() => _vendedorSeleccionado = Map<String, dynamic>.from(v));
  }

  // ==========================================
  // AGRUPACIÓN DE TIENDAS CERCANAS
  // ==========================================

  /// Junta las tiendas que en pantalla quedarían a menos de [radioPx]
  /// pixeles entre sí, para que no se encimen.
  List<List<dynamic>> _agrupar(List<dynamic> vendedores, {double radioPx = 46}) {
    final escala = 256 * math.pow(2, _zoom);
    math.Point<double> px(dynamic v) {
      final lat = (v['latitud'] as num).toDouble() * math.pi / 180;
      final lng = (v['longitud'] as num).toDouble();
      final x = (lng + 180) / 360 * escala;
      final y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * escala;
      return math.Point(x, y);
    }

    final grupos = <(math.Point<double>, List<dynamic>)>[];
    for (final v in vendedores) {
      final p = px(v);
      final idx = grupos.indexWhere((g) => g.$1.distanceTo(p) < radioPx);
      if (idx == -1) {
        grupos.add((p, [v]));
      } else {
        grupos[idx].$2.add(v);
      }
    }
    return grupos.map((g) => g.$2).toList();
  }

  LatLng _centro(List<dynamic> grupo) {
    final lat = grupo.fold<double>(0, (s, v) => s + (v['latitud'] as num)) / grupo.length;
    final lng = grupo.fold<double>(0, (s, v) => s + (v['longitud'] as num)) / grupo.length;
    return LatLng(lat, lng);
  }

  /// Al tocar un globo: se acerca el mapa y aparece la lista de tiendas para
  /// elegir cualquiera fácilmente.
  void _abrirGrupo(List<dynamic> grupo) {
    _moverA(_centro(grupo), math.min(_zoom + 1.5, 18.5));
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${grupo.length} tiendas en este punto',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: grupo.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final v = grupo[i];
                  return ListTile(
                    leading: UserAvatar(
                      nombre: '${v['nombre'] ?? 'V'}',
                      fotoUrl: v['foto_url'],
                    ),
                    title: Text(
                      '${v['nombre'] ?? 'Vendedor'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${v['producto'] ?? 'Productos variados'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      _seleccionarVendedor(v);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PANTALLA
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeRoute: 'Mapa',
      builder: (context, isMobile) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SectionHeader(
                        eyebrow: 'PUNTOS DE VENTA ITZ',
                        title: '¿Quién vende cerca?',
                        titleSize: isMobile ? 26 : 36,
                        subtitle: 'Mira en vivo dónde están los vendedores del campus y ve directo a su tienda',
                        subtitleStyle: TextStyle(
                          fontSize: isMobile ? 13 : 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ResponsiveSplit(
                  isMobile: isMobile,
                  leftFlex: 7,
                  rightFlex: 3,
                  mobileSpacing: 16,
                  mobileCrossAxisAlignment: CrossAxisAlignment.stretch,
                  left: _buildMapArea(isMobile),
                  right: _buildRightPanel(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapArea(bool isMobile) {
    final visibles = _vendedoresActivos
        .where(
          (v) =>
              v['id'] != currentUserId &&
              v['latitud'] is num &&
              v['longitud'] is num,
        )
        .toList();
    final grupos = _agrupar(visibles);

    return Container(
      height: isMobile ? 420 : 560,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _itzLocation,
              initialZoom: _zoomInicial,
              minZoom: 15.0,
              maxZoom: 18.5,
              cameraConstraint: CameraConstraint.contain(bounds: _limitesCampus),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (camera, _) {
                // Se reagrupan las tiendas solo cuando cambia el zoom.
                if ((camera.zoom - _zoom).abs() > 0.2) {
                  setState(() => _zoom = camera.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.market_tec.app',
                keepBuffer: 5,
              ),
              MarkerLayer(
                markers: [
                  for (final g in grupos)
                    g.length == 1
                        ? Marker(
                            point: _centro(g),
                            width: 54,
                            height: 54,
                            child: GestureDetector(
                              onTap: () => _seleccionarVendedor(g.first),
                              child: _VendedorPin(
                                vendedor: g.first,
                                seleccionado:
                                    _vendedorSeleccionado?['id'] == g.first['id'],
                              ),
                            ),
                          )
                        : Marker(
                            point: _centro(g),
                            width: 58,
                            height: 58,
                            child: GestureDetector(
                              onTap: () => _abrirGrupo(g),
                              child: _GrupoPin(cantidad: g.length),
                            ),
                          ),
                ],
              ),
              if (_compartir)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _miUbicacionActual,
                      width: 60,
                      height: 60,
                      child: const _MiUbicacionPin(),
                    ),
                  ],
                ),
            ],
          ),
          // Contador de vendedores
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(8, visibles.isEmpty ? Colors.grey : Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    visibles.length == 1
                        ? '1 vendedor activo'
                        : '${visibles.length} vendedores activos',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          // Botones: actualizar y centrar
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                _botonMapa(
                  tooltip: 'Actualizar mapa',
                  icon: Icons.refresh,
                  cargando: _actualizando,
                  onTap: () => _cargarVendedoresActivos(manual: true),
                ),
                const SizedBox(height: 8),
                _botonMapa(
                  tooltip: 'Centrar mapa',
                  icon: Icons.my_location,
                  onTap: () => _moverA(_compartir ? _miUbicacionActual : _itzLocation),
                ),
              ],
            ),
          ),
          if (_ultimaActualizacion != null)
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Se actualiza solo · ${hora12('${_ultimaActualizacion!.hour}:${_ultimaActualizacion!.minute}')}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _botonMapa({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    bool cargando = false,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: cargando ? null : onTap,
        icon: cargando
            ? const ButtonSpinner(size: 18, color: AppColors.primary)
            : Icon(icon, color: AppColors.primary),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (esVendedor) ...[_buildMiUbicacionCard(), const SizedBox(height: 16)],
        if (_vendedorSeleccionado != null)
          VendedorInfoCard(
            key: ValueKey(_vendedorSeleccionado!['id']),
            idVendedor: _vendedorSeleccionado!['id'],
            nombre: '${_vendedorSeleccionado!['nombre'] ?? 'Vendedor'}',
            fotoUrl: _vendedorSeleccionado!['foto_url'],
            onCerrar: () => setState(() => _vendedorSeleccionado = null),
            accion: PrimaryButton(
              text: 'Ver catálogo del vendedor',
              icon: Icons.storefront_outlined,
              onPressed: () => context.irA(
                CatalogoScreen(
                  vendedorId: _vendedorSeleccionado!['id'],
                  vendedorNombre: '${_vendedorSeleccionado!['nombre']}',
                ),
              ),
            ),
          )
        else
          AppCard(
            child: EmptyState(
              icon: Icons.touch_app_outlined,
              iconGap: 12,
              title: 'Toca una tienda del mapa',
              subtitle: 'Verás quién es, cómo contactarlo y lo que vende. Los globos con número agrupan varias tiendas',
              padding: const EdgeInsets.all(24),
            ),
          ),
      ],
    );
  }

  Widget _buildMiUbicacionCard() {
    return AppCard(
      padding: const EdgeInsets.all(20),
      shadow: AppCard.softShadow(dy: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on, color: AppColors.success),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EyebrowText('MI UBICACIÓN', fontSize: 11, letterSpacing: 1),
                    SizedBox(height: 2),
                    Text(
                      'Aparecer en el mapa',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
              _procesandoUbicacion
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: ButtonSpinner(size: 20, color: AppColors.success),
                    )
                  : Switch(
                      value: _compartir,
                      onChanged: _intentarCompartirUbicacion,
                    ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _compartir ? Colors.green.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _compartir
                  ? 'Los compradores te ven en el mapa · Te avisaremos en 1 hora'
                  : 'Enciéndelo cuando estés vendiendo en el campus',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _compartir ? Colors.green.shade800 : Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Pin con la foto del vendedor (o ícono de tienda).
class _VendedorPin extends StatelessWidget {
  final dynamic vendedor;
  final bool seleccionado;
  const _VendedorPin({required this.vendedor, required this.seleccionado});

  @override
  Widget build(BuildContext context) {
    final foto = vendedor['foto_url'];
    return Center(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: seleccionado ? Colors.orange : AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: foto is String && foto.startsWith('http')
            ? UserAvatar(nombre: '${vendedor['nombre']}', fotoUrl: foto, radius: 18)
            : const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.storefront, color: Colors.white, size: 22),
              ),
      ),
    );
  }
}

/// Globo con el número de tiendas que están muy juntas.
class _GrupoPin extends StatelessWidget {
  final int cantidad;
  const _GrupoPin({required this.cantidad});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.25),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront, color: Colors.white, size: 14),
            Text(
              '$cantidad',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Punto verde con etiqueta "Tú" para la ubicación propia.
class _MiUbicacionPin extends StatelessWidget {
  const _MiUbicacionPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Tú',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
