
DROP TABLE IF EXISTS museo CASCADE;
DROP TABLE IF EXISTS guia CASCADE;
DROP TABLE IF EXISTS guia_museo CASCADE;
DROP TABLE IF EXISTS reserva CASCADE;
DROP TABLE IF EXISTS sala CASCADE;
DROP TABLE IF EXISTS sala_visita CASCADE;
DROP TABLE IF EXISTS tipo_visita CASCADE;
DROP TABLE IF EXISTS visita_guiada CASCADE;
DROP TABLE IF EXISTS visitante CASCADE;

-- Tabla Museo
CREATE TABLE museo (
    id_museo SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    direccion TEXT NOT NULL,
    telefono VARCHAR(20),
    horario_apertura TIME NOT NULL,
    horario_cierre TIME NOT NULL,
    fecha_fundacion DATE,
    CONSTRAINT chk_horario CHECK (horario_apertura < horario_cierre)
);

-- Tabla Sala
CREATE TABLE sala (
    id_sala SERIAL PRIMARY KEY,
    id_museo INTEGER NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    capacidad_maxima INTEGER NOT NULL,
    piso INTEGER NOT NULL,
    descripcion TEXT,
    estado BOOLEAN DEFAULT true,
    CONSTRAINT fk_museo FOREIGN KEY (id_museo) REFERENCES museo(id_museo),
    CONSTRAINT chk_capacidad CHECK (capacidad_maxima > 0),
    CONSTRAINT chk_piso CHECK (piso >= 0)
);

-- Tabla Guia
CREATE TABLE guia (
    id_guia SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    dni VARCHAR(20) NOT NULL UNIQUE,
    fecha_nacimiento DATE NOT NULL,
    telefono VARCHAR(20),
    email VARCHAR(100) UNIQUE,
    fecha_contratacion DATE NOT NULL,
    idiomas TEXT[] NOT NULL,
    estado BOOLEAN DEFAULT true,
    CONSTRAINT chk_edad CHECK (fecha_nacimiento <= CURRENT_DATE - INTERVAL '18 years')
);

-- Tabla Guia_Museo 
CREATE TABLE guia_museo (
    id_guia INTEGER NOT NULL,
    id_museo INTEGER NOT NULL,
    fecha_asignacion DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (id_guia, id_museo),
    FOREIGN KEY (id_guia) REFERENCES guia(id_guia),
    FOREIGN KEY (id_museo) REFERENCES museo(id_museo)
);

-- Tabla Tipo_Visita
CREATE TABLE tipo_visita (
    id_tipo_visita SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    descripcion TEXT,
    duracion_estimada INTERVAL NOT NULL,
    precio_base DECIMAL(10,2) NOT NULL,
    CONSTRAINT chk_precio CHECK (precio_base >= 0),
    CONSTRAINT chk_duracion CHECK (duracion_estimada > INTERVAL '0 minutes')
);

-- Tabla Visita_Guiada
CREATE TABLE visita_guiada (
    id_visita SERIAL PRIMARY KEY,
    id_tipo_visita INTEGER NOT NULL,
    id_guia INTEGER NOT NULL,
    id_museo INTEGER NOT NULL,
    fecha_hora_inicio TIMESTAMP NOT NULL,
    fecha_hora_fin TIMESTAMP NOT NULL,
    capacidad_maxima INTEGER NOT NULL,
    precio_final DECIMAL(10,2) NOT NULL,
    idioma VARCHAR(50) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'programada',
    FOREIGN KEY (id_tipo_visita) REFERENCES tipo_visita(id_tipo_visita),
    FOREIGN KEY (id_guia) REFERENCES guia(id_guia),
    FOREIGN KEY (id_museo) REFERENCES museo(id_museo),
    CONSTRAINT chk_fechas CHECK (fecha_hora_inicio < fecha_hora_fin),
    CONSTRAINT chk_capacidad_visita CHECK (capacidad_maxima > 0),
    CONSTRAINT chk_precio_final CHECK (precio_final >= 0),
    CONSTRAINT chk_estado CHECK (estado IN ('programada', 'en_curso', 'finalizada', 'cancelada'))
);

-- Tabla Visitante
CREATE TABLE visitante (
    id_visitante SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    telefono VARCHAR(20),
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tabla Reserva
CREATE TABLE reserva (
    id_reserva SERIAL PRIMARY KEY,
    id_visita INTEGER NOT NULL,
    id_visitante INTEGER NOT NULL,
    fecha_reserva TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cantidad_personas INTEGER NOT NULL,
    precio_total DECIMAL(10,2) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    FOREIGN KEY (id_visita) REFERENCES visita_guiada(id_visita),
    FOREIGN KEY (id_visitante) REFERENCES visitante(id_visitante),
    CONSTRAINT chk_cantidad_personas CHECK (cantidad_personas > 0),
    CONSTRAINT chk_precio_total CHECK (precio_total >= 0),
    CONSTRAINT chk_estado_reserva CHECK (estado IN ('pendiente', 'confirmada', 'cancelada'))
);

-- Tabla Sala_Visita
CREATE TABLE sala_visita (
    id_visita INTEGER NOT NULL,
    id_sala INTEGER NOT NULL,
    orden_visita INTEGER NOT NULL,
    duracion_estimada INTERVAL NOT NULL,
    PRIMARY KEY (id_visita, id_sala),
    FOREIGN KEY (id_visita) REFERENCES visita_guiada(id_visita),
    FOREIGN KEY (id_sala) REFERENCES sala(id_sala),
    CONSTRAINT chk_orden CHECK (orden_visita > 0),
    CONSTRAINT chk_duracion_sala CHECK (duracion_estimada > INTERVAL '0 minutes')
);