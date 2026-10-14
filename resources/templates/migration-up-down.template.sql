-- =============================================================================
-- Plantilla de Migración Reversible (Up / Down)
-- Nombre sugerido: YYYYMMDD_NNN_nombre_descriptivo.sql
-- =============================================================================

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UP >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
BEGIN;

-- 1. Crear esquema si no existe
CREATE SCHEMA IF NOT EXISTS app;

-- 2. Crear tabla principal con clave UUID y soft delete
CREATE TABLE IF NOT EXISTS app.entities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ DEFAULT NULL,

  CONSTRAINT chk_entities_status CHECK (status IN ('active', 'inactive', 'pending'))
);

-- 3. Índice único condicional al soft delete (permite reusar código si se eliminó)
CREATE UNIQUE INDEX IF NOT EXISTS uq_entities_code_active
ON app.entities (code)
WHERE deleted_at IS NULL;

-- 4. Índice para búsquedas y listados ordenados por fecha
CREATE INDEX IF NOT EXISTS idx_entities_created_active
ON app.entities (created_at DESC)
WHERE deleted_at IS NULL;

-- 5. Trigger para actualizar automáticamente updated_at
CREATE OR REPLACE FUNCTION app.trigger_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_entities_updated_at ON app.entities;
CREATE TRIGGER trg_entities_updated_at
BEFORE UPDATE ON app.entities
FOR EACH ROW
EXECUTE FUNCTION app.trigger_set_updated_at();

COMMIT;

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< DOWN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
-- Para revertir esta migración, ejecutar:
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_entities_updated_at ON app.entities;
-- DROP INDEX IF EXISTS app.idx_entities_created_active;
-- DROP INDEX IF EXISTS app.uq_entities_code_active;
-- DROP TABLE IF EXISTS app.entities;
-- COMMIT;
