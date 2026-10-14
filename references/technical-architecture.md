# Referencia Técnica — Arquitectura y Gestión de Bases de Datos Relacionales

> **Versión:** 2.0  
> **Motor Principal:** PostgreSQL 17  
> **Drivers & Clientes:** Node.js 22+ (`pg`), Python 3.12+ (`psycopg` v3 con `psycopg_pool` / `asyncpg`)  
> **Propósito:** Especificación técnica para desarrolladores al diseñar esquemas, escribir migraciones reproducibles, implementar procedimientos almacenados de alto rendimiento y coordinar la persistencia con el backend (`backend_manager`), frontend (`frontend_manager`) y workers asíncronos (`workers_manager`).

---

## Tabla de Contenidos

1. [Visión General y Filosofía de Persistencia](#1-visión-general-y-filosofía-de-persistencia)
2. [Arquitectura y Separación de Esquemas (`app`, `tasks`, `audit`)](#2-arquitectura-y-separación-de-esquemas-app-tasks-audit)
3. [Convenciones de Nomenclatura e Integridad Referencial](#3-convenciones-de-nomenclatura-e-integridad-referencial)
4. [Estrategia de Identificadores (UUID v4 Nativo)](#4-estrategia-de-identificadores-uuid-v4-nativo)
5. [Eliminación Lógica (*Soft Delete*) e Índices Parciales](#5-eliminación-lógica-soft-delete-e-índices-parciales)
6. [Concurrencia y Control de Bloqueos (`FOR UPDATE SKIP LOCKED`)](#6-concurrencia-y-control-de-bloqueos-for-update-skip-locked)
7. [Manejo de Tareas Asíncronas en Base de Datos (`app.async_tasks`)](#7-manejo-de-tareas-asíncronas-en-base-de-datos-appasync_tasks)
8. [Stored Procedures y Funciones PL/pgSQL (Estándar JSONB Unificado)](#8-stored-procedures-y-funciones-plpgsql-estándar-jsonb-unificado)
9. [Migraciones Reversibles (`up` / `down`) y DDL Seguro](#9-migraciones-reversibles-up--down-y-ddl-seguro)
10. [Estrategia de Indexación y Optimización de Consultas](#10-estrategia-de-indexación-y-optimización-de-consultas)
11. [Auditoría Automática y Trazabilidad Transaccional](#11-auditoría-automática-y-trazabilidad-transaccional)
12. [Gestión de Pools de Conexión (Node.js y Python)](#12-gestión-de-pools-de-conexión-nodejs-y-python)
13. [Seguridad, Roles y Principio de Menor Privilegio](#13-seguridad-roles-y-principio-de-menor-privilegio)
14. [Flujo Integrado E2E: Front -> API -> Worker -> BD -> API -> Front](#14-flujo-integrado-e2e-front---api---worker---bd---api---front)
15. [Checklist Pre-Deploy y Auditoría de Base de Datos](#15-checklist-pre-deploy-y-auditoría-de-base-de-datos)

---

## 1. Visión General y Filosofía de Persistencia

La persistencia se centraliza en PostgreSQL 17 como fuente de verdad del sistema. Para asegurar consistencia y desacoplar el acceso a datos entre servicios (Express en backend, Python en workers y React en frontend), se aplican los siguientes principios:

1. **Encapsulamiento en Stored Procedures:** La capa de aplicación no compone consultas SQL dinámicas ni escribe sentencias `SELECT *` arbitrarias. Toda interacción de lectura y mutación se efectúa a través de funciones y Stored Procedures en PL/pgSQL del esquema `app`.
2. **Serialización JSONB Nativa:** Las funciones PL/pgSQL devuelven el resultado formateado en `jsonb`, delegando la serialización al motor C de PostgreSQL (10x más rápido que formatear en Node/Python). Para colecciones, el formato devuelto es `{ data: [...], total: N }`, emparejado con los stores de Zustand del frontend.
3. **Persistencia Transaccional ACID:** Toda mutación dependiente entre múltiples tablas o actualizaciones de estado de tareas se ejecuta dentro de bloques transaccionales atómicos.
4. **Idempotencia y Trazabilidad:** Todo registro incluye marcas temporales de creación y actualización con zona horaria (`TIMESTAMPTZ`) y soporte para eliminación lógica controlada.

---

## 2. Arquitectura y Separación de Esquemas (`app`, `tasks`, `audit`)

PostgreSQL organiza los objetos lógicamente mediante esquemas (`SCHEMAS`). Prohibimos el uso del esquema predeterminado `public` para objetos de la aplicación:

```text
PostgreSQL 17 Database
├── app/        → Tablas de dominio, catálogos, entidades de negocio y SPs principales
├── tasks/      → Colas de trabajos asíncronos, estados de workers y dead-letter queues
└── audit/      → Historial inmutable de eventos, cambios (CDC) y registros de seguridad
```

### Definición Inicial de Esquemas
```sql
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS tasks;
CREATE SCHEMA IF NOT EXISTS audit;

-- Asegurar permisos adecuados
REVOKE ALL ON SCHEMA public FROM PUBLIC;
```

---

## 3. Convenciones de Nomenclatura e Integridad Referencial

| Elemento | Convención | Ejemplo | Razón |
| :--- | :--- | :--- | :--- |
| **Esquemas** | `snake_case`, singular o dominio | `app`, `audit`, `tasks` | Claridad y compatibilidad ANSI SQL |
| **Tablas** | `snake_case`, plural | `app.users`, `app.orders`, `tasks.jobs` | Representan conjuntos de entidades |
| **Columnas** | `snake_case`, descriptivo | `created_at`, `total_amount`, `job_id` | Legibilidad estándar |
| **Claves Primarias** | Siempre `id UUID` | `id UUID PRIMARY KEY DEFAULT gen_random_uuid()` | Evita colisiones distribuidas |
| **Claves Foráneas** | `{entidad_singular}_id` | `user_id UUID REFERENCES app.users(id)` | Identificación inmediata |
| **Procedimientos / Funciones** | `{entidad_singular}_{acción}` | `app.user_create()`, `app.task_claim()` | Agrupación alfabética natural |
| **Índices** | `idx_{tabla}_{columnas}` | `idx_users_email`, `idx_tasks_status_prio` | Identificación en `EXPLAIN` |
| **Restricciones Unique** | `uq_{tabla}_{columnas}` | `uq_users_email` | Manejo claro de violaciones de integridad |

### Reglas de Integridad Referencial
1. **Regla Obligatoria en FKs:** Jamás declarar una llave foránea sin definir explícitamente su comportamiento ante eliminación:
   * `ON DELETE RESTRICT` (Predeterminado para entidades de negocio protegidas).
   * `ON DELETE CASCADE` (Exclusivo para tablas detalle dependientes, ej. `invoice_items` cuando se elimina `invoice`).
   * `ON DELETE SET NULL` (Solo si la relación es opcional y la columna es nullable).
2. **Restricciones CHECK:** Obligatorias para tipos enumerados, rangos y estados finitos:
   ```sql
   CONSTRAINT chk_tasks_status CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
   CONSTRAINT chk_tasks_progress CHECK (progress >= 0 AND progress <= 100)
   ```

---

## 4. Estrategia de Identificadores (UUID v4 Nativo)

Se utilizan identificadores UUID v4 (`gen_random_uuid()`) en lugar de enteros autoincrementales (`SERIAL` / `BIGSERIAL`) por dos razones:
* **Seguridad:** Evita la exposición del volumen de registros y previene ataques de enumeración (IDOR).
* **Descentralización:** Permite que clientes, APIs y workers generen identificadores válidos antes de la inserción (`crypto.randomUUID()` en Node.js o `uuid.uuid4()` en Python).

En PostgreSQL 17, `gen_random_uuid()` está integrado en el núcleo sin requerir extensiones adicionales:

```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```

---

## 5. Eliminación Lógica (*Soft Delete*) e Índices Parciales

Para preservar trazabilidad histórica y auditoría, se aplica eliminación lógica en tablas de negocio:

### Declaración de Columnas
```sql
deleted_at TIMESTAMPTZ DEFAULT NULL
```

### Índices Parciales para Unicidad
Si una columna debe ser única (por ejemplo, el correo de un usuario o el código de un producto), una restricción tradicional `UNIQUE (email)` impediría registrar nuevamente un valor previamente eliminado.

Se utiliza un índice único parcial condicionado a filas activas (`deleted_at IS NULL`):

```sql
-- Permite reutilizar el correo si el registro anterior fue eliminado lógicamente
CREATE UNIQUE INDEX uq_users_email_active
ON app.users (email)
WHERE deleted_at IS NULL;

-- Índice para optimizar consultas de listados que descartan eliminados
CREATE INDEX idx_users_created_active
ON app.users (created_at DESC)
WHERE deleted_at IS NULL;
```

---

## 6. Concurrencia y Control de Bloqueos (`FOR UPDATE SKIP LOCKED`)

Cuando múltiples workers consumen tareas en paralelo, `SELECT ... WHERE status = 'pending' LIMIT 1` genera colisiones y condiciones de carrera si dos procesos seleccionan la misma fila simultáneamente. Un bloqueo tradicional `FOR UPDATE` provoca espera pasiva y contención.

### El Patrón `SKIP LOCKED`
`FOR UPDATE SKIP LOCKED` instruye a PostgreSQL a bloquear la primera fila disponible y omitir de inmediato las que ya se encuentren bloqueadas por otras transacciones:

```sql
-- Reclamar de forma atómica y segura la siguiente tarea pendiente
WITH next_task AS (
  SELECT id
  FROM tasks.jobs
  WHERE status = 'pending'
    AND scheduled_at <= NOW()
  ORDER BY priority DESC, created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED
)
UPDATE tasks.jobs
SET
  status = 'processing',
  worker_id = p_worker_id,
  started_at = NOW(),
  attempts = attempts + 1
FROM next_task
WHERE tasks.jobs.id = next_task.id
RETURNING tasks.jobs.*;
```

> Este patrón permite que múltiples workers concurrentes consuman la cola en paralelo sin bloqueos ni contención de transacciones.

---

## 7. Manejo de Tareas Asíncronas en Base de Datos (`app.async_tasks`)

Para integrar el flujo completo entre Express, Python y React sin añadir complejidad operativa innecesaria, se define una tabla centralizada de tareas:

```sql
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

-- Índices estratégicos
CREATE INDEX idx_async_tasks_poll
ON app.async_tasks (status, scheduled_at, created_at)
WHERE status = 'pending';

CREATE INDEX idx_async_tasks_user
ON app.async_tasks (created_by, created_at DESC);
```

---

## 8. Stored Procedures y Funciones PL/pgSQL (Estándar JSONB Unificado)

Para garantizar la compatibilidad con el backend de Node.js y los stores de Zustand en Next.js, las funciones PL/pgSQL siguen una estructura invariable.

### 1. Función para Listados Paginados (`getAll`)
Retorna `{ "data": [...], "total": N }`:

```sql
CREATE OR REPLACE FUNCTION app.user_get_all(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'data', COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb),
    'total', (SELECT COUNT(*) FROM app.users WHERE deleted_at IS NULL)
  )
  INTO v_result
  FROM (
    SELECT id, name, email, role, status, created_at, updated_at
    FROM app.users
    WHERE deleted_at IS NULL
    ORDER BY created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN COALESCE(v_result, '{"data":[], "total": 0}'::jsonb);
END;
$$;
```

### 2. Función para Búsqueda por ID (`getById`)
Retorna el objeto JSON o `null`:

```sql
CREATE OR REPLACE FUNCTION app.user_get_by_id(p_id UUID)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT to_jsonb(t) INTO v_result
  FROM (
    SELECT id, name, email, role, status, created_at, updated_at
    FROM app.users
    WHERE id = p_id AND deleted_at IS NULL
  ) t;

  RETURN v_result;
END;
$$;
```

### 3. Función de Creación (`create`)
Inserta y retorna el objeto insertado:

```sql
CREATE OR REPLACE FUNCTION app.user_create(
  p_name VARCHAR,
  p_email VARCHAR,
  p_role VARCHAR DEFAULT 'user'
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_result jsonb;
BEGIN
  INSERT INTO app.users (name, email, role)
  VALUES (TRIM(p_name), LOWER(TRIM(p_email)), p_role)
  RETURNING to_jsonb(users.*) INTO v_result;

  RETURN v_result;
END;
$$;
```

### 4. Función de Eliminación Lógica (`delete`)
Aplica soft delete y retorna `{ "deleted": true }`:

```sql
CREATE OR REPLACE FUNCTION app.user_delete(p_id UUID)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE app.users
  SET deleted_at = NOW(), updated_at = NOW()
  WHERE id = p_id AND deleted_at IS NULL;

  RETURN jsonb_build_object('deleted', true);
END;
$$;
```

---

## 9. Migraciones Reversibles (`up` / `down`) y DDL Seguro

Toda alteración del esquema se documenta en un archivo de migración formal con ambas fases obligatorias.

### Estructura Canónica de una Migración
```sql
-- =============================================================================
-- Migración: 20261014_001_create_users_table.sql
-- =============================================================================

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> UP >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
BEGIN;

CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL DEFAULT 'user',
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ DEFAULT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_active
ON app.users (email) WHERE deleted_at IS NULL;

COMMIT;

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< DOWN <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
-- BEGIN;
-- DROP INDEX IF EXISTS app.uq_users_email_active;
-- DROP TABLE IF EXISTS app.users;
-- COMMIT;
```

### Directrices de DDL Seguro en Producción
1. **Evitar Bloqueos de Tablas en Índices:** En bases de datos en caliente con millones de filas, crear índices con `CREATE INDEX CONCURRENTLY` (nota: debe ejecutarse fuera de un bloque transaccional explícito `BEGIN/COMMIT`).
2. **Añadir Columnas de Forma Segura:** En PostgreSQL 11+, añadir columnas con valores por defecto constantes (ej. `ADD COLUMN status VARCHAR(20) DEFAULT 'active' NOT NULL`) es una operación instantánea que solo actualiza el catálogo y no reescribe la tabla.
3. **Estrategia de 2 Pasos para Eliminar Columnas:**
   * *Paso 1:* Dejar de leer y escribir la columna en el código (Node.js / Python).
   * *Paso 2:* En una migración posterior, marcar la columna como oculta o eliminarla (`ALTER TABLE ... DROP COLUMN`).

---

## 10. Estrategia de Indexación y Optimización de Consultas

### Reglas para Selección de Índices
* **B-Tree (Predeterminado):** Para comparaciones de igualdad (`=`), rangos (`<`, `<=`, `>`, `>=`) y ordenamientos (`ORDER BY`).
* **GIN (Generalized Inverted Index):** Obligatorio para búsquedas dentro de columnas `JSONB` (`WHERE payload @> '{"tipo": "A"}'`) o búsquedas de texto completo (`tsvector`).
* **Índices Compuestos (Orden de Columnas):** La regla de oro es colocar primero las columnas de igualdad estricta y al final las columnas de rango o fecha:
  ```sql
  -- Si la consulta es: WHERE tenant_id = X AND created_at >= Y ORDER BY created_at DESC
  CREATE INDEX idx_orders_tenant_date ON app.orders (tenant_id, created_at DESC);
  ```

### Prevención Activa de Anti-Patrones
1. **Anti-N+1 Queries:** Nunca ejecutar consultas SQL dentro de un bucle en el código de backend o worker. Utilizar `jsonb_agg` o `JOIN` en PostgreSQL para recopilar entidades asociadas en un único viaje de red (*single round-trip*).
2. **Uso de `EXPLAIN (ANALYZE, BUFFERS)`:** Antes de aprobar un procedimiento o consulta pesada, validar que no realice *Sequential Scans* involuntarios sobre tablas extensas y que los aciertos de caché en memoria (*shared hit blocks*) sean óptimos.

---

## 11. Auditoría Automática y Trazabilidad Transaccional

Para trazabilidad forense, cambios críticos en tablas de negocio pueden registrarse automáticamente mediante un Trigger universal de auditoría:

```sql
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

CREATE OR REPLACE FUNCTION audit.if_modified_func()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (TG_OP = 'UPDATE') THEN
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
```

---

## 12. Gestión de Pools de Conexión (Node.js y Python)

Tanto el backend en Node.js como los workers en Python deben compartir una gestión calibrada de conexiones a PostgreSQL:

```
                            ┌─── Node.js API Gateway (Pool max: 20)
                            │
PostgreSQL 17 (max_conn: 100) ─── Python Worker Service (AsyncConnectionPool max: 10)
                            │
                            └─── Herramientas Admin / Migraciones (1-2 conn)
```

### 1. Parámetros Críticos de Configuración
* `max_connections`: Ajustado al tamaño de memoria del servidor de base de datos.
* `idle_timeout`: 30 segundos (cierra conexiones inactivas para liberar memoria en PG).
* `connection_timeout`: 5 segundos (falla rápido si la base de datos no responde).
* `timezone`: Configurar obligatoriamente la misma zona en clientes y servidor (ej. `'America/Santiago'` o `'UTC'`).

### 2. Implementación en Python con `psycopg_pool` (v3)
```python
from psycopg_pool import AsyncConnectionPool

pool = AsyncConnectionPool(
    conninfo="postgresql://postgres:password@localhost:5432/mydb",
    min_size=2,
    max_size=10,
    timeout=5.0,
    kwargs={"options": "-c timezone=America/Santiago"}
)
```

---

## 13. Seguridad, Roles y Principio de Menor Privilegio

Para entornos de producción se crean roles con privilegios estrictamente delimitados:

```sql
-- 1. Rol de Aplicación (API Express y Worker Python)
CREATE ROLE app_user WITH LOGIN PASSWORD 'password_seguro';

-- Otorgar uso de esquemas
GRANT USAGE ON SCHEMA app, tasks TO app_user;

-- Otorgar ejecución exclusiva de Stored Procedures
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tasks TO app_user;

-- Otorgar CRUD a tablas de dominio y tareas
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tasks TO app_user;

-- Denegar permisos DDL destructivos
REVOKE CREATE ON SCHEMA app, tasks FROM app_user;
REVOKE DROP ON ALL TABLES IN SCHEMA app, tasks FROM app_user;
```

---

## 14. Flujo Integrado E2E: Front -> API -> Worker -> BD -> API -> Front

El flujo que conecta todos los componentes del sistema opera de la siguiente manera:

```text
1. [FRONTEND]
   Usuario presiona "Generar Reporte Complejo".
   El Store de Zustand invoca `taskService.dispatch({ tipo: 'REPORTE_VENTAS' })`.
   Se activa `onLoading = true` y estado `isProcessing = true`.

2. [EXPRESS API GATEWAY]
   Router recibe `POST /api/v1/tasks/dispatch`.
   Controller valida el body con Zod.
   Service ejecuta: `SELECT app.async_task_create('REPORTE_VENTAS', payload)` en PostgreSQL.
   PostgreSQL inserta con `status = 'pending'` y retorna `task_id`.
   API responde de inmediato `202 Accepted` con `{ taskId, status: 'pending' }`.

3. [PYTHON ASYNC WORKER]
   Worker en paralelo ejecuta `SELECT * FROM tasks.claim_next_task()`.
   Encuentra la tarea, la marca como `processing` y obtiene el payload.
   Ejecuta cálculos pesados, generación de modelos o consultas analíticas.
   Almacena los datos finales en las tablas correspondientes (ej. `app.reports`).
   Actualiza la tarea a `status = 'completed'` con `progress = 100`.

4. [EXPRESS API GATEWAY]
   Frontend realiza polling periódico (`GET /api/v1/tasks/:taskId/status`).
   Controller invoca `SELECT app.async_task_get_status(p_task_id)`.
   API retorna `{ success: true, data: { status: 'completed', progress: 100, resultId } }`.

5. [FRONTEND "PINTA" RESULTADOS]
   El hook detecta `status === 'completed'`.
   El store consulta los datos generados (`reportService.getById(resultId)`).
   Actualiza el estado, apaga `onLoading` y el Componente Funcional renderiza
   la tabla, gráfico o visualizador sin ningún bloqueo en la experiencia de usuario.
```

---

## 15. Checklist Pre-Deploy y Auditoría de Base de Datos

Antes de liberar cambios de base de datos a producción, verificar cada punto:

- [ ] Todas las tablas cuentan con clave primaria `UUID DEFAULT gen_random_uuid()`.
- [ ] Las tablas de negocio implementan `deleted_at TIMESTAMPTZ DEFAULT NULL`.
- [ ] Los campos únicos cuentan con un índice parcial `WHERE deleted_at IS NULL`.
- [ ] Toda llave foránea (`FOREIGN KEY`) define explícitamente su regla de eliminación (`RESTRICT` o `CASCADE`).
- [ ] No existen sentencias `DROP TABLE` o `DROP COLUMN` en migraciones directas.
- [ ] La migración cuenta con sus bloques `UP` y `DOWN` verificados en entorno de desarrollo.
- [ ] Toda función PL/pgSQL retorna `jsonb` o `{ data: [...], total: N }` para mantener paridad con el frontend.
- [ ] Se utilizó `SKIP LOCKED` en consultas de reclamo de tareas por workers.
- [ ] Se probó el plan de ejecución con `EXPLAIN ANALYZE` descartando recorridos secuenciales innecesarios.
- [ ] El pool de conexiones está configurado con timeout de inactividad y límites estrictos.
