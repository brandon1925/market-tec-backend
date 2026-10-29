import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../globals.dart';
import '../login_screen.dart';
import '../mapa_screen.dart';
import '../widgets/chat_pedido_sheet.dart';
import 'api_client.dart';
import 'app_theme.dart';
import 'ui_helpers.dart';

/// Notificaciones de la app y vigilancia de la sesión.
///
/// Cómo funciona:
/// - El backend guarda cada aviso en la tabla `notificaciones` (lo hacen
///   triggers de PostgreSQL cuando hay un pedido nuevo, cuando cambia su
///   estado o cuando llega un mensaje al chat).
/// - Mientras la app está abierta (o en segundo plano y Android no la ha
///   cerrado), cada [_intervalo] se consulta `/usuarios/{id}/sync`. Lo nuevo
///   se muestra como notificación del sistema en Android y como aviso dentro
///   de la página en la web.
/// - La misma consulta trae el estado de la cuenta: si el administrador la
///   suspende, se cierra la sesión al momento.
/// - El recordatorio de "¿sigues compartiendo tu ubicación?" se programa en
///   Android con una alarma, así llega aunque la app esté cerrada.
class NotificacionesService with WidgetsBindingObserver {
  NotificacionesService._();
  static final NotificacionesService instance = NotificacionesService._();

  static const Duration _intervalo = Duration(seconds: 12);
  static const int _idRecordatorioUbicacion = 9001;
  static const Duration duracionUbicacion = Duration(hours: 1);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Últimas notificaciones (para la campanita) y cuántas faltan por leer.
  final ValueNotifier<List<Map<String, dynamic>>> recientes = ValueNotifier([]);
  final ValueNotifier<int> noLeidas = ValueNotifier(0);

  /// id_pedido del chat que está abierto: sus mensajes no se notifican.
  int? chatAbierto;

  Timer? _timer;
  Timer? _timerUbicacion;
  int _ultimaId = 0;
  bool _primeraSync = true;
  bool _sincronizando = false;
  bool _inicializado = false;
  bool _cerrandoSesion = false;

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'market_tec_avisos',
    'Avisos de Market-Tec',
    channelDescription: 'Pedidos, ventas, mensajes y recordatorios',
    importance: Importance.high,
    priority: Priority.high,
    color: AppColors.primary,
  );

  // ==========================================
  // INICIO
  // ==========================================
  Future<void> init() async {
    if (_inicializado) return;
    _inicializado = true;
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) => _alTocar(r.payload),
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _payloadPendiente = launch!.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('No se pudieron iniciar las notificaciones: $e');
    }
  }

  String? _payloadPendiente;

  /// Pide permiso de notificaciones (Android 13+). Se llama al iniciar sesión.
  Future<void> pedirPermiso() async {
    if (kIsWeb) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Permiso de notificaciones: $e');
    }
  }

  /// Arranca la consulta periódica. Se llama después de iniciar sesión.
  void iniciarSesion() {
    _ultimaId = 0;
    _primeraSync = true;
    _cerrandoSesion = false;
    recientes.value = [];
    noLeidas.value = 0;
    _timer?.cancel();
    sincronizar();
    _timer = Timer.periodic(_intervalo, (_) => sincronizar());
    pedirPermiso();
    if (_payloadPendiente != null) {
      final p = _payloadPendiente;
      _payloadPendiente = null;
      Future.delayed(const Duration(seconds: 1), () => _alTocar(p));
    }
  }

  void detener() {
    _timer?.cancel();
    _timer = null;
    _timerUbicacion?.cancel();
    recientes.value = [];
    noLeidas.value = 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app se revisa de inmediato (cuenta bloqueada, avisos).
    if (state == AppLifecycleState.resumed && currentUserId != 0) {
      sincronizar();
    }
  }

  // ==========================================
  // SINCRONIZACIÓN
  // ==========================================
  Future<void> sincronizar() async {
    if (currentUserId == 0 || _sincronizando) return;
    _sincronizando = true;
    try {
      final data = await ApiClient.getMap(
        '/usuarios/$currentUserId/sync?desde=$_ultimaId',
      );
      if (data == null) return;

      final estado = '${data['estado_cuenta'] ?? 'Activa'}';
      if (estado != 'Activa') {
        await cerrarSesion(
          mensaje: estado == 'Suspendida'
              ? 'Tu cuenta fue suspendida por un administrador. Si crees que es un error, acércate a la coordinación'
              : 'Tu cuenta ya no está activa',
        );
        return;
      }

      noLeidas.value = (data['no_leidas'] ?? 0) as int;
      final primera = _primeraSync;
      _primeraSync = false;
      final nuevas = List<Map<String, dynamic>>.from(
        (data['notificaciones'] ?? const []) as List,
      );
      if (nuevas.isEmpty) return;

      for (final n in nuevas) {
        final id = (n['id'] ?? 0) as int;
        if (id > _ultimaId) _ultimaId = id;
      }
      recientes.value = [...nuevas.reversed, ...recientes.value]
          .take(30)
          .toList();

      // En la primera consulta solo se cargan las pendientes, sin avisar
      // una por una (evita una lluvia de notificaciones al entrar).
      if (primera) {
        final sinLeer = nuevas.where((n) => n['leida'] != true).length;
        if (sinLeer > 0) {
          _mostrar(
            0,
            'Tienes $sinLeer avisos nuevos',
            'Toca la campana para verlos',
            null,
          );
        }
        return;
      }

      for (final n in nuevas) {
        if (n['leida'] == true) continue;
        final esDeChatAbierto =
            n['tipo'] == 'chat' && n['id_referencia'] == chatAbierto;
        if (esDeChatAbierto) continue;
        _mostrar(
          n['id'] ?? 0,
          '${n['titulo'] ?? 'Market-Tec'}',
          '${n['cuerpo'] ?? ''}',
          '${n['tipo']}:${n['id_referencia'] ?? ''}',
        );
      }
    } catch (e) {
      debugPrint('Sync: $e');
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> marcarLeidas() async {
    if (currentUserId == 0) return;
    noLeidas.value = 0;
    recientes.value = [
      for (final n in recientes.value) {...n, 'leida': true},
    ];
    try {
      await ApiClient.post('/usuarios/$currentUserId/notificaciones/leidas', {
        "hasta": _ultimaId,
      });
    } catch (_) {}
  }

  void _mostrar(int id, String titulo, String cuerpo, String? payload) {
    if (kIsWeb) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (cuerpo.isNotEmpty)
                      Text(cuerpo, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
          action: payload == null
              ? null
              : SnackBarAction(
                  label: 'Ver',
                  textColor: Colors.white,
                  onPressed: () => _alTocar(payload),
                ),
        ),
      );
      return;
    }
    _plugin
        .show(
          id % 100000,
          titulo,
          cuerpo,
          const NotificationDetails(android: _android),
          payload: payload,
        )
        .catchError((e) => debugPrint('Notificación: $e'));
  }

  /// Acción al tocar una notificación o el botón "Ver".
  void _alTocar(String? payload) {
    final ctx = navigatorKey.currentContext;
    if (payload == null || ctx == null || currentUserId == 0) return;
    final partes = payload.split(':');
    final tipo = partes.first;
    final ref = partes.length > 1 ? int.tryParse(partes[1]) : null;
    if (tipo == 'ubicacion') {
      preguntarSiSigueCompartiendo();
    } else if (tipo == 'chat' && ref != null) {
      ChatPedidoSheet.abrir(ctx, idPedido: ref);
    } else if (tipo == 'pedido' || tipo == 'venta' || tipo == 'compra') {
      if (ref != null) ChatPedidoSheet.abrir(ctx, idPedido: ref);
    }
  }

  // ==========================================
  // RECORDATORIO DE UBICACIÓN
  // ==========================================

  /// Se llama al activar "Compartir mi ubicación".
  Future<void> programarRecordatorioUbicacion() async {
    ubicacionCompartidaDesde = DateTime.now();
    _timerUbicacion?.cancel();
    // Dentro de la app (también funciona en web).
    _timerUbicacion = Timer(duracionUbicacion, preguntarSiSigueCompartiendo);
    if (kIsWeb) return;
    // Alarma de Android: llega aunque la app esté cerrada.
    try {
      await _plugin.zonedSchedule(
        _idRecordatorioUbicacion,
        '¿Sigues vendiendo en el campus?',
        'Tu ubicación lleva 1 hora visible. Toca para seguir compartiéndola o apagarla',
        tz.TZDateTime.now(tz.UTC).add(duracionUbicacion),
        const NotificationDetails(android: _android),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'ubicacion:',
      );
    } catch (e) {
      debugPrint('No se pudo programar el recordatorio: $e');
    }
  }

  Future<void> cancelarRecordatorioUbicacion() async {
    ubicacionCompartidaDesde = null;
    _timerUbicacion?.cancel();
    if (kIsWeb) return;
    try {
      await _plugin.cancel(_idRecordatorioUbicacion);
    } catch (_) {}
  }

  bool _preguntando = false;

  /// Diálogo "¿Seguir compartiendo?" (al cumplirse la hora o al tocar la
  /// notificación).
  Future<void> preguntarSiSigueCompartiendo() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !compartiendoUbicacion || _preguntando) return;
    _preguntando = true;
    final seguir = await showConfirmDialog(
      context: ctx,
      icon: Icons.location_on,
      title: '¿Sigues en el campus?',
      message:
          'Tu ubicación lleva 1 hora visible para los compradores. ¿Quieres seguir compartiéndola otra hora?',
      confirmText: 'Seguir compartiendo',
      confirmColor: AppColors.success,
    );
    _preguntando = false;
    if (seguir) {
      await programarRecordatorioUbicacion();
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Listo, te volvemos a preguntar en 1 hora')),
      );
    } else {
      await dejarDeCompartirUbicacion();
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Dejaste de compartir tu ubicación')),
      );
    }
  }

  Future<void> dejarDeCompartirUbicacion() async {
    compartiendoUbicacion = false;
    await cancelarRecordatorioUbicacion();
    MapaScreen.avisarCambioUbicacion();
    try {
      await ApiClient.put('/ubicacion/$currentUserId', {
        "compartir": false,
        "latitud": null,
        "longitud": null,
      });
    } catch (_) {}
  }

  // ==========================================
  // CIERRE DE SESIÓN
  // ==========================================
  Future<void> cerrarSesion({String? mensaje}) async {
    if (_cerrandoSesion) return;
    _cerrandoSesion = true;
    detener();
    if (compartiendoUbicacion) await dejarDeCompartirUbicacion();
    limpiarUsuario();
    final nav = navigatorKey.currentState;
    nav?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    if (mensaje != null) {
      await Future.delayed(const Duration(milliseconds: 300));
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await showDialog(
          context: ctx,
          builder: (c) => AlertDialog(
            shape: AppStyles.dialogShape(),
            icon: const Icon(Icons.block, color: Colors.red, size: 40),
            title: const Text('Sesión cerrada', textAlign: TextAlign.center),
            content: Text(mensaje, textAlign: TextAlign.center),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    }
  }
}
