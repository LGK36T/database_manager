---
name: database-manager
description: >-
  Instrucciones y estándares de ingeniería para diseñar esquemas, escribir migraciones reversibles, implementar Stored Procedures en PL/pgSQL y gestionar persistencia en PostgreSQL 17 con Node.js y Python.
---

# Database Manager

Guía de ingeniería, persistencia y flujo de trabajo para bases de datos relacionales en PostgreSQL 17, PL/pgSQL, migraciones reversibles y concurrencia segura con Node.js y Python.

---

## Arquitectura de Persistencia

Toda interacción de datos se canaliza a través de capas bien definidas:

```
Aplicación (Express / Python Worker)
       ↓
Llamada SQL parametrizada a Stored Procedure: SELECT app.{entity}_*(...) AS data
       ↓
PostgreSQL 17 (Esquema app / tasks)
       ↓
Serialización JSONB nativa en motor C: jsonb_build_object('data', ..., 'total', ...)
       ↓
Resultado directo en rows[0].data (cero mapeo ORM innecesario)
```

Documentación detallada en [Guía de Arquitectura Técnica](./references/technical-architecture.md).

---

## Flujo de Trabajo

Al diseñar o modificar el modelo de datos de una entidad o subsistema, seguir este orden estricto:

### 1. Diseñar el Esquema Relacional
- Ubicación: Esquema `app` para negocio, `tasks` para colas asíncronas, `audit` para trazabilidad.
- Claves primarias obligatorias: `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`.
- Soporte de soft delete: `deleted_at TIMESTAMPTZ DEFAULT NULL`.
- Restricciones de integridad explícitas (`NOT NULL`, `CHECK`, `FOREIGN KEY ... ON DELETE RESTRICT`).
- Referencia: [table-with-audit.template.sql](./resources/templates/table-with-audit.template.sql).

### 2. Configurar Índices Estratégicos
- En campos únicos con soft delete: crear **índices únicos parciales** (`WHERE deleted_at IS NULL`).
- En campos de consulta frecuente: índices B-Tree en `created_at DESC`, llaves foráneas y estados.
- En campos JSONB de consulta interna: índices GIN (`USING gin (metadata)`).

### 3. Redactar Migración Reversible (`up` / `down`)
- Ubicación: `migrations/YYYYMMDD_NNN_{nombre}.sql`.
- Toda migración debe incluir el bloque forward (`UP`) y el bloque rollback (`DOWN`).
- Emplear sentencias idempotentes (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`).
- Referencia: [migration-up-down.template.sql](./resources/templates/migration-up-down.template.sql).

### 4. Implementar Stored Procedures CRUD (Esquema `app`)
- Retorno invariable: formato `jsonb`.
- Listados (`_get_all`): retornar `{ data: jsonb_agg(...), total: count(*) }`.
- Detalle / Crear / Actualizar: retornar `to_jsonb(t)`.
- Eliminación lógica (`_delete`): actualizar `deleted_at = NOW()` y retornar `{ deleted: true }`.
- Referencia: [stored-procedures.template.sql](./resources/templates/stored-procedures.template.sql).

### 5. Configurar Colas de Tareas para Workers Asíncronos
- Si el módulo requiere procesamiento en segundo plano, utilizar la tabla `app.async_tasks`.
- Implementar el reclamo de tareas mediante el procedimiento seguro `app.async_task_claim()` usando `FOR UPDATE SKIP LOCKED`.
- Referencia: [task-queue-schema.template.sql](./resources/templates/task-queue-schema.template.sql).

### 6. Configurar Conexiones y Pooling en Clientes
- Node.js (Backend): Configurar `pg.Pool` con límite de 20 conexiones e inactividad de 30s.
- Python (Workers): Emplear `psycopg_pool.AsyncConnectionPool` con context manager asíncrono.
- Referencia: [python-db-pool.template.py](./resources/templates/python-db-pool.template.py).

### 7. Verificación del Plan de Ejecución
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT app.entity_get_all(50, 0);
```
Validar que no existan lecturas secuenciales completas (*Seq Scan*) en tablas grandes y que los índices respondan adecuadamente.

---

## Reglas Estrictas

- Prohibido el uso de sentencias destructivas (`DROP TABLE`, `DROP DATABASE`, `TRUNCATE`) en migraciones directas.
- Toda interacción con la base de datos debe ejecutarse mediante Stored Procedures del esquema `app`.
- Jamás concatenar cadenas para construir consultas SQL; utilizar siempre parámetros posicionales (`$1`, `$2` o `%s`).
- Las colecciones (`_get_all`) deben retornar `{ data: T[], total: number }` para paridad con `frontend_manager`.
- Los workers deben usar obligatoriamente `SKIP LOCKED` para evitar colisiones y bloqueos en colas de tareas.
- Configurar siempre la misma zona horaria en el servidor y las conexiones (`options: "-c timezone=America/Santiago"` o `'UTC'`).

---

## Referencias y Plantillas

- [Guía de Arquitectura Técnica](./references/technical-architecture.md)
- [Plantillas de Código SQL y Python](./resources/templates/)
