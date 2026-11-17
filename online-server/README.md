# P2P Online Sync — self-hosted administrator server

An online admin UI and a private API for the original iOS 2.10.1 SwiftUI app. **This package is source code, not a deployed website or App Store build.**

## Features

- Existing web interface: operations (receive/pay/exchange/adjustment), report checkpoints, USD/TJS rate, opening balances, backup JSON export/import.
- Server-side SQLite persistence, admin login, HTTPS-compatible signed HttpOnly cookies, and a separate bearer token for iPhone.
- Versioned full-backup snapshot API. A stale PUT receives **409 Conflict**; never last-write-wins.
- iPhone remains usable offline. Local edits are queued and synced upon connectivity; remote changes are polled every ~15s while the app is active. Background or instant APNs updates when the app is closed are **not implemented**.
- Included original iOS SwiftUI sources modified to show an Online Sync configuration screen. iOS build not tested on an Apple build environment.

## Quick local verification (not for exposure to the internet)

```bash
cd online-server
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export P2P_ADMIN_PASSWORD='choose-a-unique-password-over-12-chars'
export P2P_DEVICE_TOKEN="$(python3 -c 'import secrets;print(secrets.token_urlsafe(48))')"
export P2P_SESSION_SECRET="$(python3 -c 'import secrets;print(secrets.token_urlsafe(48))')"
export P2P_INSECURE_LOCAL=1
uvicorn main:app --host 127.0.0.1 --port 8000
```

Open http://127.0.0.1:8000 and sign in with P2P_ADMIN_PASSWORD. **Local HTTP is for checking the web interface only; iOS requires HTTPS.** Store the token securely so you can enter it in the iOS app.

## Production deployment

1. Provision a VPS with persistent storage, valid domain, TLS 1.2+, firewall, and daily encrypted database backups.
2. Set secrets (do not commit to Git) in `online-server/.env` based on `.env.example`. Generate different secrets of at least 32 characters each; password minimum 12 characters.
3. Run `docker compose up -d --build`. It binds ONLY to `127.0.0.1:8000`, not public internet.
4. Configure an HTTPS proxy (Caddy/Nginx) for your domain to `http://127.0.0.1:8000`. Require HTTPS only; never enable P2P_INSECURE_LOCAL on production.
5. Test admin login, export JSON backup, web writes, iPhone transfer and a deliberate version-conflict scenario before using real financial data.
6. Install updated iPhone application by building the SwiftUI project with Xcode or existing Codemagic configuration and signing credentials. Original app installations do not gain online sync automatically.

## First iPhone pairing

1. Take a **full local backup** in the old app first. Install the updated app without deleting its stored data; verify the backup.
2. On iPhone open **Ещё → Веб-админка и синхронизация**. Enter your **HTTPS** server address and P2P_DEVICE_TOKEN. Save connection.
3. To preserve existing iPhone transactions, choose **«Отправить данные iPhone на ПУСТОЙ сервер»** only when server version is 0. Alternatively, if the web server already has your wanted data, select **«Загрузить данные сервера на iPhone»** (a local pre-sync copy is saved first).
4. Subsequent local saves push automatically; inbound updates arrive while the app is open. There is a status indicator; network outages do not delete local data.

## Data protection notes

**Single iPhone / one admin recommended for this version.** The server stores complete archives, potentially including receipt image attachments and personally identifying financial data. Protect backups and server disk, consider encryption at rest, limit token access, rotate leaked credentials, and comply with your local data protection requirements. Admin writes use Origin checks and SameSite cookies. Tokens and passwords are supplied by environment and are not embedded in application source. The iPhone token is stored in Keychain, not UserDefaults.

**Conflict behaviour:** iPhone stops syncing on HTTP 409, retains its local copy, and asks for manual reconciliation. Web admin shows a warning and allows JSON export of in-browser edits. Automatic record-level conflict merging, collaborative editing, audit trails, account roles, 2FA, rate limiting and automatic push notifications are not yet implemented. Do not use as an unsupervised multi-operator accounting system without adding these controls.

**Important:** Admin changes are snapshots and transmitted over TLS; transfers are not automatically mirrored into an already published version of the iPhone app. Rebuild and install the updated app and deploy the backend first.

## API

- `POST /api/login` → secure admin session cookie
- `GET /api/snapshot` → `{version,payload,updatedAt}`
- `PUT /api/snapshot` → `{baseVersion,payload}` optimistic version update, 409 on stale version
- `GET /api/health` → lightweight health endpoint
- iPhone API calls set `Authorization: Bearer <P2P_DEVICE_TOKEN>`
