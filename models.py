from sqlalchemy import Column, Integer, String, Boolean, Numeric, ForeignKey, DateTime, Time, Text
from sqlalchemy.orm import relationship
from database import Base
import datetime

# 1. SEGURIDAD Y USUARIOS
class Rol(Base):
    __tablename__ = "roles" # PostgreSQL guarda los nombres en minúsculas por defecto
    
    id_rol = Column(Integer, primary_key=True, index=True)
    nombre_rol = Column(String(50), nullable=False)

class Usuario(Base):
    __tablename__ = "usuarios"
    
    id_usuario = Column(Integer, primary_key=True, index=True)
    numero_control = Column(String(20), unique=True, nullable=False)
    nombre_completo = Column(String(150), nullable=False)
    username = Column(String(50), unique=True, nullable=False)
    correo_institucional = Column(String(100), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    id_rol = Column(Integer, ForeignKey("roles.id_rol"), nullable=False)
    estado_cuenta = Column(String(20), default="Activa")
    compartir_ubicacion = Column(Boolean, default=False)
    latitud = Column(Numeric(10, 8))
    longitud = Column(Numeric(11, 8))
    fecha_registro = Column(DateTime, default=datetime.datetime.utcnow)

    # Relaciones para acceder fácilmente con Python
    rol = relationship("Rol")

# 2. LOGÍSTICA Y HORARIOS
class HorarioVendedor(Base):
    __tablename__ = "horarios_vendedor"
    
    id_horario = Column(Integer, primary_key=True, index=True)
    id_vendedor = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    dia_semana = Column(Integer, nullable=False)
    hora_inicio = Column(Time, nullable=False)
    hora_fin = Column(Time, nullable=False)

# 3. CATÁLOGO
class Categoria(Base):
    __tablename__ = "categorias"
    
    id_categoria = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False)

class Producto(Base):
    __tablename__ = "productos"
    
    id_producto = Column(Integer, primary_key=True, index=True)
    id_vendedor = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    id_categoria = Column(Integer, ForeignKey("categorias.id_categoria"), nullable=False)
    nombre_producto = Column(String(150), nullable=False)
    descripcion = Column(Text)
    precio_actual = Column(Numeric(10, 2), nullable=False)
    imagen_url = Column(String(255))
    ventas_concretadas = Column(Integer, default=0)
    pausado_por_agotado = Column(Boolean, default=False)
    bloqueado_por_admin = Column(Boolean, default=False)
    fecha_publicacion = Column(DateTime, default=datetime.datetime.utcnow)

    categoria = relationship("Categoria")
    vendedor = relationship("Usuario")

# 4. TRANSACCIONES
class Pedido(Base):
    __tablename__ = "pedidos"
    
    id_pedido = Column(Integer, primary_key=True, index=True)
    id_cliente = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    id_vendedor = Column(Integer, ForeignKey("usuarios.id_usuario"), nullable=False)
    id_producto = Column(Integer, ForeignKey("productos.id_producto"), nullable=False)
    cantidad = Column(Integer, nullable=False)
    precio_congelado = Column(Numeric(10, 2), nullable=False)
    total_venta = Column(Numeric(10, 2), nullable=False)
    estado_solicitud = Column(String(30), default="Pendiente")
    fecha_hora_pedido = Column(DateTime, default=datetime.datetime.utcnow)