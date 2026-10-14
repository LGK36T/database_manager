# Database Manager

Skill de desarrollo y persistencia en bases de datos relacionales para agentes de IA y desarrolladores. Define estándares de modelado, migraciones reproducibles, Stored Procedures en PL/pgSQL y concurrencia segura para PostgreSQL 17 con Node.js y Python.

---

## Arquitectura y Principios

- **Esquematización y Aislamiento:** Separación estricta en esquemas `app` (lógica de negocio), `tasks` (colas asíncronas) y `audit` (trazabilidad y logs inmutables).
- **Paridad con Backend y Frontend:** Stored Procedures que serializan nativamente a `jsonb`, devolviendo `{ data: T[], total: number }` en colecciones para mapeo directo con los stores de Zustand.
- **Concurrencia Segura con SKIP LOCKED:** Procedimientos de reclamo de tareas para workers en Python (`app.async_task_claim`) que evitan bloqueos contenciosos y condiciones de carrera entre múltiples réplicas.
- **Identificadores UUID v4:** Uso exclusivo de `gen_random_uuid()` como clave primaria para evitar problemas de enumeración (IDOR) y facilitar la generación descentralizada.
- **Eliminación Lógica e Índices Parciales:** Manejo de soft delete mediante `deleted_at` combinado con índices únicos parciales (`WHERE deleted_at IS NULL`) que permiten recrear registros sin colisiones.
- **Migraciones Reversibles:** Estructura mandatoria de fases `up` y `down` garantizando rollbacks limpios e idempotentes.

---

## Estructura del Repositorio

```text
database_manager/
├── SKILL.md                          # Instrucciones y flujo de trabajo principal
├── references/                       # Documentación técnica de referencia
│   └── technical-architecture.md     # Especificación técnica exhaustiva
├── resources/
│   └── templates/                    # Plantillas de código reutilizables
│       ├── migration-up-down.template.sql   # Migración reversible segura
│       ├── table-with-audit.template.sql    # Tabla con auditoría automática y soft delete
│       ├── stored-procedures.template.sql   # SPs CRUD con serialización JSONB
│       ├── task-queue-schema.template.sql   # Esquema y funciones para colas con SKIP LOCKED
│       └── python-db-pool.template.py       # Pool asíncrono en Python con psycopg v3
├── CHANGELOG.md                      # Historial de cambios
├── LICENSE                           # Licencia MIT
└── README.md                         # Este documento
```

---

## Instalación y Uso

Colocar este directorio dentro de la ruta de skills del entorno de trabajo:

```bash
.agents/skills/database_manager/
```

Para consultar el flujo de trabajo completo, ver [SKILL.md](./SKILL.md).

---

## Licencia

[MIT](./LICENSE)
