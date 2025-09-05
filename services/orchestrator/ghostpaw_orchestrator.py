# /home/melynxis/solace/services/orchestrator/ghostpaw_orchestrator.py

from fastapi import FastAPI, Body, HTTPException
from typing import Dict, Literal, Optional
import time

app = FastAPI(title="Ghostpaw Orchestrator", version="0.1.0")

# In-memory registry for demo; move to MySQL table for production
registered_services: Dict[str, Dict] = {}

@app.post("/v1/registry/checkin")
def checkin_service(
    name: str = Body(..., embed=True),
    service_type: Literal["spirit", "builder", "dashboard", "memory", "control", "other"] = Body(..., embed=True),
    api_url: str = Body(..., embed=True),
    meta: Optional[dict] = Body(None, embed=True)
):
    registered_services[name] = {
        "type": service_type,
        "api_url": api_url,
        "meta": meta or {},
        "last_checkin": int(time.time()),
        "status": "online"
    }
    return {"ok": True, "data": registered_services[name]}

@app.get("/v1/registry/services")
def list_services():
    return {"ok": True, "data": list(registered_services.values())}

@app.post("/v1/registry/service_status")
def update_service_status(
    name: str = Body(..., embed=True),
    status: Literal["online", "offline", "error"] = Body(..., embed=True)
):
    if name not in registered_services:
        raise HTTPException(status_code=404, detail="Service not found")
    registered_services[name]["status"] = status
    registered_services[name]["last_checkin"] = int(time.time())
    return {"ok": True, "data": registered_services[name]}

@app.get("/v1/registry/health")
def registry_health():
    # Simple alive check
    return {"ok": True, "services": len(registered_services)}
