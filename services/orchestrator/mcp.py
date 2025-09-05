# /home/melynxis/solace/services/orchestrator/mcp.py
"""
Ghostpaw MCP — Master Control Program
Section 3: MCP manages runtime, lifecycle, and orchestration.
Tmux creation/modification logic will be added later.
"""

from fastapi import FastAPI, Body, HTTPException
from typing import Optional, Literal
import time

app = FastAPI(title="Ghostpaw MCP", version="0.1.0")

# In-memory state (will wire to DB/Registry later)
spirits: dict[str, dict] = {}

@app.get("/v1/mcp/health")
def health():
    return {"ok": True, "spirits": len(spirits)}

@app.post("/v1/mcp/birth")
def birth_spirit(
    name: str = Body(..., embed=True),
    role: str = Body(..., embed=True),
    meta: Optional[dict] = Body(None, embed=True)
):
    # Tmux creation logic will be added in future
    if name in spirits:
        raise HTTPException(status_code=409, detail="spirit name exists")
    spirit = {
        "name": name,
        "role": role,
        "state": "created",
        "meta": meta or {},
        "born_at": int(time.time())
    }
    spirits[name] = spirit
    return {"ok": True, "spirit": spirit}

@app.post("/v1/mcp/change")
def change_spirit(
    name: str = Body(..., embed=True),
    new_state: Literal["ready", "error", "archived"] = Body(..., embed=True),
    note: Optional[str] = Body(None, embed=True)
):
    if name not in spirits:
        raise HTTPException(status_code=404, detail="spirit not found")
    spirits[name]["state"] = new_state
    spirits[name]["note"] = note
    spirits[name]["changed_at"] = int(time.time())
    return {"ok": True, "spirit": spirits[name]}

@app.get("/v1/mcp/spirits")
def list_spirits():
    return {"ok": True, "spirits": list(spirits.values())}
