from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, time

# --- 1. USUARIOS ---
class UsuarioCreate(BaseModel):
    numero_control: str
    nombre_completo: str
    username: str
    correo_institucional: str
    password: str
    id_rol: int

class UsuarioResponse(BaseModel):
    id_usuario: int
    numero_control: str
    nombre_completo: str
    username: str
    correo_institucional: str
    id_rol: int
    estado_cuenta: str

    class Config:
        from_attributes = True

class UsuarioLogin(BaseModel):
    correo_institucional: str
    password: str

# --- 2. MINI-ESQUEMAS PARA RELACIONES ---
class CategoriaBase(BaseModel):
    id_categoria: int
    nombre: str
    class Config:
        from_attributes = True

class VendedorBase(BaseModel):
    nombre_completo: str 
    class Config:
        from_attributes = True

# --- 3. PRODUCTOS ---
class ProductoCreate(BaseModel):
    id_categoria: int
    nombre_producto: str
    descripcion: Optional[str] = None
    precio_actual: float
    imagen_url: Optional[str] = None

class ProductoResponse(BaseModel):
    id_producto: int
    nombre_producto: str
    descripcion: Optional[str]
    precio_actual: float
    imagen_url: Optional[str]
    ventas_concretadas: int
    pausado_por_agotado: bool
    bloqueado_por_admin: bool
    
    categoria: CategoriaBase
    vendedor: VendedorBase

    class Config:
        from_attributes = True

# --- 4. PEDIDOS (COMPRAS) ---
class PedidoCreate(BaseModel):
    id_vendedor: int
    id_producto: int
    cantidad: int
    precio_congelado: float
    total_venta: float

class PedidoEstadoUpdate(BaseModel):
    estado_solicitud: str # "Aceptado", "Entregado", "Cancelado"

class PedidoResponse(BaseModel):
    id_pedido: int
    id_cliente: int
    id_vendedor: int
    id_producto: int
    cantidad: int
    precio_congelado: float
    total_venta: float
    estado_solicitud: str
    fecha_hora_pedido: datetime

    class Config:
        from_attributes = True

# --- 5. HORARIOS DE ENTREGA ---
class HorarioCreate(BaseModel):
    dia_semana: int # 1=Lunes, 5=Viernes
    hora_inicio: time
    hora_fin: time

class HorarioResponse(BaseModel):
    id_horario: int
    id_vendedor: int
    dia_semana: int
    hora_inicio: time
    hora_fin: time

    class Config:
        from_attributes = True

# --- 6. SEGURIDAD (TOKEN) ---
class Token(BaseModel):
    access_token: str
    token_type: str