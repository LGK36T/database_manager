---
name: database-manager
description: >-
  Instrucciones y estándares de seguridad para agentes de IA al diseñar esquemas, escribir migraciones, optimizar consultas SQL/NoSQL y gestionar la persistencia de datos.
---

# Skill: Database Manager para Agentes de IA

Este skill define las pautas críticas para que los agentes de IA interactúen con bases de datos con máxima seguridad, garantizando la integridad de los datos, evitando mutaciones destructivas y optimizando el rendimiento.

---

## 🎯 Directrices Principales de Comportamiento

### 1. Migraciones Reversibles y Reproducibles
- Cada cambio en el esquema debe implementarse mediante un archivo de migración formal con ambas fases:
  - **`up` / forward:** aplica la mutación o adición.
  - **`down` / rollback:** revierte exactamente el cambio sin dejar inconsistencias.
- Las migraciones deben ser idempotentes siempre que sea posible (`IF NOT EXISTS`, `IF EXISTS`).

### 2. Prevención de Mutaciones Destructivas
- **Prohibición absoluta:** Jamás emitir instrucciones destructivas (`DROP TABLE`, `DROP DATABASE`, `TRUNCATE`, `ALTER TABLE DROP COLUMN`) en entornos compartidos o producción sin confirmación explícita y plan de respaldo.
- Para eliminar columnas en sistemas en vivo, aplicar la estrategia de 2 fases: deprecación en código primero, eliminación en migración posterior.

### 3. Optimización de Consultas y Rendimiento
- **Prevención de N+1 Queries:** Usar joins, agregaciones o cargas tempranas (eager loading / dataloaders) en lugar de consultas dentro de bucles.
- **Indexación Estratégica:** Añadir índices a columnas utilizadas frecuentemente en cláusulas `WHERE`, `JOIN` y `ORDER BY`. Evitar sobre-indexar columnas con baja cardinalidad.
- **Paginación Obligatoria:** Toda consulta que retorne colecciones debe utilizar paginación (basada en cursores o límites con offset).

### 4. Transaccionalidad e Integridad
- Operaciones que afecten múltiples tablas o registros interdependientes deben ejecutarse dentro de una **transacción atómica (`BEGIN ... COMMIT / ROLLBACK`)**.
- Respetar llaves foráneas (`FOREIGN KEY`) y restricciones de integridad (`NOT NULL`, `CHECK`, `UNIQUE`).

---

## 🚫 Acciones Prohibidas para el Agente

- ❌ Ejecutar consultas con concatenación de cadenas sin parámetros (SQL Injection).
- ❌ Crear migraciones irreversibles o sin método `down`.
- ❌ Realizar operaciones masivas (`UPDATE` o `DELETE`) sin cláusula `WHERE`.
- ❌ Almacenar datos sensibles (tarjetas, contraseñas, PII) sin cifrado ni hashing.
