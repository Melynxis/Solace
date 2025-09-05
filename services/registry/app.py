# /home/melynxis/solace/services/registry/app.py

from fastapi import FastAPI, Body, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse, Response, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST, REGISTRY
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
from typing import Optional, Literal
import os, time, json, uuid, datetime

# -----------------------------
# Config (env with sane defaults)
# -----------------------------
MYSQL_HOST = os.getenv("MYSQL_HOST", "127.0.0.1")
MYSQL_PORT = int(os.getenv("MYSQL_PORT", "3306"))
MYSQL_DB   = os.getenv("MYSQL_DB", "solace")
MYSQL_USER = os.getenv("MYSQL_USER", "solace_app")
MYSQL_PW   = os.getenv("MYSQL_PASSWORD", "solace_app_pwd")
REGISTRY_PORT = int(os.getenv("REGISTRY_PORT", "8081"))

DATABASE_URL = f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PW}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}"

# -----------------------------
# DB engine
# -----------------------------
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=300,
    pool_size=5,
    max_overflow=10,
    future=True,
)

# -----------------------------
# App + CORS + Metrics
# -----------------------------
app = FastAPI(title="Solace Registry API", version="0.4.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],       # Set to UI origins in prod!
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

spirit_creations_total = Counter(
    "spirit_creations_total", "Number of spirit creation requests", ["role"]
)
spirit_creation_seconds = Histogram(
    "spirit_creation_duration_seconds", "Time to create a spirit"
)
request_counter = Counter(
    "solace_requests_total", "Total requests", ["route", "status"]
)

# -----------------------------
# Helpers
# -----------------------------
State = Literal["pending", "created", "ready", "error"]

ALLOWED_TRANSITIONS: dict[State, set[State]] = {
    "pending": {"created", "error"},
    "created": {"ready", "error"},
    "ready": {"error"},
    "error": {"pending", "created"},
}

def _json_or_none(obj: Optional[dict]) -> Optional[str]:
    return json.dumps(obj) if obj is not None else None

def _coerce_meta(row: dict) -> dict:
    """Ensure 'meta' is a Python object, not a JSON string."""
    r = dict(row)
    m = r.get("meta")
    if m is not None and isinstance(m, str) and m != "":
        try:
            r["meta"] = json.loads(m)
        except Exception:
            pass
    return r

def serialize_row(row: dict) -> dict:
    """
    Convert all datetime/date fields to ISO8601 strings.
    """
    r = dict(row)
    for k, v in r.items():
        if isinstance(v, (datetime.datetime, datetime.date)):
            r[k] = v.isoformat()
    return r

def get_request_id(request: Request) -> str:
    req_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    return req_id

def solace_response(ok, data=None, error=None, request_id=None):
    resp = {"ok": ok}
    if ok and data is not None:
        resp["data"] = data
    if not ok and error is not None:
        resp["error"] = error
    resp["meta"] = {"requestId": request_id or str(uuid.uuid4())}
    return JSONResponse(resp)

def log_event(conn, spirit_id: int, event_type: str,
              prev_state: Optional[str] = None,
              new_state: Optional[str] = None,
              note: Optional[str] = None,
              meta: Optional[dict] = None):
    conn.execute(
        text(
            "INSERT INTO spirit_events (spirit_id, event_type, prev_state, new_state, note, meta) "
            "VALUES (:sid, :etype, :prev, :new, :note, CAST(:meta AS JSON))"
        ),
        {
            "sid": spirit_id,
            "etype": event_type,
            "prev": prev_state,
            "new": new_state,
            "note": note,
            "meta": _json_or_none(meta),
        },
    )

def fetch_spirit(conn, spirit_id: int):
    row = conn.execute(
        text("SELECT id, name, role, state, meta, created_at, updated_at FROM spirits WHERE id=:id"),
        {"id": spirit_id},
    ).mappings().first()
    return serialize_row(_coerce_meta(row)) if row else None

def fetch_registry(conn, reg_id: str):
    row = conn.execute(
        text("SELECT id, name, type, config, auth_mode, status, created_at, updated_at FROM registry_services WHERE id=:id"),
        {"id": reg_id},
    ).mappings().first()
    if row:
        r = dict(row)
        if r.get("config") is not None and isinstance(r["config"], str):
            try:
                r["config"] = json.loads(r["config"])
            except Exception:
                pass
        return serialize_row(r)
    return None

def now_mysql():
    return datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')

# -----------------------------
# Error handling
# -----------------------------
@app.exception_handler(HTTPException)
async def solace_http_exception_handler(request: Request, exc: HTTPException):
    request_id = get_request_id(request)
    code = exc.status_code
    msg = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
    error_code = {
        400: "VALIDATION_FAILED",
        401: "UNAUTHENTICATED",
        403: "RBAC_DENIED",
        404: "NOT_FOUND",
        409: "CONFLICT",
        429: "RATE_LIMITED",
        500: "INTERNAL_ERROR"
    }.get(code, "INTERNAL_ERROR")
    error = { "code": error_code, "message": msg }
    request_counter.labels(route=request.url.path, status=str(code)).inc()
    return solace_response(False, error=error, request_id=request_id)

# -----------------------------
# Health & meta endpoints
# -----------------------------
@app.get("/health", response_class=PlainTextResponse, tags=["meta"])
def health():
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return "ok"
    except SQLAlchemyError as e:
        raise HTTPException(status_code=500, detail=f"db_error: {e}") from e

@app.get("/v1/healthz", tags=["meta"])
def healthz(request: Request):
    request_id = get_request_id(request)
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return solace_response(True, data={"status":"ok"}, request_id=request_id)
    except SQLAlchemyError as e:
        raise HTTPException(status_code=500, detail=f"db_error: {e}") from e

@app.get("/v1/version", tags=["meta"])
def version(request: Request):
    request_id = get_request_id(request)
    return solace_response(True, data={"version": app.version}, request_id=request_id)

@app.get("/v1/readyz", tags=["meta"])
def readyz(request: Request):
    request_id = get_request_id(request)
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return solace_response(True, data={"ready": True}, request_id=request_id)
    except SQLAlchemyError as e:
        raise HTTPException(status_code=500, detail=f"db_error: {e}") from e

# -----------------------------
# RBAC endpoints
# -----------------------------
@app.get("/v1/rbac/roles", tags=["rbac"])
def rbac_roles(request: Request):
    request_id = get_request_id(request)
    roles = ["owner", "admin", "maintainer", "reader"]
    return solace_response(True, data={"roles": roles}, request_id=request_id)

@app.post("/v1/rbac/check", tags=["rbac"])
def rbac_check(request: Request, subject: str = Body(...), action: str = Body(...), resource: str = Body(...)):
    request_id = get_request_id(request)
    allowed = not (action == "delete" and subject != "owner")
    result = { "allowed": allowed }
    return solace_response(True, data=result, request_id=request_id)

# -----------------------------
# Spirits endpoints
# -----------------------------
@app.post("/spirits", tags=["spirits"])
def create_spirit(request: Request,
    name: str = Body(..., embed=True),
    role: str = Body(..., embed=True),
    meta: dict | None = Body(None, embed=True),
):
    t0 = time.time()
    request_id = get_request_id(request)
    spirit_creations_total.labels(role=role).inc()
    try:
        with engine.begin() as conn:
            result = conn.execute(
                text(
                    "INSERT INTO spirits (name, role, state, meta) "
                    "VALUES (:name, :role, 'pending', CAST(:meta AS JSON))"
                ),
                {"name": name, "role": role, "meta": _json_or_none(meta)},
            )
            spirit_id = result.lastrowid
            conn.execute(text("UPDATE spirits SET state='created' WHERE id=:id"), {"id": spirit_id})
            log_event(conn, spirit_id, event_type="create", prev_state="pending", new_state="created", meta=meta)
        data = {"id": spirit_id, "name": name, "role": role, "state": "created"}
        return solace_response(True, data=data, request_id=request_id)
    finally:
        spirit_creation_seconds.observe(time.time() - t0)

@app.get("/spirits/{spirit_id}", tags=["spirits"])
def get_spirit(request: Request, spirit_id: int):
    request_id = get_request_id(request)
    with engine.connect() as conn:
        row = fetch_spirit(conn, spirit_id)
        if not row:
            raise HTTPException(status_code=404, detail="not found")
        return solace_response(True, data=row, request_id=request_id)

@app.put("/spirits/{spirit_id}/state", tags=["spirits"])
def update_spirit_state(request: Request, spirit_id: int,
                        new_state: State = Body(..., embed=True),
                        note: str | None = Body(None, embed=True)):
    request_id = get_request_id(request)
    with engine.begin() as conn:
        row = fetch_spirit(conn, spirit_id)
        if not row:
            raise HTTPException(status_code=404, detail="not found")
        prev = row["state"]
        if new_state not in ALLOWED_TRANSITIONS.get(prev, set()):
            raise HTTPException(status_code=409, detail=f"illegal transition {prev} -> {new_state}")
        conn.execute(text("UPDATE spirits SET state=:s WHERE id=:id"), {"s": new_state, "id": spirit_id})
        log_event(conn, spirit_id, event_type="state_change", prev_state=prev, new_state=new_state, note=note)
        row = fetch_spirit(conn, spirit_id)
        return solace_response(True, data=row, request_id=request_id)

@app.patch("/spirits/{spirit_id}", tags=["spirits"])
def patch_spirit(request: Request, spirit_id: int,
                 name: str | None = Body(None, embed=True),
                 meta: dict | None = Body(None, embed=True),
                 note: str | None = Body(None, embed=True)):
    request_id = get_request_id(request)
    if name is None and meta is None:
        raise HTTPException(status_code=400, detail="no changes provided")
    with engine.begin() as conn:
        raw = conn.execute(
            text("SELECT id, name, role, state, meta FROM spirits WHERE id=:id"),
            {"id": spirit_id},
        ).mappings().first()
        if not raw:
            raise HTTPException(status_code=404, detail="not found")
        updates = []
        params = {"id": spirit_id}
        if name is not None:
            updates.append("name=:name")
            params["name"] = name
        if meta is not None:
            updates.append("meta=CAST(:meta AS JSON)")
            params["meta"] = _json_or_none(meta)
        conn.execute(text(f"UPDATE spirits SET {', '.join(updates)} WHERE id=:id"), params)
        if name is not None:
            log_event(conn, spirit_id, event_type="name_update", note=note)
        if meta is not None:
            log_event(conn, spirit_id, event_type="meta_update", note=note, meta=meta)
        row = fetch_spirit(conn, spirit_id)
        return solace_response(True, data=row, request_id=request_id)

@app.get("/spirits", tags=["spirits"])
def list_spirits(request: Request,
    state: Optional[State] = Query(None),
    role: Optional[str] = Query(None),
    q: Optional[str] = Query(None, description="substring match on name"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    sort: str = Query("updated_at:desc"),
):
    request_id = get_request_id(request)
    field_map = {"id": "id", "name": "name", "role": "role", "state": "state",
                 "created_at": "created_at", "updated_at": "updated_at"}
    f, d = (sort.split(":", 1) + [""])[:2]
    order_field = field_map.get(f, "updated_at")
    order_dir = "DESC" if d.lower() != "asc" else "ASC"

    where = []
    params = {}
    if state:
        where.append("state = :state")
        params["state"] = state
    if role:
        where.append("role = :role")
        params["role"] = role
    if q:
        where.append("name LIKE :q")
        params["q"] = f"%{q}%"

    where_sql = ("WHERE " + " AND ".join(where)) if where else ""
    sql = f"""
        SELECT id, name, role, state, meta, created_at, updated_at
        FROM spirits
        {where_sql}
        ORDER BY {order_field} {order_dir}
        LIMIT :limit OFFSET :offset
    """
    params.update({"limit": limit, "offset": offset})
    with engine.connect() as conn:
        rows = conn.execute(text(sql), params).mappings().all()
        def rowmap(r):
            return serialize_row(_coerce_meta(r))
        return solace_response(True, data=[rowmap(r) for r in rows], request_id=request_id)

# -----------------------------
# Registry endpoints
# -----------------------------
@app.post("/registry", tags=["registry"])
def create_registry(request: Request,
    name: str = Body(..., embed=True),
    type: str = Body(..., embed=True),
    config: dict | None = Body(None, embed=True),
    auth_mode: str = Body("none", embed=True),
    status_: str = Body("active", embed=True)
):
    request_id = get_request_id(request)
    try:
        reg_id = str(uuid.uuid4())
        with engine.begin() as conn:
            conn.execute(
                text(
                    "INSERT INTO registry_services (id, name, type, config, auth_mode, status, created_at, updated_at) "
                    "VALUES (:id, :name, :type, :config, :auth_mode, :status, :created_at, :updated_at)"
                ),
                {
                    "id": reg_id,
                    "name": name,
                    "type": type,
                    "config": _json_or_none(config),
                    "auth_mode": auth_mode,
                    "status": status_,
                    "created_at": now_mysql(),
                    "updated_at": now_mysql()
                },
            )
        data = {
            "id": reg_id,
            "name": name,
            "type": type,
            "status": status_,
            "auth_mode": auth_mode
        }
        return solace_response(True, data=data, request_id=request_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e

@app.get("/registry/{reg_id}", tags=["registry"])
def get_registry(request: Request, reg_id: str):
    request_id = get_request_id(request)
    with engine.connect() as conn:
        row = fetch_registry(conn, reg_id)
        if not row:
            raise HTTPException(status_code=404, detail="not found")
        return solace_response(True, data=row, request_id=request_id)

@app.patch("/registry/{reg_id}", tags=["registry"])
def patch_registry(request: Request, reg_id: str,
                  name: str | None = Body(None, embed=True),
                  config: dict | None = Body(None, embed=True),
                  auth_mode: str | None = Body(None, embed=True),
                  status_: str | None = Body(None, embed=True)):
    request_id = get_request_id(request)
    if not any([name, config, auth_mode, status_]):
        raise HTTPException(status_code=400, detail="no changes provided")
    with engine.begin() as conn:
        raw = conn.execute(
            text("SELECT id FROM registry_services WHERE id=:id"),
            {"id": reg_id},
        ).mappings().first()
        if not raw:
            raise HTTPException(status_code=404, detail="not found")
        updates = []
        params = {"id": reg_id}
        if name is not None:
            updates.append("name=:name")
            params["name"] = name
        if config is not None:
            updates.append("config=CAST(:config AS JSON)")
            params["config"] = _json_or_none(config)
        if auth_mode is not None:
            updates.append("auth_mode=:auth_mode")
            params["auth_mode"] = auth_mode
        if status_ is not None:
            updates.append("status=:status")
            params["status"] = status_
        updates.append("updated_at=:updated_at")
        params["updated_at"] = now_mysql()
        conn.execute(text(f"UPDATE registry_services SET {', '.join(updates)} WHERE id=:id"), params)
        row = fetch_registry(conn, reg_id)
        return solace_response(True, data=row, request_id=request_id)

@app.delete("/registry/{reg_id}", tags=["registry"])
def delete_registry(request: Request, reg_id: str):
    request_id = get_request_id(request)
    with engine.begin() as conn:
        raw = conn.execute(
            text("SELECT id FROM registry_services WHERE id=:id"),
            {"id": reg_id},
        ).mappings().first()
        if not raw:
            raise HTTPException(status_code=404, detail="not found")
        conn.execute(text("DELETE FROM registry_services WHERE id=:id"), {"id": reg_id})
    return solace_response(True, data={"id": reg_id, "deleted": True}, request_id=request_id)

@app.get("/registry", tags=["registry"])
def list_registry(request: Request,
    type_: Optional[str] = Query(None, alias="type"),
    status_: Optional[str] = Query(None, alias="status"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    sort: str = Query("updated_at:desc"),
):
    request_id = get_request_id(request)
    field_map = {"id": "id", "name": "name", "type": "type", "status": "status",
                 "created_at": "created_at", "updated_at": "updated_at"}
    f, d = (sort.split(":", 1) + [""])[:2]
    order_field = field_map.get(f, "updated_at")
    order_dir = "DESC" if d.lower() != "asc" else "ASC"

    where = []
    params = {}
    if type_:
        where.append("type = :type")
        params["type"] = type_
    if status_:
        where.append("status = :status")
        params["status"] = status_
    where_sql = ("WHERE " + " AND ".join(where)) if where else ""
    sql = f"""
        SELECT id, name, type, config, auth_mode, status, created_at, updated_at
        FROM registry_services
        {where_sql}
        ORDER BY {order_field} {order_dir}
        LIMIT :limit OFFSET :offset
    """
    params.update({"limit": limit, "offset": offset})
    with engine.connect() as conn:
        rows = conn.execute(text(sql), params).mappings().all()
        def rowmap(r):
            rr = dict(r)
            if rr.get("config") is not None and isinstance(rr["config"], str):
                try: rr["config"] = json.loads(rr["config"])
                except Exception: pass
            return serialize_row(rr)
        return solace_response(True, data=[rowmap(r) for r in rows], request_id=request_id)

# -----------------------------
# Metrics endpoint
# -----------------------------
@app.get("/metrics", tags=["meta"])
def metrics():
    return Response(generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)
