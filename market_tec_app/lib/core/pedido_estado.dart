import 'package:flutter/material.dart';

/// Etiqueta, colores y explicación corta del estado de un pedido.
class PedidoEstadoStyle {
  final String label;
  final Color color;
  final Color background;

  /// Texto breve que aparece al tocar el ícono de ayuda junto al estado.
  final String ayuda;
  const PedidoEstadoStyle(this.label, this.color, this.background, this.ayuda);

  static bool esEnCamino(String estado) =>
      estado == 'Confirmado' || estado == 'En camino';

  static bool esRechazado(String? estado) =>
      estado == 'Rechazado_Agotado' ||
      estado == 'Rechazado' ||
      estado == 'Cancelado' ||
      estado == 'No entregada';

  /// El chat del pedido sigue abierto mientras la venta no termina.
  static bool chatActivo(String? estado) =>
      estado == null || estado == 'Pendiente' || esEnCamino(estado);

  /// Vista del comprador (Mis Compras en Inicio e historial).
  static PedidoEstadoStyle paraCliente(String estado) {
    if (estado == 'Entregado') {
      return _crear(
        'Entregada',
        Colors.green.shade700,
        'Recibiste tu pedido. Ya puedes calificarlo',
      );
    }
    if (esEnCamino(estado)) {
      return _crear(
        'En camino',
        Colors.blue.shade700,
        'El vendedor aceptó tu pedido. Cuando lo recibas marca "Ya lo recibí"',
      );
    }
    if (estado == 'No entregada') {
      return _crear(
        'No entregada',
        Colors.red.shade700,
        'Reportaste que no recibiste el pedido. Se canceló y no se cobró',
      );
    }
    if (esRechazado(estado)) {
      return _crear(
        'Rechazada',
        Colors.red.shade700,
        'El vendedor no pudo atender tu pedido. Revisa el motivo',
      );
    }
    return _crear(
      'Por confirmar',
      Colors.orange.shade800,
      'Tu pedido está apartado. Falta que el vendedor lo acepte',
    );
  }

  /// Vista del vendedor (Historial de Ventas).
  static PedidoEstadoStyle paraVendedor(String? estado) {
    switch (estado) {
      case 'Confirmado':
      case 'En camino':
        return _crear(
          'Por entregar',
          Colors.blue.shade700,
          'Aceptaste el pedido. Falta que el comprador confirme que lo recibió',
        );
      case 'Entregado':
        return _crear(
          'Entregado',
          Colors.green.shade700,
          'El comprador confirmó que recibió su pedido',
        );
      case 'No entregada':
        return _crear(
          'No entregado',
          Colors.red.shade700,
          'El comprador reportó que no recibió el pedido',
        );
      case 'Rechazado_Agotado':
      case 'Rechazado':
      case 'Cancelado':
        return _crear(
          'Rechazado',
          Colors.red.shade700,
          'Rechazaste este pedido y el stock regresó a tu inventario',
        );
      case 'Pendiente':
        return _crear(
          'Pendiente',
          Colors.orange.shade800,
          'Esperando a que aceptes o rechaces el pedido',
        );
      default:
        return _crear(estado ?? '', Colors.grey.shade700, '');
    }
  }

  static PedidoEstadoStyle _crear(String label, Color color, String ayuda) =>
      PedidoEstadoStyle(label, color, color.withOpacity(0.12), ayuda);

  /// Filtros que se muestran en los historiales: etiqueta → estados reales.
  static const Map<String, List<String>> filtros = {
    'Todos': [],
    'Pendientes': ['Pendiente'],
    'Por entregar': ['Confirmado', 'En camino'],
    'Entregados': ['Entregado'],
    'No entregados': ['No entregada', 'Rechazado_Agotado', 'Rechazado', 'Cancelado'],
  };
}
