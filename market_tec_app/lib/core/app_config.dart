/// Configuración que cambia según dónde corre la app (PC, celular, servidor).
///
/// Los valores se pasan al compilar con `--dart-define`, así no hay que
/// editar código para cambiar de servidor:
///
/// ```
/// flutter run -d chrome --dart-define=API_URL=http://localhost:8000
/// flutter build apk --release --dart-define=API_URL=http://192.168.1.50:8000
/// flutter build web --release --dart-define=API_URL=https://api.market-tec.mx
/// ```
///
/// Ojo: en un celular `localhost` es el propio celular, no tu PC. Usa la IP
/// de tu PC en la red Wi-Fi (o `http://10.0.2.2:8000` en el emulador).
class AppConfig {
  AppConfig._();

  /// URL del backend FastAPI, sin diagonal al final.
  /// Por defecto apunta a producción. Para probar contra tu PC:
  /// `flutter run -d chrome --dart-define=API_URL=http://localhost:8000`
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://market-tec-itz.duckdns.org',
  );

  /// Dónde se descarga el APK desde la versión web. Puede ser una ruta
  /// relativa a la carpeta `web/` (se sirve junto con la app) o una URL
  /// completa (Google Drive, GitHub Releases, tu servidor...).
  static const String apkUrl = String.fromEnvironment(
    'APK_URL',
    defaultValue: 'downloads/market-tec.apk',
  );

  /// Versión que se muestra junto al botón de descarga. Debe coincidir con
  /// `version:` de pubspec.yaml.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '2.0.0',
  );
}
