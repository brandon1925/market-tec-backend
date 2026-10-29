library market_tec.globals;

int currentUserId = 0;
String currentUserRole = '';
String currentUserName = '';
String currentUserUsername = '';
String currentUserEmail = '';
String currentUserControl = '';
String currentUserStatus = '';
String? currentUserFoto;

/// Redes sociales del usuario (instagram, whatsapp, facebook, tiktok).
Map<String, String> currentUserRedes = {};

/// El vendedor tiene su ubicación compartida en el mapa. Se guarda aquí para
/// que el switch no se "apague" al cambiar de pantalla.
bool compartiendoUbicacion = false;
DateTime? ubicacionCompartidaDesde;

bool get esVendedor =>
    currentUserRole == 'Vendedor' || currentUserRole == 'Administrador';

/// Llena los datos del usuario a partir de la respuesta de /login o de
/// /usuarios/{id}/perfil.
void cargarUsuario(Map<String, dynamic> d) {
  currentUserId = d['user_id'] ?? d['id_usuario'] ?? currentUserId;
  currentUserName = d['nombre_completo'] ?? currentUserName;
  currentUserUsername = d['username'] ?? currentUserUsername;
  currentUserEmail = d['correo_institucional'] ?? currentUserEmail;
  currentUserControl = d['numero_control'] ?? currentUserControl;
  currentUserStatus = d['estado_cuenta'] ?? currentUserStatus;
  currentUserRole = d['rol'] ?? currentUserRole;
  if (d.containsKey('foto_url')) currentUserFoto = d['foto_url'];
  if (d['redes'] is Map) {
    currentUserRedes = {
      for (final e in (d['redes'] as Map).entries)
        if (e.value != null && '${e.value}'.trim().isNotEmpty)
          '${e.key}': '${e.value}',
    };
  }
  if (d['compartir_ubicacion'] is bool) {
    compartiendoUbicacion = d['compartir_ubicacion'];
  }
}

void limpiarUsuario() {
  currentUserId = 0;
  currentUserRole = '';
  currentUserName = '';
  currentUserUsername = '';
  currentUserEmail = '';
  currentUserControl = '';
  currentUserStatus = '';
  currentUserFoto = null;
  currentUserRedes = {};
  compartiendoUbicacion = false;
  ubicacionCompartidaDesde = null;
}
