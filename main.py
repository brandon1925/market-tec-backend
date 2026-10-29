import smtplib
import random
import os
import shutil
import re
import unicodedata
from email.message import EmailMessage
from fastapi import FastAPI, HTTPException, Depends, UploadFile, File, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Float, ForeignKey, Boolean, Time
from sqlalchemy.orm import declarative_base, sessionmaker, Session, relationship
from datetime import time, date, datetime
from typing import Optional

# ==========================================
# 1. CONFIGURACIÓN DE BASE DE DATOS
# ==========================================
DATABASE_URL = "postgresql://postgres:root@localhost:5432/market_tec_db"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

os.makedirs("static/productos", exist_ok=True)

# ==========================================
# 2. MODELOS DE BASE DE DATOS (SQLAlchemy)
# ==========================================
class Rol(Base):
    __tablename__ = "roles"
    id_rol = Column(Integer, primary_key=True)
    nombre_rol = Column(String(50), nullable=False)

class Usuario(Base):
    __tablename__ = "usuarios"
    id_usuario = Column(Integer, primary_key=True, index=True)
    numero_control = Column(String(20), unique=True, nullable=False)
    nombre_completo = Column(String(150), nullable=False)
    username = Column(String(50), unique=True, nullable=False)
    correo_institucional = Column(String(100), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    id_rol = Column(Integer, ForeignKey("roles.id_rol"))
    estado_cuenta = Column(String(20), default='Activa')
    compartir_ubicacion = Column(Boolean, default=False)
    latitud = Column(Float, nullable=True)
    longitud = Column(Float, nullable=True)
    
    rol = relationship("Rol")
    productos = relationship("Producto", back_populates="vendedor")

class Categoria(Base):
    __tablename__ = "categorias"
    id_categoria = Column(Integer, primary_key=True)
    nombre = Column(String(100), nullable=False)

class Producto(Base):
    __tablename__ = "productos"
    id_producto = Column(Integer, primary_key=True, index=True)
    id_vendedor = Column(Integer, ForeignKey("usuarios.id_usuario", ondelete="CASCADE"))
    id_categoria = Column(Integer, ForeignKey("categorias.id_categoria"))
    
    nombre_producto = Column(String, nullable=False)
    precio_actual = Column(Float, nullable=False)
    descripcion = Column(String, nullable=True)
    estado = Column(String, nullable=False, default="Nuevo") 
    stock = Column(Integer, nullable=False, default=1) 
    imagen_url = Column(String, nullable=True)
    ventas_concretadas = Column(Integer, default=0)
    pausado_por_agotado = Column(Boolean, default=False) 
    
    vendedor = relationship("Usuario", back_populates="productos")
    categoria_rel = relationship("Categoria")

class Logistica(Base):
    __tablename__ = "configuracion_logistica"
    id_logistica = Column(Integer, primary_key=True)
    id_vendedor = Column(Integer, ForeignKey("usuarios.id_usuario", ondelete="CASCADE"))
    tipo_entrega = Column(String(50), nullable=False, default="Entrega en campus")
    descripcion_punto_fijo = Column(String, nullable=True)

class Horario(Base):
    __tablename__ = "horarios_vendedor"
    id_horario = Column(Integer, primary_key=True)
    id_vendedor = Column(Integer, ForeignKey("usuarios.id_usuario", ondelete="CASCADE"))
    dia_semana = Column(Integer, nullable=False) 
    hora_inicio = Column(Time, nullable=False)
    hora_fin = Column(Time, nullable=False)

class Pedido(Base):
    __tablename__ = "pedidos"
    id_pedido = Column(Integer, primary_key=True)
    id_cliente = Column(Integer, ForeignKey("usuarios.id_usuario"))
    id_vendedor = Column(Integer, ForeignKey("usuarios.id_usuario"))
    id_producto = Column(Integer, ForeignKey("productos.id_producto"))
    cantidad = Column(Integer, nullable=False)
    precio_congelado = Column(Float, nullable=False)
    total_venta = Column(Float, nullable=False)
    estado_solicitud = Column(String(30), default='Pendiente')
    producto_rel = relationship("Producto")

class Favoritos(Base):
    __tablename__ = "favoritos"
    id_favorito = Column(Integer, primary_key=True)
    id_cliente = Column(Integer, ForeignKey("usuarios.id_usuario", ondelete="CASCADE"))
    id_producto = Column(Integer, ForeignKey("productos.id_producto", ondelete="CASCADE"))

class ReporteCreate(BaseModel):
    id_reportante: int
    id_producto: Optional[int] = None
    id_vendedor: Optional[int] = None
    motivo: str
    descripcion: str

class Resena(Base):
    __tablename__ = "resenas"
    id_resena = Column(Integer, primary_key=True)
    id_producto = Column(Integer, ForeignKey("productos.id_producto", ondelete="CASCADE"))
    id_cliente = Column(Integer, ForeignKey("usuarios.id_usuario", ondelete="CASCADE"))
    calificacion = Column(Integer, nullable=False)
    comentario = Column(String, nullable=True)
    fecha = Column(String, default=lambda: date.today().isoformat())
    
    cliente = relationship("Usuario")

Base.metadata.create_all(bind=engine)

# ==========================================
# 3. ESQUEMAS DE VALIDACIÓN (Pydantic)
# ==========================================
class EmailRequest(BaseModel):
    correo: str

class LoginRequest(BaseModel):
    correo_institucional: str
    password: str

class UserCreate(BaseModel):
    numero_control: str
    nombre_completo: str
    username: str
    correo_institucional: str
    password: str
    id_rol: int = 1

class RecuperarRequest(BaseModel):
    correo: str

class RestablecerRequest(BaseModel):
    correo: str
    nueva_password: str

class UpdateRolRequest(BaseModel):
    nuevo_rol_id: int

class UpdateLogisticaRequest(BaseModel):
    tipo_entrega: str

class CreateHorarioRequest(BaseModel):
    id_vendedor: int
    dia_semana: int
    hora_inicio: str
    hora_fin: str

class ProductoCreate(BaseModel):
    nombre: str
    precio: float
    descripcion: Optional[str] = None
    estado: str
    categoria: str
    stock: int
    imagen_url: Optional[str] = None
    vendedor_id: int

class ProductoUpdate(BaseModel):
    nombre: str
    precio: float
    descripcion: Optional[str] = None
    estado: str
    categoria: str
    stock: int

class PedidoCreate(BaseModel):
    id_cliente: int
    id_vendedor: int
    id_producto: int
    cantidad: int
    precio_congelado: float
    total_venta: float

class FavoritoRequest(BaseModel):
    id_producto: int
    id_cliente: int

class UbicacionUpdate(BaseModel):
    compartir: bool
    latitud: Optional[float] = None
    longitud: Optional[float] = None

class UpdatePedidoEstado(BaseModel):
    nuevo_estado: str

class ResenaCreate(BaseModel):
    id_producto: int
    id_cliente: int
    calificacion: int
    comentario: Optional[str] = None

# ==========================================
# 4. API SETUP & HELPERS
# ==========================================
app = FastAPI(title="Market-Tec API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/static", StaticFiles(directory="/home/ubuntu/backend_api/static"), name="static")

def calcular_rating_promedio(db: Session, id_producto: int) -> float:
    resenas = db.query(Resena).filter(Resena.id_producto == id_producto).all()
    if not resenas:
        return 0.0
    return round(sum(r.calificacion for r in resenas) / len(resenas), 1)

def normalizar_texto(texto: str) -> str:
    if not texto:
        return ""
    texto = texto.lower()
    return ''.join(c for c in unicodedata.normalize('NFD', texto) if unicodedata.category(c) != 'Mn')

# ==========================================
# 5. BÚSQUEDA LÉXICA Y SEMÁNTICA LOCAL
# ==========================================
@app.get("/productos/buscar")
def buscar_productos(q: str, db: Session = Depends(get_db)):
    if not q or not q.strip():
        return obtener_productos_catalogo(db)

    stop_words = {"un", "una", "unos", "unas", "el", "la", "los", "las", "para", "de", "a", "en", "con", "por", "que", "su", "busco", "quiero", "algo"}
    q_norm = normalizar_texto(q)
    
    max_precio = None
    min_precio = None
    
    match_menos = re.search(r'(?:menos|menor|abajo|maximo) (?:de|a) (\d+)|< ?(\d+)|hasta (\d+)', q_norm)
    if match_menos:
        max_precio = float(match_menos.group(1) or match_menos.group(2) or match_menos.group(3))
        q_norm = re.sub(r'(?:menos|menor|abajo|maximo) (?:de|a) \d+|< ?\d+|hasta \d+', '', q_norm)
        
    match_mas = re.search(r'(?:mas|mayor|arriba|minimo) (?:de|a) (\d+)|> ?(\d+)|desde (\d+)', q_norm)
    if match_mas:
        min_precio = float(match_mas.group(1) or match_mas.group(2) or match_mas.group(3))
        q_norm = re.sub(r'(?:mas|mayor|arriba|minimo) (?:de|a) \d+|> ?\d+|desde \d+', '', q_norm)

    palabras_clave = [word for word in q_norm.split() if word not in stop_words]
    productos_activos = db.query(Producto).filter(Producto.pausado_por_agotado == False, Producto.stock > 0).all()
    resultados = []
    
    for p in productos_activos:
        if max_precio is not None and p.precio_actual > max_precio:
            continue
        if min_precio is not None and p.precio_actual < min_precio:
            continue
            
        if not palabras_clave:
            resultados.append((1, p))
            continue
        
        score = 0
        texto_producto = normalizar_texto(f"{p.nombre_producto} {p.descripcion or ''} {p.categoria_rel.nombre if p.categoria_rel else ''} {p.vendedor.nombre_completo if p.vendedor else ''}")
        
        for palabra in palabras_clave:
            if palabra in texto_producto:
                score += 1
                
        if score > 0:
            resultados.append((score, p))
    
    resultados.sort(key=lambda x: x[0], reverse=True)
    
    return [
        {
            "id": res[1].id_producto,
            "nombre": res[1].nombre_producto,
            "precio": res[1].precio_actual,
            "descripcion": res[1].descripcion,
            "estado": res[1].estado,
            "categoria": res[1].categoria_rel.nombre if res[1].categoria_rel else "Otros",
            "imagen_url": res[1].imagen_url,
            "vendedor_id": res[1].id_vendedor,
            "vendedor_nombre": res[1].vendedor.nombre_completo if res[1].vendedor else "Desconocido",
            "stock": res[1].stock,
            "rating": calcular_rating_promedio(db, res[1].id_producto)
        }
        for res in resultados
    ]

# ==========================================
# 6. RUTAS BASE (Auth, Correos, Imágenes, Estadísticas)
# ==========================================
@app.post("/upload-imagen")
async def upload_imagen(request: Request, file: UploadFile = File(...)):
    file_location = f"static/productos/{file.filename}"
    with open(file_location, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    base_url = str(request.base_url).rstrip("/")
    return {"url": f"{base_url}/static/productos/{file.filename}"}

@app.post("/enviar-codigo")
async def enviar_codigo_email(req: EmailRequest):
    codigo = str(random.randint(1000, 9999))
    remitente = "belc1109@gmail.com" 
    password_app = "xfbqmonpklvkolvq" 
    msg = EmailMessage()
    msg.set_content(f"Tu código de verificación para Market-Tec es: {codigo}")
    msg['Subject'] = 'Código - Market-Tec'
    msg['From'] = remitente
    msg['To'] = req.correo 
    server = smtplib.SMTP_SSL('smtp.gmail.com', 465)
    server.login(remitente, password_app)
    server.send_message(msg)
    server.quit()
    return {"codigo_secreto": codigo}

@app.post("/usuarios")
def crear_usuario(request: UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(Usuario).filter(Usuario.correo_institucional == request.correo_institucional).first()
    if db_user:
        raise HTTPException(status_code=400, detail="El correo ya está registrado")
    nuevo = Usuario(
        numero_control=request.numero_control,
        nombre_completo=request.nombre_completo,
        username=request.username,
        correo_institucional=request.correo_institucional,
        password_hash=request.password,
        id_rol=request.id_rol
    )
    db.add(nuevo)
    db.commit()
    db.refresh(nuevo)
    db.add(Logistica(id_vendedor=nuevo.id_usuario, tipo_entrega="Entrega en campus"))
    db.commit()
    return {"user_id": nuevo.id_usuario}

@app.post("/login")
def login(request: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.correo_institucional == request.correo_institucional).first()
    if not user or user.password_hash != request.password:
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")
    return {
        "user_id": user.id_usuario,
        "nombre_completo": user.nombre_completo,
        "username": user.username,
        "correo_institucional": user.correo_institucional,
        "numero_control": user.numero_control,
        "estado_cuenta": user.estado_cuenta,
        "rol": user.rol.nombre_rol if user.rol else "Cliente"
    }

@app.put("/usuarios/{user_id}/rol")
def actualizar_rol(user_id: int, req: UpdateRolRequest, db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.id_usuario == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.id_rol = req.nuevo_rol_id
    db.commit()
    return {"message": "Rol actualizado"}

@app.post("/recuperar-password/enviar")
async def enviar_codigo_recuperacion(req: RecuperarRequest, db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.correo_institucional == req.correo).first()
    if not user:
        raise HTTPException(status_code=404, detail="Este correo no está registrado en Market-Tec")
    codigo = str(random.randint(1000, 9999))
    remitente = "belc1109@gmail.com"
    password_app = "xfbqmonpklvkolvq" 
    msg = EmailMessage()
    msg.set_content(f"Hola {user.nombre_completo},\n\nTu código es: {codigo}")
    msg['Subject'] = 'Recuperación de Contraseña'
    msg['From'] = remitente
    msg['To'] = req.correo
    server = smtplib.SMTP_SSL('smtp.gmail.com', 465)
    server.login(remitente, password_app)
    server.send_message(msg)
    server.quit()
    return {"codigo_secreto": codigo}

@app.post("/recuperar-password/restablecer")
def restablecer_password(req: RestablecerRequest, db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.correo_institucional == req.correo).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.password_hash = req.nueva_password
    db.commit()
    return {"message": "Contraseña actualizada exitosamente"}

@app.get("/estadisticas/inicio")
def obtener_estadisticas(db: Session = Depends(get_db)):
    ventas_reales = db.query(Pedido).filter(Pedido.estado_solicitud.in_(['Confirmado', 'Entregado'])).count()
    return {
        "estudiantes_activos": db.query(Usuario).filter(Usuario.estado_cuenta == 'Activa').count(),
        "productos_vendidos": ventas_reales if ventas_reales > 0 else db.query(Producto).count(),
        "carreras_itz": 7
    }

# ==========================================
# 7. RUTAS DE GPS Y MAPA REAL
# ==========================================
@app.put("/ubicacion/{user_id}")
def actualizar_mi_ubicacion(user_id: int, req: UbicacionUpdate, db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.id_usuario == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.compartir_ubicacion = req.compartir
    user.latitud = req.latitud
    user.longitud = req.longitud
    db.commit()
    return {"message": "Ubicación actualizada en BD"}

@app.get("/ubicaciones/activas")
def obtener_todos_los_vendedores_activos(db: Session = Depends(get_db)):
    activos = db.query(Usuario).filter(Usuario.compartir_ubicacion == True, Usuario.id_rol > 1).all()
    res = []
    for u in activos:
        if u.latitud is None or u.longitud is None:
            continue
        prod = db.query(Producto).filter(Producto.id_vendedor == u.id_usuario, Producto.pausado_por_agotado == False).first()
        producto_nombre = prod.nombre_producto if prod else "Varios productos"
        res.append({
            "id": u.id_usuario,
            "nombre": u.nombre_completo,
            "inicial": u.nombre_completo[0].upper() if u.nombre_completo else "V",
            "latitud": u.latitud,
            "longitud": u.longitud,
            "producto": producto_nombre
        })
    return res

# ==========================================
# 8. RUTAS DE LOGÍSTICA Y HORARIOS
# ==========================================
@app.get("/logistica/{vendedor_id}")
def obtener_logistica(vendedor_id: int, db: Session = Depends(get_db)):
    logi = db.query(Logistica).filter(Logistica.id_vendedor == vendedor_id).first()
    if not logi:
        logi = Logistica(id_vendedor=vendedor_id, tipo_entrega="Entrega en campus")
        db.add(logi)
        db.commit()
        db.refresh(logi)
    return {"tipo_entrega": logi.tipo_entrega}

@app.put("/logistica/{vendedor_id}")
def actualizar_logistica(vendedor_id: int, req: UpdateLogisticaRequest, db: Session = Depends(get_db)):
    logi = db.query(Logistica).filter(Logistica.id_vendedor == vendedor_id).first()
    if logi:
        logi.tipo_entrega = req.tipo_entrega
    else:
        db.add(Logistica(id_vendedor=vendedor_id, tipo_entrega=req.tipo_entrega))
    db.commit()
    return {"message": "Modalidad actualizada"}

@app.get("/horarios/{vendedor_id}")
def obtener_horarios(vendedor_id: int, db: Session = Depends(get_db)):
    horarios = db.query(Horario).filter(Horario.id_vendedor == vendedor_id).order_by(Horario.dia_semana, Horario.hora_inicio).all()
    return [
        {
            "id": h.id_horario,
            "dia": h.dia_semana,
            "inicio": h.hora_inicio.strftime("%H:%M"),
            "fin": h.hora_fin.strftime("%H:%M")
        }
        for h in horarios
    ]

@app.post("/horarios")
def agregar_horario(req: CreateHorarioRequest, db: Session = Depends(get_db)):
    h_ini = datetime.strptime(req.hora_inicio, "%H:%M").time()
    h_fin = datetime.strptime(req.hora_fin, "%H:%M").time()
    nuevo = Horario(id_vendedor=req.id_vendedor, dia_semana=req.dia_semana, hora_inicio=h_ini, hora_fin=h_fin)
    db.add(nuevo)
    db.commit()
    return {"message": "Turno agregado"}

@app.delete("/horarios/{id_horario}")
def eliminar_horario(id_horario: int, db: Session = Depends(get_db)):
    db.query(Horario).filter(Horario.id_horario == id_horario).delete()
    db.commit()
    return {"message": "Turno eliminado"}

# ==========================================
# 9. RUTAS DE PEDIDOS Y REGLAS DE INVENTARIO
# ==========================================
@app.get("/pedidos/vendedor/{vendedor_id}")
def obtener_pedidos_pendientes(vendedor_id: int, db: Session = Depends(get_db)):
    pedidos = db.query(Pedido).filter(Pedido.id_vendedor == vendedor_id, Pedido.estado_solicitud == 'Pendiente').order_by(Pedido.id_pedido.desc()).all()
    res = []
    for p in pedidos:
        cliente = db.query(Usuario).filter(Usuario.id_usuario == p.id_cliente).first()
        res.append({
            "id_pedido": p.id_pedido,
            "cliente_nombre": cliente.nombre_completo if cliente else "Desconocido",
            "producto": p.producto_rel.nombre_producto if p.producto_rel else "Producto eliminado",
            "cantidad": p.cantidad,
            "total": p.total_venta
        })
    return res

@app.get("/pedidos/vendedor/{vendedor_id}/historial")
def obtener_historial_pedidos(vendedor_id: int, db: Session = Depends(get_db)):
    # Ordenamos por id_pedido en lugar de fecha_hora_pedido para evitar el Error 500
    pedidos = db.query(Pedido).filter(
        Pedido.id_vendedor == vendedor_id,
        Pedido.estado_solicitud != 'Pendiente'
    ).order_by(Pedido.id_pedido.desc()).all()
    
    res = []
    for p in pedidos:
        cliente = db.query(Usuario).filter(Usuario.id_usuario == p.id_cliente).first()
        res.append({
            "id_pedido": p.id_pedido,
            "cliente_nombre": cliente.nombre_completo if cliente else "Desconocido",
            "producto": p.producto_rel.nombre_producto if p.producto_rel else "Producto eliminado",
            "cantidad": p.cantidad,
            "total": p.total_venta,
            "estado": p.estado_solicitud,
            "fecha": "Reciente"
        })
    return res

@app.post("/pedidos")
def crear_pedido(pedido: PedidoCreate, db: Session = Depends(get_db)):
    prod = db.query(Producto).filter(Producto.id_producto == pedido.id_producto).first()
    if not prod:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    
    if prod.pausado_por_agotado or prod.stock < pedido.cantidad:
        raise HTTPException(status_code=400, detail="Stock insuficiente")
    
    # 1. Restamos el stock inmediatamente al solicitar la compra
    prod.stock -= pedido.cantidad
    
    # 2. Si se compran las últimas existencias (queda en 0), se pausa automáticamente
    if prod.stock <= 0:
        prod.stock = 0
        prod.pausado_por_agotado = True

    nuevo_pedido = Pedido(
        id_cliente=pedido.id_cliente,
        id_vendedor=pedido.id_vendedor,
        id_producto=pedido.id_producto,
        cantidad=pedido.cantidad,
        precio_congelado=pedido.precio_congelado,
        total_venta=pedido.total_venta,
        estado_solicitud='Pendiente'
    )
    db.add(nuevo_pedido)
    db.commit()
    db.refresh(nuevo_pedido)
    return {"message": "Pedido solicitado", "id_pedido": nuevo_pedido.id_pedido}

@app.put("/pedidos/{id_pedido}/estado")
def actualizar_estado_pedido(id_pedido: int, req: UpdatePedidoEstado, db: Session = Depends(get_db)):
    pedido = db.query(Pedido).filter(Pedido.id_pedido == id_pedido).first()
    if not pedido:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    
    estado_anterior = pedido.estado_solicitud
    prod = db.query(Producto).filter(Producto.id_producto == pedido.id_producto).first()

    # Si el vendedor niega la venta o no se entrega, devolvemos el stock y reanudamos la publicación
    if req.nuevo_estado in ['Rechazado_Agotado', 'Cancelado', 'No entregada'] and estado_anterior not in ['Rechazado_Agotado', 'Cancelado', 'No entregada']:
        if prod:
            prod.stock += pedido.cantidad
            if prod.stock > 0:
                prod.pausado_por_agotado = False
                
    # Si confirma la venta, sumamos las unidades vendidas
    elif req.nuevo_estado == 'Confirmado' and estado_anterior == 'Pendiente':
        if prod:
            prod.ventas_concretadas = (prod.ventas_concretadas or 0) + pedido.cantidad
            if prod.stock <= 0:
                prod.pausado_por_agotado = True

    pedido.estado_solicitud = req.nuevo_estado
    db.commit()
    return {"message": "Estado actualizado correctamente"}
# ==========================================
# 10. RUTAS DE COMPRAS DEL CLIENTE Y RESEÑAS
# ==========================================
@app.get("/mis-compras/{cliente_id}")
def obtener_mis_compras(cliente_id: int, db: Session = Depends(get_db)):
    pedidos = db.query(Pedido).filter(Pedido.id_cliente == cliente_id).order_by(Pedido.id_pedido.desc()).all()
    res = []
    for p in pedidos:
        ya_calificado = db.query(Resena).filter(
            Resena.id_producto == p.id_producto,
            Resena.id_cliente == cliente_id
        ).first() is not None
        
        vendedor = db.query(Usuario).filter(Usuario.id_usuario == p.id_vendedor).first()
        res.append({
            "id_pedido": p.id_pedido,
            "id_producto": p.id_producto,
            "producto_nombre": p.producto_rel.nombre_producto if p.producto_rel else "Producto eliminado",
            "vendedor_nombre": vendedor.nombre_completo if vendedor else "Desconocido",
            "imagen_url": (p.producto_rel.imagen_url if p.producto_rel and p.producto_rel.imagen_url else "https://images.unsplash.com/photo-1582058091505-f87a2e55a40f"),
            "cantidad": p.cantidad,
            "total": p.total_venta,
            "estado": p.estado_solicitud,
            "ya_calificado": ya_calificado
        })
    return res

@app.post("/resenas")
def crear_resena(req: ResenaCreate, db: Session = Depends(get_db)):
    nueva = Resena(
        id_producto=req.id_producto,
        id_cliente=req.id_cliente,
        calificacion=req.calificacion,
        comentario=req.comentario
    )
    db.add(nueva)
    db.commit()
    return {"message": "Reseña guardada exitosamente"}

@app.get("/productos/{id_producto}/resenas")
def obtener_resenas_producto(id_producto: int, db: Session = Depends(get_db)):
    resenas = db.query(Resena).filter(Resena.id_producto == id_producto).order_by(Resena.id_resena.desc()).all()
    return [
        {
            "cliente": r.cliente.nombre_completo if r.cliente else "Anónimo",
            "calificacion": r.calificacion,
            "comentario": r.comentario or "",
            "fecha": r.fecha
        }
        for r in resenas
    ]

# ==========================================
# 11. PRODUCTOS (CRUD) Y FAVORITOS
# ==========================================
@app.post("/productos")
def crear_producto(producto: ProductoCreate, db: Session = Depends(get_db)):
    cat = db.query(Categoria).filter(Categoria.nombre == producto.categoria).first()
    id_cat = cat.id_categoria if cat else 6 
    nuevo_producto = Producto(
        nombre_producto=producto.nombre,
        precio_actual=producto.precio,
        descripcion=producto.descripcion,
        estado=producto.estado,
        stock=producto.stock,
        id_categoria=id_cat,
        imagen_url=producto.imagen_url,
        id_vendedor=producto.vendedor_id,
        pausado_por_agotado=(producto.stock <= 0)
    )
    db.add(nuevo_producto)
    db.commit()
    db.refresh(nuevo_producto)
    return {"id_producto": nuevo_producto.id_producto}

@app.get("/productos")
def obtener_productos_catalogo(db: Session = Depends(get_db)):
    # Solo mostramos productos que NO estén pausados y que tengan stock > 0
    productos = db.query(Producto).filter(Producto.pausado_por_agotado == False, Producto.stock > 0).all()
    return [
        {
            "id": p.id_producto,
            "nombre": p.nombre_producto,
            "precio": p.precio_actual,
            "descripcion": p.descripcion,
            "estado": p.estado,
            "categoria": p.categoria_rel.nombre if p.categoria_rel else "Otros",
            "imagen_url": p.imagen_url,
            "vendedor_id": p.id_vendedor,
            "vendedor_nombre": p.vendedor.nombre_completo if p.vendedor else "Desconocido",
            "stock": p.stock,
            "rating": calcular_rating_promedio(db, p.id_producto)
        }
        for p in productos
    ]

@app.get("/productos/vendedor/{vendedor_id}")
def obtener_productos_vendedor(vendedor_id: int, db: Session = Depends(get_db)):
    productos = db.query(Producto).filter(Producto.id_vendedor == vendedor_id).order_by(Producto.id_producto.desc()).all()
    return [
        {
            "id": p.id_producto,
            "nombre": p.nombre_producto,
            "precio": p.precio_actual,
            "descripcion": p.descripcion,
            "estado": p.estado,
            "stock": p.stock,
            "pausado": p.pausado_por_agotado,
            "categoria": p.categoria_rel.nombre if p.categoria_rel else "Otros",
            "imagen_url": p.imagen_url,
            "vendedor_id": p.id_vendedor,
            "rating": calcular_rating_promedio(db, p.id_producto)
        }
        for p in productos
    ]

@app.put("/productos/{id_producto}")
def editar_producto(id_producto: int, req: ProductoUpdate, db: Session = Depends(get_db)):
    prod = db.query(Producto).filter(Producto.id_producto == id_producto).first()
    if not prod:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    cat = db.query(Categoria).filter(Categoria.nombre == req.categoria).first()
    prod.nombre_producto = req.nombre
    prod.precio_actual = req.precio
    prod.descripcion = req.descripcion
    prod.estado = req.estado
    prod.stock = req.stock
    prod.id_categoria = cat.id_categoria if cat else 6
    prod.pausado_por_agotado = (req.stock <= 0)
    db.commit()
    return {"message": "Producto actualizado"}

@app.put("/productos/{id_producto}/pausar")
def pausar_producto(id_producto: int, db: Session = Depends(get_db)):
    prod = db.query(Producto).filter(Producto.id_producto == id_producto).first()
    if not prod:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    # Si intenta despausar un producto con stock 0, no se lo permitimos hasta que suba el stock
    if prod.pausado_por_agotado and prod.stock <= 0:
        raise HTTPException(status_code=400, detail="Agrega más stock antes de reanudar la venta")
    prod.pausado_por_agotado = not prod.pausado_por_agotado
    db.commit()
    return {"pausado": prod.pausado_por_agotado}

@app.delete("/productos/{id_producto}")
def eliminar_producto(id_producto: int, db: Session = Depends(get_db)):
    db.query(Producto).filter(Producto.id_producto == id_producto).delete()
    db.commit()
    return {"message": "Producto eliminado"}

@app.post("/favoritos")
def toggle_favorito(req: FavoritoRequest, db: Session = Depends(get_db)):
    fav = db.query(Favoritos).filter(Favoritos.id_cliente == req.id_cliente, Favoritos.id_producto == req.id_producto).first()
    if fav:
        db.delete(fav)
        db.commit()
        return {"message": "Removido", "is_favorite": False}
    else:
        db.add(Favoritos(id_cliente=req.id_cliente, id_producto=req.id_producto))
        db.commit()
        return {"message": "Agregado", "is_favorite": True}

@app.get("/favoritos/{cliente_id}")
def obtener_favoritos(cliente_id: int, db: Session = Depends(get_db)):
    favs = db.query(Favoritos.id_producto).filter(Favoritos.id_cliente == cliente_id).all()
    return [f[0] for f in favs]

@app.post("/reportes")
def crear_reporte(req: ReporteCreate, db: Session = Depends(get_db)):
    nuevo = Reporte(
        id_reportante=req.id_reportante,
        id_producto=req.id_producto,
        id_vendedor=req.id_vendedor,
        motivo=req.motivo,
        descripcion=req.descripcion
    )
    db.add(nuevo)
    db.commit()
    return {"message": "Reporte enviado correctamente"}

@app.get("/reportes")
def obtener_reportes(db: Session = Depends(get_db)):
    reportes = db.query(Reporte).order_by(Reporte.id_reporte.desc()).all()
    res = []
    for r in reportes:
        usuario = db.query(Usuario).filter(Usuario.id_usuario == r.id_reportante).first()
        prod = db.query(Producto).filter(Producto.id_producto == r.id_producto).first() if r.id_producto else None
        res.append({
            "id_reporte": r.id_reporte,
            "reportante": usuario.nombre_completo if usuario else "Anónimo",
            "producto": prod.nombre_producto if prod else "General",
            "motivo": r.motivo,
            "descripcion": r.descripcion,
            "estado": r.estado,
            "fecha": r.fecha
        })
    return res

# ==========================================
# RUTAS EXCLUSIVAS DE ADMINISTRACIÓN
# ==========================================
class UpdateEstadoCuentaRequest(BaseModel):
    nuevo_estado: str

class UpdateEstadoReporteRequest(BaseModel):
    nuevo_estado: str

@app.get("/admin/usuarios")
def obtener_todos_los_usuarios(db: Session = Depends(get_db)):
    usuarios = db.query(Usuario).order_by(Usuario.id_usuario.asc()).all()
    res = []
    for u in usuarios:
        total_prods = db.query(Producto).filter(Producto.id_vendedor == u.id_usuario).count()
        res.append({
            "id_usuario": u.id_usuario,
            "numero_control": u.numero_control,
            "nombre_completo": u.nombre_completo,
            "username": u.username,
            "correo": u.correo_institucional,
            "rol": u.rol.nombre_rol if u.rol else "Cliente",
            "id_rol": u.id_rol or 1,
            "estado_cuenta": u.estado_cuenta or "Activa",
            "productos_publicados": total_prods
        })
    return res

@app.put("/admin/usuarios/{user_id}/estado")
def cambiar_estado_cuenta(user_id: int, req: UpdateEstadoCuentaRequest, db: Session = Depends(get_db)):
    user = db.query(Usuario).filter(Usuario.id_usuario == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.estado_cuenta = req.nuevo_estado
    if req.nuevo_estado != "Activa":
        user.compartir_ubicacion = False
    db.commit()
    return {"message": "Estado de cuenta actualizado"}

@app.put("/admin/reportes/{id_reporte}/estado")
def cambiar_estado_reporte(id_reporte: int, req: UpdateEstadoReporteRequest, db: Session = Depends(get_db)):
    rep = db.query(Reporte).filter(Reporte.id_reporte == id_reporte).first()
    if not rep:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")
    rep.estado = req.nuevo_estado
    db.commit()
    return {"message": "Estado de reporte actualizado"}

from fastapi.responses import FileResponse
import os

@app.get("/descargar-apk")
def descargar_apk():
    apk_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static", "Market-Tec-ITZ.apk")
    return FileResponse(
        path=apk_path,
        filename="Market-Tec-ITZ.apk",
        media_type="application/vnd.android.package-archive"
    )

app.mount("/", StaticFiles(directory="/var/www/market_tec", html=True), name="web")

from market_tec_v2 import instalar_v2
instalar_v2(app, conectar=engine.raw_connection)
