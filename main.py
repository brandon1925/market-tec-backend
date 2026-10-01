from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from passlib.context import CryptContext
from typing import List, Optional
import jwt
from datetime import datetime, timedelta
import os
import shutil

import models
import schemas
from database import engine, get_db

# Crea las tablas si no existen (comentado si ya existen en pgAdmin)
# models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="API Market-Tec")

# Crear carpeta para imágenes si no existe y montarla para que Flutter las pueda ver
os.makedirs("imagenes", exist_ok=True)
app.mount("/imagenes", StaticFiles(directory="imagenes"), name="imagenes")

# --- CONFIGURACIÓN DE SEGURIDAD ---
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()

SECRET_KEY = "market_tec_super_secreto_itz"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def crear_token_acceso(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

# EL "CADENERO": Esta función exige el token y extrae al usuario actual
def obtener_usuario_actual(credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    token = credentials.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        correo: str = payload.get("sub")
        if correo is None:
            raise HTTPException(status_code=401, detail="Token inválido")
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Token expirado o inválido")
    
    usuario = db.query(models.Usuario).filter(models.Usuario.correo_institucional == correo).first()
    if usuario is None:
        raise HTTPException(status_code=401, detail="Usuario no encontrado")
    return usuario

# --- RUTAS DE USUARIOS Y LOGIN ---

@app.post("/usuarios", response_model=schemas.UsuarioResponse)
def crear_usuario(usuario: schemas.UsuarioCreate, db: Session = Depends(get_db)):
    existe = db.query(models.Usuario).filter(models.Usuario.correo_institucional == usuario.correo_institucional).first()
    if existe:
        raise HTTPException(status_code=400, detail="El correo ya está registrado")
    
    nuevo_usuario = models.Usuario(
        numero_control=usuario.numero_control,
        nombre_completo=usuario.nombre_completo,
        username=usuario.username,
        correo_institucional=usuario.correo_institucional,
        password_hash=get_password_hash(usuario.password),
        id_rol=usuario.id_rol
    )
    db.add(nuevo_usuario)
    db.commit()
    db.refresh(nuevo_usuario)
    return nuevo_usuario

@app.post("/login", response_model=schemas.Token)
def iniciar_sesion(credenciales: schemas.UsuarioLogin, db: Session = Depends(get_db)):
    usuario = db.query(models.Usuario).filter(models.Usuario.correo_institucional == credenciales.correo_institucional).first()
    if not usuario or not verify_password(credenciales.password, usuario.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Credenciales incorrectas")
    
    access_token = crear_token_acceso(data={"sub": usuario.correo_institucional})
    return {"access_token": access_token, "token_type": "bearer"}

# --- RUTAS DE CATÁLOGO (PRODUCTOS) ---

# Crear producto (Protegido: asume que el vendedor es quien tiene la sesión iniciada)
@app.post("/productos", response_model=schemas.ProductoResponse)
def crear_producto(producto: schemas.ProductoCreate, usuario_actual: models.Usuario = Depends(obtener_usuario_actual), db: Session = Depends(get_db)):
    nuevo_producto = models.Producto(
        id_vendedor=usuario_actual.id_usuario, # Se asigna automáticamente al dueño del token
        id_categoria=producto.id_categoria,
        nombre_producto=producto.nombre_producto,
        descripcion=producto.descripcion,
        precio_actual=producto.precio_actual,
        imagen_url=producto.imagen_url
    )
    db.add(nuevo_producto)
    db.commit()
    db.refresh(nuevo_producto)
    return nuevo_producto

# Subir imagen física del producto (Protegido)
@app.post("/productos/{id_producto}/imagen")
def subir_imagen_producto(id_producto: int, archivo: UploadFile = File(...), usuario_actual: models.Usuario = Depends(obtener_usuario_actual), db: Session = Depends(get_db)):
    producto = db.query(models.Producto).filter(models.Producto.id_producto == id_producto, models.Producto.id_vendedor == usuario_actual.id_usuario).first()
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado o no te pertenece")
    
    # Guarda el archivo en la carpeta "imagenes"
    ruta_archivo = f"imagenes/{id_producto}_{archivo.filename}"
    with open(ruta_archivo, "wb") as buffer:
        shutil.copyfileobj(archivo.file, buffer)
    
    producto.imagen_url = f"/{ruta_archivo}" # Actualiza la base de datos
    db.commit()
    return {"mensaje": "Imagen subida con éxito", "url": producto.imagen_url}

# Catálogo con Búsqueda, Filtros y Paginación (Público)
@app.get("/productos", response_model=List[schemas.ProductoResponse])
def obtener_productos(skip: int = 0, limit: int = 20, busqueda: Optional[str] = None, categoria: Optional[int] = None, db: Session = Depends(get_db)):
    consulta = db.query(models.Producto)
    
    if busqueda:
        consulta = consulta.filter(models.Producto.nombre_producto.ilike(f"%{busqueda}%"))
    if categoria:
        consulta = consulta.filter(models.Producto.id_categoria == categoria)
        
    return consulta.offset(skip).limit(limit).all()

# --- RUTAS DE TRANSACCIONES (PEDIDOS) ---

# Comprar un producto (Protegido: el cliente es quien tiene la sesión iniciada)
@app.post("/pedidos", response_model=schemas.PedidoResponse)
def crear_pedido(pedido: schemas.PedidoCreate, usuario_actual: models.Usuario = Depends(obtener_usuario_actual), db: Session = Depends(get_db)):
    nuevo_pedido = models.Pedido(
        id_cliente=usuario_actual.id_usuario,
        id_vendedor=pedido.id_vendedor,
        id_producto=pedido.id_producto,
        cantidad=pedido.cantidad,
        precio_congelado=pedido.precio_congelado,
        total_venta=pedido.total_venta
    )
    db.add(nuevo_pedido)
    db.commit()
    db.refresh(nuevo_pedido)
    return nuevo_pedido

# Ver mis compras (Como cliente)
@app.get("/mis-compras", response_model=List[schemas.PedidoResponse])
def mis_compras(usuario_actual: models.Usuario = Depends(obtener_usuario_actual), db: Session = Depends(get_db)):
    return db.query(models.Pedido).filter(models.Pedido.id_cliente == usuario_actual.id_usuario).all()

# Ver lo que me han comprado (Como vendedor)
@app.get("/mis-ventas", response_model=List[schemas.PedidoResponse])
def mis_ventas(usuario_actual: models.Usuario = Depends(obtener_usuario_actual), db: Session = Depends(get_db)):
    return db.query(models.Pedido).filter(models.Pedido.id_vendedor == usuario_actual.id_usuario).all()

# Actualizar el estado de un pedido (Ej. de Pendiente a Entregado)
@app.put("/pedidos/{id_pedido}/estado", response_model=schemas.PedidoResponse)
def actualizar_estado_pedido(id_pedido: int, estado: schemas.PedidoEstadoUpdate, usuario_actual: models.Usuario = Depends(obtener_usuario_actual), db: Session = Depends(get_db)):
    pedido = db.query(models.Pedido).filter(models.Pedido.id_pedido == id_pedido, models.Pedido.id_vendedor == usuario_actual.id_usuario).first()
    if not pedido:
        raise HTTPException(status_code=404, detail="Pedido no encontrado o no tienes permiso")
    
    pedido.estado_solicitud = estado.estado_solicitud
    db.commit()
    db.refresh(pedido)
    return pedido

# --- RUTAS DE HORARIOS DE ENTREGA ---
@app.post("/horarios", response_model=schemas.HorarioResponse)
def crear_horario(horario: schemas.HorarioCreate, usuario_actual: models.Usuario = Depends(obtener_usuario_actual), db: Session = Depends(get_db)):
    nuevo_horario = models.HorarioVendedor(
        id_vendedor=usuario_actual.id_usuario,
        dia_semana=horario.dia_semana,
        hora_inicio=horario.hora_inicio,
        hora_fin=horario.hora_fin
    )
    db.add(nuevo_horario)
    db.commit()
    db.refresh(nuevo_horario)
    return nuevo_horario

@app.get("/horarios/{id_vendedor}", response_model=List[schemas.HorarioResponse])
def ver_horarios_vendedor(id_vendedor: int, db: Session = Depends(get_db)):
    return db.query(models.HorarioVendedor).filter(models.HorarioVendedor.id_vendedor == id_vendedor).all()