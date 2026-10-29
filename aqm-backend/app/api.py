import os
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Reading
from app.schemas import ReadingCreate, ReadingResponse

router = APIRouter(prefix="/api")
MAX_HISTORY_READINGS = 12_000


@router.get("/health")
def health(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        raise HTTPException(status_code=503, detail="Database unavailable") from exc
    return {"status": "ok", "database": "ok"}


@router.post("/readings", response_model=ReadingResponse, status_code=201)
def create_reading(
    payload: ReadingCreate,
    x_device_key: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    expected_key = os.getenv("DEVICE_API_KEY", "")
    if not expected_key:
        raise HTTPException(status_code=503, detail="Device ingestion is not configured")
    if x_device_key is None or not secrets.compare_digest(x_device_key, expected_key):
        raise HTTPException(status_code=401, detail="Invalid device key")

    reading = Reading(**payload.model_dump())
    db.add(reading)
    db.commit()
    db.refresh(reading)
    return reading


@router.get("/readings/latest", response_model=ReadingResponse | None)
def get_latest_reading(db: Session = Depends(get_db)):
    return db.scalar(select(Reading).order_by(Reading.timestamp.desc(), Reading.id.desc()).limit(1))


@router.get("/readings", response_model=list[ReadingResponse])
def get_readings(
    hours: int = Query(default=24, ge=1, le=168),
    db: Session = Depends(get_db),
):
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    statement = (
        select(Reading)
        .where(Reading.timestamp >= cutoff)
        .order_by(Reading.timestamp.desc(), Reading.id.desc())
        .limit(MAX_HISTORY_READINGS)
    )
    return list(reversed(db.scalars(statement).all()))
