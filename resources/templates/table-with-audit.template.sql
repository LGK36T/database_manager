-- =============================================================================
-- Plantilla: Tabla de Negocio con Auditoría Inmutable (Change Data Capture)
-- Registra automáticamente INSERT, UPDATE y DELETE en el esquema audit
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS audit;

-- 1. Tabla de Registro de Auditoría
CREATE TABLE IF NOT EXISTS audit.logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schema_name VARCHAR(63) NOT NULL,
  table_name VARCHAR(63) NOT NULL,
  record_id UUID NOT NULL,
  action VARCHAR(10) NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
  old_data JSONB DEFAULT NULL,
  new_data JSONB DEFAULT NULL,
  changed_by VARCHAR(100) DEFAULT CURRENT_USER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_record
ON audit.logs (schema_name, table_name, record_id, created_at DESC);

-- 2. Función Trigger Universal de Auditoría
CREATE OR REPLACE FUNCTION audit.process_audit_log()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    INSERT INTO audit.logs (schema_name, table_name, record_id, action, new_data)
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW));
    RETURN NEW;
  ELSIF (TG_OP = 'UPDATE') THEN
    INSERT INTO audit.logs (schema_name, table_name, record_id, action, old_data, new_data)
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, OLD.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    INSERT INTO audit.logs (schema_name, table_name, record_id, action, old_data)
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD));
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

-- 3. Tabla de Negocio de Ejemplo
CREATE TABLE IF NOT EXISTS app.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sku VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  stock INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ DEFAULT NULL,

  CONSTRAINT chk_products_price CHECK (price >= 0),
  CONSTRAINT chk_products_stock CHECK (stock >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_products_sku_active
ON app.products (sku)
WHERE deleted_at IS NULL;

-- 4. Asociar el Trigger a la Tabla
DROP TRIGGER IF EXISTS trg_audit_products ON app.products;
CREATE TRIGGER trg_audit_products
AFTER INSERT OR UPDATE OR DELETE ON app.products
FOR EACH ROW EXECUTE FUNCTION audit.process_audit_log();
