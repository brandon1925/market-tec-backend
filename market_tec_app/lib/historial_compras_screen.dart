import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'core/pedido_estado.dart';
import 'core/ui_helpers.dart';
import 'widgets/compra_card.dart';
import 'widgets/widgets.dart';

/// Historial completo de compras con filtros por estado y por fechas.
class HistorialComprasScreen extends StatefulWidget {
  const HistorialComprasScreen({super.key});

  @override
  State<HistorialComprasScreen> createState() => _HistorialComprasScreenState();
}

class _HistorialComprasScreenState extends State<HistorialComprasScreen> {
  List<dynamic> _compras = [];
  bool _cargando = true;
  String _filtro = 'Todos';
  DateTimeRange? _rango;
  final Set<int> _enProceso = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      _compras = await cargarMisCompras(
        estados: PedidoEstadoStyle.filtros[_filtro]!.join(','),
        desde: _rango?.start,
        hasta: _rango?.end,
      );
      // Si el servidor no soporta filtros (endpoint viejo) se filtra aquí.
      final estados = PedidoEstadoStyle.filtros[_filtro]!;
      _compras = _compras.where((c) {
        if (estados.isNotEmpty && !estados.contains(c['estado'])) return false;
        final f = leerFecha(c['fecha']);
        if (_rango != null && f != null) {
          final fin = _rango!.end.add(const Duration(days: 1));
          if (f.isBefore(_rango!.start) || !f.isBefore(fin)) return false;
        }
        return true;
      }).toList();
    } catch (_) {
      if (mounted) context.showError('Sin conexión con el servidor');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirFechas() async {
    final hoy = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoy.year - 2),
      lastDate: hoy,
      initialDateRange: _rango,
      helpText: 'Elige las fechas',
      saveText: 'Aplicar',
    );
    if (rango == null) return;
    setState(() => _rango = rango);
    _cargar();
  }

  Future<void> _cambiarEstado(int idPedido, String nuevoEstado) async {
    if (!_enProceso.add(idPedido)) return;
    setState(() {});
    final ok = await cambiarEstadoCompra(context, idPedido, nuevoEstado);
    _enProceso.remove(idPedido);
    if (ok) {
      await _cargar();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Mi historial de compras',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              _buildFiltros(),
              const Divider(height: 1),
              Expanded(
                child: _cargando
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: _compras.isEmpty
                            ? ListView(
                                children: const [
                                  EmptyState(
                                    icon: Icons.receipt_long_outlined,
                                    title: 'No hay compras con estos filtros',
                                    subtitle: 'Prueba con otro estado u otras fechas',
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _compras.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) => CompraCard(
                                  compra: Map<String, dynamic>.from(_compras[i]),
                                  enProceso: _enProceso.contains(
                                    _compras[i]['id_pedido'],
                                  ),
                                  onCambiarEstado: _cambiarEstado,
                                  onCalificada: _cargar,
                                ),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in PedidoEstadoStyle.filtros.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: _filtro == f,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: _filtro == f ? Colors.white : Colors.grey.shade700,
                        fontWeight: _filtro == f
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      onSelected: (_) {
                        setState(() => _filtro = f);
                        _cargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _elegirFechas,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    _rango == null
                        ? 'Filtrar por fechas'
                        : '${formatFecha(_rango!.start, conHora: false)} al ${formatFecha(_rango!.end, conHora: false)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_rango != null)
                IconButton(
                  tooltip: 'Quitar fechas',
                  onPressed: () {
                    setState(() => _rango = null);
                    _cargar();
                  },
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
