"""
ProctorLens backend — minimal REST API for flag ingestion and retrieval.

Endpoints:
    POST /flags                   — log one integrity flag
    GET  /sessions/{id}/flags     — list all flags for a session

Storage: SQLite via aiosqlite (single file, no ORM needed at this scale).
"""

import asyncio
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from typing import Literal

import aiosqlite
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

DB_PATH = Path(__file__).parent / "proctor.db"

FLAG_TYPES = Literal["no_face", "multiple_faces", "head_turned_away", "app_backgrounded"]


# ---------------------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------------------

async def init_db() -> None:
    """Create tables if they don't exist yet."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS flags (
                id          TEXT PRIMARY KEY,
                session_id  TEXT NOT NULL,
                flag_type   TEXT NOT NULL,
                timestamp   TEXT NOT NULL
            )
        """)
        await db.execute("CREATE INDEX IF NOT EXISTS idx_session ON flags (session_id)")
        await db.commit()


# ---------------------------------------------------------------------------
# Lifespan (replaces deprecated on_event)
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="ProctorLens API",
    version="1.0.0",
    lifespan=lifespan,
)

# Allow the iOS app (and local dashboard) to call this without CORS issues.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class FlagIn(BaseModel):
    id: str = Field(..., description="UUID generated on device")
    session_id: str
    flag_type: FLAG_TYPES
    timestamp: str = Field(..., description="ISO 8601 UTC string")


class FlagOut(BaseModel):
    id: str
    session_id: str
    flag_type: str
    timestamp: str


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.post("/flags", status_code=201, response_model=FlagOut)
async def log_flag(flag: FlagIn) -> FlagOut:
    """Persist one integrity flag from the iOS app."""
    async with aiosqlite.connect(DB_PATH) as db:
        try:
            await db.execute(
                "INSERT INTO flags (id, session_id, flag_type, timestamp) VALUES (?, ?, ?, ?)",
                (flag.id, flag.session_id, flag.flag_type, flag.timestamp),
            )
            await db.commit()
        except sqlite3.IntegrityError:
            # Duplicate id — idempotent, just return the existing record.
            pass

    return FlagOut(
        id=flag.id,
        session_id=flag.session_id,
        flag_type=flag.flag_type,
        timestamp=flag.timestamp,
    )


@app.get("/sessions/{session_id}/flags", response_model=list[FlagOut])
async def get_flags(session_id: str) -> list[FlagOut]:
    """Return all flags for a session, sorted by timestamp ascending."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT id, session_id, flag_type, timestamp FROM flags "
            "WHERE session_id = ? ORDER BY timestamp ASC",
            (session_id,),
        )
        rows = await cursor.fetchall()

    return [FlagOut(**dict(row)) for row in rows]


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
