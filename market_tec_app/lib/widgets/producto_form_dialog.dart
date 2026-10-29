import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../core/validators.dart';
import '../globals.dart';
import 'custom_buttons.dart';
import 'user_avatar.dart';

/// Formulario para publicar (producto == null) o editar un producto.
/// Antes eran dos clases casi idénticas: FormularioProductoDialog y
/// FormularioEditarDialog.
class ProductoFormDialog extends StatefulWidget {
  final dynamic producto;
  const ProductoFormDialog({super.key, this.producto});

  bool get esEdicion => producto != null;

  @override
  State<ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends State<ProductoFormDialog>
    with FormSubmitMixin {
  late final TextEditingController _nombreController;
  late final TextEditingController _precioController;
  late final TextEditingController _stockController;
  late final TextEditingController _descripcionController;
  String? _categoriaSeleccionada;
  String? _estadoSeleccionado;

  ImagenElegida? _imagenSeleccionada;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _nombreController = TextEditingController(text: p?['nombre'] ?? '');
    _precioController = TextEditingController(
      text: p == null ? '' : (p['precio'] ?? 0.0).toString(),
    );
    _stockController = TextEditingController(
      text: p == null ? "1" : (p['stock'] ?? 1).toString(),
    );
    _descripcionController = TextEditingController(
      text: p?['descripcion'] ?? '',
    );
    if (p != null) {
      if (AppConstants.categoriasProducto.contains(p['categoria'])) {
        _categoriaSeleccionada = p['categoria'];
      }
      if (AppConstants.estadosProducto.contains(p['estado'])) {
        _estadoSeleccionado = p['estado'];
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _precioController.dispose();
    _stockController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  /// Cámara o galería; la foto se comprime antes de subirla.
  Future<void> _seleccionarImagen() async {
    final imagen = await elegirFoto(context, titulo: 'Foto del producto');
    if (imagen != null) setState(() => _imagenSeleccionada = imagen);
  }

  /// Sube la imagen elegida. Lanza un error si el servidor no regresa una
  /// URL válida, para no publicar el producto con una imagen rota.
  Future<String?> _subirImagen() async {
    if (_imagenSeleccionada == null) return null;
    final url = await ApiClient.uploadImage(
      _imagenSeleccionada!.bytes,
      _imagenSeleccionada!.nombre,
    );
    if (!Validators.esUrlImagen(url)) {
      throw const FormatException('No se pudo subir la imagen');
    }
    return url;
  }

  Future<void> _guardar() async {
    if (!validarFormulario()) return;

    await enviar(
      () async {
        final Map<String, dynamic> productoData = {
          "nombre": _nombreController.text.trim(),
          "precio": double.parse(_precioController.text.trim()),
          "stock": int.parse(_stockController.text.trim()),
          "descripcion": _descripcionController.text.trim(),
          "estado": _estadoSeleccionado ?? 'Nuevo',
          "categoria": _categoriaSeleccionada ?? 'Otros',
        };

        final http.Response response;
        if (widget.esEdicion) {
          final idProducto = widget.producto['id'];
          response = await ApiClient.put('/productos/$idProducto', productoData);
          // Foto nueva: se sube y se guarda con el endpoint nuevo.
          if (response.statusCode == 200 && _imagenSeleccionada != null) {
            final url = await _subirImagen();
            final resImg = await ApiClient.put('/productos/$idProducto/imagen', {
              "imagen_url": url,
            });
            if (resImg.statusCode != 200) {
              throw const FormatException('No se pudo cambiar la foto');
            }
          }
        } else {
          productoData["imagen_url"] = await _subirImagen();
          productoData["vendedor_id"] = currentUserId;
          response = await ApiClient.post('/productos', productoData);
        }

        if (!mounted) return;
        final ok =
            response.statusCode == 200 ||
            (!widget.esEdicion && response.statusCode == 201);
        if (ok) {
          // Se toma el messenger antes de cerrar el diálogo.
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                widget.esEdicion
                    ? '¡Cambios guardados!'
                    : '¡Listo! Tu producto ya está en el catálogo',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          context.showError(
            ApiClient.detalle(response) ??
                'No se pudo guardar (${response.statusCode})',
          );
        }
      },
      onError: (e) => context.showError(
        e is FormatException
            ? '${e.message}, intenta con otra foto'
            : 'Sin conexión con el servidor',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppStyles.dialogShape(),
      title: Text(
        widget.esEdicion ? 'Editar producto' : 'Publicar un producto',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            autovalidateMode: autovalidateMode,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImagePicker(),
                const SizedBox(height: 20),
                _textField(
                  _nombreController,
                  'Nombre del producto *',
                  validator: Validators.nombreProducto,
                  maxLength: 60,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _textField(
                        _precioController,
                        'Precio (\$) *',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: InputFilters.precio,
                        validator: Validators.precio,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _textField(
                        _stockController,
                        'Piezas disponibles *',
                        keyboardType: TextInputType.number,
                        inputFormatters: InputFilters.entero4,
                        // Al publicar se pide al menos 1; al editar se permite 0.
                        validator: (v) => Validators.stock(
                          v,
                          minimo: widget.esEdicion ? 0 : 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _dropdown(
                        label: 'Categoría',
                        value: _categoriaSeleccionada,
                        options: AppConstants.categoriasProducto,
                        onChanged: (val) =>
                            setState(() => _categoriaSeleccionada = val),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _dropdown(
                        label: 'Estado',
                        value: _estadoSeleccionado,
                        options: AppConstants.estadosProducto,
                        onChanged: (val) =>
                            setState(() => _estadoSeleccionado = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descripcionController,
                  maxLines: 3,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      Validators.maxDescripcionProducto,
                    ),
                  ],
                  validator: Validators.descripcionProducto,
                  decoration: const InputDecoration(
                    labelText: 'Descripción corta (opcional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SecondaryButton(
          text: 'Cancelar',
          onPressed: () => Navigator.pop(context),
        ),
        PrimaryButton(
          text: isLoading
              ? 'Guardando'
              : (widget.esEdicion ? 'Guardar cambios' : 'Publicar'),
          onPressed: _guardar, // _guardar ignora los clics mientras guarda
        ),
      ],
    );
  }

  Widget _buildImagePicker() {
    final String? actual = widget.producto?['imagen_url'];
    final Widget vista;
    if (_imagenSeleccionada != null) {
      vista = Image.memory(_imagenSeleccionada!.bytes, fit: BoxFit.contain);
    } else if (Validators.esUrlImagen(actual)) {
      vista = ProductImage(url: actual);
    } else {
      vista = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: 44,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            'Toma o sube una foto',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }
    final hayFoto =
        _imagenSeleccionada != null || Validators.esUrlImagen(actual);

    return GestureDetector(
      onTap: _seleccionarImagen,
      child: Container(
        width: double.infinity,
        height: 170,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            vista,
            if (hayFoto)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_camera, color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Cambiar foto',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: [
        ...?inputFormatters,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
