from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import List

from app.database import get_db
from app.models import DeviceHeartbeat

router = APIRouter()


class HeartbeatRequest(BaseModel):
    device_id: str
    timestamp: str
    service_status: str = "running"


class HeartbeatResponse(BaseModel):
    success: bool
    message: str
    device_id: str


class DeviceStatusResponse(BaseModel):
    device_id: str
    service_status: str
    last_heartbeat: datetime
    is_online: bool


@router.post("/", response_model=HeartbeatResponse)
async def receive_heartbeat(
    heartbeat: HeartbeatRequest,
    db: Session = Depends(get_db)
):
    """
    Receive heartbeat from a device to indicate it's online and running.
    Updates existing record or creates new one.
    """
    try:
        # Parse the timestamp
        try:
            heartbeat_time = datetime.fromisoformat(heartbeat.timestamp.replace('Z', '+00:00'))
        except ValueError:
            heartbeat_time = datetime.utcnow()

        # Check if device heartbeat record exists
        existing = db.query(DeviceHeartbeat).filter(
            DeviceHeartbeat.device_id == heartbeat.device_id
        ).first()

        if existing:
            # Update existing record
            existing.last_heartbeat = heartbeat_time
            existing.service_status = heartbeat.service_status
        else:
            # Create new record
            new_heartbeat = DeviceHeartbeat(
                device_id=heartbeat.device_id,
                service_status=heartbeat.service_status,
                last_heartbeat=heartbeat_time
            )
            db.add(new_heartbeat)

        db.commit()

        return HeartbeatResponse(
            success=True,
            message="Heartbeat received",
            device_id=heartbeat.device_id
        )

    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/status/{device_id}", response_model=DeviceStatusResponse)
async def get_device_status(
    device_id: str,
    db: Session = Depends(get_db)
):
    """
    Get the current status of a specific device.
    Device is considered online if last heartbeat was within 30 minutes.
    """
    heartbeat = db.query(DeviceHeartbeat).filter(
        DeviceHeartbeat.device_id == device_id
    ).first()

    if not heartbeat:
        raise HTTPException(status_code=404, detail="Device not found")

    # Consider device online if heartbeat within last 30 minutes
    is_online = (datetime.utcnow() - heartbeat.last_heartbeat.replace(tzinfo=None)) < timedelta(minutes=30)

    return DeviceStatusResponse(
        device_id=heartbeat.device_id,
        service_status=heartbeat.service_status,
        last_heartbeat=heartbeat.last_heartbeat,
        is_online=is_online
    )


@router.get("/devices", response_model=List[DeviceStatusResponse])
async def get_all_devices_status(
    db: Session = Depends(get_db)
):
    """
    Get status of all registered devices.
    Useful for monitoring dashboard.
    """
    heartbeats = db.query(DeviceHeartbeat).all()

    result = []
    for hb in heartbeats:
        is_online = (datetime.utcnow() - hb.last_heartbeat.replace(tzinfo=None)) < timedelta(minutes=30)
        result.append(DeviceStatusResponse(
            device_id=hb.device_id,
            service_status=hb.service_status,
            last_heartbeat=hb.last_heartbeat,
            is_online=is_online
        ))

    return result


@router.get("/devices/online", response_model=List[DeviceStatusResponse])
async def get_online_devices(
    db: Session = Depends(get_db)
):
    """
    Get only devices that are currently online (heartbeat within 30 min).
    """
    cutoff_time = datetime.utcnow() - timedelta(minutes=30)
    
    heartbeats = db.query(DeviceHeartbeat).filter(
        DeviceHeartbeat.last_heartbeat >= cutoff_time
    ).all()

    return [
        DeviceStatusResponse(
            device_id=hb.device_id,
            service_status=hb.service_status,
            last_heartbeat=hb.last_heartbeat,
            is_online=True
        )
        for hb in heartbeats
    ]


@router.get("/devices/offline", response_model=List[DeviceStatusResponse])
async def get_offline_devices(
    db: Session = Depends(get_db)
):
    """
    Get devices that are offline (no heartbeat in last 30 min).
    Useful for alerts/monitoring.
    """
    cutoff_time = datetime.utcnow() - timedelta(minutes=30)
    
    heartbeats = db.query(DeviceHeartbeat).filter(
        DeviceHeartbeat.last_heartbeat < cutoff_time
    ).all()

    return [
        DeviceStatusResponse(
            device_id=hb.device_id,
            service_status=hb.service_status,
            last_heartbeat=hb.last_heartbeat,
            is_online=False
        )
        for hb in heartbeats
    ]
