## PillPals Backend (FastAPI)

### Quickstart

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env: set FIREBASE_SERVICE_ACCOUNT_PATH to your Admin SDK JSON file.
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Firebase (Firestore sync on signup)

Signups that include `name` + `account_role` also write a document to Firestore `users/{email}` using the **Admin SDK** (same credentials as FCM).

- Set **`FIREBASE_SERVICE_ACCOUNT_PATH`** in `backend/.env` to the downloaded service account JSON path, **or** set **`FIREBASE_SERVICE_ACCOUNT_JSON`** to the raw JSON string.
- If credentials are missing, the API still creates the user locally; Firestore sync is skipped.
- Check Admin SDK + Firestore: `GET /health/firebase` (confirms project id and that **Cloud Firestore** is reachable — this is **not** Realtime Database).
- **Firestore Data** lives in the Firebase console under **Build → Firestore Database** → collection **`users`**. If you only open **Realtime Database**, it will look empty.

### Docs

- Swagger UI: `http://localhost:8000/docs`
- Health: `GET /health`

