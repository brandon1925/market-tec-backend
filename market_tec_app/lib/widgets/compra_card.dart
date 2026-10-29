import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/pedido_estado.dart';
import '../core/ui_helpers.dart';
import '../core/validators.dart';
import '../globals.dart';
import 'app_card.dart';
import 'chat_pedido_sheet.dart';
import 'info_hint.dart';
import 'star_rating.dart';
import 'status_badge.dart';
import 'user_avatar.dart';

/// Tarjeta de una compra (Inicio y Historial de compras).
class CompraCard extends StatelessWidget {
  final Map<String, dynamic> compra;
  final bool enProceso;
  final void Function(int idPedido, String nuevoEstado) onCambiarEstado;
  final VoidCallback onCalificada;

  const CompraCard({
    super.key,
    required this.compra,
    required this.enProceso,
    required this.onCambiarEstado,
    required this.onCalificada,
  });

  @override
  Widget build(BuildContext context) {
    final String estadoRaw = '${compra['estado'] ?? 'Pendiente'}';
    final estilo = PedidoEstadoStyle.paraCliente(estadoRaw);
    final bool yaCalificado = compra['ya_calificado'] == true;
    final int idPedido = compra['id_pedido'];
    final String? motivo = compra['motivo_rechazo'];

    return AppCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProductImage(
                url: compra['imagen_url'],
                width: 60,
                height: 60,
                radius: 10,
                cover: true,
              ),
              const SizedBox(width: 12),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          radius: 8,
                          fontSize: 11,
                        ),
                        InfoHint(estilo.ayuda, size: 15),
                        const Spacer(),
                        Text(
                          '\$${compra['total']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${compra['producto_nombre']} (x${compra['cantidad']})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        '${compra['vendedor_nombre'] ?? ''}',
                        if (compra['fecha'] != null)
                          formatFecha(compra['fecha'], conHora: false),
                      ].join(' · '),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (PedidoEstadoStyle.esRechazado(estadoRaw) &&
              motivo != null &&
              motivo.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Motivo: $motivo',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          ],
          if (PedidoEstadoStyle.chatActivo(estadoRaw)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    ChatPedidoSheet.abrir(context, idPedido: idPedido),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Chat con el vendedor'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
          if (PedidoEstadoStyle.esEnCamino(estadoRaw)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: enProceso
                        ? null
                        : () => onCambiarEstado(idPedido, 'No entregada'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text(
                      'No me llegó',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: enProceso
                        ? null
                        : () => onCambiarEstado(idPedido, 'Entregado'),
                    icon: const Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Ya lo recibí',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const InfoHint(
                  'Toca "Ya lo recibí" cuando tengas tu producto. Si el vendedor no llegó toca "No me llegó" y el pedido se cancela',
                ),
              ],
            ),
          ],
          if (estadoRaw == 'Entregado') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: yaCalificado
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '★ Ya calificaste este producto',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.amber.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await mostrarCalificarDialog(
                          context,
                          idProducto: compra['id_producto'],
                          nombreProducto: '${compra['producto_nombre']}',
                        );
                        if (ok) onCalificada();
                      },
                      icon: const Icon(Icons.star, color: Colors.amber, size: 16),
                      label: const Text(
                        'Calificar producto',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withOpacity(0.3),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Diálogo de estrellas + comentario. Regresa true si se publicó.
Future<bool> mostrarCalificarDialog(
  BuildContext context, {
  required int idProducto,
  required String nombreProducto,
}) async {
  int rating = 5;
  final comentarioCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool enviando = false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateModal) => AlertDialog(
        shape: AppStyles.dialogShape(),
        title: Text(
          '¿Qué tal estuvo "$nombreProducto"?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tu opinión ayuda a otros estudiantes a comprar mejor',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 12),
                StarRatingSelector(
                  value: rating,
                  alignment: MainAxisAlignment.center,
                  onChanged: (v) => setStateModal(() => rating = v),
                ),
                const SizedBox(height: 12),
                Form(
                  key: formKey,
                  child: TextFormField(
                    controller: comentarioCtrl,
                    maxLines: 3,
                    validator: (v) => Validators.comentario(v, opcional: true),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(Validators.maxComentario),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Cuéntanos más (opcional)',
                      hintText: 'Ej. Llegó a tiempo y muy rico',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogCancelButton(onPressed: () => Navigator.pop(context, false)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: enviando
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setStateModal(() => enviando = true);
                    try {
                      final res = await ApiClient.post('/resenas', {
                        "id_producto": idProducto,
                        "id_cliente": currentUserId,
                        "calificacion": rating,
                        "comentario": comentarioCtrl.text.trim(),
                      });
                      if (!context.mounted) return;
                      if (res.statusCode == 200) {
                        Navigator.pop(context, true);
                        return;
                      }
                      context.showError('No se pudo publicar tu opinión');
                    } catch (_) {
                      if (context.mounted) {
                        context.showError('Sin conexión con el servidor');
                      }
                    }
                    if (context.mounted) setStateModal(() => enviando = false);
                  },
            child: enviando
                ? const ButtonSpinner(size: 18)
                : const Text('Publicar opinión'),
          ),
        ],
      ),
    ),
  );
  comentarioCtrl.dispose();
  if (ok == true && context.mounted) {
    context.showSuccess('¡Gracias por tu opinión!');
  }
  return ok == true;
}

/// Confirma (si hace falta) y cambia el estado de una compra.
/// Regresa true si el servidor aceptó el cambio.
Future<bool> cambiarEstadoCompra(
  BuildContext context,
  int idPedido,
  String nuevoEstado,
) async {
  if (nuevoEstado == 'No entregada' &&
      !await showConfirmDialog(
        context: context,
        icon: Icons.report_gmailerrorred,
        title: '¿No te llegó el pedido?',
        message:
            'El pedido se cancela y las piezas regresan al vendedor. Esto no se puede deshacer',
        confirmText: 'Sí, no me llegó',
        confirmColor: Colors.red,
      )) {
    return false;
  }
  try {
    final res = await ApiClient.put('/pedidos/$idPedido/estado', {
      "nuevo_estado": nuevoEstado,
    });
    if (!context.mounted) return false;
    if (res.statusCode == 200) {
      final entregado = nuevoEstado == 'Entregado';
      context.showSnack(
        entregado
            ? '¡Qué bien! Ya puedes calificar tu compra'
            : 'Listo, reportamos que no te llegó el pedido',
        color: entregado ? Colors.green.shade700 : Colors.orange.shade800,
      );
      return true;
    }
    context.showError('No se pudo actualizar el pedido');
  } catch (_) {
    if (context.mounted) context.showError('Sin conexión con el servidor');
  }
  return false;
}

/// Compras del usuario actual. Usa el endpoint nuevo (con fecha, motivo de
/// rechazo y filtros) y si el servidor aún no lo tiene, el anterior.
Future<List<dynamic>> cargarMisCompras({
  int? limite,
  String? estados,
  DateTime? desde,
  DateTime? hasta,
}) async {
  final params = <String, String>{
    if (limite != null) 'limite': '$limite',
    if (estados != null && estados.isNotEmpty) 'estados': estados,
    if (desde != null) 'desde': desde.toIso8601String().substring(0, 10),
    if (hasta != null) 'hasta': hasta.toIso8601String().substring(0, 10),
  };
  final query = Uri(queryParameters: params).query;
  final v2 = await ApiClient.getList(
    '/v2/mis-compras/$currentUserId${query.isEmpty ? '' : '?$query'}',
  );
  if (v2 != null) return v2;
  final viejas = await ApiClient.getList('/mis-compras/$currentUserId') ?? [];
  return limite == null ? viejas : viejas.take(limite).toList();
}
