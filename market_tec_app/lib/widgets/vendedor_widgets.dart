import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import 'redes_sociales.dart';
import 'user_avatar.dart';

/// Texto de un turno: "7:00 am a 9:00 am".
String rangoTurno(dynamic t) => '${hora12(t['inicio'])} a ${hora12(t['fin'])}';

/// Nombre del día (1 = lunes ... 5 = viernes).
String nombreDia(dynamic dia) {
  final d = (dia is int ? dia : int.tryParse('$dia') ?? 1) - 1;
  return d >= 0 && d < AppConstants.diasNombres.length
      ? AppConstants.diasNombres[d]
      : 'Día $dia';
}

/// Fila horizontal con los vendedores del campus (foto + nombre). Al tocar
/// uno se filtra el catálogo con sus productos.
class VendedoresStrip extends StatelessWidget {
  final List<dynamic> vendedores;
  final int? seleccionado;
  final ValueChanged<int?> onSeleccionar;

  const VendedoresStrip({
    super.key,
    required this.vendedores,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    if (vendedores.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: vendedores.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final v = vendedores[i];
          final activo = v['id'] == seleccionado;
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSeleccionar(activo ? null : v['id']),
            child: SizedBox(
              width: 72,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: activo ? AppColors.primary : Colors.grey.shade200,
                        width: activo ? 3 : 1.5,
                      ),
                    ),
                    child: UserAvatar(
                      nombre: '${v['nombre'] ?? 'V'}',
                      fotoUrl: v['foto_url'],
                      radius: 26,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${v['nombre'] ?? ''}'.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: activo ? FontWeight.bold : FontWeight.w500,
                      color: activo ? AppColors.primary : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tarjeta con la información de un vendedor: foto, redes sociales y
/// horario de entrega. Se usa en el catálogo filtrado y en el mapa.
class VendedorInfoCard extends StatefulWidget {
  final int idVendedor;
  final String nombre;
  final String? fotoUrl;
  final VoidCallback? onCerrar;
  final Widget? accion;

  const VendedorInfoCard({
    super.key,
    required this.idVendedor,
    required this.nombre,
    this.fotoUrl,
    this.onCerrar,
    this.accion,
  });

  @override
  State<VendedorInfoCard> createState() => _VendedorInfoCardState();
}

class _VendedorInfoCardState extends State<VendedorInfoCard> {
  Map<String, dynamic>? _detalle;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant VendedorInfoCard old) {
    super.didUpdateWidget(old);
    if (old.idVendedor != widget.idVendedor) {
      _detalle = null;
      _cargar();
    }
  }

  Future<void> _cargar() async {
    try {
      final d = await ApiClient.getMap('/vendedores/${widget.idVendedor}');
      if (mounted) setState(() => _detalle = d ?? {});
    } catch (_) {
      if (mounted) setState(() => _detalle = {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detalle ?? {};
    final redes = Map<String, dynamic>.from(d['redes'] ?? {});
    final horarios = List<dynamic>.from(d['horarios'] ?? const []);
    final nombre = '${d['nombre'] ?? widget.nombre}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(
                nombre: nombre,
                fotoUrl: d['foto_url'] ?? widget.fotoUrl,
                radius: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (d['username'] != null)
                      Text(
                        '@${d['username']}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.onCerrar != null)
                IconButton(
                  tooltip: 'Ver todos los productos',
                  onPressed: widget.onCerrar,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_detalle == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            )
          else ...[
            if (redes.values.any((v) => v != null && '$v'.isNotEmpty)) ...[
              const SizedBox(height: 12),
              RedesSocialesBotones(redes: redes, compacto: true),
            ],
            if (horarios.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildHorarios(horarios),
            ],
          ],
          if (widget.accion != null) ...[
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: widget.accion!),
          ],
        ],
      ),
    );
  }

  Widget _buildHorarios(List<dynamic> horarios) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cuándo y dónde entrega',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (final t in horarios.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      nombreDia(t['dia']),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      [
                        rangoTurno(t),
                        if ((t['modalidad'] ?? '').toString().isNotEmpty)
                          t['modalidad'],
                        if ((t['punto_entrega'] ?? '').toString().isNotEmpty)
                          t['punto_entrega'],
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
