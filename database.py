from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Configuración de tu conexión a PostgreSQL
# Formato: "postgresql://usuario:contraseña@servidor:puerto/nombre_bd"
# Si usas tu PC local, suele ser usuario "postgres" y puerto "5432"
SQLALCHEMY_DATABASE_URL = "postgresql://postgres:root@localhost:5432/market_tec_db"

# El "motor" que abre la comunicación con PostgreSQL
engine = create_engine(SQLALCHEMY_DATABASE_URL)

# La fábrica de sesiones para ejecutar consultas (SELECT, INSERT, UPDATE)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# La clase base de la que van a heredar nuestras 11 tablas
Base = declarative_base()

# Función de dependencia para que FastAPI abra y cierre la conexión en cada petición
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()