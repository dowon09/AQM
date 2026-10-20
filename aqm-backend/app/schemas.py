from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ReadingCreate(BaseModel):
    aqi: int | None = Field(default=None, ge=0, le=500)
    tvoc: float | None = Field(default=None, ge=0)
    eco2: float | None = Field(default=None, ge=0)
    temperature: float | None = Field(default=None, ge=-50, le=100)
    humidity: float | None = Field(default=None, ge=0, le=100)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @model_validator(mode="after")
    def require_sensor_value(self):
        if all(getattr(self, field) is None for field in ("aqi", "tvoc", "eco2", "temperature", "humidity")):
            raise ValueError("At least one sensor value is required")
        return self


class ReadingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    aqi: int | None
    tvoc: float | None
    eco2: float | None
    temperature: float | None
    humidity: float | None
    timestamp: datetime
