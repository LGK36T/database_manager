# Database Manager (AI Agent Skill)

Skill especializada para guiar a los agentes de Inteligencia Artificial al diseñar esquemas, gestionar migraciones, optimizar consultas y administrar la persistencia de datos con máxima seguridad.

---

## 📌 ¿Qué es este Skill?

**Database Manager** proporciona a los agentes de IA (como Antigravity, Claude Code, Cursor, Copilot, etc.) un conjunto riguroso de reglas y directrices para prevenir pérdidas de datos, bloqueos de tablas y degradaciones de rendimiento durante el desarrollo y mantenimiento de bases de datos.

La especificación completa del comportamiento del agente se encuentra en [SKILL.md](file:///home/LGK36T/workspace/skills/database_manager/SKILL.md).

---

## 🎯 Directrices que impone a la IA

- **Migraciones Reversibles:** Obligatoriedad de scripts `up` y `down` para garantizar rollbacks seguros e idempotentes.
- **Prevención de Destrucción:** Bloqueo estricto de comandos destructivos (`DROP`, `TRUNCATE`) sin aprobación explícita.
- **Optimización de Rendimiento:** Prevención activa de problemas de N+1 queries, indexación adecuada y paginación en todas las listas.
- **Integridad y Transacciones:** Agrupación de operaciones dependientes en transacciones ACID con manejo de bloqueos y fallos.
- **Sanitización Total:** Uso mandatorio de consultas parametrizadas o capas ORM seguras contra inyección SQL.

---

## 📂 Contenido del Repositorio

```text
database_manager/
├── SKILL.md             # Instrucciones principales para el agente de IA
├── CHANGELOG.md         # Historial de cambios del skill
├── LICENSE              # Licencia de código abierto (MIT)
├── README.md            # Documentación y descripción del skill
└── .gitignore           # Exclusiones de control de versiones
```

---

## 🚀 Uso e Integración

### En Google Antigravity / Asistentes IA
Coloca este repositorio dentro del directorio de skills de tu espacio de trabajo:
```bash
.agents/skills/database_manager/
# o ~/.gemini/antigravity-cli/skills/database_manager/
```
El agente descubrirá automáticamente el archivo `SKILL.md` y aplicará estas pautas de manera progresiva cuando interactúe con modelos de datos, migraciones o consultas.

---

## 📄 Licencia

Este proyecto está bajo la licencia [MIT](file:///home/LGK36T/workspace/skills/database_manager/LICENSE).
