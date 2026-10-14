# Changelog

Todos los cambios notables en este proyecto serán documentados en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/),
y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

---

## [2.0.0] - 2026-10-14

### Añadido
- Documento exhaustivo de arquitectura técnica en [references/technical-architecture.md](./references/technical-architecture.md) con especificaciones de PostgreSQL 17, concurrencia `SKIP LOCKED`, diseño de esquemas (`app`, `tasks`, `audit`), índices parciales, auditoría transaccional y pooling en Node.js y Python.
- Plantillas canónicas de código en `resources/templates/`:
  - `migration-up-down.template.sql` (Migraciones reversibles seguras e idempotentes).
  - `table-with-audit.template.sql` (Modelado con UUID, soft delete y triggers de Change Data Capture en `audit.logs`).
  - `stored-procedures.template.sql` (Procedimientos CRUD con serialización JSONB directa y formato `{ data, total }`).
  - `task-queue-schema.template.sql` (Tabla `app.async_tasks` y procedimientos de reclamo seguro con `FOR UPDATE SKIP LOCKED`).
  - `python-db-pool.template.py` (Pool de conexiones asíncrono en Python con `psycopg v3` y context managers).
- Especificación del flujo de extremo a extremo: Front -> API -> Worker (Python) -> BD -> API -> Front.

### Modificado
- Actualizado [SKILL.md](./SKILL.md) con flujo de trabajo por fases de 7 pasos, verificación con `EXPLAIN ANALYZE` y reglas estrictas para agentes de IA.
- Actualizado [README.md](./README.md) con la nueva estructura de repositorios y principios de persistencia.

---

## [0.2.0] - 2026-10-11

### Añadido
- Archivo nativo para agentes de IA ([SKILL.md](./SKILL.md)) con directrices de migraciones reversibles, prevención de mutaciones destructivas, anti-N+1 e integridad transaccional.
- Licencia de código abierto MIT ([LICENSE](./LICENSE)).

### Modificado
- Reorientación completa del proyecto de módulo genérico a **Skill para agentes de IA** en [README.md](./README.md).

---

## [0.1.0] - 2026-10-11

### Añadido
- Inicialización del repositorio Git y configuración base del proyecto.
- Documentación inicial y registro de control de cambios.
- Configuración de exclusiones de archivos para control de versiones (`.gitignore`).
