import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Cliente HTTP único para el backend FastAPI.
/// El servidor se elige al compilar con `--dart-define=API_URL=...`
/// (ver [AppConfig.apiUrl]).
class ApiClient {
  ApiClient._();

  static const String baseUrl = AppConfig.apiUrl;

  static const Map<String, String> _jsonHeaders = {
    "Content-Type": "application/json",
  };

  static const Duration _timeout = Duration(seconds: 20);

  static Uri uri(String path) => Uri.parse('$baseUrl$path');

  static Future<http.Response> get(String path) =>
      http.get(uri(path)).timeout(_timeout);

  static Future<http.Response> post(String path, Object body) => http
      .post(uri(path), headers: _jsonHeaders, body: json.encode(body))
      .timeout(_timeout);

  /// Si [body] es null se manda un PUT vacío (como en /productos/{id}/pausar).
  static Future<http.Response> put(String path, [Object? body]) {
    if (body == null) return http.put(uri(path)).timeout(_timeout);
    return http
        .put(uri(path), headers: _jsonHeaders, body: json.encode(body))
        .timeout(_timeout);
  }

  static Future<http.Response> delete(String path) =>
      http.delete(uri(path)).timeout(_timeout);

  /// Decodifica el cuerpo JSON de una respuesta (respetando acentos).
  static dynamic decode(http.Response response) =>
      json.decode(utf8.decode(response.bodyBytes));

  /// Mensaje de error que manda FastAPI en `detail`, si lo hay.
  static String? detalle(http.Response response) {
    try {
      final d = decode(response);
      if (d is Map && d['detail'] is String) return d['detail'];
    } catch (_) {}
    return null;
  }

  /// Decodifica una respuesta que debería ser una lista.
  /// Si no es lista (o el JSON es inválido) regresa una lista vacía.
  static List<dynamic> decodeList(http.Response response) {
    try {
      final decoded = decode(response);
      if (decoded is List) return decoded;
    } catch (e) {
      debugPrint("Error parseando lista: $e");
    }
    return [];
  }

  /// GET que regresa una lista, o null si el status no fue 200.
  static Future<List<dynamic>?> getList(String path) async {
    final res = await get(path);
    return res.statusCode == 200 ? decodeList(res) : null;
  }

  /// GET que regresa un mapa, o null si el status no fue 200.
  static Future<Map<String, dynamic>?> getMap(String path) async {
    final res = await get(path);
    if (res.statusCode != 200) return null;
    final d = decode(res);
    return d is Map<String, dynamic> ? d : null;
  }

  /// Sube una imagen a /upload-imagen y regresa la URL pública, o null.
  static Future<String?> uploadImage(List<int> bytes, String filename) async {
    final request = http.MultipartRequest('POST', uri('/upload-imagen'));
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final response = await request.send().timeout(const Duration(seconds: 60));
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(await response.stream.bytesToString());
      return jsonResponse['url'];
    }
    if (response.statusCode == 413) {
      throw const FormatException('La foto pesa demasiado');
    }
    return null;
  }
}
