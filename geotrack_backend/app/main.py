from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import HTTPBearer
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
import uvicorn
from dotenv import load_dotenv

# Charger les variables d'environnement
load_dotenv()

from app.database import engine, get_db
from app.models import Base
from app.routes import auth, config, data, heartbeat

# Create database tables
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Nexor GeoTrack API",
    description="GPS tracking system with offline capabilities",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth.router, prefix="/auth", tags=["authentication"])
app.include_router(config.router, prefix="/config", tags=["configuration"])
app.include_router(data.router, prefix="/data", tags=["gps-data"])
app.include_router(heartbeat.router, prefix="/heartbeat", tags=["device-monitoring"])

@app.get("/")
async def root():
    return {"message": "Nexor GeoTrack API is running"}

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)