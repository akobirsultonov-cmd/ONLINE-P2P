"""P2P private single-tenant sync server. Put behind HTTPS reverse proxy."""
import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import threading
import time
from pathlib import Path
from contextlib import contextmanager
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

ROOT = Path(__file__).resolve().parent
DATABASE = Path(os.environ.get('P2P_DB_PATH', str(ROOT / 'p2p.sqlite3')))
ADMIN_PASSWORD = os.environ.get('P2P_ADMIN_PASSWORD', '')
DEVICE_TOKEN = os.environ.get('P2P_DEVICE_TOKEN', '')
SESSION_SECRET = os.environ.get('P2P_SESSION_SECRET', '')
if not all([ADMIN_PASSWORD, DEVICE_TOKEN, SESSION_SECRET]):
    raise RuntimeError('Set P2P_ADMIN_PASSWORD, P2P_DEVICE_TOKEN and P2P_SESSION_SECRET in environment')
if len(SESSION_SECRET) < 32 or len(DEVICE_TOKEN) < 32 or len(ADMIN_PASSWORD) < 12:
    raise RuntimeError('Password >=12, token/secret >=32 characters required')
MAX_BYTES = 20 * 1024 * 1024
LOCK = threading.RLock()
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

@contextmanager
def db():
    DATABASE.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(DATABASE, timeout=30) as con:
        con.execute('CREATE TABLE IF NOT EXISTS snapshot (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL, payload TEXT NOT NULL, updated_at REAL NOT NULL)')
        yield con

# Opaque signed short-lived cookie. SameSite + Origin check for writes.
def sign(data):
    raw = base64.urlsafe_b64encode(json.dumps(data, separators=(',', ':')).encode()).decode().rstrip('=')
    sig = hmac.new(SESSION_SECRET.encode(), raw.encode(), hashlib.sha256).hexdigest()
    return raw + '.' + sig

def valid_session(token):
    try:
        raw, sig = token.split('.', 1)
        good = hmac.new(SESSION_SECRET.encode(), raw.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(sig, good): return False
        data = json.loads(base64.urlsafe_b64decode(raw + '=' * (-len(raw) % 4)))
        return data.get('exp', 0) > time.time() and data.get('role') == 'admin'
    except Exception:
        return False

def authorize(req: Request, write=False):
    bearer = req.headers.get('authorization', '')
    if bearer.startswith('Bearer ') and hmac.compare_digest(bearer[7:], DEVICE_TOKEN):
        return 'device'
    if valid_session(req.cookies.get('p2p_session', '')):
        if write:
            origin = req.headers.get('origin', '')
            # Verify Host/proxy hostname and protocol, prohibiting cross-origin requests.
            allowed = str(req.base_url).rstrip('/')
            forwarded = req.headers.get('x-forwarded-proto')
            if forwarded == 'https': allowed = 'https://' + req.headers.get('host', '')
            if origin != allowed:
                raise HTTPException(403, 'Invalid origin')
        return 'admin'
    raise HTTPException(401, 'Authentication required')

@app.middleware('http')
async def limit_request(request: Request, call_next):
    if request.url.path.startswith('/api/'):
        size = request.headers.get('content-length')
        if size and int(size) > MAX_BYTES:
            return JSONResponse({'detail': 'Request too large'}, status_code=413)
    response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['Referrer-Policy'] = 'no-referrer'
    return response

@app.get('/')
def home():
    return FileResponse(ROOT / 'static' / 'index.html')

@app.post('/api/login')
async def login(req: Request):
    data = await req.json()
    password = str(data.get('password', ''))
    if not hmac.compare_digest(password, ADMIN_PASSWORD):
        # keep response uniform
        raise HTTPException(401, 'Wrong credentials')
    response = JSONResponse({'ok': True})
    response.set_cookie('p2p_session', sign({'role': 'admin', 'exp': int(time.time()) + 8 * 3600}), httponly=True, secure=os.environ.get('P2P_INSECURE_LOCAL') != '1', samesite='strict', max_age=28800, path='/')
    return response

@app.post('/api/logout')
def logout():
    response = JSONResponse({'ok': True})
    response.delete_cookie('p2p_session', path='/')
    return response

@app.get('/api/snapshot')
def get_snapshot(req: Request):
    authorize(req)
    with LOCK, db() as con:
        row = con.execute('SELECT version,payload,updated_at FROM snapshot WHERE id=1').fetchone()
    if not row: return {'version': 0, 'payload': None, 'updatedAt': None}
    return {'version': row[0], 'payload': json.loads(row[1]), 'updatedAt': row[2]}

@app.put('/api/snapshot')
async def put_snapshot(req: Request):
    authorize(req, write=True)
    raw = await req.body()
    if len(raw) > MAX_BYTES: raise HTTPException(413, 'Request too large')
    try: data = json.loads(raw)
    except Exception: raise HTTPException(400, 'Invalid JSON')
    base = data.get('baseVersion')
    payload = data.get('payload')
    if type(base) is not int or base < 0: raise HTTPException(422, 'baseVersion required')
    if not isinstance(payload, dict) or not isinstance(payload.get('transactions'), list) or not isinstance(payload.get('preferences'), dict) or not isinstance(payload.get('reportBalanceCheckpoints', []), list):
        raise HTTPException(422, 'Invalid P2P backup')
    if len(payload['transactions']) > 100000: raise HTTPException(422, 'Too many transactions')
    for tx in payload['transactions']:
        if not isinstance(tx, dict) or not all(k in tx for k in ('id','number','personName','type','amount','currency','date')):
            raise HTTPException(422, 'Invalid transaction')
        if tx['type'] not in ('received','paid','adjustment','exchange') or tx['currency'] not in ('USD','TJS'):
            raise HTTPException(422, 'Invalid type/currency')
    serialized = json.dumps(payload, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
    now = time.time()
    with LOCK, db() as con:
        con.execute('BEGIN IMMEDIATE')
        row = con.execute('SELECT version FROM snapshot WHERE id=1').fetchone()
        current = row[0] if row else 0
        if base != current:
            raise HTTPException(409, detail={'error':'version_conflict','serverVersion':current})
        con.execute('INSERT INTO snapshot (id,version,payload,updated_at) VALUES (1,?,?,?) ON CONFLICT(id) DO UPDATE SET version=excluded.version,payload=excluded.payload,updated_at=excluded.updated_at', (current+1,serialized,now))
        con.commit()
    return {'version':current+1,'updatedAt':now}

@app.get('/api/health')
def health():
    return {'ok': True}
