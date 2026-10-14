-- =============================================================================
-- Plantilla: Stored Procedures CRUD con Formato JSONB Unificado
-- Compatible con Express (backend_manager) y Zustand (frontend_manager)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS app;

-- =============================================================================
-- 1. Listar Paginado (getAll) -> Retorna { data: [...], total: N }
-- =============================================================================
CREATE OR REPLACE FUNCTION app.entity_get_all(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'data', COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb),
    'total', (SELECT COUNT(*) FROM app.entities WHERE deleted_at IS NULL)
  )
  INTO v_result
  FROM (
    SELECT id, code, name, status, metadata, created_at, updated_at
    FROM app.entities
    WHERE deleted_at IS NULL
    ORDER BY created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN COALESCE(v_result, '{"data":[], "total": 0}'::jsonb);
END;
$$;

-- =============================================================================
-- 2. Obtener por ID (getById) -> Retorna objeto JSON o NULL
-- =============================================================================
CREATE OR REPLACE FUNCTION app.entity_get_by_id(p_id UUID)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT to_jsonb(t) INTO v_result
  FROM (
    SELECT id, code, name, status, metadata, created_at, updated_at
    FROM app.entities
    WHERE id = p_id AND deleted_at IS NULL
  ) t;

  RETURN v_result;
END;
$$;

-- =============================================================================
-- 3. Crear (create) -> Retorna el objeto creado
-- =============================================================================
CREATE OR REPLACE FUNCTION app.entity_create(
  p_code VARCHAR,
  p_name VARCHAR,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_result jsonb;
BEGIN
  INSERT INTO app.entities (code, name, metadata)
  VALUES (UPPER(TRIM(p_code)), TRIM(p_name), COALESCE(p_metadata, '{}'::jsonb))
  RETURNING to_jsonb(entities.*) INTO v_result;

  RETURN v_result;
END;
$$;

-- =============================================================================
-- 4. Actualizar (update) -> Retorna el objeto modificado
-- =============================================================================
CREATE OR REPLACE FUNCTION app.entity_update(
  p_id UUID,
  p_name VARCHAR,
  p_status VARCHAR DEFAULT NULL,
  p_metadata JSONB DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_result jsonb;
BEGIN
  UPDATE app.entities
  SET
    name = TRIM(p_name),
    status = COALESCE(p_status, status),
    metadata = COALESCE(p_metadata, metadata),
    updated_at = NOW()
  WHERE id = p_id AND deleted_at IS NULL
  RETURNING to_jsonb(entities.*) INTO v_result;

  RETURN v_result;
END;
$$;

-- =============================================================================
-- 5. Eliminación Lógica (delete) -> Retorna { "deleted": true }
-- =============================================================================
CREATE OR REPLACE FUNCTION app.entity_delete(p_id UUID)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE app.entities
  SET deleted_at = NOW(), updated_at = NOW()
  WHERE id = p_id AND deleted_at IS NULL;

  RETURN jsonb_build_object('deleted', true);
END;
$$;
