-- =============================================================================
-- Plantilla: Cola de Tareas Asíncronas en PostgreSQL (Patrón SKIP LOCKED)
-- Permite coordinar API (Express) y Workers (Python) con transaccionalidad ACID
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS app;

-- 1. Tabla de Tareas Asíncronas
CREATE TABLE IF NOT EXISTS app.async_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_type VARCHAR(100) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  progress SMALLINT NOT NULL DEFAULT 0,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  result JSONB DEFAULT NULL,
  error_message TEXT DEFAULT NULL,
  error_details JSONB DEFAULT NULL,
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 3,
  worker_id VARCHAR(100) DEFAULT NULL,
  created_by UUID DEFAULT NULL,
  scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ DEFAULT NULL,
  completed_at TIMESTAMPTZ DEFAULT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_async_tasks_status CHECK (
    status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')
  ),
  CONSTRAINT chk_async_tasks_progress CHECK (
    progress BETWEEN 0 AND 100
  )
);

-- Índices de alto rendimiento para encolado y monitoreo
CREATE INDEX IF NOT EXISTS idx_async_tasks_claim
ON app.async_tasks (scheduled_at ASC, created_at ASC)
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_async_tasks_status_created
ON app.async_tasks (status, created_at DESC);

-- =============================================================================
-- 2. SP: Crear Tarea (Llamado desde API Gateway Express al recibir petición)
-- =============================================================================
CREATE OR REPLACE FUNCTION app.async_task_create(
  p_task_type VARCHAR,
  p_payload JSONB DEFAULT '{}'::jsonb,
  p_created_by UUID DEFAULT NULL,
  p_max_attempts INT DEFAULT 3
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_result jsonb;
BEGIN
  INSERT INTO app.async_tasks (
    task_type,
    payload,
    created_by,
    max_attempts,
    status
  )
  VALUES (
    p_task_type,
    COALESCE(p_payload, '{}'::jsonb),
    p_created_by,
    p_max_attempts,
    'pending'
  )
  RETURNING jsonb_build_object(
    'taskId', id,
    'taskType', task_type,
    'status', status,
    'createdAt', created_at
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- =============================================================================
-- 3. SP: Reclamar Tarea (Llamado por Worker en Python usando SKIP LOCKED)
-- =============================================================================
CREATE OR REPLACE FUNCTION app.async_task_claim(p_worker_id VARCHAR)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_task record;
BEGIN
  -- Bloqueo atómico no contencioso
  SELECT id INTO v_task
  FROM app.async_tasks
  WHERE status = 'pending'
    AND scheduled_at <= NOW()
  ORDER BY scheduled_at ASC, created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE app.async_tasks
  SET
    status = 'processing',
    worker_id = p_worker_id,
    started_at = NOW(),
    updated_at = NOW(),
    attempts = attempts + 1
  WHERE id = v_task.id
  RETURNING * INTO v_task;

  RETURN to_jsonb(v_task);
END;
$$;

-- =============================================================================
-- 4. SP: Actualizar Progreso (0 - 100%)
-- =============================================================================
CREATE OR REPLACE FUNCTION app.async_task_update_progress(
  p_task_id UUID,
  p_progress SMALLINT
)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE app.async_tasks
  SET
    progress = LEAST(100, GREATEST(0, p_progress)),
    updated_at = NOW()
  WHERE id = p_task_id AND status = 'processing';

  RETURN jsonb_build_object('success', true);
END;
$$;

-- =============================================================================
-- 5. SP: Completar Tarea con Resultado
-- =============================================================================
CREATE OR REPLACE FUNCTION app.async_task_complete(
  p_task_id UUID,
  p_result JSONB
)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE app.async_tasks
  SET
    status = 'completed',
    progress = 100,
    result = p_result,
    completed_at = NOW(),
    updated_at = NOW()
  WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'status', 'completed');
END;
$$;

-- =============================================================================
-- 6. SP: Fallar Tarea (Reintentar o marcar Failed si agota intentos)
-- =============================================================================
CREATE OR REPLACE FUNCTION app.async_task_fail(
  p_task_id UUID,
  p_error_message TEXT,
  p_error_details JSONB DEFAULT NULL,
  p_retry_delay_seconds INT DEFAULT 30
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_task app.async_tasks%ROWTYPE;
BEGIN
  SELECT * INTO v_task FROM app.async_tasks WHERE id = p_task_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Task not found');
  END IF;

  IF v_task.attempts < v_task.max_attempts THEN
    -- Reprogramar con retraso exponencial
    UPDATE app.async_tasks
    SET
      status = 'pending',
      error_message = p_error_message,
      error_details = p_error_details,
      scheduled_at = NOW() + (p_retry_delay_seconds || ' seconds')::INTERVAL,
      updated_at = NOW()
    WHERE id = p_task_id;

    RETURN jsonb_build_object('status', 'retry_scheduled', 'attempts', v_task.attempts);
  ELSE
    -- Agotó intentos: marcar como fallo definitivo (Dead-Letter)
    UPDATE app.async_tasks
    SET
      status = 'failed',
      error_message = p_error_message,
      error_details = p_error_details,
      completed_at = NOW(),
      updated_at = NOW()
    WHERE id = p_task_id;

    RETURN jsonb_build_object('status', 'failed', 'attempts', v_task.attempts);
  END IF;
END;
$$;

-- =============================================================================
-- 7. SP: Consultar Estado (Para Polling desde Express / Frontend)
-- =============================================================================
CREATE OR REPLACE FUNCTION app.async_task_get_status(p_task_id UUID)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'taskId', id,
    'taskType', task_type,
    'status', status,
    'progress', progress,
    'result', result,
    'errorMessage', error_message,
    'attempts', attempts,
    'startedAt', started_at,
    'completedAt', completed_at,
    'createdAt', created_at
  ) INTO v_result
  FROM app.async_tasks
  WHERE id = p_task_id;

  RETURN v_result;
END;
$$;
