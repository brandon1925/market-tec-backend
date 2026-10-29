import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/notificaciones_service.dart';
import '../core/pedido_estado.dart';
import '../core/ui_helpers.dart';
import '../globals.dart';
import 'redes_sociales.dart';
import 'user_avatar.dart';

/// Mini chat entre comprador y vendedor de un pedido. Sirve para quedar de
/// acuerdo en el lugar y la hora de entrega. Se puede escribir mientras la
/// venta no termina; después queda como historial de solo lectura.
class ChatPedidoSheet extends StatefulWidget {
  final int idPedido;
  const ChatPedidoSheet({super.key, required this.idPedido});

  static Future<void> abrir(BuildContext context, {required int idPedido}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChatPedidoSheet(idPedido: idPedido),
    );
  }

  @override
  State<ChatPedidoSheet> createState() => _ChatPedidoSheetState();
}

class _ChatPedidoSheetState extends State<ChatPedidoSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _mensajes = [];
  Map<String, dynamic>? _pedido;
  Timer? _timer;
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  int get _ultimaId => _mensajes.isEmpty ? 0 : (_mensajes.last['id'] ?? 0);

  @override
  void initState() {
    super.initState();
    NotificacionesService.instance.chatAbierto = widget.idPedido;
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (NotificacionesService.instance.chatAbierto == widget.idPedido) {
      NotificacionesService.instance.chatAbierto = null;
    }
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final data = await ApiClient.getMap(
        '/pedidos/${widget.idPedido}/mensajes?desde=$_ultimaId&id_usuario=$currentUserId',
      );
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _cargando = false;
          _error ??= 'No se pudo abrir el chat de este pedido';
        });
        return;
      }
      final nuevos = List<Map<String, dynamic>>.from(
        (data['mensajes'] ?? const []) as List,
      );
      final idsActuales = _mensajes.map((m) => m['id']).toSet();
      setState(() {
        _pedido = Map<String, dynamic>.from(data['pedido'] ?? {});
        _mensajes.addAll(nuevos.where((m) => !idsActuales.contains(m['id'])));
        _cargando = false;
        _error = null;
      });
      if (nuevos.isNotEmpty) _bajar();
    } catch (e) {
      if (mounted && _cargando) {
        setState(() {
          _cargando = false;
          _error = 'Sin conexión con el servidor';
        });
      }
    }
  }

  void _bajar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final res = await ApiClient.post('/pedidos/${widget.idPedido}/mensajes', {
        "id_remitente": currentUserId,
        "mensaje": texto,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        _ctrl.clear();
        await _cargar();
      } else {
        context.showError(
          ApiClient.detalle(res) ?? 'No se pudo enviar el mensaje',
        );
      }
    } catch (_) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  bool get _soyVendedor => _pedido?['id_vendedor'] == currentUserId;

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.82;
    final teclado = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: SizedBox(
        height: alto,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _pedido == null
            ? Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            : Column(
                children: [
                  _buildEncabezado(),
                  const Divider(height: 1),
                  Expanded(child: _buildMensajes()),
                  _buildEntrada(),
                ],
              ),
      ),
    );
  }

  Widget _buildEncabezado() {
    final p = _pedido ?? {};
    final otroNombre = '${_soyVendedor ? p['cliente_nombre'] : p['vendedor_nombre']}';
    final otroFoto = _soyVendedor ? p['cliente_foto'] : p['vendedor_foto'];
    final redes = Map<String, dynamic>.from(
      (_soyVendedor ? p['redes_cliente'] : p['redes_vendedor']) ?? {},
    );
    final estilo = _soyVendedor
        ? PedidoEstadoStyle.paraVendedor(p['estado'])
        : PedidoEstadoStyle.paraCliente('${p['estado'] ?? 'Pendiente'}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(nombre: otroNombre, fotoUrl: otroFoto, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otroNombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Pedido #${p['id_pedido'] ?? widget.idPedido} · ${p['producto'] ?? ''} x${p['cantidad'] ?? 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: estilo.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  estilo.label,
                  style: TextStyle(
                    color: estilo.color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          if (redes.values.any((v) => v != null && '$v'.isNotEmpty)) ...[
            const SizedBox(height: 8),
            RedesSocialesBotones(redes: redes, compacto: true),
          ],
        ],
      ),
    );
  }

  Widget _buildMensajes() {
    if (_mensajes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text(
                'Aún no hay mensajes',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _soyVendedor
                    ? 'Saluda y acuerda con tu cliente dónde y a qué hora entregar'
                    : 'Escríbele al vendedor para quedar de acuerdo en la entrega',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _mensajes.length,
      itemBuilder: (context, i) {
        final m = _mensajes[i];
        final mio = m['id_remitente'] == currentUserId;
        return Align(
          alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mio ? AppColors.primary : Colors.grey.shade100,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mio ? 16 : 4),
                bottomRight: Radius.circular(mio ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: mio
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  '${m['mensaje']}',
                  style: TextStyle(color: mio ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  fechaRelativa(m['fecha']),
                  style: TextStyle(
                    fontSize: 10,
                    color: mio ? Colors.white60 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntrada() {
    final activo = PedidoEstadoStyle.chatActivo(_pedido?['estado']);
    if (!activo) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: Colors.grey.shade50,
        child: Text(
          'La venta terminó, el chat queda solo para consulta',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                onSubmitted: (_) => _enviar(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _enviando ? null : _enviar,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              icon: _enviando
                  ? const ButtonSpinner(size: 18)
                  : const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
