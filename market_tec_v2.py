"""
Market-Tec ITZ - endpoints de la versión 2.0
============================================

Este archivo se pone junto a main.py y se conecta con 2 líneas al FINAL de
main.py (después de todas las rutas):

    from market_tec_v2 import instalar_v2
    instalar_v2(app)

Qué agrega:
  * Perfil editable (foto, nombre, usuario, redes sociales)
  * Catálogo de vendedores y su horario de entrega
  * Mini chat por venta y notificaciones (las crea la base con triggers)
  * Historial de compras y ventas con filtros, motivo de rechazo
  * Horarios con modalidad de entrega (lunes a viernes, 6:00 am a 9:00 pm)
  * Comentarios de la página y reportes a vendedores (arregla el error 500)
  * Admin: editar perfiles
  * Bloqueo real: una cuenta suspendida ya no puede iniciar sesión
  * Validación de login, registro y recuperación ANTES de que lleguen a
    main.py (formato del correo y del número de control, largo y caracteres
    permitidos), como segunda barrera contra inyección SQL

Conexión a la base: usa la variable de entorno DATABASE_URL, por ejemplo
    postgresql://usuario:contraseña@localhost:5432/market_tec
o DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD. Si main.py ya tiene una
función que regresa una conexión de psycopg2, se le puede pasar directo:
    instalar_v2(app, conectar=get_db_connection)
"""

import json
import os
import re
from contextlib import contextmanager
from datetime import date, datetime, time, timedelta
from typing import Callable, Optional

import psycopg2
import psycopg2.extras
import psycopg2.pool
from fastapi import APIRouter, FastAPI, HTTPException, Query
from fastapi.routing import APIRoute
from pydantic import BaseModel

router = APIRouter()

# ==========================================================
# CONEXIÓN
# ==========================================================

_pool: Optional[psycopg2.pool.SimpleConnectionPool] = None
_conectar: Optional[Callable] = None


def _dsn() -> str:
    url = os.getenv("DATABASE_URL")
    if url:
        return url
    return (
        f"host={os.getenv('DB_HOST', 'localhost')} "
        f"port={os.getenv('DB_PORT', '5432')} "
        f"dbname={os.getenv('DB_NAME', 'market_tec')} "
        f"user={os.getenv('DB_USER', 'postgres')} "
        f"password={os.getenv('DB_PASSWORD', '')}"
    )


@contextmanager
def db():
    """Cursor que regresa diccionarios. Hace commit al salir sin errores."""
    global _pool
    if _conectar is not None:
        conn = _conectar()
    else:
        if _pool is None:
            _pool = psycopg2.pool.SimpleConnectionPool(1, 10, _dsn())
        conn = _pool.getconn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    try:
        yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        if _conectar is not None:
            conn.close()
        else:
            _pool.putconn(conn)


def _todos(sql: str, params=()) -> list:
    with db() as cur:
        cur.execute(sql, params)
        return [dict(r) for r in cur.fetchall()]


def _uno(sql: str, params=()) -> Optional[dict]:
    with db() as cur:
        cur.execute(sql, params)
        r = cur.fetchone()
        return dict(r) if r else None


def _ejecutar(sql: str, params=()) -> Optional[dict]:
    """INSERT/UPDATE; si lleva RETURNING regresa la fila."""
    with db() as cur:
        cur.execute(sql, params)
        if cur.description:
            r = cur.fetchone()
            return dict(r) if r else None
        return None


# ==========================================================
# AYUDANTES
# ==========================================================

ESTADOS_CHAT = ("Pendiente", "Confirmado", "En camino")
ROLES = {1: "Cliente", 2: "Vendedor", 3: "Administrador"}


def _hora(t) -> Optional[str]:
    if t is None:
        return None
    if isinstance(t, (time, datetime)):
        return t.strftime("%H:%M")
    return str(t)[:5]


def _fecha(f) -> Optional[str]:
    if f is None:
        return None
    if isinstance(f, (datetime, date)):
        return f.isoformat()
    return str(f)


def _num(n):
    if n is None:
        return 0
    f = float(n)
    return int(f) if f.is_integer() else round(f, 2)


def _texto(v: Optional[str], maximo: int) -> Optional[str]:
    """Quita espacios; '' se guarda como NULL."""
    if v is None:
        return None
    v = v.strip()
    return v[:maximo] if v else None


def _redes(u: dict, prefijo: str = "") -> dict:
    return {
        "whatsapp": u.get(f"{prefijo}whatsapp"),
        "instagram": u.get(f"{prefijo}instagram"),
        "facebook": u.get(f"{prefijo}facebook"),
        "tiktok": u.get(f"{prefijo}tiktok"),
    }


def _usuario_o_404(id_usuario: int) -> dict:
    u = _uno("SELECT * FROM Usuarios WHERE id_usuario = %s", (id_usuario,))
    if not u:
        raise HTTPException(404, "El usuario no existe")
    return u


def _es_admin(id_usuario: Optional[int]) -> bool:
    if not id_usuario:
        return False
    u = _uno("SELECT id_rol FROM Usuarios WHERE id_usuario = %s", (id_usuario,))
    return bool(u and u["id_rol"] == 3)


def _lista_estados(estados: Optional[str]) -> list:
    return [e.strip() for e in (estados or "").split(",") if e.strip()]


# ==========================================================
# PERFIL
# ==========================================================


def _perfil(id_usuario: int) -> dict:
    u = _usuario_o_404(id_usuario)
    stats = _uno(
        """
        SELECT
          (SELECT COUNT(*) FROM Pedidos WHERE id_cliente = %(id)s) AS compras,
          (SELECT COUNT(*) FROM Favoritos WHERE id_cliente = %(id)s) AS favoritos,
          (SELECT COUNT(*) FROM Resenas WHERE id_cliente = %(id)s) AS resenas,
          (SELECT COUNT(*) FROM Reportes WHERE id_denunciante = %(id)s) AS reportes,
          (SELECT COUNT(*) FROM Productos WHERE id_vendedor = %(id)s) AS productos
        """,
        {"id": id_usuario},
    )
    return {
        "user_id": u["id_usuario"],
        "id_usuario": u["id_usuario"],
        "nombre_completo": u["nombre_completo"],
        "username": u["username"],
        "correo_institucional": u["correo_institucional"],
        "numero_control": u["numero_control"],
        "rol": ROLES.get(u["id_rol"], "Cliente"),
        "id_rol": u["id_rol"],
        "estado_cuenta": u["estado_cuenta"],
        "foto_url": u.get("foto_url"),
        "redes": _redes(u),
        "compartir_ubicacion": bool(u.get("compartir_ubicacion")),
        "fecha_registro": _fecha(u.get("fecha_registro")),
        "stats": stats,
    }


class PerfilIn(BaseModel):
    nombre_completo: Optional[str] = None
    username: Optional[str] = None
    foto_url: Optional[str] = None
    whatsapp: Optional[str] = None
    instagram: Optional[str] = None
    facebook: Optional[str] = None
    tiktok: Optional[str] = None


class AdminPerfilIn(PerfilIn):
    id_admin: Optional[int] = None
    numero_control: Optional[str] = None
    correo_institucional: Optional[str] = None


def _validar_y_armar(datos: dict, id_usuario: int) -> dict:
    """Valida los campos que sí vienen y regresa {columna: valor}."""
    cambios = {}
    # Si el número de control o el correo no cambian, no se revalidan (así se
    # pueden guardar cuentas viejas, como la del admin, sin tocar esos datos).
    actual = (
        _uno(
            "SELECT numero_control, correo_institucional FROM Usuarios WHERE id_usuario = %s",
            (id_usuario,),
        )
        or {}
    )

    if datos.get("nombre_completo") is not None:
        nombre = re.sub(r"\s+", " ", datos["nombre_completo"]).strip()
        if len(nombre) < 5 or len(nombre) > 150:
            raise HTTPException(400, "El nombre debe tener entre 5 y 150 letras")
        cambios["nombre_completo"] = nombre

    if datos.get("username") is not None:
        user = datos["username"].strip()
        if not re.fullmatch(r"[A-Za-z0-9_.]{3,50}", user):
            raise HTTPException(
                400, "El usuario solo puede tener letras, números, punto y guion bajo (3 a 50)"
            )
        if _uno(
            "SELECT 1 FROM Usuarios WHERE LOWER(username) = LOWER(%s) AND id_usuario <> %s",
            (user, id_usuario),
        ):
            raise HTTPException(409, "Ese nombre de usuario ya está ocupado")
        cambios["username"] = user

    if datos.get("numero_control") is not None:
        control = datos["numero_control"].strip().upper()
        if control != (actual.get("numero_control") or "").upper() and not RE_NUMERO_CONTROL.fullmatch(
            control
        ):
            raise HTTPException(400, "El número de control son 8 números, con una C opcional al inicio")
        if _uno(
            "SELECT 1 FROM Usuarios WHERE UPPER(numero_control) = %s AND id_usuario <> %s",
            (control, id_usuario),
        ):
            raise HTTPException(409, "Ese número de control ya está registrado")
        cambios["numero_control"] = control

    if datos.get("correo_institucional") is not None:
        correo = datos["correo_institucional"].strip().lower()
        if correo != (actual.get("correo_institucional") or "").lower() and not RE_CORREO_ALUMNO.fullmatch(
            correo
        ):
            raise HTTPException(
                400, "El correo debe ser L, C o LC + 8 números y @zacatepec.tecnm.mx"
            )
        if _uno(
            "SELECT 1 FROM Usuarios WHERE LOWER(correo_institucional) = %s AND id_usuario <> %s",
            (correo, id_usuario),
        ):
            raise HTTPException(409, "Ese correo ya está registrado")
        cambios["correo_institucional"] = correo

    if datos.get("foto_url") is not None:
        cambios["foto_url"] = _texto(datos["foto_url"], 500)

    if datos.get("whatsapp") is not None:
        tel = re.sub(r"\D", "", datos["whatsapp"])
        if tel and not 10 <= len(tel) <= 13:
            raise HTTPException(400, "El WhatsApp debe tener 10 dígitos")
        cambios["whatsapp"] = tel or None
    for red, maximo in (("instagram", 60), ("tiktok", 60), ("facebook", 200)):
        if datos.get(red) is not None:
            cambios[red] = _texto(datos[red].lstrip("@") if red != "facebook" else datos[red], maximo)

    return cambios


def _guardar_cambios(id_usuario: int, cambios: dict):
    if not cambios:
        return
    columnas = ", ".join(f"{c} = %({c})s" for c in cambios)
    _ejecutar(
        f"UPDATE Usuarios SET {columnas} WHERE id_usuario = %(id)s",
        {**cambios, "id": id_usuario},
    )


@router.get("/usuarios/{id_usuario}/perfil")
def ver_perfil(id_usuario: int):
    return _perfil(id_usuario)


@router.put("/usuarios/{id_usuario}/perfil")
def editar_perfil(id_usuario: int, datos: PerfilIn):
    _usuario_o_404(id_usuario)
    _guardar_cambios(id_usuario, _validar_y_armar(datos.model_dump(), id_usuario))
    return _perfil(id_usuario)


# ==========================================================
# ADMIN: usuarios
# ==========================================================


@router.get("/admin/usuarios")
def admin_usuarios():
    filas = _todos(
        """
        SELECT id_usuario, nombre_completo, username, correo_institucional AS correo,
               numero_control, id_rol, estado_cuenta, foto_url, fecha_registro
        FROM Usuarios
        ORDER BY fecha_registro DESC, id_usuario DESC
        """
    )
    for f in filas:
        f["fecha_registro"] = _fecha(f["fecha_registro"])
    return filas


@router.put("/admin/usuarios/{id_usuario}")
def admin_editar_usuario(id_usuario: int, datos: AdminPerfilIn):
    if not _es_admin(datos.id_admin):
        raise HTTPException(403, "Solo un administrador puede editar perfiles")
    _usuario_o_404(id_usuario)
    cambios = _validar_y_armar(datos.model_dump(exclude={"id_admin"}), id_usuario)
    _guardar_cambios(id_usuario, cambios)
    if cambios:
        _ejecutar(
            """INSERT INTO Bitacora (id_usuario, accion, tabla_afectada, descripcion_detalle)
               VALUES (%s, 'ADMIN_EDITA_PERFIL', 'Usuarios', %s)""",
            (id_usuario, f"Admin #{datos.id_admin} cambió: {', '.join(cambios)}"),
        )
    return _perfil(id_usuario)


# ==========================================================
# SINCRONIZACIÓN: notificaciones + estado de la cuenta
# ==========================================================


@router.get("/usuarios/{id_usuario}/sync")
def sincronizar(id_usuario: int, desde: int = 0):
    u = _uno("SELECT estado_cuenta FROM Usuarios WHERE id_usuario = %s", (id_usuario,))
    if not u:
        return {"estado_cuenta": "Eliminada", "no_leidas": 0, "notificaciones": []}

    notifs = _todos(
        """
        SELECT * FROM (
            SELECT id_notificacion AS id, tipo, titulo, cuerpo, id_referencia, fecha, leida
            FROM Notificaciones
            WHERE id_usuario = %s AND id_notificacion > %s
            ORDER BY id_notificacion DESC
            LIMIT 30
        ) t ORDER BY id
        """,
        (id_usuario, desde),
    )
    for n in notifs:
        n["fecha"] = _fecha(n["fecha"])
    no_leidas = _uno(
        "SELECT COUNT(*) AS n FROM Notificaciones WHERE id_usuario = %s AND NOT leida",
        (id_usuario,),
    )["n"]
    return {
        "estado_cuenta": u["estado_cuenta"],
        "no_leidas": no_leidas,
        "notificaciones": notifs,
    }


class LeidasIn(BaseModel):
    hasta: Optional[int] = None


@router.post("/usuarios/{id_usuario}/notificaciones/leidas")
def marcar_leidas(id_usuario: int, datos: LeidasIn):
    _ejecutar(
        """UPDATE Notificaciones SET leida = TRUE
           WHERE id_usuario = %s AND NOT leida AND (%s IS NULL OR id_notificacion <= %s)""",
        (id_usuario, datos.hasta, datos.hasta),
    )
    return {"ok": True}


# ==========================================================
# VENDEDORES
# ==========================================================

_SQL_VENDEDORES = """
    SELECT u.id_usuario AS id, u.nombre_completo AS nombre, u.username, u.foto_url,
           u.whatsapp, u.instagram, u.facebook, u.tiktok, u.compartir_ubicacion,
           COUNT(DISTINCT p.id_producto) FILTER (
               WHERE NOT COALESCE(p.pausado_por_agotado, FALSE)
                 AND NOT COALESCE(p.bloqueado_por_admin, FALSE)
                 AND p.stock > 0
           ) AS productos,
           ROUND(AVG(r.calificacion)::numeric, 1) AS rating
    FROM Usuarios u
    LEFT JOIN Productos p ON p.id_vendedor = u.id_usuario
    LEFT JOIN Resenas r ON r.id_producto = p.id_producto
    WHERE u.estado_cuenta = 'Activa' AND (u.id_rol = 2 OR p.id_producto IS NOT NULL)
"""


def _vendedor_json(v: dict) -> dict:
    return {
        "id": v["id"],
        "nombre": v["nombre"],
        "username": v["username"],
        "foto_url": v["foto_url"],
        "redes": _redes(v),
        "productos": v["productos"] or 0,
        "rating": _num(v["rating"]) if v["rating"] is not None else 0,
        "compartiendo_ubicacion": bool(v["compartir_ubicacion"]),
    }


@router.get("/vendedores")
def listar_vendedores():
    filas = _todos(
        _SQL_VENDEDORES
        + " GROUP BY u.id_usuario ORDER BY productos DESC, u.nombre_completo"
    )
    return [_vendedor_json(v) for v in filas]


@router.get("/vendedores/{id_vendedor}")
def ver_vendedor(id_vendedor: int):
    v = _uno(
        _SQL_VENDEDORES.replace("WHERE u.estado_cuenta = 'Activa' AND", "WHERE u.id_usuario = %s AND")
        + " GROUP BY u.id_usuario",
        (id_vendedor,),
    )
    if not v:
        raise HTTPException(404, "El vendedor no existe")
    datos = _vendedor_json(v)
    datos["horarios"] = _horarios(id_vendedor)
    return datos


# ==========================================================
# HORARIOS (con modalidad de entrega)
# ==========================================================


def _horarios(id_vendedor: int) -> list:
    filas = _todos(
        """
        SELECT id_horario, dia_semana, hora_inicio, hora_fin, modalidad, punto_entrega
        FROM Horarios_Vendedor
        WHERE id_vendedor = %s
        ORDER BY dia_semana, hora_inicio
        """,
        (id_vendedor,),
    )
    return [
        {
            "id": h["id_horario"],
            "id_horario": h["id_horario"],
            "dia": h["dia_semana"],
            "dia_semana": h["dia_semana"],
            "inicio": _hora(h["hora_inicio"]),
            "fin": _hora(h["hora_fin"]),
            "hora_inicio": _hora(h["hora_inicio"]),
            "hora_fin": _hora(h["hora_fin"]),
            "modalidad": h["modalidad"],
            "punto_entrega": h["punto_entrega"],
        }
        for h in filas
    ]


@router.get("/v2/horarios/{id_vendedor}")
def ver_horarios(id_vendedor: int):
    return _horarios(id_vendedor)


class HorarioIn(BaseModel):
    id_vendedor: int
    dia_semana: int
    hora_inicio: str
    hora_fin: str
    modalidad: Optional[str] = "Punto de encuentro"
    punto_entrega: Optional[str] = None


def _a_hora(texto: str) -> time:
    try:
        h, m = texto.strip()[:5].split(":")
        return time(int(h), int(m))
    except Exception:
        raise HTTPException(400, f"Hora no válida: {texto}")


@router.post("/v2/horarios")
def crear_horario(datos: HorarioIn):
    if not 1 <= datos.dia_semana <= 5:
        raise HTTPException(400, "Solo se pueden poner turnos de lunes a viernes")
    inicio, fin = _a_hora(datos.hora_inicio), _a_hora(datos.hora_fin)
    if inicio < time(6, 0) or fin > time(21, 0):
        raise HTTPException(400, "El horario debe estar entre las 6:00 am y las 9:00 pm")
    if inicio >= fin:
        raise HTTPException(400, "La hora de fin debe ser después de la de inicio")
    if (datetime.combine(date.today(), fin) - datetime.combine(date.today(), inicio)) < timedelta(minutes=15):
        raise HTTPException(400, "El turno debe durar al menos 15 minutos")
    if _uno(
        """SELECT 1 FROM Horarios_Vendedor
           WHERE id_vendedor = %s AND dia_semana = %s AND hora_inicio < %s AND hora_fin > %s""",
        (datos.id_vendedor, datos.dia_semana, fin, inicio),
    ):
        raise HTTPException(409, "Ese turno se cruza con otro que ya tienes ese día")

    fila = _ejecutar(
        """INSERT INTO Horarios_Vendedor
               (id_vendedor, dia_semana, hora_inicio, hora_fin, modalidad, punto_entrega)
           VALUES (%s, %s, %s, %s, %s, %s) RETURNING id_horario""",
        (
            datos.id_vendedor,
            datos.dia_semana,
            inicio,
            fin,
            _texto(datos.modalidad, 40) or "Punto de encuentro",
            _texto(datos.punto_entrega, 150),
        ),
    )
    return {"mensaje": "Turno guardado", "id_horario": fila["id_horario"]}


# ==========================================================
# MAPA
# ==========================================================


@router.get("/v2/ubicaciones/activas")
def ubicaciones_activas():
    filas = _todos(
        """
        SELECT u.id_usuario AS id, u.nombre_completo AS nombre, u.foto_url,
               u.latitud, u.longitud, u.ubicacion_actualizada,
               (SELECT STRING_AGG(nombre_producto, ', ')
                  FROM (SELECT nombre_producto FROM Productos p
                        WHERE p.id_vendedor = u.id_usuario AND p.stock > 0
                          AND NOT COALESCE(p.pausado_por_agotado, FALSE)
                          AND NOT COALESCE(p.bloqueado_por_admin, FALSE)
                        ORDER BY p.ventas_concretadas DESC LIMIT 3) t) AS producto
        FROM Usuarios u
        WHERE u.compartir_ubicacion AND u.estado_cuenta = 'Activa'
          AND u.latitud IS NOT NULL AND u.longitud IS NOT NULL
          AND (u.ubicacion_actualizada IS NULL
               OR u.ubicacion_actualizada > NOW() - INTERVAL '3 hours')
        """
    )
    for f in filas:
        f["latitud"] = float(f["latitud"])
        f["longitud"] = float(f["longitud"])
        f["ubicacion_actualizada"] = _fecha(f["ubicacion_actualizada"])
    return filas


# ==========================================================
# COMPRAS Y VENTAS (con filtros)
# ==========================================================


def _filtros_pedido(estados, desde, hasta) -> tuple:
    sql, params = "", []
    lista = _lista_estados(estados)
    if lista:
        sql += " AND pe.estado_solicitud = ANY(%s)"
        params.append(lista)
    if desde:
        sql += " AND pe.fecha_hora_pedido >= %s"
        params.append(desde)
    if hasta:
        sql += " AND pe.fecha_hora_pedido < %s::date + 1"
        params.append(hasta)
    return sql, params


@router.get("/v2/mis-compras/{id_cliente}")
def mis_compras(
    id_cliente: int,
    limite: Optional[int] = Query(None, ge=1, le=500),
    estados: Optional[str] = None,
    desde: Optional[date] = None,
    hasta: Optional[date] = None,
):
    extra, params = _filtros_pedido(estados, desde, hasta)
    filas = _todos(
        f"""
        SELECT pe.id_pedido, pe.id_producto, p.nombre_producto AS producto_nombre,
               p.imagen_url, pe.cantidad, pe.total_venta AS total,
               pe.estado_solicitud AS estado, pe.motivo_rechazo,
               pe.fecha_hora_pedido AS fecha,
               v.id_usuario AS vendedor_id, v.nombre_completo AS vendedor_nombre,
               v.foto_url AS vendedor_foto,
               EXISTS (SELECT 1 FROM Resenas r
                       WHERE r.id_producto = pe.id_producto AND r.id_cliente = pe.id_cliente
                      ) AS ya_calificado
        FROM Pedidos pe
        JOIN Productos p ON p.id_producto = pe.id_producto
        JOIN Usuarios v ON v.id_usuario = pe.id_vendedor
        WHERE pe.id_cliente = %s {extra}
        ORDER BY pe.fecha_hora_pedido DESC
        {"LIMIT %s" if limite else ""}
        """,
        [id_cliente, *params, *([limite] if limite else [])],
    )
    for f in filas:
        f["total"] = _num(f["total"])
        f["fecha"] = _fecha(f["fecha"])
    return filas


@router.get("/v2/ventas/{id_vendedor}")
def mis_ventas(
    id_vendedor: int,
    estados: Optional[str] = None,
    desde: Optional[date] = None,
    hasta: Optional[date] = None,
):
    extra, params = _filtros_pedido(estados, desde, hasta)
    filas = _todos(
        f"""
        SELECT pe.id_pedido, pe.id_cliente, c.nombre_completo AS cliente_nombre,
               c.foto_url AS cliente_foto, p.nombre_producto AS producto,
               p.imagen_url, pe.cantidad, pe.total_venta AS total,
               pe.estado_solicitud AS estado, pe.motivo_rechazo,
               pe.fecha_hora_pedido AS fecha
        FROM Pedidos pe
        JOIN Productos p ON p.id_producto = pe.id_producto
        JOIN Usuarios c ON c.id_usuario = pe.id_cliente
        WHERE pe.id_vendedor = %s {extra}
        ORDER BY pe.fecha_hora_pedido DESC
        LIMIT 500
        """,
        [id_vendedor, *params],
    )
    for f in filas:
        f["total"] = _num(f["total"])
        f["fecha"] = _fecha(f["fecha"])
    return filas


class MotivoIn(BaseModel):
    motivo: str


@router.put("/pedidos/{id_pedido}/motivo")
def guardar_motivo(id_pedido: int, datos: MotivoIn):
    motivo = _texto(datos.motivo, 150)
    if not motivo:
        raise HTTPException(400, "Escribe el motivo")
    fila = _ejecutar(
        "UPDATE Pedidos SET motivo_rechazo = %s WHERE id_pedido = %s RETURNING id_pedido",
        (motivo, id_pedido),
    )
    if not fila:
        raise HTTPException(404, "El pedido no existe")
    return {"mensaje": "Motivo guardado"}


# ==========================================================
# MINI CHAT DE CADA VENTA
# ==========================================================


def _pedido_chat(id_pedido: int) -> dict:
    p = _uno(
        """
        SELECT pe.id_pedido, pe.id_cliente, pe.id_vendedor, pe.cantidad,
               pe.estado_solicitud AS estado, pr.nombre_producto AS producto,
               c.nombre_completo AS cliente_nombre, c.foto_url AS cliente_foto,
               c.whatsapp AS c_whatsapp, c.instagram AS c_instagram,
               c.facebook AS c_facebook, c.tiktok AS c_tiktok,
               v.nombre_completo AS vendedor_nombre, v.foto_url AS vendedor_foto,
               v.whatsapp AS v_whatsapp, v.instagram AS v_instagram,
               v.facebook AS v_facebook, v.tiktok AS v_tiktok
        FROM Pedidos pe
        JOIN Productos pr ON pr.id_producto = pe.id_producto
        JOIN Usuarios c ON c.id_usuario = pe.id_cliente
        JOIN Usuarios v ON v.id_usuario = pe.id_vendedor
        WHERE pe.id_pedido = %s
        """,
        (id_pedido,),
    )
    if not p:
        raise HTTPException(404, "El pedido no existe")
    return p


@router.get("/pedidos/{id_pedido}/mensajes")
def ver_mensajes(id_pedido: int, id_usuario: int, desde: int = 0):
    p = _pedido_chat(id_pedido)
    if id_usuario not in (p["id_cliente"], p["id_vendedor"]) and not _es_admin(id_usuario):
        raise HTTPException(403, "Este chat es solo del comprador y el vendedor")

    mensajes = _todos(
        """SELECT id_mensaje AS id, id_remitente, mensaje, fecha
           FROM Mensajes_Pedido WHERE id_pedido = %s AND id_mensaje > %s
           ORDER BY id_mensaje LIMIT 200""",
        (id_pedido, desde),
    )
    for m in mensajes:
        m["fecha"] = _fecha(m["fecha"])
    # Lo que ya se ve en el chat deja de contar como notificación sin leer
    _ejecutar(
        """UPDATE Notificaciones SET leida = TRUE
           WHERE id_usuario = %s AND tipo = 'chat' AND id_referencia = %s AND NOT leida""",
        (id_usuario, id_pedido),
    )
    return {
        "pedido": {
            "id_pedido": p["id_pedido"],
            "producto": p["producto"],
            "cantidad": p["cantidad"],
            "estado": p["estado"],
            "id_cliente": p["id_cliente"],
            "id_vendedor": p["id_vendedor"],
            "cliente_nombre": p["cliente_nombre"],
            "vendedor_nombre": p["vendedor_nombre"],
            "cliente_foto": p["cliente_foto"],
            "vendedor_foto": p["vendedor_foto"],
            "redes_cliente": _redes(p, "c_"),
            "redes_vendedor": _redes(p, "v_"),
        },
        "mensajes": mensajes,
    }


class MensajeIn(BaseModel):
    id_remitente: int
    mensaje: str


@router.post("/pedidos/{id_pedido}/mensajes")
def enviar_mensaje(id_pedido: int, datos: MensajeIn):
    p = _pedido_chat(id_pedido)
    if datos.id_remitente not in (p["id_cliente"], p["id_vendedor"]):
        raise HTTPException(403, "Solo el comprador y el vendedor pueden escribir aquí")
    if p["estado"] not in ESTADOS_CHAT:
        raise HTTPException(409, "El chat se cerró porque la venta ya terminó")
    texto = (datos.mensaje or "").strip()
    if not texto:
        raise HTTPException(400, "Escribe un mensaje")
    if len(texto) > 500:
        raise HTTPException(400, "El mensaje puede tener máximo 500 letras")
    fila = _ejecutar(
        """INSERT INTO Mensajes_Pedido (id_pedido, id_remitente, mensaje)
           VALUES (%s, %s, %s) RETURNING id_mensaje AS id, id_remitente, mensaje, fecha""",
        (id_pedido, datos.id_remitente, texto),
    )
    fila["fecha"] = _fecha(fila["fecha"])
    return fila


# ==========================================================
# PRODUCTOS: cambiar la foto
# ==========================================================


class ImagenIn(BaseModel):
    imagen_url: str


@router.put("/productos/{id_producto}/imagen")
def cambiar_imagen(id_producto: int, datos: ImagenIn):
    url = _texto(datos.imagen_url, 255)
    if not url:
        raise HTTPException(400, "Falta la imagen")
    fila = _ejecutar(
        "UPDATE Productos SET imagen_url = %s WHERE id_producto = %s RETURNING id_producto",
        (url, id_producto),
    )
    if not fila:
        raise HTTPException(404, "El producto no existe")
    return {"mensaje": "Imagen actualizada", "imagen_url": url}


# ==========================================================
# COMENTARIOS DE LA PÁGINA
# ==========================================================


class ComentarioWebIn(BaseModel):
    id_usuario: Optional[int] = None
    tipo: str = "Comentario"
    calificacion: Optional[int] = None
    mensaje: str


@router.post("/comentarios-web")
def crear_comentario_web(datos: ComentarioWebIn):
    if datos.tipo not in ("Sugerencia", "Error", "Comentario"):
        raise HTTPException(400, "Tipo de comentario no válido")
    if datos.calificacion is not None and not 1 <= datos.calificacion <= 5:
        raise HTTPException(400, "La calificación va de 1 a 5")
    texto = (datos.mensaje or "").strip()
    if len(texto) < 3 or len(texto) > 500:
        raise HTTPException(400, "El comentario debe tener entre 3 y 500 letras")
    fila = _ejecutar(
        """INSERT INTO Comentarios_Web (id_usuario, tipo, calificacion, mensaje)
           VALUES (%s, %s, %s, %s) RETURNING id_comentario""",
        (datos.id_usuario or None, datos.tipo, datos.calificacion, texto),
    )
    return {"mensaje": "Comentario recibido", "id": fila["id_comentario"]}


def _comentarios(where: str = "", params=()) -> list:
    filas = _todos(
        f"""SELECT c.id_comentario AS id, c.tipo, c.calificacion, c.mensaje, c.estado,
                   c.respuesta, c.fecha, c.id_usuario,
                   COALESCE(u.nombre_completo, 'Usuario eliminado') AS usuario
            FROM Comentarios_Web c
            LEFT JOIN Usuarios u ON u.id_usuario = c.id_usuario
            {where}
            ORDER BY (c.estado = 'Atendido'), c.fecha DESC
            LIMIT 300""",
        params,
    )
    for f in filas:
        f["fecha"] = _fecha(f["fecha"])
    return filas


@router.get("/usuarios/{id_usuario}/comentarios-web")
def mis_comentarios_web(id_usuario: int):
    return _comentarios("WHERE c.id_usuario = %s", (id_usuario,))


@router.get("/admin/comentarios-web")
def admin_comentarios_web():
    return _comentarios()


class EstadoComentarioIn(BaseModel):
    nuevo_estado: str
    respuesta: Optional[str] = None


@router.put("/admin/comentarios-web/{id_comentario}/estado")
def admin_estado_comentario(id_comentario: int, datos: EstadoComentarioIn):
    if datos.nuevo_estado not in ("Recibido", "Atendido"):
        raise HTTPException(400, "Estado no válido")
    fila = _ejecutar(
        """UPDATE Comentarios_Web
           SET estado = %s, respuesta = COALESCE(%s, respuesta)
           WHERE id_comentario = %s RETURNING id_comentario""",
        (datos.nuevo_estado, _texto(datos.respuesta, 300), id_comentario),
    )
    if not fila:
        raise HTTPException(404, "El comentario no existe")
    return {"mensaje": "Comentario actualizado"}


# ==========================================================
# REPORTES (reemplaza a los de main.py, que daban error 500)
# ==========================================================


class ReporteIn(BaseModel):
    id_reportante: int
    id_vendedor: Optional[int] = None
    id_producto: Optional[int] = None
    motivo: str
    descripcion: str


@router.post("/reportes")
def crear_reporte(datos: ReporteIn):
    id_vendedor = datos.id_vendedor
    if datos.id_producto:
        prod = _uno(
            "SELECT id_vendedor FROM Productos WHERE id_producto = %s", (datos.id_producto,)
        )
        if not prod:
            raise HTTPException(404, "El producto ya no existe")
        if id_vendedor and prod["id_vendedor"] != id_vendedor:
            raise HTTPException(400, "Ese producto no es de ese vendedor")
        id_vendedor = prod["id_vendedor"]
    if not id_vendedor:
        raise HTTPException(400, "Elige al vendedor que quieres reportar")
    if id_vendedor == datos.id_reportante:
        raise HTTPException(400, "No puedes reportarte a ti mismo")
    if not _uno("SELECT 1 FROM Usuarios WHERE id_usuario = %s", (id_vendedor,)):
        raise HTTPException(404, "El vendedor no existe")

    motivo = _texto(datos.motivo, 100)
    descripcion = (datos.descripcion or "").strip()
    if not motivo:
        raise HTTPException(400, "Elige un motivo")
    if len(descripcion) < 10:
        raise HTTPException(400, "Explica un poco más qué pasó")

    fila = _ejecutar(
        """INSERT INTO Reportes (id_denunciante, id_usuario_reportado, id_producto_reportado,
                                 motivo_principal, descripcion_detallada)
           VALUES (%s, %s, %s, %s, %s) RETURNING id_reporte""",
        (datos.id_reportante, id_vendedor, datos.id_producto or None, motivo, descripcion[:1000]),
    )
    # Aviso a los administradores
    _ejecutar(
        """INSERT INTO Notificaciones (id_usuario, tipo, titulo, cuerpo, id_referencia)
           SELECT id_usuario, 'reporte', 'Nuevo reporte', %s, %s
           FROM Usuarios WHERE id_rol = 3 AND estado_cuenta = 'Activa'""",
        (motivo, fila["id_reporte"]),
    )
    return {"mensaje": "Reporte enviado", "id_reporte": fila["id_reporte"]}


@router.get("/reportes")
def listar_reportes():
    filas = _todos(
        """
        SELECT r.id_reporte, r.motivo_principal AS motivo,
               r.descripcion_detallada AS descripcion, r.estado_revision AS estado,
               r.fecha_reporte AS fecha,
               d.nombre_completo AS reportante,
               r.id_usuario_reportado AS id_vendedor, v.nombre_completo AS vendedor,
               r.id_producto_reportado AS id_producto, p.nombre_producto AS producto
        FROM Reportes r
        LEFT JOIN Usuarios d ON d.id_usuario = r.id_denunciante
        LEFT JOIN Usuarios v ON v.id_usuario = r.id_usuario_reportado
        LEFT JOIN Productos p ON p.id_producto = r.id_producto_reportado
        ORDER BY (r.estado_revision <> 'Pendiente'), r.fecha_reporte DESC
        """
    )
    for f in filas:
        f["fecha"] = _fecha(f["fecha"])
    return filas


class EstadoReporteIn(BaseModel):
    nuevo_estado: str


@router.put("/admin/reportes/{id_reporte}/estado")
def admin_estado_reporte(id_reporte: int, datos: EstadoReporteIn):
    if datos.nuevo_estado not in ("Pendiente", "Resuelto", "Descartado"):
        raise HTTPException(400, "Estado no válido")
    fila = _ejecutar(
        "UPDATE Reportes SET estado_revision = %s WHERE id_reporte = %s RETURNING id_reporte",
        (datos.nuevo_estado, id_reporte),
    )
    if not fila:
        raise HTTPException(404, "El reporte no existe")
    return {"mensaje": f"Reporte marcado como {datos.nuevo_estado}"}


# ==========================================================
# VALIDACIÓN DE LOGIN / REGISTRO / RECUPERACIÓN Y BLOQUEO REAL
# ==========================================================
# Estas rutas viven en main.py. El middleware revisa el JSON ANTES de que
# llegue a ellas: si algo no tiene el formato esperado responde 400 y main.py
# ni se entera. Así, aunque main.py armara alguna consulta pegando textos, no
# podría llegarle una comilla, un punto y coma ni un "--" en el correo, el
# número de control, el usuario o el nombre.

DOMINIO = "@zacatepec.tecnm.mx"
# Correo de alumno: L, C o LC + 8 números (ej. l23090970@zacatepec.tecnm.mx)
RE_CORREO_ALUMNO = re.compile(r"(l|c|lc)\d{8}" + re.escape(DOMINIO))
# Cualquier correo del dominio con caracteres seguros (cuentas que ya existen,
# como admin@zacatepec.tecnm.mx). Solo se acepta si la cuenta ya está en la base.
RE_CORREO_SEGURO = re.compile(r"[a-z0-9._-]{1,64}" + re.escape(DOMINIO))
RE_NUMERO_CONTROL = re.compile(r"C?\d{8}")
RE_USERNAME = re.compile(r"[A-Za-z0-9_.]{3,20}")
RE_NOMBRE = re.compile(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' ]{5,80}")
RE_PASSWORD = re.compile(r"\S{8,64}")

# Rutas de main.py que se revisan
_RUTAS_AUTH = {
    "/login",
    "/usuarios",
    "/enviar-codigo",
    "/recuperar-password/enviar",
    "/recuperar-password/restablecer",
}


def _correo_existe(correo: str) -> bool:
    try:
        return bool(
            _uno(
                "SELECT 1 FROM Usuarios WHERE LOWER(correo_institucional) = %s",
                (correo,),
            )
        )
    except Exception:
        return False  # si la base falla, solo pasan correos de alumno


def _validar_auth(ruta: str, datos: dict) -> Optional[str]:
    """Regresa el mensaje de error, o None si todo está bien."""
    if not isinstance(datos, dict):
        return "Datos no válidos"
    for valor in datos.values():
        if isinstance(valor, str) and ("\x00" in valor or len(valor) > 1000):
            return "Datos no válidos"

    correo = datos.get("correo_institucional") or datos.get("correo") or datos.get("email")
    if correo is not None:
        if not isinstance(correo, str):
            return "Correo no válido"
        correo = correo.strip().lower()
        if not RE_CORREO_ALUMNO.fullmatch(correo):
            # Registro y código de registro: solo correos de alumno.
            # Login y recuperación: también cuentas viejas que ya existan.
            if ruta in ("/usuarios", "/enviar-codigo") or not (
                RE_CORREO_SEGURO.fullmatch(correo) and _correo_existe(correo)
            ):
                return "El correo debe ser L, C o LC + 8 números y @zacatepec.tecnm.mx"
    elif ruta != "/login":
        return "Falta el correo"

    if ruta == "/usuarios":
        control = datos.get("numero_control")
        if not isinstance(control, str) or not RE_NUMERO_CONTROL.fullmatch(control.strip().upper()):
            return "El número de control son 8 números, con una C opcional al inicio"
        user = datos.get("username")
        if not isinstance(user, str) or not RE_USERNAME.fullmatch(user.strip()):
            return "El usuario solo puede tener letras, números, punto y guion bajo (3 a 20)"
        nombre = datos.get("nombre_completo")
        if not isinstance(nombre, str) or not RE_NOMBRE.fullmatch(nombre.strip()):
            return "El nombre solo puede tener letras y espacios (5 a 80)"
        rol = datos.get("id_rol", 1)
        if rol not in (1, 2):
            return "Rol no válido"  # nadie se registra solo como administrador

    nueva = datos.get("password") if ruta == "/usuarios" else datos.get("nueva_password")
    if ruta in ("/usuarios", "/recuperar-password/restablecer"):
        if not isinstance(nueva, str) or not RE_PASSWORD.fullmatch(nueva):
            return "La contraseña debe tener de 8 a 64 caracteres y sin espacios"
    if ruta == "/login" and not isinstance(datos.get("password", ""), str):
        return "Contraseña no válida"
    return None


async def _responder(send, status: int, detalle: str):
    texto = json.dumps({"detail": detalle}).encode()
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(texto)).encode()),
            ],
        }
    )
    await send({"type": "http.response.body", "body": texto})


class BloqueoLoginMiddleware:
    """Antes de que main.py atienda login, registro o recuperación de
    contraseña, valida el formato de los datos (400 si algo no cuadra). En
    /login además se fija si la cuenta está suspendida (403)."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        ruta = scope.get("path", "").rstrip("/") if scope["type"] == "http" else ""
        if not (scope["type"] == "http" and scope["method"] == "POST" and ruta in _RUTAS_AUTH):
            return await self.app(scope, receive, send)

        # Se lee el cuerpo completo (máx. 64 KB) y luego se le vuelve a entregar
        cuerpo = b""
        while True:
            msg = await receive()
            cuerpo += msg.get("body", b"")
            if len(cuerpo) > 65536:
                return await _responder(send, 413, "Datos demasiado grandes")
            if not msg.get("more_body"):
                break

        try:
            datos = json.loads(cuerpo or b"{}")
        except Exception:
            datos = None
        if datos is not None:
            error = _validar_auth(ruta, datos)
            if error:
                return await _responder(send, 400, error)

        correo = None
        if isinstance(datos, dict):
            correo = (
                datos.get("correo_institucional") or datos.get("correo") or datos.get("email")
            )
        if ruta == "/login" and isinstance(correo, str):
            try:
                u = _uno(
                    "SELECT estado_cuenta FROM Usuarios WHERE LOWER(correo_institucional) = LOWER(%s)",
                    (correo.strip(),),
                )
            except Exception:
                u = None  # si la base falla, que /login responda como siempre
            if u and u["estado_cuenta"] != "Activa":
                return await _responder(
                    send, 403, "Tu cuenta está suspendida, contacta al administrador"
                )

        entregado = False

        async def receive_de_nuevo():
            nonlocal entregado
            if not entregado:
                entregado = True
                return {"type": "http.request", "body": cuerpo, "more_body": False}
            return await receive()

        await self.app(scope, receive_de_nuevo, send)


# ==========================================================
# INSTALACIÓN
# ==========================================================


def instalar_v2(app: FastAPI, conectar: Optional[Callable] = None):
    """Quita de main.py las rutas que este archivo reemplaza y agrega todas
    las nuevas. Se llama al final de main.py."""
    global _conectar
    _conectar = conectar

    # "/reportes/{id}" y "/reportes/{id_reporte}" cuentan como la misma ruta
    def forma(path: str) -> str:
        return re.sub(r"\{[^}]*\}", "{}", path.rstrip("/"))

    nuevas = {
        (forma(ruta.path), metodo)
        for ruta in router.routes
        if isinstance(ruta, APIRoute)
        for metodo in ruta.methods
    }
    app.router.routes[:] = [
        r
        for r in app.router.routes
        if not (
            isinstance(r, APIRoute)
            and any((forma(r.path), m) in nuevas for m in r.methods)
        )
    ]
    app.include_router(router)

    # main.py monta la página web en "/" (StaticFiles). Ese montaje atrapa
    # todas las rutas que estén después de él, así que se manda al final
    from starlette.routing import Mount

    montajes = [r for r in app.router.routes if isinstance(r, Mount) and r.path in ("", "/")]
    app.router.routes[:] = [r for r in app.router.routes if r not in montajes] + montajes

    app.add_middleware(BloqueoLoginMiddleware)
