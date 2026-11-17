import importlib.util
import os
import tempfile
from pathlib import Path

os.environ['P2P_ADMIN_PASSWORD'] = 'test-password-not-for-production'
os.environ['P2P_DEVICE_TOKEN'] = 'test-device-token-abcdefghijklmnopqrstuvwxyz'
os.environ['P2P_SESSION_SECRET'] = 'test-session-secret-abcdefghijklmnopqrstuvwxyz'
os.environ['P2P_INSECURE_LOCAL'] = '1'
with tempfile.TemporaryDirectory() as tmp:
    os.environ['P2P_DB_PATH'] = str(Path(tmp) / 'test.sqlite3')
    spec = importlib.util.spec_from_file_location('p2p_main', Path(__file__).resolve().parents[1] / 'main.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    from fastapi.testclient import TestClient
    client = TestClient(module.app)
    auth = {'Authorization': 'Bearer ' + os.environ['P2P_DEVICE_TOKEN']}
    data = {'transactions': [], 'preferences': {'usdToTJSRate': 9.28, 'openingBalances': {'USD': 0, 'TJS': 0}}, 'reportBalanceCheckpoints': []}
    assert client.get('/api/snapshot').status_code == 401
    assert client.get('/api/snapshot', headers=auth).json()['version'] == 0
    assert client.put('/api/snapshot', headers=auth, json={'baseVersion': 0, 'payload': data}).json()['version'] == 1
    assert client.put('/api/snapshot', headers=auth, json={'baseVersion': 0, 'payload': data}).status_code == 409
    assert client.get('/api/snapshot', headers=auth).json()['payload'] == data
    assert client.post('/api/login', json={'password': 'wrong'}).status_code == 401
    assert client.post('/api/login', json={'password': os.environ['P2P_ADMIN_PASSWORD']}).status_code == 200
    assert client.get('/api/snapshot').json()['version'] == 1
    assert client.put('/api/snapshot', json={'baseVersion': 1, 'payload': data}, headers={'Origin': 'https://other.example'}).status_code == 403
    assert client.put('/api/snapshot', json={'baseVersion': 1, 'payload': data}, headers={'Origin': 'http://testserver'}).json()['version'] == 2
    print('PASS: auth, read, save, conflict, same-origin protection')
