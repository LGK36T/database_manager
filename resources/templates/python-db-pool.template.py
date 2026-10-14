"""
Plantilla: Pool de Conexiones Asíncrono en Python (psycopg v3)
Diseñado para Workers Asíncronos y Microservicios que consumen PostgreSQL 17.
"""

import os
import json
import logging
from typing import Any, Optional, Dict
from contextlib import asynccontextmanager
from psycopg_pool import AsyncConnectionPool
from psycopg.rows import dict_row

logger = logging.getLogger("database")

class DatabasePool:
    _instance: Optional["DatabasePool"] = None
    _pool: Optional[AsyncConnectionPool] = None

    def __init__(self) -> None:
        db_host = os.getenv("DB_HOST", "localhost")
        db_port = os.getenv("DB_PORT", "5432")
        db_name = os.getenv("DB_NAME", "mydb")
        db_user = os.getenv("DB_USER", "postgres")
        db_pass = os.getenv("DB_PASSWORD", "password")
        min_conn = int(os.getenv("DB_POOL_MIN", "2"))
        max_conn = int(os.getenv("DB_POOL_MAX", "10"))

        conninfo = f"postgresql://{db_user}:{db_pass}@{db_host}:{db_port}/{db_name}"

        self._pool = AsyncConnectionPool(
            conninfo=conninfo,
            min_size=min_conn,
            max_size=max_conn,
            timeout=10.0,
            max_idle=30.0,
            kwargs={
                "row_factory": dict_row,
                "options": "-c timezone=America/Santiago"
            },
            open=False
        )

    @classmethod
    def get_instance(cls) -> "DatabasePool":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    async def open(self) -> None:
        """Inicializa el pool de conexiones."""
        if self._pool and not self._pool.opened:
            await self._pool.open()
            logger.info("Pool de PostgreSQL inicializado correctamente")

    async def close(self) -> None:
        """Cierra todas las conexiones del pool de forma limpia."""
        if self._pool and self._pool.opened:
            await self._pool.close()
            logger.info("Pool de PostgreSQL cerrado correctamente")

    @asynccontextmanager
    async def connection(self):
        """Context manager para obtener una conexión del pool."""
        if not self._pool:
            raise RuntimeError("El pool de base de datos no está inicializado")
        async with self._pool.connection() as conn:
            yield conn

    async def execute_sp(self, sp_name: str, params: Optional[list] = None) -> Any:
        """
        Ejecuta un Stored Procedure en PostgreSQL y extrae el resultado JSONB.
        Ejemplo: await db.execute_sp("app.entity_get_all", [50, 0])
        """
        params = params or []
        placeholders = ", ".join(["%s"] * len(params))
        query = f"SELECT {sp_name}({placeholders}) AS data;"

        async with self.connection() as conn:
            async with conn.cursor() as cur:
                await cur.execute(query, params)
                row = await cur.fetchone()
                return row["data"] if row else None

# Instancia singleton accesible
db_pool = DatabasePool.get_instance()
