-- ==========================================
-- 1. MÓDULO DE SEGURIDAD Y USUARIOS
-- ==========================================

CREATE TABLE Roles (
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50) NOT NULL
);

-- Insertar los roles base inmediatamente
INSERT INTO Roles (nombre_rol) VALUES ('Cliente'), ('Vendedor'), ('Administrador');

CREATE TABLE Usuarios (
    id_usuario SERIAL PRIMARY KEY,
    numero_control VARCHAR(20) UNIQUE NOT NULL, -- Validación ITZ
    nombre_completo VARCHAR(150) NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    correo_institucional VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    id_rol INT NOT NULL REFERENCES Roles(id_rol),
    estado_cuenta VARCHAR(20) DEFAULT 'Activa', -- Activa, Suspendida, Eliminada
    compartir_ubicacion BOOLEAN DEFAULT FALSE,
    latitud DECIMAL(10, 8),
    longitud DECIMAL(11, 8),
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- 2. MÓDULO DE LOGÍSTICA DEL VENDEDOR
-- ==========================================

CREATE TABLE Configuracion_Logistica (
    id_logistica SERIAL PRIMARY KEY,
    id_vendedor INT NOT NULL REFERENCES Usuarios(id_usuario) ON DELETE CASCADE,
    tipo_entrega VARCHAR(50) NOT NULL, -- 'Punto Fijo', 'Dinámica', 'Ambas'
    descripcion_punto_fijo TEXT
);

CREATE TABLE Horarios_Vendedor (
    id_horario SERIAL PRIMARY KEY,
    id_vendedor INT NOT NULL REFERENCES Usuarios(id_usuario) ON DELETE CASCADE,
    dia_semana INT NOT NULL, -- 1=Lunes, 2=Martes, etc.
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL
);

-- ==========================================
-- 3. MÓDULO DE CATÁLOGO
-- ==========================================

CREATE TABLE Categorias (
    id_categoria SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL
);

-- Insertar categorías base
INSERT INTO Categorias (nombre) VALUES ('Dulces'), ('Electrónica'), ('Servicios'), ('Materiales'), ('Ropa y Accesorios');

CREATE TABLE Productos (
    id_producto SERIAL PRIMARY KEY,
    id_vendedor INT NOT NULL REFERENCES Usuarios(id_usuario) ON DELETE CASCADE,
    id_categoria INT NOT NULL REFERENCES Categorias(id_categoria),
    nombre_producto VARCHAR(150) NOT NULL,
    descripcion TEXT,
    precio_actual DECIMAL(10, 2) NOT NULL,
    imagen_url VARCHAR(255),
    ventas_concretadas INT DEFAULT 0,
    pausado_por_agotado BOOLEAN DEFAULT FALSE,
    bloqueado_por_admin BOOLEAN DEFAULT FALSE,
    fecha_publicacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- 4. MÓDULO DE TRANSACCIONES (PEDIDOS)
-- ==========================================

CREATE TABLE Pedidos (
    id_pedido SERIAL PRIMARY KEY,
    id_cliente INT NOT NULL REFERENCES Usuarios(id_usuario),
    id_vendedor INT NOT NULL REFERENCES Usuarios(id_usuario),
    id_producto INT NOT NULL REFERENCES Productos(id_producto),
    cantidad INT NOT NULL,
    precio_congelado DECIMAL(10, 2) NOT NULL,
    total_venta DECIMAL(10, 2) NOT NULL,
    estado_solicitud VARCHAR(30) DEFAULT 'Pendiente', -- Pendiente, Confirmado, Rechazado_Agotado, Cancelado
    fecha_hora_pedido TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- 5. MÓDULO DE REPUTACIÓN Y MODERACIÓN
-- ==========================================

CREATE TABLE Favoritos (
    id_favorito SERIAL PRIMARY KEY,
    id_cliente INT NOT NULL REFERENCES Usuarios(id_usuario) ON DELETE CASCADE,
    id_producto INT NOT NULL REFERENCES Productos(id_producto) ON DELETE CASCADE,
    UNIQUE(id_cliente, id_producto) -- Evita que un cliente de like dos veces al mismo producto
);

CREATE TABLE Resenas (
    id_resena SERIAL PRIMARY KEY,
    id_cliente INT NOT NULL REFERENCES Usuarios(id_usuario),
    id_producto INT NOT NULL REFERENCES Productos(id_producto) ON DELETE CASCADE,
    calificacion_estrellas INT CHECK (calificacion_estrellas >= 1 AND calificacion_estrellas <= 5),
    comentario TEXT,
    fecha_resena TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Reportes (
    id_reporte SERIAL PRIMARY KEY,
    id_denunciante INT NOT NULL REFERENCES Usuarios(id_usuario),
    id_usuario_reportado INT REFERENCES Usuarios(id_usuario) ON DELETE SET NULL,
    id_producto_reportado INT REFERENCES Productos(id_producto) ON DELETE SET NULL,
    motivo_principal VARCHAR(100) NOT NULL,
    descripcion_detallada TEXT NOT NULL,
    estado_revision VARCHAR(30) DEFAULT 'Pendiente', -- Pendiente, Resuelto, Descartado
    fecha_reporte TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- ==========================================
-- 6. MÓDULO DE AUDITORÍA Y CONTROL (BITÁCORA)
-- ==========================================

CREATE TABLE Bitacora (
    id_bitacora SERIAL PRIMARY KEY,
    id_usuario INT REFERENCES Usuarios(id_usuario) ON DELETE SET NULL, -- Se pone SET NULL para no perder el historial si el usuario es eliminado
    accion VARCHAR(50) NOT NULL, -- Ej: 'INSERT', 'UPDATE', 'DELETE', 'SUSPENSION', 'LOGIN'
    tabla_afectada VARCHAR(50) NOT NULL, -- Ej: 'Usuarios', 'Productos', 'Pedidos'
    descripcion_detalle TEXT NOT NULL, -- Ej: 'El Administrador suspendió la cuenta del Vendedor ID 15'
    direccion_ip VARCHAR(45), -- Opcional pero recomendado para rastrear desde dónde se hizo la acción
    fecha_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- 7. TRIGGERS Y FUNCIONES AUTOMATIZADAS
-- ==========================================

-- --------------------------------------------------------
-- A. AUTOMATIZACIÓN DE PEDIDOS (Ventas y Auto-Pausa)
-- --------------------------------------------------------
CREATE OR REPLACE FUNCTION procesar_estado_pedido()
RETURNS TRIGGER AS $$
BEGIN
    -- Regla 1: Si el vendedor confirma la venta, aumentar el contador de ventas del producto
    IF NEW.estado_solicitud = 'Confirmado' AND OLD.estado_solicitud = 'Pendiente' THEN
        UPDATE Productos 
        SET ventas_concretadas = ventas_concretadas + NEW.cantidad 
        WHERE id_producto = NEW.id_producto;
    END IF;

    -- Regla 2: Si el vendedor rechaza por falta de stock, pausar el producto automáticamente
    IF NEW.estado_solicitud = 'Rechazado_Agotado' AND OLD.estado_solicitud = 'Pendiente' THEN
        UPDATE Productos 
        SET pausado_por_agotado = TRUE 
        WHERE id_producto = NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_estado_pedido
AFTER UPDATE ON Pedidos
FOR EACH ROW
WHEN (OLD.estado_solicitud IS DISTINCT FROM NEW.estado_solicitud)
EXECUTE FUNCTION procesar_estado_pedido();


-- --------------------------------------------------------
-- B. AUDITORÍA AUTOMÁTICA EN BITÁCORA (Estados de cuenta)
-- --------------------------------------------------------
CREATE OR REPLACE FUNCTION auditar_estado_usuario()
RETURNS TRIGGER AS $$
BEGIN
    -- Regla 3: Si cambia el estado de una cuenta (Ej. de Activa a Suspendida), registrarlo en Bitácora
    IF NEW.estado_cuenta <> OLD.estado_cuenta THEN
        INSERT INTO Bitacora (id_usuario, accion, tabla_afectada, descripcion_detalle)
        VALUES (
            NEW.id_usuario,
            'UPDATE_ESTADO', 
            'Usuarios', 
            'El estado de la cuenta cambió de ' || OLD.estado_cuenta || ' a ' || NEW.estado_cuenta
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_auditar_usuario
AFTER UPDATE ON Usuarios
FOR EACH ROW
WHEN (OLD.estado_cuenta IS DISTINCT FROM NEW.estado_cuenta)
EXECUTE FUNCTION auditar_estado_usuario();