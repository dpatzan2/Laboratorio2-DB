-- ==========================================
-- FUNCIONES DEFINIDAS POR EL USUARIO
-- ==========================================

-- ==========================================
-- 1. Función Escalar: calcular_ingresos_museo
-- Calcula el total de ingresos de un museo en un período específico
-- ==========================================
CREATE OR REPLACE FUNCTION calcular_ingresos_museo(
    p_id_museo INTEGER,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
) RETURNS DECIMAL(10,2) AS $$
DECLARE
    total_ingresos DECIMAL(10,2);
BEGIN
    SELECT COALESCE(SUM(r.precio_total), 0.00)
    INTO total_ingresos
    FROM reserva r
    JOIN visita_guiada v ON r.id_visita = v.id_visita
    WHERE v.id_museo = p_id_museo
    AND v.fecha_hora_inicio::DATE BETWEEN p_fecha_inicio AND p_fecha_fin
    AND r.estado = 'confirmada';

    RETURN total_ingresos;
END;
$$ LANGUAGE plpgsql;


-- ==========================================
-- 2. Función que retorna conjunto de resultados: obtener_visitas_disponibles
-- Retorna todas las visitas disponibles para un día específico con sus detalles
-- ==========================================
CREATE OR REPLACE FUNCTION obtener_visitas_disponibles(
    p_fecha DATE,
    p_idioma VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id_visita INTEGER,
    nombre_museo VARCHAR,
    tipo_visita VARCHAR,
    hora_inicio TIME,
    hora_fin TIME,
    guia_nombre VARCHAR,
    idioma VARCHAR,
    precio DECIMAL(10,2),
    lugares_disponibles INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id_visita,
        m.nombre as nombre_museo,
        tv.nombre as tipo_visita,
        v.fecha_hora_inicio::TIME as hora_inicio,
        v.fecha_hora_fin::TIME as hora_fin,
        g.nombre || ' ' || g.apellido as guia_nombre,
        v.idioma,
        v.precio_final as precio,
        v.capacidad_maxima - COALESCE(SUM(r.cantidad_personas), 0) as lugares_disponibles
    FROM visita_guiada v
    JOIN museo m ON v.id_museo = m.id_museo
    JOIN tipo_visita tv ON v.id_tipo_visita = tv.id_tipo_visita
    JOIN guia g ON v.id_guia = g.id_guia
    LEFT JOIN reserva r ON v.id_visita = r.id_visita AND r.estado = 'confirmada'
    WHERE v.fecha_hora_inicio::DATE = p_fecha
    AND v.estado = 'programada'
    AND (p_idioma IS NULL OR v.idioma = p_idioma)
    GROUP BY v.id_visita, m.nombre, tv.nombre, v.fecha_hora_inicio, v.fecha_hora_fin,
             g.nombre, g.apellido, v.idioma, v.precio_final, v.capacidad_maxima
    HAVING v.capacidad_maxima - COALESCE(SUM(r.cantidad_personas), 0) > 0
    ORDER BY v.fecha_hora_inicio;
END;
$$ LANGUAGE plpgsql;



-- ==========================================
-- 3. Función con múltiples parámetros y lógica condicional: gestionar_reserva
-- Gestiona la creación o modificación de una reserva, verificando disponibilidad
-- ==========================================
CREATE OR REPLACE FUNCTION gestionar_reserva(
    p_id_visita INTEGER,
    p_id_visitante INTEGER,
    p_cantidad_personas INTEGER,
    p_accion VARCHAR -- 'crear' o 'modificar'
) RETURNS JSON AS $$
DECLARE
    v_capacidad_maxima INTEGER;
    v_ocupacion_actual INTEGER;
    v_precio_unitario DECIMAL(10,2);
    v_precio_total DECIMAL(10,2);
    v_estado_visita VARCHAR;
    v_resultado JSON;
BEGIN
    
    SELECT 
        v.capacidad_maxima,
        v.precio_final,
        v.estado,
        COALESCE(SUM(r.cantidad_personas), 0)
    INTO 
        v_capacidad_maxima,
        v_precio_unitario,
        v_estado_visita,
        v_ocupacion_actual
    FROM visita_guiada v
    LEFT JOIN reserva r ON v.id_visita = r.id_visita 
        AND r.estado = 'confirmada'
    WHERE v.id_visita = p_id_visita
    GROUP BY v.capacidad_maxima, v.precio_final, v.estado;

   
    IF NOT FOUND THEN
        RETURN json_build_object(
            'status', 'error',
            'message', 'Visita no encontrada'
        );
    END IF;

    IF v_estado_visita != 'programada' THEN
        RETURN json_build_object(
            'status', 'error',
            'message', 'La visita no está disponible para reservas'
        );
    END IF;

   
    IF (v_ocupacion_actual + p_cantidad_personas) > v_capacidad_maxima THEN
        RETURN json_build_object(
            'status', 'error',
            'message', 'No hay suficientes lugares disponibles',
            'lugares_disponibles', v_capacidad_maxima - v_ocupacion_actual
        );
    END IF;

   
    v_precio_total := v_precio_unitario * p_cantidad_personas;


    CASE p_accion
        WHEN 'crear' THEN
            INSERT INTO reserva (
                id_visita, 
                id_visitante, 
                cantidad_personas, 
                precio_total, 
                estado
            ) VALUES (
                p_id_visita,
                p_id_visitante,
                p_cantidad_personas,
                v_precio_total,
                'pendiente'
            );
            
            v_resultado := json_build_object(
                'status', 'success',
                'message', 'Reserva creada exitosamente',
                'precio_total', v_precio_total
            );

        WHEN 'modificar' THEN
            UPDATE reserva
            SET cantidad_personas = p_cantidad_personas,
                precio_total = v_precio_total
            WHERE id_visita = p_id_visita 
            AND id_visitante = p_id_visitante
            AND estado = 'pendiente';

            IF FOUND THEN
                v_resultado := json_build_object(
                    'status', 'success',
                    'message', 'Reserva modificada exitosamente',
                    'precio_total', v_precio_total
                );
            ELSE
                v_resultado := json_build_object(
                    'status', 'error',
                    'message', 'No se encontró una reserva pendiente para modificar'
                );
            END IF;

        ELSE
            v_resultado := json_build_object(
                'status', 'error',
                'message', 'Acción no válida'
            );
    END CASE;

    RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;



-- ==========================================
-- PROCEDIMIENTOS ALMACENADOS
-- ==========================================


-- ==========================================
-- 1. Procedimiento para Inserción Compleja: crear_visita_guiada_completa
-- Crea una visita guiada completa con sus salas y horarios
-- ==========================================
CREATE OR REPLACE PROCEDURE crear_visita_guiada_completa(
    p_id_museo INTEGER,
    p_id_guia INTEGER,
    p_tipo_visita INTEGER,
    p_fecha DATE,
    p_hora_inicio TIME,
    p_idioma VARCHAR,
    p_capacidad_maxima INTEGER,
    p_salas INTEGER[],
    p_duracion_por_sala INTERVAL[]
) LANGUAGE plpgsql AS $$
DECLARE
    v_id_visita INTEGER;
    v_duracion_total INTERVAL := INTERVAL '0';
    v_precio_base DECIMAL(10,2);
    v_fecha_hora_inicio TIMESTAMP;
    v_fecha_hora_fin TIMESTAMP;
    v_sala INTEGER;
    v_indice INTEGER := 1;
    v_guia_disponible BOOLEAN;
    v_salas_validas BOOLEAN := TRUE;
BEGIN

    SELECT EXISTS (
        SELECT 1 FROM visita_guiada
        WHERE id_guia = p_id_guia
        AND fecha_hora_inicio::DATE = p_fecha
        AND estado != 'cancelada'
    ) INTO v_guia_disponible;

    IF v_guia_disponible THEN
        RAISE EXCEPTION 'El guía ya tiene visitas programadas para esta fecha';
    END IF;


    SELECT NOT EXISTS (
        SELECT unnest(p_salas) AS sala_id
        EXCEPT
        SELECT id_sala FROM sala WHERE id_museo = p_id_museo
    ) INTO v_salas_validas;

    IF NOT v_salas_validas THEN
        RAISE EXCEPTION 'Una o más salas no pertenecen al museo especificado';
    END IF;


    IF array_length(p_salas, 1) != array_length(p_duracion_por_sala, 1) THEN
        RAISE EXCEPTION 'La cantidad de salas y duraciones no coincide';
    END IF;


    SELECT sum(duracion) INTO v_duracion_total
    FROM unnest(p_duracion_por_sala) AS duracion;

    v_fecha_hora_inicio := p_fecha + p_hora_inicio;
    v_fecha_hora_fin := v_fecha_hora_inicio + v_duracion_total;


    SELECT precio_base INTO v_precio_base
    FROM tipo_visita
    WHERE id_tipo_visita = p_tipo_visita;


    BEGIN
      
        INSERT INTO visita_guiada (
            id_tipo_visita,
            id_guia,
            id_museo,
            fecha_hora_inicio,
            fecha_hora_fin,
            capacidad_maxima,
            precio_final,
            idioma,
            estado
        ) VALUES (
            p_tipo_visita,
            p_id_guia,
            p_id_museo,
            v_fecha_hora_inicio,
            v_fecha_hora_fin,
            p_capacidad_maxima,
            v_precio_base,
            p_idioma,
            'programada'
        ) RETURNING id_visita INTO v_id_visita;

    
        FOR i IN 1..array_length(p_salas, 1) LOOP
            INSERT INTO sala_visita (
                id_visita,
                id_sala,
                orden_visita,
                duracion_estimada
            ) VALUES (
                v_id_visita,
                p_salas[i],
                i,
                p_duracion_por_sala[i]
            );
        END LOOP;

        COMMIT;
        RAISE NOTICE 'Visita guiada creada exitosamente con ID: %', v_id_visita;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE EXCEPTION 'Error al crear la visita guiada: %', SQLERRM;
    END;
END;
$$;


-- ==========================================
-- 2. Procedimiento para Actualización con Validaciones: actualizar_estado_reserva
-- Actualiza el estado de una reserva con validaciones
-- ==========================================
CREATE OR REPLACE PROCEDURE actualizar_estado_reserva(
    p_id_reserva INTEGER,
    p_nuevo_estado VARCHAR,
    p_usuario_modificacion VARCHAR
) LANGUAGE plpgsql AS $$
DECLARE
    v_estado_actual VARCHAR;
    v_fecha_visita TIMESTAMP;
    v_capacidad_disponible INTEGER;
    v_cantidad_personas INTEGER;
    v_id_visita INTEGER;
BEGIN
   
    SELECT 
        r.estado,
        r.cantidad_personas,
        r.id_visita,
        v.fecha_hora_inicio,
        v.capacidad_maxima - COALESCE(SUM(r2.cantidad_personas), 0) as capacidad_disponible
    INTO 
        v_estado_actual,
        v_cantidad_personas,
        v_id_visita,
        v_fecha_visita,
        v_capacidad_disponible
    FROM reserva r
    JOIN visita_guiada v ON r.id_visita = v.id_visita
    LEFT JOIN reserva r2 ON v.id_visita = r2.id_visita 
        AND r2.estado = 'confirmada' 
        AND r2.id_reserva != p_id_reserva
    WHERE r.id_reserva = p_id_reserva
    GROUP BY r.estado, r.cantidad_personas, r.id_visita, v.fecha_hora_inicio, v.capacidad_maxima;


    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reserva no encontrada';
    END IF;

    IF v_estado_actual = p_nuevo_estado THEN
        RAISE EXCEPTION 'La reserva ya se encuentra en estado %', p_nuevo_estado;
    END IF;

 
    IF NOT (
        (v_estado_actual = 'pendiente' AND p_nuevo_estado IN ('confirmada', 'cancelada')) OR
        (v_estado_actual = 'confirmada' AND p_nuevo_estado = 'cancelada')
    ) THEN
        RAISE EXCEPTION 'Transición de estado no permitida: % -> %', v_estado_actual, p_nuevo_estado;
    END IF;


    IF v_fecha_visita < CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'No se puede modificar una reserva de una visita ya realizada';
    END IF;

    IF p_nuevo_estado = 'confirmada' AND v_cantidad_personas > v_capacidad_disponible THEN
        RAISE EXCEPTION 'No hay suficiente capacidad disponible. Capacidad: %, Solicitados: %', 
            v_capacidad_disponible, v_cantidad_personas;
    END IF;

 
    BEGIN
      
        UPDATE reserva
        SET 
            estado = p_nuevo_estado,
            fecha_modificacion = CURRENT_TIMESTAMP,
            usuario_modificacion = p_usuario_modificacion
        WHERE id_reserva = p_id_reserva;

        
        INSERT INTO auditoria_reservas (
            id_reserva,
            estado_anterior,
            estado_nuevo,
            fecha_cambio,
            usuario_cambio
        ) VALUES (
            p_id_reserva,
            v_estado_actual,
            p_nuevo_estado,
            CURRENT_TIMESTAMP,
            p_usuario_modificacion
        );

      
        IF v_estado_actual = 'confirmada' AND p_nuevo_estado = 'cancelada' THEN
            
            RAISE NOTICE 'Se ha liberado capacidad para la visita ID: %', v_id_visita;
        END IF;

        COMMIT;
        RAISE NOTICE 'Estado de reserva actualizado exitosamente';
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE EXCEPTION 'Error al actualizar el estado de la reserva: %', SQLERRM;
    END;
END;
$$;

-- ==========================================
-- VISTAS REQUERIDAS
-- ==========================================

-- ==========================================
-- 1. Vista simple: listado de museos con su horario
-- ==========================================
CREATE OR REPLACE VIEW v_museos_simple AS
SELECT 
    id_museo,
    nombre,
    horario_apertura,
    horario_cierre
FROM museo;

-- ==========================================
-- 2. Vista con JOIN y GROUP BY: total de reservas confirmadas por museo
-- ==========================================
CREATE OR REPLACE VIEW v_reservas_por_museo AS
SELECT
    m.id_museo,
    m.nombre AS museo,
    COUNT(r.id_reserva) AS total_reservas
FROM reserva r
JOIN visita_guiada v ON r.id_visita = v.id_visita
JOIN museo m ON v.id_museo = m.id_museo
WHERE r.estado = 'confirmada'
GROUP BY m.id_museo, m.nombre;

-- ==========================================
-- 3. Vista con expresiones (CASE, COALESCE): estado legible de la visita
-- ==========================================

CREATE OR REPLACE VIEW v_visitas_estado_legible AS
SELECT
    id_visita,
    estado,
    CASE
      WHEN estado = 'programada' THEN 'Pendiente de inicio'
      WHEN estado = 'en_curso'   THEN 'Actualmente en curso'
      WHEN estado = 'finalizada' THEN 'Concluida'
      WHEN estado = 'cancelada'  THEN 'Cancelada'
      ELSE 'Desconocido'
    END AS descripcion_estado,
    COALESCE(idioma, 'sin especificar') AS idioma_visita
FROM visita_guiada;

-- 4. Vista compuesta con JOIN, GROUP BY y COALESCE: plazas disponibles por visita
CREATE OR REPLACE VIEW v_plazas_disponibles AS
SELECT
    v.id_visita,
    m.nombre        AS museo,
    tv.nombre       AS tipo_visita,
    v.fecha_hora_inicio::DATE AS fecha,
    v.fecha_hora_inicio::TIME AS hora_inicio,
    v.capacidad_maxima,
    COALESCE(v.capacidad_maxima - SUM(r.cantidad_personas), v.capacidad_maxima) AS plazas_libres
FROM visita_guiada v
JOIN museo m         ON v.id_museo = m.id_museo
JOIN tipo_visita tv  ON v.id_tipo_visita = tv.id_tipo_visita
LEFT JOIN reserva r  ON v.id_visita = r.id_visita AND r.estado = 'confirmada'
GROUP BY 
    v.id_visita, m.nombre, tv.nombre,
    v.fecha_hora_inicio, v.capacidad_maxima;


-- ==========================================
-- TRIGGERS REQUERIDOS
-- ==========================================


-- ==========================================
-- Trigger BEFORE: valida capacidad antes de insertar o actualizar una reserva
-- ==========================================
CREATE OR REPLACE FUNCTION fn_check_capacity() RETURNS trigger AS $$
DECLARE
    ocupacion_actual INTEGER;
    cap_max           INTEGER;
BEGIN
    -- Suma de todas las personas confirmadas en la visita
    SELECT COALESCE(SUM(cantidad_personas), 0)
      INTO ocupacion_actual
      FROM reserva
     WHERE id_visita = NEW.id_visita
       AND estado = 'confirmada';

    -- Capacidad máxima de la visita
    SELECT capacidad_maxima
      INTO cap_max
      FROM visita_guiada
     WHERE id_visita = NEW.id_visita;

    IF ocupacion_actual + NEW.cantidad_personas > cap_max THEN
        RAISE EXCEPTION 'Capacidad excedida: disponibles % y se intentan reservar %',
            cap_max - ocupacion_actual, NEW.cantidad_personas;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_before_reserva
BEFORE INSERT OR UPDATE ON reserva
FOR EACH ROW
EXECUTE FUNCTION fn_check_capacity();

-- ==========================================
-- Trigger AFTER: registra en la auditoría cada nueva reserva
-- ==========================================
CREATE OR REPLACE FUNCTION fn_audit_reserva_insert() RETURNS trigger AS $$
BEGIN
    INSERT INTO auditoria_reservas (
        id_reserva,
        estado_anterior,
        estado_nuevo,
        usuario_cambio
    ) VALUES (
        NEW.id_reserva,
        NULL,
        NEW.estado,
        'trigger_after_insert'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_after_reserva
AFTER INSERT ON reserva
FOR EACH ROW
EXECUTE FUNCTION fn_audit_reserva_insert();

